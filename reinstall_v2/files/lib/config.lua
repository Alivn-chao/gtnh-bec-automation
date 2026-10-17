local c=require('component')
local fs=require('filesystem')
local ser=require('serialization')
local M={ROOT='/home/bec_v2'}
-- Keep a web lease alive between callbacks; never mutate global component.
function M.component(native)
 local proxy={};for k,v in pairs(native)do proxy[k]=v end
 setmetatable(proxy,{__index=native})
 for _,name in ipairs({'invoke','methods','list'})do
  proxy[name]=function(...)
   if not M.pulse then return native[name](...)end
   M.pulse();local values=table.pack(native[name](...))
   if name=='invoke'then M.pulse(false,select(1,...),select(2,...),values[1])else M.pulse()end
   return table.unpack(values,1,values.n)
  end
 end
 return proxy
end
c=M.component(c)
function M.path(name) return M.ROOT..'/'..name end
function M.read(path)
 if M.pulse then M.pulse()end
 local f=io.open(path,'r');if not f then return nil end
 local text=f:read('*a');f:close();if M.pulse then M.pulse()end
 local value=ser.unserialize(text);assert(type(value)=='table','配置/记录损坏: '..path)
 return value
end
function M.write(path,value)
 if M.pulse then M.pulse()end
 local text=ser.serialize(value,false)
 local dir=fs.path(path);assert(fs.exists(dir) or fs.makeDirectory(dir),'无法建立目录')
 local old=io.open(path,'r')
 if old then
  local previous=old:read('*a');old:close();local backup=assert(io.open(path..'.previous','w'))
  assert(backup:write(previous));assert(backup:flush());backup:close();if M.pulse then M.pulse()end
 end
 local file=assert(io.open(path,'w'));assert(file:write(text));assert(file:flush());file:close();if M.pulse then M.pulse()end
 file=assert(io.open(path,'r'));local actual=file:read('*a');file:close();assert(actual==text,'配置回读失败')
end
local function integer(n,lo,hi) return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi end
local function address(a,label) assert(type(a)=='string' and #a>0,label..' 未绑定') end
local function methods(a,list,label)
 address(a,label);local ok,m,reason=pcall(c.methods,a)
 assert(ok,label..' 方法列表读取失败 ['..a..']: '..tostring(m))
 assert(type(m)=='table',label..' 不在线，OC查不到组件 ['..a..']: '..tostring(reason))
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
   methods(g.storage,{'getStoredCondensate','isWorkAllowed'},'设备组'..i..' 约束场')
   assert(c.invoke(g.storage,'isWorkAllowed')==true,'约束场须保持开启')
   methods(g.subInterface,{'getFluidsInNetwork'},'设备组'..i..' 原液子网接口')
   methods(g.transposer,{'transferFluid','getFluidInTank'},'设备组'..i..' 供液转运器')
   for _,a in ipairs(g.bulkTransposers or {})do methods(a,{'transferFluid','getFluidInTank'},'高速供液转运器')end
   for j,a in ipairs(g.generators) do
    methods(a,{'setWorkAllowed','isWorkAllowed','isMachineActive'},'设备组'..i..' 纠缠器'..j)
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
