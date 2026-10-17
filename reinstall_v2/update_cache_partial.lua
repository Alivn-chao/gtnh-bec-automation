-- BEC_V2_CACHE_PARTIAL_UPDATE_1
local SELF_SIGNATURE='43647:3208582542'
print('BEC partial cache update; Q to exit the old UI first')
local rows={{name='runtime/cache.lua',added=false,source=[=[-- V2 adapter of V1 bec_cache.lua; original transfer/AE/conversion protocol retained.
local c = require("component") local ser = require("serialization") local computer = require("computer")
local fs = require("filesystem") local sides = require("sides") local event = require("event")
local mode, cacheCopies = ... mode=mode or "preview" local fixedStock -- BEC_V1_CACHE_CUSTOM_V1
local overrides={}
local background=mode=="background-stock" if mode=="preview-stock" or mode=="run-stock" or background then fixedStock=tonumber(cacheCopies)
assert(fixedStock and fixedStock>=1 and fixedStock<=2147483647 and fixedStock==math.floor(fixedStock),"统一库存需指定正整数mB") mode=mode=="preview-stock" and "preview" or "run" cacheCopies=1
else cacheCopies=tonumber(cacheCopies) or 1 end local JOURNAL = "/home/bec_cache.journal" local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50" local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad" local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0"
local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0" local GATE_ADDRESS = "cf2a0c4a-ab8d-4958-b1df-253094d6690c" local RS, GEN, GATE, armed, record
local stopping=false local mapping = { entangled_infinity = "molten.infinity",
entangled_chromaticglass = "molten.chromaticglass", entangled_transcendentmetal = "molten.transcendentmetal", entangled_dimshiftedsuperfluid = "dimensionallyshiftedsuperfluid",
entangled_neutronium="molten.neutronium",entangled_cosmicneutronium="molten.cosmicneutronium", entangled_bedrockium="molten.bedrockium",entangled_celestialtungsten="molten.celestialtungsten", entangled_hypogen="molten.hypogen",entangled_phononmedium="phononmedium",
entangled_quarkgluonplasma="quarkgluonplasma",entangled_spacetime="molten.spacetime", entangled_time="molten.temporalfluid",entangled_space="molten.spatialfluid", entangled_cosmicsolder="boundlesscosmicsolder",
entangled_mhdcsm="molten.magnetohydrodynamicallyconstrainedstarmatter", entangled_magmatter="molten.magmatter",entangled_universium="molten.universium", entangled_eternity="molten.eternity"
} local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000, entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000}
local function call(a, m, ...) return c.invoke(a, m, ...) end local function method(a, m) assert(c.methods(a)[m] ~= nil, "组件缺少方法: " .. m)
end local function resolve(prefix, kind) local address, count = nil, 0
for a, t in c.list() do if a:sub(1, #prefix) == prefix and t == kind then address, count = a, count + 1
end end assert(count == 1, "目标组件缺失或不唯一: " .. prefix)
return address end local function integer(v)
assert(type(v) == "number" and v >= 0 and v == math.floor(v), "库存/需求数量无效") return v end
local function same(a, b) for k, v in pairs(a) do if b[k] ~= v then return false end end for k, v in pairs(b) do if a[k] ~= v then return false end end
return true end local function network(a)
local rows, result = call(a, "getFluidsInNetwork"), {} assert(type(rows) == "table", "网络库存不可读") for _, f in pairs(rows) do
assert(type(f) == "table", "流体条目无效") local n = integer(f.amount or f.size or 0) if n > 0 then
assert(type(f.name) == "string", "流体名称缺失") result[f.name] = (result[f.name] or 0) + n end
end return result end
local matchedOutputs, perRecipe local function tick(seconds) local _,_,character=event.pull(seconds,"key_down")
if character==113 or character==81 then stopping=true end end local function archiveJournal(contents,suffix)
if BEC_V2_CACHE_PRUNE then BEC_V2_CACHE_PRUNE() end

suffix=suffix or ".stopped-" local index=1 while fs.exists(JOURNAL..suffix..index) do index=index+1 end
local backup=JOURNAL..suffix..index assert(fs.rename(JOURNAL,backup),"旧常驻日志归档失败") local f=assert(io.open(backup,"r"));local actual=f:read("*a");f:close()
assert(actual==contents and not fs.exists(JOURNAL),"旧常驻日志归档验证失败") end local function field()
assert(call(STORAGE, "isWorkAllowed") == true, "约束场必须保持开启") local v = call(STORAGE, "getStoredCondensate") assert(type(v) == "table", "凝聚物库存不可读")
for _, n in pairs(v) do integer(n) end return v end
local function writeVerified(path, contents) local f = assert(io.open(path, "w")) local ok, err = f:write(contents)
local flushed, flushErr = f:flush() f:close() assert(ok and flushed, tostring(err or flushErr or "日志写入失败"))
local r = assert(io.open(path, "r")) local actual = r:read("*a"); r:close() assert(actual == contents and type(ser.unserialize(actual)) == "table", "日志回读失败")
end local function save(stage) record.stage = stage
if fs.exists(JOURNAL) then local f = assert(io.open(JOURNAL, "r")) local old = f:read("*a"); f:close()
writeVerified(JOURNAL .. ".previous", old) end writeVerified(JOURNAL, ser.serialize(record, false))
end local function pause(value) call(RS, "setOutput", sides.top, value)
assert(call(RS, "getOutput", sides.top) == value, "红石输出回读不符") end local function generator(enabled)
call(GEN, "setWorkAllowed", enabled) assert(call(GEN, "isWorkAllowed") == enabled, "纠缠装置启停回读不符") end
local function gateFilters(required) assert(type(required)=="table","门过滤需求不可读") local result={}
for name,n in pairs(required) do assert(mapping[name] and integer(n)>0,"门过滤需求无效: "..tostring(name)) result[#result+1]=name
end table.sort(result) assert(#result>0,"禁止写入全空过滤；全空会放行全部凝聚物")
return result end local function verifyGate(expected)
local count=integer(call(GATE,"getCondensateFilterCount")) assert(count>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters")
assert(type(actual)=="table" and same(actual,expected), "麦克斯韦门过滤回读不符；检查门的流体输入仓是否自动覆盖 OC 过滤") assert(call(GATE,"isWorkAllowed")==true,"麦克斯韦门未启用，保持暂停")
assert(call(GATE,"isMachineActive")==true,"麦克斯韦门未运行；检查结构和供电，保持暂停") end local function configureGate(required)
assert(call(RS,"getOutput",sides.top)==15 and call(NODE,"getState")=="paused-immediate", "切换门过滤前节点必须立即暂停") local expected=gateFilters(required)
assert(integer(call(GATE,"getCondensateFilterCount"))>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table","麦克斯韦门过滤不可读")
record.gateIntent={address=GATE,filters=expected};save(record.stage) if not same(actual,expected) then call(GATE,"setCondensateFilters",expected) end for i=1,3 do
verifyGate(expected) assert(call(NODE,"getState")=="paused-immediate","设置过滤时订单状态变化") if i<3 then tick(0.1) end
end print("麦克斯韦门过滤: "..table.concat(expected,", ")) return expected
end local function tanks(side, name) local count, amount = integer(call(TRANS, "getTankCount", side)), 0
assert(count > 0, "接口没有流体槽") for i = 1, count do local f = call(TRANS, "getFluidInTank", side, i)
assert(type(f) == "table", "接口缓存不可读") if type(f[1]) == "table" then f = f[i] or f[1] end local n = integer(f.amount or 0)
if n > 0 then assert(name and f.name == name, "接口有未处理流体缓存") amount = amount + n
end end return amount
end local function emptyConfig() for slot = 0, 5 do
assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置") end end
local function waitUntil(seconds, condition, guard) local deadline = computer.uptime() + seconds while true do
local ready, snapshot = condition() if ready then return end if guard then guard(snapshot) end
assert(computer.uptime() < deadline, "等待超时，停止") os.sleep(0.25) end
end local function bulkPorts() local allowed,ports={},{}
for _,raw in pairs(mapping) do allowed[raw]=true;allowed["fluid."..raw]=true end
for _,raw in ipairs({"spatialfluid","fluid.spatialfluid","temporalfluid","fluid.temporalfluid"}) do allowed[raw]=true end for address,kind in c.list("transposer") do if kind=="transposer" and address~=TRANS then
local sources,receivers={},{} for side=0,5 do local ok,count=pcall(call,address,"getTankCount",side)
if ok and count==1 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==2147483647 then
local f=call(address,"getFluidInTank",side,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end if type(f)=="table" and allowed[f.name] then sources[#sources+1]={from=side,raw=f.name} end
end elseif ok and count==6 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1)
if readable and capacity==16000 then receivers[#receivers+1]=side end end end
if #sources>0 then assert(#receivers==1,"高速供液口接收方向缺失或不唯一: "..address) for _,source in ipairs(sources) do
assert(not ports[source.raw],"高速供液口重复绑定: "..source.raw) ports[source.raw]={address=address,from=source.from,to=receivers[1]} end
end end end
return ports end local function verifyBulk(route,raw)
local f=call(route.address,"getFluidInTank",route.from,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end assert(type(f)=="table" and f.name==raw
and call(route.address,"getTankCapacity",route.from,1)==2147483647,"高速缓存口绑定已变化") assert(call(route.address,"getTankCount",route.to)==6,"高速接收接口已变化") for i=1,6 do
local tank=call(route.address,"getFluidInTank",route.to,i) if type(tank)=="table" and type(tank[1])=="table" then tank=tank[i] or tank[1] end assert(type(tank)=="table" and integer(tank.amount or 0)==0,"高速接收接口有未处理缓存")
end end local function unchanged()
local state=call(NODE,"getState") local blocked={idle=true,["paused-immediate"]=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true} assert(state=="idle" or (background and blocked[state]),"节点状态变化，停止预缓存并保留已有库存")
assert(call(RS,"getOutput",sides.top)==15,"暂停信号变化") field() end
-- BEC_V1_CACHE_FAST_V2
local productionOutputs,priorityAt,priorityQueued={},-math.huge,false
local unknownReported=false
local function productionWaiting()
 if not background then return false end
 if BEC_V2_CACHE_YIELD and BEC_V2_CACHE_YIELD()then return true end
 local state=call(NODE,"getState")
 if state~="idle" then
  local req=call(NODE,"getRequiredCondensate")
  if (type(req)=="table" and next(req)~=nil) or state=="crafting" or state=="paused-step" then
   print("后台缓存让位：节点有配方，优先生产。")
   return true
  end
 end
 if computer.uptime()<priorityAt then return priorityQueued end
 priorityAt=computer.uptime()+1;priorityQueued=false
 local cpus=call(MAIN,"getCpus");assert(type(cpus)=="table","主网 CPU 状态不可读")
 for _,cpu in pairs(cpus) do if cpu.busy==true then
  for _,getter in ipairs({"activeItems","pendingItems"}) do
   local ok,rows=pcall(function()return cpu.cpu[getter]()end)
   if not ok or type(rows)~="table" then
    if not unknownReported then print("AE CPU任务列表不可读；未确认为配方，空闲补库继续。") end
    unknownReported=true
   else for _,item in pairs(rows) do
    local key=tostring(item.name)..":"..tostring(tonumber(item.damage or 0))
    if productionOutputs[key] and (item.size or item.amount or 0)>0 then priorityQueued=true end
   end end
  end
 end end
 if priorityQueued then print("后台缓存让位：AE队列有登记配方，优先生产。") end
 return priorityQueued
end

local function prepareStreaming(target) local ports=bulkPorts() local stock,previous=field(),network(SUB)
local expected,raws={},{}

local priority=false
local function handoff()
 for _,job in ipairs(record.requests) do assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"缓存申请尚未完成，不能交回生产") end
 for raw,n in pairs(previous) do
  local known=false;for name in pairs(target) do if mapping[name]==raw then known=true;assert(integer(n)%(units[name] or 144)==0,"已搬缓存不是整批") end end
  assert(known,"交回生产前子网有无关原液")
 end
 for name in pairs(target) do target[name]=(stock[name] or 0)+(previous[mapping[name]] or 0) end
 expected=previous;record.target=target;record.expected=previous;record.secured=previous;record.plan=nil
 record.yieldedToRecipe=true;save("stream-prepared")
 print("已有配方，停止补缓存；仅转换已搬入原液后交回生产。")
 return previous
end
if productionWaiting() then return handoff() end

for name,need in pairs(target) do local raw=mapping[name]
local batch=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0
assert(amount==0 or ports[raw],"缺少高速供液口："..raw.."；禁止普通接口回退")
assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end raws[#raws+1]={raw=raw,amount=amount,batch=batch}
end for raw in pairs(previous) do local allowed=false
for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end
for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned")
for _,item in ipairs(raws) do if productionWaiting() then return handoff() end local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw]
local chunk=math.floor(2147483647/batch)*batch local function bufferedInlet() return 0 end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=false;save("stream-configuring")
assert(route,"高速供液口不可用："..raw);verifyBulk(route,raw)
print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to)
print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt
local attempts=0 local inletOpen=false local deadline=computer.uptime()+1800
while not stopping do unchanged();assert(same(field(),stock),"备料时约束场库存变化") assert(same(network(SUB),previous),"备料时子网库存变化")
priority=priority or productionWaiting()
local remaining=need-(previous[raw] or 0) local settling=(batch-(previous[raw]or 0)%batch)%batch
local buffered=network(MAIN)[raw] or 0 local amount=math.floor(math.min(priority and settling or remaining,buffered,chunk))
if amount>0 then verifyBulk(route,raw);local address,from,to=route.address,route.from,route.to
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to}
save("transfer-returned") assert(ok==true and type(moved)=="number" and moved>=0 and moved<=amount and moved==math.floor(moved),"搬运返回值未确认，停止且不重试") if moved>0 then previous[raw]=(previous[raw] or 0)+moved end
waitUntil(10,function() return same(network(SUB),previous) end,unchanged)
if moved==0 then table.remove(record.transfers);record.zeroTransfers=(record.zeroTransfers or 0)+1 else deadline=computer.uptime()+1800 end
record.pending=nil;record.secured=previous;save("stream-transfer-confirmed") print(raw.." 已入子网 "..(previous[raw]or 0).." / "..need.." mB；本次 "..moved.." / "..amount)
end remaining=need-(previous[raw] or 0);settling=(batch-(previous[raw]or 0)%batch)%batch
if remaining==0 and inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;inletOpen=false;save("stream-inlet-cleared")
waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) end -- BEC_V1_SEQUENTIAL_CPU_WAIT_V1: keep both production fallback and cache alive while CPUs are occupied.
local supplyWaiting=false
local function supplyWait(reason,manual,missing,failure)
 supplyWaiting=true
 local summary=raw..': '..reason
 if not record.supplyWait or record.supplyWait.cpuWaitSummary~=summary then
  record.supplyWait={cpuWaitSummary=summary,cpuWait={[raw]={reason=reason,manual=manual,amount=missing,failure=failure}}}
  save(record.stage);print('供液等待: '..summary)
 end
end
if status and job.state=='submitted' then
 local computing=type(status.isComputing)=='function' and status.isComputing()
 local failed,why
 if type(status.hasFailed)=='function' then failed,why=status.hasFailed()end
 if computing==false and type(status.isComputing)=='function' and failed==true then
  job.state='rejected';job.preSubmissionFailed=true;job.manualSupply=true;job.failure=tostring(why)
  status=nil;save('stream-request-rejected')
 elseif computing then supplyWait('AE 正在计算计划，继续收料')
 else
  local canceled,why=status.isCanceled();assert(canceled==false,'AE任务取消且结果未确认: '..tostring(why))
  local done=status.isDone();assert(type(done)=='boolean','AE 状态不可读')
  if done then job.state='done';job.securedAfter=previous[raw] or 0;doneAt=computer.uptime();save('stream-craft-done')
  else supplyWait('AE 合成进行中，继续收料')end
 end
end
if priority and settling==0 and (not job or job.state=='done' or job.state=='rejected')then return handoff()end
if remaining==0 and (not job or job.state=='done' or job.state=='rejected')then record.supplyWait=nil;break end
if (not priority or settling>0) and remaining>0 and (not job or job.state=='done' or job.state=='rejected')then
 local function deficit()return math.max(0,(priority and settling or remaining)-bufferedInlet()-(network(MAIN)[raw]or 0))end
 local missing=deficit()
 if missing>0 and (not doneAt or computer.uptime()-doneAt>=3)then
  if job and job.state=='done'then assert((previous[raw]or 0)>job.securedBefore,'原液合成已结束但没有收获，核对竞争设备')end
  local ok,cpus=pcall(call,MAIN,'getCpus');local free,total,known,maxStorage=0,0,0,0;local unknown=not ok or type(cpus)~='table'
  if not unknown then for _,cpu in pairs(cpus)do
   total=total+1
   if type(cpu)~='table' or type(cpu.busy)~='boolean'then unknown=true
   else if not cpu.busy then free=free+1 end
    if type(cpu.storage)=='number'and cpu.storage>=0 then known=known+1;maxStorage=math.max(maxStorage,cpu.storage)end
   end
  end end
  if job and job.manualSupply then
   supplyWait('AE未启动申请；请在 ME 手动申请 '..missing..' mB；自动收料继续',true,missing,job.failure)
  elseif unknown then supplyWait('等待 CPU 状态恢复可读')
  elseif total==0 or (known==total and maxStorage==0)then supplyWait('CPU 容量不足：没有可用合成存储')
  elseif free==0 then supplyWait('等待合成 CPU 空闲，自动化继续运行')
  else
   if not craft then
    local rows=call(MAIN,'getCraftables',{name=raw});assert(type(rows)=='table','原液配方不可读')
    local count=0;for _,v in pairs(rows)do craft=v;count=count+1 end
    assert(count==1,'原液配方缺失或不唯一: '..raw)
    local f=craft.getStack();assert(type(f)=='table'and f.name==raw and f.isCraftable==true and type(f.amount)=='number'and f.amount==f.size and f.hasTag==false,'未验证的流体合成对象')
   end
   missing=deficit()
   if missing>0 then
    if productionWaiting()then return handoff()end
    attempts=attempts+1;assert(attempts<=3,'原液被其他设备争抢，保留已收库存')
    job={raw=raw,amount=missing,unit='mB',state='pending',securedBefore=previous[raw]or 0}
    record.requests[#record.requests+1]=job;save('craft-request-pending')
    local why;status,why=craft.request(missing);assert(status~=nil,'AE申请结果不明: '..tostring(why))
    job.state='submitted';doneAt=nil;save('stream-crafting')
    supplyWait('AE 正在计算计划，继续收料')
   end
  end
 end
end
if supplyWaiting then deadline=math.max(deadline,computer.uptime()+1800)end
assert(computer.uptime()<deadline,'持续收料超时，保留子网已搬入原液')
 tick(0.1) end
if inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;save("stream-inlet-cleared")
end waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) if stopping then return expected end
end end assert(same(network(SUB),expected),"整批子网原液不符")
record.plan=nil;save("stream-prepared") return expected end
local function cacheTarget(copies) assert(type(copies)=="number" and copies>=1 and copies==math.floor(copies),"缓存份数必须为正整数") local totals,count={},0 local selectedBackground
assert(fs.exists("/home/bec/recipes"),"没有已登记配方") for filename in fs.list("/home/bec/recipes") do if filename:sub(-4)==".dat" then local f=assert(io.open("/home/bec/recipes/"..filename,"r"));local text=f:read("*a");f:close()
local recipe=ser.unserialize(text) assert(type(recipe)=="table" and recipe.state=="converted" and type(recipe.condensates)=="table","配方记录未完成: "..filename) local demand={}
for _,out in ipairs(recipe.outputs or {}) do productionOutputs[tostring(out.name)..":"..tostring(tonumber(out.damage or 0))]=true end
for _,fluid in ipairs(recipe.condensates) do assert(mapping[fluid.name],"未登记原液映射: "..tostring(fluid.name)) demand[fluid.name]=(demand[fluid.name] or 0)+integer(fluid.amount)
end assert(next(demand),"配方没有凝聚物需求: "..filename) for name,need in pairs(demand) do
assert(need*copies<=2147483647,"缓存目标过大") totals[name]=math.max(totals[name] or 0,need*copies) end
count=count+1 print("配方 "..count.."："..filename) end end
assert(count>0,"没有可缓存的已登记配方") if fixedStock then
local input=io.open("/home/bec_cache.config","r")
if input then local cfg=ser.unserialize(input:read("*a"));input:close()
 assert(type(cfg)=="table" and cfg.version==1 and (cfg.overrides==nil or type(cfg.overrides)=="table"),"单项缓存配置无效")
 overrides=cfg.overrides or {};for name,n in pairs(overrides) do assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"单项缓存目标无效") end
end
for name in pairs(totals) do totals[name]=overrides[name]~=nil and overrides[name] or fixedStock end
end if background then local previous=io.open(JOURNAL,"r")
local old if previous then old=ser.unserialize(previous:read("*a"));previous:close() end if old and old.background and old.incomplete then
assert(old.stage=="stopped" and old.pending==nil and old.configOwned==false,"后台缓存有未确认操作，保留日志核对") totals=old.target else
if productionWaiting() then return {} end local stock=field();local selected,lowest for name,need in pairs(totals) do local available=stock[name] or 0
if available<need and (not lowest or available<lowest) then selected=name;lowest=available end end if not selected then return {} end
selectedBackground=selected;totals={[selected]=totals[selected]} end end
local live,stock=network(MAIN),field();for raw,n in pairs(network(SUB)) do live[raw]=math.max(live[raw] or 0,n) end local visibleRoutes=bulkPorts();local waiting for kind in pairs(totals) do local raw=mapping[kind]
local candidates={[raw]=true} candidates["fluid."..raw]=true if kind=="entangled_space" or kind=="entangled_time" then
local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" candidates[stem]=true;candidates["fluid."..stem]=true end
local found={} for name in pairs(candidates) do if (live[name] or 0)>0 or visibleRoutes[name] then found[name]=true end end for name in pairs(candidates) do
local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败") for _,craft in pairs(rows) do local stack=craft.getStack()
if type(stack)=="table" and stack.name==name and type(stack.amount)=="number" then found[name]=true end end end
local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"原液名称不唯一: "..kind)
if n==0 and (stock[kind] or 0)<totals[kind] then waiting="等待原液库存/样板可见: "..kind.." / "..raw end
if n==1 then mapping[kind]=name end end
if productionWaiting() then return totals end local routes=bulkPorts();local stored=field()
for kind,need in pairs(totals) do
 if (stored[kind] or 0)<need and not routes[mapping[kind]] then waiting="等待高速口流体可见: "..kind.." / "..mapping[kind].."；空口暂不能识别绑定，稍后重扫" end
end
if selectedBackground then print("空闲高速补库：直接补本种完整缺口到 "..totals[selectedBackground].." mB；有配方优先让位。") end if fixedStock then
print("登记配方 "..count.."；默认目标 "..fixedStock.." mB，单项设置优先，0停补；只补差额。") else print("登记配方 "..count.."；每配方 "..copies.." 份，共用流体按最大用量缓存。") end return totals,waiting
end local function cacheMain() assert(mode=="preview" or mode=="run","用法: preview / run [每配方份数，默认1]")
RS=resolve("266f65b5","redstone");GEN=resolve("c1ae3f7c","gt_machine") assert(call(GEN,"getName")=="multi.bec.generator","纠缠装置名称不符") local target,waiting=cacheTarget(cacheCopies)
while waiting do print(waiting)
if background or mode=="preview" then return end
tick(2);if stopping then print("已取消等待；日志和库存未修改。");return end
target,waiting=cacheTarget(cacheCopies) end
if background and next(target)==nil then return end local stock=field() for name,need in pairs(target) do
local batch=units[name] or 144 print(name.." 缓存目标 "..need.."；凝聚物已有 "..(stock[name] or 0) .."；待补原液 "..math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch.." mB")
end if mode=="preview" then print("只读规划完成，未申请、搬料、转换或写记录。");return end
assert(BEC_V2_CACHE_GUARD,'缺少V2缓存调度器');BEC_V2_CACHE_GUARD()
local nodeState=call(NODE,"getState") local blocked={idle=true,["paused-immediate"]=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true} assert(nodeState=="idle" or (background and blocked[nodeState]),"预缓存须在节点空闲/已暂停时进行")
assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"预缓存前须暂停并关闭纠缠装置") emptyConfig();tanks(4,nil);tanks(5,nil)
if fs.exists(JOURNAL) then local f=assert(io.open(JOURNAL,"r"));local text=f:read("*a");f:close() local old=ser.unserialize(text)
assert(type(old)=="table" and old.kind=="cache" and old.stage=="stopped" and old.pending==nil and old.configOwned==false,"旧缓存有未确认操作，请保留日志核对") for _,job in ipairs(old.requests or {}) do assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"缓存申请仍未确认") end
archiveJournal(text) end record={version=1,kind="cache",requests={},transfers={},configOwned=false,target=target,copies=cacheCopies,fixedStock=fixedStock,background=background}
save("starting");armed=true local expected=prepareStreaming(target) if not stopping and next(expected) then
unchanged();save("converting");generator(true);if background then print("后台缓存纠缠转换中；本轮目标已更新。") end local deadline=computer.uptime()+180 for kind in pairs(target) do
deadline=deadline+math.ceil((expected[mapping[kind]] or 0)/(units[kind] or 144))*180 end while true do
unchanged();local ready=true;local now=field() for name,need in pairs(target) do if (now[name] or 0)<need then ready=false end end if ready then break end
assert(computer.uptime()<deadline,"缓存转换超时，保留库存与日志") tick(0.25) if stopping then break end
end generator(false) end
unchanged();generator(false) record.incomplete=false local final=field()
for name,need in pairs(target) do if (final[name] or 0)<need then record.incomplete=true end end for _,job in ipairs(record.requests) do if job.state~="done" and not(job.state=="rejected" and job.preSubmissionFailed==true) then save("craft-paused");print("缓存已暂停，AE申请仍需核对，不重复下单。");return
end end save("stopped") print(stopping and "预缓存已暂停，已有原液/凝聚物保留。" or background and "预缓存完成（本轮）；统一目标仍以界面各项库存为准。" or "预缓存完成；凝聚物留在约束场，生产时直接抵扣。")
end local ok,err=xpcall(cacheMain,debug.traceback) if not ok then
if armed then pcall(pause,15);pcall(generator,false) if record.configOwned then pcall(call,MAIN,"setFluidInterfaceConfiguration",0) end
end print("预缓存停止："..tostring(err));print("保留 "..JOURNAL.." 和库存，不删除日志重跑。") end
return ok,err
]=],supported={['28595:725651639']=true,['28595:725651639']=true,['28595:725651639']=true,['28595:725651639']=true,['28595:725651639']=true}},{name='cache_recover.lua',added=true,source=[=[-- Explicit reconciliation of the old spatialfluid partial-return failure.
-- Does not request/cancel AE jobs. The operator must confirm the original job ended.
local mode,ack,group=...;mode=mode or 'preview';group=tonumber(group)or 1
assert(mode=='preview'or mode=='run','用法: preview / run ae-finished [设备组]')
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local c=require('component');local fs=require('filesystem');local clock=require('computer')
local cfg=C.load();C.validate(cfg,false);local g=assert(cfg.groups[group],'设备组不存在')
local path=C.path('state/group-'..group..'/cache.journal')
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local original=assert(read(path),'没有缓存日志');local formal=assert(read(C.path('config.dat')))
local old=assert(C.read(path));local raw='spatialfluid';local kind='entangled_space';local batch=144
local function whole(n)return type(n)=='number'and n>=0 and n<=2147483647 and n%1==0 end
local function same(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;for k,v in pairs(b)do if a[k]~=v then return false end end;return true end
local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
assert(old.version==1 and old.kind=='cache'and old.stage=='transfer-returned'and old.configOwned==false and not old.reconciliation,'仅核对此前空间流体部分返回；其他未确认状态保留')
assert(type(old.plan)=='table'and #old.plan==1 and old.plan[1].raw==raw and old.plan[1].batch==batch,'不是单种空间流体缓存，保留日志')
assert(type(old.target)=='table'and whole(old.target[kind]),'原目标不可读')
for name in pairs(old.target)do assert(name==kind,'原目标包含其他流体，保留日志')end
local pending=assert(old.pending,'没有待核对搬运');local transfers=assert(old.transfers);local last=assert(transfers[#transfers])
assert(pending.raw==raw and whole(pending.amount)and pending.amount>0,'搬运意图无效')
for _,key in ipairs({'raw','address','from','to'})do assert(last[key]==pending[key],'最后回执与搬运意图不对应')end
assert(last.ok==true and whole(last.amount)and last.amount>0 and last.amount<last.requested and last.requested==pending.amount,'不是明确成功的部分返回，禁止猜测恢复')
local before=0
for i=1,#transfers-1 do local t=transfers[i]
 assert(t.raw==raw and t.ok==true and whole(t.amount)and t.amount==t.requested,'前序搬运未完整确认')
 assert(t.address==pending.address and t.from==pending.from and t.to==pending.to,'前序搬运路线不一致')
 before=before+t.amount
end
assert(type(old.secured)=='table'and same(old.secured,{[raw]=before}),'前序回执与已确认库存不一致')
local arrived=before+last.amount
assert(type(old.expected)=='table'and whole(old.expected[raw])and arrived<=old.expected[raw]and old.expected[raw]==old.plan[1].amount,'原计划与回执不一致')
assert(type(old.requests)=='table'and #old.requests<=1,'原AE申请不唯一，需另外核对')
for _,job in ipairs(old.requests)do
 assert(job.raw==raw and whole(job.amount)and(job.state=='submitted'or job.state=='done'or job.state=='rejected'and job.preSubmissionFailed),'原AE申请状态不支持此恢复')
end
local permitted=false;for _,a in ipairs(g.bulkTransposers or {})do if a==pending.address then permitted=true end end
assert(permitted,'原高速口已不在当前绑定内')
local function fluids(address)
 local result={};local rows=c.invoke(address,'getFluidsInNetwork');assert(type(rows)=='table','网络库存不可读')
 for _,f in pairs(rows)do local n=f.amount or f.size or 0;assert(whole(n),'库存数量无效');if n>0 then result[f.name]=(result[f.name]or 0)+n end end
 return result
end
local function field()
 assert(c.invoke(g.storage,'isWorkAllowed')==true,'约束场须保持开启')
 local v=c.invoke(g.storage,'getStoredCondensate');assert(type(v)=='table','凝聚物库存不可读');for _,n in pairs(v)do assert(whole(n),'凝聚物数量无效')end;return v
end
local function tank(side,i)local t=c.invoke(pending.address,'getFluidInTank',side,i);assert(type(t)=='table','高速口不可读');if type(t[1])=='table'then t=t[i]or t[1]end;return t end
local function port()
 assert(c.invoke(pending.address,'getTankCapacity',pending.from,1)==2147483647 and c.invoke(pending.address,'getTankCount',pending.to)==6,'高速口方向/类型变化')
 assert(tank(pending.from,1).name==raw,'高速口源流体变化')
 for i=1,6 do assert((tank(pending.to,i).amount or 0)==0,'接收接口尚有缓存，等待入网后再核对')end
end
local function guard(converting)
 assert(read(C.path('config.dat'))==formal,'核对期间绑定变化')
 local cohort=C.read(C.path('state/group-'..group..'/cohort.dat'));assert(not cohort or cohort.stage=='stopped','生产批次尚未收尾，保留日志')
 for i,n in ipairs(cfg.nodes)do if n.group==group then
  local production=C.read(C.path('state/node-'..i..'/production.journal'))
  if production then
   assert(production.stage=='stopped'and production.pending==nil and production.configOwned==false,'生产记录未确认，保留日志')
   for _,job in ipairs(production.requests or {})do assert(job.state=='done','生产AE申请未确认，保留日志')end
  end
  assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15 and c.invoke(n.address,'isWorkAllowed')==false,'先Q退出网页，暂停并关闭整组接单')
  local state=c.invoke(n.address,'getState');assert(state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low','节点状态不适合收尾')
 end end
 for _,a in ipairs(g.generators)do
  assert(c.invoke(a,'isWorkAllowed')==converting,'纠缠器工作许可变化')
  if not converting then assert(c.invoke(a,'isMachineActive')==false,'先等待全部纠缠器停机')end
 end
end
guard(false);port()
assert(same(fluids(g.subInterface),{[raw]=arrived}),'实际子网库存不等于前序确认量加最后返回量；未修改日志')
local baseline=field();local padding=(batch-arrived%batch)%batch;local aligned=arrived+padding
local target=copy(baseline);target[kind]=(baseline[kind]or 0)+aligned
assert(whole(target[kind]),'收尾目标超出范围')
print('回执与实物核对通过：已搬入 '..arrived..'；只补整批余量 '..padding..'；收尾原液合计 '..aligned)
for _,job in ipairs(old.requests)do print('原AE申请 '..job.amount..'，日志状态 '..job.state..'；本工具不会重新下单或取消。')end
if mode=='preview'then print('只读核对结束；原AE任务完成后使用 run ae-finished。');return end
assert(ack=='ae-finished','需先确认原AE任务已完成；用 run ae-finished 收尾，不重下单')
local disk=assert(fs.get(C.ROOT));assert(disk.spaceTotal()-disk.spaceUsed()>=524288+65536,'磁盘不足，未开始恢复；需保留512KiB及日志空间')
assert(read(path)==original,'核对期间原日志变化')
local index=1;while fs.exists(path..'.before-partial-recovery-'..index)do index=index+1 end
local archive=path..'.before-partial-recovery-'..index
local f=assert(io.open(archive,'w'));assert(f:write(original));assert(f:flush());f:close();assert(read(archive)==original,'原日志归档回读失败')
assert(read(path)==original,'归档期间原日志变化')
local record={version=1,kind='cache',stage='reconciling-partial',configOwned=false,requests={},transfers=transfers,
 target={[kind]=target[kind]},expected={[raw]=aligned},secured={[raw]=arrived},plan={{raw=raw,amount=aligned,batch=batch}},
 reconciliation={archive=archive,originalBytes=#original,originalAERequests=old.requests,operatorConfirmedAEFinished=true,returnedAmount=last.amount,requestedAmount=last.requested,verifiedStock=arrived}}
local function save(stage)record.stage=stage;C.write(path,record)end
local function stopGenerators()for _,a in ipairs(g.generators)do pcall(c.invoke,a,'setWorkAllowed',false)end end
local ok,reason=xpcall(function()
 save('reconciling-partial');local total=arrived;local deadline=clock.uptime()+30
 while total<aligned do
  guard(false);port();assert(same(field(),baseline)and same(fluids(g.subInterface),{[raw]=total}),'补整批前库存变化')
  local amount=aligned-total;assert((fluids(cfg.mainInterface)[raw]or 0)>=amount,'主网空间流体不足以补齐整批；不申请AE，保留恢复记录')
  record.pending={raw=raw,amount=amount,address=pending.address,from=pending.from,to=pending.to};save('recovery-transfer-pending')
  local accepted,moved=c.invoke(pending.address,'transferFluid',pending.from,pending.to,amount)
  local row={raw=raw,address=pending.address,from=pending.from,to=pending.to,requested=amount,ok=accepted,amount=moved}
  record.transfers[#record.transfers+1]=row;save('recovery-transfer-returned')
  assert(accepted==true and whole(moved)and moved<=amount,'补整批回执未确认，保留现场，不重试')
  total=total+moved;local untilAt=clock.uptime()+10
  while not same(fluids(g.subInterface),{[raw]=total})do guard(false);assert(clock.uptime()<untilAt,'补整批库存未确认，保留现场');os.sleep(.25)end
  if moved==0 then table.remove(record.transfers)end
  record.pending=nil;record.secured={[raw]=total};save('recovery-transfer-confirmed')
  assert(total==aligned or clock.uptime()<deadline,'补整批无进展，保留现场');if total<aligned then os.sleep(.25)end
 end
 guard(false);port();assert(same(field(),baseline)and same(fluids(g.subInterface),{[raw]=aligned}),'转换前库存不符')
 save('recovery-converting')
 for _,a in ipairs(g.generators)do c.invoke(a,'setWorkAllowed',true);assert(c.invoke(a,'isWorkAllowed')==true,'纠缠器开启回读失败')end
 local deadline=clock.uptime()+180+math.ceil(aligned/batch)*180
 while true do
  guard(true);local stock=field();local sub=fluids(g.subInterface)
  if same(stock,target)and next(sub)==nil then break end
  assert((stock[kind]or 0)<=target[kind],'转换超过核对目标，保留现场')
  for name,value in pairs(stock)do if name~=kind then assert(value==baseline[name],'其他凝聚物库存变化')end end
  assert(clock.uptime()<deadline,'收尾转换超时，保留恢复记录');os.sleep(.25)
 end
 stopGenerators();local deadline=clock.uptime()+10
 while true do local stopped=true;for _,a in ipairs(g.generators)do if c.invoke(a,'isMachineActive')then stopped=false end end;if stopped then break end;assert(clock.uptime()<deadline,'纠缠器尚未停机');os.sleep(.25)end
 guard(false);assert(same(field(),target)and next(fluids(g.subInterface))==nil,'最终收尾库存不符')
 record.expected={};record.secured={};record.plan=nil;record.pending=nil;record.incomplete=false;record.reconciliation.finalStock=target[kind]
 save('stopped')
end,debug.traceback)
if not ok then stopGenerators();error(tostring(reason)..'\n原日志及恢复记录保留，不要删除重跑。')end
print('缓存收尾核对完成；原日志保留：'..archive)
print('未重新申请AE。请重新打开网页；原缓存目标保留，可继续样板处理或补库。')
]=],supported={}}}

local fs=require('filesystem');local root='/home/bec_v2/'
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function normal(s)return s and s:gsub('\r\n','\n')end
local function signature(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local old,identical,bytes={},true,0
for i,row in ipairs(rows)do
 local target=root..row.name;old[i]=read(target);assert(old[i]or row.added,'缺少V2程序: '..target)
 local text=normal(old[i]);assert(row.added and text==nil or text==row.source or text and row.supported[signature(text)],'未知本地程序，保留未覆盖: '..target)
 if text~=row.source then identical=false end
 if row.name:sub(-4)=='.lua'then assert(load(row.source,'@'..target,'t',_ENV),'新程序语法无效')end
 bytes=bytes+#row.source
end
-- Release only this exact, already-loaded temporary download. The program
-- backups and every state/configuration file are retained.
local self='/home/bec_cache_partial_update.lua'
do
 local downloaded=read(self)
 local payload=downloaded and downloaded:match('^%-%- BEC_V2_CACHE_PARTIAL_UPDATE_1\nlocal SELF_SIGNATURE=[^\n]*\n(.*)$')
 if payload and signature(payload)==SELF_SIGNATURE then
  pcall(fs.remove,self)
 end
 downloaded=nil;payload=nil;if type(collectgarbage)=='function'then pcall(collectgarbage,'collect')end
end
if identical then print('缓存部分返回修复已安装，无需重复更新。');return end
local disk=assert(fs.get(root));assert(disk.spaceTotal()-disk.spaceUsed()>=bytes+524288,'磁盘空间不足：更新后需保留512KiB')
local n=1
while true do
 local conflict=false;for _,row in ipairs(rows)do for _,suffix in ipairs({'.before-cache-partial-','.cache-partial-new-','.cache-partial-failed-'})do if fs.exists(root..row.name..suffix..n)then conflict=true end end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(rows)do
 local temp=root..row.name..'.cache-partial-new-'..n;local f=assert(io.open(temp,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(temp)==row.source,'临时文件回读失败，旧程序未改')
end
for i,row in ipairs(rows)do assert(read(root..row.name)==old[i],'更新期间程序改变，未替换')end
local backed,installed={},{}
local ok,reason=pcall(function()
 for i,row in ipairs(rows)do local target=root..row.name
  if old[i]then assert(fs.rename(target,target..'.before-cache-partial-'..n),'备份失败');backed[i]=true end
  assert(fs.rename(target..'.cache-partial-new-'..n,target),'替换失败');installed[i]=true
  assert(read(target)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#rows,1,-1 do local target=root..rows[i].name
  if installed[i]then assert(fs.rename(target,target..'.cache-partial-failed-'..n),'移出失败程序失败，保留备份')end
  if backed[i]then assert(fs.rename(target..'.before-cache-partial-'..n,target),'恢复失败，保留备份')end
 end
 error('更新失败，旧程序已恢复：'..tostring(reason))
end
print('缓存部分返回修复已安装；原未确认日志保留，须另行核对收尾。')
print('已有地址、草稿、配置、配方和运行记录保留；未控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
