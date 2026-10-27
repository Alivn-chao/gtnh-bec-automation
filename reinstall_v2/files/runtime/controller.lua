-- BEC_V3_LARGE_BATCH_1: long-sized totals; bounded per-call fluid requests.
local c = require("component") local ser = require("serialization") local computer = require("computer") local fs = require("filesystem")
local sides = require("sides") local event = require("event") local mode = (...) or "preview" local JOURNAL = "/home/bec_auto.journal"
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d" local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50" local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad" local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0"
local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0" local GATE_ADDRESS = "cf2a0c4a-ab8d-4958-b1df-253094d6690c" local RS, GEN, GATE, armed, record local stopping=false
local NANITES=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")()
local lastNaniteTier,lastNaniteFamily
local startupAt=computer.uptime();local methodLists={};local fastStartup=type(BEC_V3_STARTUP_STATE)=='function'
local Prep=BEC_V3_PREPARATION;local preparing=false;local prepGateReady=false;local prepConverting=false
local balanceInventory,maybeConvert
local function preparationPaused(s)return s=='paused-immediate'or preparing and s=='nanite-tier-too-low'end
local mapping = { entangled_infinity = "molten.infinity", entangled_chromaticglass = "molten.chromaticglass", entangled_transcendentmetal = "molten.transcendentmetal",
entangled_dimshiftedsuperfluid = "dimensionallyshiftedsuperfluid", entangled_neutronium="molten.neutronium",entangled_cosmicneutronium="molten.cosmicneutronium", entangled_bedrockium="molten.bedrockium",entangled_celestialtungsten="molten.celestialtungsten", entangled_hypogen="molten.hypogen",entangled_phononmedium="phononmedium",
entangled_quarkgluonplasma="quarkgluonplasma",entangled_spacetime="molten.spacetime", entangled_time="molten.temporalfluid",entangled_space="molten.spatialfluid", entangled_cosmicsolder="boundlesscosmicsolder", entangled_mhdcsm="molten.magnetohydrodynamicallyconstrainedstarmatter",
entangled_magmatter="molten.magmatter",entangled_universium="molten.universium", entangled_eternity="molten.eternity" } local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000,
entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000} local function call(a, m, ...) return c.invoke(a, m, ...) end local function method(a, m)
local methods=fastStartup and methodLists[a];if not methods then methods=assert(c.methods(a),'组件不在线: '..a);if fastStartup then methodLists[a]=methods end end
assert(methods[m] ~= nil, "组件缺少方法: " .. m)
end local function resolve(prefix, kind) local address, count = nil, 0 for a, t in c.list() do
if a:sub(1, #prefix) == prefix and t == kind then address, count = a, count + 1 end end
assert(count == 1, "目标组件缺失或不唯一: " .. prefix) return address end local function integer(v)
assert(type(v) == "number" and v >= 0 and v <= 9007199254740991 and v == math.floor(v), "库存/需求数量无效或超出Lua精确整数范围") return v end local function same(a, b)
for k, v in pairs(a) do if b[k] ~= v then return false end end for k, v in pairs(b) do if a[k] ~= v then return false end end return true end
local function network(a) local rows, result = call(a, "getFluidsInNetwork"), {} assert(type(rows) == "table", "网络库存不可读") for _, f in pairs(rows) do
assert(type(f) == "table", "流体条目无效") local n = integer(f.amount or f.size or 0) if n > 0 then assert(type(f.name) == "string", "流体名称缺失")
result[f.name] = (result[f.name] or 0) + n end end return result
end
-- BEC_V3_PERFORMANCE_1: one catalogue per worker/batch. A new worker (including
-- resume) reloads disk; pattern editing is excluded while a worker is active.
local recipeIndex
local frozenRecipe=BEC_V3_FROZEN_RECIPE;local frozenNeeds
local function recipeKey(needs)
 local names,parts={},{}
 for name in pairs(needs)do names[#names+1]=name end
 table.sort(names)
 for _,name in ipairs(names)do parts[#parts+1]=#name..":"..name.."="..string.format("%.0f",needs[name])end
 return table.concat(parts,";")
end
local function indexedRecipes(needs)
 if frozenRecipe then
  if not frozenNeeds then
   frozenNeeds={}
   assert(type(frozenRecipe.recipe)=='string'and type(frozenRecipe.condensates)=='table'and #frozenRecipe.condensates>0,'冻结配方登记无效')
   assert(type(frozenRecipe.outputs)=='table'and #frozenRecipe.outputs==1,'冻结配方产物无效')
   for _,v in ipairs(frozenRecipe.condensates)do
    assert(type(v.name)=='string');local n=integer(v.amount or v.size);assert(n>0,'冻结配方流体数量无效')
    frozenNeeds[v.name]=(frozenNeeds[v.name]or 0)+n
   end
   print('复用原料盘已确认配方：'..frozenRecipe.recipe..'；不重扫登记目录。')
  end
  assert(same(needs,frozenNeeds),'节点需求与冻结配方登记不符')
  return {frozenRecipe.outputs[1]}
 end
 if not recipeIndex then
  local index={}
  if fs.exists("/home/bec/recipes")then
   for file in fs.list("/home/bec/recipes")do if file:match("%.dat$")then
    local f=assert(io.open("/home/bec/recipes/"..file,"r"));local r=ser.unserialize(f:read("*a"));f:close()
    assert(type(r)=="table","登记配方损坏: "..file)
    if r.state=="converted"then
     local amounts={}
     for _,fluid in ipairs(r.condensates or {})do amounts[fluid.name]=(amounts[fluid.name]or 0)+integer(fluid.amount or fluid.size)end
     local key=recipeKey(amounts);index[key]=index[key]or {};index[key][#index[key]+1]={outputs=r.outputs,file=file}
    end
   end end
  end
  recipeIndex=index
 end
 local matches={}
 for _,r in ipairs(recipeIndex[recipeKey(needs)]or {})do
  assert(type(r.outputs)=="table"and #r.outputs==1,"登记产物无效: "..r.file)
  matches[#matches+1]=r.outputs[1]
 end
 return matches
end
local matchedOutputs, perRecipe local function checkRecipe(required,parallel,snapshot) parallel=parallel or integer(call(NODE,"getParallelRecipesInProgress"))
assert(parallel>0 and type(required)=="table","当前配方并行/需求不可读") local normalized={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0 and n%parallel==0,"配方需求无法按并行拆分: "..tostring(name))
normalized[name]=n/parallel end local matches=indexedRecipes(normalized) if #matches>0 then
if snapshot or c.methods(NODE).getRequiredTier~=nil then local needed;if snapshot then needed=snapshot.requiredTier else needed=call(NODE,"getRequiredTier")end local tier=type(needed)=="table" and needed.tier or needed
assert(type(tier)=="number","所需蜂群等级不可读") end  matchedOutputs,perRecipe=matches,normalized
return parallel end local amount=type(required)=="table" and required.entangled_chromaticglass assert(type(amount)=="number" and amount>0 and amount%288==0
and required.entangled_transcendentmetal==amount, "未验证的配方需求，保持暂停") local recipes=amount/288 assert(parallel==nil or parallel==recipes,"实际并行与凝聚物需求不符") local count=0; for _ in pairs(required) do count=count+1 end
assert(count==2,"未验证的凝聚物需求，保持暂停") local tier=call(NODE,"getProvidedTier")
matchedOutputs={{name="gregtech:gt.metaitem.03",damage=32307,size=1}};perRecipe=normalized return recipes end local function tick(seconds)
local _,_,character=event.pull(seconds,"key_down") if character==113 or character==81 then stopping=true end end local function archiveJournal(contents,suffix)
suffix=suffix or ".stopped-" local index=1 while fs.exists(JOURNAL..suffix..index) do index=index+1 end local backup=JOURNAL..suffix..index
assert(fs.rename(JOURNAL,backup),"旧常驻日志归档失败") local f=assert(io.open(backup,"r"));local actual=f:read("*a");f:close() assert(actual==contents and not fs.exists(JOURNAL),"旧常驻日志归档验证失败") end
local function field() assert(call(STORAGE, "isWorkAllowed") == true, "约束场必须保持开启") local v = call(STORAGE, "getStoredCondensate") assert(type(v) == "table", "凝聚物库存不可读")
for _, n in pairs(v) do integer(n) end return v end local function writeVerified(path, contents)
local f = assert(io.open(path, "w")) local ok, err = f:write(contents) local flushed, flushErr = f:flush() f:close()
assert(ok and flushed, tostring(err or flushErr or "日志写入失败")) local r = assert(io.open(path, "r")) local actual = r:read("*a"); r:close() assert(actual == contents and type(ser.unserialize(actual)) == "table", "日志回读失败")
end local function save(stage) if BEC_V2_PHASE and stage~=record.stage then BEC_V2_PHASE(stage)end record.stage = stage if fs.exists(JOURNAL) then
local f = assert(io.open(JOURNAL, "r")) local old = f:read("*a"); f:close() writeVerified(JOURNAL .. ".previous", old) end
writeVerified(JOURNAL, ser.serialize(record, false)) end local function pause(value) call(RS, "setOutput", sides.top, value)
assert(call(RS, "getOutput", sides.top) == value, "红石输出回读不符") end local function generator(enabled) call(GEN, "setWorkAllowed", enabled)
assert(call(GEN, "isWorkAllowed") == enabled, "纠缠装置启停回读不符") end local function switchNanites()
local demand;if not NANITES.handlesPhase then demand=call(NODE,"getRequiredTier")end local family=type(demand)=="table"and demand.name or nil
local needed=type(demand)=="table" and demand.tier or demand
if not NANITES.handlesPhase and type(needed)~="number" then return end
if BEC_V2_PHASE then BEC_V2_PHASE("nanites")end
local started=computer.uptime();print("检查蜂群 / 准备换盘")
NANITES.ensure({tick=tick,stopping=function() return stopping end})
if NANITES.handlesPhase then
 demand=NANITES.lastRequirement;if not demand then return end
 needed,family=demand.tier,demand.name
end
print(string.format("蜂群检查/换盘完成：%.2f 秒",computer.uptime()-started))
local provided=call(NODE,"getProvidedTier")
assert(type(provided)=="table" and provided.tier>=needed and integer(call(NODE,"getAvailableNanites"))>=64,"蜂群等级或数量不足，保持暂停")
lastNaniteTier=needed;lastNaniteFamily=family
end local function gateFilters(required) assert(type(required)=="table","门过滤需求不可读")
local result={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0,"门过滤需求无效: "..tostring(name)) result[#result+1]=name
end table.sort(result) assert(#result>0,"禁止写入全空过滤；全空会放行全部凝聚物") return result
end local function verifyGate(expected) local count=integer(call(GATE,"getCondensateFilterCount")) assert(count>=#expected,"麦克斯韦门过滤槽不足")
local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table" and same(actual,expected), "麦克斯韦门过滤回读不符；检查门的流体输入仓是否自动覆盖 OC 过滤") assert(call(GATE,"isWorkAllowed")==true,"麦克斯韦门未启用，保持暂停")
assert(call(GATE,"isMachineActive")==true,"麦克斯韦门未运行；检查结构和供电，保持暂停") end local function gateNodeState(full)
if type(BEC_V2_GATE_STATE)=="function" then return BEC_V2_GATE_STATE(full) end
return call(NODE,"getState") end
local function configureGate(required) if BEC_V2_PHASE then BEC_V2_PHASE("gate")end local started=computer.uptime();print("配置韦门 / 三轮回读")
assert(call(RS,"getOutput",sides.top)==15 and preparationPaused(gateNodeState(true)),
"切换门过滤前节点必须立即暂停") local expected=gateFilters(required) assert(integer(call(GATE,"getCondensateFilterCount"))>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters")
assert(type(actual)=="table","麦克斯韦门过滤不可读") record.gateIntent={address=GATE,filters=expected};save(record.stage) if not same(actual,expected) then call(GATE,"setCondensateFilters",expected) end for i=1,3 do
verifyGate(expected) assert(preparationPaused(gateNodeState(false)),"设置过滤时订单状态变化") if i<3 then tick(0.1) end end
print("麦克斯韦门过滤: "..table.concat(expected,", ")..string.format(" / 确认 %.2f 秒",computer.uptime()-started)) return expected end local function tanks(side, name)
local count, amount = integer(call(TRANS, "getTankCount", side)), 0 assert(count > 0, "接口没有流体槽") for i = 1, count do local f = call(TRANS, "getFluidInTank", side, i)
assert(type(f) == "table", "接口缓存不可读") if type(f[1]) == "table" then f = f[i] or f[1] end local n = integer(f.amount or 0) if n > 0 then
assert(name and f.name == name, "接口有未处理流体缓存") amount = amount + n end end
return amount end local function emptyConfig() for slot = 0, 5 do
assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置") end end local function current(recovering)
-- V2 bridge can read all four adjacent fields in one fresh group scan.
-- Outside that bridge, retain the original component getter path.
local snapshot=type(BEC_V2_NODE_SNAPSHOT)=="function" and BEC_V2_NODE_SNAPSHOT() or nil
local state=snapshot and snapshot.state or call(NODE,"getState") local unavailable=state=="assembler-offline" or state=="unpowered" or state=="nanite-tier-too-low" assert(preparationPaused(state) or (recovering and unavailable and call(RS,"getOutput",sides.top)==15),"订单未处于立即暂停状态")
local parallel=integer(snapshot and snapshot.parallel or call(NODE, "getParallelRecipesInProgress")) assert(parallel>=1,"暂停节点没有正在处理的配方") local required, consumed
if snapshot then required,consumed=snapshot.required,snapshot.consumed else required,consumed=call(NODE,"getRequiredCondensate"),call(NODE,"getConsumedCondensate")end
assert(type(required) == "table" and type(consumed) == "table", "订单需求不可读")
local remaining, total = {}, 0 for name, amount in pairs(required) do assert(mapping[name], "不支持的凝聚物: " .. tostring(name)) amount = integer(amount)
local used = integer(consumed[name] or 0) assert(used <= amount, "已消耗数量超过需求") remaining[name] = amount - used; total = total + amount end
assert(total > 0, "订单没有有效需求") for name, amount in pairs(consumed) do assert(integer(amount) == 0 or required[name], "消耗记录与当前订单不符") end
checkRecipe(required,parallel,snapshot) return required, remaining, parallel end local function queuedRecipes() return 0 end local function batchTarget(required,remaining,parallel)
parallel=parallel or checkRecipe(required) local count=math.max(parallel,queuedRecipes()) local target={} for name,amount in pairs(required) do
assert(count-parallel<=math.floor((9007199254740991-integer(remaining[name]))/perRecipe[name]),"整批需求超出Lua精确整数范围")
target[name]=integer(remaining[name]+perRecipe[name]*(count-parallel)) end return target,count
end local function unchanged() local req, remaining = current() assert(same(req, record.required) and same(remaining, record.remaining), "暂停订单发生变化，停止")
end
local discovery,saveDiscovery,discoveryLoaded
local baseMapping={};for k,v in pairs(mapping)do baseMapping[k]=v end
local function rawAlias(kind,raw)
 local base=baseMapping[kind]
 return base and(raw==base or raw=='fluid.'..base or kind=='entangled_space'and(raw=='spatialfluid'or raw=='fluid.spatialfluid')or kind=='entangled_time'and(raw=='temporalfluid'or raw=='fluid.temporalfluid'))
end
local function loadDiscovery()
 if discoveryLoaded then return end;discoveryLoaded=true
 if type(BEC_V3_PRODUCTION_DISCOVERY)=='function'then discovery,saveDiscovery=BEC_V3_PRODUCTION_DISCOVERY()end
 if discovery then for kind,raw in pairs(discovery.rawNames)do if rawAlias(kind,raw)then mapping[kind]=raw else discovery.rawNames[kind]=nil end end end
end
local function resolveRawNames(target)
 loadDiscovery()
 local unknown=false;for kind in pairs(target)do if(kind=='entangled_space'or kind=='entangled_time')and not(discovery and discovery.rawNames[kind])then unknown=true end end
 if not unknown then return end
 local main,sub,stock=network(MAIN),network(SUB),field()
 for kind,need in pairs(target)do
 if(kind=='entangled_space'or kind=='entangled_time')and not(discovery and discovery.rawNames[kind])then local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" local candidates={[stem]=true,["molten."..stem]=true,["fluid."..stem]=true,["fluid.molten."..stem]=true} local found={}
for name in pairs(candidates) do if (main[name] or 0)>0 or (sub[name] or 0)>0 then found[name]=true end local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败")
for _,craft in pairs(rows) do local f=craft.getStack() if type(f)=="table" and f.name==name then found[name]=true end end
end local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"空间/时间原液名称不唯一: "..kind) assert(n==1 or (stock[kind] or 0)>=need,"主网缺少空间/时间原液库存或样板: "..kind)
if n==1 then mapping[kind]=name;if discovery then discovery.rawNames[kind]=name;if saveDiscovery then saveDiscovery()end end end end end end
local function plan(remaining,quiet) resolveRawNames(remaining) local stock, sub, main = field(), network(SUB), network(MAIN) local moves, expected, allowed, shortages, deficits = {}, {}, {}, {}, {}
for name, need in pairs(remaining) do local raw = mapping[name] allowed[raw] = true local unit=units[name] or 144
local required = math.ceil(math.max(0, need - (stock[name] or 0)) / unit) * unit local existing = sub[raw] or 0 assert(existing <= required and existing % unit == 0, "子网原液超额或非整批: " .. raw) local missing = required - existing
if (main[raw] or 0)<missing then deficits[#deficits+1]={raw=raw,amount=missing-(main[raw] or 0),needed=missing} shortages[#shortages+1]=raw..": 本次需补 "..missing.." mB，主网有 "..(main[raw] or 0) .."，还缺 "..(missing-(main[raw] or 0)).." mB"
end if required > 0 then expected[raw] = required end if missing>0 then moves[#moves+1]={raw=raw,amount=missing,chunk=math.floor(16000/unit)*unit}end if not quiet then print(raw .. " 本次补入 " .. missing .. " mB") end
end for raw in pairs(sub) do assert(allowed[raw], "子网有无关原液: " .. raw) end for name, amount in pairs(stock) do assert(amount == 0 or mapping[name], "约束场有未知凝聚物: " .. name)
end table.sort(moves, function(a,b) return a.raw < b.raw end) if #shortages>0 then table.sort(shortages)
local message=table.concat(shortages,"；") if not quiet then print("缺料: "..message.."；运行时向主网 AE 申请缺口") end table.sort(deficits,function(a,b) return a.raw<b.raw end) return nil,message,deficits
end return moves, sub, expected end local function waitUntil(seconds, condition, guard,label)
local deadline = computer.uptime() + seconds while true do local ready, snapshot = condition() if ready then return end
if guard then guard(snapshot) end assert(computer.uptime() < deadline, "等待超时，停止"..(label and "："..label.." / 实际状态 "..tostring(snapshot)or "")) os.sleep(0.25) end
end
local function probeRoute(route,raw)
 if call(route.address,'getTankCount',route.from)~=1 or call(route.address,'getTankCapacity',route.from,1)~=2147483647
  or call(route.address,'getTankCount',route.to)~=6 or call(route.address,'getTankCapacity',route.to,1)~=16000 then return false end
 local f=call(route.address,'getFluidInTank',route.from,1);if type(f)=='table'and type(f[1])=='table'then f=f[1]end
 return type(f)=='table'and(f.name==raw or not f.name and tonumber(f.amount or 0)==0)
end
local function bulkPorts(required)
 loadDiscovery();if not next(required)then return{}end
 if discovery and discovery.ports then
  local valid=true
  for kind in pairs(required)do local route=discovery.ports[mapping[kind]];local ok,match=false,false
   if route then ok,match=pcall(probeRoute,route,mapping[kind])end
   if not ok or not match then valid=false;break end
  end
  if valid then return discovery.ports end
  discovery.ports=nil
 end
 local allowed,ports={},{}
 for _,raw in pairs(baseMapping)do allowed[raw]=true;allowed['fluid.'..raw]=true end
 for _,raw in ipairs({'spatialfluid','fluid.spatialfluid','temporalfluid','fluid.temporalfluid'})do allowed[raw]=true end
 for address,kind in c.list('transposer')do if kind=='transposer'and address~=TRANS then
  local sources,receivers={},{}
  for side=0,5 do
   local ok,count=pcall(call,address,'getTankCount',side)
   if ok and count==1 then
    local readable,capacity=pcall(call,address,'getTankCapacity',side,1)
    if readable and capacity==2147483647 then local f=call(address,'getFluidInTank',side,1);if type(f)=='table'and type(f[1])=='table'then f=f[1]end
     if type(f)=='table'and allowed[f.name]then sources[#sources+1]={from=side,raw=f.name}end
    end
   elseif ok and count==6 then local readable,capacity=pcall(call,address,'getTankCapacity',side,1);if readable and capacity==16000 then receivers[#receivers+1]=side end end
  end
  if #sources>0 then assert(#receivers==1,'高速供液口接收方向缺失或不唯一: '..address)
   for _,source in ipairs(sources)do assert(not ports[source.raw],'高速供液口重复绑定: '..source.raw);ports[source.raw]={address=address,from=source.from,to=receivers[1]}end
  end
 end end
 for kind in pairs(required)do
  local raw=mapping[kind]
  if not ports[raw]then local found,n=nil,0;for name in pairs(ports)do if rawAlias(kind,name)then found=name;n=n+1 end end
   assert(n<=1,'高速供液原液名称不唯一: '..kind);if n==1 then mapping[kind]=found end
  end
  if discovery and ports[mapping[kind]]then discovery.rawNames[kind]=mapping[kind]end
 end
 if discovery then discovery.ports=ports;if saveDiscovery then saveDiscovery()end end
 return ports
end
local function verifyBulk(route,raw,allowEmpty) local f=call(route.address,"getFluidInTank",route.from,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end assert(type(f)=="table" and(f.name==raw or allowEmpty and not f.name and integer(f.amount or 0)==0)
and call(route.address,"getTankCapacity",route.from,1)==2147483647,"高速缓存口绑定已变化") assert(call(route.address,"getTankCount",route.to)==6,"高速接收接口已变化") for i=1,6 do local tank=call(route.address,"getFluidInTank",route.to,i)
if type(tank)=="table" and type(tank[1])=="table" then tank=tank[i] or tank[1] end assert(type(tank)=="table" and integer(tank.amount or 0)==0,"高速接收接口有未处理缓存") end end
local function prepareStreaming(target) resolveRawNames(target) local stock,previous=field(),network(SUB)
local wanted={};for name,need in pairs(target)do local batch=units[name]or 144;local amount=math.ceil(math.max(0,need-(stock[name]or 0))/batch)*batch
 if amount>(previous[mapping[name]]or 0)then wanted[name]=true end end
local ports=bulkPorts(wanted)
if preparing then
 local highSpeed=true;for name in pairs(wanted)do if not ports[mapping[name]]then highSpeed=false end end
 if highSpeed then
  record.supplyLedger={version=1,base=stock}
  balanceInventory=function()
   local before=field();local sub=network(SUB);local after=field()
   return Prep.balance(stock,previous,mapping,before,sub,after)
  end
  maybeConvert=function()
   if prepGateReady and not prepConverting and not record.pending and next(network(SUB))then
    assert(balanceInventory(),'转换前原液/凝聚物账本不符')
    record.supplyLedger.converting=true;record.supplyLedger.startedAt=computer.uptime();save('stream-converting');generator(true);prepConverting=true
   end
  end
 end
end
local expected,raws={},{} for name,need in pairs(target) do local raw=mapping[name] local batch=units[name] or 144
local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0 assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end
raws[#raws+1]={raw=raw,amount=amount,batch=batch} end for raw in pairs(previous) do local allowed=false
for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end
table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned") for _,item in ipairs(raws) do local raw,need,batch=item.raw,item.amount,item.batch
local route=ports[raw] local chunk=math.floor((route and 2147483647 or 16000)/batch)*batch local function bufferedInlet() return route and 0 or tanks(4,raw) end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=route==nil;save("stream-configuring") if route then verifyBulk(route,raw,true)
print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to) else assert(call(MAIN,"setFluidInterfaceConfiguration",0, {name=raw,amount=math.min(need-(previous[raw] or 0),chunk),
size=math.min(need-(previous[raw] or 0),chunk)})==true,"持续供液配置失败") end print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt
local requestChunk=math.floor(2147483647/batch)*batch
local attempts=0 local attemptLimit=math.ceil(need/requestChunk)+2 local inletOpen=route==nil local deadline=computer.uptime()+1800 while not stopping do
if maybeConvert then maybeConvert()end
unchanged();if balanceInventory then waitUntil(10,balanceInventory,unchanged,'并行转换账本')else assert(same(field(),stock),"备料时约束场库存变化");assert(same(network(SUB),previous),"备料时子网库存变化")end local remaining=need-(previous[raw] or 0) local buffered=route and (network(MAIN)[raw] or 0) or bufferedInlet()
local amount=math.floor(math.min(remaining,buffered,chunk)/batch)*batch if amount>0 then local address,from,to=TRANS,4,5 if route then verifyBulk(route,raw);address,from,to=route.address,route.from,route.to end
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to} save("transfer-returned")
assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试") previous[raw]=(previous[raw] or 0)+amount waitUntil(10,balanceInventory or function() return same(network(SUB),previous) end,unchanged) record.pending=nil;record.secured=previous;save("stream-transfer-confirmed");if maybeConvert then maybeConvert()end
print(raw.." 已入子网 "..previous[raw].." / "..need.." mB") deadline=computer.uptime()+1800 end remaining=need-(previous[raw] or 0)
if remaining==0 and inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;inletOpen=false;save("stream-inlet-cleared") waitUntil(20,function() return tanks(4,raw)==0 end,unchanged)
end if status and job.state=="submitted" then local canceled,why=status.isCanceled() assert(canceled==false,"主网原液申请失败/取消: "..tostring(why))
local done=status.isDone();assert(type(done)=="boolean","AE 状态不可读") if done then job.state="done";job.securedAfter=previous[raw] or 0 doneAt=computer.uptime();save("stream-craft-done")
else assert(computer.uptime()<jobDeadline,"主网原液合成超时，保留申请记录") end end if remaining==0 and (not job or job.state=="done") then break end if remaining>0 and (not job or job.state=="done") then
local missing=math.max(0,remaining-bufferedInlet()-(network(MAIN)[raw] or 0)) if missing>0 and (not doneAt or computer.uptime()-doneAt>=3) then if job then assert((previous[raw] or 0)>job.securedBefore,
"本次原液合成已结束但子网没有收获，暂停核对竞争设备") end local cpus=call(MAIN,"getCpus") assert(type(cpus)=="table","主网 CPU 状态不可读")
local available=false for _,cpu in pairs(cpus) do if cpu.busy==false then available=true end end if available then if not craft then
local rows=call(MAIN,"getCraftables",{name=raw}) assert(type(rows)=="table","原液配方不可读") local count=0;for _,v in pairs(rows) do craft=v;count=count+1 end assert(count==1,"原液配方缺失或不唯一: "..raw)
local f=craft.getStack() assert(type(f)=="table" and f.name==raw and f.isCraftable==true and type(f.amount)=="number" and f.amount==f.size and f.hasTag==false, "未验证的流体合成对象")
end attempts=attempts+1;assert(attempts<=attemptLimit,"原液仍被争抢，暂停保留已收获库存") missing=math.max(0,need-(previous[raw] or 0)-bufferedInlet()-(network(MAIN)[raw] or 0)) if missing>0 then
missing=math.min(missing,requestChunk)
job={raw=raw,amount=missing,unit="mB",state="pending",securedBefore=previous[raw] or 0} record.requests[#record.requests+1]=job;save("craft-request-pending") local reason;status,reason=craft.request(missing) assert(status~=nil,"AE 申请未确认: "..tostring(reason))
job.state="submitted";jobDeadline=computer.uptime()+1800;doneAt=nil save("stream-crafting") print("主网 AE 申请 "..raw.." "..missing.." mB；合成中持续收料。") end
end end end assert(computer.uptime()<deadline,"持续收料超时，保留子网已搬入原液")
tick(0.1) end if inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败")
record.configOwned=false;save("stream-inlet-cleared") end waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) if stopping then return expected end
end end if balanceInventory then waitUntil(10,balanceInventory,unchanged,'并行转换账本')else assert(same(network(SUB),expected),"整批子网原液不符")end record.plan=nil;save("stream-prepared")
return expected end local function completedIdle(state)
if state~="idle" or not BEC_V2_COHORT_IDLE then return false end
assert(BEC_V2_COHORT_IDLE());return true
end
local function stockedBatch(target)
 if record.pending or record.configOwned or next(record.transfers or {})then return false end
 for _,job in ipairs(record.requests or {})do if job.state~="done"then return false end end
 local stock=field()
 for name,amount in pairs(stock)do assert(amount==0 or mapping[name],"约束场有未知凝聚物")end
 for name,need in pairs(target)do if (stock[name]or 0)<need then return false end end
 return next(network(SUB))==nil
end
local function productionSnapshot()
 if type(BEC_V3_FIXED_BATCH_SNAPSHOT)=="function"then return BEC_V3_FIXED_BATCH_SNAPSHOT()end
 if type(BEC_V2_NODE_SNAPSHOT)=="function"then return BEC_V2_NODE_SNAPSHOT()end
 local v={state=call(NODE,"getState"),required=call(NODE,"getRequiredCondensate")}
 local demand=call(NODE,"getRequiredTier")
 v.requiredTier=type(demand)=="table"and demand.tier or demand
 v.requiredFamily=type(demand)=="table"and demand.name or nil
 v.parallel=call(NODE,"getParallelRecipesInProgress");v.consumed=call(NODE,"getConsumedCondensate")
 return v
end
local function serve() local waiting={idle=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
local round=0 while not stopping do preparing=Prep~=nil;prepGateReady=false;prepConverting=false;balanceInventory=nil;maybeConvert=nil;local nanitesChecked=false;pause(15); generator(false) local state=fastStartup and BEC_V3_STARTUP_STATE()or call(NODE,"getState")
if stopping then break end if not fastStartup then state=call(NODE,"getState")end
if state=="idle" and BEC_V2_COHORT_IDLE then assert(BEC_V2_COHORT_IDLE());print("本批节点已完成，消耗核对通过；结束旧批次并交回设备组调度。") break end
if not Prep and(state=="paused-immediate" or state=="nanite-tier-too-low")then switchNanites();nanitesChecked=true;state=call(NODE,"getState")end if waiting[state]and not(Prep and state=="nanite-tier-too-low")then
if state~=record.lastState then print("等待订单/机器就绪: "..state.."；任意数量同配方订单均可，按 Q 停止。") record.lastState=state;save("waiting") end
field();tick(0.1) else local completed=false;waitUntil(10,function() local v=fastStartup and BEC_V3_STARTUP_STATE()or call(NODE,"getState");completed=completedIdle(v)
return preparationPaused(v)or completed,v end,function(v) assert(v=="crafting" or waiting[v],"无法暂停，实际状态: "..tostring(v)) field()
end,"备料前暂停/完成核对") if completed then print("暂停等待期间本批已完成，消耗核对通过；交回调度。");break end;if not nanitesChecked and not Prep then switchNanites()end;if stopping then break end local parallel;record.required,record.remaining,parallel=current() local target,count=batchTarget(record.required,record.remaining,fastStartup and parallel or nil) local stable=false
-- A closed frozen cell fixes the quantity; there is no growing CPU order to
-- debounce. current() above still freshly checks every member and consumption.
if fastStartup and frozenRecipe then stable=true else
for i=1,20 do tick(0.25);unchanged() local nextTarget,nextCount=batchTarget(record.required,record.remaining) if same(target,nextTarget) then stable=true;break end
target,count=nextTarget,nextCount end assert(stable,"主网任务清单持续变化，保持暂停") if stopping then break end
end
record.batchCount=count print("本组当前配方 "..count.." 份；当前实际并行 "..(fastStartup and parallel or checkRecipe(record.required)) .."；一次准备整批所需流体。") round=round+1;record.round=round;record.transfers={};record.target=target;record.plan=nil;record.topups={};record.supplyLedger=nil
waitUntil(10,function()return call(GEN,"isMachineActive")==false end);emptyConfig();tanks(4,nil);tanks(5,nil)
local filters,cached
if Prep then
 if BEC_V2_PHASE then BEC_V2_PHASE('nanites')end
 BEC_V3_PREPARATION_BEGIN()
 print('并行准备：换蜂、韦门确认、原液备料；门确认后到账即转换，全部完成再放行。')
 record.preparation=Prep.run({
  {name='nanites',run=function()switchNanites();nanitesChecked=true end},
  {name='gate',run=function()filters=configureGate(record.required);prepGateReady=true;BEC_V3_PREPARATION_GATE_READY()end},
  {name='supply',run=function()
   cached=stockedBatch(target)
   if cached then
    record.expected={};record.secured={};record.plan=nil;save('stream-prepared')
    print('凝聚物库存满足本批需求；子网为空，无需搬液和纠缠。')
   else
    local expected=prepareStreaming(target);if stopping then return end
    -- Every transfer already confirmed its subnet delta or conversion ledger.
    -- Replace the old twenty full-cohort polls with a fresh barrier check.
    while not prepGateReady and not stopping do tick(.1)end
    if stopping then return end
    if balanceInventory then waitUntil(10,balanceInventory,unchanged,'转换前账本')else assert(same(network(SUB),expected),'转换前原液变化')end
    if record.supplyLedger and not prepConverting then record.supplyLedger.startedAt=computer.uptime()end
    save('converting');if not prepConverting then generator(true);prepConverting=true end
    local limit=180;for name in pairs(target)do limit=limit+math.ceil((expected[mapping[name]]or 0)/(units[name]or 144))*180 end
    waitUntil(limit,function()
     local stock=field();for name,need in pairs(target)do if(stock[name]or 0)<need then return false end end
     return next(network(SUB))==nil
    end,unchanged,'并行转换')
   end
  end}
 },{now=computer.uptime,stopping=function()return stopping end,
  abort=function()stopping=true end,cleanup=BEC_V3_PREPARATION_CLEANUP})
 if record.supplyLedger then
  record.preparation.conversionAt=record.supplyLedger.startedAt
  record.preparation.earlyConversion=record.supplyLedger.startedAt and record.supplyLedger.startedAt<record.preparation.started+(record.preparation.durations.nanites or 0)or false
 end
 BEC_V3_PREPARATION_END();preparing=false
 if stopping then break end
 print(string.format('并行准备完成：%.2f秒（换蜂%.2f / 门%.2f / 备料转换%.2f；重叠计时不相加）',record.preparation.elapsed,record.preparation.durations.nanites or 0,record.preparation.durations.gate or 0,record.preparation.durations.supply or 0))
else
filters=configureGate(record.required) unchanged()
if stopping then break end cached=stockedBatch(target)
if cached then
 record.expected={};record.secured={};record.plan=nil;save("stream-prepared")
 print("凝聚物库存满足本批需求；子网为空，无需搬液和纠缠。")
else
local expected=prepareStreaming(target) if stopping then break end for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end
save("converting");generator(true) local conversionLimit=180 for name,need in pairs(target) do conversionLimit=conversionLimit+math.ceil(need/(units[name] or 144))*180 end waitUntil(conversionLimit,function()
local stock=field() for name,need in pairs(target) do if (stock[name] or 0)<need then return false end end return true end,unchanged)
end
end
unchanged();generator(false) record.plan=nil;record.lastState=nil;save("watching") if not stopping then verifyGate(filters);unchanged()
if cached then
 emptyConfig();tanks(4,nil);tanks(5,nil);assert(stockedBatch(target),"快速放行前库存或子网变化，保持暂停")
 if BEC_V3_RELEASE_SUPPLY then BEC_V3_RELEASE_SUPPLY()end
end
if BEC_V2_PHASE then BEC_V2_PHASE("producing")end pause(0) print("整批流体齐备，已连续放行；本组同配方节点已同时放行。按 Q 停止。") local releasedAt=computer.uptime() -- BEC_V3_NO_RECIPE_TIMEOUT_1: slow recipes wait until completion or explicit stop.
local lastRequired=record.required local nextQueueCheck=0 while not stopping do
-- One full group sample per decision, plus a separate fresh sample at the
-- refill boundary. Never reuse it after a pause, swap, release, or yield.
local sample=productionSnapshot();local v,req=sample.state,sample.required
local stock=field();verifyGate(filters)
local needed,family=sample.requiredTier,sample.requiredFamily
local supplied=call(NODE,"getProvidedTier")
if type(needed)=="number" and (sample.phaseReleaseRequired or needed~=lastNaniteTier or family~=lastNaniteFamily or type(supplied)~="table" or supplied.tier<needed) then
pause(15);local completed=false;waitUntil(10,function() local s=call(NODE,"getState");completed=completedIdle(s);return s=="paused-immediate" or s=="nanite-tier-too-low"or completed,s end,nil,"换蜂前暂停/完成核对")
if completed then print("换蜂暂停期间本批已完成，消耗核对通过；无需再换蜂。");stopping=true;break end
switchNanites();if stopping then break end;verifyGate(filters);pause(0);releasedAt=computer.uptime();if BEC_V2_PHASE then BEC_V2_PHASE("producing")end
sample=productionSnapshot();v,req=sample.state,sample.required;stock=field()
end
local parallel if req~=nil then parallel=integer(sample.parallel) local matching=parallel>0
for name,n in pairs(req) do if not perRecipe[name] or n~=perRecipe[name]*parallel then matching=false end end for name in pairs(perRecipe) do if req[name]==nil then matching=false end end if not matching then pause(15);break end if not same(gateFilters(req),filters) then pause(15);break end
lastRequired=req end if v=="idle" then local consumed=sample.consumed
assert(type(consumed)=="table","节点空闲后消耗记录不可读") for name,need in pairs(lastRequired) do assert(integer(consumed[name] or 0)>=need, "节点进入空闲但凝聚物未消耗完，可能故障关闭: "..name.."；需求 "..need.."，已消耗 "..tostring(consumed[name] or 0))
end stopping=true;break end if waiting[v] then break end
assert(v=="crafting" or (v=="paused-immediate" and computer.uptime()-releasedAt<(BEC_V2_RELEASE_GRACE or 3)), "节点运行异常: "..tostring(v)) local refill=false if computer.uptime()>=nextQueueCheck and req~=nil then
local freshSample=productionSnapshot();local consumed=freshSample.consumed;assert(type(consumed)=="table","当前消耗记录不可读") local fresh=freshSample.required if type(fresh)~="table" or not same(req,fresh) or parallel~=freshSample.parallel then pause(15);break end
local count=math.max(1,queuedRecipes()) for name,amount in pairs(req) do local need=perRecipe[name]*math.max(parallel,count)-integer(consumed[name] or 0) if (stock[name] or 0)<need then refill=true end
end nextQueueCheck=computer.uptime()+1 end if refill then break end
-- Recipe duration and condensate consumption can remain unchanged for hours.
-- State, demand, gate, refill and cancellation guards above remain active.
tick(0.1) end
end end end pause(15);generator(false);record.configOwned=false
for _,job in ipairs(record.requests) do if job.state~="done" then save("craft-paused") print("服务已暂停；主网原液申请仍需核对，保留日志，不重复下单。")
return end end save("stopped")
print("已停止常驻服务：暂停输出 15，纠缠装置关闭；约束场与已有凝聚物保持开启。") end local function main() assert(mode=="preview" or mode=="run" or mode=="resume" or mode=="restock", "用法: preview / run / resume / restock，无需填写数量")
local bound=BEC_V3_BOUND_COMPONENTS
RS = bound and bound.redstone or resolve("266f65b5", "redstone") GEN = bound and bound.generator or resolve("c1ae3f7c", "gt_machine") GATE = bound and bound.gate or resolve(GATE_ADDRESS, "bec_diode") assert(call(GEN, "getName") == "multi.bec.generator", "纠缠装置名称不符")
for _, item in ipairs({{RS,"setOutput"},{RS,"getOutput"},{GEN,"setWorkAllowed"}, {GEN,"isWorkAllowed"},{GEN,"isMachineActive"},{MAIN,"getFluidsInNetwork"}, {MAIN,"setFluidInterfaceConfiguration"},{MAIN,"getFluidInterfaceConfiguration"}, {SUB,"getFluidsInNetwork"},{TRANS,"transferFluid"},
{MAIN,"getCraftables"},{MAIN,"getCpus"},{GATE,"getCondensateFilterCount"}, {GATE,"getCondensateFilters"},{GATE,"setCondensateFilters"}, {GATE,"isWorkAllowed"},{GATE,"isMachineActive"}}) do method(item[1],item[2]) end local minimum,maximum=integer(call(NODE,"getMinParallel")),integer(call(NODE,"getMaxParallel"))
local function startupState()return type(BEC_V3_STARTUP_STATE)=='function'and BEC_V3_STARTUP_STATE()or call(NODE,'getState')end
assert(minimum>=1 and maximum>=minimum,"节点并行设置无效") print("远端红石: " .. RS .. "；纠缠装置: " .. GEN) print("节点: " .. startupState() .. "；向上输出: " .. call(RS,"getOutput",sides.top)) print("纠缠装置允许工作: " .. tostring(call(GEN,"isWorkAllowed")))
print("麦克斯韦门: "..GATE.."；过滤: "..ser.serialize(call(GATE,"getCondensateFilters"),false) .."；运行: "..tostring(call(GATE,"isMachineActive"))) print("凝聚物库存: " .. ser.serialize(field(),false)) if mode == "preview" then
print("子网原液: " .. ser.serialize(network(SUB),false)) if call(NODE,"getState") == "paused-immediate" then local required,remaining=current();local target,count=batchTarget(required,remaining) print("本组当前配方 "..count.." 份")
plan(target) end print("预览结束：没有开关、搬液、配置或写日志。") return
end local waitingStates = {idle=true, ["paused-immediate"]=true, ["assembler-offline"]=true, unpowered=true, ["nanite-tier-too-low"]=true} local initialState = startupState()
assert(waitingStates[initialState], "节点状态不适合启动: " .. tostring(initialState)) emptyConfig(); tanks(4,nil); tanks(5,nil) if fs.exists(JOURNAL) then local f=assert(io.open(JOURNAL,"r"));local contents=f:read("*a");f:close()
local old=ser.unserialize(contents);local liveSupply=Prep and type(old)=='table'and type(old.supplyLedger)=='table'and old.supplyLedger.version==1 and type(old.supplyLedger.base)=='table'and type(old.secured)=='table'and type(old.target)=='table'and type(old.stage)=='string'and(old.stage:match('^stream%-')or old.stage=='converting');local streaming=type(old)=="table" and type(old.plan)=="table" and (old.stage=="stream-configuring" or old.stage=="stream-transfer-confirmed" or old.stage=="stream-inlet-cleared" or old.stage=="stream-planned")
and type(old.secured)=="table" and type(old.target)=="table" assert(type(old)=="table" and old.version==1 and old.kind=="continuous" and old.pending==nil and (old.configOwned==false or streaming),"日志无效或有未确认操作，禁止重跑") if mode=="resume" or mode=="restock" then
local stopped=old.stage=="stopped" and old.plan==nil and type(old.transfers)=="table" local preTransfer=(old.stage=="starting" or old.stage=="waiting" or old.stage=="waiting-stock") and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil and (old.requests==nil or next(old.requests)==nil)
local watching=(old.stage=="watching" or old.stage=="waiting") and old.plan==nil and type(old.transfers)=="table" and type(old.target)=="table" local crafted=old.stage=="craft-done" and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil
and type(old.requests)=="table" and next(old.requests)~=nil local prepared=old.stage=="stream-prepared" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table"
local converting=old.stage=="converting" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table" and type(old.required)=="table" and type(old.remaining)=="table" if stopped or watching or crafted or prepared or converting or streaming or liveSupply then
for _,move in ipairs(old.transfers) do assert(move.ok==true and type(move.amount)=="number" and move.amount>0, "旧搬运未确认，禁止恢复") end
for _,job in ipairs(old.requests or {}) do assert(job.state=="done","原液申请未完成，禁止重复申请") end assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false
and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置已停机")
if liveSupply then
 resolveRawNames(old.target);local req,left=current(true)
 assert(same(req,old.required)and same(left,old.remaining),'并行备料恢复时原批次变化，保留现场')
 local stock=field();assert(Prep.balance(old.supplyLedger.base,old.secured,mapping,stock,network(SUB),stock),'并行备料恢复原液/凝聚物总账不符，不重复搬入')
 print('并行备料恢复账本通过；按实际原液与凝聚物抵扣，已确认申请和搬运不重放。')
end
if streaming and not liveSupply then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"供液恢复订单变化，暂停核对")
assert(same(network(SUB),old.secured),"已确认搬运与子网库存不符，禁止恢复") resolveRawNames(old.target) local expected,stock={},field() for name,need in pairs(old.target) do
local unit=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/unit)*unit local raw=mapping[name];if amount>0 then expected[raw]=amount end local held=old.secured[raw] or 0
assert(held<=amount and held%unit==0,"供液恢复子网超额或非整批") end for raw in pairs(old.secured) do assert(expected[raw],"供液恢复子网有无关原液") end print("供液恢复核对通过；保留已搬入原液，只补当前缺口。")
end if crafted then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"旧申请订单已变化，暂停核对")
print("已完成原液申请已归档；按当前真实库存重新计算缺口。") end if prepared and not liveSupply then current(true)
assert(same(network(SUB),old.expected),"已备齐原液与日志不符，暂停核对") print("整批原液已在子网，恢复时抵扣，不重复搬料或申请。") end if converting and not liveSupply then
local req,remaining=current(true) resolveRawNames(old.target) local target=old.target if not (same(req,old.required) and same(remaining,old.remaining)) then
local count;target,count=batchTarget(req,remaining) assert(type(old.batchCount)=="number" and count<=old.batchCount, "恢复时订单增加或旧批量缺失，暂停核对") for name,need in pairs(target) do assert(need<=integer(old.target[name]),"恢复需求超过旧整批目标") end
print("实际并行/消耗已变化，按 AE 剩余订单扣除节点已消耗量核对库存。") end local sub,stock=network(SUB),field() for name,value in pairs(target) do
local raw=mapping[name] local need=integer(value) local liquid,condensate=integer(sub[raw] or 0),integer(stock[name] or 0) local unit=units[name] or 144
local stocked=liquid==0 and condensate>=need
assert(liquid%unit==0 and condensate%unit==0 and (stocked or liquid+condensate==need or (mode=="restock" and liquid+condensate<need)), "转换恢复库存不符: "..raw.."；子网 "..liquid.." + 凝聚物 "..condensate.."，目标 "..need) if stocked and condensate>need then print(raw.." 原液已清空，凝聚物足量；保留多余库存 "..(condensate-need).." mB。") end if liquid+condensate<need then print(raw.." 当前缺口 "..(need-liquid-condensate).." mB；归档旧操作后重新备料。") end
end for raw in pairs(sub) do local allowed=false;for _,known in pairs(mapping) do if known==raw then allowed=true end end assert(allowed,"转换恢复子网有无关原液")
end for name,n in pairs(stock) do assert(n==0 or mapping[name],"转换恢复有无关凝聚物") end print("转换恢复核对通过，抵扣当前库存；已完成的旧申请和搬运记录保留归档。") end
end assert(stopped or preTransfer or watching or crafted or prepared or converting or streaming or liveSupply,"该阶段存在未确认操作，不能自动恢复") archiveJournal(contents,".before-resume-") else
assert(old.stage=="stopped","已有非正常停止日志，请核对后使用 resume，禁止盲目重跑") for _,job in ipairs(old.requests or {}) do assert(job.state=="done","旧日志有未确认的主网申请，禁止重新下单") end
archiveJournal(contents) end else assert(mode~="resume" and mode~="restock","没有可恢复的日志")
end record={version=1,kind="continuous",stage="starting",transfers={},requests={},configOwned=false,startupSeconds=computer.uptime()-startupAt} save("starting");armed=true print(string.format('启动接口与旧记录核对：%.2f秒',record.startupSeconds)) print("常驻模式：无需填写数量。先只提交原始屏蔽层任务，可先 5 再 10。")
print("按主网 CPU 剩余任务量，一次准备整批原液；追加订单自动补差额。") serve() end local ok, err = xpcall(main, debug.traceback)
if not ok then if armed then local paused = pcall(pause,15) local stopped = pcall(generator,false)
local cleaned = true if record and record.configOwned then local success, result = pcall(call,MAIN,"setFluidInterfaceConfiguration",0) cleaned = success and result == true
end print("恢复暂停: " .. tostring(paused) .. "；关闭纠缠装置: " .. tostring(stopped) .. "；清供液配置: " .. tostring(cleaned)) if not paused then print("请手动提供控制仓暂停信号。") end end
print("程序停止: " .. tostring(err)) print("保留现场与日志；不要删除日志盲目重跑。约束场保持开启。") end
