-- Continuous known-recipe service, no user-specified order count. Preview is read-only.
-- Request missing main-network fluids. Never retry an uncertain request/transfer.
local c = require("component")
local ser = require("serialization")
local computer = require("computer")
local fs = require("filesystem")
local sides = require("sides")
local event = require("event")
local mode = (...) or "preview"
local JOURNAL = "/home/bec_auto.journal"
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50"
local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad"
local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0"
local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0"
local RS, GEN, armed, record
local stopping=false
local mapping = {
  entangled_infinity = "molten.infinity",
  entangled_chromaticglass = "molten.chromaticglass",
  entangled_transcendentmetal = "molten.transcendentmetal",
  entangled_dimshiftedsuperfluid = "dimensionallyshiftedsuperfluid",
  entangled_neutronium="molten.neutronium",entangled_cosmicneutronium="molten.cosmicneutronium",
  entangled_bedrockium="molten.bedrockium",entangled_celestialtungsten="molten.celestialtungsten",
  entangled_hypogen="molten.hypogen",entangled_phononmedium="phononmedium",
  entangled_quarkgluonplasma="quarkgluonplasma",entangled_spacetime="molten.spacetime",
  entangled_time="molten.temporalfluid",entangled_space="molten.spatialfluid",
  entangled_cosmicsolder="boundlesscosmicsolder",
  entangled_mhdcsm="molten.magnetohydrodynamicallyconstrainedstarmatter",
  entangled_magmatter="molten.magmatter",entangled_universium="molten.universium",
  entangled_eternity="molten.eternity"
}
local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000,
 entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000}
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
local matchedOutputs, perRecipe
local function checkRecipe(required,parallel)
  parallel=parallel or integer(call(NODE,"getParallelRecipesInProgress"))
  assert(parallel>0 and type(required)=="table","当前配方并行/需求不可读")
  local normalized={}
  for name,n in pairs(required) do
    assert(mapping[name] and integer(n)>0 and n%parallel==0,"配方需求无法按并行拆分: "..tostring(name))
    normalized[name]=n/parallel
  end
  local matches={}
  if fs.exists("/home/bec/recipes") then
    for file in fs.list("/home/bec/recipes") do
      if file:match("%.dat$") then
        local f=assert(io.open("/home/bec/recipes/"..file,"r"));local r=ser.unserialize(f:read("*a"));f:close()
        assert(type(r)=="table","登记配方损坏: "..file)
        if r.state=="converted" then
          local needs={}
          for _,fluid in ipairs(r.condensates or {}) do needs[fluid.name]=(needs[fluid.name] or 0)+integer(fluid.amount or fluid.size) end
          if same(needs,normalized) then
            assert(type(r.outputs)=="table" and #r.outputs==1,"登记产物无效: "..file)
            matches[#matches+1]=r.outputs[1]
          end
        end
      end
    end
  end
  if #matches>0 then
    local provided=call(NODE,"getProvidedTier")
    if c.methods(NODE).getRequiredTier~=nil then
      local needed=call(NODE,"getRequiredTier")
      local tier=type(needed)=="table" and needed.tier or needed
      assert(type(tier)=="number" and type(provided)=="table" and provided.tier>=tier,"当前蜂群等级不足")
    end
    assert(integer(call(NODE,"getAvailableNanites"))>0,"当前蜂群为空")
    matchedOutputs,perRecipe=matches,normalized
    return parallel
  end
  local amount=type(required)=="table" and required.entangled_chromaticglass
  assert(type(amount)=="number" and amount>0 and amount%288==0
    and required.entangled_transcendentmetal==amount, "未验证的配方需求，保持暂停")
  local recipes=amount/288
  assert(parallel==nil or parallel==recipes,"实际并行与凝聚物需求不符")
  local count=0; for _ in pairs(required) do count=count+1 end
  assert(count==2,"未验证的凝聚物需求，保持暂停")
  local tier=call(NODE,"getProvidedTier")
  assert(type(tier)=="table" and tier.tier==4 and integer(call(NODE,"getAvailableNanites"))>=64,
    "须使用 tier 4 蜂群且数量至少64，可以增加同级蜂群")
  matchedOutputs={{name="gregtech:gt.metaitem.03",damage=32307,size=1}};perRecipe=normalized
  return recipes
end
local function tick(seconds)
  local _,_,character=event.pull(seconds,"key_down")
  if character==113 or character==81 then stopping=true end
end
local function archiveJournal(contents,suffix)
  suffix=suffix or ".stopped-"
  local index=1
  while fs.exists(JOURNAL..suffix..index) do index=index+1 end
  local backup=JOURNAL..suffix..index
  assert(fs.rename(JOURNAL,backup),"旧常驻日志归档失败")
  local f=assert(io.open(backup,"r"));local actual=f:read("*a");f:close()
  assert(actual==contents and not fs.exists(JOURNAL),"旧常驻日志归档验证失败")
end
local function field()
  assert(call(STORAGE, "isWorkAllowed") == true, "约束场必须保持开启")
  local v = call(STORAGE, "getStoredCondensate")
  assert(type(v) == "table", "凝聚物库存不可读")
  for _, n in pairs(v) do integer(n) end
  return v
end
local function checkContaminants(stock,required)
  local extras={}
  for name,n in pairs(stock) do
    if n>0 and (required[name] or 0)==0 then extras[#extras+1]=name end
  end
  table.sort(extras)
  assert(#extras<=3,"BEC网络有 "..#extras.." 种多余凝聚物，须先设置凝聚物过滤，保持暂停: "..table.concat(extras,", "))
  if #extras>0 then print("BEC网络多余凝聚物 "..#extras.." 种，可能减速；需过滤当前配方以外类型。") end
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
local function current(recovering)
  local state=call(NODE,"getState")
  local unavailable=state=="assembler-offline" or state=="unpowered" or state=="nanite-tier-too-low"
  assert(state=="paused-immediate" or (recovering and unavailable
    and call(RS,"getOutput",sides.top)==15),"订单未处于立即暂停状态")
  local parallel=integer(call(NODE, "getParallelRecipesInProgress"))
  assert(parallel>=1,"暂停节点没有正在处理的配方")
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
  checkRecipe(required,parallel)
  return required, remaining
end
local function queuedRecipes()
  local cpus=call(MAIN,"getCpus")
  assert(type(cpus)=="table","主网 CPU 清单不可读")
  local total=0
  for _,row in pairs(cpus) do
    if row.busy==true then
      assert(row.cpu~=nil,"主网 CPU 不提供任务对象，无法读取整批数量")
      -- ACTIVE = outputs already dispatched but not returned; PENDING =
      -- pattern outputs not yet dispatched. Add both, never storage items.
      for _,getter in ipairs({"activeItems","pendingItems"}) do
        local items=row.cpu[getter]()
        assert(type(items)=="table","主网剩余任务不可读: "..getter)
        for _,item in pairs(items) do
          for _,out in ipairs(matchedOutputs or {{name="gregtech:gt.metaitem.03",damage=32307,size=1}}) do
          if item.name==out.name and tonumber(item.damage or 0)==tonumber(out.damage or 0) then
            assert(not out.hasTag and not item.hasTag,"带NBT产物不能用于整批计数")
            total=total+integer(item.size or item.amount or 0)/math.max(1,integer(out.size or out.amount or 1))
            break
          end
          end
        end
      end
    end
  end
  return math.ceil(total)
end
local function batchTarget(required,remaining)
  local parallel=checkRecipe(required)
  local count=math.max(parallel,queuedRecipes())
  local target={}
  for name,amount in pairs(required) do
    target[name]=remaining[name]+perRecipe[name]*(count-parallel)
    assert(target[name]<=2147483647,"整批需求过大")
  end
  return target,count
end
local function unchanged()
  local req, remaining = current()
  assert(same(req, record.required) and same(remaining, record.remaining), "暂停订单发生变化，停止")
end
local function plan(remaining,quiet)
  local stock, sub, main = field(), network(SUB), network(MAIN)
  local moves, expected, allowed, shortages, deficits = {}, {}, {}, {}, {}
  for name, need in pairs(remaining) do
    local raw = mapping[name]
    allowed[raw] = true
    local unit=units[name] or 144
    local required = math.ceil(math.max(0, need - (stock[name] or 0)) / unit) * unit
    local existing = sub[raw] or 0
    assert(existing <= required and existing % unit == 0, "子网原液超额或非整批: " .. raw)
    local missing = required - existing
    if (main[raw] or 0)<missing then
      deficits[#deficits+1]={raw=raw,amount=missing-(main[raw] or 0),needed=missing}
      shortages[#shortages+1]=raw..": 本次需补 "..missing.." mB，主网有 "..(main[raw] or 0)
        .."，还缺 "..(missing-(main[raw] or 0)).." mB"
    end
    if required > 0 then expected[raw] = required end
    -- Supply interface caches are finite; move an entire batch in confirmed
    -- chunks while the generator stays off, not one product at a time.
    local left=missing
    while left>0 do
      local chunk=math.min(left,math.floor(16000/unit)*unit)
      moves[#moves+1]={raw=raw,amount=chunk};left=left-chunk
    end
    if not quiet then print(raw .. " 本次补入 " .. missing .. " mB") end
  end
  for raw in pairs(sub) do assert(allowed[raw], "子网有无关原液: " .. raw) end
  for name, amount in pairs(stock) do
    assert(amount == 0 or mapping[name], "约束场有未知凝聚物: " .. name)
  end
  table.sort(moves, function(a,b) return a.raw < b.raw end)
  if #shortages>0 then
    table.sort(shortages)
    local message=table.concat(shortages,"；")
    if not quiet then print("缺料: "..message.."；运行时向主网 AE 申请缺口") end
    table.sort(deficits,function(a,b) return a.raw<b.raw end)
    return nil,message,deficits
  end
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
local function prepareStreaming(target)
  local stock,previous=field(),network(SUB)
  local expected,raws={},{}
  for name,need in pairs(target) do
    local raw=mapping[name]
    local batch=units[name] or 144
    local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch
    local existing=previous[raw] or 0
    assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw)
    if amount>0 then expected[raw]=amount end
    raws[#raws+1]={raw=raw,amount=amount,batch=batch}
  end
  for raw in pairs(previous) do
    local allowed=false
    for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end
    assert(allowed,"子网有无关原液: "..raw)
  end
  for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end
  table.sort(raws,function(a,b) return a.raw<b.raw end)
  record.plan=raws;record.expected=expected;save("stream-planned")
  for _,item in ipairs(raws) do
    local raw,need,batch=item.raw,item.amount,item.batch
    local chunk=math.floor(16000/batch)*batch
    if (previous[raw] or 0)<need then
      unchanged();emptyConfig();tanks(4,nil)
      record.configOwned=true;save("stream-configuring")
      assert(call(MAIN,"setFluidInterfaceConfiguration",0,
        {name=raw,amount=math.min(need-(previous[raw] or 0),chunk),
         size=math.min(need-(previous[raw] or 0),chunk)})==true,"持续供液配置失败")
      print(raw.." 整批目标 "..need.." mB；到账即搬入子网。")
      local job,status,craft,jobDeadline,doneAt
      local attempts=0
      local inletOpen=true
      local deadline=computer.uptime()+1800
      while not stopping do
        unchanged();assert(same(field(),stock),"备料时约束场库存变化")
        assert(same(network(SUB),previous),"备料时子网库存变化")
        local remaining=need-(previous[raw] or 0)
        local buffered=tanks(4,raw)
        local amount=math.floor(math.min(remaining,buffered,chunk)/batch)*batch
        if amount>0 then
          record.pending={raw=raw,amount=amount};save("transfer-pending")
          local ok,moved=call(TRANS,"transferFluid",4,5,amount)
          record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount}
          save("transfer-returned")
          assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试")
          previous[raw]=(previous[raw] or 0)+amount
          waitUntil(10,function() return same(network(SUB),previous) end,unchanged)
          record.pending=nil;record.secured=previous;save("stream-transfer-confirmed")
          print(raw.." 已入子网 "..previous[raw].." / "..need.." mB")
          deadline=computer.uptime()+1800
        end
        remaining=need-(previous[raw] or 0)
        if remaining==0 and inletOpen then
          assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败")
          record.configOwned=false;inletOpen=false;save("stream-inlet-cleared")
          waitUntil(20,function() return tanks(4,raw)==0 end,unchanged)
        end
        if status and job.state=="submitted" then
          local canceled,why=status.isCanceled()
          assert(canceled==false,"主网原液申请失败/取消: "..tostring(why))
          local done=status.isDone();assert(type(done)=="boolean","AE 状态不可读")
          if done then
            job.state="done";job.securedAfter=previous[raw] or 0
            doneAt=computer.uptime();save("stream-craft-done")
          else assert(computer.uptime()<jobDeadline,"主网原液合成超时，保留申请记录") end
        end
        if remaining==0 and (not job or job.state=="done") then break end
        -- Keep the inlet configured while waiting for CPU, crafting or delivery.
        -- There is never more than one unconfirmed job for this fluid.
        if remaining>0 and (not job or job.state=="done") then
          local missing=math.max(0,remaining-tanks(4,raw)-(network(MAIN)[raw] or 0))
          if missing>0 and (not doneAt or computer.uptime()-doneAt>=3) then
            if job then
              assert((previous[raw] or 0)>job.securedBefore,
                "本次原液合成已结束但子网没有收获，暂停核对竞争设备")
            end
            local cpus=call(MAIN,"getCpus")
            assert(type(cpus)=="table","主网 CPU 状态不可读")
            local available=false
            for _,cpu in pairs(cpus) do if cpu.busy==false then available=true end end
            if available then
              if not craft then
                local rows=call(MAIN,"getCraftables",{name=raw})
                assert(type(rows)=="table","原液配方不可读")
                local count=0;for _,v in pairs(rows) do craft=v;count=count+1 end
                assert(count==1,"原液配方缺失或不唯一: "..raw)
                local f=craft.getStack()
                assert(type(f)=="table" and f.name==raw and f.isCraftable==true
                  and type(f.amount)=="number" and f.amount==f.size and f.hasTag==false,
                  "未验证的流体合成对象")
              end
              attempts=attempts+1;assert(attempts<=3,"原液仍被争抢，暂停保留已收获库存")
              -- Request only the outstanding amount, subtracting protected inlet
              -- cache and subnet inventory, even while output is still arriving.
              missing=math.max(0,need-(previous[raw] or 0)-tanks(4,raw)-(network(MAIN)[raw] or 0))
              if missing>0 then
                job={raw=raw,amount=missing,unit="mB",state="pending",securedBefore=previous[raw] or 0}
                record.requests[#record.requests+1]=job;save("craft-request-pending")
                local reason;status,reason=craft.request(missing)
                assert(status~=nil,"AE 申请未确认: "..tostring(reason))
                job.state="submitted";jobDeadline=computer.uptime()+1800;doneAt=nil
                save("stream-crafting")
                print("主网 AE 申请 "..raw.." "..missing.." mB；合成中持续收料。")
              end
            end
          end
        end
        assert(computer.uptime()<deadline,"持续收料超时，保留子网已搬入原液")
        tick(0.1)
      end
      if inletOpen then
        assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败")
        record.configOwned=false;save("stream-inlet-cleared")
      end
      waitUntil(20,function() return tanks(4,raw)==0 end,unchanged)
      if stopping then return expected end
    end
  end
  assert(same(network(SUB),expected),"整批子网原液不符")
  record.plan=nil;save("stream-prepared")
  return expected
end
local function serve()
  local waiting={idle=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
  local round=0
  local nextCache=0
  local function idleCache(state)
    if computer.uptime()<nextCache then return end
    nextCache=computer.uptime()+2
    local pending=io.open("/home/bec_cache.journal","r")
    local old
    if pending then old=ser.unserialize(pending:read("*a"));pending:close() end
    local incomplete=type(old)=="table" and old.background and old.incomplete
    if state~="idle" and not incomplete then return end
    local input=io.open("/home/bec_cache.config","r")
    local settings
    if input then settings=ser.unserialize(input:read("*a"));input:close() end
    if not settings and not incomplete then
      if not fs.exists("/home/bec/recipes") then return end
      settings={version=1,target=144000}
    end
    assert(not settings or (type(settings)=="table" and settings.version==1),"缓存配置无效")
    local target=incomplete and old.fixedStock or settings.target
    assert(type(target)=="number" and target>=1 and target==math.floor(target),"缓存配置无效")
    local worker,reason=loadfile("/home/bec_cache.lua","t",_ENV)
    assert(worker,"缺少后台缓存脚本："..tostring(reason))
    waitUntil(190,function() return call(GEN,"isMachineActive")==false end)
    save("cache-working")
    local ok,err=worker("background-stock",target)
    assert(ok,"后台缓存停止："..tostring(err))
    record.lastState=nil;save("waiting")
    tick(0.1)
  end
  while not stopping do
    pause(15); generator(false)
    local state=call(NODE,"getState")
    idleCache(state)
    if stopping then break end
    state=call(NODE,"getState")
    if waiting[state] then
      if state~=record.lastState then
        print("等待订单/机器就绪: "..state.."；任意数量同配方订单均可，按 Q 停止。")
        record.lastState=state;save("waiting")
      end
      field();tick(0.1)
    else
      waitUntil(10,function()
        local v=call(NODE,"getState")
        return v=="paused-immediate",v
      end,function(v)
        assert(v=="crafting" or waiting[v],"无法暂停，实际状态: "..tostring(v))
        field()
      end)
      record.required,record.remaining=current()
      -- Briefly let AE finish dispatching inputs into the blocked node.
      -- Read the paused batch twice to avoid a transient ACTIVE/PENDING move.
      local target,count=batchTarget(record.required,record.remaining)
      local stable=false
      for i=1,20 do
        tick(0.25);unchanged()
        local nextTarget,nextCount=batchTarget(record.required,record.remaining)
        if same(target,nextTarget) then stable=true;break end
        target,count=nextTarget,nextCount
      end
      assert(stable,"主网任务清单持续变化，保持暂停")
      if stopping then break end
      record.batchCount=count
      print("主网剩余配方 "..count.." 份；当前实际并行 "..checkRecipe(record.required)
        .."；一次准备整批所需流体。")
      round=round+1;record.round=round;record.transfers={};record.target=target;record.plan=nil;record.topups={}
      waitUntil(10,function() return call(GEN,"isMachineActive")==false end)
      emptyConfig();tanks(4,nil);tanks(5,nil)
      local expected=prepareStreaming(target)
      if stopping then break end
      for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end
      save("converting");generator(true)
      local conversionLimit=180
      for name,need in pairs(target) do conversionLimit=conversionLimit+math.ceil(need/(units[name] or 144))*180 end
      waitUntil(conversionLimit,function()
        local stock=field()
        for name,need in pairs(target) do if (stock[name] or 0)<need then return false end end
        return true
      end,unchanged)
      unchanged();generator(false)
      record.plan=nil;record.lastState=nil;save("watching")
      if not stopping then
        checkContaminants(field(),record.required)
        pause(0)
        print("整批流体齐备，已连续放行；追加订单自动补整批差额。按 Q 停止。")
        local releasedAt=computer.uptime()
        local deadline=releasedAt+600
        local lastStock=field()
        local nextQueueCheck=0
        while not stopping do
          local v=call(NODE,"getState")
          local stock=field()
          local req=call(NODE,"getRequiredCondensate")
          if req~=nil then checkRecipe(req) end
          if v=="idle" or waiting[v] then break end
          assert(v=="crafting" or (v=="paused-immediate" and computer.uptime()-releasedAt<3),
            "节点运行异常: "..tostring(v))
          local refill=false
          if computer.uptime()>=nextQueueCheck and req~=nil then
            local consumed=call(NODE,"getConsumedCondensate")
            assert(type(consumed)=="table","当前消耗记录不可读")
            local count=math.max(1,queuedRecipes())
            for name,amount in pairs(req) do
              local parallel=checkRecipe(req)
              local need=perRecipe[name]*math.max(parallel,count)-integer(consumed[name] or 0)
              if (stock[name] or 0)<need then refill=true end
            end
            nextQueueCheck=computer.uptime()+1
          end
          if refill then break end
          if not same(stock,lastStock) then deadline=computer.uptime()+600;lastStock=stock end
          assert(computer.uptime()<deadline,"当前配方运行超时")
          tick(0.1)
        end
      end
    end
  end
  pause(15);generator(false);record.configOwned=false
  for _,job in ipairs(record.requests) do
    if job.state~="done" then
      save("craft-paused")
      print("服务已暂停；主网原液申请仍需核对，保留日志，不重复下单。")
      return
    end
  end
  save("stopped")
  print("已停止常驻服务：暂停输出 15，纠缠装置关闭；约束场与已有凝聚物保持开启。")
end
local function main()
  assert(mode=="preview" or mode=="run" or mode=="resume" or mode=="restock", "用法: preview / run / resume / restock，无需填写数量")
  RS = resolve("266f65b5", "redstone")
  GEN = resolve("c1ae3f7c", "gt_machine")
  assert(call(GEN, "getName") == "multi.bec.generator", "纠缠装置名称不符")
  for _, item in ipairs({{RS,"setOutput"},{RS,"getOutput"},{GEN,"setWorkAllowed"},
    {GEN,"isWorkAllowed"},{GEN,"isMachineActive"},{MAIN,"getFluidsInNetwork"},
    {MAIN,"setFluidInterfaceConfiguration"},{MAIN,"getFluidInterfaceConfiguration"},
    {SUB,"getFluidsInNetwork"},{TRANS,"transferFluid"},
    {MAIN,"getCraftables"},{MAIN,"getCpus"}}) do method(item[1],item[2]) end
  local minimum,maximum=integer(call(NODE,"getMinParallel")),integer(call(NODE,"getMaxParallel"))
  assert(minimum>=1 and maximum>=minimum,"节点并行设置无效")
  print("远端红石: " .. RS .. "；纠缠装置: " .. GEN)
  print("节点: " .. call(NODE,"getState") .. "；向上输出: " .. call(RS,"getOutput",sides.top))
  print("纠缠装置允许工作: " .. tostring(call(GEN,"isWorkAllowed")))
  print("凝聚物库存: " .. ser.serialize(field(),false))
  if mode == "preview" then
    print("子网原液: " .. ser.serialize(network(SUB),false))
    if call(NODE,"getState") == "paused-immediate" then
      local required,remaining=current();local target,count=batchTarget(required,remaining)
      print("主网剩余配方 "..count.." 份")
      plan(target)
    end
    print("预览结束：没有开关、搬液、配置或写日志。")
    return
  end
  local waitingStates = {idle=true, ["paused-immediate"]=true, ["assembler-offline"]=true,
    unpowered=true, ["nanite-tier-too-low"]=true}
  local initialState = call(NODE,"getState")
  assert(waitingStates[initialState], "节点状态不适合启动: " .. tostring(initialState))
  emptyConfig(); tanks(4,nil); tanks(5,nil)
  if fs.exists(JOURNAL) then
    local f=assert(io.open(JOURNAL,"r"));local contents=f:read("*a");f:close()
    local old=ser.unserialize(contents)
    assert(type(old)=="table" and old.version==1 and old.kind=="continuous"
      and old.pending==nil and old.configOwned==false,"日志无效或有未确认操作，禁止重跑")
    if mode=="resume" or mode=="restock" then
      local preTransfer=(old.stage=="starting" or old.stage=="waiting" or old.stage=="waiting-stock")
        and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil
        and (old.requests==nil or next(old.requests)==nil)
      local watching=(old.stage=="watching" or old.stage=="waiting") and old.plan==nil
        and type(old.transfers)=="table" and type(old.target)=="table"
      local crafted=old.stage=="craft-done" and old.plan==nil
        and type(old.transfers)=="table" and next(old.transfers)==nil
        and type(old.requests)=="table" and next(old.requests)~=nil
      local prepared=old.stage=="stream-prepared" and old.plan==nil
        and type(old.expected)=="table" and type(old.transfers)=="table"
        and type(old.target)=="table"
      local converting=old.stage=="converting" and old.plan==nil
        and type(old.expected)=="table" and type(old.transfers)=="table"
        and type(old.target)=="table" and type(old.required)=="table" and type(old.remaining)=="table"
      if watching or crafted or prepared or converting then
        for _,move in ipairs(old.transfers) do
          assert(move.ok==true and type(move.amount)=="number" and move.amount>0,
            "旧搬运未确认，禁止恢复")
        end
        for _,job in ipairs(old.requests or {}) do
          assert(job.state=="done","原液申请未完成，禁止重复申请")
        end
        assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false
          and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置已停机")
        if crafted then
          -- Offline/low-power states can mask the immediate-pause status.
          -- Read the retained order under verified pause output; serve() waits
          -- for the observation array before configuring or moving any fluid.
          local req,remaining=current(true)
          assert(same(req,old.required) and same(remaining,old.remaining),"旧申请订单已变化，暂停核对")
          print("已完成原液申请已归档；按当前真实库存重新计算缺口。")
        end
        if prepared then
          current(true)
          assert(same(network(SUB),old.expected),"已备齐原液与日志不符，暂停核对")
          print("整批原液已在子网，恢复时抵扣，不重复搬料或申请。")
        end
        if converting then
          local req,remaining=current(true)
          local target=old.target
          if not (same(req,old.required) and same(remaining,old.remaining)) then
            local count;target,count=batchTarget(req,remaining)
            assert(type(old.batchCount)=="number" and count<=old.batchCount,
              "恢复时订单增加或旧批量缺失，暂停核对")
            for name,need in pairs(target) do assert(need<=integer(old.target[name]),"恢复需求超过旧整批目标") end
            print("实际并行/消耗已变化，按 AE 剩余订单扣除节点已消耗量核对库存。")
          end
          local sub,stock=network(SUB),field()
          for name,value in pairs(target) do
            local raw=mapping[name]
            local need=integer(value)
            local liquid,condensate=integer(sub[raw] or 0),integer(stock[name] or 0)
            local unit=units[name] or 144
            assert(liquid%unit==0 and condensate%unit==0 and (liquid+condensate==need
              or (mode=="restock" and liquid+condensate<need)),
              "转换恢复库存不符: "..raw.."；子网 "..liquid.." + 凝聚物 "..condensate.."，目标 "..need)
            if liquid+condensate<need then print(raw.." 当前缺口 "..(need-liquid-condensate).." mB；归档旧操作后重新备料。") end
          end
          for raw in pairs(sub) do
            local allowed=false;for _,known in pairs(mapping) do if known==raw then allowed=true end end
            assert(allowed,"转换恢复子网有无关原液")
          end
          for name,n in pairs(stock) do assert(n==0 or mapping[name],"转换恢复有无关凝聚物") end
          print("转换恢复核对通过，抵扣当前库存；已完成的旧申请和搬运记录保留归档。")
        end
      end
      assert(preTransfer or watching or crafted or prepared or converting,"该阶段存在未确认操作，不能自动恢复")
      archiveJournal(contents,".before-resume-")
    else
      assert(old.stage=="stopped","已有非正常停止日志，请核对后使用 resume，禁止盲目重跑")
      for _,job in ipairs(old.requests or {}) do
        assert(job.state=="done","旧日志有未确认的主网申请，禁止重新下单")
      end
      archiveJournal(contents)
    end
  else
    assert(mode~="resume" and mode~="restock","没有可恢复的日志")
  end
  record={version=1,kind="continuous",stage="starting",transfers={},requests={},configOwned=false}
  save("starting");armed=true
  print("常驻模式：无需填写数量。先只提交原始屏蔽层任务，可先 5 再 10。")
  print("按主网 CPU 剩余任务量，一次准备整批原液；追加订单自动补差额。")
  serve()

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
