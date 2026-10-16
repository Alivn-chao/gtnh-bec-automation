-- BEC V2 clean-install bundle; no V1 dependency.
local FILES={
{"lib/bridge.lua",[=[local c=require('component')
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
 local n,g=cfg.nodes[index],cfg.groups[cfg.nodes[index].group]
 local task=engine.tasks[index]
 local members=task.members or {index}
 local entries=task.entries or {}
 local function nodeSnapshot()
  local snapshot={required={},consumed={},parallel=0,requiredTier=0,allIdle=true,allPaused=true}
  for _,i in ipairs(members) do
   local address=cfg.nodes[i].address
   local state=c.invoke(address,'getState')
   local current=c.invoke(address,'getRequiredCondensate')
   local entry=entries[i]
   assert(entry,'生产组缺少节点快照')
   local p=type(current)=='table'and next(current)and c.invoke(address,'getParallelRecipesInProgress')or nil
   local consumed=c.invoke(address,'getConsumedCondensate')or {}
   local needed=c.invoke(address,'getRequiredTier');needed=type(needed)=='table'and needed.tier or needed
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
    assert(type(needed)=='number'and needed==entry.tier,'组内配方蜂群等级变化，保持整组暂停')
    assert(state~='unpowered' and state~='assembler-offline','组内节点不可用: '..cfg.nodes[i].name..' / '..state)
    if type(needed)=='number' then snapshot.requiredTier=math.max(snapshot.requiredTier,needed) end
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
   if m=='getRequiredTier' then local value=nodeSnapshot().requiredTier;return value>0 and {tier=value} or nil end
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
]=]},
{"lib/config.lua",[=[local c=require('component')
local fs=require('filesystem')
local ser=require('serialization')
local M={ROOT='/home/bec_v2'}
function M.path(name) return M.ROOT..'/'..name end
function M.read(path)
 local f=io.open(path,'r');if not f then return nil end
 local text=f:read('*a');f:close()
 local value=ser.unserialize(text);assert(type(value)=='table','配置/记录损坏: '..path)
 return value
end
function M.write(path,value)
 local text=ser.serialize(value,false)
 local dir=fs.path(path);assert(fs.exists(dir) or fs.makeDirectory(dir),'无法建立目录')
 local old=io.open(path,'r')
 if old then
  local previous=old:read('*a');old:close();local backup=assert(io.open(path..'.previous','w'))
  assert(backup:write(previous));assert(backup:flush());backup:close()
 end
 local file=assert(io.open(path,'w'));assert(file:write(text));assert(file:flush());file:close()
 file=assert(io.open(path,'r'));local actual=file:read('*a');file:close();assert(actual==text,'配置回读失败')
end
local function integer(n,lo,hi) return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi end
local function address(a,label) assert(type(a)=='string' and #a>0,label..' 未绑定') end
local function methods(a,list,label)
 address(a,label);local m=c.methods(a)
 assert(type(m)=='table',label..' 不在线')
 for _,name in ipairs(list) do assert(m[name]~=nil,label..' 缺少方法 '..name) end
end
function M.validate(cfg,live)
 assert(type(cfg)=='table' and cfg.version==2,'需要 V2 配置')
 assert(type(cfg.nodes)=='table' and integer(#cfg.nodes,1,16),'节点数量必须为1到16')
 assert(type(cfg.groups)=='table' and integer(#cfg.groups,1,16),'设备组数量必须为1到16')
 address(cfg.mainInterface,'主网接口')
 assert(type(cfg.recipeDirectory)=='string' and cfg.recipeDirectory~='','配方目录未设置')
 local used,redstones,gates,resources={},{},{},{[cfg.mainInterface]=true}
 for i,g in ipairs(cfg.groups) do
  for _,name in ipairs({'storage','subInterface','transposer'}) do address(g[name],'设备组'..i..' '..name) end
  assert(type(g.generators)=='table' and #g.generators>=1,'设备组至少绑定一台纠缠器')
  for _,name in ipairs({'storage','subInterface','transposer'}) do
   assert(not resources[g[name]],'设备组共享 '..name..'，请合并到同一组');resources[g[name]]=true
  end
  assert(integer(g.mainSide,0,5) and integer(g.subSide,0,5) and g.mainSide~=g.subSide,'供液方向无效')
  for _,a in ipairs(g.generators) do address(a,'纠缠器');assert(not resources[a],'纠缠器重复绑定');resources[a]=true end
  for _,a in ipairs(g.bulkTransposers or {}) do address(a,'高速供液转运器');assert(not resources[a],'高速供液转运器重复绑定');resources[a]=true end
  if g.nanites and g.nanites.enabled then
   local n=g.nanites
   local mode=n.mode or 'me-interface'
   assert(mode=='cell-io'or mode=='me-interface','未知蜂群模式')
   local names
   if mode=='cell-io'then
    names={'transposer','loadRedstone','returnRedstone'}
    for _,key in ipairs({'bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide'})do assert(integer(n[key],0,5),'蜂群IO方向无效: '..key)end
    assert(n.bankSide~=n.loadSide and n.bankSide~=n.returnSide and n.loadSide~=n.returnSide,'硬盘盒和两端IO必须不同方向')
   else
    names={'transposer','supplyInterface','hatchInterface'}
    assert(n.supplyInterface~=n.hatchInterface,'蜂群供货网和收容网接口不能相同')
    assert(integer(n.supplySide,0,5) and integer(n.hatchSide,0,5) and n.supplySide~=n.hatchSide,'蜂群方向无效')
   end
   for _,name in ipairs(names)do address(n[name],'蜂群 '..name);assert(not resources[n[name]],'蜂群控制设备跨组重复');resources[n[name]]=true end
  end
  if live then
   methods(g.storage,{'getStoredCondensate','isWorkAllowed'},'约束场')
   assert(c.invoke(g.storage,'isWorkAllowed')==true,'约束场须保持开启')
   methods(g.subInterface,{'getFluidsInNetwork'},'原液子网接口')
   methods(g.transposer,{'transferFluid','getFluidInTank'},'供液转运器')
   for _,a in ipairs(g.bulkTransposers or {})do methods(a,{'transferFluid','getFluidInTank'},'高速供液转运器')end
   for _,a in ipairs(g.generators) do
    methods(a,{'setWorkAllowed','isWorkAllowed','isMachineActive'},'纠缠器')
    assert(c.invoke(a,'getName')=='multi.bec.generator','绑定的设备不是纠缠器')
   end
   if g.nanites and g.nanites.enabled then
    local n=g.nanites
    if n.mode=='cell-io'then
     methods(n.transposer,{'transferItem','getInventoryName','getInventorySize','getStackInSlot'},'蜂群硬盘转运器')
     for _,side in ipairs({n.loadSide,n.returnSide})do
      assert(c.invoke(n.transposer,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort'and c.invoke(n.transposer,'getInventorySize',side)==12,'蜂群两端必须是12槽ME IO端口')
     end
     local size=c.invoke(n.transposer,'getInventorySize',n.bankSide);assert(integer(size,1,1024),'蜂群硬盘盒不可读')
     for _,a in ipairs({n.loadRedstone,n.returnRedstone})do methods(a,{'setOutput','getOutput'},'蜂群IO红石')end
    else
     methods(n.transposer,{'transferItem','getInventoryName'},'蜂群转运器')
     for _,a in ipairs({n.supplyInterface,n.hatchInterface})do methods(a,{'getItemsInNetwork','setInterfaceConfiguration','getInterfaceConfiguration'},'蜂群接口')end
    end
   end
  end
 end
 for group in ipairs(cfg.groups)do
  local count=0;for _,n in ipairs(cfg.nodes)do if n.group==group then count=count+1 end end
  assert(count>0,'设备组'..group..'没有分配节点')
 end
 for i,n in ipairs(cfg.nodes) do
  assert(integer(n.group,1,#cfg.groups),'节点'..i..'设备组无效')
  for _,name in ipairs({'address','redstone','gate'}) do address(n[name],'节点'..i..' '..name) end
  assert(not resources[n.address]and not resources[n.redstone],'节点/暂停红石与公共设备重复')
  assert(not used[n.address],'节点重复绑定');used[n.address]=true
  assert(integer(n.pauseSide,0,5),'红石输出方向无效')
  local key=n.redstone..':'..n.pauseSide;assert(not redstones[key],'红石输出线路重复');redstones[key]=true
  assert(not gates[n.gate] or gates[n.gate]==n.group,'不同生产组不能共享韦门');gates[n.gate]=n.group
  if live then
   methods(n.address,{'getState','getRequiredTier','getRequiredCondensate','getParallelRecipesInProgress','setWorkAllowed','isWorkAllowed'},'传送节点（需要可启停的机器组件）')
   if cfg.groups[n.group].nanites and cfg.groups[n.group].nanites.enabled and cfg.groups[n.group].nanites.mode=='cell-io'then methods(n.address,{'getAvailableNanites','getProvidedTier'},'蜂群读数节点')end
   methods(n.redstone,{'setOutput','getOutput'},'暂停红石')
   methods(n.gate,{'setCondensateFilters','getCondensateFilters','getCondensateFilterCount'},'韦门')
  end
 end
 if live then methods(cfg.mainInterface,{'getFluidsInNetwork','getCraftables','getCpus','setFluidInterfaceConfiguration'},'主网供液接口') end
 return true
end
function M.load() return assert(M.read(M.path('config.dat')),'请先运行 setup') end
return M
]=]},
{"lib/engine.lua",[=[local c=require('component')
local clock=require('computer')
return function(cfg,C,Bridge,monitor)
 local E={tasks={},groupOwner={},fluidOwner=nil,logs={},monitor=monitor,roundRobin={}}
 local phases={starting='detect',waiting='detect',nanites='nanites',gate='gate',converting='convert',watching='produce',producing='produce',stopped='finish',fault='fault'}
 function E.phase(i,stage)
  local t=E.tasks[i];local phase=phases[stage]or(stage:find('craft',1,true)and 'supply')or(stage:find('stream',1,true)and 'supply')or(stage:find('transfer',1,true)and 'supply')
  if not phase then return end
  local now=clock.uptime();t.flow=t.flow or {};t.timeline=t.timeline or {}
  if t.phase==phase then return end
  if t.phase then t.flow[t.phase]=(t.flow[t.phase]or 0)+now-(t.phaseAt or now)end
  t.phase=phase;t.phaseAt=now
  t.timeline[#t.timeline+1]={phase=phase,at=now}
  if #t.timeline>12 then table.remove(t.timeline,1)end
 end
 -- BEC_V2_GITHUB_REPORTS_V1
 local reports
 if not monitor then
  local ok,result=pcall(function()return assert(loadfile(C.path("lib/reports.lua")))()(cfg,C)end)
  reports=ok and result or {status="报告初始化失败，生产日志保留",step=function()end,close=function()end,capture=function()end}
 end
 E.reports=reports
 local storage,nextDiskCheck
 if not monitor and require('filesystem').get then storage=assert(loadfile(C.path('lib/storage.lua')))()(C);nextDiskCheck=0 end
 function E.reportFault(i,reason)
  if reports then local ok=pcall(reports.capture,i,E,reason);if not ok then reports.status="故障报告保存失败，现场日志保留" end end
 end
 for i in ipairs(cfg.nodes)do E.tasks[i]={status='等待订单',disabled=false}end
 function E.log(i,message)
  E.logs[#E.logs+1]='['..cfg.nodes[i].name..'] '..message
  if #E.logs>40 then table.remove(E.logs,1)end
  if message:find('程序停止:',1,true)and not E.tasks[i].cancel then E.tasks[i].fault=true end
 end
 function E.acquire(i)
  while E.fluidOwner and E.fluidOwner~=i do
   E.tasks[i].status='等待共享供液';coroutine.yield('lock')
   assert(not E.tasks[i].cancel,'用户暂停生产组')
  end
  E.fluidOwner=i
 end
 function E.release(i)if E.fluidOwner==i then E.fluidOwner=nil end end
 local function pause(i)
  local n=cfg.nodes[i];c.invoke(n.redstone,'setOutput',n.pauseSide,15)
  assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'节点暂停回读失败')
 end
 -- BEC_V2_BATCH_STOP_V1: workAllowed gates NEXT recipe acquisition;
 -- the active batch still runs when its immediate-pause signal is released.
 function E.nodeWork(i,enabled)
  local n=cfg.nodes[i];local methods=c.methods(n.address)
  assert(methods and methods.setWorkAllowed~=nil and methods.isWorkAllowed~=nil,'传送节点缺少启停接口: '..n.name)
  if c.invoke(n.address,'isWorkAllowed')==enabled then return end
  local path=C.path('state/node-'..i..'/batch-stop.dat')
  local intent={version=2,node=n.address,enabled=enabled,stage='pending'}
  C.write(path,intent)
  c.invoke(n.address,'setWorkAllowed',enabled)
  assert(c.invoke(n.address,'isWorkAllowed')==enabled,'传送节点启停回读不符: '..n.name)
  intent.stage='confirmed';C.write(path,intent)
 end
 function E.pauseNode(i)
  assert(not monitor,'只读监控不能修改机器')
  local group=cfg.nodes[i].group
  local errors={}
  for j,n in ipairs(cfg.nodes)do if n.group==group then
   local t=E.tasks[j];t.disabled=true;t.cancel=true
   local ok,reason=pcall(pause,j);if not ok then errors[#errors+1]=tostring(reason)end
   ok,reason=pcall(E.nodeWork,j,false);if not ok then errors[#errors+1]=tostring(reason)end
   if not t.co then t.status='整组暂停'end
  end end
  assert(#errors==0,table.concat(errors,' / '))
 end
 function E.resumeNode(i)
  assert(not monitor,'只读监控不能修改机器')
  local group=cfg.nodes[i].group;assert(not E.groupOwner[group],'等待工作器暂停结束')
  for j,n in ipairs(cfg.nodes)do if n.group==group then
   local t=E.tasks[j];t.disabled=false;t.cancel=false;t.fault=false;t.reviewed=true;t.status='等待订单'
  end end
 end
 function E.pauseAll()
  local seen,errors={},{}
  for i,n in ipairs(cfg.nodes)do if not seen[n.group]then
   seen[n.group]=true;local ok,reason=pcall(E.pauseNode,i);if not ok then errors[#errors+1]=tostring(reason)end
  end end
  assert(#errors==0,table.concat(errors,' / '))
 end
 function E.shutdown()
  if monitor then return {}end
  if reports then reports.close()end
  local errors={}
  for i,t in ipairs(E.tasks)do
   t.cancel=true;t.disabled=true
   local ok,e=pcall(pause,i);if not ok then errors[#errors+1]=tostring(e)end
   ok,e=pcall(E.nodeWork,i,false);if not ok then errors[#errors+1]=tostring(e)end
  end
  for _,g in ipairs(cfg.groups)do for _,a in ipairs(g.generators)do
   local ok,e=pcall(function()c.invoke(a,'setWorkAllowed',false);assert(c.invoke(a,'isWorkAllowed')==false)end)
   if not ok then errors[#errors+1]=a..': '..tostring(e)end
  end end
  for _,g in ipairs(cfg.groups)do if g.nanites and g.nanites.enabled and g.nanites.mode=='cell-io'then
   for _,pair in ipairs({{g.nanites.loadRedstone,g.nanites.loadOutputSide},{g.nanites.returnRedstone,g.nanites.returnOutputSide}})do
    local ok,e=pcall(function()c.invoke(pair[1],'setOutput',pair[2],0);assert(c.invoke(pair[1],'getOutput',pair[2])==0,'蜂群IO停止回读失败')end)
    if not ok then errors[#errors+1]=pair[1]..': '..tostring(e)end
   end
  end end
  return errors
 end
 local function cohortPath(group)return C.path('state/group-'..group..'/cohort.dat')end
 local function advance(i)
  local t=E.tasks[i];local ok,kind,time=coroutine.resume(t.co)
  if not ok then t.fault=true;E.log(i,tostring(kind))end
  if ok and coroutine.status(t.co)~='dead' then t.waitKind=kind;t.deadline=time or clock.uptime();return end
  local group=cfg.nodes[i].group
  t.endedAt=clock.uptime();E.phase(i,(t.fault or t.cancel)and 'fault'or 'stopped')
  if t.fault or t.cancel then
   for _,a in ipairs(cfg.groups[group].generators)do pcall(c.invoke,a,'setWorkAllowed',false)end
   for j,n in ipairs(cfg.nodes)do if n.group==group then
    E.tasks[j].disabled=true;E.tasks[j].status=t.fault and '同组故障，需核对' or '整组暂停';pcall(pause,j);pcall(E.nodeWork,j,false)
   end end
  else for _,j in ipairs(t.members)do E.tasks[j].status='等待订单'end end
  C.write(cohortPath(group),{version=2,stage=(t.fault or t.cancel)and 'interrupted'or 'stopped',
   leader=i,members=t.members,entries=t.entries,normalized=t.normalized})
  if reports then
   reports.historyWanted=true
   if t.fault and not t.cancel then E.reportFault(i,E.logs[#E.logs]or "worker failure")end
  end
  E.release(i);E.groupOwner[group]=nil;E.roundRobin[group]=i;t.co=nil
 end
 local function pending(i)
  local n=cfg.nodes[i];local state=c.invoke(n.address,'getState')
  if state~='paused-immediate' and state~='nanite-tier-too-low'then return end
  local req=c.invoke(n.address,'getRequiredCondensate')
  if type(req)~='table'or not next(req)then return end
  local p=c.invoke(n.address,'getParallelRecipesInProgress')
  assert(type(p)=='number'and p>=1,'节点并行不可读')
  local normalized={};for key,value in pairs(req)do normalized[key]=value/p end
  local tier=c.invoke(n.address,'getRequiredTier');tier=type(tier)=='table'and tier.tier or tier
  assert(type(tier)=='number','节点蜂群需求不可读')
  return {required=req,parallel=p,tier=tier,consumed=c.invoke(n.address,'getConsumedCondensate')or {}},normalized
 end
 local function same(a,b)
  for key,value in pairs(a)do if b[key]~=value then return false end end
  for key,value in pairs(b)do if a[key]~=value then return false end end;return true
 end
 function E.step()
  if monitor then return end
  if storage and clock.uptime()>=(nextDiskCheck or 0)then
   storage.prune(cfg);E.disk=storage.status();nextDiskCheck=clock.uptime()+10
   if not E.disk.known or not E.disk.ok then
    E.diskLow=true;E.pauseAll();E.log(1,'磁盘空间不足或不可读：停止接单，保留当前日志，需腾出至少512KiB')
   else E.diskLow=false end
  end
  if reports then
   reports.step()
   if E.reportStatus~=reports.status then E.reportStatus=reports.status;E.log(1,reports.status)end
  end
  for i,t in ipairs(E.tasks)do if t.co and (t.cancel or t.waitKind=='lock'and(not E.fluidOwner or E.fluidOwner==i)or t.waitKind~='lock'and clock.uptime()>=(t.deadline or 0))then advance(i)end end
  for group in ipairs(cfg.groups)do if not E.groupOwner[group]then
   local saved=C.read(cohortPath(group));local unfinished=saved and saved.stage~='stopped'
   -- Reopen only after the previous cohort has finished its cleanup. Never
   -- reopen on restart with an interrupted cohort awaiting manual review.
   if not unfinished then
    for j,n in ipairs(cfg.nodes)do if n.group==group and not E.tasks[j].disabled and not E.tasks[j].fault then
     pause(j)
     local journal=C.read(C.path('state/node-'..j..'/production.journal'))
     local reviewed=not journal or journal.stage=='stopped' or E.tasks[j].reviewed
     E.nodeWork(j,reviewed and c.invoke(n.address,'getState')=='idle')
    end end
   end
   local first=unfinished and saved.leader or (E.roundRobin[group]or 0)%#cfg.nodes+1
   for offset=0,#cfg.nodes-1 do
    local i=(first+offset-1)%#cfg.nodes+1;local t,n=E.tasks[i],cfg.nodes[i]
    if n.group==group and not t.disabled and not t.fault then
     local entry,normalized=pending(i)
     if entry or unfinished and i==saved.leader then
      local journal=C.read(C.path('state/node-'..i..'/production.journal'))
      if (unfinished or journal and journal.stage~='stopped')and not t.reviewed then
       E.log(i,'保留旧进度；核对后按R恢复');E.pauseNode(i);t.status='旧进度待核对';break
      end
      t.members={};t.entries={};t.normalized=normalized;t.released=false
      if unfinished then
       assert(i==saved.leader and type(saved.members)=='table'and type(saved.entries)=='table','旧生产组记录不可恢复')
       t.members=saved.members;t.entries=saved.entries;t.normalized=saved.normalized
       for _,j in ipairs(t.members)do assert(cfg.nodes[j]and cfg.nodes[j].group==group,'配置改变了旧生产组，禁止恢复')end
      else
       for j,v in ipairs(cfg.nodes)do if v.group==group and not E.tasks[j].disabled then
        local row,norm=pending(j)
        if row and row.tier==entry.tier and same(normalized,norm)then t.members[#t.members+1]=j;t.entries[j]=row end
       end end
      end
      t.status='整组备料 / '..#t.members..'台';t.cancel=false;t.reviewed=false;t.fault=false
      t.startedAt=clock.uptime();t.endedAt=nil;t.phase=nil;t.flow={};t.timeline={};E.phase(i,'starting')
      for _,j in ipairs(t.members)do if j~=i then E.tasks[j].status='同配方物理并行'end end
      E.groupOwner[group]=i
      require('filesystem').makeDirectory(C.path('state/node-'..i))
      C.write(cohortPath(group),{version=2,stage='working',leader=i,members=t.members,entries=t.entries,normalized=t.normalized})
      t.co=coroutine.create(function()
       for j,v in ipairs(cfg.nodes)do if v.group==group then pause(j);E.nodeWork(j,false)end end
       E.acquire(i);Bridge.environment(cfg,i,E)(journal and 'resume'or 'run')
      end)
      advance(i);break
     end
    end
    if unfinished then break end
   end
  end end
 end
 return E
end
]=]},
{"lib/ochd_bindings.lua",[=[-- BEC_BULK_SLOTS_10
-- Strict data-only binding editor shared by the V1 monitor and V2 setup page.
local c=require('component');local fs=require('filesystem');local ser=require('serialization')
local M={}
local function uuid(s)return type(s)=='string'and s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')end
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function clone(t)return ser.unserialize(ser.serialize(t,false))end
local function field(out,key,label,value,kind)
 out[#out+1]={key=key,label=label,value=value==nil and ''or tostring(value),kind=kind or 'uuid'}
end
function M.revision(text)
 local a,b=1,0;for i=1,#(text or '')do a=(a+text:byte(i))%65521;b=(b+a)%65521 end
 return string.format('%.0f',b*65536+a)
end
function M.parse(payload,fields,revision,draft)
 assert(type(payload)=='string'and #payload<=32768,'绑定数据过大')
 if revision then
  local base,rest=payload:match('^_revision=(%d+)\n(.*)$')
  assert(base==revision and rest,'绑定配置已变化，请重新打开页面');payload=rest
 end
 local specs,values={},{}
 for _,f in ipairs(fields)do specs[f.key]=f.kind end
 for line in (payload..'\n'):gmatch('(.-)\n')do
  local key,v=line:match('^([%w_.-]+)=(.*)$')
  assert(key and specs[key]and values[key]==nil and #v<=160,'字段未知、重复或格式不正确')
  assert(not v:find('[\r\n=]'),'字段不能包含换行或等号')
  local kind=specs[key]
  if v~=''and not draft then
   if kind=='uuid'then assert(uuid(v),'请输入完整组件地址：'..key)
   elseif kind=='path'then assert(v:match('^/[%w_./-]+$')and not v:find('..',1,true),'目录格式不正确')
   elseif kind=='mode'then assert(v=='cell-io'or v=='me-interface','蜂群模式不正确')
   else
    assert(v:match('^%d+$')and tonumber(v)<=2147483647,'数值格式不正确：'..key)
    if kind=='side'then assert(tonumber(v)<=5,'方向必须为0至5')end
   end
  end
  values[key]=v
 end
 for _,f in ipairs(fields)do assert(values[f.key]~=nil,'缺少字段：'..f.key)end
 return values
end
function M.commit(path,value,expected,request)
 assert(read(path)==expected,'配置已被其他程序修改，请重新打开绑定页')
 local suffix=tostring(request);assert(suffix:match('^%d+$'),'保存请求编号无效')
 local temp=path..'.hd.new.'..suffix;local backup=path..'.hd.bak.'..suffix
 assert(not fs.exists(temp)and not fs.exists(backup),'同一保存请求已有文件，请先核对')
 local text=ser.serialize(value,false)
 local f=assert(io.open(temp,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(temp)==text and type(ser.unserialize(text))=='table','临时配置回读失败')
 assert(read(path)==expected,'配置在保存期间改变')
 if expected then assert(fs.rename(path,backup),'原配置备份失败')end
 local ok,reason=pcall(function()assert(fs.rename(temp,path),'配置替换失败');assert(read(path)==text,'保存回读失败')end)
 if not ok then
  if fs.exists(path)then assert(fs.rename(path,path..'.hd.failed.'..suffix))end
  if expected then assert(fs.rename(backup,path),'配置恢复失败')end
  error('保存失败，原配置已恢复：'..tostring(reason))
 end
 return expected and backup or nil
end
function M.v1Fields(cfg)
 local out={};field(out,'node','V1高清监控 · 传送节点',cfg.node);field(out,'field','V1高清监控 · 约束场',cfg.field);return out
end
function M.saveV1(connection,payload,request)
 local path='/home/bec_hd.config';local expected=read(path)
 assert(expected and ser.serialize(ser.unserialize(expected),false)==ser.serialize(connection,false),'高清连接配置已变化')
 local values=M.parse(payload,M.v1Fields(connection),M.revision(expected));assert(uuid(values.node)and uuid(values.field),'两项地址都需要填写')
 assert(c.methods(values.node).getRequiredCondensate~=nil and c.methods(values.field).getStoredCondensate~=nil,'节点或约束场类型不匹配')
 local next=clone(connection);next.node=values.node;next.field=values.field
 return next,M.commit(path,next,expected,request)
end
function M.v2Fields(cfg)
 local out={}
 field(out,'mainInterface','公共 · 主网供液ME接口',cfg.mainInterface)
 field(out,'workshopInterface','公共 · 样板工坊ME接口（可空）',cfg.workshopInterface)
 field(out,'recipeDirectory','公共 · 配方目录',cfg.recipeDirectory,'path')
 field(out,'cacheTarget','公共 · 库存参考目标',cfg.cacheTarget or 144000,'integer')
 for i,g in ipairs(cfg.groups)do
  local prefix='g'..i..'.';local title='组'..i..' · '
  for _,row in ipairs({{'storage','约束场'},{'gate','公共韦门'},{'subInterface','原液子网ME接口'},{'transposer','供液转运器'}})do field(out,prefix..row[1],title..row[2],g[row[1]])end
  field(out,prefix..'mainSide',title..'主网侧方向',g.mainSide or 4,'side');field(out,prefix..'subSide',title..'子网侧方向',g.subSide or 5,'side')
  assert(#g.generators<=16,'本页面最多配置16台纠缠器/组')
  for j=1,math.max(4,#g.generators)do field(out,prefix..'generator'..j,title..'纠缠器'..j..'（多余可空）',g.generators[j])end
  for j=1,math.max(10,#(g.bulkTransposers or {}))do field(out,prefix..'bulk'..j,title..'高速供液口'..j..'（可空）',(g.bulkTransposers or {})[j])end
  local n=g.nanites or {}
  for _,row in ipairs({{'transposer','转运器'},{'loadRedstone','装入红石'},{'returnRedstone','回收红石'}})do
   field(out,prefix..'bee_'..row[1],title..'蜂群 · '..row[2],n[row[1]])
  end
  for _,row in ipairs({{'bankSide',0,'箱子方向'},{'loadSide',3,'装入端口方向'},{'returnSide',2,'回收端口方向'},{'loadOutputSide',0,'装入红石输出方向'},{'returnOutputSide',0,'回收红石输出方向'}})do
   field(out,prefix..'bee_'..row[1],title..'蜂群 · '..row[3],n[row[1]]or row[2],'side')
  end
 end
 local slots={};for i,n in ipairs(cfg.nodes)do slots[n.slot or i]=n end
 for i=1,16 do
  local n=slots[i]or {};local prefix='n'..i..'.';local title='节点'..i..' · '
  field(out,prefix..'address',title..'组件地址（空位不填）',n.address)
  field(out,prefix..'redstone',title..'暂停红石地址',n.redstone)
  field(out,prefix..'pauseSide',title..'暂停红石方向',n.pauseSide or 1,'side')
  field(out,prefix..'group',title..'设备组编号',n.group or 1,'integer')
  field(out,prefix..'gate',title..'独立韦门（空则用组韦门）',n.gate)
 end
 assert(#out<=1024,'绑定字段超过页面容量');return out
end
function M.applyV2(cfg,payload,revision)
 local values=M.parse(payload,M.v2Fields(cfg),revision);local next=clone(cfg)
 next.mainInterface=values.mainInterface;next.workshopInterface=values.workshopInterface~=''and values.workshopInterface or nil
 next.recipeDirectory=values.recipeDirectory;next.cacheTarget=tonumber(values.cacheTarget)
 for i,g in ipairs(next.groups)do
  local p='g'..i..'.'
  for _,key in ipairs({'storage','gate','subInterface','transposer'})do g[key]=values[p..key]end
  g.mainSide=tonumber(values[p..'mainSide']);g.subSide=tonumber(values[p..'subSide'])
  g.generators={};for j=1,math.max(4,#cfg.groups[i].generators)do local v=values[p..'generator'..j];if v~=''then g.generators[#g.generators+1]=v end end
  g.bulkTransposers={};for j=1,math.max(10,#(cfg.groups[i].bulkTransposers or {}))do local v=values[p..'bulk'..j];if v~=''then g.bulkTransposers[#g.bulkTransposers+1]=v end end
  local n={mode='cell-io'};g.nanites=n
  for _,key in ipairs({'transposer','loadRedstone','returnRedstone'})do n[key]=values[p..'bee_'..key]~=''and values[p..'bee_'..key]or nil end
  for _,key in ipairs({'bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide'})do n[key]=tonumber(values[p..'bee_'..key])end
  n.enabled=n.transposer~=nil
  assert(n.enabled or not(n.loadRedstone or n.returnRedstone or n.supplyInterface or n.hatchInterface),'蜂群设备需完整填写或一起留空')
 end
 local oldSlots={};for i,n in ipairs(cfg.nodes)do oldSlots[n.slot or i]=n end
 next.nodes={}
 for i=1,16 do
  local p='n'..i..'.';local a,r=values[p..'address'],values[p..'redstone']
  if a~=''or r~=''then
   assert(uuid(a)and uuid(r),'节点组件和暂停红石地址需一起填写')
   local group=tonumber(values[p..'group']);assert(next.groups[group],'节点设备组不存在')
   local row=oldSlots[i]and clone(oldSlots[i])or {name='节点'..i}
   row.slot=i;row.address=a;row.redstone=r;row.group=group;row.pauseSide=tonumber(values[p..'pauseSide'])
   row.gate=values[p..'gate']~=''and values[p..'gate']or next.groups[group].gate
   next.nodes[#next.nodes+1]=row
  end
 end
 return next
end
function M.saveV2(C,cfg,payload,request,expected,revision)
 local function unfinished()
  for i in ipairs(cfg.nodes)do
   local r=C.read(C.path('state/node-'..i..'/production.journal'))
   assert(not r or r.stage=='stopped'and not r.pending and not r.plan,'有未完成生产记录，暂不改绑定')
   for _,move in ipairs(r and r.transfers or {})do assert(move.ok==true,'旧搬运未确认，暂不改绑定')end
   for _,job in ipairs(r and r.requests or {})do assert(job.state=='done','旧申请未确认，暂不改绑定')end
  end
  for i in ipairs(cfg.groups)do
   local path='state/group-'..i..'/'
   for _,name in ipairs({'cohort.dat','nanites-cell.journal','nanites.journal'})do
    local r=C.read(C.path(path..name));assert(not r or r.stage==(name=='cohort.dat'and 'stopped'or 'done'),'有未完成批次或换蜂记录，暂不改绑定')
   end
  end
 end
 unfinished()
 for _,n in ipairs(cfg.nodes)do assert(c.invoke(n.address,'getState')~='crafting','旧绑定仍在生产，先退出控制器')end
 for _,g in ipairs(cfg.groups)do for _,a in ipairs(g.generators)do assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'原绑定纠缠器须先停止活动')end end
 local next=M.applyV2(cfg,payload,revision or M.revision(expected));C.validate(next,true)
 for _,n in ipairs(next.nodes)do
  local state=c.invoke(n.address,'getState')
  assert(state=='idle'or(state=='paused-immediate'or state=='nanite-tier-too-low')and c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'先停止生产再改绑定')
 end
 for _,g in ipairs(next.groups)do for _,a in ipairs(g.generators)do assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'纠缠器须先停止活动')end end
 unfinished();return next,M.commit(C.path('config.dat'),next,expected,request)
end
-- Drafts preserve raw incomplete input without touching active config or hardware.
function M.draftFields(cfg,record,expected)
 local fields=M.v2Fields(cfg)
 if type(record)=='table'and record.version==1 and record.base==M.revision(expected)and type(record.values)=='table'then
  for _,f in ipairs(fields)do
   local value=record.values[f.key]
   if type(value)=='string'and #value<=160 and not value:find('[\r\n=]')then f.value=value end
  end
 end
 return fields
end
function M.saveDraft(C,cfg,payload,request,expected,rawDraft,revision)
 assert(read(C.path('config.dat'))==expected,'正式配置已变化，请重新打开')
 local values=M.parse(payload,M.v2Fields(cfg),revision,true)
 local path=C.path('bindings.draft.dat')
 local backup=M.commit(path,{version=1,base=M.revision(expected),values=values},rawDraft,request)
 if backup then fs.remove(backup)end
 return read(path)
end
M.read=read
return M
]=]},
{"lib/patterns.lua",[=[local c=require('component')
return function(C,mode)
 assert(mode=='preview'or mode=='run'or mode=='watch','用法：patterns preview / run / watch')
 local cfg=C.load();local address=assert(cfg.workshopInterface,'先setup绑定专用工坊ME接口')
 assert(address~=cfg.mainInterface,'工坊接口不能用主网供液接口')
 for group,g in ipairs(cfg.groups)do
  assert(address~=g.subInterface,'工坊接口不能用原液子网接口')
  for _,n in ipairs(cfg.nodes)do if n.group==group then
   local state=c.invoke(n.address,'getState')
   assert(mode=='preview'or (state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low'),'先暂停生产再处理样板')
  end end
  for _,a in ipairs(g.generators)do
   assert(mode=='preview'or (c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false),'先关闭纠缠器再处理样板')
  end
 end
 local f=assert(io.open(C.path('runtime/patterns.lua'),'r'));local text=f:read('*a');f:close()
 text=text:gsub('local ADDRESS="[^"]+"',function()return 'local ADDRESS='..string.format('%q',address)end,1)
 text=text:gsub('local DIR="[^"]+"',function()return 'local DIR='..string.format('%q',cfg.recipeDirectory)end,1)
 assert(load(text,'V2样板处理','t',_ENV))(mode)
end
]=]},
{"lib/reports.lua",[=[-- V2 fault outbox. Network polling never sleeps or controls a machine.
local fs=require('filesystem');local ser=require('serialization');local clock=require('computer')
local c=require('component')
local M={}
local MAX=49152
local function read(path,limit)
 local f=io.open(path,'r');if not f then return end
 local s=f:read((limit or MAX)+1)or '';f:close()
 if #s>(limit or MAX)then return nil,'oversize' end
 return s
end
local function quote(s)
 return '"'..s:gsub('[%z\1-\31\\"]',function(x)
  return ({['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'})[x] or string.format('\\u%04x',x:byte())
 end)..'"'
end
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(s)
 local out={}
 for i=1,#s,3 do
  local a,b,d=s:byte(i,i+2);local n=a*65536+(b or 0)*256+(d or 0)
  out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
   ..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
   ..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1)or '=')
   ..(d and alphabet:sub(n%64+1,n%64+1)or '=')
 end
 return table.concat(out)
end
local function encode(s)return(s:gsub('[^%w%-%._~]',function(x)return string.format('%%%02X',x:byte())end))end
local function scrub(s,token)
 s=tostring(s)
 if token and #token>0 then s=s:gsub(token:gsub('([^%w])','%%%1'),'[REDACTED]')end
 return s:gsub('github_pat_[%w_]+','[REDACTED]'):gsub('gh[pousr]_[%w]+','[REDACTED]')
  :gsub('[Aa]uthorization[^\r\n]*','Authorization: [REDACTED]')
end
M.base64=base64
return setmetatable(M,{__call=function(_,cfg,C)
 local R={status='未配置 GitHub 上传'}
 local dir=C.path('diagnostics');local indexPath=dir..'/index.dat'
 local credentialPath=C.path('github-upload.dat')
 local function credentials()
  local v=C.read(credentialPath)
  if not v or type(v.token)~='string' or #v.token<10 then return end
  assert(type(v.owner)=='string'and v.owner:match('^[%w%-]+$')and #v.owner<=39 and type(v.repo)=='string'and v.repo:match('^[%w%._%-]+$')and #v.repo<=100 and v.repo~='.'and v.repo~='..','Invalid diagnostic repository')
  return v
 end
 local state=C.read(indexPath)or {version=1,next=1,reports={},overflow=0}
 assert(state.version==1 and type(state.reports)=='table' and type(state.next)=='number','Invalid diagnostic index')
 local function save()C.write(indexPath,state)end
 local function reportPath(row)
  assert(type(row.id)=='string' and row.id:match('^[%w%-]+$'),'Invalid report id')
  return dir..'/'..row.id..'.txt'
 end
 -- Complete an interrupted report/index transaction before accepting a new fault.
 local writing=C.read(dir..'/writing.dat')
 if writing and type(writing.row)=='table'then
  local row=writing.row;local exists=false
  for _,r in ipairs(state.reports)do if r.id==row.id then exists=true end end
  if not exists then
   local text=read(reportPath(row))
   if text then
    local ok,data=pcall(ser.unserialize,text)
    row.status=ok and type(data)=='table'and data.format=='bec-v2-diagnostic-v1'and 'pending'or 'incomplete'
    state.reports[#state.reports+1]=row;save()
   end
  end
 end
 local function prune()
  local uploaded={}
  for _,r in ipairs(state.reports)do if r.status=='uploaded'then uploaded[#uploaded+1]=r end end
  table.sort(uploaded,function(a,b)return a.sequence>b.sequence end)
  local removed={}
  for i=4,#uploaded do
   local r=uploaded[i];local p=reportPath(r)
   if not fs.exists(p)or fs.remove(p)then removed[r.id]=true end
  end
  if next(removed)then
   local keep={};for _,r in ipairs(state.reports)do if not removed[r.id]then keep[#keep+1]=r end end
   state.reports=keep;save()
  end
 end
 function R.capture(index,engine,reason)
  local pending=0
  for _,r in ipairs(state.reports)do if r.status~='uploaded'then pending=pending+1 end end
  local cred=credentials();local token=cred and cred.token
  if pending>=5 then
   state.overflow=state.overflow+1;state.lastOverflow=scrub(reason,token):sub(1,512);save()
   R.status='报告队列已满：保留5份待上传报告及简短摘要';return
  end
  local group=cfg.nodes[index]and cfg.nodes[index].group
  local parts={'BEC V2 FAULT REPORT','node='..tostring(index)..' group='..tostring(group),
   'reason='..scrub(reason,token),'uptime='..tostring(clock.uptime()),'LAST KNOWN NODE ENTRIES'}
  for i,n in ipairs(cfg.nodes)do if not group or n.group==group then
   local t=engine.tasks[i]or {}
   parts[#parts+1]=ser.serialize({index=i,name=n.name,address=n.address,group=n.group,status=t.status,
    fault=t.fault,entries=t.entries,members=t.members},false):sub(1,4096)
  end end
  parts[#parts+1]='RECENT EVENTS'
  for i=math.max(1,#engine.logs-19),#engine.logs do parts[#parts+1]=scrub(engine.logs[i],token):sub(1,1024)end
  local journals={}
  for i,n in ipairs(cfg.nodes)do if not group or n.group==group then journals[#journals+1]='state/node-'..i..'/production.journal' end end
  local groups=group and {group}or {};if not group then for i in ipairs(cfg.groups)do groups[#groups+1]=i end end
  for _,g in ipairs(groups)do for _,name in ipairs({'cohort.dat','generators.dat','nanites-cell.journal','nanites.journal'})do
   journals[#journals+1]='state/group-'..g..'/'..name
  end end
  for _,p in ipairs(journals)do
   local s,err=read(C.path(p),8192)
   if s then parts[#parts+1]='JOURNAL '..p..'\n'..scrub(s,token)
   elseif err then parts[#parts+1]='JOURNAL '..p..' omitted: '..err end
  end
  local text=scrub(table.concat(parts,'\n'),token)
  if #text>MAX then text=text:sub(1,MAX-32)..'\n[REPORT TRUNCATED]\n' end
  -- ASCII-safe serialized report avoids splitting a UTF-8 codepoint at the cap.
  text=ser.serialize({format='bec-v2-diagnostic-v1',text=text},false)
  if #text>MAX then text=ser.serialize({format='bec-v2-diagnostic-v1',text='Report exceeded encoded limit',reason=scrub(reason,token):sub(1,512)},false)end
  local device=clock.address():gsub('[^%w]',''):sub(1,12)
  local id=device..'-'..tostring(state.next)..'-'..string.format('%.0f',os.time())
  local row={id=id,sequence=state.next,status='pending',owner=cred and cred.owner,repo=cred and cred.repo,branch='main'}
  row.remote='diagnostics/v2/'..id..'.txt'
  assert(not fs.exists(reportPath(row)),'Diagnostic id already exists')
  -- Reserve sequence before writing so a crash never reuses a published path.
  state.next=state.next+1;save()
  C.write(dir..'/writing.dat',{version=1,row=row})
  local f=assert(io.open(reportPath(row),'w'));assert(f:write(text));assert(f:flush());f:close()
  assert(read(reportPath(row))==text,'Diagnostic report read-back failed')
  state.reports[#state.reports+1]=row;save();prune()
  R.status='报告已排队：'..id
  return id
 end
 local current,blockedUntil=nil,0
 local maintenance
 R.historyWanted=true
 local function close()
  if current and current.handle then pcall(current.handle.close)end
  current=nil
 end
 local function fail(message)
  R.status=message;blockedUntil=clock.uptime()+60;close()
 end
 local function start(row,stage,text,cred)
  assert(row.owner==cred.owner and row.repo==cred.repo and row.branch=='main'
   and row.remote=='diagnostics/v2/'..row.id..'.txt','Unexpected upload destination')
  local path=row.remote:gsub('[^/]+',encode)
  local url='https://api.github.com/repos/'..row.owner..'/'..row.repo..'/contents/'..path
  local method,body='GET',nil
  local headers={['User-Agent']='BEC-V2-diagnostics',['Authorization']='Bearer '..cred.token,
   ['Accept']='application/vnd.github.raw+json'}
  if stage=='put'then
   method='PUT';headers.Accept='application/vnd.github+json';headers['Content-Type']='application/json'
   body='{"message":'..quote('BEC V2 fault report '..row.id)..',"branch":'..quote(row.branch)..',"content":'..quote(base64(text))..'}'
  else url=url..'?ref='..encode(row.branch)end
  local net=c.internet
  if not net or type(net.request)~='function'then return fail('报告保留：需要互联网卡')end
  local ok,h=pcall(net.request,url,body,headers,method)
  if not ok or not h then return fail('报告保留：GitHub 请求未建立')end
  current={row=row,stage=stage,text=text,cred=cred,handle=h,deadline=clock.uptime()+20,chunks={},size=0,connected=false}
 end
 local function finish(code,body)
  local job=current;close()
  if job.stage=='check' then
   if code==404 then return start(job.row,'put',job.text,job.cred)end
   if code~=200 or body~=job.text then return fail('报告保留：远程报告未确认一致，HTTP '..tostring(code))end
  elseif job.stage=='put'then
   if code~=201 then return fail('报告保留：GitHub 未确认创建，HTTP '..tostring(code))end
   return start(job.row,'verify',job.text,job.cred)
  else
   if code~=200 or body~=job.text then return fail('报告保留：上传后回读未通过，HTTP '..tostring(code))end
  end
  job.row.status='uploaded'
  job.row.url='https://github.com/'..job.row.owner..'/'..job.row.repo..'/blob/'..job.row.branch..'/'..job.row.remote
  save();R.status='报告已上传：'..job.row.url;prune()
 end
 local function networkStep()
  if current then
   if clock.uptime()>current.deadline then return fail('报告保留：GitHub 请求超时')end
   local h=current.handle
   if not current.connected then
    local connected,err=h.finishConnect();if err then return fail('报告保留：连接失败')end
    if not connected then return end
    current.connected=true;return
   end
   local part,err=h.read(4096)
   if err then return fail('报告保留：网络读取失败')end
   if part then
    current.size=current.size+#part
    if current.size>131072 then return fail('报告保留：网络响应超出限制')end
    current.chunks[#current.chunks+1]=part;return
   end
   local code=h.response()
   return finish(code,table.concat(current.chunks))
  end
  if clock.uptime()<blockedUntil then return end
  local cred=credentials();if not cred then R.status='报告保留：尚未配置 GitHub 写入凭据';blockedUntil=clock.uptime()+60;return end
  for _,row in ipairs(state.reports)do if row.status=='pending'then
   if not row.owner and not row.repo then row.owner=cred.owner;row.repo=cred.repo;save()end
   local text=read(reportPath(row));if not text then return fail('报告文件缺失或过大，保留索引等待核对')end
   start(row,'check',text,cred);return
  end end
 end
 function R.step()
  local ok=pcall(networkStep)
  if not ok then fail('报告保留：上传暂时失败，稍后重试')end
  if R.historyWanted and not maintenance then
   R.historyWanted=false;maintenance=coroutine.create(R.pruneHistory)
  end
  if maintenance then
   local success=coroutine.resume(maintenance)
   if not success or coroutine.status(maintenance)=='dead'then maintenance=nil end
   if not success then R.status='旧历史清理失败，当前记录保持不变'end
  end
 end
 function R.close()close()end
 -- Only successfully completed runtime archives are eligible for deletion.
 function R.pruneHistory()
  local jobs={}
  for i in ipairs(cfg.nodes)do
   jobs[#jobs+1]={directory=C.path('state/node-'..i),stem='production.journal.stopped-',stage='stopped'}
   jobs[#jobs+1]={directory=C.path('state/node-'..i),stem='production.journal.before-resume-',stage='stopped'}
  end
  for i in ipairs(cfg.groups)do jobs[#jobs+1]={directory=C.path('state/group-'..i),stem='nanites-cell.journal.before-run-',stage='done'}end
  for _,job in ipairs(jobs)do if fs.exists(job.directory)then
   local candidates={}
   for name in fs.list(job.directory)do
    local suffix=name:sub(#job.stem+1)
    if name:sub(1,#job.stem)==job.stem and suffix:match('^%d+$')then
     local path=job.directory..'/'..name
     if not fs.isDirectory(path)then
      local text=read(path);local ok,r=pcall(function()return text and ser.unserialize(text)end)
      local complete=ok and type(r)=='table' and r.stage==job.stage and r.pending==nil and r.plan==nil
       and r.configOwned~=true and r.naniteStage==nil and r.pipeline==nil
      for _,move in ipairs(complete and r.transfers or {})do if move.ok~=true then complete=false end end
      for _,request in ipairs(complete and r.requests or {})do if request.state~='done'then complete=false end end
      if complete then candidates[#candidates+1]={path=path,index=tonumber(suffix),time=fs.lastModified(path)}end
     end
     coroutine.yield()
    end
   end
   table.sort(candidates,function(a,b)if a.time~=b.time then return a.time>b.time end;return a.index>b.index end)
   for i=4,#candidates do
    local row=candidates[i]
    assert(fs.lastModified(row.path)==row.time,'History changed during cleanup')
    assert(fs.remove(row.path),'Completed history cleanup failed');coroutine.yield()
   end
  end end
 end
 return R
end})
]=]},
{"lib/scan.lua",[=[local c=require('component')
return function()
 local rows={}
 for address,kind in c.list()do rows[#rows+1]={address=address,kind=kind}end
 table.sort(rows,function(a,b)return a.kind==b.kind and a.address<b.address or a.kind<b.kind end)
 print('OC组件地址 / 只读扫描')
 print('同类型多台设备：临时断开其他同类设备的OC连接，再扫描定位。')
 for _,row in ipairs(rows)do
  if row.kind=='me_interface'or row.kind=='gt_machine'or row.kind=='bec_io_node'or row.kind=='bec_storage'or row.kind=='bec_diode'or row.kind=='redstone'or row.kind=='transposer'then
   print(row.kind..'  '..row.address)
   if row.kind=='gt_machine'then local ok,name=pcall(c.invoke,row.address,'getName');if ok then print('  机器名称：'..tostring(name))end end
   if row.kind=='transposer'then
    for side=0,5 do local ok,name=pcall(c.invoke,row.address,'getInventoryName',side)
     if ok and name then print('  面 '..side..' 库存：'..name)end
    end
   end
  end
 end
 print('方向：0下 1上 2北 3南 4西 5东；方向以转运器/红石I/O自身为准。')
end
]=]},
{"lib/setup.lua",[=[local c=require('component')
local term=require('term')
return function(C,addOnly)
 local function ask(label,default)
  io.write(label..(default~=nil and ' ['..tostring(default)..']' or '')..': ')
  local answer=assert(io.read(),'配置输入已取消')
  return answer=='' and default or answer
 end
 local function number(label,default,lo,hi)
  while true do local n=tonumber(ask(label,default));if n and n==math.floor(n) and n>=lo and n<=hi then return n end;print('请输入 '..lo..' 到 '..hi..' 的整数') end
 end
 local function pick(label,kind,method)
  local rows={}
  for a,t in c.list() do if (not kind or t==kind) and (not method or c.methods(a)[method]~=nil) then rows[#rows+1]={a,t} end end
  table.sort(rows,function(a,b)return a[1]<b[1]end)
  print('\n'..label)
  for i,r in ipairs(rows) do print(i..'  '..r[2]..'  '..r[1]) end
  assert(#rows>0,'找不到 '..label..'；请接入OC网络')
  while true do
   local value=ask('输入序号或地址前缀')
   local index=tonumber(value)
   if index and rows[index] then return rows[index][1] end
   local selected,count=nil,0
   for _,r in ipairs(rows) do if r[1]:sub(1,#value)==value then selected=r[1];count=count+1 end end
   if count==1 then return selected end
   print('选择不唯一或不存在')
  end
 end
 term.clear();print('BEC V2 / 独立测试版配置向导')
 print('方向：0下 1上 2北 3南 4西 5东；配置时只读取设备')
 local previous=C.read(C.path('config.dat'))
 if previous then
  for group in ipairs(previous.groups)do
   for _,file in ipairs({'nanites.journal','nanites-cell.journal'})do local r=C.read(C.path('state/group-'..group..'/'..file));assert(not r or r.stage=='done','蜂群记录未完成，禁止改设备配置')end
   local old=C.read(C.path('state/group-'..group..'/cohort.dat'))
   assert(not old or old.stage=='stopped','本组旧进度尚未结束；先按原配置核对恢复，禁止更换设备绑定')
  end
  print('已有配置。重新配置会备份旧配置，不修改稳定版。')
 end
 if addOnly then
  assert(previous,'首次安装请先运行setup')
  assert(#previous.nodes<16,'已经达到16台节点上限')
  for _,g in ipairs(previous.groups)do for _,a in ipairs(g.generators)do
   assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'先停止生产服务和纠缠器再扩容')
  end end
  for _,n in ipairs(previous.nodes)do
   local state=c.invoke(n.address,'getState')
   assert((state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low')and c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'先暂停原有节点再扩容')
  end
  local count=number('扩容后的总节点数量',#previous.nodes+1,#previous.nodes+1,16)
  for group,g in ipairs(previous.groups)do print('设备组 '..group..'：'..g.name)end
  for i=#previous.nodes+1,count do
   print('\n=== 新增传送节点 '..i..' ===')
   local group=number('归属现有设备组',1,1,#previous.groups)
   previous.nodes[i]={name=ask('节点名称','节点'..i),group=group,
    address=pick('新传送节点','bec_io_node','getState'),redstone=pick('新节点暂停红石I/O','redstone','setOutput'),
    pauseSide=number('红石输出方向',1,0,5),gate=previous.groups[group].gate}
  end
  C.validate(previous,true);C.write(C.path('config.dat'),previous)
  print('扩容已保存；原有设备地址保留。先运行monitor检查，再run启动。');return
 end
 local count=number('传送节点数量',previous and #previous.nodes or 1,1,16)
 local groupCount=number('观测阵列/设备组数量',1,1,count)
 local cfg={version=2,nodes={},groups={},cacheTarget=144000}
 cfg.mainInterface=pick('主网供液接口','me_interface','getFluidsInNetwork')
 cfg.recipeDirectory=ask('配方需求记录目录（新用户直接回车）','/home/bec_v2/recipes')
 if ask('绑定样板处理工坊接口？新用户建议y，已有记录可选n','y')=='y'then
  cfg.workshopInterface=pick('专用工坊ME接口（不要选择生产接口）','me_interface','getInterfacePattern')
 end
 for i=1,groupCount do
  print('\n=== 设备组 '..i..' ===')
  local g={name=ask('设备组名称','观测阵列'..i),generators={},bulkTransposers={}}
  g.storage=pick('此组约束场','bec_storage','getStoredCondensate')
  g.gate=pick('此组韦门','bec_diode','setCondensateFilters')
  g.subInterface=pick('此组原液子网接口','me_interface','getFluidsInNetwork')
  g.transposer=pick('主网到此子网的供液转运器','transposer')
  g.mainSide=number('转运器主网方向',4,0,5);g.subSide=number('转运器子网方向',5,0,5)
  local generators=number('此组纠缠器数量',1,1,64)
  for j=1,generators do g.generators[j]=pick('纠缠器 '..j,'gt_machine','setWorkAllowed') end
  local bulk=number('此组额外高速供液转运器数量（没有填0）',0,0,64)
  for j=1,bulk do g.bulkTransposers[j]=pick('高速供液转运器 '..j,'transposer') end
  local enabled=ask('启用此组自动换蜂群？y/n','n')=='y'
  g.nanites={enabled=enabled}
  if enabled then
   local n=g.nanites
   n.mode=ask('蜂群模式：cell-io硬盘盒 / me-interface旧接口','cell-io')
   assert(n.mode=='cell-io'or n.mode=='me-interface','蜂群模式无效')
   n.transposer=pick('蜂群转运器','transposer')
   if n.mode=='cell-io'then
    n.loadRedstone=pick('装入端ME IO控制红石','redstone','setOutput')
    n.returnRedstone=pick('回收端ME IO控制红石','redstone','setOutput')
    n.bankSide=number('硬盘盒方向',0,0,5);n.loadSide=number('装入ME IO方向',3,0,5);n.returnSide=number('回收ME IO方向',2,0,5)
    n.loadOutputSide=number('装入端红石输出方向',0,0,5);n.returnOutputSide=number('回收端红石输出方向',0,0,5)
   else
    n.supplyInterface=pick('备用蜂群子网接口','me_interface','getItemsInNetwork')
    n.hatchInterface=pick('收容总线子网接口','me_interface','getItemsInNetwork')
    n.supplySide=number('备用网接口方向',2,0,5);n.hatchSide=number('收容网接口方向',4,0,5)
   end
  end
  cfg.groups[i]=g
 end
 for i=1,count do
  print('\n=== 传送节点 '..i..' ===')
  local group=number('归属设备组',1,1,groupCount)
  cfg.nodes[i]={name=ask('节点名称','节点'..i),group=group,
   address=pick('传送节点','bec_io_node','getState'),
   redstone=pick('暂停控制红石I/O','redstone','setOutput'),
   pauseSide=number('红石输出方向',1,0,5),
   gate=cfg.groups[group].gate}
 end
 C.validate(cfg,true)
 C.write(C.path('config.dat'),cfg)
 print('\n配置已保存。运行 lua /home/bec_v2/main.lua monitor 先看仪表盘。')
end
]=]},
{"lib/storage.lua",[=[-- Bounded maintenance: completed archives only; never remove live/recovery data.
local fs=require('filesystem');local ser=require('serialization')
return function(C)
 local S={reserve=524288}
 local function record(path)
  local f=io.open(path,'r');if not f then return end
  local text=f:read(65537);f:close();if not text or #text>65536 then return end
  local ok,r=pcall(ser.unserialize,text);if ok and type(r)=='table'then return r end
 end
 local function complete(r)
  if not r or r.stage~='stopped'or r.pending or r.plan or r.configOwned or r.naniteStage or r.pipeline then return false end
  for _,m in ipairs(r.transfers or {})do if m.ok~=true then return false end end
  for _,j in ipairs(r.requests or {})do if j.state~='done'then return false end end
  return true
 end
 local function prune(directory,pattern,valid,keep)
  if not fs.exists(directory)then return 0 end
  local rows={}
  for name in fs.list(directory)do
   local id=name:match(pattern)
   if id then local path=directory..'/'..name
    if valid(record(path))then rows[#rows+1]={path=path,id=tonumber(id),modified=fs.lastModified and fs.lastModified(path)or 0}end
   end
  end
  table.sort(rows,function(a,b)if a.modified==b.modified then return a.id>b.id end;return a.modified>b.modified end)
  local removed=0;for i=keep+1,#rows do if fs.remove(rows[i].path)then removed=removed+1 end end
  return removed
 end
 function S.prune(cfg)
  local removed=prune(C.ROOT,'^config%.dat%.hd%.bak%.(%d+)$',function(r)return r and r.version==2 and type(r.nodes)=='table'and type(r.groups)=='table'end,2)
  for i in ipairs(cfg.nodes)do
   local dir=C.path('state/node-'..i)
   for _,pattern in ipairs({'^production%.journal%.stopped%-(%d+)$','^production%.journal%.before%-resume%-(%d+)$'})do removed=removed+prune(dir,pattern,complete,3)end
  end
  return removed
 end
 function S.status()
  if not fs.get then return {known=false,ok=false,reserve=S.reserve}end
  local ok,device=pcall(fs.get,C.ROOT)
  if not ok or not device or not device.spaceTotal or not device.spaceUsed then return {known=false,ok=false,reserve=S.reserve}end
  local valid,total,used=pcall(function()return device.spaceTotal(),device.spaceUsed()end)
  if not valid or type(total)~='number'or type(used)~='number'then return {known=false,ok=false,reserve=S.reserve}end
  local free=math.max(0,total-used)
  return {known=true,free=free,total=total,reserve=S.reserve,ok=free>=S.reserve}
 end
 return S
end
]=]},
{"lib/ui.lua",[=[local c=require('component')
local unicode=require('unicode')
return function(cfg,E,C)
 local gpu=c.gpu;assert(gpu,'需要GPU和屏幕')
 local oldW,oldH=gpu.getResolution();local maxW,maxH=gpu.maxResolution()
 local w,h=math.min(120,maxW),math.min(40,maxH)
 assert(w>=80 and h>=25,'屏幕至少需要80×25字符')
 gpu.setResolution(w,h)
 local oldBuffer=gpu.getActiveBuffer and gpu.getActiveBuffer()or 0
 local buffer
 if gpu.allocateBuffer then local ok,value=pcall(gpu.allocateBuffer,w,h);if ok then buffer=value end end
 local selected=1;local page=1;local cachePage=1
 local UI={}
 local bg,panel,white,dim,cyan,green,amber,red=0x080D14,0x111B28,0xDCE7F5,0x73869C,0x35C9EC,0x45D9A1,0xE6B35A,0xF07888
 local function text(x,y,s,color)
  gpu.setForeground(color or white);s=tostring(s)
  while unicode.wlen(s)>w-x do s=unicode.sub(s,1,-2)end
  gpu.set(x,y,s)
 end
 local function read(a,m,...)
  local ok,result=pcall(c.invoke,a,m,...);return ok and result or nil
 end
 local function bar(x,y,width,value,target)
  local ratio=math.max(0,math.min(1,(value or 0)/math.max(1,target or 1)))
  gpu.setBackground(0x213246);gpu.fill(x,y,width,1,' ')
  gpu.setBackground(cyan);local fill=math.floor(width*ratio);if fill>0 then gpu.fill(x,y,fill,1,' ')end
  gpu.setBackground(panel)
 end
 function UI.selected()return selected end
 function UI.key(character,code)
  if code==200 then selected=(selected-2)%#cfg.nodes+1 elseif code==208 then selected=selected%#cfg.nodes+1 end
  if character==110 then cachePage=cachePage+1 end
  if E.monitor then return end
  if character==112 then E.pauseNode(selected)elseif character==114 then E.resumeNode(selected)elseif character==97 then E.pauseAll()end
 end
 function UI.draw()
  if buffer then gpu.setActiveBuffer(buffer)end
  gpu.setBackground(bg);gpu.fill(1,1,w,h,' ')
  text(3,2,'BEC / PARALLEL CONTROL',cyan)
  text(w-28,2,E.monitor and '只读监控 / V2' or '独立测试版 / V2',amber)
  local active,parallel,failed=0,0,0
  for i,n in ipairs(cfg.nodes)do
   local state=read(n.address,'getState');if state=='crafting'then active=active+1 end
   parallel=parallel+(tonumber(read(n.address,'getParallelRecipesInProgress'))or 0)
   if E.tasks[i].fault then failed=failed+1 end
  end
  text(3,4,'节点 '..active..' / '..#cfg.nodes..' 运行    合计并行 '..parallel..'    设备组 '..#cfg.groups..'    故障 '..failed,white)
  local rows=math.min(16,h-22);page=math.floor((selected-1)/rows)+1
  gpu.setBackground(panel);gpu.fill(2,6,w-2,rows+2,' ')
  text(3,6,'节点      设备组   当前状态                  并行 / 蜂群等级 / 蜂群数量',dim)
  for row=1,rows do local i=(page-1)*rows+row;local n=cfg.nodes[i];if n then
   local state=read(n.address,'getState')or '离线'
   local tier=read(n.address,'getProvidedTier');tier=type(tier)=='table'and tier.tier or '?'
   text(3,6+row,(i==selected and '> 'or '  ')..string.format('%02d',i)..' '..n.name,i==selected and cyan or white)
   text(20,6+row,'G'..n.group,dim)
   text(27,6+row,state,state=='crafting'and green or state=='idle'and dim or amber)
   text(54,6+row,tostring(read(n.address,'getParallelRecipesInProgress')or '?')..' / T'..tier..' / '..tostring(read(n.address,'getAvailableNanites')or '?'),white)
  end end
  local g=cfg.groups[cfg.nodes[selected].group];local y=rows+9
  local generators=0;for _,a in ipairs(g.generators)do if read(a,'isMachineActive')then generators=generators+1 end end
  text(3,y,g.name..'   纠缠器 '..generators..' / '..#g.generators..' 运行',cyan)
  text(3,y+1,'调度：'..E.tasks[selected].status..'   '..(g.nanites and g.nanites.enabled and '自动蜂群开启'or '手动蜂群'),dim)
  local stock=read(g.storage,'getStoredCondensate')or {};local keys={}
  for key in pairs(stock)do keys[#keys+1]=key end;table.sort(keys)
  local pages=math.max(1,math.ceil(#keys/3));cachePage=(cachePage-1)%pages+1
  text(3,y+3,'凝聚物库存 / 参考目标 '..(cfg.cacheTarget or 144000)..' mB   '..cachePage..' / '..pages,white)
  for row=1,3 do local key=keys[(cachePage-1)*3+row];if key then
   local yy=y+3+row;local value=stock[key]
   text(3,yy,key:gsub('entangled_','')..'  '..value,dim)
   bar(math.floor(w*0.6),yy,math.floor(w*0.35),value,cfg.cacheTarget)
  end end
  gpu.setBackground(bg)
  text(3,h-4,E.logs[#E.logs]or '同组节点：同配方物理并行，共用蜂群；新批次等整组完成',dim)
  text(3,h-2,E.monitor and '↑↓ 选节点   N 库存翻页   Q 退出监控'or '↑↓ 选节点  P 暂停整组  R 核对后恢复整组  A 暂停全部  Q 安全退出',cyan)
  if buffer then gpu.setActiveBuffer(0);gpu.bitblt(0,1,1,w,h,buffer,1,1)end
 end
 function UI.close()
  if buffer then gpu.setActiveBuffer(oldBuffer);gpu.freeBuffer(buffer)end
  gpu.setResolution(oldW,oldH);gpu.setBackground(0x000000);gpu.setForeground(0xFFFFFF)
 end
 return UI
end
]=]},
{"lib/web_json.lua",[=[-- HTML package loader and bounded JSON decoder. Never evaluates page-provided Lua.
local fs=require('filesystem');local unicode=require('unicode')
local M={null={}}
function M.decode(text)
 assert(type(text)=='string'and #text<=262144,'JSON too large')
 local pos,nodes=1,0
 local function ws()local _,last=text:find('^[ \t\r\n]*',pos);pos=(last or pos-1)+1 end
 local value
 local function str()
  assert(text:sub(pos,pos)=='"','Expected JSON string');pos=pos+1;local out={}
  while pos<=#text do
   local ch=text:sub(pos,pos);pos=pos+1
   if ch=='"'then return table.concat(out)end
   if ch=='\\'then
    local e=text:sub(pos,pos);pos=pos+1
    local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
    if e=='u'then
     local hex=text:sub(pos,pos+3);assert(hex:match('^%x%x%x%x$'),'Invalid Unicode escape');pos=pos+4;local code=tonumber(hex,16)
     if code>=0xD800 and code<=0xDBFF then
      assert(text:sub(pos,pos+1)=='\\u','Missing Unicode surrogate');local tail=text:sub(pos+2,pos+5);assert(tail:match('^%x%x%x%x$'),'Invalid surrogate');local low=tonumber(tail,16);assert(low>=0xDC00 and low<=0xDFFF,'Invalid surrogate');code=0x10000+(code-0xD800)*1024+low-0xDC00;pos=pos+6
     else assert(code<0xDC00 or code>0xDFFF,'Invalid surrogate')end
     out[#out+1]=unicode.char(code)
    else assert(escapes[e],'Invalid JSON escape');out[#out+1]=escapes[e]end
   else assert(ch:byte()>=32,'Control character in JSON');out[#out+1]=ch end
  end
  error('Unterminated JSON string')
 end
 value=function(depth)
  nodes=nodes+1;assert(depth<=8 and nodes<=512,'JSON too complex');ws();local ch=text:sub(pos,pos)
  if ch=='"'then return str()end
  if ch=='{'or ch=='['then
   local object=ch=='{';local result={};pos=pos+1;ws();local ending=object and '}'or ']'
   if text:sub(pos,pos)==ending then pos=pos+1;return result end
   while true do
    ws();local key=object and str()or #result+1
    if object then ws();assert(text:sub(pos,pos)==':','Expected colon');pos=pos+1;assert(result[key]==nil,'Duplicate JSON key')end
    result[key]=value(depth+1);ws();local delimiter=text:sub(pos,pos);pos=pos+1
    if delimiter==ending then return result end;assert(delimiter==',','Expected comma')
   end
  end
  for _,row in ipairs({{'true',true},{'false',false},{'null',M.null}})do if text:sub(pos,pos+#row[1]-1)==row[1]then pos=pos+#row[1];return row[2]end end
  local token=text:match('^-?%d+%.?%d*[eE]?[+-]?%d*',pos);assert(token,'Invalid JSON value')
  assert(not token:match('^-?0%d')and not token:match('%.$')and(not token:find('.',1,true)or token:match('%.%d')),'Invalid JSON number');local number=tonumber(token);assert(number and number==number and math.abs(number)<math.huge,'Invalid JSON number');pos=pos+#token;return number
 end
 local result=value(0);ws();assert(pos>#text,'Trailing JSON content');return result
end
local function read(path,limit)
 local f=assert(io.open(path,'r'),'Missing page file: '..path);local text=f:read(limit+1)or '';f:close();assert(#text<=limit,'Page package too large');return text
end
function M.package(directory)
 local manifest=M.decode(read(fs.concat(directory,'app.json'),16384))
 assert(type(manifest)=='table'and type(manifest.files)=='table'and #manifest.files>=1 and #manifest.files<=32,'Invalid app.json')
 local files,total={},0
 for _,name in ipairs(manifest.files)do
  assert(type(name)=='string'and #name<=100 and name:match('^[%w_./-]+$')and name:sub(1,1)~='/'and not name:find('..',1,true)and not name:find('//',1,true),'Invalid page path')
  assert(not files[name],'Duplicate page file');files[name]=read(fs.concat(directory,name),262144-total);total=total+#files[name]
 end
 return {id=manifest.id,title=manifest.title,entry=manifest.entry or 'index.html',events=manifest.events or {},files=files}
end
return M
]=]},
{"lib/web_page.html",[=[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>BEC V2 · 结构绑定与自动化流程</title><meta name="description" content="用真实GTNH方块结构与贴图查看BEC装配线，旋转、分层、选模块并保存绑定草稿。"><style>:root{--ink:#263342;--muted:#8a95a3;--line:#e5eaf0;--blue:#2e77ee;--teal:#20a88e;--soft:#f5f8fc;--font:'Segoe UI','Microsoft YaHei',sans-serif}*{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;overflow:hidden}body{font:13px/1.5 var(--font);color:var(--ink);background:#fff}button,input,select{font:inherit}button{cursor:pointer}button:focus-visible,input:focus-visible,select:focus-visible,a:focus-visible{outline:2px solid #6ba7ff;outline-offset:3px}button{transition:background .15s,color .15s,border .15s}button:hover{filter:brightness(.98)}button:disabled{cursor:not-allowed;opacity:.5}a{color:var(--blue);text-decoration:none}h1,h2,h3,p{margin:0}[hidden]{display:none!important}.topbar{height:70px;border-bottom:1px solid var(--line);display:flex;align-items:center;padding:0 26px;gap:26px;background:#fff;position:relative;z-index:3}.brand{display:flex;align-items:center;gap:12px;color:var(--ink);white-space:nowrap}.brand strong{font-size:17px;letter-spacing:.3px}.brand strong>span{font-weight:400;color:#9aa5b2;font-size:12px;letter-spacing:1.2px}.brand-icon{position:relative;width:27px;height:30px;display:block}.brand-icon i{position:absolute;width:15px;height:15px;border:2px solid var(--blue);transform:rotate(30deg) skewY(-10deg);border-radius:2px;left:2px;top:4px}.brand-icon i:nth-child(2){left:10px;top:9px;background:white}.brand-icon i:nth-child(3){left:2px;top:14px;background:#eaf2ff}.top-divider{height:25px;border-left:1px solid var(--line)}.project-name{font-size:13px;font-weight:600;white-space:nowrap}.pill{margin-left:12px;padding:3px 7px;font-size:10px;color:#4983d1;background:#edf4ff;border-radius:4px;font-weight:400}.top-actions{margin-left:auto;display:flex;align-items:center;gap:10px}.save-status{font-size:11px;color:#8995a4;margin-right:12px;white-space:nowrap}.save-status i,.statusbar i{display:inline-block;width:5px;height:5px;border-radius:50%;background:var(--teal);margin-right:7px;vertical-align:middle}.save-status.busy i{background:#e9ac40}.save-status.error i{background:#e48163}.button{height:34px;padding:0 13px;border:1px solid #dfe6ef;border-radius:5px;background:#fff;color:#687789;font-size:11px}.button.primary{background:var(--blue);border-color:var(--blue);color:white;box-shadow:0 2px 5px #2e77ee16}.workspace{display:grid;grid-template-columns:238px minmax(300px,1fr) 292px;height:calc(100% - 100px)}.sidebar{border-right:1px solid var(--line);display:flex;flex-direction:column;min-height:0;background:#fff}.side-head{padding:27px 22px 22px}.eyebrow{font-size:8px;font-weight:600;letter-spacing:1.8px;color:#9da8b5;display:block}.side-head h1{font-size:18px;letter-spacing:.3px;font-weight:600;margin-top:7px}.side-head p{font-size:10px;color:#a0a9b5;margin-top:9px;line-height:1.7}.search-box{display:flex;align-items:center;background:#f6f8fb;border:1px solid #edf0f5;border-radius:5px;margin:0 17px 24px;padding:7px 9px;gap:6px}.search-box>span{font-size:19px;line-height:15px;color:#97a4b4}.search-box input{background:none;border:0;outline:none;width:100%;min-width:0;font-size:10px;color:#68788b}.search-box kbd{border:1px solid #e2e7ee;border-radius:3px;font-size:9px;color:#a7b0bd;padding:0 4px}.line-header{display:flex;align-items:center;gap:8px;padding:0 20px 12px;color:#8592a3;font-size:10px}.line-header>b{color:#647487;font-weight:600}.count{margin-left:auto;background:#eff3f8;color:#98a5b4;padding:2px 6px;border-radius:4px;font:9px Consolas,monospace}.tree{overflow-y:auto;flex:1;padding:0 11px 20px}.tree-row{display:flex;align-items:center;gap:10px;width:100%;border:0;background:none;text-align:left;padding:10px 11px;border-radius:5px;margin:3px 0;color:#708094;position:relative;min-height:43px}.tree-row:hover{background:#f6f8fc}.tree-row.active{background:#edf4ff;color:#3478db}.tree-row.active:before{content:'';position:absolute;left:-11px;height:24px;width:3px;background:var(--blue);border-radius:0 3px 3px 0}.module-icon{font:17px var(--font);width:25px;height:25px;display:flex;align-items:center;justify-content:center;border:1px solid #dbe3ec;border-radius:5px;color:#8fa1b5;background:#f8fafc;flex-shrink:0}.tree-row.active .module-icon{border-color:#bdd3f4;color:var(--blue);background:#f6faff}.tree-title{font-size:11px;display:block;font-weight:500}.tree-role{font-size:8px;color:#a2acba;display:block;margin-top:2px}.state-dot{width:5px;height:5px;background:#bdc7d3;flex-shrink:0;display:inline-block;border-radius:50%;margin-left:auto}.state-dot.filled{background:var(--teal);box-shadow:0 0 0 3px #20a88e0a}.node-group-button{display:flex;align-items:center;gap:9px;width:100%;background:none;border:0;padding:12px 11px 6px;color:#8393a7;font-size:10px}.node-group-button .count{margin-left:auto}.node-rows{border-left:1px solid #eaf0f7;margin:6px 0 3px 22px;padding-left:9px}.node-rows .tree-row{min-height:33px;padding:7px 9px}.node-rows .tree-title{font-size:10px}.node-rows .tree-role{display:none}.node-rows .module-icon{width:19px;height:19px;font-size:12px}.node-rows .tree-row.active:before{left:-10px;height:18px;width:2px}.side-footer{padding:18px 22px;border-top:1px solid var(--line);background:#fbfcfe}.source-label{display:flex;align-items:center;gap:6px;font-size:10px;color:#8797a9}.verified{display:inline-flex;align-items:center;justify-content:center;border:1px solid #9fb7d2;border-radius:50%;width:12px;height:12px;font-size:8px;color:#6e96be}.side-footer p{font-size:9px;color:#a3adba;line-height:1.8;margin-top:7px}.text-button{background:none;border:0;padding:0;color:#729bd0;font-size:9px;margin-top:7px}.main{display:flex;flex-direction:column;min-height:0;min-width:0;background:#f1f4f8}.view-header{height:51px;display:flex;align-items:center;justify-content:space-between;gap:14px;padding:0 22px;border-bottom:1px solid #e1e8f0;background:#fafbfd;flex-shrink:0}.breadcrumb{display:flex;align-items:center;gap:10px;font-size:10px;color:#96a2b2;white-space:nowrap}.breadcrumb>span{color:#c0cad6;font-size:9px}.breadcrumb b{font-weight:500;color:#74879b}.view-modes{display:flex;background:#eef2f7;border:1px solid #e6ecf3;padding:3px;border-radius:5px}.view-modes button{background:none;border:0;padding:4px 10px;color:#9aa8b9;font-size:9px;border-radius:3px}.view-modes button.active{background:white;color:#4c7eb9;box-shadow:0 1px 3px #172b4510}.stage{position:relative;flex:1;overflow:hidden;min-height:250px;background:#f0f3f7}.stage>canvas{width:100%;height:100%;display:block;cursor:grab;touch-action:none}.stage>canvas.dragging{cursor:grabbing!important}.labels{position:absolute;inset:0;pointer-events:none}.device-label{position:absolute;transform:translate(-50%,-100%);white-space:nowrap;font-size:10px;border:1px solid #d4e0ed;background:#fffffff2;border-radius:4px;padding:4px 8px;box-shadow:0 2px 7px #39566f09;color:#607d99;pointer-events:auto;cursor:pointer;display:flex;align-items:center;gap:6px}.device-label:after{content:'';position:absolute;width:1px;height:13px;background:#a7bfd7;left:50%;top:100%}.device-label i{width:5px;height:5px;border-radius:2px;background:#6a9cd4}.device-label.node{font-size:8px;padding:3px 5px;color:#439984;border-color:#b6dbd0;background:#f9fffcf2}.device-label.node i{background:#41b18d}.device-label.selected{border-color:#69a3f1;color:#2875d9;box-shadow:0 0 0 3px #448bee0b}.stage-title{position:absolute;left:22px;top:20px;display:flex;align-items:center;gap:8px;color:#778b9f;font-size:10px;pointer-events:none}.live-dot{width:5px;height:5px;border-radius:50%;background:#729bc0}.stage-sub{color:#a5b2c0;font-size:9px;margin-left:3px}.viewport-tools{position:absolute;left:17px;top:58px;background:#fffffff2;border:1px solid #dfe6ef;border-radius:6px;box-shadow:0 2px 7px #2c435309;padding:4px;display:flex;flex-direction:column}.viewport-tools button{border:0;background:none;color:#8397ad;border-radius:3px;width:29px;height:30px;font-size:18px}.viewport-tools button:hover{background:#edf4fc;color:#347ede}.viewport-tools>div{border-top:1px solid #e8edf3;margin:3px}.orientation{position:absolute;right:16px;top:16px;display:flex;align-items:center;gap:3px;font-size:9px;color:#a0aebb}.orientation>span{margin-right:4px}.orientation button{border:1px solid #dce5ef;background:#f9fbfd;color:#95a6b9;font-size:8px;padding:4px 6px;border-radius:3px}.orientation button.active{border-color:#b5cdf0;background:#e8f1ff;color:#4f85cc}.model-callout{position:absolute;top:62px;left:64px;padding:15px 20px 14px 16px;border:1px solid #dde5ef;background:#fffffff0;border-radius:6px;pointer-events:auto;box-shadow:0 4px 18px #182c4205}.model-callout>span{font:7px Consolas,monospace;letter-spacing:1.5px;color:#a4b2c0;display:block}.model-callout strong{display:block;font-size:11px;font-weight:500;color:#70859c;margin:6px 0}.model-callout p{font-size:9px;color:#a4b0bf;line-height:1.8}.model-callout>button{position:absolute;right:7px;top:4px;border:0;background:none;color:#b4bfcd;font-size:15px}.axis-gizmo{position:absolute;bottom:26px;left:18px;width:73px;height:64px;opacity:.75}.axis-gizmo svg{width:100%;height:100%}.stage-help{position:absolute;bottom:13px;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:9px;white-space:nowrap;font-size:8px;color:#9fadb9}.stage-help>span{color:#b8c3ce}.mouse-icon{width:9px;height:13px;border:1px solid #9aabba;border-radius:4px;display:block;position:relative}.mouse-icon:after{content:'';width:1px;height:4px;background:#9aabba;position:absolute;left:3px;top:1px}.renderer-badge{position:absolute;right:13px;bottom:12px;font:7px Consolas,monospace;color:#a9b6c3;letter-spacing:.4px}.layer-bar{height:61px;background:#fafcfe;display:flex;align-items:center;border-top:1px solid #dfe7ef;padding:0 22px;gap:11px;flex-shrink:0}.layer-icon{font-size:23px;color:#91a4b8;margin-right:0}.layer-title{min-width:76px;display:flex;flex-direction:column;gap:2px}.layer-title strong{font-size:10px;font-weight:500;color:#74889e}.layer-title>span{font:8px Consolas,monospace;color:#a2afbf}.layer-bar input{flex:1;min-width:50px;accent-color:#4e8ee9;height:3px;cursor:pointer}.layer-step{font-size:12px;width:20px;height:23px;border:0;background:#f0f4f9;border-radius:4px;color:#9caec0}.mini-button{border:1px solid #d6e5fa;background:#edf4ff;padding:5px 7px;color:#6b9ad7;font-size:8px;border-radius:4px}.view-options{height:42px;display:flex;align-items:center;gap:16px;border-top:1px solid #e8edf3;background:#fff;padding:0 22px;flex-shrink:0;font-size:8px;color:#93a3b4;white-space:nowrap}.view-options label{display:flex;align-items:center;gap:4px;cursor:pointer}.view-options input{width:10px;height:10px;accent-color:#6f99d2;margin:0}.legend{display:flex;gap:5px;align-items:center;margin-left:auto;font-size:7px;color:#a6b3c0}.legend i{display:inline-block;width:5px;height:5px;background:#b8c4d0;border-radius:50%;margin-left:6px}.legend i.filled{background:#20a88e}.legend i.selected{background:#488eea}.inspector{border-left:1px solid var(--line);display:flex;flex-direction:column;min-height:0;overflow-y:auto;background:#fff}.inspector-head{display:flex;align-items:center;justify-content:space-between;padding:28px 23px 22px;border-bottom:1px solid #eef1f6}.inspector-head h2{font-size:16px;font-weight:600;margin-top:7px}.property-icon{font-size:18px;color:#bcc8d4}.module-summary{padding:21px 23px 17px}.module-summary .summary-icon{width:41px;height:41px;display:flex;align-items:center;justify-content:center;font-size:23px;border:1px solid #dbe7f5;border-radius:7px;color:#6b96c8;background:#f3f8fe;margin-bottom:14px}.module-summary h3{font-size:15px;font-weight:600;letter-spacing:.2px}.module-summary p{font-size:9px;color:#9aaabc;margin-top:5px;line-height:1.8}.module-state{display:inline-flex;align-items:center;font-size:8px;gap:5px;margin-top:12px;border-radius:3px;background:#f2f5f9;padding:3px 6px;color:#9cabbc}.module-state i{width:4px;height:4px;border-radius:50%;background:#bac6d1}.module-state.filled{background:#edf9f4;color:#6d9b8d}.module-state.filled i{background:var(--teal)}.properties{border-top:1px solid #edf1f6;padding:18px 23px}.properties-title{font-size:9px;letter-spacing:.5px;color:#75899f;font-weight:500;margin-bottom:15px}.field{margin:0 0 17px}.field>label{display:flex;align-items:center;justify-content:space-between;font-size:10px;color:#8799ac;margin-bottom:7px}.field small{color:#b1bdcb;font-size:8px}.field input,.field select{width:100%;background:#fbfcfe;border:1px solid #e1e8f1;border-radius:5px;padding:10px 9px;color:#5a708a;font-size:10px;outline:none;transition:border-color .2s}.field input{font-family:Consolas,'Microsoft YaHei',monospace;font-size:9px}.field input:focus,.field select:focus{border-color:#83afea;box-shadow:0 0 0 3px #528fea0b}.field input::placeholder{color:#b6c2cf;font-size:8px}.field input.invalid{border-color:#edc2ad;background:#fffdfb}.field .hint{font-size:8px;line-height:1.8;color:#abb8c6;margin-top:6px}.field .hint.error{color:#cd9a80}.direction-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:5px}.direction-grid button{background:#fbfcfe;border:1px solid #e1e8f1;border-radius:4px;color:#a4b1c0;font-size:9px;height:27px}.direction-grid button.active{background:#edf4ff;border-color:#adcaf0;color:#4c82c5}.module-metadata{border-top:1px solid #edf1f6;padding:19px 23px;color:#a6b3c1}.metadata-row{display:flex;justify-content:space-between;font-size:9px;margin:8px 0}.metadata-row b{font:9px Consolas,monospace;font-weight:normal;color:#7e91a7}.metadata-row.role{display:block;font-size:8px;line-height:1.8}.metadata-row.role b{display:block;word-break:break-all;margin-top:4px;font-size:8px}.inspector-bottom{margin-top:auto;padding:17px 23px;border-top:1px solid #eef2f6;background:#fbfcfe;display:flex;gap:9px;align-items:flex-start;color:#a5b5c6}.inspector-bottom>span{font-size:16px;color:#b6c6d6}.inspector-bottom p{font-size:8px;line-height:1.8;color:#a6b4c3}.section-note{font-size:10px;color:#9caebf;line-height:1.95;background:#f7fafe;padding:12px;border:1px solid #e8eef6;border-radius:5px}.related-button{width:100%;margin-top:12px;border:1px solid #cfe0f6;background:#f1f6ff;padding:9px;border-radius:5px;color:#6b95ce;font-size:9px}.validation-state{display:flex;align-items:center;gap:6px;font-size:8px;color:#a0b0c1;background:#f7fafc;padding:9px;border:1px solid #edf2f6;border-radius:4px}.validation-state.valid{color:#5d9c88;background:#f1faf6;border-color:#def0e6}.statusbar{height:30px;border-top:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;padding:0 22px;font-size:8px;color:#a2afbd;background:#fbfcfe}.statusbar b{font:9px Consolas,monospace;color:#7f93a8;font-weight:normal}.status-divider{color:#d6dfe8;margin:0 12px}.toast{position:fixed;left:50%;bottom:55px;transform:translateX(-50%);z-index:10;padding:11px 18px;border:1px solid #dce7f3;background:#fffffff7;box-shadow:0 5px 25px #2b435318;border-radius:6px;font-size:11px;color:#6c8cac;max-width:90vw}.toast.error{border-color:#f1d2bd;color:#ba9277}dialog{border:1px solid #dae5f1;border-radius:10px;box-shadow:0 20px 100px #263b5229;max-width:510px;padding:32px;color:#506981;background:#fff}dialog::backdrop{background:#263c5150}dialog h2{font-size:22px;margin:10px 0 20px}dialog p{font-size:12px;line-height:1.9;color:#8b9fb3;margin-bottom:14px}dialog>a{display:inline-block;margin:8px 20px 12px 0;font-size:11px}.dialog-close{position:absolute;right:13px;top:9px;background:none;border:0;font-size:23px;color:#aab7c6}.license-note{font-size:9px!important;margin-top:12px}::-webkit-scrollbar{width:4px}::-webkit-scrollbar-thumb{background:#d7e0eb;border-radius:4px}@media(min-width:1600px){.workspace{grid-template-columns:260px minmax(300px,1fr) 320px}.side-head,.inspector-head{padding-top:30px}.view-options{font-size:10px}.legend{font-size:9px}.tree-title{font-size:12px}.node-rows .tree-title{font-size:11px}.stage-help{font-size:10px}.field input{font-size:10px}.field>label{font-size:11px}.field .hint{font-size:9px}.module-summary p{font-size:10px}.direction-grid button{font-size:10px}.metadata-row{font-size:10px}.validation-state{font-size:9px}.inspector-bottom p{font-size:9px}.device-label{font-size:12px}.device-label.node{font-size:10px}.tree-role{font-size:9px}.breadcrumb{font-size:11px}.stage-title{font-size:12px}.stage-sub{font-size:10px}}@media(max-width:1100px){.workspace{grid-template-columns:198px minmax(300px,1fr) 250px}.topbar{padding:0 18px;gap:16px}.top-actions{gap:7px}.save-status{display:none}.side-head{padding:23px 17px}.side-head p{font-size:9px}.inspector-head,.module-summary,.properties,.module-metadata{padding-left:18px;padding-right:18px}.view-header{padding:0 14px}.breadcrumb{gap:7px;font-size:9px}.view-modes button{font-size:8px;padding:4px 6px}.view-options{padding:0 12px;gap:10px;font-size:7px}.legend{display:none}.stage-sub{display:none}.model-callout{left:59px;padding:11px 15px}.model-callout p{font-size:8px}.top-divider{display:none}.brand strong>span{font-size:10px}.stage-help{font-size:7px;gap:5px}.renderer-badge{display:none}}@media(max-width:800px){.workspace{grid-template-columns:0 minmax(280px,1fr) 230px}.sidebar{overflow:hidden;border:0}.brand strong>span,.project-name .pill{display:none}.topbar{height:60px;padding:0 14px;gap:20px}.workspace{height:calc(100% - 86px)}.statusbar{height:26px}.statusbar>span:last-child{display:none}.top-actions .quiet{display:none}.project-name{font-size:11px}.button{padding:0 10px}.orientation{gap:2px;right:10px}.orientation>span{display:none}.orientation button{font-size:7px;padding:3px}.model-callout{display:none}.view-header{height:44px}.breadcrumb{display:none}.view-modes{margin-left:auto}.view-options{flex-wrap:wrap;height:52px;gap:6px 10px}.layer-bar{padding:0 12px;gap:7px}.layer-title{min-width:54px}.layer-icon{display:none}.stage-help{display:none}.stage-title{left:14px;font-size:9px}}@media(max-width:540px){.workspace{grid-template-columns:1fr;grid-template-rows:minmax(310px,55%) auto;overflow-y:auto}.main{min-height:360px}.inspector{border-left:0;border-top:1px solid var(--line);overflow:visible}.inspector-head{padding:17px 20px}.inspector-head h2{font-size:14px}.module-summary{padding:15px 20px}.module-summary .summary-icon{display:none}.properties{padding:15px 20px}.module-metadata{padding:15px 20px}.inspector-bottom{display:none}.topbar{gap:14px}.project-name{display:none}.top-actions{margin-left:auto}.statusbar{padding:0 13px}.stage-title{top:13px}.viewport-tools{top:44px;left:10px}.viewport-tools button{width:24px;height:26px}.axis-gizmo{width:50px;left:7px;bottom:10px}.view-options{height:40px}.layer-bar{height:48px}}@media(prefers-reduced-motion:reduce){*{transition:none!important}}

.view-options{flex-wrap:wrap;min-height:54px;height:auto;padding-top:8px;padding-bottom:8px;row-gap:6px}.peripheral-heading{margin-top:12px;border-top:1px solid var(--line);padding-top:14px}.peripheral-heading+.tree-row{margin-top:4px}.tree-role{display:block;max-width:165px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

.signal-links{position:absolute;inset:0;width:100%;height:100%;pointer-events:none;overflow:hidden;z-index:1}.labels{z-index:2}.device-label.channel-A{border-color:#9ec5ff;color:#2264c5;background:#f6faff}.device-label.channel-B{border-color:#c4afe6;color:#8055b4;background:#fbf8ff}.device-label.channel-B i{background:#9462d6}.io-guide{padding:20px 22px;border-top:1px solid var(--line)}.io-channel{border:1px solid #c5d9fa;background:#f7faff;border-radius:8px;padding:13px;margin:12px 0;--pair:#2e77ee}.io-channel.channel-B{--pair:#9462d6;border-color:#d6c8ee;background:#fbf8ff}.io-channel>strong{font-size:12px;color:var(--pair);display:flex;align-items:center;gap:8px}.io-channel>strong i{font-style:normal;background:var(--pair);color:white;border-radius:4px;padding:1px 6px}.io-flow{font-size:11px;margin:10px 0;color:var(--ink)}.io-pair-buttons{display:flex;flex-direction:column;gap:5px;align-items:stretch;text-align:center;margin:13px 0}.io-pair-buttons button{font-size:11px;border:1px solid #d1dceb;background:white;color:var(--pair);border-radius:5px;padding:8px 4px}.io-pair-buttons>span{font-size:9px;color:var(--pair)}.io-channel dl{font-size:11px;margin:0;line-height:1.7}.io-channel dt{color:#8592a4;margin-top:8px}.io-channel dd{margin:1px 0 0;color:#39485b}.io-binding-readout{border-top:1px dashed #d0dbea;padding-top:10px;margin-top:13px;font-size:10px;line-height:1.9;color:#687990}.io-channel .related-button{font-size:10px;margin-top:10px;width:100%;padding:8px 4px}.io-wiring-note{font-size:10px;line-height:1.9;color:#7a889a;margin:14px 0}.io-guide>.related-button{width:100%;font-size:10px}
</style><style>.topbar{height:66px;padding:0 20px;gap:18px}.project-name{font-size:12px}.top-actions{gap:8px}.button{padding:8px 13px}.workspace{height:calc(100% - 96px)}.runtime-tabs{display:flex;gap:4px;margin-left:auto}.runtime-tabs button{border:0;background:transparent;color:#8491a5;padding:10px 14px;border-radius:7px}.runtime-tabs .active{background:#edf3ff;color:#2e77ee}.save-status{min-width:140px;font-size:11px}.run-button{background:#20a88e!important;color:white!important}.stop-button{color:#c25961!important;border-color:#edd3d6!important}.runtime-notice{border-top:1px solid #e5eaf0;padding:9px 18px;background:#fff;color:#6c7b91;font-size:11px;min-height:35px}.flow-panel{background:white;border-top:1px solid #e1e7f0;padding:18px 24px;flex:0 0 310px;overflow:auto}.flow-title{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:20px}.flow-title h2{font-size:17px;font-weight:600}.flow-title p{font-size:11px;color:#8d9aad;margin-top:4px}.elapsed{font-size:24px;font-variant-numeric:tabular-nums;letter-spacing:1px;color:#2e77ee}.elapsed small{font-size:10px;color:#8b98a9;display:block;text-align:right;letter-spacing:0}.flow-path{display:flex;gap:22px;align-items:stretch;margin-bottom:18px}.flow-step{position:relative;flex:1;min-width:72px;border:1px solid #e3e9f1;border-radius:9px;padding:11px 9px;background:#fbfcfe}.flow-step:not(:last-child):after{content:'→';position:absolute;right:-18px;top:26px;color:#a7b4c5}.flow-step .index{font-size:10px;color:#99a8bb;margin-bottom:4px}.flow-step strong{font-size:12px;display:block;white-space:nowrap}.flow-step time{display:block;font-size:11px;color:#8c9bb0;margin-top:8px;font-variant-numeric:tabular-nums}.flow-step.current{border-color:#5b92f5;background:#edf4ff;box-shadow:0 0 0 3px #2e77ee0a}.flow-step.current strong{color:#2e77ee}.flow-step.done{border-color:#d6eae4}.flow-step.done .index{color:#20a88e}.flow-step.fault{border-color:#d7737c;background:#fff5f6}.flow-bottom{display:grid;grid-template-columns:1fr 1.4fr;gap:24px}.flow-bottom h4{font-size:10px;letter-spacing:1px;color:#98a4b4;margin:0 0 8px}.node-list{display:flex;flex-wrap:wrap;gap:6px}.node-chip{border:1px solid #e5eaf1;border-radius:5px;padding:4px 8px;font-size:10px;color:#7b899b}.node-chip.active{border-color:#b2e3d6;color:#20a88e}.runtime-log{font:10px/1.8 'Consolas','Microsoft YaHei',monospace;color:#7d8b9e;max-height:70px;overflow:auto;word-break:break-all}.runtime-running .stage{min-height:190px}.runtime-running .model-callout{display:none}.runtime-running .stage-title{color:#20a88e}.device-label[data-live=active]{color:#168b74;border-color:#88d1bd;box-shadow:0 0 0 4px #20a88e14}.device-label[data-live=active] i{background:#20a88e;box-shadow:0 0 8px #20a88e}.device-label[data-live=phase]{border-color:#d7b877;color:#9d792e}.tree-row[data-live=active] .module-icon{color:#20a88e}.tree-row[data-live=active] .state-dot{background:#20a88e;box-shadow:0 0 7px #20a88e55}.runtime-legend{font-size:10px;color:#8a98aa;margin-top:10px}.runtime-legend b{color:#20a88e;font-weight:400}.runtime-legend em{color:#a48643;font-style:normal}.runtime-settings{border:1px solid #e1e8f2;border-radius:12px;padding:24px;width:530px;max-height:85vh;overflow:auto;box-shadow:0 20px 90px #24334b30}.runtime-settings::backdrop{background:#1d2e4844}.runtime-settings h2{font-size:19px;margin-bottom:7px}.runtime-settings p{font-size:12px;color:#8291a4;margin-bottom:17px}.runtime-settings label{display:block;font-size:12px;color:#65768b;margin-top:13px}.runtime-settings input{width:100%;padding:10px;border:1px solid #dce4ef;border-radius:5px;margin-top:5px}.runtime-settings select{padding:7px;border:1px solid #dce4ef;border-radius:5px}.runtime-settings footer{display:flex;justify-content:flex-end;margin-top:20px}.live-selection{font-size:11px;color:#20a88e;margin-top:8px}.inspector-bottom p{font-size:10px}.runtime-running input,.runtime-running .direction-grid button,.runtime-running #field-group{pointer-events:none;opacity:.55}.offline-alert{color:#c25961!important}.flow-full .flow-panel{flex:1;padding-top:40px}.flow-full .stage,.flow-full .layer-bar,.flow-full .view-options{display:none}.flow-full .flow-path{margin-top:35px;margin-bottom:35px}.flow-full .flow-step{padding:24px 12px}.flow-full .flow-step:not(:last-child):after{top:40px}.flow-full .flow-bottom{margin-top:30px}.flow-full .runtime-log{max-height:240px}.flow-full .flow-panel{min-height:330px}@media(max-width:1300px){.topbar{gap:8px;padding:0 12px}.top-divider,.project-name{display:none}.runtime-tabs button{padding:8px}.button{padding:8px 10px}.flow-panel{padding:15px 16px;flex-basis:295px}.flow-path{gap:15px}.flow-step:not(:last-child):after{right:-13px}.flow-step{padding:10px 5px;min-width:58px}.flow-step strong{font-size:10px}.elapsed{font-size:20px}.save-status{min-width:100px}}

input,textarea{caret-color:#236ee8;cursor:text}input:focus,textarea:focus{outline:2px solid #75a8ff!important;outline-offset:1px;background:#f6faff!important;box-shadow:0 0 0 4px #2e77ee18}input::selection,textarea::selection{background:#aaceff;color:#153766}.field .clear-address{display:block;margin:6px 0 0 auto;padding:3px 9px;border:1px solid #dbe5f2;border-radius:5px;color:#517093;background:#fff;font-size:11px}.ochd-native-select{display:none!important}.ochd-select{display:block;width:100%;min-height:36px;text-align:left;padding:8px 30px 8px 11px;border:1px solid #dce4ef;border-radius:6px;background:#fff;color:#36506b;position:relative}.ochd-select:after{content:'▾';position:absolute;right:11px;color:#6d87a6}.ochd-select[aria-expanded=true],.ochd-select:focus{border-color:#69a4ff;outline:2px solid #bdd6ff}.ochd-select-menu{position:fixed;z-index:10000;max-height:230px;overflow:auto;overscroll-behavior:contain;background:white;border:1px solid #bcd2ed;border-radius:7px;box-shadow:0 8px 28px #25456933;padding:4px}.ochd-select-option{display:block;width:100%;padding:9px 11px;border:0;background:#fff;text-align:left;border-radius:4px;color:#36506b}.ochd-select-option:hover,.ochd-select-option.highlight{background:#e9f2ff;color:#236ee8}.ochd-select-option[aria-selected=true]{font-weight:600}.runtime-running .ochd-select,.runtime-running .clear-address{pointer-events:none;opacity:.55}

.action-feedback{position:fixed;z-index:4;top:66px;left:0;right:0;min-height:44px;max-height:100px;overflow:auto;padding:11px 20px;background:#edf4ff;border-bottom:1px solid #ccdcf2;color:#315f94;font-size:12px;overflow-wrap:anywhere}.action-feedback.action-error{background:#fff0f0;color:#a52d3c;border-color:#efbdc4}.workspace{padding-top:44px}

#binding-issues-list{display:grid;gap:8px;margin:12px 0 18px}#binding-issues-list button{text-align:left;border:1px solid #efc7cd;background:#fff6f7;color:#a52d3c;padding:10px;border-radius:6px}
</style></head><body>
<header class="topbar"><a class="brand" href="#"><span class="brand-icon"><i></i><i></i><i></i></span><strong>BEC<span> / STUDIO</span></strong></a><div class="top-divider"></div><span class="project-name">装配线 01 <span class="pill">配置原型</span></span><div class="top-actions"><span id="save-status" class="save-status"><i></i>本地草稿已就绪</span><button class="button quiet" id="import-btn">↥ 导入草稿</button><button class="button primary" id="export-btn">↧ 导出配置</button><input id="import-file" type="file" accept="application/json,.json" hidden></div></header>
<div class="workspace"><aside class="sidebar"><div class="side-head"><span class="eyebrow">PROJECT EXPLORER</span><h1>装配线结构</h1><p>以实际设备为入口，完成每一处绑定。</p></div><div class="search-box"><span>⌕</span><input id="tree-search" placeholder="查找设备或地址" aria-label="查找设备或地址"><kbd>/</kbd></div><div class="line-header"><span>⌄</span><b>设备组 01</b><span id="binding-count" class="count">0 / 31</span></div><div id="structure-tree" class="tree"></div><div class="side-footer"><div class="source-label"><span class="verified">✓</span><span>GTNH 官方结构数据</span></div><p>GregTech 5.09.54.133<br>方块形状与材质来自原始资源</p><button class="text-button" id="source-button">查看数据来源 ↗</button></div></aside>
<main class="main"><div class="view-header"><div class="breadcrumb">工作区 <span>/</span> 装配线 01 <span>/</span><b id="view-title">整体结构</b></div><div class="view-modes"><button class="active" id="whole-button">整体视图</button><button id="isolate-button">只看选中</button></div></div><div class="stage" id="stage"><canvas id="scene" aria-label="BEC三维装配线，可拖动旋转，滚轮缩放，点击设备配置"></canvas><svg id="signal-links" class="signal-links" aria-label="A装入和B回收红石对应关系"></svg><div id="labels" class="labels"></div><div class="stage-title"><span class="live-dot"></span>结构配置<span class="stage-sub">/ 真实方块模型</span></div><div class="viewport-tools"><button id="fit-button" title="适应当前视图">⊡</button><button id="reset-button" title="恢复默认视角">↻</button><div></div><button id="zoom-in" title="放大">＋</button><button id="zoom-out" title="缩小">−</button></div><div class="orientation"><span>视角</span><button data-view="iso" class="active">等轴</button><button data-view="front">正面</button><button data-view="top">顶面</button></div><div class="model-callout" id="model-callout"><span>01 / STRUCTURE</span><strong>从模型开始配置</strong><p>点击任意设备，打开它的地址绑定。<br>拖动旋转 · 滚轮缩放 · 右键平移</p><button id="dismiss-callout" aria-label="关闭操作提示">×</button></div><div class="axis-gizmo"><svg viewBox="0 0 80 70" id="axes" aria-label="三维方向轴"></svg></div><div class="stage-help"><span class="mouse-icon"></span>左键旋转<span>·</span>右键平移<span>·</span>滚轮缩放</div><div class="renderer-badge" id="renderer-badge">准备模型…</div></div><div class="layer-bar"><div class="layer-icon">▱</div><div class="layer-title"><strong>分层查看</strong><span id="layer-value">全部层</span></div><button id="layer-down" class="layer-step" aria-label="降低一层">−</button><input type="range" id="layer-slider" min="-15" max="49" value="49" step="1" aria-label="显示到哪一层"><button id="layer-up" class="layer-step" aria-label="提高一层">＋</button><button id="all-layers" class="mini-button active">ALL</button></div><div class="view-options"><label><input type="checkbox" id="show-labels" checked>设备标签</label><label><input type="checkbox" id="show-nodes" checked>节点接入标记</label><label><input type="checkbox" id="full-nodes">展开节点结构</label><label><input type="checkbox" id="show-peripherals" checked>AE / OC 外设</label><label class="missing-option"><input type="checkbox" id="only-missing">仅看未填写</label><span class="legend"><i></i>未填写<i class="filled"></i>地址完整<i class="selected"></i>当前选中</span></div></main>
<aside class="inspector"><div class="inspector-head"><div><span class="eyebrow">MODULE INSPECTOR</span><h2>模块配置</h2></div><span class="property-icon">⚙</span></div><div id="inspector-content"></div><div class="inspector-bottom"><span>◈</span><p>这一版保存到当前浏览器。<br>尚未写入 OC 或修改生产配置。</p></div></aside></div>
<footer class="statusbar"><span><i></i><b id="status-module-count">35</b> 个模块<span class="status-divider">|</span><span id="status-selection">观测阵列 01</span></span><span>布局示意 · 主体采用官方结构<span class="status-divider">|</span>OCHD HTML PREVIEW</span></footer>
<div id="toast" class="toast" role="status" hidden></div><dialog id="sources-dialog"><button class="dialog-close" id="sources-close" aria-label="关闭">×</button><span class="eyebrow">SOURCE / PROVENANCE</span><h2>真实结构，真实材质。</h2><p>五类 BEC 主体来自 GTNewHorizons / GT5-Unofficial 的 5.09.54.133 版本，包含逐层结构、控制器位置与方块贴图。AE / OC 外设采用本机模组贴图及放大的方块示意；硬盘箱为占位材质。动画材质在该预览中使用首帧。</p><p>装配线间距、节点示意与外设布局为配置界面示意，不是经过游戏验证的搭建蓝图。绑定草稿由 OC 硬盘保存；机器状态来自 OC 快照。</p><a href="https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/tectech/thing/metaTileEntity/multi/structures/BECStructureDefinitions.java" target="_blank" rel="noreferrer">结构定义 ↗</a><a href="https://github.com/GTNewHorizons/GT5-Unofficial/tree/5.09.54.133/src/main/resources/assets/gregtech/textures/blocks/iconsets" target="_blank" rel="noreferrer">原始材质 ↗</a><p class="license-note">GTNH 主体资源遵循 LGPL-3.0；AE2 材质遵循 CC BY-NC-SA 3.0；OC 材质为 CC0。<a href="SOURCE-NOTICE.txt">查看全部来源与改动</a>。<a href="UPSTREAM-LICENSE.txt">查看许可证</a></p><details><summary>资源来源与许可证全文</summary><pre style="white-space:pre-wrap;font-size:10px">GTNH BEC structures and original texture sprites: GTNewHorizons/GT5-Unofficial, version 5.09.54.133, commit 74150cf3b624e504fd72746606317a3f5b423667. LGPL-3.0. https://github.com/GTNewHorizons/GT5-Unofficial/tree/5.09.54.133 ; texture atlas uses the first frame of the original animated sprites, controller faces composite the original casing/background/active layers. Layout of the line and peripheral icons is illustrative, not a verified construction schematic. Binding data is browser-local only in this prototype.

AE2 interface / IO port textures: AlgorithmX2 et al, CC BY-NC-SA 3.0; extracted from appliedenergistics2-rv3-beta-1050-GTNH.jar. First-frame/cropped/resized and packed into an atlas. These AE2 texture adaptations retain CC BY-NC-SA 3.0: https://creativecommons.org/licenses/by-nc-sa/3.0/ . Source: https://github.com/GTNewHorizons/Applied-Energistics-2-Unofficial (README License section).
OpenComputers transposer/redstone textures: Florian Sangar Noecke et al, CC0 resources per bundled LICENSE; extracted from OpenComputers-1.12.61-GTNH.jar. See OC-RESOURCE-LICENSE.txt.
Peripheral cubes are enlarged schematic single-block representations, not validated physical wiring. Hard disk bank uses a placeholder casing texture. ME IO ports/chest have no standalone OC address: bind their adjacent transposer and sides.


                   GNU LESSER GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. &lt;https://fsf.org/&gt;
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.


  This version of the GNU Lesser General Public License incorporates
the terms and conditions of version 3 of the GNU General Public
License, supplemented by the additional permissions listed below.

  0. Additional Definitions.

  As used herein, &quot;this License&quot; refers to version 3 of the GNU Lesser
General Public License, and the &quot;GNU GPL&quot; refers to version 3 of the GNU
General Public License.

  &quot;The Library&quot; refers to a covered work governed by this License,
other than an Application or a Combined Work as defined below.

  An &quot;Application&quot; is any work that makes use of an interface provided
by the Library, but which is not otherwise based on the Library.
Defining a subclass of a class defined by the Library is deemed a mode
of using an interface provided by the Library.

  A &quot;Combined Work&quot; is a work produced by combining or linking an
Application with the Library.  The particular version of the Library
with which the Combined Work was made is also called the &quot;Linked
Version&quot;.

  The &quot;Minimal Corresponding Source&quot; for a Combined Work means the
Corresponding Source for the Combined Work, excluding any source code
for portions of the Combined Work that, considered in isolation, are
based on the Application, and not on the Linked Version.

  The &quot;Corresponding Application Code&quot; for a Combined Work means the
object code and/or source code for the Application, including any data
and utility programs needed for reproducing the Combined Work from the
Application, but excluding the System Libraries of the Combined Work.

  1. Exception to Section 3 of the GNU GPL.

  You may convey a covered work under sections 3 and 4 of this License
without being bound by section 3 of the GNU GPL.

  2. Conveying Modified Versions.

  If you modify a copy of the Library, and, in your modifications, a
facility refers to a function or data to be supplied by an Application
that uses the facility (other than as an argument passed when the
facility is invoked), then you may convey a copy of the modified
version:

   a) under this License, provided that you make a good faith effort to
   ensure that, in the event an Application does not supply the
   function or data, the facility still operates, and performs
   whatever part of its purpose remains meaningful, or

   b) under the GNU GPL, with none of the additional permissions of
   this License applicable to that copy.

  3. Object Code Incorporating Material from Library Header Files.

  The object code form of an Application may incorporate material from
a header file that is part of the Library.  You may convey such object
code under terms of your choice, provided that, if the incorporated
material is not limited to numerical parameters, data structure
layouts and accessors, or small macros, inline functions and templates
(ten or fewer lines in length), you do both of the following:

   a) Give prominent notice with each copy of the object code that the
   Library is used in it and that the Library and its use are
   covered by this License.

   b) Accompany the object code with a copy of the GNU GPL and this license
   document.

  4. Combined Works.

  You may convey a Combined Work under terms of your choice that,
taken together, effectively do not restrict modification of the
portions of the Library contained in the Combined Work and reverse
engineering for debugging such modifications, if you also do each of
the following:

   a) Give prominent notice with each copy of the Combined Work that
   the Library is used in it and that the Library and its use are
   covered by this License.

   b) Accompany the Combined Work with a copy of the GNU GPL and this license
   document.

   c) For a Combined Work that displays copyright notices during
   execution, include the copyright notice for the Library among
   these notices, as well as a reference directing the user to the
   copies of the GNU GPL and this license document.

   d) Do one of the following:

       0) Convey the Minimal Corresponding Source under the terms of this
       License, and the Corresponding Application Code in a form
       suitable for, and under terms that permit, the user to
       recombine or relink the Application with a modified version of
       the Linked Version to produce a modified Combined Work, in the
       manner specified by section 6 of the GNU GPL for conveying
       Corresponding Source.

       1) Use a suitable shared library mechanism for linking with the
       Library.  A suitable mechanism is one that (a) uses at run time
       a copy of the Library already present on the user&#x27;s computer
       system, and (b) will operate properly with a modified version
       of the Library that is interface-compatible with the Linked
       Version.

   e) Provide Installation Information, but only if you would otherwise
   be required to provide such information under section 6 of the
   GNU GPL, and only to the extent that such information is
   necessary to install and execute a modified version of the
   Combined Work produced by recombining or relinking the
   Application with a modified version of the Linked Version. (If
   you use option 4d0, the Installation Information must accompany
   the Minimal Corresponding Source and Corresponding Application
   Code. If you use option 4d1, you must provide the Installation
   Information in the manner specified by section 6 of the GNU GPL
   for conveying Corresponding Source.)

  5. Combined Libraries.

  You may place library facilities that are a work based on the
Library side by side in a single library together with other library
facilities that are not Applications and are not covered by this
License, and convey such a combined library under terms of your
choice, if you do both of the following:

   a) Accompany the combined library with a copy of the same work based
   on the Library, uncombined with any other library facilities,
   conveyed under the terms of this License.

   b) Give prominent notice with the combined library that part of it
   is a work based on the Library, and explaining where to find the
   accompanying uncombined form of the same work.

  6. Revised Versions of the GNU Lesser General Public License.

  The Free Software Foundation may publish revised and/or new versions
of the GNU Lesser General Public License from time to time. Such new
versions will be similar in spirit to the present version, but may
differ in detail to address new problems or concerns.

  Each version is given a distinguishing version number. If the
Library as you received it specifies that a certain numbered version
of the GNU Lesser General Public License &quot;or any later version&quot;
applies to it, you have the option of following the terms and
conditions either of that published version or of any later version
published by the Free Software Foundation. If the Library as you
received it does not specify a version number of the GNU Lesser
General Public License, you may choose any version of the GNU Lesser
General Public License ever published by the Free Software Foundation.

  If the Library as you received it specifies that a proxy can decide
whether future versions of the GNU Lesser General Public License shall
apply, that proxy&#x27;s public statement of acceptance of any version is
permanent authorization for you to choose that version for the
Library.


Copyright (c) 2013-2015 Florian &quot;Sangar&quot; Nücke

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the &quot;Software&quot;), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED &quot;AS IS&quot;, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

-------------------------------------------------------------------------------

All images / textures and localization strings (resources) are put in the
public domain. More specicially, see CC0 1.0 Universal:

        http://creativecommons.org/publicdomain/zero/1.0/</pre></details></dialog>
<script>window.BEC_DATA = {"sourceRef":"5.09.54.133","sourceCommit":"74150cf3b624e504fd72746606317a3f5b423667","coordinateSystem":"x right,y up,z back; rows stored in original upstream order","models":{"BEC_GENERATOR":{"size":[19,19,34],"controller":[9,9,0],"sourceArrayOrder":"z,rowDown,x","rows":[["                   ","                   ","                   ","                   ","                   ","       GDADG       ","      GE111EG      ","     GE1DDD1EG     ","     D1D111D1D     ","     A1D1~1D1A     ","     D1D111D1D     ","     GE1DDD1EG     ","      GE111EG      ","       GDADG       ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","       GDADG       ","     GGGDADGGG     ","    GGG CAC GGG    ","    GG  CAC  GG    ","   GG  CECEC  GG   ","   DDCCEFFFECCDD   ","   AAAACF FCAAAA   ","   DDCCEFFFECCDD   ","   GG  CECEC  GG   ","    GG  CAC  GG    ","    GGG CAC GGG    ","     GGGDADGGG     ","       GDADG       ","                   ","                   ","                   "],["                   ","                   ","       GDADG       ","     GG CAC GG     ","    G         G    ","   G           G   ","   G           G   ","  G             G  ","  DC           CD  ","  AA           AA  ","  DC           CD  ","  G             G  ","   G           G   ","   G           G   ","    G         G    ","     GG CAC GG     ","       GDADG       ","                   ","                   "],["                   ","                   ","       EEAEE       ","     EEBBABBEE     ","    ECBCCCCCBCE    ","   ECBCFFFFFCBCE   ","   EBCF     FCBE   ","  EBCF       FCBE  ","  EBCF       FCBE  ","  AACF       FCAA  ","  EBCF       FCBE  ","  EBCF       FCBE  ","   EBCF     FCBE   ","   ECBCFFFFFCBCE   ","    ECBCCCCCBCE    ","     EEBBABBEE     ","       EEAEE       ","                   ","                   "],["                   ","        DAD        ","        CAC        ","                   ","                   ","                   ","                   ","                   "," DC             CD "," AA             AA "," DC             CD ","                   ","                   ","                   ","                   ","                   ","        CAC        ","        DAD        ","                   "],["                   ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   "," D               D "," A               A "," D               D ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","                   "],["        DAD        ","        CAC        ","                   ","                   ","                   ","                   ","                   ","                   ","DC               CD","AA               AA","DC               CD","                   ","                   ","                   ","                   ","                   ","                   ","        CAC        ","        DAD        "],["        DAD        ","                   ","                   ","                   ","                   ","                   ","                   ","                   ","D                 D","A                 A","D                 D","                   ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        "],["      EEEAEEE      ","    EEGGBABGGEE    ","   EGGGBBABBGGGE   ","  EBGGBCCCCCBGGBE  "," EGGBBCFFFFFCBBGGE "," EGGBCF     FCBGGE ","EGGBCF       FCBGGE","EGBCF         FCBGE","EBBCF         FCBBE","AAACF         FCAAA","EBBCF         FCBBE","EGBCF         FCBGE","EGGBCF       FCBGGE"," EGGBCF     FCBGGE "," EGGBBCFFFFFCBBGGE ","  EBGGBCCCCCBGGBE  ","   EGGGBBABBGGGE   ","    EEGGBABGGEE    ","      EEEAEEE      "],["        DAD        ","        CAC        ","                   ","                   ","                   ","                   ","                   ","                   ","DC               CD","AA               AA","DC               CD","                   ","                   ","                   ","                   ","                   ","                   ","        CAC        ","        DAD        "],["                   ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   "," D               D "," A               A "," D               D ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","                   "],["                   ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   "," D               D "," A               A "," D               D ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","                   "],["                   ","        DAD        ","        CAC        ","                   ","                   ","                   ","                   ","                   "," DC             CD "," AA             AA "," DC             CD ","                   ","                   ","                   ","                   ","                   ","        CAC        ","        DAD        ","                   "],["                   ","                   ","        DAD        ","                   ","                   ","                   ","                   ","                   ","  D             D  ","  A             A  ","  D             D  ","                   ","                   ","                   ","                   ","                   ","        DAD        ","                   ","                   "],["                   ","                   ","       EEAEE       ","     EEBBABBEE     ","    ECBCCCCCBCE    ","   ECBCFFFFFCBCE   ","   EBCF     FCBE   ","  EBCF       FCBE  ","  EBCF       FCBE  ","  AACF       FCAA  ","  EBCF       FCBE  ","  EBCF       FCBE  ","   EBCF     FCBE   ","   ECBCFFFFFCBCE   ","    ECBCCCCCBCE    ","     EEBBABBEE     ","       EEAEE       ","                   ","                   "],["                   ","                   ","        DAD        ","        CAC        ","                   ","                   ","                   ","                   ","  DC           CD  ","  AA           AA  ","  DC           CD  ","                   ","                   ","                   ","                   ","        CAC        ","        DAD        ","                   ","                   "],["                   ","                   ","                   ","        DAD        ","                   ","                   ","                   ","                   ","   D           D   ","   A           A   ","   D           D   ","                   ","                   ","                   ","                   ","        DAD        ","                   ","                   ","                   "],["                   ","                   ","                   ","        DAD        ","                   ","                   ","                   ","                   ","   D           D   ","   A           A   ","   D           D   ","                   ","                   ","                   ","                   ","        DAD        ","                   ","                   ","                   "],["                   ","                   ","                   ","        DAD        ","        CAC        ","                   ","                   ","                   ","   DC         CD   ","   AA         AA   ","   DC         CD   ","                   ","                   ","                   ","        CAC        ","        DAD        ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","        DAD        ","                   ","                   ","                   ","    D         D    ","    A         A    ","    D         D    ","                   ","                   ","                   ","        DAD        ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","       EEAEE       ","     EEGBABGEE     ","     EBBCCCBBE     ","    EGBCFFFCBGE    ","    EBCF   FCBE    ","    AACF   FCAA    ","    EBCF   FCBE    ","    EGBCFFFCBGE    ","     EBBCCCBBE     ","     EEGBABGEE     ","       EEAEE       ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","        DAD        ","        CAC        ","                   ","                   ","    DC       CD    ","    AA       AA    ","    DC       CD    ","                   ","                   ","        CAC        ","        DAD        ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","        DAD        ","                   ","                   ","     D       D     ","     A       A     ","     D       D     ","                   ","                   ","        DAD        ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","        DAD        ","                   ","                   ","     D       D     ","     A       A     ","     D       D     ","                   ","                   ","        DAD        ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","        DAD        ","        CAC        ","                   ","     DC     CD     ","     AA     AA     ","     DC     CD     ","                   ","        CAC        ","        DAD        ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","                   ","      D     D      ","      A     A      ","      D     D      ","                   ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","       EEAEE       ","      EBBABBE      ","      EBCFCBE      ","      AAF FAA      ","      EBCFCBE      ","      EBBABBE      ","       EEAEE       ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","        CAC        ","      DC   CD      ","      AA   AA      ","      DC   CD      ","        CAC        ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","       D   D       ","       A   A       ","       D   D       ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","       D   D       ","       A   A       ","       D   D       ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","       DCACD       ","       AA AA       ","       DCACD       ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","        A A        ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","                   ","                   ","        EAE        ","        AFA        ","        EAE        ","                   ","                   ","                   ","                   ","                   ","                   ","                   ","                   "],["                   ","                   ","                   ","                   ","                   ","                   ","                   ","                   ","        DAD        ","        A2A        ","        DAD        ","                   ","                   ","                   ","                   ","                   ","                   ","                   ","                   "]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"ElectromagneticWaveguide","1":"ElectromagneticallyIsolatedCasing","2":"FineStructureConstantManipulator"},"solidBlocks":1279,"surfaceFaces":3016},"BEC_CONTAINMENT_FIELD":{"size":[45,17,45],"controller":[22,2,16],"sourceArrayOrder":"z,rowDown,x","rows":[["                                             ","                                             ","                                             ","                                             ","                                             ","                                             ","                    D   D                    ","                    DCBCD                    ","                    DB1BD                    ","                    DCBCD                    ","                    D   D                    ","                                             ","                                             ","                                             ","                                             ","                                             ","                                             "],["                                             ","                                             ","                                             ","                                             ","                                             ","                  DEDDDDDED                  ","                  AAAAAAAAA                  ","                  HE FFF EH                  ","                  HE F F EH                  ","                  HE FFF EH                  ","                  AAAAAAAAA                  ","                  DEDDDDDED                  ","                                             ","                                             ","                                             ","                                             ","                                             "],["                                             ","                                             ","                                             ","                   EDHDHDE                   ","                   EDHDHDE                   ","               DDD         DDD               ","               AAAGGGGGGGGGAAA               ","               HHH         HHH               ","               HHH         HHH               ","               HHH         HHH               ","               AAAGGGGGGGGGAAA               ","               DDD         DDD               ","                   EDHDHDE                   ","                   EDHDHDE                   ","                                             ","                                             ","                                             "],["                                             ","                                             ","                  AAAAAAAAA                  ","                   H     H                   ","                   B     B                   ","            DDD               DDD            ","            AAAGGG         GGGAAA            ","            HHH               HHH            ","            HHH               HHH            ","            HHH               HHH            ","            AAAGGG         GGGAAA            ","            DDD               DDD            ","                   B     B                   ","                   H     H                   ","                  AAAAAAAAA                  ","                                             ","                                             "],["                                             ","                   EDHDHDE                   ","               AAA H     H AAA               ","                  CCCCCCCCC                  ","                   B     B                   ","           D                     D           ","           AGGG               GGGA           ","           H                     H           ","           H                     H           ","           H                     H           ","           AGGG               GGGA           ","           D                     D           ","                   B     B                   ","                  CCCCCCCCC                  ","               AAA H     H AAA               ","                   EDHDHDE                   ","                                             "],["                                             ","                   EDHDHDE                   ","             AA    B     B    AA             ","               CCC B     B CCC               ","                  FFFFFFFFF                  ","         DD                       DD         ","         AAG                     GAA         ","         HH                       HH         ","         HH                       HH         ","         HH                       HH         ","         AAG                     GAA         ","         DD                       DD         ","                  FFFFFFFFF                  ","               CCC B     B CCC               ","             AA    B     B    AA             ","                   EDHDHDE                   ","                                             "],["                   EDDDDDE                   ","                                             ","           AA                   AA           ","             CC               CC             ","               FFF         FFF               ","        D                           D        ","        AGG                       GGA        ","        H                           H        ","        H                           H        ","        H                           H        ","        AGG                       GGA        ","        D                           D        ","               FFF         FFF               ","             CC               CC             ","           AA                   AA           ","                                             ","                   EDDDDDE                   "],["                EEEEEEEEEEEEE                ","                                             ","          A                       A          ","           CC                   CC           ","             FF               FF             ","       D                             D       ","       AG                           GA       ","       H                             H       ","       H                             H       ","       H                             H       ","       AG                           GA       ","       D                             D       ","             FF               FF             ","           CC                   CC           ","          A                       A          ","                                             ","                EEEEEEEEEEEEE                "],["              EEBBBEBBBBBEBBBEE              ","                                             ","         A                         A         ","          C                       C          ","           FF                   FF           ","      D                               D      ","      AG                             GA      ","      H                               H      ","      H                               H      ","      H                               H      ","      AG                             GA      ","      D                               D      ","           FF                   FF           ","          C                       C          ","         A                         A         ","                                             ","              EEBBBEBBBBBEBBBEE              "],["             EBBEEEEEEEEEEEEEBBE             ","                                             ","        A                           A        ","         C                         C         ","          F        GGGGGGG        F          ","     D                                 D     ","     AG                               GA     ","     H                                 H     ","     H             GGGGGGG             H     ","     H                                 H     ","     AG                               GA     ","     D                                 D     ","          F        GGGGGGG        F          ","         C                         C         ","        A                           A        ","                                             ","             EBBEEEEEEEEEEEEEBBE             "],["            EBEE   AAAAAAA   EEBE            ","                   CD   DC                   ","       A           CD   DC           A       ","        C          CD   DC          C        ","         F       GGAAAAAAAGG       F         ","     D             CHHHHHC             D     ","     AG            CHHHHHC            GA     ","     H             CHHHHHC             H     ","     H           GGAAAAAAAGG           H     ","     H             CHHHHHC             H     ","     AG            CHHHHHC            GA     ","     D             CHHHHHC             D     ","         F       GGAAAAAAAGG       F         ","        C          CD   DC          C        ","       A           CD   DC           A       ","                   CD   DC                   ","            EBEE   AAAAAAA   EEBE            "],["           EBE   AAEDHAHDEAA   EBE           ","                  D       D                  ","      A           D       D           A      ","       C         DD       DD         C       ","        F      GGAA       AAGG      F        ","    D            HH       HH            D    ","    AG           HH       HH           GA    ","    H            HH       HH            H    ","    H          GGAA       AAGG          H    ","    H            HH       HH            H    ","    AG           HH       HH           GA    ","    D            HH       HH            D    ","        F      GGAA       AAGG      F        ","       C         DD       DD         C       ","      A           D       D           A      ","                  D       D                  ","           EBE   AAEDHAHDEAA   EBE           "],["          EBE  AA DEDHAHDED AA  EBE          ","                                             ","      A                               A      ","       C       DD           DD       C       ","        F     GAA           AAG     F        ","   D           HH           HH           D   ","   AG          HH           HH          GA   ","   H           HH           HH           H   ","   H          GAA           AAG          H   ","   H           HH           HH           H   ","   AG          HH           HH          GA   ","   D           HH           HH           D   ","        F     GAA           AAG     F        ","       C       DD           DD       C       ","      A                               A      ","                                             ","          EBE  AA DEDHAHDED AA  EBE          "],["         EBE  A   DEDHAHDED   A  EBE         ","                                             ","     A                                 A     ","      C       D               D       C      ","       F     GA               AG     F       ","   D          H               H          D   ","   AG         H               H         GA   ","   H          H               H          H   ","   H         GA               AG         H   ","   H          H               H          H   ","   AG         H               H         GA   ","   D          H               H          D   ","       F     GA               AG     F       ","      C       D               D       C      ","     A                                 A     ","                                             ","         EBE  A   DEDHAHDED   A  EBE         "],["        EBE  A    DEDHAHDED    A  EBE        ","                                             ","     A                                 A     ","      C      D                 D      C      ","       F    GA                 AG    F       ","   D         H                 H         D   ","   AG        H                 H        GA   ","   H         H                 H         H   ","   H        GA                 AG        H   ","   H         H                 H         H   ","   AG        H                 H        GA   ","   D         H                 H         D   ","       F    GA                 AG    F       ","      C      D                 D      C      ","     A                                 A     ","                                             ","        EBE  A    DEDHAHDED    A  EBE        "],["        EBE A     DEDHAHDED     A EBE        ","                                             ","    A                                   A    ","     C      D                   D      C     ","      F    GA                   AG    F      ","  D         H                   H         D  ","  AG        H                   H        GA  ","  H         H                   H         H  ","  H        GA                   AG        H  ","  H         H                   H         H  ","  AG        H                   H        GA  ","  D         H                   H         D  ","      F    GA                   AG    F      ","     C      D                   D      C     ","    A                                   A    ","                                             ","        EBE A     DEDHAHDED     A EBE        "],["       EBE  A     DEBBABBED     A  EBE       ","                    AHCHA                    ","    A               AHCHA               A    ","     C      D       AHCHA       D      C     ","      F    GA       AHCHA       AG    F      ","  D         H       AHCHA       H         D  ","  AG        H       AHCHA       H        GA  ","  H         H       AHCHA       H         H  ","  H        GA       AHCHA       AG        H  ","  H         H       AHCHA       H         H  ","  AG        H       AHCHA       H        GA  ","  D         H       AHCHA       H         D  ","      F    GA       AHCHA       AG    F      ","     C      D       AHCHA       D      C     ","    A               AH~HA               A    ","                    AHCHA                    ","       EBE  A     DEBBABBED     A  EBE       "],["       EBE A     DBBDDADDBBD     A EBE       ","                  HH     HH                  ","    A             HH     HH             A    ","     C     D      HH     HH      D     C     ","      F   GA      HH     HH      AG   F      ","  D        H      HH     HH      H        D  ","  AG       H      HH     HH      H       GA  ","  H        H      HH     HH      H        H  ","  H       GA      HH     HH      AG       H  ","  H        H      HH     HH      H        H  ","  AG       H      HH     HH      H       GA  ","  D        H      HH     HH      H        D  ","      F   GA      HH     HH      AG   F      ","     C     D      HH     HH      D     C     ","    A             HH     HH             A    ","                  HH     HH                  ","       EBE A     DBBDDADDBBD     A EBE       "],["       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       ","           D     HC       CH     D           ","   A       D     HC       CH     D       A   ","    C      D     HC       CH     D      C    ","     F    GA     HC       CH     AG    F     "," D         H     HC       CH     H         D "," AG        H     HC       CH     H        GA "," H         H     HC       CH     H         H "," H        GA     HC       CH     AG        H "," H         H     HC       CH     H         H "," AG        H     HC       CH     H        GA "," D         H     HC       CH     H         D ","     F    GA     HC       CH     AG    F     ","    C      D     HC       CH     D      C    ","   A       D     HC       CH     D       A   ","           D     HC       CH     D           ","       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       "],["      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      ","    EE    C      H   FDG   H      C    EE    ","   AHB    C      H   DFD   H      C    BHA   ","  EHCB    C      H   GDF   H      C    BCHE  ","  EBBF   GA      H   DGD   H      AG   FBBE  "," E        C      H   FDG   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   GDF   H      C        E "," E       GA      H   DGD   H      AG       E "," E        C      H   FDG   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   GDF   H      C        E ","  EBBF   GA      H   DGD   H      AG   FBBE  ","  EHCB    C      H   FDG   H      C    BCHE  ","   AHB    C      H   DFD   H      C    BHA   ","    EE    C      H   GDF   H      C    EE    ","      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      "],["      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      ","    DD    D     A   D   D   A     D    DD    ","   A      D     A   G   G   A     D      A   ","  D C     D     A   D   D   A     D     C D  ","  D  F   GA     A   F A F   A     AG   F  D  "," D        H     A   D   D   A     H        D ","DAG       H     A   G   G   A     H       GAD","D         H     A   D   D   A     H         D","D        GA     A   F A F   A     AG        D","D         H     A   D   D   A     H         D","DAG       H     A   G   G   A     H       GAD"," D        H     A   D   D   A     H        D ","  D  F   GA     A   F A F   A     AG   F  D  ","  D C     D     A   D   D   A     D     C D  ","   A      D     A   G   G   A     D      A   ","    DD    D     A   D   D   A     D    DD    ","      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      "],["      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      ","    HH          H  G     F  H          HH    ","   A            H  D     D  H            A   ","  H C           H  F     G  H           C H  ","  H  F   GA     H  D  A  D  H     AG   F  H  "," D        H     H  G     F  H     H        D "," AG       H     H  D     D  H     H       GA ","CF        H     H  F     G  H     H        FC","BF       GA     H  D  A  D  H     AG       FB","CF        H     H  G     F  H     H        FC"," AG       H     H  D     D  H     H       GA "," D        H     H  F     G  H     H        D ","  H  F   GA     H  D  A  D  H     AG   F  H  ","  H C           H  G     F  H           C H  ","   A            H  D     D  H            A   ","    HH          H  F     G  H          HH    ","      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      "],["      DEBEAAAAAAAAAAAAAAAAAAAAAAAAAEBED      ","    DD          C  D  A  D  C          DD    ","   A            C  F  A  F  C            A   ","  D C           C  D  A  D  C           C D  ","  D  F   GA     C  GAAAAAG  C     AG   F  D  "," D        H     C  D  A  D  C     H        D "," AG       H     C  F  A  F  C     H       GA ","BF        H     C  D  A  D  C     H        FB","1        GA     C  GAAAAAG  C     AG        1","BF        H     C  D  A  D  C     H        FB"," AG       H     C  F  A  F  C     H       GA "," D        H     C  D  A  D  C     H        D ","  D  F   GA     C  GAAAAAG  C     AG   F  D  ","  D C           C  D  A  D  C           C D  ","   A            C  F  A  F  C            A   ","    DD          C  D  A  D  C          DD    ","      DEBEAAAAAAAAAAAAAAAAAAAAAAAAAEBED      "],["      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      ","    HH          H  F     G  H          HH    ","   A            H  D     D  H            A   ","  H C           H  G     F  H           C H  ","  H  F   GA     H  D  A  D  H     AG   F  H  "," D        H     H  F     G  H     H        D "," AG       H     H  D     D  H     H       GA ","CF        H     H  G     F  H     H        FC","BF       GA     H  D  A  D  H     AG       FB","CF        H     H  F     G  H     H        FC"," AG       H     H  D     D  H     H       GA "," D        H     H  G     F  H     H        D ","  H  F   GA     H  D  A  D  H     AG   F  H  ","  H C           H  F     G  H           C H  ","   A            H  D     D  H            A   ","    HH          H  G     F  H          HH    ","      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      "],["      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      ","    DD    D     A   D   D   A     D    DD    ","   A      D     A   G   G   A     D      A   ","  D C     D     A   D   D   A     D     C D  ","  D  F   GA     A   F A F   A     AG   F  D  "," D        H     A   D   D   A     H        D ","DAG       H     A   G   G   A     H       GAD","D         H     A   D   D   A     H         D","D        GA     A   F A F   A     AG        D","D         H     A   D   D   A     H         D","DAG       H     A   G   G   A     H       GAD"," D        H     A   D   D   A     H        D ","  D  F   GA     A   F A F   A     AG   F  D  ","  D C     D     A   D   D   A     D     C D  ","   A      D     A   G   G   A     D      A   ","    DD    D     A   D   D   A     D    DD    ","      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      "],["      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      ","    EE    C      H   GDF   H      C    EE    ","   AHB    C      H   DFD   H      C    BHA   ","  EHCB    C      H   FDG   H      C    BCHE  ","  EBBF   GA      H   DGD   H      AG   FBBE  "," E        C      H   GDF   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   FDG   H      C        E "," E       GA      H   DGD   H      AG       E "," E        C      H   GDF   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   FDG   H      C        E ","  EBBF   GA      H   DGD   H      AG   FBBE  ","  EHCB    C      H   GDF   H      C    BCHE  ","   AHB    C      H   DFD   H      C    BHA   ","    EE    C      H   FDG   H      C    EE    ","      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      "],["       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       ","           D     HC       CH     D           ","   A       D     HC       CH     D       A   ","    C      D     HC       CH     D      C    ","     F    GA     HC       CH     AG    F     "," D         H     HC       CH     H         D "," AG        H     HC       CH     H        GA "," H         H     HC       CH     H         H "," H        GA     HC       CH     AG        H "," H         H     HC       CH     H         H "," AG        H     HC       CH     H        GA "," D         H     HC       CH     H         D ","     F    GA     HC       CH     AG    F     ","    C      D     HC       CH     D      C    ","   A       D     HC       CH     D       A   ","           D     HC       CH     D           ","       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       "],["       EBE A     DBBDDADDBBD     A EBE       ","                  HH     HH                  ","    A             HH     HH             A    ","     C     D      HH     HH      D     C     ","      F   GA      HH     HH      AG   F      ","  D        H      HH     HH      H        D  ","  AG       H      HH     HH      H       GA  ","  H        H      HH     HH      H        H  ","  H       GA      HH     HH      AG       H  ","  H        H      HH     HH      H        H  ","  AG       H      HH     HH      H       GA  ","  D        H      HH     HH      H        D  ","      F   GA      HH     HH      AG   F      ","     C     D      HH     HH      D     C     ","    A             HH     HH             A    ","                  HH     HH                  ","       EBE A     DBBDDADDBBD     A EBE       "],["       EBE  A     DEBBABBED     A  EBE       ","                    AHCHA                    ","    A               AHCHA               A    ","     C      D       AHCHA       D      C     ","      F    GA       AHCHA       AG    F      ","  D         H       AHCHA       H         D  ","  AG        H       AHCHA       H        GA  ","  H         H       AHCHA       H         H  ","  H        GA       AHCHA       AG        H  ","  H         H       AHCHA       H         H  ","  AG        H       AHCHA       H        GA  ","  D         H       AHCHA       H         D  ","      F    GA       AHCHA       AG    F      ","     C      D       AHCHA       D      C     ","    A               AHCHA               A    ","                    AHCHA                    ","       EBE  A     DEBBABBED     A  EBE       "],["        EBE A     DEDHAHDED     A EBE        ","                                             ","    A                                   A    ","     C      D                   D      C     ","      F    GA                   AG    F      ","  D         H                   H         D  ","  AG        H                   H        GA  ","  H         H                   H         H  ","  H        GA                   AG        H  ","  H         H                   H         H  ","  AG        H                   H        GA  ","  D         H                   H         D  ","      F    GA                   AG    F      ","     C      D                   D      C     ","    A                                   A    ","                                             ","        EBE A     DEDHAHDED     A EBE        "],["        EBE  A    DEDHAHDED    A  EBE        ","                                             ","     A                                 A     ","      C      D                 D      C      ","       F    GA                 AG    F       ","   D         H                 H         D   ","   AG        H                 H        GA   ","   H         H                 H         H   ","   H        GA                 AG        H   ","   H         H                 H         H   ","   AG        H                 H        GA   ","   D         H                 H         D   ","       F    GA                 AG    F       ","      C      D                 D      C      ","     A                                 A     ","                                             ","        EBE  A    DEDHAHDED    A  EBE        "],["         EBE  A   DEDHAHDED   A  EBE         ","                                             ","     A                                 A     ","      C       D               D       C      ","       F     GA               AG     F       ","   D          H               H          D   ","   AG         H               H         GA   ","   H          H               H          H   ","   H         GA               AG         H   ","   H          H               H          H   ","   AG         H               H         GA   ","   D          H               H          D   ","       F     GA               AG     F       ","      C       D               D       C      ","     A                                 A     ","                                             ","         EBE  A   DEDHAHDED   A  EBE         "],["          EBE  AA DEDHAHDED AA  EBE          ","                                             ","      A                               A      ","       C       DD           DD       C       ","        F     GAA           AAG     F        ","   D           HH           HH           D   ","   AG          HH           HH          GA   ","   H           HH           HH           H   ","   H          GAA           AAG          H   ","   H           HH           HH           H   ","   AG          HH           HH          GA   ","   D           HH           HH           D   ","        F     GAA           AAG     F        ","       C       DD           DD       C       ","      A                               A      ","                                             ","          EBE  AA DEDHAHDED AA  EBE          "],["           EBE   AAEDHAHDEAA   EBE           ","                  D       D                  ","      A           D       D           A      ","       C         DD       DD         C       ","        F      GGAA       AAGG      F        ","    D            HH       HH            D    ","    AG           HH       HH           GA    ","    H            HH       HH            H    ","    H          GGAA       AAGG          H    ","    H            HH       HH            H    ","    AG           HH       HH           GA    ","    D            HH       HH            D    ","        F      GGAA       AAGG      F        ","       C         DD       DD         C       ","      A           D       D           A      ","                  D       D                  ","           EBE   AAEDHAHDEAA   EBE           "],["            EBEE   AAAAAAA   EEBE            ","                   CD   DC                   ","       A           CD   DC           A       ","        C          CD   DC          C        ","         F       GGAAAAAAAGG       F         ","     D             CHHHHHC             D     ","     AG            CHHHHHC            GA     ","     H             CHHHHHC             H     ","     H           GGAAAAAAAGG           H     ","     H             CHHHHHC             H     ","     AG            CHHHHHC            GA     ","     D             CHHHHHC             D     ","         F       GGAAAAAAAGG       F         ","        C          CD   DC          C        ","       A           CD   DC           A       ","                   CD   DC                   ","            EBEE   AAAAAAA   EEBE            "],["             EBBEEEEEEEEEEEEEBBE             ","                                             ","        A                           A        ","         C                         C         ","          F        GGGGGGG        F          ","     D                                 D     ","     AG                               GA     ","     H                                 H     ","     H             GGGGGGG             H     ","     H                                 H     ","     AG                               GA     ","     D                                 D     ","          F        GGGGGGG        F          ","         C                         C         ","        A                           A        ","                                             ","             EBBEEEEEEEEEEEEEBBE             "],["              EEBBBEBBBBBEBBBEE              ","                                             ","         A                         A         ","          C                       C          ","           FF                   FF           ","      D                               D      ","      AG                             GA      ","      H                               H      ","      H                               H      ","      H                               H      ","      AG                             GA      ","      D                               D      ","           FF                   FF           ","          C                       C          ","         A                         A         ","                                             ","              EEBBBEBBBBBEBBBEE              "],["                EEEEEEEEEEEEE                ","                                             ","          A                       A          ","           CC                   CC           ","             FF               FF             ","       D                             D       ","       AG                           GA       ","       H                             H       ","       H                             H       ","       H                             H       ","       AG                           GA       ","       D                             D       ","             FF               FF             ","           CC                   CC           ","          A                       A          ","                                             ","                EEEEEEEEEEEEE                "],["                   EDDDDDE                   ","                                             ","           AA                   AA           ","             CC               CC             ","               FFF         FFF               ","        D                           D        ","        AGG                       GGA        ","        H                           H        ","        H                           H        ","        H                           H        ","        AGG                       GGA        ","        D                           D        ","               FFF         FFF               ","             CC               CC             ","           AA                   AA           ","                                             ","                   EDDDDDE                   "],["                                             ","                   EDHDHDE                   ","             AA    B     B    AA             ","               CCC B     B CCC               ","                  FFFFFFFFF                  ","         DD                       DD         ","         AAG                     GAA         ","         HH                       HH         ","         HH                       HH         ","         HH                       HH         ","         AAG                     GAA         ","         DD                       DD         ","                  FFFFFFFFF                  ","               CCC B     B CCC               ","             AA    B     B    AA             ","                   EDHDHDE                   ","                                             "],["                                             ","                   EDHDHDE                   ","               AAA H     H AAA               ","                  CCCCCCCCC                  ","                   B     B                   ","           D                     D           ","           AGGG               GGGA           ","           H                     H           ","           H                     H           ","           H                     H           ","           AGGG               GGGA           ","           D                     D           ","                   B     B                   ","                  CCCCCCCCC                  ","               AAA H     H AAA               ","                   EDHDHDE                   ","                                             "],["                                             ","                                             ","                  AAAAAAAAA                  ","                   H     H                   ","                   B     B                   ","            DDD               DDD            ","            AAAGGG         GGGAAA            ","            HHH               HHH            ","            HHH               HHH            ","            HHH               HHH            ","            AAAGGG         GGGAAA            ","            DDD               DDD            ","                   B     B                   ","                   H     H                   ","                  AAAAAAAAA                  ","                                             ","                                             "],["                                             ","                                             ","                                             ","                   EDHDHDE                   ","                   EDHDHDE                   ","               DDD         DDD               ","               AAAGGGGGGGGGAAA               ","               HHH         HHH               ","               HHH         HHH               ","               HHH         HHH               ","               AAAGGGGGGGGGAAA               ","               DDD         DDD               ","                   EDHDHDE                   ","                   EDHDHDE                   ","                                             ","                                             ","                                             "],["                                             ","                                             ","                                             ","                                             ","                                             ","                  DEDDDDDED                  ","                  AAAAAAAAA                  ","                  HE FFF EH                  ","                  HE F F EH                  ","                  HE FFF EH                  ","                  AAAAAAAAA                  ","                  DEDDDDDED                  ","                                             ","                                             ","                                             ","                                             ","                                             "],["                                             ","                                             ","                                             ","                                             ","                                             ","                                             ","                    D   D                    ","                    DCBCD                    ","                    DB1BD                    ","                    DCBCD                    ","                    D   D                    ","                                             ","                                             ","                                             ","                                             ","                                             ","                                             "]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"FineStructureConstantManipulator"},"solidBlocks":5333,"surfaceFaces":15518},"BEC_ASSEMBLER":{"size":[61,31,31],"controller":[30,15,1],"sourceArrayOrder":"z,rowDown,x","rows":[["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","            E           E           E           E            ","           EBE         EBE         EBE         EBE           ","          EB3BE       EB3BE       EB3BE       EB3BE          ","           EBE         EBE         EBE         EBE           ","            E           E           E           E            ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","     AAAAAAAAAAAAAAAAAAAAAAAAA~AAAAAAAAAAAAAAAAAAAAAAAAA     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADDBDDADDCDDADDBD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    B C           C           C           C           C B    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    B C           C           C           C           C B    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A   A     A     A     A     A     A     A     A     A   A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   CC    B     B     B     B     B     B     B     B    CC   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B                                                         B "," B                                                         B "," A    A     A     A     A     A     A     A     A     A    A "," B                                                         B "," B                                                         B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   CC    B     B     B     B     B     B     B     B    CC   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  AC     F     F     F     F     F     F     F     F     CA  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AH   C     C     C     C     C     C     C     C     C   HA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  AC     F     F     F     F     F     F     F     F     CA  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ","                                                             ","                                                             "],["                                                             ","                                                             ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  C   B     B     B     B     B     B     B     B     B   C  "," BH   H     H     H     H     H     H     H     H     H   HB "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," BH   H     H     H     H     H     H     H     H     H   HB ","  C   B     B     B     B     B     B     B     B     B   C  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","                                                             ","                                                             "],["                                                             ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," BH   H     H     H     H     H     H     H     H     H   HB "," CB   B     B     B     B     B     B     B     B     B   BC "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D "," A                                                         A "," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," CB   B     B     B     B     B     B     B     B     B   BC "," BH   H     H     H     H     H     H     H     H     H   HB ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","                                                             "],["                                                             ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D ","EB                                                         BE","EBH                                                       HBE","ABH                                                       HBA","EBH                                                       HBE","EB                                                         BE"," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","                                                             "],["                                                             ","            E           E           E           E            ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," C                                                         C ","EB                                                         BE","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","EB                                                         BE"," C                                                         C "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","            E           E           E           E            ","                                                             "],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","DH                                                         HE","DH                                                         HE","DH                                                         HE","DH                                                         HE","DH                                                         HE","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","DH                                                         HE","DH                                                         HE","DG                                                         GE","DG                                                         GE","DG                                                         GE","DH                                                         HE","DH                                                         HE","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],["           EBE         EBE         EBE         EBE           ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EBH                                                       HBE","ACF                                                       FCA","BH                                                         HE","BG                                                         GD","B                                                           E","D                                                           E","D                                                           B","EG                                                         GB","DH                                                         HB","ACF                                                       FCA","EBH                                                       HBE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","           EBE         EBE         EBE         EBE           "],["          EB3BE       EB3BE       EB3BE       EB3BE          ","     AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA     ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","  A   A     A     A     A     A     A     A     A     A   A  "," A    A     A     A     A     A     A     A     A     A    A "," AH   C     C     C     C     C     C     C     C     C   HA "," AG   G     G     G     G     G     G     G     G     G   GA "," A                                                         A ","ABH                                                       HBA","ACF                                                       FCA","EH                                                         HE","EG                                                         GE","E                                                           E","2                                                           2","D                                                           D","DG                                                         GD","DH                                                         HD","ACF                                                       FCA","ABH                                                       HBA"," A                                                         A "," AG   G     G     G     G     G     G     G     G     G   GA "," AH   C     C     C     C     C     C     C     C     C   HA "," A    A     A     A     A     A     A     A     A     A    A ","  A   A     A     A     A     A     A     A     A     A   A  ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","     AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA     ","          EB3BE       EB3BE       EB3BE       EB3BE          "],["           EBE         EBE         EBE         EBE           ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EBH                                                       HBE","ACF                                                       FCA","EH                                                         HB","DG                                                         GB","E                                                           B","E                                                           D","B                                                           D","BG                                                         GE","BH                                                         HD","ACF                                                       FCA","EBH                                                       HBE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","           EBE         EBE         EBE         EBE           "],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","EH                                                         HD","EH                                                         HD","EG                                                         GD","EG                                                         GD","EG                                                         GD","EH                                                         HD","EH                                                         HD","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","EH                                                         HD","EH                                                         HD","EH                                                         HD","EH                                                         HD","EH                                                         HD","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],["                                                             ","            E           E           E           E            ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," C                                                         C ","EB                                                         BE","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","EB                                                         BE"," C                                                         C "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","            E           E           E           E            ","                                                             "],["                                                             ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D ","EB                                                         BE","EBH                                                       HBE","ABH                                                       HBA","EBH                                                       HBE","EB                                                         BE"," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","                                                             "],["                                                             ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," BH   H     H     H     H     H     H     H     H     H   HB "," CB   B     B     B     B     B     B     B     B     B   BC "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D "," A                                                         A "," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," CB   B     B     B     B     B     B     B     B     B   BC "," BH   H     H     H     H     H     H     H     H     H   HB ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","                                                             "],["                                                             ","                                                             ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  C   B     B     B     B     B     B     B     B     B   C  "," BH   H     H     H     H     H     H     H     H     H   HB "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," BH   H     H     H     H     H     H     H     H     H   HB ","  C   B     B     B     B     B     B     B     B     B   C  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","                                                             ","                                                             "],["                                                             ","                                                             ","            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  AC     F     F     F     F     F     F     F     F     CA  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AH   C     C     C     C     C     C     C     C     C   HA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  AC     F     F     F     F     F     F     F     F     CA  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   CC    B     B     B     B     B     B     B     B    CC   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B                                                         B "," B                                                         B "," A    A     A     A     A     A     A     A     A     A    A "," B                                                         B "," B                                                         B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   CC    B     B     B     B     B     B     B     B    CC   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A   A     A     A     A     A     A     A     A     A   A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    B C           C           C           C           C B    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    B C           C           C           C           C B    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","     AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "],["                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","            E           E           E           E            ","            E           E           E           E            ","           EBE         EBE         EBE         EBE           ","          EB3BE       EB3BE       EB3BE       EB3BE          ","           EBE         EBE         EBE         EBE           ","            E           E           E           E            ","            E           E           E           E            ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             ","                                                             "]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"ElectromagneticallyIsolatedCasing","2":"FineStructureConstantManipulator","3":"FineStructureConstantManipulator"},"solidBlocks":7994,"surfaceFaces":22980},"BEC_IO_NODE":{"size":[7,23,13],"controller":[3,11,0],"sourceArrayOrder":"z,rowDown,x","rows":[["       ","       ","       ","       ","       ","       ","       ","       ","       ","  BAB  "," BBABB "," AA~AA "," BBABB ","  BAB  ","       ","       ","       ","       ","       ","       ","       ","       ","       "],["       ","       ","       ","       ","       ","       ","       ","       ","  DAD  "," D C D ","D     D","AC   CA","D     D"," D C D ","  DAD  ","       ","       ","       ","       ","       ","       ","       ","       "],["       ","       ","       ","       ","       ","       ","   A   ","   A   ","  AAA  "," A   A ","A     A","A     A","A     A"," A   A ","  AAA  ","   A   ","   A   ","       ","       ","       ","       ","       ","       "],["       ","       ","       ","       ","   A   ","   A   ","   D   ","   D   ","  DBD  "," ECFCE ","DCF FCD","AF   FA","DCF FCD"," ECFCE ","  DBD  ","   D   ","   D   ","   A   ","   A   ","       ","       ","       ","       "],["       ","       ","       ","   A   ","   D   ","   D   ","  HBH  ","  HBH  "," DCGCD ","DCF FCD","CF   FC","A     A","CF   FC","DCF FCD"," DCGCD ","  HBH  ","  HBH  ","   D   ","   D   ","   A   ","       ","       ","       "],["       ","       ","   A   ","   D   ","  HBH  ","  HBH  ","  EGE  ","  EGE  "," DBGBD ","DF   FD","H     H","A     A","H     H","DF   FD"," DBGBD ","  EGE  ","  EGE  ","  HBH  ","  HBH  ","   D   ","   A   ","       ","       "],["       ","       ","   A   ","   D   ","  HBH  ","  EGE  ","  HBH  ","  HBH  "," DCBCD ","DCF FCD","CF   FC","A     A","CF   FC","DCF FCD"," DCBCD ","  HBH  ","  HBH  ","  EGE  ","  HBH  ","   D   ","   A   ","       ","       "],["       ","   A   ","   D   ","  HBH  ","  EGE  ","  HBH  ","  HBH  ","   D   ","  DDD  "," ECFCE ","DCF FCD","AF   FA","DCF FCD"," ECFCE ","  DDD  ","   D   ","  HBH  ","  HBH  ","  EGE  ","  HBH  ","   D   ","   A   ","       "],["       ","   A   ","   D   ","  HBH  ","  HBH  ","   D   ","   D   ","   A   ","  AAA  "," AGEGA ","AGEBEGA","AEB1BEA","AGEBEGA"," AGEGA ","  AAA  ","   A   ","   D   ","   D   ","  HBH  ","  HBH  ","   D   ","   A   ","       "],["   A   ","   D   ","  HBH  ","   D   ","   D   ","   A   ","   A   ","       ","  F F  ","       ","F     F","       ","F     F","       ","  F F  ","       ","   A   ","   A   ","   D   ","   D   ","  HBH  ","   D   ","   A   "],["   A   ","   D   ","   D   ","   A   ","   A   ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","   A   ","   A   ","   D   ","   D   ","   A   "],["   A   ","   D   ","   A   ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","   A   ","   D   ","   A   "],["   A   ","   A   ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","   A   ","   A   "]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"FineStructureConstantManipulator"},"solidBlocks":430,"surfaceFaces":908},"BEC_DIODE":{"size":[17,11,11],"controller":[8,5,0],"sourceArrayOrder":"z,rowDown,x","rows":[["                 ","                 ","                 ","                 ","  B  E  B  E  B  ","  B  E  ~  E  B  ","  B  E  B  E  B  ","                 ","                 ","                 ","                 "],["                 ","                 ","  B  E  B  E  B  "," DBDDEDDBDDEDDBD ","              CH ","AAAAAAAAAAAAAAAAA","              CH "," DBDDEDDBDDEDDBD ","  B  E  B  E  B  ","                 ","                 "],["                 ","  B  E  B  E  B  "," AAAAAAAAAAAAAAA ","C    H  H  H  F C","C    C  C  C  F C","D A  A  A  A  F E","C    C  C  C  F C","C    H  H  H  F C"," AAAAAAAAAAAAAAA ","  B  E  B  E  B  ","                 "],["                 "," DBDDEDDBDDEDDBD ","C    H  H  H  F C","  HHHCHHCHHC    H","  C  G  F  G    H","D A  G  F  G    E","  C  G  F  G    H","  HHHCHHCHHC    H","C    H  H  H  F C"," DBDDEDDBDDEDDBD ","                 "],["  B  E  B  E  B  ","              CH ","C    C  C  C  F C","  C  G  F  G    H","D F             E","B F             B","D F             E","  C  G  F  G    H","C    C  C  C  F C","              CH ","  B  E  B  E  B  "],["  B  E  B  E  B  ","AAAAAAAAAAAAAAAAA","D A  A  A  A  F E","D A  G  F  G    E","B F             B","1               2","B F             B","D A  G  F  G    E","D A  A  A  A  F E","AAAAAAAAAAAAAAAAA","  B  E  B  E  B  "],["  B  E  B  E  B  ","              CH ","C    C  C  C  F C","  C  G  F  G    H","D F             E","B F             B","D F             E","  C  G  F  G    H","C    C  C  C  F C","              CH ","  B  E  B  E  B  "],["                 "," DBDDEDDBDDEDDBD ","C    H  H  H  F C","  HHHC  CHHC    H","  C  G  F  G    H","D A  G  F  G    E","  C  G  F  G    H","  HHHCHHCHHC    H","C    H  H  H  F C"," DBDDEDDBDDEDDBD ","                 "],["                 ","  B  E  B  E  B  "," AAAAAAAAAAAAAAA ","C    H  H  H  F C","C    C  C  C  F C","D A  A  A  A  F E","C    C  C  C  F C","C    H  H  H  F C"," AAAAAAAAAAAAAAA ","  B  E  B  E  B  ","                 "],["                 ","                 ","  B  E  B  E  B  "," DBDDEDDBDDEDDBD ","              CH ","AAAAAAAAAAAAAAAAA","              CH "," DBDDEDDBDDEDDBD ","  B  E  B  E  B  ","                 ","                 "],["                 ","                 ","                 ","                 ","  B  E  B  E  B  ","  B  E  B  E  B  ","  B  E  B  E  B  ","                 ","                 ","                 ","                 "]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"FineStructureConstantManipulator","2":"FineStructureConstantManipulator"},"solidBlocks":620,"surfaceFaces":1966},"AE_INTERFACE":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[13,13,13,13,13,13],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"AE_IO":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[15,15,14,16,15,15],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"OC_TRANS":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[17,17,18,18,17,17],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"OC_RS":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[19,19,20,20,19,19],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"BANK_BOX":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[1,1,1,1,1,1],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}}},"textureTiles":{"BEC_CONDUIT.png":0,"BEC_CASING.png":1,"BEC_MANIPULATOR.png":2,"BEC_CONFLICTCASING.png":3,"BEC_PEACECASING.png":4,"BEC_PRIMARYCOIL.png":5,"BEC_SECONDARYCOIL.png":6,"BEC_GLASS.png":7,"BEC_GENERATOR":8,"BEC_CONTAINMENT_FIELD":9,"BEC_ASSEMBLER":10,"BEC_IO_NODE":11,"BEC_DIODE":12},"materialTextures":{"CoherencePreservingPlasmaConduit":0,"ElectromagneticallyIsolatedCasing":1,"FineStructureConstantManipulator":2,"ConflictInducementCasing":3,"PeaceEnforcementCasing":4,"CondensateTransformativeCoil":5,"CondensateGuidanceCoil":6,"ElectromagneticWaveguide":7},"atlas":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAASBUlEQVR4nO2cf4xU1RXHz3szyy7sLixbWFh+rKgghKRuA+IPBLFq7a80Lco/NvqHaSQYY0wgNuk/NTZpmmg0IYRoYogN1tI2CmmINloVRAJVgbCoFMUqFSoIAou7sj9nXvO9M9+3Zy5vZmd38AfL+SQv77777nk/7jn33HPvfTNBc3NzJBUwbty4OJ3JZArO+cfZbLZgD8aMGVNSplgeGTVq1Dcq39nZ6ergzJkz7njy5MnS3t6eWHbGjBly4MABl66pqZHu7m6ZM2dOfL6lpcXtW1tb3X7evHluv2fPHrdva2tz+08++SSWWb169cOtra1b8+dvZD7yjh8/3ox0U1PTUf8cy6eRqK6uLnjQMAwLFOUfk56eHre/6qqrCvLffPNNaW529445cuRI/ILk4MGDbn/27NlzKov3JEll6urq3H779u0F+awoH1YsufrqqxONoKGhIVHeVyyUD0UC7kvJ+w2GHD9+3BkZ6oh1vGPHDkmlUi6NcwsXLnTviXpBPrampqZY0UePHp3d3Nz8PpTN6+o0lY6yUDzKIi9dVVVVUOG4MG7ImxDkoSxbAx6UsmD9+vVy6tQpV/kwgI0bN7o0rPfuu+92lf3QQw/F5R9++OGCSqCVg7lz5yZW3oMPPuj2uO7LL79ccO6mm26SofDaa6+VPB4M3g+tGDw9fry05g2ysapKZnz0UUH5Q5ddJqf6+qAVaevslBVnzzpZNIqjR4/KNddcE5dFC582bVpscDAo5C1atCgugzpmg/KVz5aPfOxxDnucZxmcQ9p5AFoV0Wk/T5+DEdAgoPzGxkbXypAHJbHFPf30064slAy3ppWtgfyWLVtk//79cSumDNO8LgzA90hseag4vxXqPFZs1pPnPXF934voPL6Xlofy5x0+7O6xt7HRKfdY3pAn79/v9jd1dLh775k+HS4tlmUdbtu2TfpgJCKucd1www0F+fCYzKcMW7NWPpTLFu93AdoI4i4A1ub3P8XQ/dChQ4cK8iELZROmKcP95s2bz3l5AOWzouE1NPfff3/i8/j9M5VLD8R3QotNMoyMJ8/3X7FiRdyNwTW/9dZbiYYR9+GZjLv2a/X17nD/rFmy5fTpOA1wjn4K1+b1YUi49quvvho/z8033+wUD6Bw7fFQVnd7xZTvdwG+EaBsGkEY+iBsYNeuXUWDHt8zQBZl4Y6wabl77rknfjmCF9JWroHbZ8uH8nUMgGs8+uijcuutt7qXR1pDpVD5cOd+l8A8ltGKbMgbBZV/3XXXyc6dOwvkEeegblgGMl988YUL6mAEcPto+eB7p065+yDoA2go9Aws054vg27Rb3R4T11PSCNPG8F9990Xe8Yk5eNYGwbSvhFgH151+rT8qq/PbWurq922s6nJbe9Pneo2HvM8y0MWwJJRYU899ZTbAPb33nuve1D0XVAiKgTWDOueOHFi/PBUtlY+gj7IYIM7RZClK0AHXVqRWvk4pnKRh3OlArS2trYC5eOYhgLlwwiKBZjo8+Hq0c9T+fCS2JBGHs6hjB8fPPHEE06ZcO+Ic6h8NChsSCMP51AGZSEDtKvXys8//41UOPP88qHru/LBi8usq3NBCiwaD4wNaeQxyAGQwbHqi5wls3/3hy7nC309vw/X56FotC5sVLr/LNkEebpllEWgio1y/ijGl0efj3pi0DZ27Fi30QhwjnEBQZ3Rs6KbW7NmjVP4ypUrZcOGDW5DGnk4x64QMpDVAZ8e9jEwxMaAT3sKpl0MsKez0ykUe/dQdXWu//r++PHuGGkahl+W6MCOFeOPW1mBPPa7mmLB4YVKQ0ND0TkBHfgmgVY+WDwGWXbdwyXNlk3FAua5YYvyCu7BlPJdXm2tS8N1I+jzAz4oG4pnwMhjVow2AvZpSS2T0HjYLRQL4nB9DjV5r6QKzXjyCPhYlsNWyumgNwm4dwR87YcPx10A4Pu3Tp/uyujuC6MnPgNbOPZ33nlnnI/WDtfPc6hnnIMsW7Y/EmDL5znGAf48QXrX+PGyK5+xrqdnoEISJl74MMLxPzxEb6+rNIzz/YCP4OWhMPbhnA1LmuTBSyLI05WkZ81KtSicY1+vA75igaEPFI1o3w/4QLHhK58T43zd8hn4uXP5NLpSdgEIFNlQECvh2nDzeHe4fT0KgvKh9DvuuMPVP8pCBrKNjY036pk9pKFYKDwpIOSwkek0Kp8Pyr3f1xFaNCsWewRsKI/WwnE6lM8ImNeC8qFAHO/bt8/lHTt2LL42AhxWsB/x6uEWn1HL6shcG4E/DNRltHLb1cgA+Qz4+OxQoI5pUEZP0gB4S4zzMdRDpH+qvj72mmj5jKlYRsuuXbvWBcsEitZGQOVrILNu3br4WCuYRpB0zp8tTGtFYlijFV2KJDdNFw4D0EakXSGUX6xv1ArTY27Icww/WJ/KMrfddlviucFoyytYV67/fBoYonum6dNzxifiDGDuwYMFE0FIcyJI6uvdHl4NhoW6x7X1zCq7VKYZKKIMykIGsrfcckvcwn0j8NcCkmYLnQHA9egpYSjXn4tnHhVPGW0IeCBM8uhxPvt8uP3BlM9W6Y/zy0VfN+kegxlPq/IKSfFCqaDMBciY4VNdA4d77CZcy1eegehRgG5IeiYVaC9EmaQJHj/aB8VmC4OmpqbIn+ChMehpSX1MEC+4F827e4IpSz3OZ0vBSpmfhwUdLKr46BiA8+1JZdLptOu3h7MYNG/ePCfPRaWhLgbhmAtpXBjz68KHgSTlsAbAyTdsaFDoDjDO14tB6PPh9vViELqp9evXf7/YYlASfllnAFIBUELSzF45S6lAV77frZQaDRAo8JuU7+7uTlwOTjJaxDH+cjBnN4lu/RwicpEN6EAUeatWrapoOTiYM2dOdL7W8y9G+fqaQGpqBpaT06nCrhP0Z7KJ+Wc6zkoqDCuSb5kyUfrUc1blvUYURdKPFduEhT1ysr0jFwNwPfyuu+4qWHl75plnSuafOHFCLnb5uu+MlR//vDBCL5fNG591iq1EHiz5wdJhyf/lT+vEeQBUAIdmpeC3AuDKK690FQD3dzHLT2uql58u/WXBlz3lgK7gxU3PSiRBRfJj62tl0S2/kOHwt2fXSYgXgoVrGGQkfRdAKFNKfseO3W4brvyFcP8wDOK8J598sqyNBGFYIP/YH347pHROPpSTJ0+67YVNfy5rY/kgCHNdgF5WxEu/8cZAVL1w4fw4P2natpT84sVXOxkqgdcqJY+ykPPhdXmNr+r+qby8/wy4RpI8+ufhUoks5XX/D1b95nclZbQBdZ7tzhmARlcyYOUlKSUJLb9s2Yvy3HM/ccdskfraPitX/trdx38G8MADq1zeYNdIki33/sXuw+dKkk8KzmbOnClJfPjhhyVlp615X+TTv5adhrwf5JXqyv79o9+LyIAB1I2pyRkAhxZ8QSoO8IX9VqSHI0z7LpPXSCJJvpxhYyn5Ui77q5KPyhgqFsOXPXL/bJF8Cy4nDfkom5Gurq74Gv984bniN8yfY/koykoaFc6oNklxrBRtCEhTRsuX8h5Ll24uaFm+PIwuN2P8SMGzJCnlX0t/KMvLuD+uCTZt+ln+y9ri9wd4Rv0MlBfZGhsmGwdl0A8XA9O04JVXXkk8n4kKvYB23+WkIR+EA/XTuiD3DWG5ZCORok/PIIgzVIkvUCQfleR/UZzkDbQ8zre0bC3r/tdueqnk/Sk/2HNmvHz/GWA4/nMjb7DrlktS9/F1yiP+dFfwo2Ao0K94RtSMBbQM02xhusX5HqGUvKaU4Q12fxoOlKcVWO79U2oKtpz7FwMtv1jrT2KoowDy2Wefua3t7W1lbSwPCkYBrEAd8Om+X48EikXRPjqeAKXkH3/8kTjg8uG5wUYBgzHY8z/u3cd/Ll/+fETylYBRQPUwRwHoAtL+fDeNgFAZxQKkUvJIwxuUGkn48qjsYr9RWL36sSHf3x8WDibv34f3T7p3MTfsR/ul0PJDHQWASkYB7v5+RIwX1tZfrC8tFsVreV/x5cqX02d/W+4ffQtGAR0dHUMaBbA8YoCgpaUlwvInLadUBWgwFYrlXKxqXczyl04d7+byhzOV+4+/b3DpSuTH1ddKbzhWhsOJTz8emAjCCw11MURzscsf8L5zHCqVyg8X5wEqWc+v9HuAC11+wrhqN6OGnjwjuXn9lEQuzXl+7eqx+IO4D11/Noqkq6u7YnkA+WxePpQon9afegwcZ7KBk+/q7pG0W89uqBv2enR7Z+85+UEQxJ+QYcPaNPf6HI57e79Z+Ynel0tDZffu3QOrORcg6bramorWo8982S9XXHGFO+Y3gqhY9KW6wvv7+12aEzyjR492n3Ihr1L5BQsWxJ9ZocVqeSgaeZB3L5xOuw3X3J7/geX8+aXXB4qxe3fySuOFRDqLwaCIPP/880MSvP322yUVDAyj3nnnndil8o8XoACc50ji9ddfdwqrra11f3hA5WLPIAzy/K085aEwpLdu3RrL4/eGWl4bCpSOvb4/Wzw2QIO62Enr9eihgnlwVCIWFVDRcMf41woqihWu3S++g4PbZUunEpDGh5X4pm4w+UmTJsUy2gjw62K2eCidPy7V3mTZsmXy7rvvFhjDUFr08uXLR0TLJ+lK17NzCgzct3VQDCuaX8mykuGe0bphIMyn8qE0tGr+MLOYPNw+vyxmq9fXwvZS5yH5MgilPR3I1N6MfIlrZ7NyKBXKjExW3rv+euetaDQ+Gz97r6T8ifnzR5YBVLKgQFkoAMMo/Zt65HHZEYqrGV3jjpGPIZVufVAEPnFGF6Hl+ZMxGBc2yl977bUFv1tgMOj6+Ujk82xWTmZE/hOJVEdZ6ejJSDYdyYyqQLq7uuJuIps0iZMgPxWLJvCUXvFKF4O+DYTnYyaL37MDKCIpMj/Tfsa1arR0/uY9vo4yBsiinN86+ak1fm7Nvp1AoexSDlehvw/kRDaSOsx0OQ/jgh35bxhKb/5397h/kOABkuRTYSBVmZz8SCNdaj17MLAezcCLQAn+N/HaE1DZbM060GO/7/8jGI9hPO6h02lnJJSHMimPsXEqEumJxCmxIQxkXHVKJkWBXJLJysf5rqXYj02ySv7trn6px8hjTE7+MsnKwC8Sh/YBybeVikwaXQADNCghG5X2JlRYf39fwficgZsflCXJM+jDl7yUB/xHjUv7clMgC0aFMhbKCxDppuUI7p33MPr+Plq+NgjcfLmWH2mc803gcGAXEKDqgiD+WRdbGY7ZunNj8oz7IlW7YCiEgRx/rKFjAD0qoOIon8nAA+XOZwORI739cjAjMrMmJVOCQPAXCpekAumQ3CgC99dBqAbyDaHIvv7IybeEhfIjjYpHAfyrOGxolfjOHu5dr1CBqVOnutZHl69/ZcP+G10ERgmQPZ3//yEARc2ePTvuNmgslO/rywV1ONeZz58c5JQGU5kUZQR/z0gPwPslAXlcYXqYmy715UcaYaWfFQEof+/eva51odWy5XPoB9Bn4zduCOYwXocM3TcneWg4jBnQ8tnvIw9fseDHGBxtUB4xCLuQuiiS746uklm1VVIfiUyJImmOIvk8DNxwrr+vP+4uwoT4B/IwrkwqSJQfaaQrGQWgf0Vl6X4YHgCKwJ5DLR21owXW19dLP2KG/FicP82CkXCeAHsEdpzRIzCECRMmxJ7DTQ9jpjCblcWLF8sfZ892XRF6bH1/N4yLRKKe7ngWMOu9OyZ5MM4H6IRghvzedjSWT2XkUdEogLKoUMzjY4iGSsV38WxhdNcoA+VxGJfJK49xAd0/jvFXbSjPeX+Ug3HBO2CySc8iugA0P+z84IMP3LIqDCfp/iyvp481mOAZSZM8QwoCMbc/HNiC0UfzmFOxeloWBnL55ZfHCtWBHH4ivmTJEnfMeXwqn2ncA+sHUK6exOH96IWw13MMSKfClISpXL5eFzBEgrmzpkeVrEf/73hHwVSsK+PN8um0VhzLfh3yNBq92gimTJki5QDDgwHxfpS/0JeDDcMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMOQc/g/z390b1xxdH8AAAAASUVORK5CYII="};</script><script>window.BEC_PERIPHERALS = [
{id:'main-me',key:'AE_INTERFACE',title:'主网供液 ME 接口',p:[68,-7,50],role:'mainInterface',type:'ME INTERFACE',icon:'▧',description:'公共供液网络'},
{id:'workshop-me',key:'AE_INTERFACE',title:'样板工坊 ME 接口',p:[80,-7,50],role:'workshopInterface',type:'ME INTERFACE',icon:'▧',description:'公共样板接口 · 可选'},
{id:'sub-me',key:'AE_INTERFACE',title:'原液子网 ME 接口',p:[92,-7,50],role:'groups[1].subInterface',type:'ME INTERFACE',icon:'▧',description:'原液子网络'},
{id:'fluid-transposer',key:'OC_TRANS',title:'供液转运器',p:[104,-7,50],role:'groups[1].transposer',type:'FLUID TRANSPOSER',icon:'⇄',description:'主网 → 原液子网',sides:[['mainSide','主网侧方向',4],['subSide','子网侧方向',5]]},
{id:'bulk-transposer-1',key:'OC_TRANS',title:'高速供液转运器 01',p:[116,-7,50],role:'groups[1].bulkTransposers[1]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 01'},
{id:'bulk-transposer-2',key:'OC_TRANS',title:'高速供液转运器 02',p:[128,-7,50],role:'groups[1].bulkTransposers[2]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 02'},
{id:'bulk-transposer-3',key:'OC_TRANS',title:'高速供液转运器 03',p:[140,-7,50],role:'groups[1].bulkTransposers[3]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 03'},
{id:'bulk-transposer-4',key:'OC_TRANS',title:'高速供液转运器 04',p:[152,-7,50],role:'groups[1].bulkTransposers[4]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 04'},
{id:'bulk-transposer-5',key:'OC_TRANS',title:'高速供液转运器 05',p:[164,-7,50],role:'groups[1].bulkTransposers[5]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 05'},
{id:'bulk-transposer-6',key:'OC_TRANS',title:'高速供液转运器 06',p:[116,-7,64],role:'groups[1].bulkTransposers[6]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 06'},
{id:'bulk-transposer-7',key:'OC_TRANS',title:'高速供液转运器 07',p:[128,-7,64],role:'groups[1].bulkTransposers[7]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 07'},
{id:'bulk-transposer-8',key:'OC_TRANS',title:'高速供液转运器 08',p:[140,-7,64],role:'groups[1].bulkTransposers[8]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 08'},
{id:'bulk-transposer-9',key:'OC_TRANS',title:'高速供液转运器 09',p:[152,-7,64],role:'groups[1].bulkTransposers[9]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 09'},
{id:'bulk-transposer-10',key:'OC_TRANS',title:'高速供液转运器 10',p:[164,-7,64],role:'groups[1].bulkTransposers[10]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 10'},
{id:'nanite-bank',key:'BANK_BOX',title:'蜂群硬盘箱',p:[6,-7,58],role:null,type:'CELL BANK',icon:'▣',description:'无独立 OC 地址 · 外形示意',related:'nanite-transposer',note:'硬盘箱通过蜂群转运器的箱子方向读取；不是另一个 OC 组件，不需要独立地址。箱体材质暂用示意。'},
{id:'nanite-transposer',key:'OC_TRANS',title:'蜂群硬盘转运器',p:[36,-7,58],role:'groups[1].nanites.transposer',type:'CELL TRANSPOSER',icon:'⇄',description:'ME-IO 装入 / 回收',sides:[['bankSide','硬盘箱方向',0],['loadSide','装入端口方向',3],['returnSide','回收端口方向',2]]},
{id:'load-io',key:'AE_IO',title:'ME-IO 装入端口',p:[30,-7,58],role:null,type:'ME IO PORT',icon:'▥',description:'由蜂群转运器访问',related:'nanite-transposer',note:'在蜂群硬盘转运器中设置装入端口方向；此端口无需独立 OC 组件地址。装入信号在装入红石模块中配置。'},
{id:'return-io',key:'AE_IO',title:'ME-IO 回收端口',p:[42,-7,58],role:null,type:'ME IO PORT',icon:'▥',description:'由蜂群转运器访问',related:'nanite-transposer',note:'在蜂群硬盘转运器中设置回收端口方向；此端口无需独立 OC 组件地址。回收信号在回收红石模块中配置。'},
{id:'load-redstone',key:'OC_RS',title:'蜂群装入红石',p:[30,-7,70],role:'groups[1].nanites.loadRedstone',type:'REDSTONE CONTROL',icon:'⚡',description:'装入端口信号',sides:[['loadOutputSide','装入红石输出方向',0]]},
{id:'return-redstone',key:'OC_RS',title:'蜂群回收红石',p:[42,-7,70],role:'groups[1].nanites.returnRedstone',type:'REDSTONE CONTROL',icon:'⚡',description:'回收端口信号',sides:[['returnOutputSide','回收红石输出方向',0]]}
];

window.BEC_PERIPHERALS.forEach(function(m){
var map={'load-io':['A','load-redstone','A · 装入 ME-IO'],'load-redstone':['A','load-io','A · 装入红石 I/O'],'return-io':['B','return-redstone','B · 回收 ME-IO'],'return-redstone':['B','return-io','B · 回收红石 I/O']};
var v=map[m.id];if(v){m.channel=v[0];m.pair=v[1];m.label=v[2];m.description=v[0]+' 通道 · '+(v[0]==='A'?'硬盘 → 蜂群网':'蜂群网 → 硬盘');}
});
</script><script>(function(){'use strict';
var FACE=[{n:[1,0,0],c:[[1,0,0],[1,1,0],[1,1,1],[1,0,1]]},{n:[-1,0,0],c:[[0,0,1],[0,1,1],[0,1,0],[0,0,0]]},{n:[0,1,0],c:[[0,1,1],[1,1,1],[1,1,0],[0,1,0]]},{n:[0,-1,0],c:[[0,0,0],[1,0,0],[1,0,1],[0,0,1]]},{n:[0,0,1],c:[[1,0,1],[1,1,1],[0,1,1],[0,0,1]]},{n:[0,0,-1],c:[[0,0,0],[0,1,0],[1,1,0],[1,0,0]]}];
var I=[1,0,0,0,1,0,0,0,1],RY=[-1,0,0,0,1,0,0,0,-1],RX=[1,0,0,0,0,-1,0,1,0],RXN=[1,0,0,0,0,1,0,-1,0],RY90=[0,0,1,0,1,0,-1,0,0],RY270=[0,0,-1,0,1,0,1,0,0];
function transform(r,v){return[r[0]*v[0]+r[1]*v[1]+r[2]*v[2],r[3]*v[0]+r[4]*v[1]+r[5]*v[2],r[6]*v[0]+r[7]*v[1]+r[8]*v[2]];}
function add(a,b){return[a[0]+b[0],a[1]+b[1],a[2]+b[2]];}function sub(a,b){return[a[0]-b[0],a[1]-b[1],a[2]-b[2]];}function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}function norm(v){var d=Math.sqrt(dot(v,v))||1;return v.map(function(n){return n/d;});}function cross(a,b){return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];}
function multiply(a,b){var o=new Float32Array(16);for(var c=0;c<4;c++)for(var r=0;r<4;r++)for(var k=0;k<4;k++)o[c*4+r]+=a[k*4+r]*b[c*4+k];return o;}
function modelMatrix(r,p){return new Float32Array([r[0],r[3],r[6],0,r[1],r[4],r[7],0,r[2],r[5],r[8],0,p[0],p[1],p[2],1]);}
function matPoint(m,p){return[m[0]*p[0]+m[4]*p[1]+m[8]*p[2]+m[12],m[1]*p[0]+m[5]*p[1]+m[9]*p[2]+m[13],m[2]*p[0]+m[6]*p[1]+m[10]*p[2]+m[14]];}
function buildMesh(data,key){var model=data.models[key],size=model.size,map=new Map(),faces=[],count=0;if(model.cube)return{key:key,size:size,blocks:1,faces:FACE.map(function(f,i){return{p:[0,0,0],n:f.n,c:f.c.map(function(v){return v.map(function(n,a){return n*size[a];});}),t:model.faceTextures[i],glass:false};})};
 model.rows.forEach(function(layer,z){layer.forEach(function(row,down){for(var x=0;x<row.length;x++){var ch=row[x];if(ch!==' '&&ch!=='-'&&ch!=='+'){var y=size[1]-1-down;map.set(x+','+y+','+z,ch);count++;}}});});
 map.forEach(function(ch,pos){var p=pos.split(',').map(Number),mat=model.materials[ch],tile=ch==='~'?data.textureTiles.BEC_CASING:data.materialTextures[mat];FACE.forEach(function(f,fi){var n=f.n;if(map.has((p[0]+n[0])+','+(p[1]+n[1])+','+(p[2]+n[2])))return;var t=ch==='~'&&fi===5?data.textureTiles[key]:tile;faces.push({p:p,n:n,c:f.c,t:t,glass:mat==='ElectromagneticWaveguide'});});});
 return{key:key,size:size,faces:faces,blocks:count};}
function cubeMesh(data){return{key:'marker',size:[3,3,3],faces:FACE.map(function(f,i){return{p:[0,0,0],n:f.n,c:f.c.map(function(v){return v.map(function(n){return n*3;});}),t:i===5?data.textureTiles.BEC_IO_NODE:data.textureTiles.BEC_CASING,glass:false};}),blocks:1};}
function makeModules(data){var a=[];function put(id,key,title,p,r,kind,role){var m={id:id,key:key,title:title,p:p,r:r||I,kind:kind,role:role,size:data.models[key].size};m.center=add(transform(m.r,m.size.map(function(v){return v/2;})),p);m.marker=add(transform(m.r,data.models[key].controller),p);a.push(m);return m;}
 put('assembler','BEC_ASSEMBLER','观测阵列 01',[0,0,0],I,'assembler',null);
 put('field','BEC_CONTAINMENT_FIELD','约束场 01',[78,7,-7],I,'field','groups[1].storage');
 put('generator','BEC_GENERATOR','纠缠器 01',[164,6,6],RY270,'generator','groups[1].generators[1]');
 put('gate','BEC_DIODE','麦克斯韦门 01',[61,10,10],I,'gate','groups[1].gate');
 var i=0;[12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x-3,4,-14],I,'node','nodes['+i+'].address');});
 [12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x+3,4,44],RY,'node','nodes['+i+'].address');});
 [12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x-3,45,4],RX,'node','nodes['+i+'].address');});
 [12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x-3,-14,26],RXN,'node','nodes['+i+'].address');});
 (window.BEC_PERIPHERALS||[]).forEach(function(d){var m=put(d.id,d.key,d.title,d.p,I,'peripheral',d.role);Object.keys(d).forEach(function(k){if(k!=='p')m[k]=d[k];});});
 return a;}
function Scene(canvas,data,onSelect,onRender){this.canvas=canvas;this.data=data;this.onSelect=onSelect;this.onRender=onRender;this.modules=makeModules(data);this.meshes={};var self=this;Object.keys(data.models).forEach(function(k){self.meshes[k]=buildMesh(data,k);});this.markerMesh=cubeMesh(data);this.camera={target:[78,8,27],yaw:-.85,pitch:.62,distance:250};this.selected='assembler';this.hovered=null;this.layer=49;this.showNodes=true;this.fullNodes=false;this.showPeripherals=true;this.isolate=false;this.onlyMissing=false;this.statuses={};this.visibleModules=[];this.pending=false;this.drawCount=0;
 var gl=null;try{gl=canvas.getContext('webgl',{alpha:false,antialias:true,preserveDrawingBuffer:true});}catch(e){}this.gl=gl;this.mode=gl?'WebGL':'Canvas 2D';if(gl)this.initGL();else this.ctx=canvas.getContext('2d');this.atlas=new Image();this.atlas.onload=function(){if(gl){gl.bindTexture(gl.TEXTURE_2D,self.texture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,self.atlas);}self.request();};this.atlas.src=data.atlas;this.bind();this.observer=new ResizeObserver(function(){self.request();});this.observer.observe(canvas);}
Scene.prototype.bind=function(){var self=this,drag=null;this.canvas.addEventListener('pointerdown',function(e){if(e.button!==0&&e.button!==1&&e.button!==2)return;drag={x:e.clientX,y:e.clientY,lastX:e.clientX,lastY:e.clientY,moved:false,pan:e.button!==0||e.shiftKey};self.canvas.setPointerCapture(e.pointerId);self.canvas.classList.add('dragging');});
 this.canvas.addEventListener('pointermove',function(e){if(drag){var dx=e.clientX-drag.lastX,dy=e.clientY-drag.lastY;if(Math.abs(e.clientX-drag.x)+Math.abs(e.clientY-drag.y)>4)drag.moved=true;if(drag.pan){var scale=self.camera.distance*.5/self.canvas.clientHeight;self.camera.target=add(self.camera.target,add(self.right.map(function(v){return-v*dx*scale;}),self.up.map(function(v){return v*dy*scale;})));}else{self.camera.yaw-=dx*.008;self.camera.pitch=Math.max(-1.3,Math.min(1.48,self.camera.pitch+dy*.008));}drag.lastX=e.clientX;drag.lastY=e.clientY;self.request();}else{var hit=self.pick(e.clientX,e.clientY);if(hit!==self.hovered){self.hovered=hit;self.canvas.style.cursor=hit?'pointer':'grab';self.request();}}});
 this.canvas.addEventListener('pointerup',function(e){if(drag&&!drag.moved&&e.button===0){var hit=self.pick(e.clientX,e.clientY);if(hit)self.onSelect(hit,true);}drag=null;self.canvas.classList.remove('dragging');});this.canvas.addEventListener('pointercancel',function(){drag=null;self.canvas.classList.remove('dragging');});this.canvas.addEventListener('contextmenu',function(e){e.preventDefault();});this.canvas.addEventListener('wheel',function(e){e.preventDefault();self.camera.distance=Math.max(18,Math.min(520,self.camera.distance*Math.exp(Math.max(-240,Math.min(240,(e.deltaMode===1?e.deltaY*32:e.deltaMode===2?e.deltaY*240:Math.abs(e.deltaY)<16?e.deltaY*32:e.deltaY)))*.002)));self.request();},{passive:false});};
Scene.prototype.request=function(){if(this.pending)return;this.pending=true;var self=this;requestAnimationFrame(function(){self.pending=false;self.draw();});};
Scene.prototype.cameraMatrices=function(){var c=this.camera,eye=add(c.target,[Math.sin(c.yaw)*Math.cos(c.pitch)*c.distance,Math.sin(c.pitch)*c.distance,Math.cos(c.yaw)*Math.cos(c.pitch)*c.distance]);this.eye=eye;var back=norm(sub(eye,c.target)),right=norm(cross([0,1,0],back)),up=cross(back,right);this.back=back;this.right=right;this.up=up;var view=new Float32Array([right[0],up[0],back[0],0,right[1],up[1],back[1],0,right[2],up[2],back[2],0,-dot(right,eye),-dot(up,eye),-dot(back,eye),1]);this.halfH=c.distance*.25;this.halfW=this.halfH*this.canvas.clientWidth/this.canvas.clientHeight;var l=-this.halfW,r=this.halfW,b=-this.halfH,t=this.halfH,n=.1,f=2000;var proj=new Float32Array([2/(r-l),0,0,0,0,2/(t-b),0,0,0,0,-2/(f-n),0,-(r+l)/(r-l),-(t+b)/(t-b),-(f+n)/(f-n),1]);this.vp=multiply(proj,view);};
Scene.prototype.project=function(p){var v=sub(p,this.camera.target);return{x:(dot(v,this.right)/this.halfW+1)*this.canvas.clientWidth/2,y:(1-dot(v,this.up)/this.halfH)*this.canvas.clientHeight/2,depth:dot(v,this.back)};};
Scene.prototype.meshFor=function(m){return m.kind==='node'&&!this.fullNodes&&!(this.isolate&&this.selected===m.id)?this.markerMesh:this.meshes[m.key];};
Scene.prototype.matrixFor=function(m){return this.meshFor(m)===this.markerMesh?modelMatrix(I,sub(m.marker,[1,1,1])):modelMatrix(m.r,m.p);};
Scene.prototype.list=function(){var self=this;return this.modules.filter(function(m){var values=self.runtimeValues||{},assigned=Number(values['n'+m.id.slice(5)+'.group']||1);if(m.kind==='node'&&values['n'+m.id.slice(5)+'.address']&&self.runtimeGroup&&assigned!==self.runtimeGroup)return false;return(!self.isolate||m.id===self.selected)&&(m.kind!=='peripheral'||self.showPeripherals||m.id===self.selected)&&(!self.onlyMissing||!self.statuses[m.id])&&(m.kind!=='node'||self.showNodes||m.id===self.selected);});};
Scene.prototype.draw=function(){var ratio=Math.min(window.devicePixelRatio||1,1.6),w=Math.max(1,Math.round(this.canvas.clientWidth*ratio)),h=Math.max(1,Math.round(this.canvas.clientHeight*ratio));if(this.canvas.width!==w||this.canvas.height!==h){this.canvas.width=w;this.canvas.height=h;}this.cameraMatrices();this.visibleModules=this.list();if(this.gl)this.drawGL();else this.drawCanvas(ratio);this.drawCount++;if(this.onRender)this.onRender(this);};
Scene.prototype.pick=function(clientX,clientY){if(!this.right)return null;var rect=this.canvas.getBoundingClientRect(),x=((clientX-rect.left)/rect.width*2-1)*this.halfW,y=(1-(clientY-rect.top)/rect.height*2)*this.halfH,origin=add(this.eye,add(this.right.map(function(v){return v*x;}),this.up.map(function(v){return v*y;}))),direction=this.back.map(function(v){return-v;}),best=Infinity,hit=null,self=this;
 this.visibleModules.forEach(function(m){var matrix=self.matrixFor(m),position=[matrix[12],matrix[13],matrix[14]],delta=sub(origin,position),r=[matrix[0],matrix[4],matrix[8],matrix[1],matrix[5],matrix[9],matrix[2],matrix[6],matrix[10]],inv=[r[0],r[3],r[6],r[1],r[4],r[7],r[2],r[5],r[8]],o=transform(inv,delta),d=transform(inv,direction),size=self.meshFor(m).size,near=-Infinity,far=Infinity;
 for(var a=0;a<3;a++){if(Math.abs(d[a])<1e-7){if(o[a]<0||o[a]>size[a])return;}else{var t0=-o[a]/d[a],t1=(size[a]-o[a])/d[a];near=Math.max(near,Math.min(t0,t1));far=Math.min(far,Math.max(t0,t1));}}var distance=Math.max(0,near);if(near<=far&&far>=0&&distance<best&&origin[1]+direction[1]*distance<=self.layer+1){best=distance;hit=m.id;}});return hit;};
Scene.prototype.focus=function(id,isolated){var m=this.modules.find(function(v){return v.id===id;});if(!m)return;this.selected=id;if(isolated){this.isolate=true;this.camera.target=m.center.slice();this.camera.distance=Math.max.apply(null,m.size)*2.15;}this.request();};
Scene.prototype.reset=function(){this.isolate=false;this.camera={target:[78,8,27],yaw:-.85,pitch:.62,distance:250};this.request();};
Scene.prototype.initGL=function(){var g=this.gl,self=this;function shader(type,source){var s=g.createShader(type);g.shaderSource(s,source);g.compileShader(s);if(!g.getShaderParameter(s,g.COMPILE_STATUS))throw new Error(g.getShaderInfoLog(s));return s;}
 var vs='attribute vec3 aPosition;attribute vec3 aNormal;attribute vec2 aUV;uniform mat4 uVP;uniform mat4 uModel;varying vec2 vUV;varying vec3 vNormal;varying float vY;void main(){vec4 p=uModel*vec4(aPosition,1.0);vY=p.y;vUV=aUV;vNormal=mat3(uModel)*aNormal;gl_Position=uVP*p;}';
 var fs='precision mediump float;uniform sampler2D uAtlas;uniform float uSlice;uniform float uSelected;uniform float uSolid;uniform vec4 uColor;varying vec2 vUV;varying vec3 vNormal;varying float vY;void main(){if(uSolid>0.5){gl_FragColor=uColor;return;}if(vY>uSlice)discard;vec4 c=texture2D(uAtlas,vUV);if(c.a<0.05)discard;float light=.6+.4*max(0.0,dot(normalize(vNormal),normalize(vec3(-.4,.85,.5))));vec3 rgb=c.rgb*light;rgb=mix(rgb,vec3(.08,.72,.87),uSelected*.26);gl_FragColor=vec4(rgb,c.a);}';
 this.program=g.createProgram();g.attachShader(this.program,shader(g.VERTEX_SHADER,vs));g.attachShader(this.program,shader(g.FRAGMENT_SHADER,fs));g.linkProgram(this.program);if(!g.getProgramParameter(this.program,g.LINK_STATUS))throw new Error(g.getProgramInfoLog(this.program));g.useProgram(this.program);this.loc={};['aPosition','aNormal','aUV'].forEach(function(n){self.loc[n]=g.getAttribLocation(self.program,n);});['uVP','uModel','uSlice','uSelected','uSolid','uColor'].forEach(function(n){self.loc[n]=g.getUniformLocation(self.program,n);});this.texture=g.createTexture();g.bindTexture(g.TEXTURE_2D,this.texture);g.texImage2D(g.TEXTURE_2D,0,g.RGBA,1,1,0,g.RGBA,g.UNSIGNED_BYTE,new Uint8Array([110,120,130,255]));g.texParameteri(g.TEXTURE_2D,g.TEXTURE_MIN_FILTER,g.NEAREST);g.texParameteri(g.TEXTURE_2D,g.TEXTURE_MAG_FILTER,g.NEAREST);g.texParameteri(g.TEXTURE_2D,g.TEXTURE_WRAP_S,g.CLAMP_TO_EDGE);g.texParameteri(g.TEXTURE_2D,g.TEXTURE_WRAP_T,g.CLAMP_TO_EDGE);
 Object.keys(this.meshes).forEach(function(k){self.upload(self.meshes[k]);});this.upload(this.markerMesh);
 var lines=[];for(var x=-25;x<=195;x+=5)lines.push(x,-16,-45,0,1,0,0,0,x,-16,75,0,1,0,0,0);for(var z=-45;z<=75;z+=5)lines.push(-25,-16,z,0,1,0,0,0,195,-16,z,0,1,0,0,0);this.grid=this.buffer(lines);
};
Scene.prototype.buffer=function(values){var g=this.gl,b=g.createBuffer();g.bindBuffer(g.ARRAY_BUFFER,b);g.bufferData(g.ARRAY_BUFFER,new Float32Array(values),g.STATIC_DRAW);return{buffer:b,count:values.length/8};};
Scene.prototype.upload=function(mesh){var opaque=[],glass=[];mesh.faces.forEach(function(f){var a=f.glass?glass:opaque,u=(f.t%8)*16/128,v=Math.floor(f.t/8)*16/128,uv=[[u+.001,v+.124],[u+.001,v+.001],[u+.124,v+.001],[u+.124,v+.124]];[0,1,2,0,2,3].forEach(function(i){a.push(f.p[0]+f.c[i][0],f.p[1]+f.c[i][1],f.p[2]+f.c[i][2],f.n[0],f.n[1],f.n[2],uv[i][0],uv[i][1]);});});mesh.opaque=this.buffer(opaque);mesh.glass=this.buffer(glass);};
Scene.prototype.drawBuffer=function(b,mode){if(!b.count)return;var g=this.gl;g.bindBuffer(g.ARRAY_BUFFER,b.buffer);g.enableVertexAttribArray(this.loc.aPosition);g.vertexAttribPointer(this.loc.aPosition,3,g.FLOAT,false,32,0);g.enableVertexAttribArray(this.loc.aNormal);g.vertexAttribPointer(this.loc.aNormal,3,g.FLOAT,false,32,12);g.enableVertexAttribArray(this.loc.aUV);g.vertexAttribPointer(this.loc.aUV,2,g.FLOAT,false,32,24);g.drawArrays(mode||g.TRIANGLES,0,b.count);};
Scene.prototype.drawGL=function(){var g=this.gl,self=this;g.viewport(0,0,this.canvas.width,this.canvas.height);g.clearColor(.94,.954,.969,1);g.clear(g.COLOR_BUFFER_BIT|g.DEPTH_BUFFER_BIT);g.useProgram(this.program);g.enable(g.DEPTH_TEST);g.enable(g.CULL_FACE);g.enable(g.BLEND);g.blendFunc(g.SRC_ALPHA,g.ONE_MINUS_SRC_ALPHA);g.uniformMatrix4fv(this.loc.uVP,false,this.vp);g.uniform1f(this.loc.uSolid,1);g.uniform4f(this.loc.uColor,.76,.8,.85,.45);g.uniformMatrix4fv(this.loc.uModel,false,modelMatrix(I,[0,0,0]));this.drawBuffer(this.grid,g.LINES);g.uniform1f(this.loc.uSolid,0);g.uniform1f(this.loc.uSlice,this.layer+1);g.bindTexture(g.TEXTURE_2D,this.texture);
 this.visibleModules.forEach(function(m){g.uniformMatrix4fv(self.loc.uModel,false,self.matrixFor(m));g.uniform1f(self.loc.uSelected,(m.id===self.selected||m.pair===self.selected)?1:m.id===self.hovered?.45:(self.liveStates&&self.liveStates[m.id]==='active'?.7:0));self.drawBuffer(self.meshFor(m).opaque);});g.depthMask(false);this.visibleModules.slice().sort(function(a,b){return dot(sub(a.center,self.eye),self.back)-dot(sub(b.center,self.eye),self.back);}).forEach(function(m){g.uniformMatrix4fv(self.loc.uModel,false,self.matrixFor(m));g.uniform1f(self.loc.uSelected,(m.id===self.selected||m.pair===self.selected)?1:0);self.drawBuffer(self.meshFor(m).glass);});g.depthMask(true);};
Scene.prototype.drawCanvas=function(ratio){var ctx=this.ctx,self=this,w=this.canvas.clientWidth,h=this.canvas.clientHeight;ctx.setTransform(ratio,0,0,ratio,0,0);ctx.fillStyle='#f0f3f7';ctx.fillRect(0,0,w,h);ctx.strokeStyle='#d9e0e8';ctx.lineWidth=.6;for(var x=-25;x<=195;x+=5){var a=this.project([x,-16,-45]),b=this.project([x,-16,75]);ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke();}for(var z=-45;z<=75;z+=5){var c=this.project([-25,-16,z]),d=this.project([195,-16,z]);ctx.beginPath();ctx.moveTo(c.x,c.y);ctx.lineTo(d.x,d.y);ctx.stroke();}var faces=[];
 this.visibleModules.forEach(function(m){var matrix=self.matrixFor(m),mesh=self.meshFor(m);mesh.faces.forEach(function(f){var normal=matPoint(matrix,f.n).map(function(v,i){return v-matrix[12+i];});if(dot(normal,self.back)<=.03)return;var points=f.c.map(function(c){return matPoint(matrix,add(f.p,c));});if(points.every(function(p){return p[1]>self.layer+1;}))return;var screen=points.map(function(p){return self.project(p);});var depth=screen.reduce(function(sum,p){return sum+p.depth;},0)/4;faces.push({p:screen,t:f.t,depth:depth,selected:m.id===self.selected||m.pair===self.selected,n:normal});});});faces.sort(function(a,b){return a.depth-b.depth;});
 if(!this.atlas.complete)return;ctx.imageSmoothingEnabled=false;
 faces.forEach(function(f){var p=f.p,dx=p[3].x-p[0].x,dy=p[3].y-p[0].y,ex=p[1].x-p[0].x,ey=p[1].y-p[0].y;ctx.setTransform(dx/16*ratio,dy/16*ratio,-ex/16*ratio,-ey/16*ratio,p[1].x*ratio,p[1].y*ratio);ctx.drawImage(self.atlas,(f.t%8)*16,Math.floor(f.t/8)*16,16,16,0,0,16,16);var light=.6+.4*Math.max(0,dot(norm(f.n),norm([-.4,.85,.5])));ctx.fillStyle='rgba(0,0,0,'+(1-light)+')';ctx.fillRect(0,0,16,16);if(f.selected){ctx.fillStyle='rgba(20,178,205,.13)';ctx.fillRect(0,0,16,16);}});ctx.setTransform(ratio,0,0,ratio,0,0);
};
window.BECScene=Scene;
})();
</script><script>(function(){'use strict';
var $=function(id){return document.getElementById(id);},KEY='bec-structure-studio.draft.v1',draft={version:1,modules:{}},timer,toastTimer,scene,expanded=true;
var uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];});}
function toast(s){$('toast').textContent=s;$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(function(){$('toast').hidden=true;},2600);}
function safeDraft(value){if(!value||value.version!==1||!value.modules||typeof value.modules!=='object')throw Error('不是此配置台的草稿文件');var out={version:1,modules:{}};['field','generator','gate'].concat(Array.from({length:15},function(_,i){return 'generator-'+(i+2);})).concat((window.BEC_PERIPHERALS||[]).map(function(m){return m.id;})).concat(Array.from({length:16},function(_,i){return'node-'+(i+1);})).forEach(function(id){var item=value.modules[id];if(!item||typeof item!=='object')return;var v={};['address','redstone','gate'].forEach(function(k){if(typeof item[k]==='string')v[k]=item[k].slice(0,160);});if(Number.isInteger(item.group)&&item.group>=1&&item.group<=16)v.group=item.group;['pauseSide','mainSide','subSide','bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide'].forEach(function(k){if(Number.isInteger(item[k])&&item[k]>=0&&item[k]<=5)v[k]=item[k];});out.modules[id]=v;});return out;}
try{var stored=localStorage.getItem(KEY);if(stored)draft=safeDraft(JSON.parse(stored));}catch(e){/* Local draft remains usable in memory when storage is unavailable. */}
function data(m){return draft.modules[m.id]||{};}
function sideFields(m){return m.kind==='node'?[['pauseSide','暂停信号方向',1]]:(m.sides||[]);}
function sideIssues(m){var v=data(m),keys=m.id==='fluid-transposer'?['mainSide','subSide']:m.id==='nanite-transposer'?['bankSide','loadSide','returnSide']:[];var values=keys.map(function(k){var f=sideFields(m).find(function(f){return f[0]===k;});return v[k]==null?f[2]:v[k];});return new Set(values).size!==values.length;}
function complete(m){var v=data(m);return !!m.role&&uuid.test(v.address||'')&&(m.kind!=='node'||uuid.test(v.redstone||''))&&!sideIssues(m);}
function save(){clearTimeout(timer);if(window.BEC_BINDING_DIRTY)window.BEC_BINDING_DIRTY(draft);$('save-status').innerHTML='<i></i>正在保存草稿…';timer=setTimeout(flush,300);}
function flush(){clearTimeout(timer);draft.updatedAt=new Date().toISOString();try{localStorage.setItem(KEY,JSON.stringify(draft));$('save-status').innerHTML='<i></i>草稿已自动保存';}catch(e){$('save-status').textContent='仅保留在本页 · 请导出草稿';}refreshStatus();if(window.BEC_BINDING_DIRTY)window.BEC_BINDING_DIRTY(draft);}
function refreshStatus(){var n=0;scene.modules.forEach(function(m){scene.statuses[m.id]=complete(m);if(complete(m))n++;});$('binding-count').textContent=n+' / '+scene.modules.filter(function(m){return !!m.role;}).length;renderTree();scene.request();}
function row(m){return '<button class="tree-row '+(m.id===scene.selected?'active':'')+'" data-module="'+m.id+'"><span class="module-icon">'+(m.icon||({assembler:'▤',field:'◎',generator:'◈',gate:'◇',node:'▣'})[m.kind])+'</span><span><span class="tree-title">'+esc(m.title)+'</span><span class="tree-role">'+(m.description||({assembler:'主体结构 · 16 个接入口',field:'凝聚物库存',generator:'凝聚物生成',gate:'阶段切换',node:'传送与暂停控制'})[m.kind])+'</span></span><i class="state-dot '+(complete(m)?'filled':'')+'"></i></button>';}
function renderTree(){var q=$('tree-search').value.trim().toLowerCase(),matches=function(m){return(m.title+' '+(data(m).address||'')).toLowerCase().indexOf(q)>=0;};var main=scene.modules.filter(function(m){return m.kind!=='node'&&m.kind!=='peripheral'&&matches(m);}),nodes=scene.modules.filter(function(m){return m.kind==='node'&&matches(m);});var extras=scene.modules.filter(function(m){return m.kind==='peripheral'&&matches(m);});$('structure-tree').innerHTML=main.map(row).join('')+(extras.length?'<div class="node-group-button peripheral-heading">AE / OC 外设 <span class="count">'+extras.length+'</span></div>'+extras.map(row).join(''):'')+(nodes.length?'<button class="node-group-button" id="node-toggle"><span>'+(expanded?'⌄':'›')+'</span> 传送节点 <span class="count">'+nodes.length+'</span></button><div class="node-rows" '+(!expanded&&!q?'hidden':'')+'>'+nodes.map(row).join('')+'</div>':'');$('structure-tree').querySelectorAll('[data-module]').forEach(function(b){b.onclick=function(){select(b.dataset.module);};});var toggle=$('node-toggle');if(toggle)toggle.onclick=function(){expanded=!expanded;renderTree();};}
function addressField(label,key,value){return '<div class="field"><label for="field-'+key+'">'+label+'</label><input id="field-'+key+'" data-field="'+key+'" value="'+esc(value||'')+'" placeholder="粘贴 OC 组件的完整 UUID" autocomplete="off" spellcheck="false" maxlength="160"><button type="button" class="clear-address" data-clear="'+key+'">清空</button><small class="hint" data-hint="'+key+'">支持 Ctrl + V，可先填一部分，稍后继续。</small></div>';}
function directionFields(m,v){return sideFields(m).map(function(f){return '<div class="field"><label>'+esc(f[1])+'</label><div class="direction-grid">'+[['下',0],['上',1],['南',3],['北',2],['东',5],['西',4]].map(function(d){return '<button data-side="'+d[1]+'" data-side-key="'+f[0]+'" class="'+((v[f[0]]==null?f[2]:v[f[0]])===d[1]?'active':'')+'">'+d[0]+'</button>';}).join('')+'</div></div>';}).join('');}
function ioGuide(m){
 if(!m.channel&&m.id!=='nanite-transposer')return '';
 var channels=m.channel?[m.channel]:['A','B'],v=data(scene.modules.find(function(x){return x.id==='nanite-transposer';})),names={0:'下',1:'上',2:'北',3:'南',4:'西',5:'东'};
 return '<section class="io-guide"><div class="properties-title">ME-IO 配置与控制对应</div>'+channels.map(function(ch){var load=ch==='A',io=load?'load-io':'return-io',rs=load?'load-redstone':'return-redstone',rsModule=scene.modules.find(function(x){return x.id===rs;}),rv=data(rsModule),side=load?'loadSide':'returnSide',out=load?'loadOutputSide':'returnOutputSide',sv=v[side]==null?(load?3:2):v[side],ov=rv[out]==null?0:rv[out];
 return '<article class="io-channel channel-'+ch+'"><strong><i>'+ch+'</i> '+(load?'装入通道':'回收通道')+'</strong><div class="io-flow">'+(load?'存储盘 → 蜂群收容子网':'蜂群收容子网 → 存储盘')+'</div><div class="io-pair-buttons"><button data-jump="'+rs+'">'+ch+' · '+(load?'装入':'回收')+'红石 I/O</button><span>↓ 红石控制</span><button data-jump="'+io+'">'+ch+' · '+(load?'装入':'回收')+' ME-IO</button></div><dl><dt>传输方向</dt><dd>'+(load?'存储盘 → 网络':'网络 → 存储盘')+'</dd><dt>完成后移盘</dt><dd>'+(load?'清空后移出（工序完成后移出）':'工序完成后移出；不要选等待装满')+'</dd><dt>红石模式</dt><dd>有红石信号时工作</dd><dt>升级卡</dt><dd>1 张红石卡、2 张超光速卡</dd></dl><div class="io-binding-readout">转运器连接此端口：'+names[sv]+' '+sv+'<br>对应红石 I/O 输出面：'+names[ov]+' '+ov+'<br>红石地址：'+(uuid.test(rv.address||'')?'格式完整 · 尚未检测设备':'未填完整')+'</div><button class="related-button" data-jump="'+(m.id===rs?io:rs)+'">配置对应的'+(m.id===rs?' ME-IO 端口':'红石 I/O')+' →</button></article>';
 }).join('')+'<p class="io-wiring-note">两端只连接蜂群收容子网，由该子网的存储总线访问蜂群仓。不要把它接到主网或备用大库。<br><br>转运器方向以转运器为准；红石输出方向以各自红石 I/O 为准，选择实际通向对应 ME-IO 的那一面。示意模型的位置不代表真实接线面。</p><button class="related-button" data-jump="nanite-transposer">配置硬盘箱 / 两端连接方向 →</button></section>';
}
function refreshGuide(m){var old=$('inspector-content').querySelector('.io-guide');if(old)old.outerHTML=ioGuide(m);$('inspector-content').querySelectorAll('[data-jump]').forEach(function(b){b.onclick=function(){select(b.dataset.jump);};});}
function renderInspector(){var m=scene.modules.find(function(v){return v.id===scene.selected;}),v=data(m);$('inspector-content').innerHTML='<div class="module-summary"><span class="summary-icon">'+esc(m.icon||({assembler:'▤',field:'◎',generator:'◈',gate:'◇',node:'▣'})[m.kind])+'</span><h3>'+esc(m.title)+'</h3><p>'+esc(m.type||({assembler:'OBSERVATION ARRAY',field:'CONTAINMENT FIELD',generator:'ENTANGLEMENT GENERATOR',gate:'MAXWELL GATE',node:'TRANSFER NODE'})[m.kind])+'</p><span id="module-state" class="module-state">'+(m.role?'未填写':m.kind==='peripheral'?'转运器关联设备':'主体结构')+'</span></div>'+(m.role?'':ioGuide(m))+'<div class="properties"><div class="properties-title">'+(m.role?'地址绑定':'接入方式')+'</div>'+(m.role?addressField('设备组件地址','address',v.address)+(m.kind==='node'?addressField('暂停控制 · 红石组件','redstone',v.redstone)+addressField('独立韦门 · 可空，使用组韦门','gate',v.gate):'')+directionFields(m,v)+(m.kind==='node'?'<div class="field"><label for="field-group">所属设备组</label><select id="field-group">'+Array.from({length:16},function(_,i){return '<option value="'+(i+1)+'" '+((v.group||1)===i+1?'selected':'')+'>设备组 '+String(i+1).padStart(2,'0')+'</option>';}).join('')+'</select></div>':'')+'<div id="validation-state" class="validation-state">草稿允许留空，填写时自动保存。</div>':'<p class="section-note">'+esc(m.note||'观测阵列提供 16 个传送节点接入口。V2 通过节点地址配置，主体没有独立地址字段。')+'</p><button id="related-node" class="related-button">'+(m.related?'配置蜂群硬盘转运器':'配置传送节点 01')+' →</button>')+'</div>'+(m.role?ioGuide(m):'')+'<div class="module-metadata"><div class="properties-title">'+(m.kind==='peripheral'?'外设信息':'模型信息')+'</div><div class="metadata-row"><span>显示方式</span><b>'+(m.kind==='peripheral'?'放大方块示意':'官方主体结构')+'</b></div><div class="metadata-row"><span>结构方块</span><b>'+scene.meshes[m.key].blocks.toLocaleString()+'</b></div><div class="metadata-row"><span>转运方案</span><b>ME-IO</b></div>'+(m.role?'<div class="metadata-row role"><span>V2 字段</span><code>'+esc(m.role)+'</code></div>':'')+'</div><p class="section-note">'+(m.kind==='peripheral'?'外设位置为便于点选的配置示意；接线方向以游戏内实际设备为准。':'模型间距和节点位置用于界面展示。实际搭建与端口方向以游戏内机器为准。')+'</p>';
$('inspector-content').querySelectorAll('[data-clear]').forEach(function(button){button.onclick=function(){var input=$('field-'+button.dataset.clear);input.value='';input.focus();input.dispatchEvent(new Event('input',{bubbles:true}));};});$('inspector-content').querySelectorAll('[data-field]').forEach(function(input){input.oninput=function(){var item=draft.modules[m.id]||(draft.modules[m.id]={});item[input.dataset.field]=input.value;validateInputs(m);refreshGuide(m);save();};});$('inspector-content').querySelectorAll('[data-side]').forEach(function(b){b.onclick=function(){var item=draft.modules[m.id]||(draft.modules[m.id]={}),key=b.dataset.sideKey;item[key]=Number(b.dataset.side);$('inspector-content').querySelectorAll('[data-side-key="'+key+'"]').forEach(function(x){x.classList.toggle('active',x===b);});validateInputs(m);refreshGuide(m);save();};});var group=$('field-group');if(group)group.onchange=function(){var item=draft.modules[m.id]||(draft.modules[m.id]={});item.group=Number(group.value);save();};var related=$('related-node');if(related)related.onclick=function(){select(m.related||'node-1');};$('inspector-content').querySelectorAll('[data-jump]').forEach(function(b){b.onclick=function(){select(b.dataset.jump);};});validateInputs(m);}

function validateInputs(m){if(!m.role)return;var v=data(m),has=false;['address','redstone'].forEach(function(key){var input=$('field-'+key);if(!input)return;var value=v[key]||'',bad=!!value&&!uuid.test(value),hint=$('inspector-content').querySelector('[data-hint="'+key+'"]');has=has||!!value;input.classList.toggle('invalid',bad);hint.classList.toggle('error',bad);hint.textContent=bad?'已保留草稿；完整地址应为 8-4-4-4-12 格式。':value?'地址格式正确 · 点击顶部「应用绑定」检测连接':'支持 Ctrl + V，可先填一部分，稍后继续。';});var done=complete(m);$('module-state').className='module-state'+(done?' filled':'');$('module-state').textContent=done?'地址完整':has?'草稿':'未填写';$('validation-state').className='validation-state'+(done?' valid':'');$('validation-state').textContent=sideIssues(m)?'方向有冲突：同一转运器的不同容器必须选择不同方向。草稿仍已保留。':done?'✓ 格式完整；请点击顶部「应用绑定」，由 OC 校验设备连接。':'草稿允许留空，填写时自动保存。';}
function select(id){scene.focus(id,scene.isolate);renderTree();renderInspector();document.querySelector('.inspector').scrollTop=0;$('status-selection').textContent=scene.modules.find(function(m){return m.id===id;}).title;$('view-title').textContent=scene.isolate?'单模块视图':'整体结构';}
function signalLinks(s){var svg=$('signal-links'),w=s.canvas.clientWidth,h=s.canvas.clientHeight;svg.setAttribute('viewBox','0 0 '+w+' '+h);var html='<defs><marker id="arrow-A" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6" fill="#2e77ee"/></marker><marker id="arrow-B" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6" fill="#9462d6"/></marker></defs>';if($('show-labels').checked)[['A','load-redstone','load-io','#2e77ee'],['B','return-redstone','return-io','#9462d6']].forEach(function(pair){var a=s.visibleModules.find(function(m){return m.id===pair[1];}),b=s.visibleModules.find(function(m){return m.id===pair[2];});if(!a||!b||s.layer<Math.max(a.center[1],b.center[1])-1)return;var p=s.project(a.center),q=s.project(b.center),dx=q.x-p.x,dy=q.y-p.y,n=Math.sqrt(dx*dx+dy*dy)||1,cut=Math.min(12,n*.25);html+='<path d="M'+(p.x+dx/n*cut)+','+(p.y+dy/n*cut)+' L'+(q.x-dx/n*cut)+','+(q.y-dy/n*cut)+'" stroke="'+pair[3]+'" stroke-width="2.5" stroke-dasharray="5 4" marker-end="url(#arrow-'+pair[0]+')" fill="none"/>';});svg.innerHTML=html;}
function labels(s){signalLinks(s);var show=$('show-labels').checked,visible=s.visibleModules;var html='';if(show)visible.forEach(function(m){if(m.kind==='node'&&m.id!==s.selected&&['node-1','node-5','node-9','node-13'].indexOf(m.id)<0)return;if(m.kind==='peripheral'&&!m.channel&&m.id!==s.selected&&['main-me','fluid-transposer','nanite-transposer'].indexOf(m.id)<0)return;var p=s.project(m.kind==='node'?m.marker:[m.center[0],m.p[1]+m.size[1]+4,m.center[2]]);if(p.x<0||p.y<0||p.x>s.canvas.clientWidth||p.y>s.canvas.clientHeight)return;html+='<button data-label="'+m.id+'" class="device-label '+(m.kind==='node'?'node ':'')+(m.id===s.selected||m.pair===s.selected?'selected ':'')+(m.channel?'channel-'+m.channel:'')+'" style="left:'+p.x.toFixed(1)+'px;top:'+p.y.toFixed(1)+'px"><i></i>'+esc(m.label||m.title)+'</button>';});$('labels').innerHTML=html;$('labels').querySelectorAll('[data-label]').forEach(function(b){b.onclick=function(){select(b.dataset.label);};});$('status-module-count').textContent=visible.length;$('renderer-badge').textContent=s.mode+' · '+(s.fullNodes?'完整节点':'节点标记');var origin=[35,39],vectors=[[1,0,0,'X','#d66c60'],[0,1,0,'Y','#59a58a'],[0,0,1,'Z','#6b91d1']];$('axes').innerHTML=vectors.map(function(v){var x=origin[0]+(v[0]*s.right[0]+v[1]*s.right[1]+v[2]*s.right[2])*23,y=origin[1]-(v[0]*s.up[0]+v[1]*s.up[1]+v[2]*s.up[2])*23;return'<line x1="35" y1="39" x2="'+x+'" y2="'+y+'" stroke="'+v[4]+'" stroke-width="2"/><text x="'+(x+4)+'" y="'+(y+3)+'" fill="'+v[4]+'" font-size="10">'+v[3]+'</text>';}).join('');}
scene=new BECScene($('scene'),BEC_DATA,select,labels);refreshStatus();renderInspector();
$('tree-search').oninput=renderTree;
function mode(isolate){scene.isolate=isolate;if(isolate)scene.focus(scene.selected,true);else scene.reset();$('whole-button').classList.toggle('active',!isolate);$('isolate-button').classList.toggle('active',isolate);$('view-title').textContent=isolate?'单模块视图':'整体结构';}
$('whole-button').onclick=function(){mode(false);};$('isolate-button').onclick=function(){mode(true);};$('reset-button').onclick=function(){mode(false);setLayer(49);toast('已恢复默认视角');};$('fit-button').onclick=function(){if(scene.isolate)scene.focus(scene.selected,true);else scene.reset();};$('zoom-in').onclick=function(){scene.camera.distance=Math.max(18,scene.camera.distance*.82);scene.request();};$('zoom-out').onclick=function(){scene.camera.distance=Math.min(520,scene.camera.distance/ .82);scene.request();};
document.querySelectorAll('[data-view]').forEach(function(b){b.onclick=function(){document.querySelectorAll('[data-view]').forEach(function(x){x.classList.toggle('active',x===b);});var view=b.dataset.view;scene.camera.yaw=view==='front'?Math.PI:view==='top'?-Math.PI/2:-.85;scene.camera.pitch=view==='top'?1.48:view==='front'?0:.62;scene.request();};});
function setLayer(n){n=Math.max(-15,Math.min(49,Number(n)));scene.layer=n;$('layer-slider').value=n;$('layer-value').textContent=n===49?'全部层':'Y ≤ '+n;$('all-layers').classList.toggle('active',n===49);scene.request();}$('layer-slider').oninput=function(){setLayer(this.value);};$('layer-down').onclick=function(){setLayer(scene.layer-1);};$('layer-up').onclick=function(){setLayer(scene.layer+1);};$('all-layers').onclick=function(){setLayer(49);};
[['show-peripherals','showPeripherals'],['show-nodes','showNodes'],['full-nodes','fullNodes'],['only-missing','onlyMissing']].forEach(function(pair){$(pair[0]).onchange=function(){scene[pair[1]]=this.checked;scene.request();};});$('show-labels').onchange=function(){scene.request();};$('dismiss-callout').onclick=function(){$('model-callout').hidden=true;};
$('source-button').onclick=function(){if($('sources-dialog').showModal)$('sources-dialog').showModal();else $('sources-dialog').setAttribute('open','');};$('sources-close').onclick=function(){$('sources-dialog').close();};
$('export-btn').onclick=function(){flush();var a=document.createElement('a'),url=URL.createObjectURL(new Blob([JSON.stringify(draft,null,2)],{type:'application/json'}));a.href=url;a.download='bec-structure-draft.json';a.click();setTimeout(function(){URL.revokeObjectURL(url);},3000);toast('已导出浏览器草稿，尚未写入 OC');};$('import-btn').onclick=function(){$('import-file').click();};$('import-file').onchange=function(){var file=this.files[0];if(!file)return;if(file.size>131072){toast('草稿文件超过 128 KiB');return;}var reader=new FileReader();reader.onload=function(){try{draft=safeDraft(JSON.parse(reader.result));flush();renderInspector();toast('已导入并保存草稿');}catch(e){toast('导入失败：'+e.message);}};reader.readAsText(file);this.value='';};
window.addEventListener('pagehide',flush);document.addEventListener('keydown',function(e){if(e.key==='/'&&!/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)){e.preventDefault();$('tree-search').focus();}});
window.BEC_APP={scene:scene,select:select,getDraft:function(){return JSON.parse(JSON.stringify(draft));},flush:flush,setLayer:setLayer,importDraft:function(v){draft=safeDraft(v);flush();renderInspector();}};
})();
</script><script>// DOM dropdowns render in the same offscreen texture; native popup windows do not.
(function(){'use strict';
var open=null;
function close(){if(!open)return;open.menu.remove();open.button.setAttribute('aria-expanded','false');open=null;}
function enhance(select){
 if(select.dataset.ochdSelect)return;select.dataset.ochdSelect='1';select.classList.add('ochd-native-select');select.tabIndex=-1;
 var button=document.createElement('button');button.type='button';button.className='ochd-select';button.setAttribute('role','combobox');button.setAttribute('aria-haspopup','listbox');button.setAttribute('aria-expanded','false');
 var label=select.closest('label')||document.querySelector('label[for="'+select.id+'"]');button.setAttribute('aria-label',label?label.textContent.trim():'选择配置');select.parentNode.insertBefore(button,select.nextSibling);
 function refresh(){var option=select.options[select.selectedIndex],text=option?option.textContent:'请选择';if(button.textContent!==text)button.textContent=text;button.disabled=select.disabled;}
 select._ochdRefresh=refresh;select.addEventListener('change',refresh);refresh();
 function show(){close();var menu=document.createElement('div');menu.className='ochd-select-menu';menu.setAttribute('role','listbox');var chosen=Math.max(0,select.selectedIndex);
  function highlight(index){chosen=Math.max(0,Math.min(select.options.length-1,index));Array.from(menu.children).forEach(function(row,i){row.classList.toggle('highlight',i===chosen);});if(menu.children[chosen])menu.children[chosen].scrollIntoView({block:'nearest'});}
  function choose(index){if(select.options[index].disabled)return;select.selectedIndex=index;refresh();close();button.focus();select.dispatchEvent(new Event('change',{bubbles:true}));}
  Array.from(select.options).forEach(function(option,index){var row=document.createElement('button');row.type='button';row.className='ochd-select-option';row.textContent=option.textContent;row.setAttribute('role','option');row.setAttribute('aria-selected',String(index===select.selectedIndex));row.disabled=option.disabled;row.onclick=function(){choose(index);};menu.appendChild(row);});
  document.body.appendChild(menu);var r=button.getBoundingClientRect(),height=Math.min(230,menu.scrollHeight);menu.style.left=Math.min(innerWidth-r.width-8,r.left)+'px';menu.style.width=r.width+'px';menu.style.top=(r.bottom+height>innerHeight-8?Math.max(8,r.top-height-4):r.bottom+4)+'px';
  button.setAttribute('aria-expanded','true');open={menu:menu,button:button,select:select,highlight:highlight,choose:choose,index:function(){return chosen;}};highlight(chosen);
 }
 button.onclick=function(){if(open&&open.button===button)close();else show();};
 button.onkeydown=function(e){if(e.key==='Escape'){close();return;}if(e.key==='Tab'){close();return;}if(['ArrowDown','ArrowUp','Home','End','Enter',' '].indexOf(e.key)<0)return;e.preventDefault();var wasOpen=open&&open.button===button;if(!wasOpen)show();if(e.key==='ArrowDown')open.highlight(open.index()+1);else if(e.key==='ArrowUp')open.highlight(open.index()-1);else if(e.key==='Home')open.highlight(0);else if(e.key==='End')open.highlight(select.options.length-1);else if(wasOpen)open.choose(open.index());};
}
function refresh(){if(open&&!open.select.isConnected)close();document.querySelectorAll('select').forEach(function(select){enhance(select);select._ochdRefresh();});}
document.addEventListener('pointerdown',function(e){if(open&&!open.menu.contains(e.target)&&e.target!==open.button)close();});
document.addEventListener('scroll',function(e){if(open&&!open.menu.contains(e.target))close();},true);window.addEventListener('resize',close);
new MutationObserver(refresh).observe(document.body,{childList:true,subtree:true});window.BEC_REFRESH_SELECTS=refresh;refresh();
})();
</script><script>(function(){'use strict';
var $=function(id){return document.getElementById(id);},app=window.BEC_APP,last=null,online=false,receivedAt=0,receiving=false,queue={},inflight=false,waiting=null,failed=false,group=1,switching=null,currentSave=null,actionPending=null,actionMessage=null;
var order=['detect','nanites','gate','supply','convert','produce','finish'],titles={idle:'等待订单',detect:'读取配方',nanites:'蜂群检查',gate:'韦门确认',supply:'原液备料',convert:'凝聚物转换',produce:'配方运行',finish:'批次收尾',fault:'保护暂停'};
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];});}
function time(n){n=Math.max(0,Number(n)||0);return n<60?n.toFixed(1)+'s':Math.floor(n/60)+'m '+(n%60).toFixed(1)+'s';}
function status(s,bad){$('save-status').textContent=s;$('save-status').classList.toggle('offline-alert',!!bad);}
function saving(){return inflight||!!waiting||!!Object.keys(queue).length;}
function showAction(message,bad){actionMessage={text:message,bad:!!bad};refreshActions();}
function refreshActions(){
 var running=last&&last.mode==='running',reason=!online?'OC 未连接，暂不能启动。':running?'自动化运行中。':saving()?'正在保存草稿，请稍候。':!last.configured?'草稿已保存还不等于绑定已应用。请先点击「应用绑定」，校验通过后再启动。':'绑定已应用，可以启动；修改地址后需重新应用绑定。';
 var hint=$('action-feedback');hint.textContent=actionPending?({'apply_bindings':'正在校验并应用绑定…',start:'正在启动自动化…',pause:'正在暂停自动化…'}[actionPending]):actionMessage?actionMessage.text:reason;
 hint.classList.toggle('action-error',!!(actionMessage&&actionMessage.bad&&!actionPending));hint.setAttribute('role',actionMessage&&actionMessage.bad?'alert':'status');
 $('start-run').textContent=running?'运行中':'启动自动化';$('start-run').disabled=!online||running||!!actionPending||saving();$('start-run').title=reason;
 $('apply-config').disabled=!online||running||!!actionPending||saving();$('stop-run').disabled=!online||!running||!!actionPending;
}
function send(name,args){if(!online)return Promise.reject(Error('OC 未连接，未执行操作'));return OC.emit(name,args||{});}
function key(id,k){var m={'field':'g'+group+'.storage','generator':'g'+group+'.generator1','gate':'g'+group+'.gate','main-me':'mainInterface','workshop-me':'workshopInterface','sub-me':'g'+group+'.subInterface','fluid-transposer':'g'+group+'.transposer','nanite-transposer':'g'+group+'.bee_transposer','load-redstone':'g'+group+'.bee_loadRedstone','return-redstone':'g'+group+'.bee_returnRedstone'};
 if(id.indexOf('node-')===0)return 'n'+id.slice(5)+'.'+(k==='address'?'address':k==='redstone'?'redstone':k);
 if(k==='address')return m[id]||(id.indexOf('generator-')===0?'g'+group+'.generator'+id.slice(10):id.indexOf('bulk-transposer-')===0?'g'+group+'.bulk'+id.slice(16):null);
 return 'g'+group+'.'+(['bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide'].indexOf(k)>=0?'bee_':'')+k;
}
function fieldKeys(m){return ['address'].concat(m.kind==='node'?['redstone','group','pauseSide','gate']:(m.sides||[]).map(function(f){return f[0];}));}
function toValues(draft){var out={};app.scene.modules.forEach(function(m){var v=draft.modules[m.id];if(!v||!m.role)return;fieldKeys(m).forEach(function(k){if(v[k]!=null){var name=key(m.id,k);if(name)out[name]=String(v[k]);}});});return out;}
function importValues(values){var draft={version:1,modules:{}};app.scene.modules.forEach(function(m){if(!m.role)return;var v={};fieldKeys(m).forEach(function(k){var value=values[key(m.id,k)];if(value!=null)v[k]=k==='address'||k==='redstone'||k==='gate'?value:Number(value);});draft.modules[m.id]=v;});receiving=true;app.importDraft(draft);receiving=false;}
function dirty(draft){if(receiving||switching||!last||last.mode==='running')return;var values=toValues(draft);Object.keys(values).forEach(function(k){if(values[k]!==last.values[k]||(currentSave&&currentSave.key===k&&currentSave.value!==values[k])||(waiting&&waiting.key===k&&waiting.value!==values[k]))queue[k]=values[k];});status('正在保存到 OC…');pump();}
window.BEC_BINDING_DIRTY=dirty;
function pump(){if(inflight||waiting||failed||switching||!online||!last)return;var keys=Object.keys(queue);if(!keys.length){status('草稿已保存到 OC');return;}var k=keys[0],v=queue[k],revision=last.revision;delete queue[k];inflight=true;currentSave={key:k,value:v};status('正在保存到 OC…');send('save_field',{key:k,value:v,revision:revision}).then(function(){inflight=false;currentSave=null;waiting={revision:revision,key:k,value:v};if(last&&(last.revision!==revision||last.values[k]===v)){waiting=null;pump();}}).catch(function(e){inflight=false;currentSave=null;if(!Object.prototype.hasOwnProperty.call(queue,k))queue[k]=v;failed=true;status('保存未确认 · 点击重试',true);$('runtime-notice').textContent=e.message;});}
function syncModels(d){var scene=app.scene,base=scene.modules.find(function(m){return m.id==='generator';});if(!base)return;var count=Math.min(16,Math.max(4,d.generatorSlots||4));scene.modules=scene.modules.filter(function(m){return m.id.indexOf('generator-')!==0||Number(m.id.slice(10))<=count;});if(!scene.modules.some(function(m){return m.id===scene.selected;}))scene.selected='assembler';
 for(var j=2;j<=count;j++)if(!scene.modules.some(function(m){return m.id==='generator-'+j;})){var m=Object.assign({},base),dx=Math.floor((j-1)/4)*40,dz=((j-1)%4)*26;m.id='generator-'+j;m.title='纠缠器 '+String(j).padStart(2,'0');m.role='groups['+group+'].generators['+j+']';m.p=[base.p[0]+dx,base.p[1],base.p[2]+dz];m.center=[base.center[0]+dx,base.center[1],base.center[2]+dz];m.marker=[base.marker[0]+dx,base.marker[1],base.marker[2]+dz];scene.modules.push(m);}
 scene.modules.forEach(function(m){if(m.role)m.role=m.role.replace(/^groups\[\d+\]/,'groups['+group+']');if(m.kind==='generator')m.role='groups['+group+'].generators['+(m.id==='generator'?1:m.id.slice(10))+']';});scene.runtimeGroup=group;scene.runtimeValues=d.values||{};scene.request();}
function markMachines(){if(!last)return;app.scene.liveStates=last.machines||{};document.querySelectorAll('[data-label],[data-module]').forEach(function(el){el.dataset.live=(last.machines||{})[el.dataset.label||el.dataset.module]||'unknown';});}
var render=app.scene.onRender;app.scene.onRender=function(s){render(s);markMachines();};
function flow(){if(!last)return;var age=online?Math.min(3,(Date.now()-receivedAt)/1000):0,active=last.mode==='running'&&last.phase!=='idle'&&last.phase!=='finish'&&!last.fault;var elapsed=(last.elapsed||0)+(active?age:0);$('flow-elapsed').textContent=time(elapsed);$('flow-current').textContent=titles[last.phase]||last.phase;$('flow-stage-time').textContent='当前步骤 '+time((last.phaseElapsed||0)+(active?age:0));
 $('flow-steps').innerHTML=order.map(function(p,i){var duration=Number((last.flow||{})[p]||0)+(active&&p===last.phase?age:0),current=last.phase===p,done=duration>0&&!current;return '<div class="flow-step '+(current?'current ':done?'done ':'')+(current&&last.fault?'fault':'')+'"><div class="index">'+(done?'✓ ':String(i+1).padStart(2,'0'))+'</div><strong>'+titles[p]+'</strong><time>'+((duration>0||current)?time(duration):'待执行')+'</time></div>';}).join('');
 $('node-status-list').innerHTML=(Array.isArray(last.nodes)?last.nodes:[]).map(function(n){return '<span class="node-chip '+(n.state==='crafting'?'active':'')+'">N'+String(n.slot).padStart(2,'0')+' · '+esc(n.state)+' · '+(n.workAllowed?'允许接单':'关闭接单')+'</span>';}).join('')||'<span class="node-chip">尚未绑定节点</span>';
 var machines=Object.keys(last.machines||{}).filter(function(id){return id==='field'||id==='gate'||id.indexOf('generator')===0;}).map(function(id){var active=last.machines[id]==='active';return '<span class="node-chip '+(active?'active':'')+'">'+(id==='field'?'约束场':id==='gate'?'韦门':id==='generator'?'纠缠器 1':'纠缠器 '+id.split('-')[1])+' · '+(active?'运行中':last.machines[id]==='unknown'?'不可读':'未运行')+'</span>';}).join('');$('node-status-list').innerHTML=machines+$('node-status-list').innerHTML;
 var events=(Array.isArray(last.timeline)?last.timeline:[]).map(function(e){return '+'+time(e.offset)+'  '+(titles[e.phase]||e.phase);});$('runtime-log').textContent=events.concat(Array.isArray(last.logs)?last.logs:[]).join('\n');
}
function data(d){var changed=group!==(d.group||1);last=d;online=d._online!==false;receivedAt=Date.now();group=d.group||1;if(switching===group)switching=null;if(waiting&&(waiting.revision!==d.revision||(d.values||{})[waiting.key]===waiting.value))waiting=null;
 syncModels(d);if(!switching&&!inflight&&!waiting&&!Object.keys(queue).length&&(changed||!/INPUT|TEXTAREA/.test(document.activeElement.tagName)))importValues(d.values||{});
 $('runtime-notice').textContent=(online?'': 'OC 离线，显示最后快照。')+(d.notice||'')+(d.disk&&d.disk.known?' · 磁盘剩余 '+(d.disk.free/1024).toFixed(0)+' KiB / 保留 '+(d.disk.reserve/1024).toFixed(0)+' KiB':' · 磁盘容量不可读');$('runtime-notice').classList.toggle('offline-alert',!online);
 document.body.classList.toggle('runtime-running',d.mode==='running');$('flow-panel').hidden=false;refreshActions();$('global-settings').disabled=d.mode==='running';
 if(!online)status('OC 离线 · 未保存操作',true);else if(failed)status('保存未确认 · 点击重试',true);else if(!inflight&&!waiting&&!Object.keys(queue).length)status('OC 已连接 · 草稿已保存');
 if($('group-select').options.length!==d.groupCount){$('group-select').innerHTML=Array.from({length:d.groupCount||1},function(_,i){return '<option value="'+(i+1)+'">设备组 '+String(i+1).padStart(2,'0')+'</option>';}).join('');}$('group-select').value=group;if(window.BEC_REFRESH_SELECTS)window.BEC_REFRESH_SELECTS();
 markMachines();flow();pump();
}
function bindingIssues(){
 var v=last&&last.values||{},p='g'+group+'.',issues=[],uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 function value(k){return String(v[k]||'').trim();}
 function add(label,id,field){issues.push({label:label,id:id,field:field||'address'});}
 function address(k,label,id,required,field){var x=value(k);if(!x&&required)add(label+'：未填写',id,field);else if(x&&!uuid.test(x))add(label+'：地址需为完整 UUID',id,field);}
 address('mainInterface','主网供液 ME 接口','main-me',true);
 address(p+'storage','约束场','field',true);address(p+'subInterface','原液子网 ME 接口','sub-me',true);address(p+'transposer','供液转运器','fluid-transposer',true);
 var generators=0;for(var j=1;j<=Math.max(4,last.generatorSlots||4);j++){var k=p+'generator'+j;if(value(k))generators++;address(k,'纠缠器 '+j,j===1?'generator':'generator-'+j,false);}if(!generators)add('至少填写一台纠缠器','generator');
 address(p+'gate','公共韦门','gate',false);address('workshopInterface','样板工坊 ME 接口','workshop-me',false);
 for(var j=1;j<=10;j++)address(p+'bulk'+j,'高速供液口 '+j,'bulk-transposer-'+j,false);
 var bees=[['transposer','蜂群转运器','nanite-transposer'],['loadRedstone','装入端口红石','load-redstone'],['returnRedstone','回收端口红石','return-redstone']],beeOn=bees.some(function(b){return !!value(p+'bee_'+b[0]);});
 bees.forEach(function(b){address(p+'bee_'+b[0],b[1],b[2],beeOn);});
 if(v[p+'mainSide']===v[p+'subSide'])add('供液主网侧与子网侧不能相同','fluid-transposer');
 if(beeOn){var sides=['bankSide','loadSide','returnSide'].map(function(k){return v[p+'bee_'+k];});if(sides.some(function(x,i){return sides.indexOf(x)!==i;}))add('蜂群箱子、装入端口、回收端口必须是三个不同方向','nanite-transposer');}
 var total=0,localCount=0;for(var i=1;i<=16;i++){var n='n'+i+'.';if(!value(n+'address')&&!value(n+'redstone'))continue;total++;if(Number(v[n+'group'])!==group)continue;localCount++;
 address(n+'address','节点 '+i+' 组件','node-'+i,true);address(n+'redstone','节点 '+i+' 暂停红石','node-'+i,true,'redstone');address(n+'gate','节点 '+i+' 独立韦门','node-'+i,false,'gate');
 if(!value(n+'gate')&&!value(p+'gate'))add('节点 '+i+' 需要韦门：填写独立韦门或本组公共韦门','node-'+i,'gate');}
 if(!total)add('至少填写一组传送节点和暂停红石，空位会自动跳过','node-1');else if(!localCount)add('当前设备组还没有分配传送节点','node-1','group');
 if(!value('recipeDirectory'))add('配方目录：未填写','settings');return issues;
}
function showIssues(issues){
 $('binding-issues-list').innerHTML=issues.map(function(x){return '<button type="button" data-issue-module="'+esc(x.id)+'" data-issue-field="'+esc(x.field)+'">'+esc(x.label)+' → 去填写</button>';}).join('');
 $('binding-issues-list').querySelectorAll('button').forEach(function(b){b.onclick=function(){$('binding-issues').close();if(b.dataset.issueModule==='settings'){settings();return;}document.body.classList.toggle('flow-full',false);app.select(b.dataset.issueModule);var field=$('field-'+b.dataset.issueField);if(field)field.focus();};});
 $('binding-issues').showModal();showAction('当前设备组有 '+issues.length+' 项绑定需要补充或修正，点击清单可跳转。',true);
}
function action(name){
 if(actionPending)return;
 if(saving()){showAction('请先等待草稿保存完成。',true);return;}
 if(name==='start'&&last&&!last.configured){showAction('尚未应用绑定：请先点击「应用绑定」。如果校验失败，这里会显示具体原因。',true);return;}
 if(name==='apply_bindings'){var issues=bindingIssues();if(issues.length){showIssues(issues);return;}}
 actionMessage=null;actionPending=name;refreshActions();
 send(name,{revision:last&&last.revision}).then(function(r){actionPending=null;showAction(r.message||'请求已确认，等待 OC 状态更新。',false);}).catch(function(e){actionPending=null;showAction((name==='apply_bindings'?'应用绑定失败：':name==='start'?'启动失败：':'暂停失败：')+e.message,true);});
}
function settings(){if(!last)return;var specs=[['recipeDirectory','配方目录'],['cacheTarget','库存参考目标']];for(var i=1;i<=Math.max(4,last.generatorSlots||4);i++)specs.push(['g'+group+'.generator'+i,'纠缠器 '+i+'（多余可空）']);$('extra-fields').innerHTML=specs.map(function(f){return '<label>'+f[1]+'<input data-config="'+f[0]+'" value="'+esc(last.values[f[0]]||'')+'" maxlength="160" spellcheck="false"></label>';}).join('');$('extra-fields').querySelectorAll('input').forEach(function(input){input.onchange=function(){queue[input.dataset.config]=input.value;pump();};});$('runtime-settings').showModal();}
document.querySelector('.top-actions').innerHTML='<span id="save-status" class="save-status">等待 OC 连接</span><button class="button quiet" id="global-settings">公共设置</button><button class="button quiet" id="apply-config">应用绑定</button><button class="button primary run-button" id="start-run">启动自动化</button><button class="button quiet stop-button" id="stop-run">暂停</button>';
var feedback=document.createElement('div');feedback.id='action-feedback';feedback.className='action-feedback';feedback.textContent='等待 OC 连接…';feedback.setAttribute('aria-live','polite');document.body.appendChild(feedback);
var tabs=document.createElement('nav');tabs.className='runtime-tabs';tabs.innerHTML='<button class="active" data-tab="structure">结构 / 绑定</button><button data-tab="flow">运行流程</button>';document.querySelector('.topbar').insertBefore(tabs,document.querySelector('.top-actions'));
var flowPanel=document.createElement('section');flowPanel.className='flow-panel';flowPanel.id='flow-panel';flowPanel.innerHTML='<div class="flow-title"><div><h2>自动化流程 <span id="flow-current">等待 OC</span></h2><p id="flow-stage-time">当前步骤 —</p></div><div><div class="elapsed" id="flow-elapsed">0.0s</div><small>当前 / 最近批次总耗时</small></div></div><div class="flow-path" id="flow-steps"></div><div class="flow-bottom"><div><h4>TRANSFER NODES / 接单控制</h4><div class="node-list" id="node-status-list"></div><div class="runtime-legend"><b>绿色：机器回读运行中</b> · <em>金色：当前步骤使用的外设</em><br>外设阶段占用不等同于硬件正在搬运</div></div><div><h4>EXECUTION / 阶段时间线</h4><div id="runtime-log" class="runtime-log" style="white-space:pre-wrap"></div></div></div>';
document.querySelector('.main').appendChild(flowPanel);var notice=document.createElement('div');notice.id='runtime-notice';notice.className='runtime-notice';notice.textContent='等待 OC 数据，网页预览不控制机器。';document.querySelector('.main').appendChild(notice);
var issuesDialog=document.createElement('dialog');issuesDialog.id='binding-issues';issuesDialog.className='runtime-settings binding-issues';issuesDialog.innerHTML='<h2>绑定检查 / 当前设备组</h2><p>点击下列项目跳转填写。这里只检查填写内容；通过后还会由 OC 校验设备是否在线、方法和机器状态。</p><div id="binding-issues-list"></div><p>空传送节点会跳过。额外纠缠器、高速供液口、样板工坊可留空；自动换蜂的三项地址须全部填写或全部留空。每个节点须有独立韦门或使用本组公共韦门。</p><footer><button id="close-issues" class="button primary">返回修改</button></footer>';document.body.appendChild(issuesDialog);$('close-issues').onclick=function(){$('binding-issues').close();};
var dialog=document.createElement('dialog');dialog.id='runtime-settings';dialog.className='runtime-settings';dialog.innerHTML='<h2>公共配置</h2><p>填写后自动暂存。应用绑定通过设备校验后，才能启动。</p><label>当前模型对应 <select id="group-select"></select></label><div id="extra-fields"></div><footer><button id="close-settings" class="button primary">完成</button></footer>';document.body.appendChild(dialog);
document.querySelectorAll('[data-tab]').forEach(function(b){b.onclick=function(){document.querySelectorAll('[data-tab]').forEach(function(x){x.classList.toggle('active',x===b);});document.body.classList.toggle('flow-full',b.dataset.tab==='flow');app.scene.request();};});

 document.querySelector('.inspector-bottom p').textContent='草稿由 OC 自动保存，支持 Ctrl+V。应用绑定前不控制机器。';$('model-callout').querySelector('p').innerHTML='点击机器填写地址，自动暂存到 OC。<br>拖动旋转 · 滚轮缩放 · 右键平移';document.querySelector('.pill').textContent='V2 / OCHD';
document.querySelector('.stage-title').innerHTML='<span class="live-dot"></span>结构与机器状态<span class="stage-sub">/ 实际回读 + 阶段标记</span>';
$('save-status').onclick=function(){if(failed){failed=false;pump();}};$('apply-config').onclick=function(){action('apply_bindings');};$('start-run').onclick=function(){action('start');};$('stop-run').onclick=function(){action('pause');};$('global-settings').onclick=settings;$('close-settings').onclick=function(){$('runtime-settings').close();};$('group-select').onchange=function(){if(inflight||waiting||Object.keys(queue).length){this.value=group;return;};switching=Number(this.value);send('select_group',{group:switching}).then(function(){$('runtime-settings').close();}).catch(function(e){switching=null;$('runtime-notice').textContent=e.message;});};
 window.BEC_CONTROL={receive:data,values:toValues,issues:bindingIssues,queue:function(){return queue;}};
if(window.OC&&OC.onData)OC.onData(data);else{$('runtime-notice').textContent='浏览器预览：未连接 OC，所有机器操作禁用。';$('start-run').disabled=$('stop-run').disabled=$('apply-config').disabled=true;}
setInterval(function(){flow();if(last&&Date.now()-receivedAt>7000){online=false;status('OC 数据已过期',true);refreshActions();}},250);
})();
</script></body></html>
]=]},
{"lib/web_session.lua",[=[-- HTML is a data client. Only this Lua allowlist can save bindings or run V2.
local c=require('component');local clock=require('computer');local ser=require('serialization')
return function(C,B,W,options)
 options=options or {}
 local H={running=false,group=1,notice='点击机器填写地址；草稿自动存到 OC，应用绑定后再启动。'}
 local path=C.path('config.dat');local expected=B.read(path)
 local cfg=expected and C.read(path)or {version=2,mainInterface='',recipeDirectory=C.path('recipes'),cacheTarget=144000,
  groups={{name='设备组 01',storage='',gate='',subInterface='',transposer='',mainSide=4,subSide=5,generators={},bulkTransposers={},nanites={enabled=false,mode='cell-io'}}},nodes={}}
 local draftPath=C.path('bindings.draft.dat');local raw=B.read(draftPath);local draft=raw and ser.unserialize(raw)
 local E
 local storage=options.storage or assert(loadfile(C.path('lib/storage.lua')))()(C)
 local function revision()return B.revision((expected or '')..'|'..(raw or ''))end
 local function fields()return B.draftFields(cfg,draft,expected)end
 local function payload(change)
  local out={'_revision='..revision()}
  for _,f in ipairs(fields())do out[#out+1]=f.key..'='..(change and change.key==f.key and change.value or f.value)end
  return table.concat(out,'\n')
 end
 local function idleEditor()
  assert(not H.running,'先暂停自动化再编辑绑定')
  if E then for _,t in ipairs(E.tasks)do assert(not t.co,'等待工作器退出并保留日志后再编辑')end end
 end
 local function read(a,m,...)
  if not a or a==''then return nil end
  local ok,value=pcall(c.invoke,a,m,...);if ok then return value end
 end
 function H.handle(name,args,request)
  assert(type(args)=='table','页面参数必须为对象')
  assert(type(request)=='number'and request==math.floor(request)and request>0,'请求编号无效')
  if name=='select_group'then
   assert(type(args.group)=='number'and cfg.groups[args.group],'设备组不存在');H.group=args.group;return '已切换设备组'
  elseif name=='save_field'then
   idleEditor();assert(args.revision==revision(),'草稿已变化，请等最新快照后重试')
   local disk=storage.status();assert(disk.known and disk.ok,'磁盘剩余空间不足或不可读，草稿未保存：至少保留512KiB')
   assert(type(args.value)=='string'and #args.value<=160 and not args.value:find('[\r\n=]'),'字段格式无效')
   local known=false;for _,f in ipairs(fields())do if f.key==args.key then known=true;break end end
   assert(known,'未知绑定字段')
   raw=B.saveDraft(C,cfg,payload(args),request,expected,raw,revision());draft=ser.unserialize(raw)
   H.notice='草稿已保存到 OC，可退出查地址后继续。';return H.notice
  elseif name=='apply_bindings'then
   idleEditor();assert(args.revision==revision(),'草稿已变化，请先等待保存完成')
   storage.prune(cfg)
   cfg=B.saveV2(C,cfg,payload(),request,expected,revision());expected=B.read(path)
   -- The old draft's base is no longer current, so B.draftFields ignores it.
   E=nil;H.started=false;H.notice='绑定已校验并应用，点击启动自动化。';return H.notice
  elseif name=='start'then
   assert(not H.running,'自动化已经运行')
   assert(B.read(path)==expected,'正式配置已被其他程序修改，请退出页面后重新打开')
   storage.prune(cfg);local disk=storage.status()
   assert(disk.known and disk.ok,'磁盘剩余空间不足或不可读：至少保留512KiB，暂停启动并保留恢复记录')
   assert(args.revision==revision(),'绑定已变化，请等最新快照后启动')
   local formal={};for _,f in ipairs(B.v2Fields(cfg))do formal[f.key]=f.value end
   for _,f in ipairs(fields())do assert(f.value==formal[f.key],'草稿尚未应用，请先应用绑定')end
   cfg=C.load();C.validate(cfg,true)
   for _,n in ipairs(cfg.nodes)do
    local state=c.invoke(n.address,'getState')
    assert(state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low','先暂停节点，当前 '..tostring(state))
   end
   for _,g in ipairs(cfg.groups)do for _,a in ipairs(g.generators)do
    assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'先退出其他控制器并停止纠缠器')
   end end
   if not E then E=options.engine and options.engine(cfg)or assert(loadfile(C.path('lib/engine.lua')))()(cfg,C,assert(loadfile(C.path('lib/bridge.lua')))(),false)end
   -- On first start initialize physical pause outputs. This is a deliberate
   -- Start action, never a side effect of displaying/editing the page.
   if not H.started then
    for i,n in ipairs(cfg.nodes)do
     c.invoke(n.redstone,'setOutput',n.pauseSide,15)
     assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'暂停输出回读失败')
     E.nodeWork(i,false)
    end
    H.started=true
   end
   local seen={};for i,n in ipairs(cfg.nodes)do if not seen[n.group]then E.resumeNode(i);seen[n.group]=true end end
   H.running=true;H.notice='自动化运行中；节点按批次关闭接单，整组完成后再接下一单。';return H.notice
  elseif name=='pause'then
   H.running=false;if E then E.pauseAll()end;H.notice='已请求暂停；工作器收尾，未确认记录保留。';return H.notice
  elseif name=='refresh'then return '页面在线'
  end
  error('不支持的页面事件')
 end
 function H.step()
  if not E then return end
  local draining=false;for _,t in ipairs(E.tasks)do if t.co then draining=true end end
  if H.running or draining then E.step()end
  if E.diskLow then H.running=false;H.notice='磁盘空间不足，自动化已暂停；当前及未确认日志保留，请腾出至少512KiB。'end
 end
 function H.snapshot()
  local now=clock.uptime();local values={}
  for _,f in ipairs(fields())do
   local g=f.key:match('^g(%d+)%.')
   if not g or tonumber(g)==H.group then values[f.key]=f.value end
  end
  local out={mode=H.running and 'running'or 'binding',revision=revision(),values=values,group=H.group,groupCount=#cfg.groups,
   configured=expected~=nil,notice=H.notice,now=now,machines={},nodes={},flow={},timeline={},logs={},disk=storage.status()}
  local g=cfg.groups[H.group];out.groupName=g.name or ('设备组 '..H.group);out.generatorSlots=math.max(4,#g.generators);local selected
  if E then local owner=E.groupOwner[H.group];selected=owner and E.tasks[owner]
   if not selected then for i,n in ipairs(cfg.nodes)do
    local t=E.tasks[i];if n.group==H.group and t.startedAt and (not selected or t.startedAt>selected.startedAt)then selected=t end
   end end
   for i=math.max(1,#E.logs-3),#E.logs do out.logs[#out.logs+1]=E.logs[i]:sub(1,300)end
  end
  if selected then
   local endTime=selected.endedAt or now;out.elapsed=endTime-selected.startedAt;out.phase=selected.phase or 'detect'
   out.phaseElapsed=endTime-(selected.phaseAt or endTime)
   for key,value in pairs(selected.flow or {})do out.flow[key]=value end
   if not selected.endedAt then out.flow[out.phase]=(out.flow[out.phase]or 0)+out.phaseElapsed end
   for _,row in ipairs(selected.timeline or {})do out.timeline[#out.timeline+1]={phase=row.phase,offset=row.at-selected.startedAt}end
   out.fault=selected.fault==true;out.leader=selected.members and selected.members[1]
  else out.phase='idle';out.elapsed=0;out.phaseElapsed=0 end
  local function actual(id,a)
   local active=read(a,'isMachineActive');out.machines[id]=active==nil and 'unknown'or active and 'active'or 'idle'
  end
  actual('field',g.storage);actual('gate',g.gate)
  for j=1,math.max(1,#g.generators)do actual(j==1 and 'generator'or 'generator-'..j,g.generators[j])end
  local supply=out.phase=='supply';out.machines['fluid-transposer']=supply and 'phase'or 'idle'
  for j=1,10 do out.machines['bulk-transposer-'..j]=supply and 'phase'or 'idle'end
  out.machines['nanite-transposer']=out.phase=='nanites'and 'phase'or 'idle'
  for i,n in ipairs(cfg.nodes)do if n.group==H.group then
   local state=read(n.address,'getState')or 'offline';local allowed=read(n.address,'isWorkAllowed')
   out.nodes[#out.nodes+1]={slot=n.slot or i,state=state,workAllowed=allowed==true,name=n.name}
   out.machines['node-'..(n.slot or i)]=state=='crafting'and 'active'or state=='offline'and 'unknown'or 'idle'
  end end
  return out
 end
 function H.close()
  H.running=false;if E then return E.shutdown()end;return {}
 end
 function H.engine()return E end
 return H
end
]=]},
{"main.lua",[=[local ROOT='/home/bec_v2'
local function module(name)return assert(loadfile(ROOT..'/lib/'..name..'.lua'))()end
local C=module('config')
local mode,option=...
if not mode then
 for _ in require('component').list('hd_panel',true)do mode='web';break end
 mode=mode or 'monitor'
end
if mode=='web'then assert(loadfile(ROOT..'/web.lua'))();return end
if mode=='setup-hd'then assert(loadfile(ROOT..'/setup_hd.lua'))();return end
if mode=='reports'then assert(loadfile(ROOT..'/report_setup.lua'))();return end
if mode=='scan'then module('scan')();return end
if mode=='setup'then module('setup')(C);return end
if mode=='add-nodes'then module('setup')(C,true);return end
if mode=='patterns'then module('patterns')(C,option or 'preview');return end
assert(mode=='monitor'or mode=='run'or mode=='pause','用法：scan / setup / add-nodes / patterns / monitor / pause / run')
local cfg=C.load();C.validate(cfg,true)
local E=module('engine')(cfg,C,module('bridge'),mode=='monitor')
local c=require('component');local event=require('event')
if mode=='pause'then
 local errors=E.shutdown();for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
 assert(#errors==0,'有暂停/停机回读失败，请核对设备')
 print('已绑定节点输出15、纠缠器关闭；待纠缠器停止活动后再run，约束场保持开启。');return
end
if mode=='run'then
 for _,g in ipairs(cfg.groups)do for _,a in ipairs(g.generators)do
  assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'先停止稳定版和所有纠缠器，再启动V2')
 end end
 for _,n in ipairs(cfg.nodes)do
  local state=c.invoke(n.address,'getState')
  assert(state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low','先暂停全部节点，再启动V2；当前 '..tostring(state))
  assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'先提供暂停信号15，再启动V2')
 end
end
local UI=module('ui')(cfg,E,C)
local ok,err=xpcall(function()
 local running=true;local nextPaint=0
 while running do
  E.step()
  local now=require('computer').uptime()
  if now>=nextPaint then UI.draw();nextPaint=now+0.5 end
  local signal,_,character,code=event.pull(0.05,'key_down')
  if signal=='key_down'then
   if character==113 or character==81 then running=false
   else local success,reason=pcall(UI.key,character,code);if not success then E.log(UI.selected(),tostring(reason))end end
  end
 end
end,debug.traceback)
local errors=E.shutdown();UI.close()
if not ok then E.reportFault(UI.selected(),tostring(err));print("V2已停止："..tostring(err))end
if E.reports then print(E.reports.status)end
for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
print(mode=='monitor'and '只读监控已退出'or 'V2已暂停所有组并关闭纠缠器；现场和日志保留')
]=]},
{"report_setup.lua",[=[local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local fs=require('filesystem');local ser=require('serialization');local term=require('term')
local path=C.path('github-upload.dat')
print('Optional GitHub reports. Use your own initialized repository (main branch).')
io.write('Destination owner/repository: ')
local destination=assert(io.read(),'Cancelled')
local owner,repo=destination:match('^([%w%-]+)/([%w%._%-]+)$')
assert(owner and #owner<=39 and #repo<=100 and repo~='.'and repo~='..','Invalid repository; nothing changed')
print('GitHub: '..owner..'/'..repo..' / diagnostics/v2/')
print('Use a fine-grained token for this repository with Contents: read and write.')
print('Paste the token HERE in OC only. Input is masked; do not send it in chat.')
io.write('Token: ')
local token=assert(term.read(nil,false,'*'),'No token entered'):gsub('%s+$','')
assert(token:match('^[%w_]+$')and #token>=10,'Token format not accepted; no configuration changed')
local value={version=1,owner=owner,repo=repo,token=token}
local text=ser.serialize(value,false);local temp=path..'.new'
local f=assert(io.open(temp,'w'));assert(f:write(text));assert(f:flush());f:close()
f=assert(io.open(temp,'r'));local actual=f:read('*a');f:close();assert(actual==text,'Read-back failed')
assert(not fs.exists(path..'.previous'),'An old token backup exists; review it locally before replacing credentials')
if fs.exists(path)then assert(fs.rename(path,path..'.previous'),'Credential backup failed')end
local ok,err=fs.rename(temp,path)
if not ok then
 if fs.exists(path..'.previous')then assert(fs.rename(path..'.previous',path),'Rollback failed')end
 error('Save failed: '..tostring(err))
end
print('SAVED. Credentials stay on this OC disk and are excluded from diagnostic reports.')
]=]},
{"runtime/controller.lua",[=[local c = require("component") local ser = require("serialization") local computer = require("computer") local fs = require("filesystem")
local sides = require("sides") local event = require("event") local mode = (...) or "preview" local JOURNAL = "/home/bec_auto.journal"
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d" local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50" local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad" local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0"
local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0" local GATE_ADDRESS = "cf2a0c4a-ab8d-4958-b1df-253094d6690c" local RS, GEN, GATE, armed, record local stopping=false
local NANITES=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")()
local lastNaniteTier
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
local needed=call(NODE,"getRequiredTier");needed=type(needed)=="table" and needed.tier or needed
if type(needed)~="number" then return end
if BEC_V2_PHASE then BEC_V2_PHASE("nanites")end
local started=computer.uptime();print("检查蜂群 / 准备换盘")
NANITES.ensure({tick=tick,stopping=function() return stopping end})
print(string.format("蜂群检查/换盘完成：%.2f 秒",computer.uptime()-started))
local provided=call(NODE,"getProvidedTier")
assert(type(provided)=="table" and provided.tier>=needed and integer(call(NODE,"getAvailableNanites"))>=64,"蜂群等级或数量不足，保持暂停")
lastNaniteTier=needed
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
end return moves, sub, expected end local function waitUntil(seconds, condition, guard)
local deadline = computer.uptime() + seconds while true do local ready, snapshot = condition() if ready then return end
if guard then guard(snapshot) end assert(computer.uptime() < deadline, "等待超时，停止") os.sleep(0.25) end
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
return expected end local function serve() local waiting={idle=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
local round=0 while not stopping do local nanitesChecked=false;pause(15); generator(false) local state=call(NODE,"getState")
if stopping then break end state=call(NODE,"getState") if state=="paused-immediate" or state=="nanite-tier-too-low" then switchNanites();nanitesChecked=true;state=call(NODE,"getState") end if waiting[state] then
if state~=record.lastState then print("等待订单/机器就绪: "..state.."；任意数量同配方订单均可，按 Q 停止。") record.lastState=state;save("waiting") end
field();tick(0.1) else waitUntil(10,function() local v=call(NODE,"getState")
return v=="paused-immediate",v end,function(v) assert(v=="crafting" or waiting[v],"无法暂停，实际状态: "..tostring(v)) field()
end) if not nanitesChecked then switchNanites()end;if stopping then break end record.required,record.remaining=current() local target,count=batchTarget(record.required,record.remaining) local stable=false
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
local needed=call(NODE,"getRequiredTier");needed=type(needed)=="table" and needed.tier or needed
local supplied=call(NODE,"getProvidedTier")
if type(needed)=="number" and (needed~=lastNaniteTier or type(supplied)~="table" or supplied.tier<needed) then
pause(15);waitUntil(10,function() local s=call(NODE,"getState");return s=="paused-immediate" or s=="nanite-tier-too-low" end)
switchNanites();if stopping then break end;verifyGate(filters);pause(0);deadline=computer.uptime()+600;v=call(NODE,"getState")
end
local parallel if req~=nil then parallel=integer(call(NODE,"getParallelRecipesInProgress")) local matching=parallel>0
for name,n in pairs(req) do if not perRecipe[name] or n~=perRecipe[name]*parallel then matching=false end end for name in pairs(perRecipe) do if req[name]==nil then matching=false end end if not matching then pause(15);break end if not same(gateFilters(req),filters) then pause(15);break end
lastRequired=req end if v=="idle" then local consumed=call(NODE,"getConsumedCondensate")
assert(type(consumed)=="table","节点空闲后消耗记录不可读") for name,need in pairs(lastRequired) do assert(integer(consumed[name] or 0)>=need, "节点进入空闲但凝聚物未消耗完，可能故障关闭: "..name.."；需求 "..need.."，已消耗 "..tostring(consumed[name] or 0))
end stopping=true;break end if waiting[v] then break end
assert(v=="crafting" or (v=="paused-immediate" and computer.uptime()-releasedAt<3), "节点运行异常: "..tostring(v)) local refill=false if computer.uptime()>=nextQueueCheck and req~=nil then
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
]=]},
{"runtime/nanites.lua",[=[-- ME storage-bus switching. Loaded by the production controller.
local c=require('component')
local ser=require('serialization')
local fs=require('filesystem')
local clock=require('computer')
local sides=require('sides')
local T='4bebfefd-f3c6-40ac-81d6-35b331415b0f'
local SUPPLY='41c9711c-cb6c-4fb5-8690-9a4ff709d18b'
local HOLD='5009c70f-9607-48b1-8831-488b599942cd'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local PATH='/home/bec_nanites.journal'
local ports,record={},nil
local function call(a,m,...) return c.invoke(a,m,...) end
local function loadRecord()
 local f=io.open(PATH,'r');if not f then return end
 local text=f:read('*a');f:close()
 local r=ser.unserialize(text);assert(type(r)=='table' and r.version==1,'蜂群日志损坏')
 return r
end
local function write(path,text)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 f=assert(io.open(path,'r'));local actual=f:read('*a');f:close();assert(actual==text,'蜂群日志回读失败')
end
local function save(stage)
 record.stage=stage
 local f=io.open(PATH,'r');if f then local old=f:read('*a');f:close();write(PATH..'.previous',old) end
 write(PATH,ser.serialize(record,false))
end
local function id(item) return item.name..':'..tostring(item.damage or 0) end
local labels={{'transcendent',4},{'six phased',5},{'six-phased',5},{'white dwarf',6},{'black dwarf',7},
 {'universium',8},{'eternity',9},{'magmatter',10},{'mag matter',10},{'carbon',1},{'glowstone',1},{'silver',2},{'neutronium',2},{'gold',3}}
local function tier(item)
 if item.name=='gregtech:gt.metaitem.03' and item.damage==451 then return 4 end
 local label=tostring(item.label or ''):lower()
 if not label:find('nanite',1,true) then return end
 for _,entry in ipairs(labels) do if label:find(entry[1],1,true) then return entry[2] end end
 error('未知蜂群类型，请保留物品编号: '..ser.serialize(item,false))
end
local function add(result,item)
 if type(item)~='table' then return end
 local n=item.size or item.amount or 0;if n<=0 then return end
 local grade=tier(item);assert(grade,'蜂群子网里有其他物品: '..tostring(item.label or item.name))
 assert(not item.hasTag,'不支持带NBT蜂群')
 local key=id(item)
 local row=result[key] or {name=item.name,damage=item.damage or 0,tier=grade,label=item.label,size=0}
 row.size=row.size+n;result[key]=row
end
local function stock(address,side)
 local result={};local items=call(address,'getItemsInNetwork');assert(type(items)=='table','蜂群子网库存不可读')
 for _,item in pairs(items) do add(result,item) end
 for slot=1,9 do add(result,call(T,'getStackInSlot',side,slot)) end
 return result
end
local function count(rows) local n=0;for _,item in pairs(rows) do n=n+item.size end;return n end
local function requiredTier()
 local value=call(NODE,'getRequiredTier');return type(value)=='table' and value.tier or value
end
local function discover()
 assert(call(T,'getInventoryName',2)=='tile.appliedenergistics2.BlockInterface','北面应为备用网物品接口')
 assert(call(T,'getInventoryName',4)=='tile.appliedenergistics2.BlockInterface','西面应为收容网物品接口')
 ports[SUPPLY]=2;ports[HOLD]=4
 for _,a in ipairs({SUPPLY,HOLD}) do
  assert(c.type(a)=='me_interface','蜂群接口组件缺失')
  for _,m in ipairs({'getItemsInNetwork','getInterfaceConfiguration','setInterfaceConfiguration'}) do assert(c.methods(a)[m]~=nil,'蜂群接口缺少 '..m) end
 end
end
local function clear(address)
 assert(call(address,'setInterfaceConfiguration',1)==true,'无法清除蜂群接口配置')
 assert(call(address,'getInterfaceConfiguration',1)==nil,'蜂群配置未清除')
 record.owned=nil;save(record.stage)
end
local function configure(address,item)
 record.owned=address;record.config={name=item.name,damage=item.damage,size=64};save(record.stage)
 assert(call(address,'setInterfaceConfiguration',1,record.config)==true,'蜂群接口配置失败；此版本可能需要数据库组件')
 local value=call(address,'getInterfaceConfiguration',1)
 assert(type(value)=='table' and id(value)==id(item),'蜂群配置回读不一致')
end
local function guard(ctx)
 assert(call(RS,'getOutput',sides.top)==15,'换蜂群必须保持暂停')
 local state=call(NODE,'getState')
 assert(state=='paused-immediate' or state=='nanite-tier-too-low','换蜂群时节点状态变化: '..tostring(state))
 assert(requiredTier()==record.requiredTier,'换蜂群时需求等级变化')
 if ctx and ctx.check then ctx.check() end
end
local function tick(ctx)
 if ctx and ctx.tick then ctx.tick(0.1) else os.sleep(0.1) end
 if ctx and ctx.stopping and ctx.stopping() then error('蜂群切换已暂停，保留进度') end
end
local function move(from,to,slot,limit)
 local item=call(T,'getStackInSlot',ports[from],slot)
 if type(item)~='table' or (item.size or 0)<=0 then return 0 end
 assert(tier(item),'接口出现无关物品')
 local n=math.min(limit,item.size)
 record.pending={from=from,to=to,slot=slot,name=item.name,damage=item.damage,requested=n};save(record.stage)
 local moved=call(T,'transferItem',ports[from],ports[to],n,slot)
 assert(type(moved)=='number' and moved>=0 and moved<=n and moved==math.floor(moved),'蜂群搬运返回值不明确')
 record.pending=nil;record.moved=(record.moved or 0)+moved;save(record.stage)
 return moved
end
local function emptyConfigs()
 for _,a in ipairs({SUPPLY,HOLD}) do for slot=1,9 do
  assert(call(a,'getInterfaceConfiguration',slot)==nil,'蜂群专用接口已有配置，请清空配置栏')
 end end
end
local M={}
function M.preview()
 discover()
 print('蜂群转运器: '..T..'；备用北2，收容西4')
 print('收容网: '..ser.serialize(stock(HOLD,4),false))
 print('备用网: '..ser.serialize(stock(SUPPLY,2),false))
 print('所需等级: '..tostring(requiredTier())..'；节点蜂群 '..tostring(call(NODE,'getAvailableNanites')))
end
function M.ensure(ctx)
 local need=requiredTier();if type(need)~='number' then return false end
 discover();record=loadRecord()
 assert(not record or not record.pending,'蜂群搬运存在未确认操作，不能自动重试')
 local provided=call(NODE,'getProvidedTier')
 local have=type(provided)=='table' and provided.tier or 0
 local available=call(NODE,'getAvailableNanites')
 local interrupted=record and record.stage~='done'
 if not interrupted and have==need and available>=64 then return false end
 if interrupted then
  assert(record.requiredTier==need,'旧蜂群切换需求变化，保留日志核对')
  guard(ctx)
  if record.owned then clear(record.owned);tick(ctx) end
 else
  emptyConfigs()
  local reserve=stock(SUPPLY,2)
  local hold=stock(HOLD,4)
  assert(count(hold)==available,'收容子网与节点蜂群数量不符；输出槽请锁定，控制网仅连接这一蜂群仓')
  local choice
  for _,item in pairs(reserve) do
   if item.tier>=need and item.size>=64 and (not choice or item.tier<choice.tier or item.tier==choice.tier and item.size>choice.size) then choice=item end
  end
  if have>=need and available>=64 and (not choice or choice.tier>=have) then return false end
  assert(choice,'备用子网缺少 T'..need..' 或更高等级蜂群，至少需要64个')
  local baseline={}
  for key,item in pairs(reserve) do baseline[key]=item.size end
  for key,item in pairs(hold) do baseline[key]=(baseline[key] or 0)+item.size end
  record={version=1,requiredTier=need,choice=choice,goal=math.min(choice.size,math.max(64,available)),stage='draining',moved=0,baseline=baseline}
  guard(ctx);save('draining')
  print('蜂群切换: T'..have..' -> T'..choice.tier..'，目标 '..record.goal..' 个')
 end
 local deadline=clock.uptime()+300
 if record.stage=='draining' then
  while true do
   guard(ctx);assert(clock.uptime()<deadline,'退回蜂群超时，检查存储总线允许提取及备用网空间')
   local rows=stock(HOLD,4)
   if count(rows)==0 then if record.owned then clear(record.owned) end;save('filling');break end
   local old;for _,item in pairs(rows) do old=item;break end
   if record.owned then clear(record.owned);tick(ctx) end
   configure(HOLD,old)
   while true do
    guard(ctx);assert(clock.uptime()<deadline,'退回蜂群超时')
    for slot=1,9 do move(HOLD,SUPPLY,slot,64) end
    tick(ctx)
    local fresh=stock(HOLD,4);if not fresh[id(old)] then break end
   end
   clear(HOLD);tick(ctx)
  end
 end
 if record.stage=='filling' then
  configure(SUPPLY,record.choice)
  while true do
   guard(ctx);assert(clock.uptime()<deadline,'装入蜂群超时，检查存储总线允许插入')
   local rows=stock(HOLD,4);local held=rows[id(record.choice)]
   local n=held and held.size or 0
   assert(count(rows)==n and n<=record.goal,'收容子网混入其他蜂群或超额，保持暂停')
   if n==record.goal then break end
   for slot=1,9 do
    local item=call(T,'getStackInSlot',2,slot)
    if item and (item.size or 0)>0 then assert(id(item)==id(record.choice),'供货口蜂群类型变化');n=n+move(SUPPLY,HOLD,slot,record.goal-n) end
    if n==record.goal then break end
   end
   tick(ctx)
  end
  clear(SUPPLY);save('verifying')
 end
 local verified=false
 for i=1,50 do
  guard(ctx);local p=call(NODE,'getProvidedTier');local n=call(NODE,'getAvailableNanites')
  if type(p)=='table' and p.tier==record.choice.tier and n==record.goal then verified=true;break end
  tick(ctx)
 end
 assert(verified,'蜂群仓回读未达到目标，检查控制网是否仅存储在蜂群仓')
 local actual={}
 for key,item in pairs(stock(SUPPLY,2)) do actual[key]=item.size end
 for key,item in pairs(stock(HOLD,4)) do actual[key]=(actual[key] or 0)+item.size end
 for key,n in pairs(record.baseline) do assert(actual[key]==n,'蜂群总量核对不符，保留日志: '..key) end
 for key,n in pairs(actual) do assert(record.baseline[key]==n,'蜂群库存类型变化，保留日志: '..key) end
 save('done');print('蜂群切换完成: T'..record.choice.tier..' / '..record.goal..' 个')
 return true
end
return M
]=]},
{"runtime/nanites_cell.lua",[=[-- V2 module: whole-cell transfers through the verified south/north ME IO ports.
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
local function hive()
 local n=call(NODE,'getAvailableNanites');assert(whole(n),'蜂群仓数量无效')
 local p=call(NODE,'getProvidedTier')
 if n==0 then return 0 end
 assert(type(p)=='table' and whole(p.tier) and type(p.name)=='string','蜂群仓类型不可读')
 return n,p
end
local function guard()
 cfg.checkGroup()
 assert(call(PAUSE,'getOutput',cfg.pauseSide)==15,'换蜂必须保持传送节点暂停红石15')
 local s=call(NODE,'getState')
 assert(s=='paused-immediate' or s=='nanite-tier-too-low' or
  s=='idle' and call(NODE,'isWorkAllowed')==false,'节点状态不适合换蜂：'..tostring(s))
 assert(needed()==record.requiredTier,'换蜂过程中配方等级变化，保留现场')
 if context and context.check then context.check() end
 if context and context.stopping and context.stopping() then error('换蜂已暂停，保留现场') end
end
local function tick()
 if context and context.tick then context.tick(0.1) else os.sleep(0.1) end
 guard()
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
local function choose(cells,need)
 local seen,best={},nil
 for _,disk in ipairs(cells) do if disk.item and not seen[disk.item.key] then
  local item=disk.item;seen[item.key]=true
  local picked,n=pack(cells,item.key)
  if item.tier>=need and n>=MIN and (not best or item.tier<best.item.tier or item.tier==best.item.tier and n>best.count) then
   best={item=item,count=n,picked=picked}
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
 local need=needed();if not whole(need) or need<1 then return false end
 if cfg.checkSharedHive then cfg.checkSharedHive()end
 context=ctx;local size=discover()
 local old=oldRecord();assert(not old or old.stage=='done','旧蜂群IO未完成，保留盘和日志，不自动重放')
 emptyPorts()
 local cells=bank(size);local h,p=hive();local best=choose(cells,need)
 local known=old and sameBinding(old.binding)and old.holding
 -- A saturated node reading cannot prove the current raw quantity. Recover to
 -- read the actual quantity before another operation, even with an old record.
 if not (known and known.count==h and h<DISPLAY_CAP and p and known.family==p.name and known.tier==p.tier) then known=nil end
 local sameFamily=0
 if p then for _,disk in ipairs(cells) do if disk.item and disk.item.family==p.name then sameFamily=sameFamily+disk.count end end end
 local keeping=h>0 and p.tier>=need and h+sameFamily>=MIN and (not best or best.item.tier>=p.tier)
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
 record={version=2,kind='cell-io',binding=binding,requiredTier=need,holding=known,stage='prepared'}
 guard();archive();save('prepared')
 local ok,result=xpcall(function()
  if h>0 and (not keeping or not known) then recover(cells);cells=bank(size);best=choose(cells,need);assert(best,'回收后没有可装入蜂群') end
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
]=]},
{"runtime/patterns.lua",[=[-- Automatic workshop pattern registration. Never touches the production interface.
local mode=(...) or "preview"
local c=require("component")
local fs=require("filesystem")
local ser=require("serialization")
local event=require("event")
local ADDRESS="72994a02-7bff-41cb-bfc7-8a541036d7ad"
local DIR="/home/bec/recipes"
local announced={}
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function read(slot) return c.invoke(ADDRESS,"getInterfacePattern",slot) end
local function load(path)
 local f=assert(io.open(path,"r"));local text=f:read("*a");f:close()
 local value=ser.unserialize(text);assert(type(value)=="table","配方记录损坏，保留原文件")
 return value
end
local function save(path,record)
 local text=ser.serialize(record,false)
 local f=assert(io.open(path..".tmp","w"))
 assert(f:write(text),"配方记录写入失败");assert(f:flush(),"配方记录刷新失败")
 local closed,reason=f:close();assert(closed~=false and reason==nil,"配方记录关闭失败")
 local check=assert(io.open(path..".tmp","r"));local copy=check:read("*a");check:close()
 assert(copy==text and type(ser.unserialize(copy))=="table","配方记录回读失败")
 local backup
 if fs.exists(path) then
  local n=1;while fs.exists(path..".backup-"..n) do n=n+1 end
  backup=path..".backup-"..n;assert(fs.rename(path,backup),"旧配方记录归档失败")
 end
 local ok,err=fs.rename(path..".tmp",path)
 if not ok then if backup then fs.rename(backup,path) end;error(err or "配方记录保存失败") end
end
local function inspect(p)
 assert(p.isCraftable==false,"仅处理加工样板")
 assert(type(p.inputs)=="table" and type(p.outputs)=="table" and #p.outputs==1,"仅处理单产物加工样板")
 local out=p.outputs[1]
 assert(type(out.name)=="string" and not out.hasTag,"产物标识无效或带NBT，暂不登记")
 local ordinary,fluids={},{}
 local tail=false
 for index,input in ipairs(p.inputs) do
  assert(type(input)=="table" and type(input.name)=="string","输入标识无效")
  if input.name:sub(1,10)=="entangled_" then
   tail=true
   local n=tonumber(input.amount or input.size)
   assert(n and n>0 and n==math.floor(n),"凝聚物数量无效")
   assert(not (input.size and input.amount) or input.size==input.amount,"凝聚物数量字段不一致")
   fluids[#fluids+1]={name=input.name,amount=n,index=index}
  else
   assert(not tail,"凝聚物后还有普通输入，保留样板不处理")
   ordinary[#ordinary+1]=input
  end
 end
 local key=out.name:gsub("[^%w_]","_").."_"..tostring(out.damage or 0).."_"..tostring(out.size or 1)
 return DIR.."/"..key..".dat",ordinary,fluids
end
local function notify(slot,text)
 if announced[slot]~=text then print("槽 "..slot.."："..text);announced[slot]=text end
end
local function process(slot)
 local p=read(slot)
 if p==nil then announced[slot]=nil;return end
 assert(type(p)=="table","样板不可读")
 local path,ordinary,fluids=inspect(p)
 local existing=fs.exists(path) and load(path)
 if #fluids==0 then
  if existing then
   assert(existing.state=="converted" and equal(p.inputs,existing.ordinaryInputs)
    and equal(p.outputs,existing.outputs),"现有样板与登记记录不符，请保留并核对")
   notify(slot,"已转换并登记，无需重复处理")
  else notify(slot,"没有凝聚物输入，也无原始需求记录；不猜测配方") end
  return
 end
 assert(#ordinary>0,"不能移除全部样板输入")
 if existing then
  assert(existing.state=="converted" and equal(existing.original,p),"同产物记录冲突或有未完成转换，保留记录")
  assert(equal(existing.ordinaryInputs,ordinary) and equal(existing.condensates,fluids),"登记需求不一致")
 end
 local name=tostring(p.outputs[1].label or p.outputs[1].name)
 if mode=="preview" then
  print("槽 "..slot.."："..name.."，普通输入 "..#ordinary.." 项，凝聚物 "..#fluids.." 项")
  for _,f in ipairs(fluids) do print("  "..f.name.." "..f.amount.." mB") end
  return
 end
 assert(equal(read(slot),p),"登记前样板已变化")
 local record=existing or {version=1,state="prepared",interface=ADDRESS,slot=slot,
  original=p,ordinaryInputs=ordinary,outputs=p.outputs,condensates=fluids}
 if not existing then assert(fs.makeDirectory(DIR)~=false,"创建配方目录失败");save(path,record) end
 local changed=false
 local ok,err=xpcall(function()
  for i=#fluids,1,-1 do
   local before=read(slot)
   local expected={};for index=1,fluids[i].index do expected[index]=p.inputs[index] end
   assert(type(before)=="table" and before.isCraftable==p.isCraftable and equal(before.inputs,expected)
    and equal(before.outputs,p.outputs),"转换途中样板变化")
   changed=true
   assert(c.invoke(ADDRESS,"clearInterfacePatternInput",slot,fluids[i].index)~=false,"清除凝聚物输入失败")
  end
  local after=read(slot)
  assert(type(after)=="table" and after.isCraftable==p.isCraftable and equal(after.inputs,ordinary) and equal(after.outputs,p.outputs),"转换结果不符")
  if not existing then record.state="converted";save(path,record) end
 end,debug.traceback)
 if not ok then
  if changed then
   local restored,restoreErr=pcall(function()
    local after=read(slot)
    assert(type(after)=="table" and after.isCraftable==p.isCraftable and equal(after.outputs,p.outputs),"样板已被替换，不能自动还原")
    assert(type(after.inputs)=="table" and #after.inputs>=#ordinary and #after.inputs<=#p.inputs,"输入数量变化")
    for i,input in ipairs(after.inputs) do assert(equal(input,p.inputs[i]),"输入内容变化，不能自动还原") end
    for index=#after.inputs+1,#p.inputs do
     local input=p.inputs[index]
     assert(c.invoke(ADDRESS,"setInterfacePatternInput",slot,index,
      {name=input.name,size=input.size or input.amount,amount=input.amount or input.size},"fluid")~=false,"还原失败")
    end
    assert(equal(read(slot),p),"还原核对失败")
   end)
   if not existing then
    record.state=restored and "restored" or "needs_manual_restore"
    record.error=tostring(err);record.restoreError=not restored and tostring(restoreErr) or nil
    pcall(save,path,record)
   end
   error(tostring(err)..(restored and "；原样板已还原" or "；请保留此槽和记录，人工核对"))
  end
  error(err)
 end
 notify(slot,"转换完成并登记："..name)
end
local function main()
 assert(mode=="preview" or mode=="run" or mode=="watch","用法: preview / run / watch")
 local methods=c.methods(ADDRESS)
 for _,m in ipairs({"getInterfacePattern","clearInterfacePatternInput","setInterfacePatternInput"}) do
  assert(methods[m]~=nil,"工作接口缺少方法："..m)
 end
 print("BEC 样板自动处理：工作接口 "..ADDRESS)
 print(mode=="preview" and "只读预览，不修改样板或记录" or "放入原加工样板的副本，自动去除凝聚物输入并保存需求")
 repeat
  for slot=1,9 do
   local ok,err=pcall(process,slot)
   if not ok then notify(slot,"暂停处理："..tostring(err));return end
  end
  if mode~="watch" then break end
  local _,_,char=event.pull(1,"key_down")
  if char==113 or char==81 then break end
 until false
 print("样板处理已结束；转换样板仍在工作接口，需求记录在 "..DIR)
end
local ok,err=xpcall(main,debug.traceback)
if not ok then print("样板服务停止："..tostring(err)) end
]=]},
{"setup_hd.lua",[=[-- A setup-only OCHD page. Never starts production or changes machine outputs.
local c=require('component');local event=require('event');local clock=require('computer')
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local B=assert(loadfile('/home/bec_v2/lib/ochd_bindings.lua'))()
local address,count=nil,0;for a in c.list('hd_panel',true)do address=a;count=count+1 end
assert(count==1,'配置绑定时请只接入一个高清屏幕主组件')
local panel=c.proxy(address)
assert(panel.setPage('bec_dashboard'),'屏幕仍由其他程序占用，请先退出原界面')
local path=C.path('config.dat');local expected=B.read(path)
local cfg=C.read(path)or {version=2,mainInterface='',recipeDirectory='/home/bec_v2/recipes',cacheTarget=144000,
 groups={{name='公共设备组',storage='',gate='',subInterface='',transposer='',mainSide=4,subSide=5,generators={},bulkTransposers={},nanites={enabled=false,mode='cell-io'}}},nodes={}}
local draftPath=C.path('bindings.draft.dat');local rawDraft=B.read(draftPath)
local draft=rawDraft and require('serialization').unserialize(rawDraft)
local function revision()return B.revision((expected or '')..'|'..(rawDraft or ''))end
local notice='可随时暂存草稿，退出查地址后继续；方向可选择，蜂群统一ME-IO。'
local nextPaint=0;local running=true
local ok,err=xpcall(function()
 while running do
  if clock.uptime()>=nextPaint then
   local accepted,reason=panel.update({status='V2 设备配置',stage='setup-only',recipe='设置页 → 设备地址绑定',mode='配置模式',
    controls=false,configEditable=false,bindingEditable=true,bindingDraftEditable=true,bindingRevision=revision(),bindings=B.draftFields(cfg,draft,expected),logs={notice}})
   assert(accepted~=nil,reason);nextPaint=clock.uptime()+(accepted and 2 or 0.6)
  end
  local e={event.pull(0.1)}
  if e[1]=='key_down'and(e[3]==113 or e[3]==81)then running=false end
  if e[1]=='hd_panel_action'and e[2]==address then
   if e[3]=='binding_save'or e[3]=='binding_draft'then
    local applying=e[3]=='binding_save';local submittedRevision=revision()
    local success,result=pcall(function()
     rawDraft=B.saveDraft(C,cfg,e[7],e[5],expected,rawDraft,submittedRevision)
     draft=require('serialization').unserialize(rawDraft)
     if applying then
      cfg=B.saveV2(C,cfg,e[7],e[5],expected,submittedRevision)
      expected=B.read(path)
      -- A completed binding has a new base; old draft is ignored until replaced.
      notice='绑定已应用；退出配置页后再启动V2。'
     else notice='草稿已暂存，可退出查地址，回来继续填写。'end
    end)
    if not success then notice=tostring(result)..'（已成功暂存的内容会保留）'end
    -- Carry the new compare-and-swap revision in the acknowledgement.
    panel.ack(e[5],success,'[rev:'..revision()..'] '..notice);nextPaint=0
   elseif e[3]=='refresh'then panel.ack(e[5],true,'配置页在线');nextPaint=clock.uptime()+0.6
   else panel.ack(e[5],false,'此页面只配置地址，不启动或控制生产')end
  end
 end
end,debug.traceback)
pcall(panel.release)
assert(ok,err)
]=]},
{"START_HERE.txt",[=[高速供液转运器每组01–10，未接的留空；已有网页版用update_bulk10.lua升级。
OCHD HTML支持alpha7/alpha8；删除与滚轮修复需要alpha8客户端输入补丁，见WEB_INPUT.md。
BEC V2 全新安装 / OpenOS

OCHD 三维绑定与自动化流程（开发预览）：
lua /home/bec_v2/main.lua web
连接 OCHD 时无参数运行 main.lua 也会打开此页。
点击机器填写地址自动暂存；应用绑定校验后再启动。Q 退出并暂停。
显示阶段/批次时间、机器回读和磁盘空间；剩余不足512KiB停止接单。
当前未实机验证，不用于无人值守；原加工样板仍需按下方步骤登记。

普通屏配置：lua /home/bec_v2/main.lua setup
OCHD配置：lua /home/bec_v2/main.lua setup-hd

新用户必须从原加工样板副本登记需求，不直接使用缺少需求记录的已转换样板。
配置完先pause，等待纠缠器停稳，将原样板副本放入工坊接口。

lua /home/bec_v2/main.lua pause
lua /home/bec_v2/main.lua patterns preview
lua /home/bec_v2/main.lua patterns run

将转换后样板移到生产接口，再monitor核对；Q退出监控后run启动。
lua /home/bec_v2/main.lua monitor
lua /home/bec_v2/main.lua run

日志上传可选：lua /home/bec_v2/main.lua reports
使用自己的仓库和仅该仓库Contents读写token，不分享凭据。

完整接线和分享说明：
https://github.com/Alivn-chao/gtnh-bec-automation/tree/bec-v2-bulk10-2026-10-17/reinstall_v2

配置和安装不会开机；pause和run会控制机器。约束场始终保持开启。
不同时运行V1/V2控制同一设备。全部V2数据保留在/home/bec_v2。
]=]},
{"web.lua",[=[local c=require('component');local event=require('event');local clock=require('computer')
local ROOT='/home/bec_v2'
local function module(n)return assert(loadfile(ROOT..'/lib/'..n..'.lua'))()end
local C,B,W=module('config'),module('ochd_bindings'),module('web_json')
local address,count=nil,0;for a in c.list('hd_panel',true)do address=a;count=count+1 end
assert(count==1,'请只连接一面 OCHD 屏幕墙的主组件')
local methods=c.methods(address)
assert(methods.setWebApp~=nil and methods.publish~=nil,'需要支持 HTML 页面的 OCHD alpha7 或兼容版 JAR')
local f=assert(io.open(C.path('lib/web_page.html'),'r'));local page=f:read('*a');f:close()
local package={id='bec-v2-studio',title='BEC V2 结构绑定与运行',entry='index.html',files={['index.html']=page},
 events={'save_field','apply_bindings','start','pause','select_group','refresh'}}
local panel=c.proxy(address);local H=module('web_session')(C,B,W)
local ok,err=xpcall(function()
 while true do local accepted,reason=panel.setWebApp(package);assert(accepted~=nil,reason);if accepted then break end;event.pull(.6)end
 print('OCHD 已显示结构绑定与流程图。右键屏幕操作；OC 按 Q 退出并暂停。')
 local running,nextPush=true,0
 while running do
  H.step()
  if clock.uptime()>=nextPush then
   local accepted,reason=panel.publish(H.snapshot());assert(accepted~=nil,reason)
   nextPush=clock.uptime()+(accepted and 2 or .6)
  end
  local e={event.pull(.05)}
  if e[1]=='key_down'and(e[3]==113 or e[3]==81)then running=false end
  if e[1]=='hd_panel_web'and e[2]==address then
   local success,message=pcall(function()return H.handle(e[3],W.decode(e[6]),e[5])end)
   if not success then H.notice=tostring(message)end
   panel.ack(e[5],success,tostring(message));nextPush=clock.uptime()+.6
  end
 end
end,debug.traceback)
local errors=H.close();for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
pcall(function()panel.release()end)
assert(ok,err);assert(#errors==0,'暂停存在回读失败，请核对机器')
]=]}
}
-- Clean install only. OpenOS must already be installed on the disk.
local fs=require('filesystem')
local ROOT='/home/bec_v2'
assert(not fs.exists(ROOT),'已有 /home/bec_v2；这是全新安装器，不覆盖配置/日志。请保留原目录并使用升级流程。')
local stage='/home/.bec-v2-new-1'
local sequence=1
while fs.exists(stage)do sequence=sequence+1;stage='/home/.bec-v2-new-'..sequence end
assert(fs.makeDirectory(stage),'无法建立安装临时目录')
local written={}
local function read(path)
 local f=assert(io.open(path,'r'));local s=f:read('*a');f:close();return s
end
local function clean()
 for i=#written,1,-1 do pcall(fs.remove,stage..'/'..written[i])end
 for _,d in ipairs({'runtime','lib','recipes'})do pcall(fs.remove,stage..'/'..d)end
 pcall(fs.remove,stage)
end
local ok,reason=pcall(function()
 for _,dir in ipairs({'lib','runtime','recipes'})do assert(fs.makeDirectory(stage..'/'..dir),'建立目录失败')end
 for _,entry in ipairs(FILES)do
  local name,source=entry[1],entry[2]
  if name:sub(-4)=='.lua'then assert(load(source,'@'..ROOT..'/'..name,'t',_ENV),'Lua语法检查失败：'..name)end
  local path=stage..'/'..name
  written[#written+1]=name
  local f=assert(io.open(path,'w'),'磁盘空间不足或无法写入：'..name)
  assert(f:write(source),'写入失败：'..name);assert(f:flush(),'刷新失败：'..name)
  local closed,err=f:close();assert(closed~=false and err==nil,'关闭文件失败：'..name)
  assert(read(path)==source,'回读不符：'..name)
 end
 assert(not fs.exists(ROOT),'安装期间目标目录发生变化，保留现场')
 assert(fs.rename(stage,ROOT),'发布安装目录失败')
end)
if not ok then clean();error('安装未完成，未启动机器：'..tostring(reason))end
print('BEC V2 完整安装完成：/home/bec_v2')
print('普通屏配置：lua /home/bec_v2/main.lua setup')
print('OCHD配置：lua /home/bec_v2/main.lua setup-hd')
print('入门说明：edit /home/bec_v2/START_HERE.txt')
print('尚未绑定、搬料、下单或启动生产。')
