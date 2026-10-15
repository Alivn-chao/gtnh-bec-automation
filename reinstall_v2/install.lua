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
   assert(not entry.finished or state=='idle','已完成节点提前接到新订单，保持整组暂停')
   if type(current)=='table' and next(current) then
    local p=c.invoke(address,'getParallelRecipesInProgress');assert(type(p)=='number' and p>0,'节点并行不可读')
    local normalized={};for key,value in pairs(current)do normalized[key]=value/p end
    for key,value in pairs(task.normalized)do assert(normalized[key]==value,'生产组出现不同配方，保持暂停')end
    for key,value in pairs(normalized)do assert(task.normalized[key]==value,'生产组配方类型变化')end
    if not entry.finished then
     assert(not task.released or p==entry.parallel,'组内节点批量变化，暂停核对')
     entry.required=current;entry.parallel=p
    end
   end
   local consumed=c.invoke(address,'getConsumedCondensate') or {}
   entry.consumed=entry.consumed or {}
   for key,value in pairs(consumed)do entry.consumed[key]=math.max(entry.consumed[key] or 0,value)end
   local needed=c.invoke(address,'getRequiredTier');needed=type(needed)=='table' and needed.tier or needed
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
   methods(n.address,{'getState','getRequiredTier','getRequiredCondensate','getParallelRecipesInProgress'},'传送节点')
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
 -- BEC_V2_GITHUB_REPORTS_V1
 local reports
 if not monitor then
  local ok,result=pcall(function()return assert(loadfile(C.path("lib/reports.lua")))()(cfg,C)end)
  reports=ok and result or {status="报告初始化失败，生产日志保留",step=function()end,close=function()end,capture=function()end}
 end
 E.reports=reports
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
 function E.pauseNode(i)
  assert(not monitor,'只读监控不能修改机器')
  local group=cfg.nodes[i].group
  local errors={}
  for j,n in ipairs(cfg.nodes)do if n.group==group then
   local t=E.tasks[j];t.disabled=true;t.cancel=true
   local ok,reason=pcall(pause,j);if not ok then errors[#errors+1]=tostring(reason)end
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
  if t.fault or t.cancel then
   for _,a in ipairs(cfg.groups[group].generators)do pcall(c.invoke,a,'setWorkAllowed',false)end
   for j,n in ipairs(cfg.nodes)do if n.group==group then
    E.tasks[j].disabled=true;E.tasks[j].status=t.fault and '同组故障，需核对' or '整组暂停';pcall(pause,j)
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
  local req=c.invoke(n.address,'getRequiredCondensate');local p=c.invoke(n.address,'getParallelRecipesInProgress')
  if (state~='paused-immediate' and state~='nanite-tier-too-low')or type(req)~='table'or not next(req)then return end
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
  if reports then
   reports.step()
   if E.reportStatus~=reports.status then E.reportStatus=reports.status;E.log(1,reports.status)end
  end
  for i,t in ipairs(E.tasks)do if t.co and (t.cancel or t.waitKind=='lock'and(not E.fluidOwner or E.fluidOwner==i)or t.waitKind~='lock'and clock.uptime()>=(t.deadline or 0))then advance(i)end end
  for group in ipairs(cfg.groups)do if not E.groupOwner[group]then
   local saved=C.read(cohortPath(group));local unfinished=saved and saved.stage~='stopped'
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
      for _,j in ipairs(t.members)do if j~=i then E.tasks[j].status='同配方物理并行'end end
      E.groupOwner[group]=i
      require('filesystem').makeDirectory(C.path('state/node-'..i))
      C.write(cohortPath(group),{version=2,stage='working',leader=i,members=t.members,entries=t.entries,normalized=t.normalized})
      t.co=coroutine.create(function()E.acquire(i);Bridge.environment(cfg,i,E)(journal and 'resume'or 'run')end)
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
{"lib/ochd_bindings.lua",[=[-- Strict data-only binding editor shared by the V1 monitor and V2 setup page.
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
function M.parse(payload,fields,revision)
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
  if v~=''then
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
  for j=1,math.max(5,#(g.bulkTransposers or {}))do field(out,prefix..'bulk'..j,title..'高速供液口'..j..'（可空）',(g.bulkTransposers or {})[j])end
  local n=g.nanites or {}
  field(out,prefix..'beeMode',title..'蜂群模式',n.mode or 'cell-io','mode')
  for _,key in ipairs({'transposer','loadRedstone','returnRedstone','supplyInterface','hatchInterface'})do
   local label=({transposer='转运器',loadRedstone='装入红石',returnRedstone='回收红石',supplyInterface='备用ME接口（旧模式）',hatchInterface='收容ME接口（旧模式）'})[key]
   field(out,prefix..'bee_'..key,title..'蜂群 · '..label,n[key])
  end
  for _,row in ipairs({{'bankSide',0},{'loadSide',3},{'returnSide',2},{'loadOutputSide',0},{'returnOutputSide',0},{'supplySide',2},{'hatchSide',4}})do
   field(out,prefix..'bee_'..row[1],title..'蜂群 · '..row[1],n[row[1]]or row[2],'side')
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
 assert(#out<=512,'绑定字段超过页面容量');return out
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
  g.bulkTransposers={};for j=1,math.max(5,#(cfg.groups[i].bulkTransposers or {}))do local v=values[p..'bulk'..j];if v~=''then g.bulkTransposers[#g.bulkTransposers+1]=v end end
  local n={mode=values[p..'beeMode']};g.nanites=n
  for _,key in ipairs({'transposer','loadRedstone','returnRedstone','supplyInterface','hatchInterface'})do n[key]=values[p..'bee_'..key]~=''and values[p..'bee_'..key]or nil end
  for _,key in ipairs({'bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide','supplySide','hatchSide'})do n[key]=tonumber(values[p..'bee_'..key])end
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
function M.saveV2(C,cfg,payload,request,expected)
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
 local next=M.applyV2(cfg,payload,M.revision(expected));C.validate(next,true)
 for _,n in ipairs(next.nodes)do
  local state=c.invoke(n.address,'getState')
  assert(state=='idle'or(state=='paused-immediate'or state=='nanite-tier-too-low')and c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'先停止生产再改绑定')
 end
 for _,g in ipairs(next.groups)do for _,a in ipairs(g.generators)do assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'纠缠器须先停止活动')end end
 unfinished();return next,M.commit(C.path('config.dat'),next,expected,request)
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
{"main.lua",[=[local ROOT='/home/bec_v2'
local function module(name)return assert(loadfile(ROOT..'/lib/'..name..'.lua'))()end
local C=module('config')
local mode,option=...
mode=mode or 'monitor'
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
end local function save(stage) record.stage = stage if fs.exists(JOURNAL) then
local f = assert(io.open(JOURNAL, "r")) local old = f:read("*a"); f:close() writeVerified(JOURNAL .. ".previous", old) end
writeVerified(JOURNAL, ser.serialize(record, false)) end local function pause(value) call(RS, "setOutput", sides.top, value)
assert(call(RS, "getOutput", sides.top) == value, "红石输出回读不符") end local function generator(enabled) call(GEN, "setWorkAllowed", enabled)
assert(call(GEN, "isWorkAllowed") == enabled, "纠缠装置启停回读不符") end local function switchNanites()
local needed=call(NODE,"getRequiredTier");needed=type(needed)=="table" and needed.tier or needed
if type(needed)~="number" then return end
NANITES.ensure({tick=tick,stopping=function() return stopping end})
local provided=call(NODE,"getProvidedTier")
assert(type(provided)=="table" and provided.tier>=needed and integer(call(NODE,"getAvailableNanites"))>=64,"蜂群等级或数量不足，保持暂停")
lastNaniteTier=needed
end local function gateFilters(required) assert(type(required)=="table","门过滤需求不可读")
local result={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0,"门过滤需求无效: "..tostring(name)) result[#result+1]=name
end table.sort(result) assert(#result>0,"禁止写入全空过滤；全空会放行全部凝聚物") return result
end local function verifyGate(expected) local count=integer(call(GATE,"getCondensateFilterCount")) assert(count>=#expected,"麦克斯韦门过滤槽不足")
local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table" and same(actual,expected), "麦克斯韦门过滤回读不符；检查门的流体输入仓是否自动覆盖 OC 过滤") assert(call(GATE,"isWorkAllowed")==true,"麦克斯韦门未启用，保持暂停")
assert(call(GATE,"isMachineActive")==true,"麦克斯韦门未运行；检查结构和供电，保持暂停") end local function configureGate(required) assert(call(RS,"getOutput",sides.top)==15 and call(NODE,"getState")=="paused-immediate",
"切换门过滤前节点必须立即暂停") local expected=gateFilters(required) assert(integer(call(GATE,"getCondensateFilterCount"))>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters")
assert(type(actual)=="table","麦克斯韦门过滤不可读") record.gateIntent={address=GATE,filters=expected};save(record.stage) if not same(actual,expected) then call(GATE,"setCondensateFilters",expected) end for i=1,3 do
verifyGate(expected) assert(call(NODE,"getState")=="paused-immediate","设置过滤时订单状态变化") if i<3 then tick(0.1) end end
print("麦克斯韦门过滤: "..table.concat(expected,", ")) return expected end local function tanks(side, name)
local count, amount = integer(call(TRANS, "getTankCount", side)), 0 assert(count > 0, "接口没有流体槽") for i = 1, count do local f = call(TRANS, "getFluidInTank", side, i)
assert(type(f) == "table", "接口缓存不可读") if type(f[1]) == "table" then f = f[i] or f[1] end local n = integer(f.amount or 0) if n > 0 then
assert(name and f.name == name, "接口有未处理流体缓存") amount = amount + n end end
return amount end local function emptyConfig() for slot = 0, 5 do
assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置") end end local function current(recovering)
local state=call(NODE,"getState") local unavailable=state=="assembler-offline" or state=="unpowered" or state=="nanite-tier-too-low" assert(state=="paused-immediate" or (recovering and unavailable and call(RS,"getOutput",sides.top)==15),"订单未处于立即暂停状态")
local parallel=integer(call(NODE, "getParallelRecipesInProgress")) assert(parallel>=1,"暂停节点没有正在处理的配方") local required, consumed = call(NODE, "getRequiredCondensate"), call(NODE, "getConsumedCondensate") assert(type(required) == "table" and type(consumed) == "table", "订单需求不可读")
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
local round=0 while not stopping do pause(15); generator(false) local state=call(NODE,"getState")
if stopping then break end state=call(NODE,"getState") if state=="paused-immediate" or state=="nanite-tier-too-low" then switchNanites();state=call(NODE,"getState") end if waiting[state] then
if state~=record.lastState then print("等待订单/机器就绪: "..state.."；任意数量同配方订单均可，按 Q 停止。") record.lastState=state;save("waiting") end
field();tick(0.1) else waitUntil(10,function() local v=call(NODE,"getState")
return v=="paused-immediate",v end,function(v) assert(v=="crafting" or waiting[v],"无法暂停，实际状态: "..tostring(v)) field()
end) switchNanites();if stopping then break end record.required,record.remaining=current() local target,count=batchTarget(record.required,record.remaining) local stable=false
for i=1,20 do tick(0.25);unchanged() local nextTarget,nextCount=batchTarget(record.required,record.remaining) if same(target,nextTarget) then stable=true;break end
target,count=nextTarget,nextCount end assert(stable,"主网任务清单持续变化，保持暂停") if stopping then break end
record.batchCount=count print("本组当前配方 "..count.." 份；当前实际并行 "..checkRecipe(record.required) .."；一次准备整批所需流体。") round=round+1;record.round=round;record.transfers={};record.target=target;record.plan=nil;record.topups={}
waitUntil(10,function() return call(GEN,"isMachineActive")==false end) emptyConfig();tanks(4,nil);tanks(5,nil) local filters=configureGate(record.required) unchanged()
if stopping then break end local expected=prepareStreaming(target) if stopping then break end for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end
save("converting");generator(true) local conversionLimit=180 for name,need in pairs(target) do conversionLimit=conversionLimit+math.ceil(need/(units[name] or 144))*180 end waitUntil(conversionLimit,function()
local stock=field() for name,need in pairs(target) do if (stock[name] or 0)<need then return false end end return true end,unchanged)
unchanged();generator(false) record.plan=nil;record.lastState=nil;save("watching") if not stopping then verifyGate(filters);unchanged()
pause(0) print("整批流体齐备，已连续放行；本组同配方节点已同时放行。按 Q 停止。") local releasedAt=computer.uptime() local deadline=releasedAt+600
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
local function bank(size)
 local cells={}
 local ok,rows=pcall(function()
  if c.methods(T).getAllStacks==nil then return end
  local reader=call(T,'getAllStacks',0)
  assert(reader.count()==size,'批量槽数不符')
  local values=reader.getAll();assert(type(values)=='table')
  for index in pairs(values) do assert(whole(index) and index>=1 and index<=size,'批量槽号不符') end
  return values
 end)
 if not ok then rows=nil end
 for slot=1,size do
  local item
  if rows then
   item=rows[slot]
   if type(item)=='table' and item.name==nil then item=nil end
   if item and (item.storedItemCount==nil or type(item.getAvailableItems)~='table') then item=stack(0,slot) end
  else item=stack(0,slot) end
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
  for slot=7,12 do local item=stack(side,slot);if item then
   assert(not at,'IO输出口出现多张盘');at=slot;n,row=describe(item)
  end end
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
 print('蜂群IO：装入侧'..cfg.loadSide..'，回收侧'..cfg.returnSide..'，硬盘盒侧'..cfg.bankSide..' / '..size..'槽；整盘搬运')
 print('仓内：'..h..' 个 / T'..tostring(p and p.tier)..'；需求T'..tostring(needed()))
 for _,disk in ipairs(cells) do if disk.item then
  print('盘槽 '..disk.slot..'：T'..disk.item.tier..' / '..disk.count..' 个 / '..disk.item.label)
 end end
 local r=oldRecord();print('蜂群IO日志：'..tostring(r and r.stage or '无')..'；旧接口日志不重放')
 emptyPorts()
end
function M.ensure(ctx)
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
local notice='打开设置页 → 设备地址绑定；支持 Ctrl+V 粘贴。保存不会启动生产。'
local nextPaint=0;local running=true
local ok,err=xpcall(function()
 while running do
  if clock.uptime()>=nextPaint then
   local accepted,reason=panel.update({status='V2 设备配置',stage='setup-only',recipe='设置页 → 设备地址绑定',mode='配置模式',
    controls=false,configEditable=false,bindingEditable=true,bindingRevision=B.revision(expected),bindings=B.v2Fields(cfg),logs={notice}})
   assert(accepted~=nil,reason);nextPaint=clock.uptime()+(accepted and 2 or 0.6)
  end
  local e={event.pull(0.1)}
  if e[1]=='key_down'and(e[3]==113 or e[3]==81)then running=false end
  if e[1]=='hd_panel_action'and e[2]==address then
   if e[3]=='binding_save'then
    local success,result,backup=pcall(B.saveV2,C,cfg,e[7],e[5],expected)
    if success then cfg=result;expected=B.read(path);notice='绑定配置已保存；退出配置页后再正常启动V2。'else notice=tostring(result)end
    panel.ack(e[5],success,notice);nextPaint=clock.uptime()+0.6
   elseif e[3]=='refresh'then panel.ack(e[5],true,'配置页在线');nextPaint=clock.uptime()+0.6
   else panel.ack(e[5],false,'此页面只配置地址，不启动或控制生产')end
  end
 end
end,debug.traceback)
pcall(panel.release)
assert(ok,err)
]=]},
{"START_HERE.txt",[=[BEC V2 全新安装 / OpenOS

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
https://github.com/Alivn-chao/gtnh-bec-automation/tree/bec-v2-clean-2026-10-15/reinstall_v2

配置和安装不会开机；pause和run会控制机器。约束场始终保持开启。
不同时运行V1/V2控制同一设备。全部V2数据保留在/home/bec_v2。
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
