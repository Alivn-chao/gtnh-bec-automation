print('BEC dynamic nanites update; Q to exit the old UI first')
local rows={{name='lib/bridge.lua',source=[=[local c=require('component')
local computer=require('computer')
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local M={}
local originals={main='3afdc4cf-04e3-4ae9-8be6-e753c23a249d',sub='86311657-33d1-41b5-a0d9-0aee7b5c2c50',
 trans='66fb280f-080d-4623-8d54-0dffd5cd5aad',storage='237a9cac-118a-4b74-8755-0d0b0ad216c0',
 node='b04787f9-5423-4b03-8549-c786d4ef38d0',gen='c1ae3f7c-f714-4c27-baf3-392d94a0aa50',
 gate='cf2a0c4a-ab8d-4958-b1df-253094d6690c',rs='266f65b5-20be-4543-8f2f-bfd2d0816611',
 bees='4bebfefd-f3c6-40ac-81d6-35b331415b0f',supply='41c9711c-cb6c-4fb5-8690-9a4ff709d18b',hold='5009c70f-9607-48b1-8831-488b599942cd'}
local function source(path) local f=assert(io.open(path,'r'));local text=f:read('*a');f:close();return text end
local function replace(text,old,new)
 local escaped=old:gsub('([^%w])','%%%1')
 return text:gsub(escaped,function()return new end)
end
function M.environment(cfg,index,engine)
 C.pulse=engine.pulse;local c=C.component and C.component(c)or c
 local n,g=cfg.nodes[index],cfg.groups[cfg.nodes[index].group]
 local task=engine.tasks[index]
 local members=task.members or {index}
 local entries=task.entries or {}
 local function nodeSnapshot(paused)
  local snapshot={required={},consumed={},parallel=0,requiredTier=0,allIdle=true,allPaused=true}
  for _,i in ipairs(members) do
   local address=cfg.nodes[i].address
   local state=c.invoke(address,'getState')
   if paused then
    assert(c.invoke(cfg.nodes[i].redstone,'getOutput',cfg.nodes[i].pauseSide)==15 and (state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low'),'换蜂必须暂停整组节点')
   end
   local current=c.invoke(address,'getRequiredCondensate')
   local entry=entries[i]
   assert(entry,'生产组缺少节点快照')
   local p=type(current)=='table'and next(current)and c.invoke(address,'getParallelRecipesInProgress')or nil
   local consumed=c.invoke(address,'getConsumedCondensate')or {}
   local demand=c.invoke(address,'getRequiredTier')
   local family=type(demand)=='table'and demand.name or nil
   local needed=type(demand)=='table'and demand.tier or demand
   -- A batch can finish between these separate OC getters. Accept that edge
   -- only after reading idle AND closed next-batch permission. Keep the old
   -- requirement and consumption proof; never infer completion from nil tier.
   if state~='idle'and(type(needed)~='number'or type(current)=='table'and next(current)and(type(p)~='number'or p<=0))then
    if c.invoke(address,'getState')=='idle'and c.invoke(address,'isWorkAllowed')==false then
     state='idle';current=nil;consumed=c.invoke(address,'getConsumedCondensate')or consumed
    end
   end
   assert(not entry.finished or state=='idle','已完成节点提前接到新订单，保持整组暂停')
   if type(current)=='table' and next(current) then
    assert(type(p)=='number' and p>0,'节点并行不可读')
    local normalized={};for key,value in pairs(current)do normalized[key]=value/p end
    for key,value in pairs(task.normalized)do assert(normalized[key]==value,'生产组出现不同配方，保持暂停')end
    for key,value in pairs(normalized)do assert(task.normalized[key]==value,'生产组配方类型变化')end
    if not entry.finished then
     assert(not task.released or p==entry.parallel,'组内节点批量变化，暂停核对')
     entry.required=current;entry.parallel=p
    end
   end
   entry.consumed=entry.consumed or {}
   for key,value in pairs(consumed)do entry.consumed[key]=math.max(entry.consumed[key] or 0,value)end
   if state~='idle' then
    snapshot.allIdle=false
    -- BEC_V2_DYNAMIC_NANITES_1: tier is a live recipe phase, not recipe identity.
    -- Members can cross phase boundaries on different ticks. The controller
    -- pauses the whole cohort and supplies its maximum live requirement;
    -- normalized fluids, batch size and completed-member checks stay above.
    -- Do not overwrite entry.tier: old cohort snapshots remain recoverable.
    assert(type(needed)=='number'and needed>=1 and needed==math.floor(needed),'组内蜂群需求等级不可读，保持整组暂停')
    assert(state~='unpowered' and state~='assembler-offline','组内节点不可用: '..cfg.nodes[i].name..' / '..state)
    if needed>snapshot.requiredTier then snapshot.requiredTier=needed;snapshot.requiredFamily=family
    elseif needed==snapshot.requiredTier and snapshot.requiredFamily~=family then snapshot.requiredFamily=nil end
   elseif task.released or entry.finished or next(entry.consumed) then
    c.invoke(cfg.nodes[i].redstone,'setOutput',cfg.nodes[i].pauseSide,15)
    for key,value in pairs(entry.required)do assert((entry.consumed[key] or 0)>=value,'节点空闲但未消耗完需求，暂停核对')end
    entry.finished=true
   end
   if state~='idle' and state~='paused-immediate' and state~='nanite-tier-too-low' then snapshot.allPaused=false end
   for key,value in pairs(entry.required)do
    snapshot.required[key]=(snapshot.required[key] or 0)+value
    snapshot.consumed[key]=(snapshot.consumed[key] or 0)+(entry.consumed[key] or 0)
   end
   snapshot.parallel=snapshot.parallel+entry.parallel
  end
  snapshot.state=snapshot.allIdle and 'idle' or snapshot.allPaused and 'paused-immediate' or 'crafting'
  return snapshot
 end
 local native={};for k,v in pairs(c) do native[k]=v end
 local bulk={};for _,a in ipairs(g.bulkTransposers or {}) do bulk[a]=true end
 local function awaitLock() engine.acquire(index) end
 local function sharedHiveReady()
  local h,p=c.invoke(n.address,'getAvailableNanites'),c.invoke(n.address,'getProvidedTier')
  for _,member in ipairs(cfg.nodes)do if member.group==n.group then
   local count,tier=c.invoke(member.address,'getAvailableNanites'),c.invoke(member.address,'getProvidedTier')
   if count~=h or h>0 and not(type(p)=='table'and type(tier)=='table'and p.tier==tier.tier and p.name==tier.name)then return false end
  end end
  return true
 end
 local function cellGuard(checkHive)
  awaitLock()
  for _,member in ipairs(cfg.nodes)do if member.group==n.group then
   local state=c.invoke(member.address,'getState')
   assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15 and (state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low'),'换蜂群必须暂停整组节点')
  end end
  for _,a in ipairs(g.generators)do assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'换蜂群必须等待全部纠缠器停机')end
  assert(not task.cancel,'用户暂停蜂群操作，保留记录')
  if checkHive then assert(sharedHiveReady(),'组内蜂群仓读数不同，核对是否共用同一收容网')end
 end
 -- One fresh, complete recipe snapshot per IO check, without expanding each
 -- logical state/tier/family getter into another full cohort scan.
 local function cellInspection()
  awaitLock();assert(not task.cancel,'用户暂停蜂群操作，保留记录')
  local value=nodeSnapshot(true);local included={}
  for _,i in ipairs(members)do included[i]=true end
  for i,member in ipairs(cfg.nodes)do if member.group==n.group and not included[i]then
   local state=c.invoke(member.address,'getState')
   assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15 and (state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low'),'换蜂必须暂停整组节点')
  end end
  for _,a in ipairs(g.generators)do assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'换蜂必须等待全部纠缠器停机')end
  return value
 end

 function native.list(...)
  local iter=c.list(...)
  return function()
   while true do
    local a,t=iter();if not a then return end
    if t~='transposer' or a==g.transposer or bulk[a] then return a,t end
   end
  end
 end
 function native.invoke(a,m,...)
  local args={...}
  if g.nanites and g.nanites.enabled and g.nanites.mode=='cell-io'and
   (a==g.nanites.transposer and m=='transferItem'or (a==g.nanites.loadRedstone or a==g.nanites.returnRedstone)and m=='setOutput'and args[2]~=0)then cellGuard()end
  if g.nanites and g.nanites.enabled and g.nanites.mode~='cell-io' and (a==g.nanites.transposer or a==g.nanites.supplyInterface or a==g.nanites.hatchInterface)then
   if m=='transferItem'or m=='setInterfaceConfiguration'then
    awaitLock()
    for _,member in ipairs(cfg.nodes)do if member.group==n.group then
     local state=c.invoke(member.address,'getState')
     assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15 and (state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low'),'换蜂群必须暂停整组节点')
    end end
    for _,address in ipairs(g.generators)do assert(c.invoke(address,'isWorkAllowed')==false and c.invoke(address,'isMachineActive')==false,'换蜂群必须等待全部纠缠器停机')end
   end
  end
  if (a==cfg.mainInterface and (m=='getFluidInterfaceConfiguration' or m=='setFluidInterfaceConfiguration')) or a==g.transposer or (bulk[a] and m=='transferFluid') then awaitLock() end
  if a==n.address then
   if m=='getState' then return nodeSnapshot().state end
   if m=='getRequiredCondensate' then return nodeSnapshot().required end
   if m=='getConsumedCondensate' then return nodeSnapshot().consumed end
   if m=='getParallelRecipesInProgress' then return nodeSnapshot().parallel end
   if m=='getRequiredTier' then local value=nodeSnapshot();return value.requiredTier>0 and {tier=value.requiredTier,name=value.requiredFamily} or nil end
   if m=='getMinParallel' or m=='getMaxParallel' then
    local total=0;for _,i in ipairs(members)do total=total+c.invoke(cfg.nodes[i].address,m)end;return total
   end
  end
  if a==n.redstone and (m=='getOutput' or m=='setOutput') then
   if m=='setOutput' then
    if args[2]==0 then
     -- Close every member's next-order admission before releasing ANY member.
     for j,member in ipairs(cfg.nodes)do if member.group==n.group then
      assert(c.invoke(member.address,'isWorkAllowed')==false,'放行前传送节点必须关闭接单: '..member.name)
     end end
    end
    for _,i in ipairs(members)do
     local member=cfg.nodes[i]
     local finished=entries[i].finished or task.released and c.invoke(member.address,'getState')=='idle'
     c.invoke(member.redstone,m,member.pauseSide,finished and 15 or args[2])
    end
    if args[2]==0 then task.released=true end
    return true
   end
   for _,i in ipairs(members)do local member=cfg.nodes[i];if c.invoke(member.redstone,m,member.pauseSide)~=15 then return 0 end end
   return 15
  end
  if a==n.gate then
   local gates,seen={},{}
   for _,i in ipairs(members)do local gate=cfg.nodes[i].gate;if not seen[gate]then gates[#gates+1]=gate;seen[gate]=true end end
   if m=='setCondensateFilters' then for _,gate in ipairs(gates)do c.invoke(gate,m,args[1])end;return true end
   if m=='getCondensateFilterCount' then local size=math.huge;for _,gate in ipairs(gates)do size=math.min(size,c.invoke(gate,m))end;return size end
   if m=='isMachineActive' or m=='isWorkAllowed' then for _,gate in ipairs(gates)do if c.invoke(gate,m)~=true then return false end end;return true end
   if m=='getCondensateFilters' then
    local result=c.invoke(gates[1],m)
    for j=2,#gates do local other=c.invoke(gates[j],m);if #result~=#other then return {} end;for k,v in ipairs(result)do if other[k]~=v then return {} end end end
    return result
   end
  end
  if a==g.transposer and type(args[1])=='number' then
   local function side(v) return v==4 and g.mainSide or v==5 and g.subSide or v end
   args[1]=side(args[1]);if m=='transferFluid' then args[2]=side(args[2]) end
  end
  if g.nanites and g.nanites.enabled and g.nanites.mode~='cell-io' and a==g.nanites.transposer and type(args[1])=='number' then
   local function side(v) return v==2 and g.nanites.supplySide or v==4 and g.nanites.hatchSide or v end
   args[1]=side(args[1]);if m=='transferItem' then args[2]=side(args[2]) end
  end
  if a==g.generators[1] then
   if m=='setWorkAllowed' then
    local intent={version=2,node=index,enabled=args[1],stage='pending'}
    C.write(C.path('state/group-'..n.group..'/generators.dat'),intent)
    for _,address in ipairs(g.generators) do
     c.invoke(address,m,args[1])
     assert(c.invoke(address,'isWorkAllowed')==args[1],'纠缠器启停回读不符: '..address)
    end
    intent.stage='confirmed';C.write(C.path('state/group-'..n.group..'/generators.dat'),intent)
    if args[1] then engine.release(index) end
    return true
   elseif m=='isMachineActive' then
    for _,address in ipairs(g.generators) do if c.invoke(address,m)==true then return true end end;return false
   elseif m=='isWorkAllowed' then
    for _,address in ipairs(g.generators) do if c.invoke(address,m)~=true then return false end end;return true
   end
  end
  return c.invoke(a,m,table.unpack(args))
 end
 local env=setmetatable({}, {__index=_G});env._ENV=env
 -- Explicit logical read only: always scans every member anew, never memoizes
 -- across a yield, component call, or hardware mutation. This is not an OC API
 -- or an atomic server-side snapshot.
 env.BEC_V2_PHASE=function(stage)if engine.phase then engine.phase(index,stage)end end
 -- OC reads across a cohort can exceed the original single-node 3-second grace.
 env.BEC_V2_RELEASE_GRACE=30
 env.BEC_V2_NODE_SNAPSHOT=nodeSnapshot
 env.BEC_V2_COHORT_IDLE=function()
  local value=nodeSnapshot()
  assert(value.allIdle,'批次节点状态已改变，保留现场核对')
  for _,i in ipairs(members)do assert(entries[i].finished,'本批节点已空闲但缺少完整消耗证明，保留日志核对')end
  return true
 end
 -- Gate setup validates the complete recipe once before writing, then checks
 -- every member's actual pause state/output in each of the three readbacks.
 -- The controller performs a fresh full current() check immediately afterward,
 -- before any fluid transfer, generator start, or production release.
 env.BEC_V2_GATE_STATE=function(full)
  if full then return nodeSnapshot().state end
  assert(not task.cancel,'用户暂停节点，保留进度')
  local allIdle,allPaused=true,true
  for _,i in ipairs(members)do
   local member=cfg.nodes[i];local state=c.invoke(member.address,'getState')
   assert(entries[i]and(not entries[i].finished or state=='idle'),'已完成节点提前接到新订单，保持整组暂停')
   assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15,'过滤回读期间节点暂停信号变化')
   if state~='idle'then allIdle=false end
   if state~='idle'and state~='paused-immediate'and state~='nanite-tier-too-low'then allPaused=false end
  end
  return allIdle and 'idle'or allPaused and 'paused-immediate'or 'crafting'
 end
 local sleeping={};for k,v in pairs(os) do sleeping[k]=v end
 sleeping.sleep=function(seconds)
  if task.cancel then error('用户暂停节点，保留进度') end
  coroutine.yield('wait',computer.uptime()+(seconds or 0))
  if task.cancel then error('用户暂停节点，保留进度') end
 end
 env.os=sleeping
 env.print=function(...)local parts={...};for i,v in ipairs(parts)do parts[i]=tostring(v)end;engine.log(index,table.concat(parts,' '))end
 env.require=function(name)
  if name=='component' then return native end
  if name=='event' then return {pull=function(seconds)
   coroutine.yield('wait',computer.uptime()+(seconds or 0.1))
   if task.cancel then return 'key_down','v2',113,16 end
  end} end
  return require(name)
 end
 local mapping={[originals.main]=cfg.mainInterface,[originals.sub]=g.subInterface,[originals.trans]=g.transposer,
 [originals.storage]=g.storage,[originals.node]=n.address,[originals.gen]=g.generators[1],[originals.gate]=n.gate,[originals.rs]=n.redstone}
 if g.nanites and g.nanites.enabled and g.nanites.mode~='cell-io' then
  mapping[originals.bees]=g.nanites.transposer;mapping[originals.supply]=g.nanites.supplyInterface;mapping[originals.hold]=g.nanites.hatchInterface
 end
 if g.nanites and g.nanites.enabled and g.nanites.mode=='cell-io'then
  env.BEC_CELL_IO={};for key,value in pairs(g.nanites)do env.BEC_CELL_IO[key]=value end
  env.BEC_CELL_IO.node=n.address;env.BEC_CELL_IO.redstone=n.redstone;env.BEC_CELL_IO.pauseSide=n.pauseSide
  env.BEC_CELL_IO.path=C.path('state/group-'..n.group..'/nanites-cell.journal')
  env.BEC_CELL_IO.checkGroup=cellGuard
  env.BEC_CELL_IO.inspect=cellInspection
  env.BEC_CELL_IO.checkSharedHive=function()cellGuard(true)end
  env.BEC_CELL_IO.sharedHiveReady=sharedHiveReady
 end
 local function instantiate(path)
  local text=source(path)
  text=text:gsub('%x+%-%x+%-%x+%-%x+%-%x+',function(a)return mapping[a]or a end)
  text=replace(text,'"266f65b5"',string.format('%q',n.redstone))
  text=replace(text,'"c1ae3f7c"',string.format('%q',g.generators[1]))
  text=replace(text,'"/home/bec_auto.journal"',string.format('%q',C.path('state/node-'..index..'/production.journal')))
  text=replace(text,"'/home/bec_nanites.journal'",string.format('%q',C.path('state/group-'..n.group..'/nanites.journal')))
  text=replace(text,'"/home/bec/recipes"',string.format('%q',cfg.recipeDirectory))
  text=replace(text,'"/home/bec/recipes/"',string.format('%q',cfg.recipeDirectory..'/'))
  return assert(load(text,path,'t',env))
 end
 env.loadfile=function(path)
  if path=='/home/bec_nanites.lua' then
   if not g.nanites or not g.nanites.enabled then return function()return {ensure=function()return false end}end end
   local other=C.read(C.path('state/group-'..n.group..'/'..(g.nanites.mode=='cell-io'and 'nanites.journal'or 'nanites-cell.journal')))
   assert(not other or other.stage=='done','另一蜂群模式存在未完成记录，不能切换或重放')
   return instantiate(C.path(g.nanites.mode=='cell-io'and 'runtime/nanites_cell.lua'or 'runtime/nanites.lua'))
  end
  error('V2工作器禁止调用稳定版脚本: '..tostring(path))
 end
 return instantiate(C.path('runtime/controller.lua'))
end
return M
]=],supported={['14972:1082549461']=true,['15577:279131571']=true,['15577:279131571']=true,['15577:279131571']=true,['15577:279131571']=true,['15577:279131571']=true,['15577:279131571']=true,['15577:279131571']=true}},{name='runtime/controller.lua',source=[=[local c = require("component") local ser = require("serialization") local computer = require("computer") local fs = require("filesystem")
local sides = require("sides") local event = require("event") local mode = (...) or "preview" local JOURNAL = "/home/bec_auto.journal"
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d" local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50" local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad" local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0"
local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0" local GATE_ADDRESS = "cf2a0c4a-ab8d-4958-b1df-253094d6690c" local RS, GEN, GATE, armed, record local stopping=false
local NANITES=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")()
local lastNaniteTier,lastNaniteFamily
local mapping = { entangled_infinity = "molten.infinity", entangled_chromaticglass = "molten.chromaticglass", entangled_transcendentmetal = "molten.transcendentmetal",
entangled_dimshiftedsuperfluid = "dimensionallyshiftedsuperfluid", entangled_neutronium="molten.neutronium",entangled_cosmicneutronium="molten.cosmicneutronium", entangled_bedrockium="molten.bedrockium",entangled_celestialtungsten="molten.celestialtungsten", entangled_hypogen="molten.hypogen",entangled_phononmedium="phononmedium",
entangled_quarkgluonplasma="quarkgluonplasma",entangled_spacetime="molten.spacetime", entangled_time="molten.temporalfluid",entangled_space="molten.spatialfluid", entangled_cosmicsolder="boundlesscosmicsolder", entangled_mhdcsm="molten.magnetohydrodynamicallyconstrainedstarmatter",
entangled_magmatter="molten.magmatter",entangled_universium="molten.universium", entangled_eternity="molten.eternity" } local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000,
entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000} local function call(a, m, ...) return c.invoke(a, m, ...) end local function method(a, m) assert(c.methods(a)[m] ~= nil, "组件缺少方法: " .. m)
end local function resolve(prefix, kind) local address, count = nil, 0 for a, t in c.list() do
if a:sub(1, #prefix) == prefix and t == kind then address, count = a, count + 1 end end
assert(count == 1, "目标组件缺失或不唯一: " .. prefix) return address end local function integer(v)
assert(type(v) == "number" and v >= 0 and v == math.floor(v), "库存/需求数量无效") return v end local function same(a, b)
for k, v in pairs(a) do if b[k] ~= v then return false end end for k, v in pairs(b) do if a[k] ~= v then return false end end return true end
local function network(a) local rows, result = call(a, "getFluidsInNetwork"), {} assert(type(rows) == "table", "网络库存不可读") for _, f in pairs(rows) do
assert(type(f) == "table", "流体条目无效") local n = integer(f.amount or f.size or 0) if n > 0 then assert(type(f.name) == "string", "流体名称缺失")
result[f.name] = (result[f.name] or 0) + n end end return result
end local matchedOutputs, perRecipe local function checkRecipe(required,parallel) parallel=parallel or integer(call(NODE,"getParallelRecipesInProgress"))
assert(parallel>0 and type(required)=="table","当前配方并行/需求不可读") local normalized={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0 and n%parallel==0,"配方需求无法按并行拆分: "..tostring(name))
normalized[name]=n/parallel end local matches={} if fs.exists("/home/bec/recipes") then
for file in fs.list("/home/bec/recipes") do if file:match("%.dat$") then local f=assert(io.open("/home/bec/recipes/"..file,"r"));local r=ser.unserialize(f:read("*a"));f:close() assert(type(r)=="table","登记配方损坏: "..file)
if r.state=="converted" then local needs={} for _,fluid in ipairs(r.condensates or {}) do needs[fluid.name]=(needs[fluid.name] or 0)+integer(fluid.amount or fluid.size) end if same(needs,normalized) then
assert(type(r.outputs)=="table" and #r.outputs==1,"登记产物无效: "..file) matches[#matches+1]=r.outputs[1] end end
end end end if #matches>0 then
local provided=call(NODE,"getProvidedTier") if c.methods(NODE).getRequiredTier~=nil then local needed=call(NODE,"getRequiredTier") local tier=type(needed)=="table" and needed.tier or needed
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
local demand=call(NODE,"getRequiredTier");local family=type(demand)=="table"and demand.name or nil
local needed=type(demand)=="table" and demand.tier or demand
if type(needed)~="number" then return end
if BEC_V2_PHASE then BEC_V2_PHASE("nanites")end
local started=computer.uptime();print("检查蜂群 / 准备换盘")
NANITES.ensure({tick=tick,stopping=function() return stopping end})
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
assert(call(RS,"getOutput",sides.top)==15 and gateNodeState(true)=="paused-immediate",
"切换门过滤前节点必须立即暂停") local expected=gateFilters(required) assert(integer(call(GATE,"getCondensateFilterCount"))>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters")
assert(type(actual)=="table","麦克斯韦门过滤不可读") record.gateIntent={address=GATE,filters=expected};save(record.stage) if not same(actual,expected) then call(GATE,"setCondensateFilters",expected) end for i=1,3 do
verifyGate(expected) assert(gateNodeState(false)=="paused-immediate","设置过滤时订单状态变化") if i<3 then tick(0.1) end end
print("麦克斯韦门过滤: "..table.concat(expected,", ")..string.format(" / 确认 %.2f 秒",computer.uptime()-started)) return expected end local function tanks(side, name)
local count, amount = integer(call(TRANS, "getTankCount", side)), 0 assert(count > 0, "接口没有流体槽") for i = 1, count do local f = call(TRANS, "getFluidInTank", side, i)
assert(type(f) == "table", "接口缓存不可读") if type(f[1]) == "table" then f = f[i] or f[1] end local n = integer(f.amount or 0) if n > 0 then
assert(name and f.name == name, "接口有未处理流体缓存") amount = amount + n end end
return amount end local function emptyConfig() for slot = 0, 5 do
assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置") end end local function current(recovering)
-- V2 bridge can read all four adjacent fields in one fresh group scan.
-- Outside that bridge, retain the original component getter path.
local snapshot=type(BEC_V2_NODE_SNAPSHOT)=="function" and BEC_V2_NODE_SNAPSHOT() or nil
local state=snapshot and snapshot.state or call(NODE,"getState") local unavailable=state=="assembler-offline" or state=="unpowered" or state=="nanite-tier-too-low" assert(state=="paused-immediate" or (recovering and unavailable and call(RS,"getOutput",sides.top)==15),"订单未处于立即暂停状态")
local parallel=integer(snapshot and snapshot.parallel or call(NODE, "getParallelRecipesInProgress")) assert(parallel>=1,"暂停节点没有正在处理的配方") local required, consumed
if snapshot then required,consumed=snapshot.required,snapshot.consumed else required,consumed=call(NODE,"getRequiredCondensate"),call(NODE,"getConsumedCondensate")end
assert(type(required) == "table" and type(consumed) == "table", "订单需求不可读")
local remaining, total = {}, 0 for name, amount in pairs(required) do assert(mapping[name], "不支持的凝聚物: " .. tostring(name)) amount = integer(amount)
local used = integer(consumed[name] or 0) assert(used <= amount, "已消耗数量超过需求") remaining[name] = amount - used; total = total + amount end
assert(total > 0, "订单没有有效需求") for name, amount in pairs(consumed) do assert(integer(amount) == 0 or required[name], "消耗记录与当前订单不符") end
checkRecipe(required,parallel) return required, remaining end local function queuedRecipes() return 0 end local function batchTarget(required,remaining)
local parallel=checkRecipe(required) local count=math.max(parallel,queuedRecipes()) local target={} for name,amount in pairs(required) do
target[name]=remaining[name]+perRecipe[name]*(count-parallel) assert(target[name]<=2147483647,"整批需求过大") end return target,count
end local function unchanged() local req, remaining = current() assert(same(req, record.required) and same(remaining, record.remaining), "暂停订单发生变化，停止")
end local function resolveRawNames(target) local main,sub,stock=network(MAIN),network(SUB),field() for kind,need in pairs(target) do
if kind=="entangled_space" or kind=="entangled_time" then local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" local candidates={[stem]=true,["molten."..stem]=true,["fluid."..stem]=true,["fluid.molten."..stem]=true} local found={}
for name in pairs(candidates) do if (main[name] or 0)>0 or (sub[name] or 0)>0 then found[name]=true end local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败")
for _,craft in pairs(rows) do local f=craft.getStack() if type(f)=="table" and f.name==name then found[name]=true end end
end local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"空间/时间原液名称不唯一: "..kind) assert(n==1 or (stock[kind] or 0)>=need,"主网缺少空间/时间原液库存或样板: "..kind)
if n==1 then mapping[kind]=name end end end end
local function plan(remaining,quiet) resolveRawNames(remaining) local stock, sub, main = field(), network(SUB), network(MAIN) local moves, expected, allowed, shortages, deficits = {}, {}, {}, {}, {}
for name, need in pairs(remaining) do local raw = mapping[name] allowed[raw] = true local unit=units[name] or 144
local required = math.ceil(math.max(0, need - (stock[name] or 0)) / unit) * unit local existing = sub[raw] or 0 assert(existing <= required and existing % unit == 0, "子网原液超额或非整批: " .. raw) local missing = required - existing
if (main[raw] or 0)<missing then deficits[#deficits+1]={raw=raw,amount=missing-(main[raw] or 0),needed=missing} shortages[#shortages+1]=raw..": 本次需补 "..missing.." mB，主网有 "..(main[raw] or 0) .."，还缺 "..(missing-(main[raw] or 0)).." mB"
end if required > 0 then expected[raw] = required end local left=missing while left>0 do
local chunk=math.min(left,math.floor(16000/unit)*unit) moves[#moves+1]={raw=raw,amount=chunk};left=left-chunk end if not quiet then print(raw .. " 本次补入 " .. missing .. " mB") end
end for raw in pairs(sub) do assert(allowed[raw], "子网有无关原液: " .. raw) end for name, amount in pairs(stock) do assert(amount == 0 or mapping[name], "约束场有未知凝聚物: " .. name)
end table.sort(moves, function(a,b) return a.raw < b.raw end) if #shortages>0 then table.sort(shortages)
local message=table.concat(shortages,"；") if not quiet then print("缺料: "..message.."；运行时向主网 AE 申请缺口") end table.sort(deficits,function(a,b) return a.raw<b.raw end) return nil,message,deficits
end return moves, sub, expected end local function waitUntil(seconds, condition, guard,label)
local deadline = computer.uptime() + seconds while true do local ready, snapshot = condition() if ready then return end
if guard then guard(snapshot) end assert(computer.uptime() < deadline, "等待超时，停止"..(label and "："..label.." / 实际状态 "..tostring(snapshot)or "")) os.sleep(0.25) end
end local function bulkPorts() local allowed,ports={},{} for _,raw in pairs(mapping) do allowed[raw]=true end
for address,kind in c.list("transposer") do if kind=="transposer" and address~=TRANS then local sources,receivers={},{} for side=0,5 do
local ok,count=pcall(call,address,"getTankCount",side) if ok and count==1 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==2147483647 then
local f=call(address,"getFluidInTank",side,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end if type(f)=="table" and allowed[f.name] then sources[#sources+1]={from=side,raw=f.name} end end
elseif ok and count==6 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==16000 then receivers[#receivers+1]=side end end
end if #sources>0 then assert(#receivers==1,"高速供液口接收方向缺失或不唯一: "..address) for _,source in ipairs(sources) do
assert(not ports[source.raw],"高速供液口重复绑定: "..source.raw) ports[source.raw]={address=address,from=source.from,to=receivers[1]} end end
end end return ports end
local function verifyBulk(route,raw) local f=call(route.address,"getFluidInTank",route.from,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end assert(type(f)=="table" and f.name==raw
and call(route.address,"getTankCapacity",route.from,1)==2147483647,"高速缓存口绑定已变化") assert(call(route.address,"getTankCount",route.to)==6,"高速接收接口已变化") for i=1,6 do local tank=call(route.address,"getFluidInTank",route.to,i)
if type(tank)=="table" and type(tank[1])=="table" then tank=tank[i] or tank[1] end assert(type(tank)=="table" and integer(tank.amount or 0)==0,"高速接收接口有未处理缓存") end end
local function prepareStreaming(target) resolveRawNames(target) local ports=bulkPorts() local stock,previous=field(),network(SUB)
local expected,raws={},{} for name,need in pairs(target) do local raw=mapping[name] local batch=units[name] or 144
local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0 assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end
raws[#raws+1]={raw=raw,amount=amount,batch=batch} end for raw in pairs(previous) do local allowed=false
for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end
table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned") for _,item in ipairs(raws) do local raw,need,batch=item.raw,item.amount,item.batch
local route=ports[raw] local chunk=math.floor((route and 2147483647 or 16000)/batch)*batch local function bufferedInlet() return route and 0 or tanks(4,raw) end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=route==nil;save("stream-configuring") if route then verifyBulk(route,raw)
print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to) else assert(call(MAIN,"setFluidInterfaceConfiguration",0, {name=raw,amount=math.min(need-(previous[raw] or 0),chunk),
size=math.min(need-(previous[raw] or 0),chunk)})==true,"持续供液配置失败") end print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt
local attempts=0 local inletOpen=route==nil local deadline=computer.uptime()+1800 while not stopping do
unchanged();assert(same(field(),stock),"备料时约束场库存变化") assert(same(network(SUB),previous),"备料时子网库存变化") local remaining=need-(previous[raw] or 0) local buffered=route and (network(MAIN)[raw] or 0) or bufferedInlet()
local amount=math.floor(math.min(remaining,buffered,chunk)/batch)*batch if amount>0 then local address,from,to=TRANS,4,5 if route then verifyBulk(route,raw);address,from,to=route.address,route.from,route.to end
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to} save("transfer-returned")
assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试") previous[raw]=(previous[raw] or 0)+amount waitUntil(10,function() return same(network(SUB),previous) end,unchanged) record.pending=nil;record.secured=previous;save("stream-transfer-confirmed")
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
end attempts=attempts+1;assert(attempts<=3,"原液仍被争抢，暂停保留已收获库存") missing=math.max(0,need-(previous[raw] or 0)-bufferedInlet()-(network(MAIN)[raw] or 0)) if missing>0 then
job={raw=raw,amount=missing,unit="mB",state="pending",securedBefore=previous[raw] or 0} record.requests[#record.requests+1]=job;save("craft-request-pending") local reason;status,reason=craft.request(missing) assert(status~=nil,"AE 申请未确认: "..tostring(reason))
job.state="submitted";jobDeadline=computer.uptime()+1800;doneAt=nil save("stream-crafting") print("主网 AE 申请 "..raw.." "..missing.." mB；合成中持续收料。") end
end end end assert(computer.uptime()<deadline,"持续收料超时，保留子网已搬入原液")
tick(0.1) end if inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败")
record.configOwned=false;save("stream-inlet-cleared") end waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) if stopping then return expected end
end end assert(same(network(SUB),expected),"整批子网原液不符") record.plan=nil;save("stream-prepared")
return expected end local function completedIdle(state)
if state~="idle" or not BEC_V2_COHORT_IDLE then return false end
assert(BEC_V2_COHORT_IDLE());return true
end local function serve() local waiting={idle=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
local round=0 while not stopping do local nanitesChecked=false;pause(15); generator(false) local state=call(NODE,"getState")
if stopping then break end state=call(NODE,"getState")
if state=="idle" and BEC_V2_COHORT_IDLE then assert(BEC_V2_COHORT_IDLE());print("本批节点已完成，消耗核对通过；结束旧批次并交回设备组调度。") break end
if state=="paused-immediate" or state=="nanite-tier-too-low" then switchNanites();nanitesChecked=true;state=call(NODE,"getState") end if waiting[state] then
if state~=record.lastState then print("等待订单/机器就绪: "..state.."；任意数量同配方订单均可，按 Q 停止。") record.lastState=state;save("waiting") end
field();tick(0.1) else local completed=false;waitUntil(10,function() local v=call(NODE,"getState");completed=completedIdle(v)
return v=="paused-immediate"or completed,v end,function(v) assert(v=="crafting" or waiting[v],"无法暂停，实际状态: "..tostring(v)) field()
end,"备料前暂停/完成核对") if completed then print("暂停等待期间本批已完成，消耗核对通过；交回调度。");break end;if not nanitesChecked then switchNanites()end;if stopping then break end record.required,record.remaining=current() local target,count=batchTarget(record.required,record.remaining) local stable=false
for i=1,20 do tick(0.25);unchanged() local nextTarget,nextCount=batchTarget(record.required,record.remaining) if same(target,nextTarget) then stable=true;break end
target,count=nextTarget,nextCount end assert(stable,"主网任务清单持续变化，保持暂停") if stopping then break end
record.batchCount=count print("本组当前配方 "..count.." 份；当前实际并行 "..checkRecipe(record.required) .."；一次准备整批所需流体。") round=round+1;record.round=round;record.transfers={};record.target=target;record.plan=nil;record.topups={}
waitUntil(10,function() return call(GEN,"isMachineActive")==false end) emptyConfig();tanks(4,nil);tanks(5,nil) local filters=configureGate(record.required) unchanged()
if stopping then break end local expected=prepareStreaming(target) if stopping then break end for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end
save("converting");generator(true) local conversionLimit=180 for name,need in pairs(target) do conversionLimit=conversionLimit+math.ceil(need/(units[name] or 144))*180 end waitUntil(conversionLimit,function()
local stock=field() for name,need in pairs(target) do if (stock[name] or 0)<need then return false end end return true end,unchanged)
unchanged();generator(false) record.plan=nil;record.lastState=nil;save("watching") if not stopping then verifyGate(filters);unchanged()
if BEC_V2_PHASE then BEC_V2_PHASE("producing")end pause(0) print("整批流体齐备，已连续放行；本组同配方节点已同时放行。按 Q 停止。") local releasedAt=computer.uptime() local deadline=releasedAt+600
local lastStock=field() local lastRequired=record.required local nextQueueCheck=0 while not stopping do
local v=call(NODE,"getState") local stock=field() local req=call(NODE,"getRequiredCondensate") verifyGate(filters)
local demand=call(NODE,"getRequiredTier");local family=type(demand)=="table"and demand.name or nil
local needed=type(demand)=="table" and demand.tier or demand
local supplied=call(NODE,"getProvidedTier")
if type(needed)=="number" and (needed~=lastNaniteTier or family~=lastNaniteFamily or type(supplied)~="table" or supplied.tier<needed) then
pause(15);local completed=false;waitUntil(10,function() local s=call(NODE,"getState");completed=completedIdle(s);return s=="paused-immediate" or s=="nanite-tier-too-low"or completed,s end,nil,"换蜂前暂停/完成核对")
if completed then print("换蜂暂停期间本批已完成，消耗核对通过；无需再换蜂。");stopping=true;break end
switchNanites();if stopping then break end;verifyGate(filters);pause(0);releasedAt=computer.uptime();deadline=releasedAt+600;if BEC_V2_PHASE then BEC_V2_PHASE("producing")end;v=call(NODE,"getState")
end
local parallel if req~=nil then parallel=integer(call(NODE,"getParallelRecipesInProgress")) local matching=parallel>0
for name,n in pairs(req) do if not perRecipe[name] or n~=perRecipe[name]*parallel then matching=false end end for name in pairs(perRecipe) do if req[name]==nil then matching=false end end if not matching then pause(15);break end if not same(gateFilters(req),filters) then pause(15);break end
lastRequired=req end if v=="idle" then local consumed=call(NODE,"getConsumedCondensate")
assert(type(consumed)=="table","节点空闲后消耗记录不可读") for name,need in pairs(lastRequired) do assert(integer(consumed[name] or 0)>=need, "节点进入空闲但凝聚物未消耗完，可能故障关闭: "..name.."；需求 "..need.."，已消耗 "..tostring(consumed[name] or 0))
end stopping=true;break end if waiting[v] then break end
assert(v=="crafting" or (v=="paused-immediate" and computer.uptime()-releasedAt<(BEC_V2_RELEASE_GRACE or 3)), "节点运行异常: "..tostring(v)) local refill=false if computer.uptime()>=nextQueueCheck and req~=nil then
local consumed=call(NODE,"getConsumedCondensate") assert(type(consumed)=="table","当前消耗记录不可读") local fresh=call(NODE,"getRequiredCondensate") if type(fresh)~="table" or not same(req,fresh) or parallel~=call(NODE,"getParallelRecipesInProgress") then pause(15);break end
local count=math.max(1,queuedRecipes()) for name,amount in pairs(req) do local need=perRecipe[name]*math.max(parallel,count)-integer(consumed[name] or 0) if (stock[name] or 0)<need then refill=true end
end nextQueueCheck=computer.uptime()+1 end if refill then break end
if not same(stock,lastStock) then deadline=computer.uptime()+600;lastStock=stock end assert(computer.uptime()<deadline,"当前配方运行超时") tick(0.1) end
end end end pause(15);generator(false);record.configOwned=false
for _,job in ipairs(record.requests) do if job.state~="done" then save("craft-paused") print("服务已暂停；主网原液申请仍需核对，保留日志，不重复下单。")
return end end save("stopped")
print("已停止常驻服务：暂停输出 15，纠缠装置关闭；约束场与已有凝聚物保持开启。") end local function main() assert(mode=="preview" or mode=="run" or mode=="resume" or mode=="restock", "用法: preview / run / resume / restock，无需填写数量")
RS = resolve("266f65b5", "redstone") GEN = resolve("c1ae3f7c", "gt_machine") GATE = resolve(GATE_ADDRESS, "bec_diode") assert(call(GEN, "getName") == "multi.bec.generator", "纠缠装置名称不符")
for _, item in ipairs({{RS,"setOutput"},{RS,"getOutput"},{GEN,"setWorkAllowed"}, {GEN,"isWorkAllowed"},{GEN,"isMachineActive"},{MAIN,"getFluidsInNetwork"}, {MAIN,"setFluidInterfaceConfiguration"},{MAIN,"getFluidInterfaceConfiguration"}, {SUB,"getFluidsInNetwork"},{TRANS,"transferFluid"},
{MAIN,"getCraftables"},{MAIN,"getCpus"},{GATE,"getCondensateFilterCount"}, {GATE,"getCondensateFilters"},{GATE,"setCondensateFilters"}, {GATE,"isWorkAllowed"},{GATE,"isMachineActive"}}) do method(item[1],item[2]) end local minimum,maximum=integer(call(NODE,"getMinParallel")),integer(call(NODE,"getMaxParallel"))
assert(minimum>=1 and maximum>=minimum,"节点并行设置无效") print("远端红石: " .. RS .. "；纠缠装置: " .. GEN) print("节点: " .. call(NODE,"getState") .. "；向上输出: " .. call(RS,"getOutput",sides.top)) print("纠缠装置允许工作: " .. tostring(call(GEN,"isWorkAllowed")))
print("麦克斯韦门: "..GATE.."；过滤: "..ser.serialize(call(GATE,"getCondensateFilters"),false) .."；运行: "..tostring(call(GATE,"isMachineActive"))) print("凝聚物库存: " .. ser.serialize(field(),false)) if mode == "preview" then
print("子网原液: " .. ser.serialize(network(SUB),false)) if call(NODE,"getState") == "paused-immediate" then local required,remaining=current();local target,count=batchTarget(required,remaining) print("本组当前配方 "..count.." 份")
plan(target) end print("预览结束：没有开关、搬液、配置或写日志。") return
end local waitingStates = {idle=true, ["paused-immediate"]=true, ["assembler-offline"]=true, unpowered=true, ["nanite-tier-too-low"]=true} local initialState = call(NODE,"getState")
assert(waitingStates[initialState], "节点状态不适合启动: " .. tostring(initialState)) emptyConfig(); tanks(4,nil); tanks(5,nil) if fs.exists(JOURNAL) then local f=assert(io.open(JOURNAL,"r"));local contents=f:read("*a");f:close()
local old=ser.unserialize(contents) local streaming=type(old)=="table" and type(old.plan)=="table" and (old.stage=="stream-configuring" or old.stage=="stream-transfer-confirmed" or old.stage=="stream-inlet-cleared" or old.stage=="stream-planned")
and type(old.secured)=="table" and type(old.target)=="table" assert(type(old)=="table" and old.version==1 and old.kind=="continuous" and old.pending==nil and (old.configOwned==false or streaming),"日志无效或有未确认操作，禁止重跑") if mode=="resume" or mode=="restock" then
local stopped=old.stage=="stopped" and old.plan==nil and type(old.transfers)=="table" local preTransfer=(old.stage=="starting" or old.stage=="waiting" or old.stage=="waiting-stock") and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil and (old.requests==nil or next(old.requests)==nil)
local watching=(old.stage=="watching" or old.stage=="waiting") and old.plan==nil and type(old.transfers)=="table" and type(old.target)=="table" local crafted=old.stage=="craft-done" and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil
and type(old.requests)=="table" and next(old.requests)~=nil local prepared=old.stage=="stream-prepared" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table"
local converting=old.stage=="converting" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table" and type(old.required)=="table" and type(old.remaining)=="table" if stopped or watching or crafted or prepared or converting or streaming then
for _,move in ipairs(old.transfers) do assert(move.ok==true and type(move.amount)=="number" and move.amount>0, "旧搬运未确认，禁止恢复") end
for _,job in ipairs(old.requests or {}) do assert(job.state=="done","原液申请未完成，禁止重复申请") end assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false
and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置已停机") if streaming then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"供液恢复订单变化，暂停核对")
assert(same(network(SUB),old.secured),"已确认搬运与子网库存不符，禁止恢复") resolveRawNames(old.target) local expected,stock={},field() for name,need in pairs(old.target) do
local unit=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/unit)*unit local raw=mapping[name];if amount>0 then expected[raw]=amount end local held=old.secured[raw] or 0
assert(held<=amount and held%unit==0,"供液恢复子网超额或非整批") end for raw in pairs(old.secured) do assert(expected[raw],"供液恢复子网有无关原液") end print("供液恢复核对通过；保留已搬入原液，只补当前缺口。")
end if crafted then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"旧申请订单已变化，暂停核对")
print("已完成原液申请已归档；按当前真实库存重新计算缺口。") end if prepared then current(true)
assert(same(network(SUB),old.expected),"已备齐原液与日志不符，暂停核对") print("整批原液已在子网，恢复时抵扣，不重复搬料或申请。") end if converting then
local req,remaining=current(true) resolveRawNames(old.target) local target=old.target if not (same(req,old.required) and same(remaining,old.remaining)) then
local count;target,count=batchTarget(req,remaining) assert(type(old.batchCount)=="number" and count<=old.batchCount, "恢复时订单增加或旧批量缺失，暂停核对") for name,need in pairs(target) do assert(need<=integer(old.target[name]),"恢复需求超过旧整批目标") end
print("实际并行/消耗已变化，按 AE 剩余订单扣除节点已消耗量核对库存。") end local sub,stock=network(SUB),field() for name,value in pairs(target) do
local raw=mapping[name] local need=integer(value) local liquid,condensate=integer(sub[raw] or 0),integer(stock[name] or 0) local unit=units[name] or 144
assert(liquid%unit==0 and condensate%unit==0 and (liquid+condensate==need or (mode=="restock" and liquid+condensate<need)), "转换恢复库存不符: "..raw.."；子网 "..liquid.." + 凝聚物 "..condensate.."，目标 "..need) if liquid+condensate<need then print(raw.." 当前缺口 "..(need-liquid-condensate).." mB；归档旧操作后重新备料。") end
end for raw in pairs(sub) do local allowed=false;for _,known in pairs(mapping) do if known==raw then allowed=true end end assert(allowed,"转换恢复子网有无关原液")
end for name,n in pairs(stock) do assert(n==0 or mapping[name],"转换恢复有无关凝聚物") end print("转换恢复核对通过，抵扣当前库存；已完成的旧申请和搬运记录保留归档。") end
end assert(stopped or preTransfer or watching or crafted or prepared or converting or streaming,"该阶段存在未确认操作，不能自动恢复") archiveJournal(contents,".before-resume-") else
assert(old.stage=="stopped","已有非正常停止日志，请核对后使用 resume，禁止盲目重跑") for _,job in ipairs(old.requests or {}) do assert(job.state=="done","旧日志有未确认的主网申请，禁止重新下单") end
archiveJournal(contents) end else assert(mode~="resume" and mode~="restock","没有可恢复的日志")
end record={version=1,kind="continuous",stage="starting",transfers={},requests={},configOwned=false} save("starting");armed=true print("常驻模式：无需填写数量。先只提交原始屏蔽层任务，可先 5 再 10。")
print("按主网 CPU 剩余任务量，一次准备整批原液；追加订单自动补差额。") serve() end local ok, err = xpcall(main, debug.traceback)
if not ok then if armed then local paused = pcall(pause,15) local stopped = pcall(generator,false)
local cleaned = true if record and record.configOwned then local success, result = pcall(call,MAIN,"setFluidInterfaceConfiguration",0) cleaned = success and result == true
end print("恢复暂停: " .. tostring(paused) .. "；关闭纠缠装置: " .. tostring(stopped) .. "；清供液配置: " .. tostring(cleaned)) if not paused then print("请手动提供控制仓暂停信号。") end end
print("程序停止: " .. tostring(err)) print("保留现场与日志；不要删除日志盲目重跑。约束场保持开启。") end
]=],supported={['37080:3439859331']=true,['37104:3097960326']=true,['37104:3097960326']=true,['37104:3097960326']=true,['37104:3097960326']=true,['37104:3097960326']=true,['37104:3097960326']=true,['37104:3097960326']=true}},{name='runtime/nanites_cell.lua',source=[=[-- V2 module: whole-cell transfers through the verified south/north ME IO ports.
local c=require('component')
local ser=require('serialization')
local fs=require('filesystem')
local clock=require('computer')
local cfg=assert(BEC_CELL_IO,'缺少V2蜂群硬盘配置')
local T,SOUTH,NORTH=cfg.transposer,cfg.loadRedstone,cfg.returnRedstone
local PAUSE,NODE=cfg.redstone,cfg.node
local PATH=cfg.path
local binding={T,SOUTH,NORTH,cfg.bankSide,cfg.loadSide,cfg.returnSide,cfg.loadOutputSide,cfg.returnOutputSide}
local function sameBinding(old)
 if type(old)~='table'then return false end
 for i,v in ipairs(binding)do if old[i]~=v then return false end end
 return #old==#binding
end
local CELL='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'
local DISPLAY_CAP,MIN=30720,64 -- Machine reading limit, not a transfer limit.
-- NaniteTier enum -> material ore name. Labels may be localized.
local tiers={Carbon={1,'Carbon'},Glowstone={1,'Glowstone'},Silver={2,'Silver'},
 Neutronium={2,'Neutronium'},Gold={3,'Gold'},TranscendentMetal={4,'Transcendent'},
 SixPhasedCopper={5,'SixPhasedCopper'},WhiteDwarfMatter={6,'WhiteDwarf'},
 BlackDwarfMatter={7,'BlackDwarf'},Universium={8,'Universium'},Eternity={9,'Eternity'},MagMatter={10,'MagMatter'}}
local record,context
local prepStarted,firstMoveStarted
local function call(a,m,...)
 local args={...}
 if a==T and type(args[1])=='number' then
  local function side(v)return v==0 and cfg.bankSide or v==2 and cfg.returnSide or v==3 and cfg.loadSide or v end
  args[1]=side(args[1]);if m=='transferItem'then args[2]=side(args[2])end
 end
 if (a==SOUTH or a==NORTH)and(m=='getOutput'or m=='setOutput')and args[1]==0 then
  args[1]=a==SOUTH and cfg.loadOutputSide or cfg.returnOutputSide
 end
 return c.invoke(a,m,table.unpack(args))
end
local function whole(n) return type(n)=='number' and n>=0 and n%1==0 end
local function read(path)
 local f=io.open(path,'r');if not f then return end
 local v=f:read('*a');f:close();return v
end
local function write(path,text)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(path)==text,'蜂群IO日志回读失败')
end
local function oldRecord()
 local text=read(PATH);if not text then return end
 local r=ser.unserialize(text)
 assert(type(r)=='table' and r.version==2 and r.kind=='cell-io','蜂群IO日志损坏，保留现场')
 return r
end
local function save(stage)
 record.stage=stage
 local old=read(PATH);if old then write(PATH..'.previous',old) end
 write(PATH,ser.serialize(record,false))
end
local function archive()
 local old=read(PATH);if not old then return end
 local n=1;while fs.exists(PATH..'.before-run-'..n) do n=n+1 end
 write(PATH..'.before-run-'..n,old)
end
local function needed()
 local v=call(NODE,'getRequiredTier');return type(v)=='table' and v.tier or v
end
-- V1 whole-cell selection rule: prefer the exact phase family when available.
local function requiredFamily()
 local v=call(NODE,'getRequiredTier');return type(v)=='table'and v.name or nil
end
local function hive()
 local n=call(NODE,'getAvailableNanites');assert(whole(n),'蜂群仓数量无效')
 local p=call(NODE,'getProvidedTier')
 if n==0 then return 0 end
 assert(type(p)=='table' and whole(p.tier) and type(p.name)=='string','蜂群仓类型不可读')
 return n,p
end
local function guard()
 if cfg.inspect then
  local v=cfg.inspect()
  assert(v.requiredTier==record.requiredTier,'换蜂过程中配方等级变化，保留现场')
  assert(not record.requiredFamily or v.requiredFamily==record.requiredFamily,'换蜂过程中蜂群类型需求变化，保留现场')
 else
 cfg.checkGroup()
 assert(call(PAUSE,'getOutput',cfg.pauseSide)==15,'换蜂必须保持传送节点暂停红石15')
 local s=call(NODE,'getState')
 assert(s=='paused-immediate' or s=='nanite-tier-too-low' or
  s=='idle' and call(NODE,'isWorkAllowed')==false,'节点状态不适合换蜂：'..tostring(s))
 assert(needed()==record.requiredTier,'换蜂过程中配方等级变化，保留现场')
 assert(not record.requiredFamily or requiredFamily()==record.requiredFamily,'换蜂过程中蜂群类型需求变化，保留现场')
 end
 if context and context.check then context.check() end
 if context and context.stopping and context.stopping() then error('换蜂已暂停，保留现场') end
end
local function tick()
 if context and context.tick then context.tick(0.1) else os.sleep(0.1) end
 -- runPort checks freshly at the start of its next iteration, after this yield.
end
local function output(a,n)
 call(a,'setOutput',0,n);assert(call(a,'getOutput',0)==n,'IO向下红石回读失败')
end
local function off()
 local a,e=pcall(output,SOUTH,0);local b,f=pcall(output,NORTH,0)
 assert(a and b,'关闭IO红石失败，手动关闭两端：'..tostring(e)..'; '..tostring(f))
end
local function stack(side,slot) return call(T,'getStackInSlot',side,slot) end
local function describe(item)
 assert(type(item)=='table' and item.name==CELL and item.size==1,'蜂群硬盘必须是单个数字奇点')
 assert(whole(item.storedItemCount) and type(item.getAvailableItems)=='table','盘内数量不可读')
 local row
 for _,v in pairs(item.getAvailableItems) do
  assert(not row and type(v.name)=='string' and whole(v.size) and v.size>0 and not v.hasTag,'盘内不能混料或放带NBT蜂群')
  local material
  for _,ore in pairs(v.oreNames or {}) do
   local candidate=type(ore)=='string' and ore:match('^nanite(.+)$')
   if candidate and tiers[candidate] then
    assert(not material or material==candidate,'蜂群矿辞类型不唯一');material=candidate
   end
  end
  -- This exact item was read from, loaded into, and recovered from the real rig.
  if not material and v.name=='gregtech:gt.metaitem.03' and v.damage==4581 then material='TranscendentMetal' end
  assert(material,'未知蜂群，请保留编号和oreNames：'..tostring(v.name)..':'..tostring(v.damage))
  local t=tiers[material]
  row={name=v.name,damage=v.damage or 0,count=v.size,tier=t[1],family=t[2],label=v.label or material}
  row.key=row.name..':'..row.damage
 end
 local n=row and row.count or 0
 assert(n==item.storedItemCount,'盘内数量与清单不一致')
 return n,row
end
local function discover()
 for a,kind in pairs({[T]='transposer',[SOUTH]='redstone',[NORTH]='redstone',[PAUSE]='redstone',[NODE]='bec_io_node'}) do
  assert(c.type(a)==kind,'组件缺失或类型错误：'..a)
 end
 for _,side in ipairs({2,3}) do
  assert(call(T,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort' and call(T,'getInventorySize',side)==12,'南北面应为12槽ME IO端口')
 end
 local size=call(T,'getInventorySize',0)
 assert(whole(size) and size>=1 and size<=1024,'底面硬盘盒不可读或过大')
 for _,a in ipairs({SOUTH,NORTH}) do for side=0,5 do
  assert(c.invoke(a,'getOutput',side)==0,'蜂群IO已有红石输出，不能叠加操作')
 end end
 return size
end
local function emptyPorts()
 for _,side in ipairs({2,3}) do for slot=1,12 do
  assert(stack(side,slot)==nil,'蜂群IO已有硬盘，保留未完成操作')
 end end
end
-- BEC_V2_STAGE_LATENCY_V2: only the first ten physical bank slots are managed.
local function bank(size)
 local cells={}
 for slot=1,math.min(size,10)do
  local item=stack(0,slot)
  if item then
   local n,row=describe(item)
   cells[#cells+1]={slot=slot,count=n,item=row,
    empty=n==0 and item.canHoldNewItem==true and (item.remainingItemCount or 0)>0}
  end
 end
 return cells
end

local function pack(cells,key)
 local candidates={}
 for _,disk in ipairs(cells) do
  if disk.item and disk.item.key==key then candidates[#candidates+1]=disk end
 end
 table.sort(candidates,function(a,b) return a.count>b.count or a.count==b.count and a.slot<b.slot end)
 local picked,n={},0
 for _,disk in ipairs(candidates) do picked[#picked+1]=disk;n=n+disk.count end
 return picked,n
end
local function choose(cells,need,family)
 local seen,best={},nil
 for _,disk in ipairs(cells) do if disk.item and not seen[disk.item.key] then
  local item=disk.item;seen[item.key]=true
  local picked,n=pack(cells,item.key)
  local exact=item.tier==need and item.family==family
  if item.tier>=need and n>=MIN and (not best or exact and not best.exact
   or exact==best.exact and (item.tier<best.item.tier or item.tier==best.item.tier and n>best.count)) then
   best={item=item,count=n,picked=picked,exact=exact}
  end
 end end
 return best
end
local function move(from,to,source,dest,expected,key)
 guard()
 local n,row=describe(stack(from,source))
 assert(n==expected and (not key or row and row.key==key) and stack(to,dest)==nil,'搬盘前槽位/内容变化')
 record.pending={from=from,to=to,source=source,dest=dest,count=expected,key=key}
 save('moving-cell')
 if not firstMoveStarted then
  print(string.format('开始首次搬盘 / 检查准备 %.2f 秒',clock.uptime()-(prepStarted or clock.uptime())))
  firstMoveStarted=true
 end
 assert(call(T,'transferItem',from,to,1,source,dest)==1,'搬盘返回值未确认，不重试')
 local actual,result=describe(stack(to,dest))
 assert(stack(from,source)==nil and actual==expected and (not key or result and result.key==key),'搬盘后槽位/内容不符，不重试')
 record.pending=nil;save('cell-moved')
end
local function runPort(side,rs,endDisk,endHive,kind,key)
 save('waiting-port');output(rs,15)
 local deadline=clock.uptime()+30
 while true do
  guard()
  local at,n,row
  -- Read stationary output first; input/output readings can straddle an AE tick.
  -- Both ports are fully checked empty before starting, then only one cell
  -- is inserted into input 1. Output 7 is that operation's first free output.
  local item=stack(side,7)
  if item then at=7;n,row=describe(item)end
  if not at then local item=stack(side,1);if item then n,row=describe(item) end end
  local h,p=hive()
  if record.operationTotal then
   assert(not n or n<=record.operationTotal,'盘内数量超出本次目标')
   assert(h<=math.min(record.operationTotal,DISPLAY_CAP),'仓内读数超出本次目标')
  end
  if row then assert(row.family==kind.family and row.tier==kind.tier and (not key or row.key==key),'IO盘内蜂群类型变化') end
  if at then
   output(rs,0)
   local diskOK=endDisk==nil and row and math.min(n,DISPLAY_CAP)==record.beforeReading or n==endDisk
   if diskOK and h==math.min(endHive,DISPLAY_CAP) and (not cfg.sharedHiveReady or cfg.sharedHiveReady()) then
    if h>0 then assert(p.tier==kind.tier and p.name==kind.family,'节点蜂群类型不符') end
    save('port-complete');return at,row
   end
  end
  assert(clock.uptime()<deadline,'IO转移未完成：盘内'..tostring(n)..'，仓内'..h..'；保留现场，不重试')
  tick()
 end
end
local function recover(cells)
 local h,p=hive();assert(h>0,'回收前蜂群已变化')
 local chosen
 for _,disk in ipairs(cells) do if disk.empty then
  if not chosen or record.holding and disk.slot==record.holding.home then chosen=disk end
 end end
 assert(chosen,'缺少可接收新类型的空数字奇点盘，旧蜂群未搬运')
 record.operationTotal=record.holding and record.holding.count or nil
 record.beforeReading=h;save('recovering')
 local known=record.holding and record.holding.key
 move(0,2,chosen.slot,1,0)
 local at,row=runPort(2,NORTH,record.operationTotal,0,{family=p.name,tier=p.tier},known)
 assert(row,'回收盘没有蜂群清单')
 move(2,0,at,chosen.slot,row.count,row.key)
 record.holding=nil;save('recovered')
 print('整盘回收：T'..row.tier..' / '..row.count..' 个，盘槽 '..chosen.slot)
end
local function loadCell(disk)
 local base,p=hive();local item=disk.item
 assert(item and item.count>0,'装入盘没有蜂群')
 if base>0 then assert(record.holding and record.holding.key==item.key and p.name==item.family and p.tier==item.tier,'追加蜂群身份未确认') end
 local actualBase=record.holding and record.holding.count or 0
 assert(base==math.min(actualBase,DISPLAY_CAP),'追加前节点数量变化')
 record.operationTotal=actualBase+item.count;save('loading')
 move(0,3,disk.slot,1,item.count,item.key)
 local at=runPort(3,SOUTH,0,record.operationTotal,item,item.key)
 move(3,0,at,disk.slot,0)
 record.holding={key=item.key,name=item.name,damage=item.damage,tier=item.tier,family=item.family,count=record.operationTotal,home=disk.slot}
 save('loaded')
 print('整盘装入：T'..item.tier..' / 仓内'..record.operationTotal..' 个，空盘槽 '..disk.slot)
end
local M={}
function M.preview()
 local size=discover();local h,p=hive();local cells=bank(size)
 print('蜂群IO：装入侧'..cfg.loadSide..'，回收侧'..cfg.returnSide..'，硬盘盒侧'..cfg.bankSide..' / '..size..'槽（仅管理前10格）；IO输入1/输出7，整盘搬运')
 print('仓内：'..h..' 个 / T'..tostring(p and p.tier)..'；需求T'..tostring(needed()))
 for _,disk in ipairs(cells) do if disk.item then
  print('盘槽 '..disk.slot..'：T'..disk.item.tier..' / '..disk.count..' 个 / '..disk.item.label)
 end end
 local r=oldRecord();print('蜂群IO日志：'..tostring(r and r.stage or '无')..'；旧接口日志不重放')
 emptyPorts()
end
function M.ensure(ctx)
 prepStarted=clock.uptime();firstMoveStarted=false
 local initial=cfg.inspect and cfg.inspect()
 local need=initial and initial.requiredTier or needed();if not whole(need) or need<1 then return false end
 if cfg.checkSharedHive then cfg.checkSharedHive()end
 context=ctx;local size=discover()
 local old=oldRecord();assert(not old or old.stage=='done','旧蜂群IO未完成，保留盘和日志，不自动重放')
 emptyPorts()
 local family;if initial then family=initial.requiredFamily else family=requiredFamily()end
 local cells=bank(size);local h,p=hive();local best=choose(cells,need,family)
 local known=old and sameBinding(old.binding)and old.holding
 -- A saturated node reading cannot prove the current raw quantity. Recover to
 -- read the actual quantity before another operation, even with an old record.
 if not (known and known.count==h and h<DISPLAY_CAP and p and known.family==p.name and known.tier==p.tier) then known=nil end
 local sameFamily=0
 if p then for _,disk in ipairs(cells) do if disk.item and disk.item.family==p.name then sameFamily=sameFamily+disk.count end end end
 local keeping=h>0 and p.tier>=need and h+sameFamily>=MIN
  and (not best or best.item.tier>=p.tier and not(best.exact and p.name~=family))
 local extra={}
 if keeping then
  if known then extra=pack(cells,known.key)
  else for _,disk in ipairs(cells) do if disk.item and disk.item.family==p.name then extra={disk};break end end end
  if #extra==0 then return false end
 else assert(best,'硬盘盒缺少满足T'..need..'的至少64个蜂群') end
 if h>0 and (not keeping or not known) then
  local hasEmpty=false;for _,disk in ipairs(cells) do if disk.empty then hasEmpty=true;break end end
  assert(hasEmpty,'缺少可接收新类型的空数字奇点盘，旧蜂群未搬运')
 end
 record={version=2,kind='cell-io',binding=binding,requiredTier=need,requiredFamily=family,holding=known,stage='prepared'}
 guard();archive();save('prepared')
 local ok,result=xpcall(function()
  if h>0 and (not keeping or not known) then recover(cells);cells=bank(size);best=choose(cells,need,family);assert(best,'回收后没有可装入蜂群') end
  local picked
  if keeping and known then picked=extra else picked=best.picked end
  for _,disk in ipairs(picked) do loadCell(disk) end
  emptyPorts();guard()
  local n,t=hive();assert(n>=MIN and t.tier>=need,'换蜂后数量或等级不足')
  assert(record.holding and math.min(record.holding.count,DISPLAY_CAP)==n and record.holding.family==t.name,'换蜂后身份核对失败')
  save('done');print('蜂群IO完成：T'..t.tier..' / '..n..' 个；节点仍暂停')
  return true
 end,debug.traceback)
 local cut,cutError=pcall(off)
 assert(cut,tostring(cutError));assert(ok,tostring(result)..'\n保留现场，不重试。')
 return result
end
return M
]=],supported={['14773:160252700']=true,['14773:160252700']=true,['14773:160252700']=true,['14773:160252700']=true,['14773:160252700']=true,['14773:160252700']=true,['14773:160252700']=true,['14773:160252700']=true}}}

local fs=require('filesystem');local root='/home/bec_v2/'
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function normal(s)return s and s:gsub('\r\n','\n')end
local function signature(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local old,identical,bytes={},true,0
for i,row in ipairs(rows)do
 local target=root..row.name;old[i]=assert(read(target),'缺少V2程序: '..target)
 local text=normal(old[i]);assert(text==row.source or row.supported[signature(text)],'未知本地程序，保留未覆盖: '..target)
 if text~=row.source then identical=false end
 if row.name:sub(-4)=='.lua'then assert(load(row.source,'@'..target,'t',_ENV),'新程序语法无效')end
 bytes=bytes+#row.source
end
if identical then print('配方阶段换蜂修复已安装，无需重复更新。');return end
local disk=assert(fs.get(root));assert(disk.spaceTotal()-disk.spaceUsed()>=bytes+524288,'磁盘空间不足：更新后需保留512KiB')
local n=1
while true do
 local conflict=false;for _,row in ipairs(rows)do for _,suffix in ipairs({'.before-dynamic-','.dynamic-new-','.dynamic-failed-'})do if fs.exists(root..row.name..suffix..n)then conflict=true end end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(rows)do
 local temp=root..row.name..'.dynamic-new-'..n;local f=assert(io.open(temp,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(temp)==row.source,'临时文件回读失败，旧程序未改')
end
for i,row in ipairs(rows)do assert(read(root..row.name)==old[i],'更新期间程序改变，未替换')end
local backed,installed={},{}
local ok,reason=pcall(function()
 for i,row in ipairs(rows)do local target=root..row.name
  assert(fs.rename(target,target..'.before-dynamic-'..n),'备份失败');backed[i]=true
  assert(fs.rename(target..'.dynamic-new-'..n,target),'替换失败');installed[i]=true
  assert(read(target)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#rows,1,-1 do local target=root..rows[i].name
  if installed[i]then assert(fs.rename(target,target..'.dynamic-failed-'..n),'移出失败程序失败，保留备份')end
  if backed[i]then assert(fs.rename(target..'.before-dynamic-'..n,target),'恢复失败，保留备份')end
 end
 error('更新失败，旧程序已恢复：'..tostring(reason))
end
print('配方阶段换蜂修复完成：按当前阶段需求换蜂，不再把等级变化当作换配方。')
print('已有地址、草稿、配置、配方和运行记录保留；未控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
