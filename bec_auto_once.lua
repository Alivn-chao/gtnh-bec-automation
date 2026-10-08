-- One real order only. Default: read-only preview. Explicit 'run' moves fluids.
-- No AE crafting requests or nanite switching. Never retry an uncertain transfer.
local c = require("component")
local ser = require("serialization")
local computer = require("computer")
local fs = require("filesystem")
local sides = require("sides")
local mode = (...) or "preview"
local JOURNAL = "/home/bec_auto_once.journal"
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
  assert(mode == "preview" or mode == "run" or mode == "resume", "用法: preview / run / resume")
  RS = resolve("266f65b5", "redstone")
  GEN = resolve("c1ae3f7c", "gt_machine")
  assert(call(GEN, "getName") == "multi.bec.generator", "纠缠装置名称不符")
  for _, item in ipairs({{RS,"setOutput"},{RS,"getOutput"},{GEN,"setWorkAllowed"},
    {GEN,"isWorkAllowed"},{GEN,"isMachineActive"},{MAIN,"getFluidsInNetwork"},
    {MAIN,"setFluidInterfaceConfiguration"},{MAIN,"getFluidInterfaceConfiguration"},
    {SUB,"getFluidsInNetwork"},{TRANS,"transferFluid"}}) do method(item[1],item[2]) end
  assert(call(NODE,"getMinParallel") == 1 and call(NODE,"getMaxParallel") == 1, "并行设置须为 1 / 1")
  print("远端红石: " .. RS .. "；纠缠装置: " .. GEN)
  print("节点: " .. call(NODE,"getState") .. "；向上输出: " .. call(RS,"getOutput",sides.top))
  print("纠缠装置允许工作: " .. tostring(call(GEN,"isWorkAllowed")))
  print("凝聚物库存: " .. ser.serialize(field(),false))
  if mode == "preview" then
    print("子网原液: " .. ser.serialize(network(SUB),false))
    if call(NODE,"getState") == "paused-immediate" then
      local _, remaining = current(); plan(remaining)
    end
    print("预览结束：没有开关、搬液、配置或写日志。")
    return
  end
  local waitingStates = {idle=true, ["paused-immediate"]=true, ["assembler-offline"]=true,
    unpowered=true, ["nanite-tier-too-low"]=true}
  local initialState = call(NODE,"getState")
  assert(waitingStates[initialState], "节点状态不适合启动: " .. tostring(initialState))
  emptyConfig(); tanks(4,nil); tanks(5,nil)
  if mode == "resume" then
    assert(fs.exists(JOURNAL), "没有可恢复的日志")
    local f = assert(io.open(JOURNAL,"r")); local contents = f:read("*a"); f:close()
    local old = ser.unserialize(contents)
    assert(type(old) == "table" and old.version == 1 and old.stage == "starting"
      and type(old.transfers) == "table" and next(old.transfers) == nil
      and old.pending == nil and old.configOwned == nil and old.plan == nil
      and old.required == nil and old.remaining == nil, "仅能恢复未进入备料的 starting 日志")
    local index = 1
    while fs.exists(JOURNAL .. ".before-resume-" .. index) do index = index + 1 end
    local backup = JOURNAL .. ".before-resume-" .. index
    assert(fs.rename(JOURNAL,backup), "旧日志归档失败")
    local check = assert(io.open(backup,"r")); local saved = check:read("*a"); check:close()
    assert(saved == contents and not fs.exists(JOURNAL), "旧日志归档回读失败")
    print("接单前旧日志已保留: " .. backup)
  else
    assert(not fs.exists(JOURNAL), "已有运行日志；先核对旧运行结果，不自动重跑或删日志")
  end
  record = {version=1, stage="starting", transfers={}}
  save("starting")
  armed = true; pause(15); generator(false)
  waitUntil(10, function() return call(GEN,"isMachineActive") == false end)
  print("已暂停并关闭纠缠装置，等待一单；只下单一次，本程序 300 秒内等待接单。")
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
  local moves, previous, expected = plan(record.remaining)
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
    for name, need in pairs(record.remaining) do if (stock[name] or 0) < need then return false end end
    return true
  end, unchanged)
  unchanged(); generator(false)
  save("releasing"); pause(0)
  local releasedAt = computer.uptime()
  print("凝聚物齐备，已放行。等待这单结束，不要追加订单。")
  waitUntil(600, function()
    local state = call(NODE,"getState")
    return state == "idle", state
  end, function(state)
    assert(state == "crafting" or (state == "paused-immediate" and computer.uptime()-releasedAt < 3),
      "运行异常，实际状态: " .. tostring(state))
    field()
  end)
  pause(15)
  assert(call(NODE,"getParallelRecipesInProgress") == 0, "完成状态并行不为零")
  local consumed = call(NODE,"getConsumedCondensate")
  assert(type(consumed) == "table", "完成消耗记录不可读")
  for name, need in pairs(record.required) do
    assert((consumed[name] or 0) == need, "可能取消或失败，消耗不完整")
  end
  save("done")
  print("单次运行结束，已恢复暂停输出 15，纠缠装置已关闭。请确认主网成品到账。")
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
