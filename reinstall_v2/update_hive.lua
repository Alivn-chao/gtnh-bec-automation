-- BEC_V2_HIVE_UPDATE_1
local SELF_SIGNATURE='36988:1041343521'
print('BEC hive inspection update; Q to exit the old UI first')
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
]=],supported={['16213:3509786521']=true,['16213:3509786521']=true,['16388:3843904074']=true,['16388:3843904074']=true}},{name='runtime/nanites_cell.lua',source=[=[-- V2 module: whole-cell transfers through the verified south/north ME IO ports.
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
]=],supported={['15338:3488554873']=true,['15338:3488554873']=true,['15338:3488554873']=true,['15338:3488554873']=true}}}

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
local self='/home/bec_hive_update.lua'
do
 local downloaded=read(self)
 local payload=downloaded and downloaded:match('^%-%- BEC_V2_HIVE_UPDATE_1\nlocal SELF_SIGNATURE=[^\n]*\n(.*)$')
 if payload and signature(payload)==SELF_SIGNATURE then
  pcall(fs.remove,self)
 end
 downloaded=nil;payload=nil;if type(collectgarbage)=='function'then pcall(collectgarbage,'collect')end
end
if identical then print('蜂群检查优化已安装，无需重复更新。');return end
local disk=assert(fs.get(root));assert(disk.spaceTotal()-disk.spaceUsed()>=bytes+524288,'磁盘空间不足：更新后需保留512KiB')
local n=1
while true do
 local conflict=false;for _,row in ipairs(rows)do for _,suffix in ipairs({'.before-hive-','.hive-new-','.hive-failed-'})do if fs.exists(root..row.name..suffix..n)then conflict=true end end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(rows)do
 local temp=root..row.name..'.hive-new-'..n;local f=assert(io.open(temp,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(temp)==row.source,'临时文件回读失败，旧程序未改')
end
for i,row in ipairs(rows)do assert(read(root..row.name)==old[i],'更新期间程序改变，未替换')end
local backed,installed={},{}
local ok,reason=pcall(function()
 for i,row in ipairs(rows)do local target=root..row.name
  if old[i]then assert(fs.rename(target,target..'.before-hive-'..n),'备份失败');backed[i]=true end
  assert(fs.rename(target..'.hive-new-'..n,target),'替换失败');installed[i]=true
  assert(read(target)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#rows,1,-1 do local target=root..rows[i].name
  if installed[i]then assert(fs.rename(target,target..'.hive-failed-'..n),'移出失败程序失败，保留备份')end
  if backed[i]then assert(fs.rename(target..'.before-hive-'..n,target),'恢复失败，保留备份')end
 end
 error('更新失败，旧程序已恢复：'..tostring(reason))
end
print('蜂群检查优化已安装：每轮合并整组读取，保留搬盘前后核对。')
print('已有地址、草稿、配置、配方和运行记录保留；未控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
