local c = require("component") local ser = require("serialization") local computer = require("computer") local fs = require("filesystem") local sides = require("sides") local event = require("event") local mode = (...) or "preview" local JOURNAL = "/home/bec_auto.journal"
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d" local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50" local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad" local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0" local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0" local GATE_ADDRESS = "cf2a0c4a-ab8d-4958-b1df-253094d6690c" local RS, GEN, GATE, armed, record local stopping=false
local NANITES=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")() local lastNaniteTier
local mapping = { entangled_infinity = "molten.infinity", entangled_chromaticglass = "molten.chromaticglass", entangled_transcendentmetal = "molten.transcendentmetal", entangled_dimshiftedsuperfluid = "dimensionallyshiftedsuperfluid", entangled_neutronium="molten.neutronium",entangled_cosmicneutronium="molten.cosmicneutronium", entangled_bedrockium="molten.bedrockium",entangled_celestialtungsten="molten.celestialtungsten", entangled_hypogen="molten.hypogen",entangled_phononmedium="phononmedium",
entangled_quarkgluonplasma="quarkgluonplasma",entangled_spacetime="molten.spacetime", entangled_time="molten.temporalfluid",entangled_space="molten.spatialfluid", entangled_cosmicsolder="boundlesscosmicsolder", entangled_mhdcsm="molten.magnetohydrodynamicallyconstrainedstarmatter", entangled_magmatter="molten.magmatter",entangled_universium="molten.universium", entangled_eternity="molten.eternity" } local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000,
entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000} local function call(a, m, ...) return c.invoke(a, m, ...) end local function method(a, m) assert(c.methods(a)[m] ~= nil, "组件缺少方法: " .. m) end local function resolve(prefix, kind) local address, count = nil, 0 for a, t in c.list() do
if a:sub(1, #prefix) == prefix and t == kind then address, count = a, count + 1 end end assert(count == 1, "目标组件缺失或不唯一: " .. prefix) return address end local function integer(v)
assert(type(v) == "number" and v >= 0 and v == math.floor(v), "库存/需求数量无效") return v end local function same(a, b) for k, v in pairs(a) do if b[k] ~= v then return false end end for k, v in pairs(b) do if a[k] ~= v then return false end end return true end
local function network(a) local rows, result = call(a, "getFluidsInNetwork"), {} assert(type(rows) == "table", "网络库存不可读") for _, f in pairs(rows) do assert(type(f) == "table", "流体条目无效") local n = integer(f.amount or f.size or 0) if n > 0 then assert(type(f.name) == "string", "流体名称缺失")
result[f.name] = (result[f.name] or 0) + n end end return result end local matchedOutputs, perRecipe local function checkRecipe(required,parallel) parallel=parallel or integer(call(NODE,"getParallelRecipesInProgress"))
assert(parallel>0 and type(required)=="table","当前配方并行/需求不可读") local normalized={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0 and n%parallel==0,"配方需求无法按并行拆分: "..tostring(name)) normalized[name]=n/parallel end local matches={} if fs.exists("/home/bec/recipes") then
for file in fs.list("/home/bec/recipes") do if file:match("%.dat$") then local f=assert(io.open("/home/bec/recipes/"..file,"r"));local r=ser.unserialize(f:read("*a"));f:close() assert(type(r)=="table","登记配方损坏: "..file) if r.state=="converted" then local needs={} for _,fluid in ipairs(r.condensates or {}) do needs[fluid.name]=(needs[fluid.name] or 0)+integer(fluid.amount or fluid.size) end if same(needs,normalized) then
assert(type(r.outputs)=="table" and #r.outputs==1,"登记产物无效: "..file) matches[#matches+1]=r.outputs[1] end end end end end if #matches>0 then
local provided=call(NODE,"getProvidedTier") if c.methods(NODE).getRequiredTier~=nil then local needed=call(NODE,"getRequiredTier") local tier=type(needed)=="table" and needed.tier or needed assert(type(tier)=="number","所需蜂群等级不可读") end  matchedOutputs,perRecipe=matches,normalized
return parallel end local amount=type(required)=="table" and required.entangled_chromaticglass assert(type(amount)=="number" and amount>0 and amount%288==0 and required.entangled_transcendentmetal==amount, "未验证的配方需求，保持暂停") local recipes=amount/288 assert(parallel==nil or parallel==recipes,"实际并行与凝聚物需求不符") local count=0; for _ in pairs(required) do count=count+1 end
assert(count==2,"未验证的凝聚物需求，保持暂停") local tier=call(NODE,"getProvidedTier") matchedOutputs={{name="gregtech:gt.metaitem.03",damage=32307,size=1}};perRecipe=normalized return recipes end local function tick(seconds)
local _,_,character=event.pull(seconds,"key_down") if character==113 or character==81 then stopping=true end end local function archiveJournal(contents,suffix)
assert(loadfile("/home/bec_history.lua"))().prune(JOURNAL..(suffix or ".stopped-"),2)
 suffix=suffix or ".stopped-" local index=1 while fs.exists(JOURNAL..suffix..index) do index=index+1 end local backup=JOURNAL..suffix..index
assert(fs.rename(JOURNAL,backup),"旧常驻日志归档失败") local f=assert(io.open(backup,"r"));local actual=f:read("*a");f:close() assert(actual==contents and not fs.exists(JOURNAL),"旧常驻日志归档验证失败") end local function field() assert(call(STORAGE, "isWorkAllowed") == true, "约束场必须保持开启") local v = call(STORAGE, "getStoredCondensate") assert(type(v) == "table", "凝聚物库存不可读")
for _, n in pairs(v) do integer(n) end return v end local function writeVerified(path, contents) local f = assert(io.open(path, "w")) local ok, err = f:write(contents) local flushed, flushErr = f:flush() f:close()
assert(ok and flushed, tostring(err or flushErr or "日志写入失败")) local r = assert(io.open(path, "r")) local actual = r:read("*a"); r:close() assert(actual == contents and type(ser.unserialize(actual)) == "table", "日志回读失败") end local function save(stage) record.stage = stage if fs.exists(JOURNAL) then
local f = assert(io.open(JOURNAL, "r")) local old = f:read("*a"); f:close() writeVerified(JOURNAL .. ".previous", old) end writeVerified(JOURNAL, ser.serialize(record, false)) end local function pause(value) call(RS, "setOutput", sides.top, value)
assert(call(RS, "getOutput", sides.top) == value, "红石输出回读不符") end local function generator(enabled) call(GEN, "setWorkAllowed", enabled) assert(call(GEN, "isWorkAllowed") == enabled, "纠缠装置启停回读不符") end local function switchNanites()
local needed=call(NODE,"getRequiredTier");needed=type(needed)=="table" and needed.tier or needed if type(needed)~="number" then return end
NANITES.ensure({tick=tick,stopping=function() return stopping end}) local provided=call(NODE,"getProvidedTier")
assert(type(provided)=="table" and provided.tier>=needed and integer(call(NODE,"getAvailableNanites"))>=64,"蜂群等级或数量不足，保持暂停") lastNaniteTier=needed
end local function gateFilters(required) assert(type(required)=="table","门过滤需求不可读") local result={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0,"门过滤需求无效: "..tostring(name)) result[#result+1]=name
end table.sort(result) assert(#result>0,"禁止写入全空过滤；全空会放行全部凝聚物") return result end local function verifyGate(expected) local count=integer(call(GATE,"getCondensateFilterCount")) assert(count>=#expected,"麦克斯韦门过滤槽不足")
local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table" and same(actual,expected), "麦克斯韦门过滤回读不符；检查门的流体输入仓是否自动覆盖 OC 过滤") assert(call(GATE,"isWorkAllowed")==true,"麦克斯韦门未启用，保持暂停") assert(call(GATE,"isMachineActive")==true,"麦克斯韦门未运行；检查结构和供电，保持暂停") end local function configureGate(required) assert(call(RS,"getOutput",sides.top)==15 and call(NODE,"getState")=="paused-immediate",
"切换门过滤前节点必须立即暂停") local expected=gateFilters(required) assert(integer(call(GATE,"getCondensateFilterCount"))>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table","麦克斯韦门过滤不可读") record.gateIntent={address=GATE,filters=expected};save(record.stage) if not same(actual,expected) then call(GATE,"setCondensateFilters",expected) end for i=1,3 do
verifyGate(expected) assert(call(NODE,"getState")=="paused-immediate","设置过滤时订单状态变化") if i<3 then tick(0.1) end end print("麦克斯韦门过滤: "..table.concat(expected,", ")) return expected end local function tanks(side, name)
local count, amount = integer(call(TRANS, "getTankCount", side)), 0 assert(count > 0, "接口没有流体槽") for i = 1, count do local f = call(TRANS, "getFluidInTank", side, i) assert(type(f) == "table", "接口缓存不可读") if type(f[1]) == "table" then f = f[i] or f[1] end local n = integer(f.amount or 0) if n > 0 then
assert(name and f.name == name, "接口有未处理流体缓存") amount = amount + n end end return amount end local function emptyConfig() for slot = 0, 5 do
assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置") end end local function current(recovering) local state=call(NODE,"getState") local unavailable=state=="assembler-offline" or state=="unpowered" or state=="nanite-tier-too-low" assert(state=="paused-immediate" or (recovering and unavailable and call(RS,"getOutput",sides.top)==15),"订单未处于立即暂停状态")
local parallel=integer(call(NODE, "getParallelRecipesInProgress")) assert(parallel>=1,"暂停节点没有正在处理的配方") local required, consumed = call(NODE, "getRequiredCondensate"), call(NODE, "getConsumedCondensate") assert(type(required) == "table" and type(consumed) == "table", "订单需求不可读") local remaining, total = {}, 0 for name, amount in pairs(required) do assert(mapping[name], "不支持的凝聚物: " .. tostring(name)) amount = integer(amount)
local used = integer(consumed[name] or 0) assert(used <= amount, "已消耗数量超过需求") remaining[name] = amount - used; total = total + amount end assert(total > 0, "订单没有有效需求") for name, amount in pairs(consumed) do assert(integer(amount) == 0 or required[name], "消耗记录与当前订单不符") end
checkRecipe(required,parallel) return required, remaining end local function queuedRecipes() local cpus=call(MAIN,"getCpus") assert(type(cpus)=="table","主网 CPU 清单不可读") local total=0 for _,row in pairs(cpus) do
if row.busy==true then assert(row.cpu~=nil,"主网 CPU 不提供任务对象，无法读取整批数量") for _,getter in ipairs({"activeItems","pendingItems"}) do local items=row.cpu[getter]() assert(type(items)=="table","主网剩余任务不可读: "..getter) for _,item in pairs(items) do for _,out in ipairs(matchedOutputs or {{name="gregtech:gt.metaitem.03",damage=32307,size=1}}) do if item.name==out.name and tonumber(item.damage or 0)==tonumber(out.damage or 0) then
assert(not out.hasTag and not item.hasTag,"带NBT产物不能用于整批计数") total=total+integer(item.size or item.amount or 0)/math.max(1,integer(out.size or out.amount or 1)) break end end end end end
end return math.ceil(total) end -- BEC_V1_ORDER_WINDOW_V1
local function batchTarget(required,remaining,queueHint)
  local parallel=checkRecipe(required)
  local queued=math.max(parallel,queueHint or queuedRecipes())
  local count=queued
  -- Bound the prepared window, not the AE order. Align the raw-fluid ceiling.
  for name in pairs(required) do
    local unit=units[name] or 144
    local limit=math.floor(2147483647/unit)*unit
    local now=integer(remaining[name])
    assert(now<=limit,'当前实际并行单轮需求超过单次供液上限: '..name..' / '..now..' mB；请降低机器最大并行')
    local per=perRecipe[name]
    assert(type(per)=='number' and per>0,'单配方需求不可读: '..name)
    count=math.min(count,parallel+math.floor((limit-now)/per))
  end
  local target={}
  for name in pairs(required) do
    target[name]=remaining[name]+perRecipe[name]*(count-parallel)
  end
  return target,count,queued
end
local function needsRefill(required,consumed,stock,queueHint)
  local remaining={}
  for name,amount in pairs(required) do
    local used=integer(consumed[name] or 0)
    assert(used<=amount,'当前消耗超过本轮需求: '..name)
    remaining[name]=amount-used
  end
  local window,count=batchTarget(required,remaining,queueHint)
  local parallel=checkRecipe(required)
  local ahead=math.min(parallel,math.max(0,count-parallel))
  for name in pairs(required) do
    -- Keep one following physical batch ready. Do not pause to refill the
    -- entire large queue after every completed recipe or small stock change.
    local low=math.min(window[name],remaining[name]+perRecipe[name]*ahead)
    if (stock[name] or 0)<low then return true end
  end
  return false
end
local function unchanged() local req, remaining = current() assert(same(req, record.required) and same(remaining, record.remaining), "暂停订单发生变化，停止")
end local function resolveRawNames(target) local main,sub,stock=network(MAIN),network(SUB),field() for kind,need in pairs(target) do if kind=="entangled_space" or kind=="entangled_time" then local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" local candidates={[stem]=true,["molten."..stem]=true,["fluid."..stem]=true,["fluid.molten."..stem]=true} local found={}
for name in pairs(candidates) do if (main[name] or 0)>0 or (sub[name] or 0)>0 then found[name]=true end local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败") for _,craft in pairs(rows) do local f=craft.getStack() if type(f)=="table" and f.name==name then found[name]=true end end
end local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"空间/时间原液名称不唯一: "..kind) assert(n==1 or (stock[kind] or 0)>=need,"主网缺少空间/时间原液库存或样板: "..kind) if n==1 then mapping[kind]=name end end end end
local function plan(remaining,quiet) resolveRawNames(remaining) local stock, sub, main = field(), network(SUB), network(MAIN) local moves, expected, allowed, shortages, deficits = {}, {}, {}, {}, {} for name, need in pairs(remaining) do local raw = mapping[name] allowed[raw] = true local unit=units[name] or 144
local required = math.ceil(math.max(0, need - (stock[name] or 0)) / unit) * unit local existing = sub[raw] or 0 assert(existing <= required and existing % unit == 0, "子网原液超额或非整批: " .. raw) local missing = required - existing if (main[raw] or 0)<missing then deficits[#deficits+1]={raw=raw,amount=missing-(main[raw] or 0),needed=missing} shortages[#shortages+1]=raw..": 本次需补 "..missing.." mB，主网有 "..(main[raw] or 0) .."，还缺 "..(missing-(main[raw] or 0)).." mB"
end if required > 0 then expected[raw] = required end local left=missing while left>0 do local chunk=math.min(left,math.floor(16000/unit)*unit) moves[#moves+1]={raw=raw,amount=chunk};left=left-chunk end if not quiet then print(raw .. " 本次补入 " .. missing .. " mB") end
end for raw in pairs(sub) do assert(allowed[raw], "子网有无关原液: " .. raw) end for name, amount in pairs(stock) do assert(amount == 0 or mapping[name], "约束场有未知凝聚物: " .. name) end table.sort(moves, function(a,b) return a.raw < b.raw end) if #shortages>0 then table.sort(shortages)
local message=table.concat(shortages,"；") if not quiet then print("缺料: "..message.."；运行时向主网 AE 申请缺口") end table.sort(deficits,function(a,b) return a.raw<b.raw end) return nil,message,deficits end return moves, sub, expected end local function waitUntil(seconds, condition, guard)
local deadline = computer.uptime() + seconds while true do local ready, snapshot = condition() if ready then return end if guard then guard(snapshot) end assert(computer.uptime() < deadline, "等待超时，停止") os.sleep(0.25) end
end local function bulkPorts() local allowed,ports={},{} for _,raw in pairs(mapping) do allowed[raw]=true end for address,kind in c.list("transposer") do if kind=="transposer" and address~=TRANS then local sources,receivers={},{} for side=0,5 do
local ok,count=pcall(call,address,"getTankCount",side) if ok and count==1 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==2147483647 then local f=call(address,"getFluidInTank",side,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end if type(f)=="table" and allowed[f.name] then sources[#sources+1]={from=side,raw=f.name} end end
elseif ok and count==6 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==16000 then receivers[#receivers+1]=side end end end if #sources>0 then assert(#receivers==1,"高速供液口接收方向缺失或不唯一: "..address) for _,source in ipairs(sources) do
assert(not ports[source.raw],"高速供液口重复绑定: "..source.raw) ports[source.raw]={address=address,from=source.from,to=receivers[1]} end end end end return ports end
local function verifyBulk(route,raw) local f=call(route.address,"getFluidInTank",route.from,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end assert(type(f)=="table" and f.name==raw and call(route.address,"getTankCapacity",route.from,1)==2147483647,"高速缓存口绑定已变化") assert(call(route.address,"getTankCount",route.to)==6,"高速接收接口已变化") for i=1,6 do local tank=call(route.address,"getFluidInTank",route.to,i)
if type(tank)=="table" and type(tank[1])=="table" then tank=tank[i] or tank[1] end assert(type(tank)=="table" and integer(tank.amount or 0)==0,"高速接收接口有未处理缓存") end end local function prepareStreaming(target) resolveRawNames(target) local ports=bulkPorts() local stock,previous=field(),network(SUB)
local expected,raws={},{} for name,need in pairs(target) do local raw=mapping[name] local batch=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0 assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end
raws[#raws+1]={raw=raw,amount=amount,batch=batch} end for raw in pairs(previous) do local allowed=false for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end
table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned") for _,item in ipairs(raws) do local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw] local chunk=math.floor((route and 2147483647 or 16000)/batch)*batch local function bufferedInlet() return route and 0 or tanks(4,raw) end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=route==nil;save("stream-configuring") if route then verifyBulk(route,raw) print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to) else assert(call(MAIN,"setFluidInterfaceConfiguration",0, {name=raw,amount=math.min(need-(previous[raw] or 0),chunk),
size=math.min(need-(previous[raw] or 0),chunk)})==true,"持续供液配置失败") end print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt local attempts=0 local inletOpen=route==nil local deadline=computer.uptime()+1800 while not stopping do
unchanged();assert(same(field(),stock),"备料时约束场库存变化") assert(same(network(SUB),previous),"备料时子网库存变化") local remaining=need-(previous[raw] or 0) local buffered=route and (network(MAIN)[raw] or 0) or bufferedInlet() local amount=math.floor(math.min(remaining,buffered,chunk)/batch)*batch if amount>0 then local address,from,to=TRANS,4,5 if route then verifyBulk(route,raw);address,from,to=route.address,route.from,route.to end
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to} save("transfer-returned") assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试") previous[raw]=(previous[raw] or 0)+amount waitUntil(10,function() return same(network(SUB),previous) end,unchanged) record.pending=nil;record.secured=previous;save("stream-transfer-confirmed")
print(raw.." 已入子网 "..previous[raw].." / "..need.." mB") deadline=computer.uptime()+1800 end remaining=need-(previous[raw] or 0) if remaining==0 and inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;inletOpen=false;save("stream-inlet-cleared") waitUntil(20,function() return tanks(4,raw)==0 end,unchanged)
end local priority=false
-- BEC_V1_SEQUENTIAL_CPU_WAIT_V1: keep both production fallback and cache alive while CPUs are occupied.
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
if priority and (not job or job.state=='done' or job.state=='rejected')then return handoff()end
if remaining==0 and (not job or job.state=='done' or job.state=='rejected')then record.supplyWait=nil;break end
if not priority and remaining>0 and (not job or job.state=='done' or job.state=='rejected')then
 local function deficit()return math.max(0,need-(previous[raw]or 0)-tanks(4,raw)-(network(MAIN)[raw]or 0))end
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

tick(0.1) end if inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;save("stream-inlet-cleared") end waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) if stopping then return expected end
end end assert(same(network(SUB),expected),"整批子网原液不符") record.plan=nil;save("stream-prepared") return expected end
local serviceNaniteStage
-- BEC_V1_PRODUCTION_OVERLAP_V3: overlap independent AE jobs and conversion on bulk routes.
local sequentialPrepare=prepareStreaming
prepareStreaming=function(target)
 resolveRawNames(target)
 local ports,base,held=bulkPorts(),field(),network(SUB)
 for name,n in pairs(base) do assert(n==0 or mapping[name],"约束场有未知凝聚物") end
 local items,allowed,expected={},{},{}
 for name,need in pairs(target) do
  local raw,batch=mapping[name],units[name] or 144
  local amount=math.ceil(math.max(0,need-(base[name] or 0))/batch)*batch
  if amount>(held[raw] or 0) and not ports[raw] then
   print("缺少独立高速口，保留原顺序备料: "..raw)
   return sequentialPrepare(target)
  end
  assert((held[raw] or 0)<=amount and (held[raw] or 0)%batch==0,"子网原液超额或非整批: "..raw)
  allowed[raw]=true
  if amount>0 then expected[raw]=amount end
  items[#items+1]={raw=raw,name=name,amount=amount,batch=batch,initial=held[raw] or 0,delivered=0,attempts=0}
 end
 for raw in pairs(held) do assert(allowed[raw],"子网有无关原液: "..raw) end
 table.sort(items,function(a,b)return a.raw<b.raw end)
 unchanged();emptyConfig();tanks(4,nil);tanks(5,nil)
 assert(call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"流水备料开始前纠缠装置须停机")
 record.pipeline={base=base,initial=held,delivered={}}
 local recipe={};checkRecipe(record.required)
 for name,n in pairs(perRecipe) do recipe[name]=n end
 record.pipeline.recipe=recipe;record.pipeline.startConsumed={}
 for name,n in pairs(record.required) do record.pipeline.startConsumed[name]=n-record.remaining[name] end
 local halted,released=false,false
 local releasedAt;local lastFeedback;local feedbackAt=0
 local lastRequired=record.required
 local tierMethod=c.methods(NODE).getRequiredTier~=nil
 local function tierValue()local t=call(NODE,"getRequiredTier");return type(t)=="table" and t.tier or t end
 local neededTier=tierMethod and tierValue()
 local function productionGuard()
  serviceNaniteStage()

  if record.gateIntent then verifyGate(record.gateIntent.filters) end
  local state=call(NODE,"getState")
  local req=call(NODE,"getRequiredCondensate")
  local parallel=call(NODE,"getParallelRecipesInProgress")
  local normalized={}
  if type(req)=="table" and type(parallel)=="number" and parallel>0 then
   for name,n in pairs(req) do normalized[name]=integer(n)/parallel end
  end
  local changed=not same(normalized,recipe)
  local reason=changed and "配方需求变化，等待旧窗口收尾" or nil
  local tierCovered=false
  if not changed and tierMethod then
   local nextTier=tierValue()
   if nextTier~=neededTier or state=="nanite-tier-too-low" then
    local provided=call(NODE,"getProvidedTier")
    local count=call(NODE,"getAvailableNanites")
    tierCovered=type(nextTier)=="number" and type(provided)=="table" and type(provided.tier)=="number"
     and provided.tier>=nextTier and type(count)=="number" and count>=64
    if tierCovered then
     neededTier=nextTier
    else neededTier=nextTier;tierCovered=true end
   end
  end
  if state~="crafting" and state~="paused-immediate" and not(state=="nanite-tier-too-low" and tierCovered) then
   changed=true;reason=reason or ("节点状态: "..tostring(state))
  end
  if released and releasedAt and computer.uptime()-releasedAt>=3 then
   local output=call(RS,"getOutput",sides.top)
   local feedback
   if output~=0 then
    feedback="本脚本已放行，但暂停输出被改为 "..tostring(output).."；检查其他运行脚本或红石控制"
   elseif state=="paused-immediate" then
    feedback="本脚本暂停输出=0，节点仍立即暂停；检查其他控制仓收到的红石信号"
   end
   if feedback and (feedback~=lastFeedback or computer.uptime()>=feedbackAt) then
    print("放行核对: "..feedback)
    record.pipeline.feedback={reason=feedback,output=output,state=state,at=computer.uptime()}
    save(record.stage);lastFeedback=feedback;feedbackAt=computer.uptime()+15
   elseif not feedback then lastFeedback=nil;record.pipeline.feedback=nil end
  end
  if changed then
   if not halted then print("生产暂停: "..reason.."；已提交的供液申请继续核对，不重复下单。") end
   pause(15);released=false;halted=true
   if state=="idle" and record.pipeline.overlap then
    local used=call(NODE,"getConsumedCondensate");assert(type(used)=="table","节点空闲后消耗记录不可读")
    for name,n in pairs(lastRequired)do assert(integer(used[name] or 0)>=n,"节点进入空闲但凝聚物未消耗完: "..name)end
   end
  else
   lastRequired=req
  end
  return req
 end
 local plans={};for _,item in ipairs(items) do plans[#plans+1]={raw=item.raw,name=item.name,amount=item.amount,batch=item.batch} end
 record.plan=plans;record.expected=expected;record.secured=held;save("pipeline-planned")
 local converting=false
 local deadline=computer.uptime()+1800
 for _,item in ipairs(items) do deadline=deadline+math.ceil(item.amount/item.batch)*180 end
 local function jobsAndRequests()
  -- BEC_V1_CPU_WAIT_V1: wait for free CPUs; proven rejected requests use manual supply.
  local waits={};local waiting=false
  local function cpus()
   local ok,rows=pcall(call,MAIN,"getCpus")
   local info={free=0,busy=0,total=0,known=0,maxFree=0,maxBusy=0,max=0}
   if not ok or type(rows)~="table" then info.unknown=true;return info end
   for _,cpu in pairs(rows) do
    info.total=info.total+1
    if type(cpu)~="table" or type(cpu.busy)~="boolean" then info.unknown=true
    else
     if cpu.busy then info.busy=info.busy+1 else info.free=info.free+1 end
     local storage=cpu.storage
     if type(storage)=="number" and storage>=0 then
      info.known=info.known+1;info.max=math.max(info.max,storage)
      if cpu.busy then info.maxBusy=math.max(info.maxBusy,storage)
      else info.maxFree=math.max(info.maxFree,storage) end
     end
    end
   end
   return info
  end
  local function capacityFailure(reason)
   local s=tostring(reason):lower()
   return s:find("insufficient storage",1,true) or s:find("not enough storage",1,true)
    or s:find("storage too small",1,true) or s:find("insufficient capacity",1,true)
    or s:find("容量不足",1,true)
  end
  local function wait(item,reason,info)
   waiting=true
   waits[item.raw]={reason=reason,free=info and info.free,busy=info and info.busy,
    maxFree=info and info.maxFree,maxBusy=info and info.maxBusy,maxStorage=info and info.max}
  end
  -- Each deficit is independent: a rejected request cannot block other fluids.
  for _,item in ipairs(items) do
   if stopping then return true end
   local job,status=item.job,item.status
   if job and job.state=="submitted" then
    local computing
    if type(status.isComputing)=="function" then computing=status.isComputing() end
    local failed,why
    if type(status.hasFailed)=="function" then failed,why=status.hasFailed() end
    if computing==false and failed==true then
     job.state="rejected";job.preSubmissionFailed=true;job.failure=tostring(why)
     job.manualSupply=true;item.status=nil
     save("pipeline-request-rejected")
    elseif computing==true then
     wait(item,"AE 正在计算合成计划")
    else
     local canceled,why=status.isCanceled()
     assert(canceled==false,"主网原液申请失败/取消（未证实未启动，不重复下单）: "..tostring(why))
     local done=status.isDone();assert(type(done)=="boolean","AE 状态不可读")
     if done then job.state="done";item.doneAt=computer.uptime();save("pipeline-craft-done")
     else wait(item,"AE 合成进行中，继续收料") end
    end
   end
   local remaining=item.amount-item.initial-item.delivered
   if remaining>0 and (not job or job.state=="done" or job.state=="rejected")
    and (not item.doneAt or computer.uptime()-item.doneAt>=3) then
    local missing=math.max(0,remaining-(network(MAIN)[item.raw] or 0))
    if missing>0 then
     if job and job.state=="done" then
      assert(item.delivered>job.securedBefore,"原液合成已结束但没有收获，暂停核对竞争设备")
     end
     local info=cpus()
     local reason
     if job and job.state=="rejected" then
      if info.unknown then reason="申请未成功；CPU 状态暂不可读"
      elseif info.busy>0 then reason="申请未成功，CPU 被占用或容量/原料不足"
      elseif capacityFailure(job.failure) then reason="CPU 容量不足：AE 拒绝了这笔申请"
      else reason="AE 未启动申请：容量或原料待核对" end
      reason=reason.."；请在 ME 手动申请 "..missing.." mB；自动收料继续"
     elseif info.unknown then reason="等待 CPU 状态恢复可读"
     elseif info.total==0 or (info.known==info.total and info.max==0) then reason="CPU 容量不足：没有可用合成存储"
     elseif info.free==0 then reason="等待合成 CPU 空闲，其他供液与生产继续"
     end
     if reason then
      wait(item,reason,info)
      waits[item.raw].amount=missing;waits[item.raw].manual=job and job.manualSupply or nil
      waits[item.raw].failure=job and job.failure or nil
     end
     if not(job and job.manualSupply) and not info.unknown and info.free>0
      and not(info.known==info.total and info.max==0) then
      if not item.craft then
       local rows=call(MAIN,"getCraftables",{name=item.raw});assert(type(rows)=="table","原液配方不可读")
       local count=0;for _,craft in pairs(rows) do item.craft=craft;count=count+1 end
       assert(count==1,"原液配方缺失或不唯一: "..item.raw)
       local f=item.craft.getStack()
       assert(type(f)=="table" and f.name==item.raw and f.isCraftable==true and type(f.amount)=="number" and f.amount==f.size and f.hasTag==false,"未验证的流体合成对象")
      end
      missing=math.max(0,remaining-(network(MAIN)[item.raw] or 0))
      if missing>0 then
       item.attempts=item.attempts+1;assert(item.attempts<=3,"原液仍被争抢，保留已收获库存")
       job={raw=item.raw,unit="mB"};record.requests[#record.requests+1]=job
       job.amount=missing;job.state="pending";job.securedBefore=item.delivered
       item.job=job;save("craft-request-pending")
       local newStatus,why=item.craft.request(missing)
       assert(newStatus~=nil,"AE 申请未确认: "..tostring(why))
       item.status=newStatus;job.state="submitted";item.doneAt=nil
       save("pipeline-crafting");print("并行 AE 申请 "..item.raw.." "..missing.." mB")
       wait(item,"AE 正在计算合成计划",info)
      end
     end
    end
   end
  end
  local lines={}
  for raw,row in pairs(waits) do lines[#lines+1]={text=raw..": "..row.reason,
   urgent=row.reason:find("手动申请",1,true) or row.reason:find("容量不足",1,true)} end
  table.sort(lines,function(a,b)if not not a.urgent~=not not b.urgent then return not not a.urgent end;return a.text<b.text end)
  for i,row in ipairs(lines)do lines[i]=row.text end
  local summary=table.concat(lines,"；")
  if summary~=record.pipeline.cpuWaitSummary then
   record.pipeline.cpuWait=waits;record.pipeline.cpuWaitSummary=summary
   save(record.stage)
   if summary~="" then print("供液等待: "..summary) end
  end
  return waiting
 end

 while not stopping do
  productionGuard();local cpuWaiting=jobsAndRequests();if cpuWaiting then deadline=math.max(deadline,computer.uptime()+1800) end;if stopping then break end
  for _,item in ipairs(items) do
   if stopping then break end
   local remaining=item.amount-item.initial-item.delivered
   local amount=remaining>0 and math.floor(math.min(remaining,network(MAIN)[item.raw] or 0,2147483647)/item.batch)*item.batch or 0
   if amount>0 then
    local route=assert(ports[item.raw]);verifyBulk(route,item.raw);productionGuard()
    record.pending={raw=item.raw,amount=amount,address=route.address,from=route.from,to=route.to};save("transfer-pending")
    local ok,moved=call(route.address,"transferFluid",route.from,route.to,amount)
    record.transfers[#record.transfers+1]={raw=item.raw,ok=ok,amount=moved,requested=amount,address=route.address,from=route.from,to=route.to}
    save("transfer-returned");assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试")
    item.delivered=item.delivered+amount;record.pipeline.delivered[item.raw]=item.delivered
    record.pending=nil;save("pipeline-transfer-confirmed")
   end
  end
  if stopping then break end
  -- Read field before sub: conversion between reads can only lower this sum.
  local stock,sub=field(),network(SUB)
  for raw in pairs(sub) do assert(allowed[raw],"流水备料子网出现无关原液") end
  for name,n in pairs(base) do if not recipe[name] then assert((stock[name] or 0)==n,"无关凝聚物库存变化") end end
  local ready,hasRaw=true,false
  for _,item in ipairs(items) do
   local supplied=item.initial+item.delivered
   local liquid=integer(sub[item.raw] or 0);local condensate=integer(stock[item.name] or 0)
   assert(liquid+condensate<=supplied+(base[item.name] or 0),"流水备料库存超过已确认搬入量: "..item.raw)
   hasRaw=hasRaw or liquid>0
   if supplied<item.amount or liquid>0 or (item.job and item.job.state~="done" and not(item.job.state=="rejected" and item.job.preSubmissionFailed==true)) then ready=false end
  end
  local req=productionGuard()
  local funded=not halted
  local shortages={}
  if funded then
   local consumed=call(NODE,"getConsumedCondensate")
   assert(type(consumed)=="table","当前消耗记录不可读")
   for name,n in pairs(req) do
    local used=integer(consumed[name] or 0);assert(used<=n,"节点消耗超过当前需求")
    if (stock[name] or 0)<n-used then
     funded=false;shortages[#shortages+1]=name.." 缺 "..(n-used-(stock[name] or 0)).." mB"
    end
   end
  end
  if funded and not released then
   checkRecipe(req)
   record.pipeline.overlap=true;save("pipeline-production-release-pending")
   local releaseReq=productionGuard()
   if not halted and same(releaseReq,req) then pause(0);released=true;releasedAt=computer.uptime();save("pipeline-producing")
    print("当前配方材料已够，暂停输出已设0；节点运行状态持续核对，其余供液纠缠继续。") end
  elseif not funded and released then
   pause(15);released=false;save("pipeline-waiting-material")
   if #shortages>0 then print("生产等料: "..table.concat(shortages,"；").."；供液纠缠继续。") end
  end
  if ready and (halted or not funded) and (not converting or call(GEN,"isMachineActive")==false) then
   pause(15)
   if converting then generator(false) end
   record.plan=nil;record.pipeline=nil;record.productionOverlapHandled=true;record.expected={};record.secured={}
   save("stream-prepared");return {}
  end
  if hasRaw and not converting then
   productionGuard();save("pipeline-converting");generator(true);converting=true
   print("原液已到货，边收料边纠缠；当前配方够料即生产。")
  end
  assert(computer.uptime()<deadline,"流水备料超时，保留全部申请和搬液记录")
  tick(0.1)
 end
 return expected
end

-- BEC_V1_FAST_CYCLE_V1: batch IO reads and single-pass stage decisions.
-- BEC_V1_NANITES_STAGE_V2: let the node stall itself; exchange bees live.
local stageBusy=false
local stageSignature,stageCheckAt
local stageWorker
local originalStageTick=tick
serviceNaniteStage=function()
 if stageBusy or stopping or not record then return end
 local overlapping=record.pipeline and record.pipeline.overlap
 if record.stage~="watching" and not overlapping then return end
 local state=call(NODE,"getState")
 if state~="crafting" and state~="paused-immediate" and state~="nanite-tier-too-low" then return end
 local req=call(NODE,"getRequiredCondensate")
 local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)~="table" or type(parallel)~="number" or parallel<1 then return end
 local normalized={};for name,n in pairs(req)do normalized[name]=integer(n)/parallel end
 local expected=overlapping and record.pipeline.recipe or perRecipe
 if not same(normalized,expected) then return end
 local required=call(NODE,"getRequiredTier")
 if type(required)~="table" or type(required.tier)~="number" then return end
 local signature=tostring(required.name)..":"..required.tier
 if signature==stageSignature and computer.uptime()<(stageCheckAt or 0) then return end
 if not stageWorker then
  local loader=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")
  stageWorker=loader()
  assert(type(stageWorker)=="table" and type(stageWorker.needsSwitch)=="function" and stageWorker.passiveStages,
   "请先安装新版自动停顿换蜂模块")
 end
 stageSignature=signature;stageCheckAt=computer.uptime()+0.5
 if not stageWorker.fastStages then error("蜂群模块版本不匹配") end
 local current=call(NODE,"getProvidedTier");local count=call(NODE,"getAvailableNanites")
 if type(current)=="table" and current.name==required.name and current.tier==required.tier and type(count)=="number" and count>=64 then return end
 stageBusy=true
 local ok,reason=xpcall(function()
  -- Stage and consumption may advance while compatible bees keep working.
  -- Do not freeze those hints or drive node/GEN outputs to exchange bees.
  local function checked()
   if record.gateIntent then verifyGate(record.gateIntent.filters) end
  end
  local announced=false
  local function announce()
   checked();record.naniteStage={required=required,stage="switching"};save(record.stage)
   print("阶段换蜂：优先对应库存；等级不足由节点自动停顿");announced=true
  end
  stageWorker.ensure({passive=true,stage=true,beforeAction=announce,check=checked,tick=originalStageTick,stopping=function()return stopping end})
  checked()
  if announced then record.naniteStage=nil;save(record.stage) end
  local latest=call(NODE,"getRequiredTier")
  if type(latest)=="table" and latest.tier==required.tier and latest.name==required.name then
   stageSignature=signature;stageCheckAt=computer.uptime()+0.5
  else stageSignature=nil;stageCheckAt=0 end
 end,debug.traceback)
 stageBusy=false
 if not ok then error(reason) end
end
tick=function(seconds)
 originalStageTick(seconds)
 if not stopping then serviceNaniteStage() end
end

-- BEC_V1_BATCH_STOP_V1: latch work off before releasing each physical batch.
local function batchControlAddress(component)
 local candidates={}
 for address in component.list() do
  local methods=component.methods(address)
  if methods.getRequiredCondensate~=nil and methods.getParallelRecipesInProgress~=nil
   and methods.getState~=nil and methods.setWorkAllowed~=nil and methods.isWorkAllowed~=nil then
   candidates[#candidates+1]=address
  end
 end
 assert(#candidates==1,"需要唯一可启停的传送节点组件；请用适配器连接节点并提供 gt_machine（当前找到 "..#candidates.." 个）")
 return candidates[1]
end

local batchControl
local batchControlVerified=false
local function batchWork(enabled)
 batchControl=batchControl or batchControlAddress(c)
 if batchControlVerified and call(batchControl,"isWorkAllowed")==enabled then return end
 -- The generic gt_machine and bec_io_node must refer to the same physical node.
 assert(call(batchControl,"getState")==call(NODE,"getState"),"启停组件与传送节点状态不一致")
 assert(call(batchControl,"getParallelRecipesInProgress")==call(NODE,"getParallelRecipesInProgress"),"启停组件与节点并行不一致")
 local a,b=call(batchControl,"getRequiredCondensate"),call(NODE,"getRequiredCondensate")
 assert((a==nil and b==nil) or (type(a)=="table" and type(b)=="table" and same(a,b)),"启停组件与节点配方不一致")
 batchControlVerified=true
 if call(batchControl,"isWorkAllowed")~=enabled then
  record.batchStop={control=batchControl,enabled=enabled,phase="pending"};save(record.stage)
  call(batchControl,"setWorkAllowed",enabled)
  assert(call(batchControl,"isWorkAllowed")==enabled,"传送节点启停回读不符")
  record.batchStop.phase="confirmed";save(record.stage)
 end
end
local function batchBetween()
 -- Immediate pause is set before allowing an idle node to accept the next recipe.
 assert(call(RS,"getOutput",sides.top)==15,"接收下一批前必须立即暂停")
 batchWork(call(NODE,"getState")=="idle")
end
local continuousBatchPrepare=prepareStreaming
prepareStreaming=function(target)
 -- Beta 3 finishes the active batch with workAllowed=false but skips checkRecipe.
 batchWork(false)
 return continuousBatchPrepare(target)
end
local continuousBatchPause=pause
pause=function(value)
 if value==0 then batchWork(false) end
 return continuousBatchPause(value)
end

local function serve() local waiting={idle=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
local round=0 local nextCache=0 local function idleCache(state) if computer.uptime()<nextCache then return end nextCache=computer.uptime()+2 local pending=io.open("/home/bec_cache.journal","r") local old if pending then old=ser.unserialize(pending:read("*a"));pending:close() end
local incomplete=type(old)=="table" and old.background and old.incomplete -- BEC_V1_IDLE_CACHE_FAST_V2
if state~="idle" and not incomplete then
 local safe={['assembler-offline']=true,unpowered=true,['nanite-tier-too-low']=true,['paused-immediate']=true}
 if not safe[state] then return end
 local req=call(NODE,"getRequiredCondensate")
 if type(req)=="table" and next(req)~=nil then return end
end local input=io.open("/home/bec_cache.config","r") local settings if input then settings=ser.unserialize(input:read("*a"));input:close() end if not settings and not incomplete then if not fs.exists("/home/bec/recipes") then return end settings={version=1,target=144000}
end assert(not settings or (type(settings)=="table" and settings.version==1),"缓存配置无效") local target=incomplete and old.fixedStock or settings.target assert(type(target)=="number" and target>=1 and target==math.floor(target),"缓存配置无效") local worker,reason=loadfile("/home/bec_cache.lua","t",_ENV) assert(worker,"缺少后台缓存脚本："..tostring(reason)) waitUntil(190,function() return call(GEN,"isMachineActive")==false end) save("cache-working")
local ok,err=worker("background-stock",target) assert(ok,"后台缓存停止："..tostring(err)) record.lastState=nil;save("waiting") tick(0.1) end while not stopping do pause(15); generator(false) batchBetween()
    local state=call(NODE,"getState")
idleCache(state) if stopping then break end state=call(NODE,"getState") if state=="paused-immediate" or state=="nanite-tier-too-low" then switchNanites();state=call(NODE,"getState") end if waiting[state] then if state~=record.lastState then print("等待订单/机器就绪: "..state.."；任意数量同配方订单均可，按 Q 停止。") record.lastState=state;save("waiting") end
field();tick(0.1) else waitUntil(10,function() local v=call(NODE,"getState") return v=="paused-immediate",v end,function(v) assert(v=="crafting" or waiting[v],"无法暂停，实际状态: "..tostring(v)) field()
end) switchNanites();if stopping then break end record.required,record.remaining=current() local target,count=batchTarget(record.required,record.remaining) local stable=false for i=1,100 do tick(0.05);unchanged() local nextTarget,nextCount=batchTarget(record.required,record.remaining) if same(target,nextTarget) then stable=true;break end
target,count=nextTarget,nextCount end assert(stable,"主网任务清单持续变化，保持暂停") if stopping then break end record.batchCount=count;record.windowed=true print("本轮备料配方 "..count.." 份；当前实际并行 "..checkRecipe(record.required) .."；按安全批量备料，大订单自动接续。") round=round+1;record.round=round;record.transfers={};record.target=target;record.plan=nil;record.topups={}
waitUntil(10,function() return call(GEN,"isMachineActive")==false end) emptyConfig();tanks(4,nil);tanks(5,nil) local filters=configureGate(record.required) unchanged() if stopping then break end local expected=prepareStreaming(target) if record.productionOverlapHandled then record.productionOverlapHandled=nil else  if stopping then break end if record.pipelineComplete then unchanged();assert(next(network(SUB))==nil,"流水转换后子网非空");record.pipelineComplete=nil else for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.05) end end
save("converting");generator(true) local conversionLimit=180 for name,need in pairs(target) do conversionLimit=conversionLimit+math.ceil(need/(units[name] or 144))*180 end waitUntil(conversionLimit,function() local stock=field() for name,need in pairs(target) do if (stock[name] or 0)<need then return false end end return true end,unchanged)
unchanged();generator(false) record.plan=nil;record.lastState=nil;save("watching") if not stopping then verifyGate(filters);unchanged() pause(0) print("本轮备料齐备，已连续放行；库存不足时自动准备下一批。按 Q 停止。") local releasedAt=computer.uptime() local deadline=releasedAt+600
local lastStock=field() local lastRequired=record.required local nextQueueCheck=0 local windowQueue
while not stopping do local v=call(NODE,"getState") local stock=field() local req=call(NODE,"getRequiredCondensate") verifyGate(filters)
local needed=call(NODE,"getRequiredTier");needed=type(needed)=="table" and needed.tier or needed local supplied=call(NODE,"getProvidedTier");local available=call(NODE,"getAvailableNanites")
if type(needed)=="number" and (type(supplied)~="table" or type(supplied.tier)~="number" or supplied.tier<needed or type(available)~="number" or available<64) then pause(15);waitUntil(10,function() local s=call(NODE,"getState");return s=="paused-immediate" or s=="nanite-tier-too-low" end)
switchNanites();if stopping then break end
print("蜂群需求变化，保持暂停，重新核对当前配方过滤和库存。")
break end
local parallel if req~=nil then parallel=integer(call(NODE,"getParallelRecipesInProgress")) local matching=parallel>0 for name,n in pairs(req) do if not perRecipe[name] or n~=perRecipe[name]*parallel then matching=false end end for name in pairs(perRecipe) do if req[name]==nil then matching=false end end if not matching then pause(15);break end if not same(gateFilters(req),filters) then pause(15);break end
lastRequired=req end if v=="idle" then
 pause(15)
 local consumed=call(NODE,"getConsumedCondensate")
 local incomplete=type(consumed)~="table"
 if not incomplete then for name,need in pairs(lastRequired) do
  local used=consumed[name] or 0
  if type(used)~="number" or used<need then incomplete=true end
 end end
 record.lastOutcome={required=lastRequired,consumed=consumed,
  status=incomplete and "unconfirmed-or-skipped" or "consumed"}
 save("waiting")
 if incomplete then print("节点已空闲，旧轮次消耗未确认；记录后继续等待当前订单，不重放旧配方。") end
 break end if waiting[v] then break end assert(v=="crafting" or (v=="paused-immediate" and computer.uptime()-releasedAt<3), "节点运行异常: "..tostring(v)) local refill=false
if req~=nil then
 if computer.uptime()>=nextQueueCheck then windowQueue=queuedRecipes();nextQueueCheck=computer.uptime()+1 end
 local consumed=call(NODE,"getConsumedCondensate")
 assert(type(consumed)=="table","当前消耗记录不可读")
 refill=needsRefill(req,consumed,stock,windowQueue)
 if refill then
  windowQueue=queuedRecipes()
  refill=needsRefill(req,consumed,stock,windowQueue)
 end
end
if refill then break end if not same(stock,lastStock) then deadline=computer.uptime()+600;lastStock=stock end assert(computer.uptime()<deadline,"当前配方运行超时") tick(0.1) end
end end end end pause(15);generator(false);batchWork(false);record.configOwned=false for _,job in ipairs(record.requests) do if job.state~="done" then save("craft-paused") print("服务已暂停；主网原液申请仍需核对，保留日志，不重复下单。")
return end end save("stopped") print("已停止常驻服务：暂停输出 15，纠缠装置关闭；约束场与已有凝聚物保持开启。") end local function main() assert(mode=="preview" or mode=="run" or mode=="resume" or mode=="restock" or mode=="reset", "用法: preview / run / resume / restock / reset，无需填写数量")
RS = resolve("266f65b5", "redstone") GEN = resolve("c1ae3f7c", "gt_machine") GATE = resolve(GATE_ADDRESS, "bec_diode") assert(call(GEN, "getName") == "multi.bec.generator", "纠缠装置名称不符") for _, item in ipairs({{RS,"setOutput"},{RS,"getOutput"},{GEN,"setWorkAllowed"}, {GEN,"isWorkAllowed"},{GEN,"isMachineActive"},{MAIN,"getFluidsInNetwork"}, {MAIN,"setFluidInterfaceConfiguration"},{MAIN,"getFluidInterfaceConfiguration"}, {SUB,"getFluidsInNetwork"},{TRANS,"transferFluid"},
{MAIN,"getCraftables"},{MAIN,"getCpus"},{GATE,"getCondensateFilterCount"}, {GATE,"getCondensateFilters"},{GATE,"setCondensateFilters"}, {GATE,"isWorkAllowed"},{GATE,"isMachineActive"}}) do method(item[1],item[2]) end local minimum,maximum=integer(call(NODE,"getMinParallel")),integer(call(NODE,"getMaxParallel")) assert(minimum>=1 and maximum>=minimum,"节点并行设置无效") print("远端红石: " .. RS .. "；纠缠装置: " .. GEN) print("节点: " .. call(NODE,"getState") .. "；向上输出: " .. call(RS,"getOutput",sides.top)) print("纠缠装置允许工作: " .. tostring(call(GEN,"isWorkAllowed")))
print("麦克斯韦门: "..GATE.."；过滤: "..ser.serialize(call(GATE,"getCondensateFilters"),false) .."；运行: "..tostring(call(GATE,"isMachineActive"))) print("凝聚物库存: " .. ser.serialize(field(),false)) if mode == "preview" then print("子网原液: " .. ser.serialize(network(SUB),false)) if call(NODE,"getState") == "paused-immediate" then local required,remaining=current();local target,count=batchTarget(required,remaining) print("本轮备料配方 "..count.." 份")
plan(target) end print("预览结束：没有开关、搬液、配置或写日志。") return end local waitingStates = {idle=true, ["paused-immediate"]=true, ["assembler-offline"]=true, unpowered=true, ["nanite-tier-too-low"]=true} local initialState = call(NODE,"getState")
assert(waitingStates[initialState], "节点状态不适合启动: " .. tostring(initialState)) emptyConfig(); tanks(4,nil); tanks(5,nil)
-- BEC_V1_NEXT_RECIPE_V1: explicit reset detaches settled historical rounds.
if mode=="reset" then
 assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false
  and call(GEN,"isMachineActive")==false,"重置前保持节点暂停、纠缠装置停机")
 assert(next(network(SUB))==nil,"重置前子网仍有原液，不能忽略在途物料")
 field()
 local archives={}
 for _,entry in ipairs({{JOURNAL,"continuous"},{"/home/bec_cache.journal","cache"}}) do
  local path,kind=entry[1],entry[2]
  if fs.exists(path) then
   local f=assert(io.open(path,"r"));local text=f:read("*a");f:close()
   local old=ser.unserialize(text)
   assert(type(old)=="table" and old.version==1 and old.kind==kind
    and old.pending==nil and old.configOwned==false,"重置日志有未确认操作: "..path)
   assert(type(old.requests)=="table" and type(old.transfers)=="table","重置日志操作清单缺失")
   for _,job in pairs(old.requests) do
    assert(type(job)=="table" and job.state=="done","旧原液申请仍在进行，不重复下单")
   end
   for _,move in pairs(old.transfers) do
    assert(type(move)=="table" and move.ok==true and integer(move.amount)>0
     and move.requested==move.amount,"旧搬液结果未完整确认")
   end
   local n=1;while fs.exists(path..".reset-"..n) do n=n+1 end
   archives[#archives+1]={path=path,backup=path..".reset-"..n,text=text}
  end
 end
 -- Validate both journals before archiving either. No old requests are replayed.
 for _,a in ipairs(archives) do
  assert(fs.rename(a.path,a.backup),"重置日志归档失败: "..a.path)
  local f=assert(io.open(a.backup,"r"));local text=f:read("*a");f:close()
  assert(text==a.text and not fs.exists(a.path),"重置归档回读不符")
  print("旧日志已保留: "..a.backup)
 end
 print("进程已重置，按当前订单和实际库存重新计算；蜂群及已有凝聚物保留。")
 mode="run"
end

if fs.exists(JOURNAL) then local f=assert(io.open(JOURNAL,"r"));local contents=f:read("*a");f:close() local old=ser.unserialize(contents); assert(not(type(old)=="table" and old.naniteStage),"旧阶段换蜂未确认完成，保留蜂群与生产日志，禁止重放")
if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then
 assert(mode=="resume" or mode=="restock","流水未完成，请用resume核对")
 assert(old.pending==nil and old.configOwned==false,"流水存在未确认搬液，保留日志核对")
 for _,job in ipairs(old.requests or {})do assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"原液申请尚未确认完成，禁止重复下单")
  if job.manualSupply then
   local received=integer((old.pipeline.delivered or {})[job.raw] or 0)-integer(job.securedBefore or 0)
   local available=integer(network(MAIN)[job.raw] or 0)
   assert(received+available>=integer(job.amount),"手动补料尚未收齐：继续等待手动任务完成后再恢复，禁止自动重复下单")
  end
end
 for _,move in ipairs(old.transfers or {})do assert(move.ok==true and move.amount==move.requested and integer(move.amount)>0,"搬液未完整确认")end
 assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置停机")
 resolveRawNames(old.target)
 local p=old.pipeline
 assert(type(p.base)=="table" and type(p.initial)=="table" and type(p.delivered)=="table","流水守恒记录缺失")
 local stock,sub=field(),network(SUB);local allowed={};local completed
 local req=call(NODE,"getRequiredCondensate");local consumed=call(NODE,"getConsumedCondensate")
 local normalized={};local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)=="table" and type(parallel)=="number" and parallel>0 then for name,n in pairs(req)do normalized[name]=integer(n)/parallel end end
 -- BEC_V1_IDLE_RECOVERY_V1: Beta 3 keeps the last consumed table when idle.
 local idleRetained=call(NODE,"getState")=="idle" and req==nil and parallel==0
 local sameRecipe=p.recipe and same(normalized,p.recipe)
 local idleAudit
 if idleRetained and p.overlap then
  assert(type(consumed)=="table" and type(old.required)=="table" and type(p.recipe)=="table","空闲末批消耗记录缺失")
  for name,n in pairs(consumed)do
   assert(p.recipe[name]~=nil or integer(n)==0,"空闲消耗有旧配方以外的流体: "..name)
   assert(integer(n)<=integer(old.required[name] or 0),"空闲末批消耗超过已记录需求: "..name)
  end
  idleAudit={kind="idle-retained-consumption",sourceJournal=contents,retainedConsumed=consumed,
   recordedRequired=old.required,field=stock,subnet=sub,missingAgainstRecorded={}}
  for name,n in pairs(old.required)do idleAudit.missingAgainstRecorded[name]=integer(n)-integer(consumed[name] or 0)end
 end
 for _,item in ipairs(old.plan)do
  local raw,name=item.raw,item.name;assert(mapping[name]==raw,"恢复原液映射变化");allowed[raw]=true
  local budget=integer(p.base[name] or 0)+integer(p.initial[raw] or 0)+integer(p.delivered[raw] or 0)
  local loss=budget-integer(stock[name] or 0)-integer(sub[raw] or 0)
  if p.overlap then
   assert(type(p.recipe)=="table" and type(p.startConsumed)=="table" and type(consumed)=="table","并行消耗记录缺失")
   local used=(sameRecipe or idleRetained) and integer(consumed[name] or 0) or 0
   if not sameRecipe and not idleRetained then for _,n in pairs(consumed)do assert(integer(n)==0,"下一配方已有消耗，须核对旧流水")end end
   local batches=(loss+integer(p.startConsumed[name] or 0)-used)/assert(p.recipe[name])
   assert(loss>=0 and batches>=0 and batches%1==0 and (completed==nil or completed==batches),"生产消耗与流水库存不守恒: "..raw)
   completed=batches
  else assert(loss==0,"流水库存不守恒: "..raw)end
 end
 for name,n in pairs(p.base)do if not allowed[mapping[name]]then assert((stock[name] or 0)==n,"无关凝聚物变化")end end
 for raw in pairs(sub)do assert(allowed[raw],"子网有无关原液")end
 -- Drain only confirmed material before archiving; never repeat a request/move.
 local total={};for _,item in ipairs(old.plan)do total[item.name]=integer(stock[item.name] or 0)+integer(sub[item.raw] or 0)end
 local ok,reason=pcall(function()
  if next(sub)~=nil then
   generator(true);local deadline=computer.uptime()+1800
   while next(network(SUB))~=nil or call(GEN,"isMachineActive")==true do
    assert(not stopping and computer.uptime()<deadline,"恢复转换未完成，原日志保留")
    assert(call(RS,"getOutput",sides.top)==15,"恢复转换时节点意外放行")
    field()
    tick(0.1)
   end
  end
  local final=field();for name,n in pairs(total)do assert((final[name] or 0)==n,"恢复转换不守恒")end
 end)
 generator(false);assert(ok,reason)
 if idleAudit then
  -- The retained batch is separate from fully completed prior recipe units.
  -- Never count its partial consumption as delivered products or replay it.
  idleAudit.completedBeforeRetained=completed
  idleAudit.finalField=field()
  local index=1;while fs.exists(JOURNAL..".idle-recovery-"..index)do index=index+1 end
  local auditPath=JOURNAL..".idle-recovery-"..index
  writeVerified(auditPath,ser.serialize(idleAudit,false))
  print("空闲末批消耗核对通过；之前完整消耗 "..tostring(completed).." 份；末批单独记录: "..auditPath)
  print("末批缺口相对原记录: "..ser.serialize(idleAudit.missingAgainstRecorded,false).."；不伪造成品，不重放旧单。")
 end
 old.stage="watching";old.plan=nil;old.pipeline=nil
 print("并行生产消耗核对通过；已确认余液转换完成，按真实库存继续，不重复下单搬液。")
end

local streaming=type(old)=="table" and type(old.plan)=="table" and (old.stage=="stream-configuring" or old.stage=="stream-transfer-confirmed" or old.stage=="stream-inlet-cleared" or old.stage=="stream-planned")
and type(old.secured)=="table" and type(old.target)=="table" assert(type(old)=="table" and old.version==1 and old.kind=="continuous" and old.pending==nil and (old.configOwned==false or streaming),"日志无效或有未确认操作，禁止重跑") if mode=="resume" or mode=="restock" then -- BEC_V1_CACHE_RESUME_V3
if old.stage == "cache-working" then
  assert(old.plan == nil, "缓存恢复：旧生产仍有备料计划，保留日志核对")
  assert(old.pending == nil and old.configOwned == false
    and type(old.requests) == "table" and type(old.transfers) == "table",
    "缓存恢复：旧生产仍有未确认操作，保留日志核对")
  for _, job in pairs(old.requests) do
    assert(type(job) == "table" and job.state == "done", "缓存恢复：旧生产申请未确认完成")
  end
  for _, move in pairs(old.transfers) do
    assert(type(move) == "table" and move.ok == true and type(move.amount) == "number"
      and move.amount > 0 and move.amount == math.floor(move.amount)
      and move.requested == move.amount, "缓存恢复：旧生产搬液未完整确认")
  end
  -- expected/secured describe the prior production round, not live inventory.
  local cf = assert(io.open("/home/bec_cache.journal", "r"), "缓存恢复：缺少缓存日志")
  local cache = ser.unserialize(cf:read("*a")); cf:close()
  assert(type(cache) == "table" and cache.version == 1 and cache.kind == "cache"
    and cache.background == true and cache.stage == "stopped"
    and cache.incomplete == false and cache.pending == nil and cache.configOwned == false,
    "缓存恢复：缓存尚未确认完成，保留日志核对")
  assert(type(cache.requests) == "table" and type(cache.transfers) == "table",
    "缓存恢复：缓存操作记录缺失")
  for _, job in pairs(cache.requests) do
    assert(type(job) == "table" and job.state == "done", "缓存恢复：申请尚未完成")
  end
  for _, move in pairs(cache.transfers) do
    assert(type(move) == "table" and move.ok == true and type(move.amount) == "number"
      and move.amount > 0 and move.amount == math.floor(move.amount)
      and move.requested == move.amount, "缓存恢复：搬液未完整确认")
  end
  local safeStates = {idle=true, ["paused-immediate"]=true,
    ["nanite-tier-too-low"]=true, ["assembler-offline"]=true, unpowered=true}
  assert(safeStates[call(NODE, "getState")] and call(RS, "getOutput", sides.top) == 15
    and call(GEN, "isWorkAllowed") == false and call(GEN, "isMachineActive") == false,
    "缓存恢复：节点须暂停且纠缠装置已停机")
  assert(next(network(SUB)) == nil, "缓存恢复：子网仍有原液，保留日志核对")
  assert(type(cache.target) == "table" and next(cache.target) ~= nil,
    "缓存恢复：缺少本轮目标")
  local stock = field()
  for name, amount in pairs(cache.target) do
    integer(amount)
    assert((stock[name] or 0) >= amount, "缓存恢复：实际库存未达本轮目标: " .. name)
  end
  -- Normalize only in memory. The existing archive keeps the original journal.
  old.stage = "waiting"
  print("后台缓存完成核对通过；归档旧生产日志后按实际库存继续，不重放旧搬液或申请。")
end

local stopped=old.stage=="stopped" and old.plan==nil and type(old.transfers)=="table" local preTransfer=(old.stage=="starting" or old.stage=="waiting" or old.stage=="waiting-stock") and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil and (old.requests==nil or next(old.requests)==nil)
local watching=(old.stage=="watching" or old.stage=="waiting") and old.plan==nil and type(old.transfers)=="table" and type(old.target)=="table" local crafted=old.stage=="craft-done" and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil and type(old.requests)=="table" and next(old.requests)~=nil local prepared=old.stage=="stream-prepared" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table"
local converting=old.stage=="converting" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table" and type(old.required)=="table" and type(old.remaining)=="table" if stopped or watching or crafted or prepared or converting or streaming then for _,move in ipairs(old.transfers) do assert(move.ok==true and type(move.amount)=="number" and move.amount>0, "旧搬运未确认，禁止恢复") end
for _,job in ipairs(old.requests or {}) do assert(job.state=="done","原液申请未完成，禁止重复申请") end assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置已停机") if streaming then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"供液恢复订单变化，暂停核对")
assert(same(network(SUB),old.secured),"已确认搬运与子网库存不符，禁止恢复") resolveRawNames(old.target) local expected,stock={},field() for name,need in pairs(old.target) do local unit=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/unit)*unit local raw=mapping[name];if amount>0 then expected[raw]=amount end local held=old.secured[raw] or 0
assert(held<=amount and held%unit==0,"供液恢复子网超额或非整批") end for raw in pairs(old.secured) do assert(expected[raw],"供液恢复子网有无关原液") end print("供液恢复核对通过；保留已搬入原液，只补当前缺口。") end if crafted then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"旧申请订单已变化，暂停核对")
print("已完成原液申请已归档；按当前真实库存重新计算缺口。") end if prepared then current(true) assert(same(network(SUB),old.expected),"已备齐原液与日志不符，暂停核对") print("整批原液已在子网，恢复时抵扣，不重复搬料或申请。") end if converting then
local req,remaining=current(true) resolveRawNames(old.target) local target=old.target if not (same(req,old.required) and same(remaining,old.remaining)) then local count;target,count=batchTarget(req,remaining) assert(type(old.batchCount)=="number" and (old.windowed==true or count<=old.batchCount), "恢复时订单增加或旧批量缺失，暂停核对") for name,need in pairs(target) do assert(need<=integer(old.target[name]),"恢复需求超过旧整批目标") end
print("实际并行/消耗已变化，按 AE 剩余订单扣除节点已消耗量核对库存。") end local sub,stock=network(SUB),field() for name,value in pairs(target) do local raw=mapping[name] local need=integer(value) local liquid,condensate=integer(sub[raw] or 0),integer(stock[name] or 0) local unit=units[name] or 144
assert(liquid%unit==0 and condensate%unit==0 and (liquid+condensate==need or (mode=="restock" and liquid+condensate<need)), "转换恢复库存不符: "..raw.."；子网 "..liquid.." + 凝聚物 "..condensate.."，目标 "..need) if liquid+condensate<need then print(raw.." 当前缺口 "..(need-liquid-condensate).." mB；归档旧操作后重新备料。") end end for raw in pairs(sub) do local allowed=false;for _,known in pairs(mapping) do if known==raw then allowed=true end end assert(allowed,"转换恢复子网有无关原液")
end for name,n in pairs(stock) do assert(n==0 or mapping[name],"转换恢复有无关凝聚物") end print("转换恢复核对通过，抵扣当前库存；已完成的旧申请和搬运记录保留归档。") end end assert(stopped or preTransfer or watching or crafted or prepared or converting or streaming,"该阶段存在未确认操作，不能自动恢复") archiveJournal(contents,".before-resume-") else
assert(old.stage=="stopped","已有非正常停止日志，请核对后使用 resume，禁止盲目重跑") for _,job in ipairs(old.requests or {}) do assert(job.state=="done","旧日志有未确认的主网申请，禁止重新下单") end archiveJournal(contents) end else assert(mode~="resume" and mode~="restock","没有可恢复的日志")
end record={version=1,kind="continuous",stage="starting",transfers={},requests={},configOwned=false} save("starting");armed=true print("常驻模式：无需填写数量。先只提交原始屏蔽层任务，可先 5 再 10。") print("按主网剩余任务分批备料，整个AE订单保留；库存不足自动接续。") serve() end local ok, err = xpcall(main, debug.traceback)
if not ok then if armed then local paused = pcall(pause,15) local stopped = pcall(generator,false) local cleaned = true if record and record.configOwned then local success, result = pcall(call,MAIN,"setFluidInterfaceConfiguration",0) cleaned = success and result == true
end print("恢复暂停: " .. tostring(paused) .. "；关闭纠缠装置: " .. tostring(stopped) .. "；清供液配置: " .. tostring(cleaned)) if not paused then print("请手动提供控制仓暂停信号。") end end print("程序停止: " .. tostring(err)) print("保留现场与日志；不要删除日志盲目重跑。约束场保持开启。") end

-- BEC_V1_BEE_GUARD_V2
