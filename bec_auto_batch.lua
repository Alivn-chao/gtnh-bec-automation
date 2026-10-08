-- Same-recipe batch, sequential parallel 1. Default preview is read-only.
-- No AE crafting requests or nanite switching. Never retry an uncertain transfer.
local c = require("component")
local ser = require("serialization")
local computer = require("computer")
local fs = require("filesystem")
local sides = require("sides")
local mode, requestedQuantity = ...
mode = mode or "preview"
local quantity = tonumber(requestedQuantity or 15)
local JOURNAL = "/home/bec_auto_batch.journal"
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50"
local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad"
local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0"
local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0"
local RS, GEN, armed, record
local mapping = {
  entangled_chromaticglass = "molten.chromaticglass",
  entangled_transcendentmetal = "molten.transcendentmetal"
}
local function call(a, m, ...) return c.invoke(a, m, ...) end
local function method(a, m)
  assert(c.methods(a)[m] ~= nil, "组件缺少方法: " .. m)
end
local function resolve(prefix, kind)
  local address, count = nil, 0
  for a, t in c.list() do
    if a:sub(1, #prefix) == prefix and t == kind then
      address, count = a, count + 1
    end
  end
  assert(count == 1, "目标组件缺失或不唯一: " .. prefix)
  return address
end
local function integer(v)
  assert(type(v) == "number" and v >= 0 and v == math.floor(v), "库存/需求数量无效")
  return v
end
local function same(a, b)
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end
local function network(a)
  local rows, result = call(a, "getFluidsInNetwork"), {}
  assert(type(rows) == "table", "网络库存不可读")
  for _, f in pairs(rows) do
    assert(type(f) == "table", "流体条目无效")
    local n = integer(f.amount or f.size or 0)
    if n > 0 then
      assert(type(f.name) == "string", "流体名称缺失")
      result[f.name] = (result[f.name] or 0) + n
    end
  end
  return result
end
local function outputCount()
  local rows = call(MAIN,"getItemsInNetwork",{name="gregtech:gt.metaitem.03",damage=32307})
  assert(type(rows) == "table", "主网成品库存不可读")
  local count = 0
  for _, item in pairs(rows) do
    assert(type(item) == "table", "成品库存条目无效")
    if item.name == "gregtech:gt.metaitem.03" and tonumber(item.damage) == 32307 then
      count = count + integer(item.size or item.amount or 0)
    end
  end
  return count
end
local function batchNeeds(required, remaining)
  assert(required.entangled_chromaticglass == 288 and required.entangled_transcendentmetal == 288,
    "批量版仅支持两种各 288 的原始屏蔽层；停止")
  local count = 0
  for _ in pairs(required) do count = count + 1 end
  assert(count == 2 and same(required,remaining), "批量首份已经消耗或配方不符；停止")
  local needs = {}
  for name, amount in pairs(required) do needs[name] = amount * quantity end
  return needs
end
local function archiveJournal(suffix, contents)
  local index = 1
  while fs.exists(JOURNAL .. suffix .. index) do index = index + 1 end
  local backup = JOURNAL .. suffix .. index
  assert(fs.rename(JOURNAL,backup), "旧批量日志归档失败")
  local f = assert(io.open(backup,"r")); local actual = f:read("*a"); f:close()
  assert(actual == contents and not fs.exists(JOURNAL), "旧批量日志归档回读失败")
  print("旧批量日志已保留: " .. backup)
end
local function field()
  assert(call(STORAGE, "isWorkAllowed") == true, "约束场必须保持开启")
  local v = call(STORAGE, "getStoredCondensate")
  assert(type(v) == "table", "凝聚物库存不可读")
  for _, n in pairs(v) do integer(n) end
  return v
end
local function writeVerified(path, contents)
  local f = assert(io.open(path, "w"))
  local ok, err = f:write(contents)
  local flushed, flushErr = f:flush()
  f:close()
  assert(ok and flushed, tostring(err or flushErr or "日志写入失败"))
  local r = assert(io.open(path, "r"))
  local actual = r:read("*a"); r:close()
  assert(actual == contents and type(ser.unserialize(actual)) == "table", "日志回读失败")
end
local function save(stage)
  record.stage = stage
  if fs.exists(JOURNAL) then
    local f = assert(io.open(JOURNAL, "r"))
    local old = f:read("*a"); f:close()
    writeVerified(JOURNAL .. ".previous", old)
  end
  writeVerified(JOURNAL, ser.serialize(record, false))
end
local function pause(value)
  call(RS, "setOutput", sides.top, value)
  assert(call(RS, "getOutput", sides.top) == value, "红石输出回读不符")
end
local function generator(enabled)
  call(GEN, "setWorkAllowed", enabled)
  assert(call(GEN, "isWorkAllowed") == enabled, "纠缠装置启停回读不符")
end
local function tanks(side, name)
  local count, amount = integer(call(TRANS, "getTankCount", side)), 0
  assert(count > 0, "接口没有流体槽")
  for i = 1, count do
    local f = call(TRANS, "getFluidInTank", side, i)
    assert(type(f) == "table", "接口缓存不可读")
    if type(f[1]) == "table" then f = f[i] or f[1] end
    local n = integer(f.amount or 0)
    if n > 0 then
      assert(name and f.name == name, "接口有未处理流体缓存")
      amount = amount + n
    end
  end
  return amount
end
local function emptyConfig()
  for slot = 0, 5 do
    assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置")
  end
end
local function current()
  assert(call(NODE, "getState") == "paused-immediate", "订单未处于立即暂停状态")
  assert(call(NODE, "getParallelRecipesInProgress") == 1, "仅支持单并行订单")
  local required, consumed = call(NODE, "getRequiredCondensate"), call(NODE, "getConsumedCondensate")
  assert(type(required) == "table" and type(consumed) == "table", "订单需求不可读")
  local remaining, total = {}, 0
  for name, amount in pairs(required) do
    assert(mapping[name], "不支持的凝聚物: " .. tostring(name))
    amount = integer(amount)
    local used = integer(consumed[name] or 0)
    assert(used <= amount, "已消耗数量超过需求")
    remaining[name] = amount - used; total = total + amount
  end
  assert(total > 0, "订单没有有效需求")
  for name, amount in pairs(consumed) do
    assert(integer(amount) == 0 or required[name], "消耗记录与当前订单不符")
  end
  return required, remaining
end
local function unchanged()
  local req, remaining = current()
  assert(same(req, record.required) and same(remaining, record.remaining), "暂停订单发生变化，停止")
end
local function plan(remaining)
  local stock, sub, main = field(), network(SUB), network(MAIN)
  local moves, expected, allowed = {}, {}, {}
  for name, need in pairs(remaining) do
    local raw = mapping[name]
    allowed[raw] = true
    local required = math.ceil(math.max(0, need - (stock[name] or 0)) / 144) * 144
    local existing = sub[raw] or 0
    assert(existing <= required and existing % 144 == 0, "子网原液超额或非整批: " .. raw)
    local missing = required - existing
    assert((main[raw] or 0) >= missing, "主网原液不足: " .. raw .. "；本版不自动下单")
    if required > 0 then expected[raw] = required end
    moves[#moves + 1] = {raw=raw, amount=missing}
    print(raw .. " 本次补入 " .. missing .. " mB")
  end
  for raw in pairs(sub) do assert(allowed[raw], "子网有无关原液: " .. raw) end
  for name, amount in pairs(stock) do
    assert(amount == 0 or remaining[name], "约束场有无关凝聚物: " .. name)
  end
  table.sort(moves, function(a,b) return a.raw < b.raw end)
  return moves, sub, expected
end
local function waitUntil(seconds, condition, guard)
  local deadline = computer.uptime() + seconds
  while true do
    local ready, snapshot = condition()
    if ready then return end
    if guard then guard(snapshot) end
    assert(computer.uptime() < deadline, "等待超时，停止")
    os.sleep(0.25)
  end
end
local function main()
  assert(mode == "preview" or mode == "run" or mode == "resume", "用法: preview / run / resume [份数]")
  assert(quantity and quantity >= 1 and quantity <= 16 and quantity == math.floor(quantity), "份数须为 1..16 整数")
  RS = resolve("266f65b5", "redstone")
  GEN = resolve("c1ae3f7c", "gt_machine")
  assert(call(GEN, "getName") == "multi.bec.generator", "纠缠装置名称不符")
  for _, item in ipairs({{RS,"setOutput"},{RS,"getOutput"},{GEN,"setWorkAllowed"},
    {GEN,"isWorkAllowed"},{GEN,"isMachineActive"},{MAIN,"getFluidsInNetwork"},
    {MAIN,"setFluidInterfaceConfiguration"},{MAIN,"getFluidInterfaceConfiguration"},
    {SUB,"getFluidsInNetwork"},{TRANS,"transferFluid"},{MAIN,"getItemsInNetwork"}}) do method(item[1],item[2]) end
  assert(call(NODE,"getMinParallel") == 1 and call(NODE,"getMaxParallel") == 1, "并行设置须为 1 / 1")
  print("远端红石: " .. RS .. "；纠缠装置: " .. GEN)
  print("节点: " .. call(NODE,"getState") .. "；向上输出: " .. call(RS,"getOutput",sides.top))
  print("纠缠装置允许工作: " .. tostring(call(GEN,"isWorkAllowed")))
  print("凝聚物库存: " .. ser.serialize(field(),false))
  print("本批原始屏蔽层份数: " .. quantity .. "；主网已有成品: " .. outputCount())
  if mode == "preview" then
    print("子网原液: " .. ser.serialize(network(SUB),false))
    if call(NODE,"getState") == "paused-immediate" then
      local required, remaining = current(); plan(batchNeeds(required,remaining))
    end
    print("预览结束：没有开关、搬液、配置或写日志。")
    return
  end
  local waitingStates = {idle=true, ["paused-immediate"]=true, ["assembler-offline"]=true,
    unpowered=true, ["nanite-tier-too-low"]=true}
  local initialState = call(NODE,"getState")
  assert(waitingStates[initialState], "节点状态不适合启动: " .. tostring(initialState))
  emptyConfig(); tanks(4,nil); tanks(5,nil)
  local baseline
  if fs.exists(JOURNAL) then
    local f = assert(io.open(JOURNAL,"r")); local contents = f:read("*a"); f:close()
    local old = ser.unserialize(contents)
    assert(type(old) == "table" and old.version == 1 and old.kind == "shielding-batch", "批量日志无效")
    if mode == "resume" then
      assert(old.stage == "starting" and old.quantity == quantity
        and type(old.transfers) == "table" and next(old.transfers) == nil
        and old.pending == nil and old.configOwned == false and old.plan == nil
        and old.required == nil and old.remaining == nil, "只能恢复相同份数且尚未备料的日志")
      baseline = integer(old.outputBaseline)
      assert(outputCount() == baseline, "接单前成品库存已变，停止恢复")
      archiveJournal(".before-resume-",contents)
    else
      assert(old.stage == "done" and old.pending == nil and old.configOwned == false
        and type(old.quantity) == "number" and old.quantity >= 1
        and old.finalOutputCount == old.outputBaseline + old.quantity
        and initialState == "idle", "旧批量未完整结束，保留日志，不重试")
      archiveJournal(".done-",contents)
    end
  else
    assert(mode ~= "resume", "没有可恢复的批量日志")
  end
  baseline = baseline or outputCount()
  record = {version=1, kind="shielding-batch", stage="starting", transfers={},
    quantity=quantity, outputBaseline=baseline, configOwned=false}
  save("starting")
  armed = true; pause(15); generator(false)
  waitUntil(10, function() return call(GEN,"isMachineActive") == false end)
  print("已暂停并关闭纠缠装置。现在在 AE 下原始屏蔽层，合计 " .. quantity .. " 个，可分多个任务；等待首单上限 300 秒。")
  local lastWaitingState
  waitUntil(300, function()
    local state = call(NODE,"getState")
    return state == "paused-immediate", state
  end, function(state)
    assert(waitingStates[state], "节点未按预期暂停，实际状态: " .. tostring(state))
    assert(call(RS,"getOutput",sides.top) == 15, "等待订单期间红石输出改变")
    if state ~= lastWaitingState then
      print("节点等待状态: " .. state .. "（观测阵列需启用并正常供电）")
      lastWaitingState = state
    end
    field()
  end)
  record.required, record.remaining = current()
  record.batchRemaining = batchNeeds(record.required,record.remaining)
  assert(outputCount() == record.outputBaseline, "备料前成品库存变动，停止")
  local moves, previous, expected = plan(record.batchRemaining)
  record.plan = moves; save("planned")
  for _, move in ipairs(moves) do
    if move.amount > 0 then
      unchanged(); assert(same(network(SUB),previous), "子网库存发生变化")
      record.configOwned = true; save("configuring")
      assert(call(MAIN,"setFluidInterfaceConfiguration",0,
        {name=move.raw,amount=move.amount,size=move.amount}) == true, "供液配置失败")
      waitUntil(30, function() return tanks(4,move.raw) >= move.amount end, unchanged)
      unchanged(); assert(same(network(SUB),previous), "搬液前子网库存变化")
      record.pending = move; save("transfer-pending") -- Durable intent before the one transfer call.
      local ok, amount = call(TRANS,"transferFluid",4,5,move.amount)
      record.transfers[#record.transfers+1] = {raw=move.raw,ok=ok,amount=amount}
      save("transfer-returned")
      assert(ok == true and amount == move.amount, "搬运未完整确认；禁止盲目重试")
      assert(call(MAIN,"setFluidInterfaceConfiguration",0) == true, "清除供液配置失败")
      record.configOwned = false; record.pending = nil; save("transfer-confirmed")
      previous[move.raw] = (previous[move.raw] or 0) + move.amount
      waitUntil(10, function() return same(network(SUB),previous) end, unchanged)
      waitUntil(20, function() return tanks(4,move.raw) == 0 end, unchanged)
    end
  end
  assert(same(network(SUB),expected), "最终子网原液不符")
  for i=1,20 do unchanged(); assert(same(network(SUB),expected), "子网原液不稳定"); os.sleep(0.25) end
  save("converting"); generator(true)
  print("精确补液完成，等待纠缠装置转换。")
  waitUntil(180, function()
    local stock = field()
    for name, need in pairs(record.batchRemaining) do if (stock[name] or 0) < need then return false end end
    return true
  end, unchanged)
  unchanged(); generator(false)
  record.releaseStock = field(); save("releasing"); pause(0)
  local releasedAt = computer.uptime()
  print("合计 " .. quantity .. " 份凝聚物齐备，已连续放行；任务总量须一致，期间不要取走成品。")
  local lastProgress = -1
  waitUntil(600*quantity, function()
    local count = outputCount() - record.outputBaseline
    assert(count >= 0 and count <= quantity, "成品库存发生意外变化，停止")
    local state = call(NODE,"getState")
    if count ~= lastProgress then
      print("主网成品增加: " .. count .. " / " .. quantity)
      lastProgress = count
    end
    return count == quantity and state == "idle", state
  end, function(state)
    assert(state == "crafting" or state == "idle"
      or (state == "paused-immediate" and computer.uptime()-releasedAt < 3),
      "批量运行异常，实际状态: " .. tostring(state))
    field()
    local req = call(NODE,"getRequiredCondensate")
    assert(req == nil or (type(req) == "table" and same(req,record.required)), "混入其他配方，停止")
  end)
  pause(15)
  assert(call(NODE,"getState") == "idle" and call(NODE,"getParallelRecipesInProgress") == 0,
    "本批结束时仍有订单，保持暂停")
  local stock = field()
  for name, total in pairs(record.batchRemaining) do
    assert((record.releaseStock[name] or 0)-(stock[name] or 0) == total,
      "本批凝聚物消耗不符，保留日志核对")
  end
  record.finalOutputCount = outputCount()
  assert(record.finalOutputCount == record.outputBaseline + quantity, "完成时成品数量改变")
  save("done")
  print("批量运行完成：主网原始屏蔽层增加 " .. quantity .. "，已恢复暂停 15，纠缠装置关闭。")

end
local ok, err = xpcall(main, debug.traceback)
if not ok then
  if armed then
    local paused = pcall(pause,15)
    local stopped = pcall(generator,false)
    local cleaned = true
    if record and record.configOwned then
      local success, result = pcall(call,MAIN,"setFluidInterfaceConfiguration",0)
      cleaned = success and result == true
    end
    print("恢复暂停: " .. tostring(paused) .. "；关闭纠缠装置: " .. tostring(stopped) .. "；清供液配置: " .. tostring(cleaned))
    if not paused then print("请手动提供控制仓暂停信号。") end
  end
  print("程序停止: " .. tostring(err))
  print("保留现场与日志；不要删除日志盲目重跑。约束场保持开启。")
end
