-- BEC_RELEASE_290_UPDATE_1
local SELF_SIGNATURE='44751:2405943513'
print('BEC GTNH 2.9.0 compatibility; finish all batches and press Q first')
local rows={{name='lib/config.lua',source=[=[local c=require('component')
local fs=require('filesystem')
local ser=require('serialization')
local M={ROOT='/home/bec_v2'}
-- OC 1.12.68 / Computronics 1.9.13 enqueue these setters on the server.
-- Keep the caller's single write and confirm only when it asks for readback.
-- This is in-memory coordination; durable intents remain owned by callers.
local queued={}
local readback={setMinParallel='getMinParallel',setMaxParallel='getMaxParallel',
 setWorkAllowed='isWorkAllowed',setCondensateFilters='getCondensateFilters'}
local function equal(a,b)
 if type(a)~='table'or type(b)~='table'then return a==b end
 for k,v in pairs(a)do if b[k]~=v then return false end end
 for k,v in pairs(b)do if a[k]~=v then return false end end;return true
end
-- Keep a web lease alive between callbacks; never mutate global component.
function M.component(native)
 local proxy={};for k,v in pairs(native)do proxy[k]=v end
 setmetatable(proxy,{__index=native})
 for _,name in ipairs({'invoke','methods','list'})do
  proxy[name]=function(...)
   if M.pulse then M.pulse()end
   local address,method=...;local key=name=='invoke'and type(address)=='string'and type(method)=='string'and(address..'\0'..method)
   local pending=key and queued[key]
   local values=table.pack(native[name](...))
   local getter=name=='invoke'and readback[method]
   if getter then
    local expected=select(3,...)
    if type(expected)=='table'then local copy={};for k,v in pairs(expected)do copy[k]=v end;expected=copy end
    queued[address..'\0'..getter]={expected=expected}
   end
   local function pulse()
    if M.pulse then if name=='invoke'then M.pulse(false,address,method,values[1])else M.pulse()end end
   end
   pulse()
   if pending then
    local clock=require('computer');local deadline=clock.uptime()+5
    for poll=1,101 do
     -- A pause handled by the heartbeat may have superseded this write.
     -- Read its actual result; never wait for or reissue the old target.
     if queued[key]~=pending then values=table.pack(native[name](...));break end
     if equal(values[1],pending.expected)then queued[key]=nil;break end
     local label=method=='isWorkAllowed'and '启停回读不符'or '服务器写入回读尚未确认'
     assert(poll<=100 and clock.uptime()<deadline,label..'：'..method..'；保留意图，不重复下发')
     local wait=M.wait or os.sleep;wait(.05)
     values=table.pack(native[name](...));pulse()
    end
   end
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
  if g.cellFeed and g.cellFeed.enabled then
   local f=g.cellFeed;address(f.transposer,'原料盘转运器')
   assert(not resources[f.transposer],'原料盘转运器不能与供液/蜂群共用');resources[f.transposer]=true
   assert(integer(f.sourceSide,0,5)and integer(f.productionSide,0,5)and f.sourceSide~=f.productionSide,'原料驱动器方向无效')
   assert(integer(f.sourceSlot,1,10)and integer(f.productionSlot,1,10),'原料盘槽位无效')
   assert(integer(f.collectSeconds,1,60),'攒料时间需为1到60秒')
   assert(f.maxParallelPerNode==nil or integer(f.maxParallelPerNode,1,2147483647),'节点自动并行上限无效')
   assert(f.representativeChecks==nil or type(f.representativeChecks)=='boolean','代表节点检查设置无效')
   assert(f.concurrentAdmission==nil or type(f.concurrentAdmission)=='boolean','同时接单设置无效')
   if live then
    methods(f.transposer,{'transferItem','getStackInSlot','getInventoryName','getInventorySize'},'原料盘转运器')
    for _,side in ipairs({f.sourceSide,f.productionSide})do assert(c.invoke(f.transposer,'getInventoryName',side)=='tile.appliedenergistics2.BlockDrive'and c.invoke(f.transposer,'getInventorySize',side)==10,'原料两侧必须是ME驱动器')end
   end
  end
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
    if cfg.groups[n.group].cellFeed and cfg.groups[n.group].cellFeed.enabled then
     methods(n.address,{'setMinParallel','setMaxParallel','getMinParallel','getMaxParallel','getConsumedCondensate'},'原料批次节点')
     if cfg.groups[n.group].cellFeed.representativeChecks then methods(n.address,{'getWorkProgress','getRecipeSteps'},'代表节点阶段同步')end
    end
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
]=],supported={['9700:2693798100']=true}},{name='lib/cell_feed.lua',source=[=[-- Frozen storage-cell batches. Never replay an uncertain move or admission.
local component=require('component')
local clock=require('computer')
local fs=require('filesystem')
local M={}
local function whole(n)return type(n)=='number'and n>=0 and n%1==0 and n<=9007199254740991 end
local function key(v)
 assert(type(v)=='table'and type(v.name)=='string','物品标识不可读')
 assert(not v.hasTag,'原料含NBT，尚不支持自动配方匹配')
 return v.name..':'..tostring(v.damage or 0)
end
local function itemMap(list)
 local result={}
 for _,v in pairs(list)do local n=v.size or v.amount;assert(whole(n)and n>0,'原料数量无效或含非消耗输入');local k=key(v);result[k]=(result[k]or 0)+n end
 return result
end
function M.describe(cell)
 assert(type(cell)=='table'and cell.size==1 and whole(cell.storedItemCount)and type(cell.getAvailableItems)=='table','存储盘内容不可读')
 local items=itemMap(cell.getAvailableItems);local total=0;for _,n in pairs(items)do total=total+n end
 assert(total==cell.storedItemCount,'盘内总数与清单不符');return items,total
end
function M.match(items,recipes)
 local found,count
 for _,r in ipairs(recipes)do
  local n,ok=nil,true
  for k,unit in pairs(r.items)do local v=items[k];if not v or v%unit~=0 then ok=false;break end;local q=v/unit;if n and n~=q then ok=false;break end;n=q end
  for k in pairs(items)do if not r.items[k]then ok=false end end
  if ok and n and n>=1 then assert(not found,'相同原料对应多份登记，不能猜测配方');found=r;count=n end
 end
 assert(found,'盘内原料未匹配到唯一完整登记配方，保持暂停');return found,count
end
function M.allocate(total,limits)
 assert(whole(total)and total>0,'批次份数无效')
 local quota={};local left=total
 for _,n in ipairs(limits)do assert(whole(n.max)and n.max>0);quota[n.index]=0 end
 while left>0 do
  local available={};for _,n in ipairs(limits)do if quota[n.index]<n.max then available[#available+1]=n end end
  assert(#available>0,'本批超过16台单轮并行容量，保留原料盘；请拆小批次')
  for pos,n in ipairs(available)do local portion=math.ceil(left/(#available-pos+1));local add=math.min(portion,n.max-quota[n.index],left);quota[n.index]=quota[n.index]+add;left=left-add end
 end
 return quota
end
function M.new(cfg,group,C,E,resumeAdmission)
 local settings=cfg.groups[group].cellFeed
 if not(settings and settings.enabled)then return end
 local c=C.component and C.component(component)or component
 local F={ready=false,message='等待缓存盘进料',nextPoll=0}
 local path=C.path('state/group-'..group..'/cell-feed.journal')
 local old=C.read(path)
 local resumeReady=resumeAdmission=='ready'and old and old.stage=='ready'
 assert(not old or old.stage=='stopped'or resumeReady and not old.pending or resumeAdmission==true and old.stage=='waiting-node'and not old.pending,'原料盘有未完成批次，请保留记录核对，禁止自动重放')
 local cohort=C.read(C.path('state/group-'..group..'/cohort.dat'))
 assert(not cohort or cohort.stage=='stopped'or resumeReady and(cohort.stage=='working'or cohort.stage=='interrupted'),'整组有旧生产记录，禁止搬入新原料盘')
 for i,n in ipairs(cfg.nodes)do if n.group==group then
  local j=C.read(C.path('state/node-'..i..'/production.journal'))
  assert(not j or (j.stage=='stopped'or resumeReady and cohort and i==cohort.leader and j.stage=='watching'and not j.plan)and not j.pending and j.configOwned==false,'节点存在未完成生产记录，禁止新批次')
  if resumeReady then for _,v in ipairs(j and j.transfers or{})do assert(v.ok==true,'旧生产搬运未确认')end end
  for _,job in ipairs(j and j.requests or {})do assert(job.state=='done','节点旧AE请求未确认')end
 end end
 local recipes={}
 for file in fs.list(cfg.recipeDirectory)do if file:match('%.dat$')then
  local r=C.read(cfg.recipeDirectory..'/'..file)
  if r and r.state=='converted'and type(r.ordinaryInputs)=='table'and #r.ordinaryInputs>0 then
   local ok,items=pcall(itemMap,r.ordinaryInputs)
   if ok then recipes[#recipes+1]={file=file,items=items,condensates=r.condensates,outputs=r.outputs}end
  end
 end end
 local function call(m,...)return c.invoke(settings.transposer,m,...)end
 local function stack(side,slot)return call('getStackInSlot',side,slot)end
 local record
 local function save(stage)record.stage=stage;C.write(path,record)end
 local function members()
  local result={};for i,n in ipairs(cfg.nodes)do if n.group==group then result[#result+1]=i end end;return result
 end
 local ids=members()
 local function enabled()
  for _,i in ipairs(ids)do if E.tasks[i].disabled or E.tasks[i].fault then
   -- No hardware intent exists yet at this checkpoint. A pause received by
   -- C.write's heartbeat must not leave a phantom unfinished batch.
   if record and record.stage=='capturing'and not record.pending then save('stopped');record=nil;F.since=nil end
   error('原料批次已暂停，保留记录')
  end end
 end
 local function pause(n)
  if c.invoke(n.redstone,'getOutput',n.pauseSide)==15 then return end
  c.invoke(n.redstone,'setOutput',n.pauseSide,15)
  assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'暂停输出回读失败')
 end
 local function closeAll()for _,i in ipairs(ids)do pause(cfg.nodes[i]);E.nodeWork(i,false)end end
 local function captureReady()
  for _,i in ipairs(ids)do local n=cfg.nodes[i]
   local allowed=c.invoke(n.address,'isWorkAllowed');assert(type(allowed)=='boolean','接单许可不可读')
   if allowed then
    if c.invoke(n.address,'getState')~='idle'then return false end
    E.nodeWork(i,false)
   end
   -- Read state AFTER closing admission. Idle cannot admit another recipe
   -- until this controller explicitly reopens it later in the transaction.
   if c.invoke(n.address,'getState')~='idle'then return false end
   pause(n)
  end
  return true
 end
 local bulkSupported
 local function inventory(side)
  if bulkSupported==nil then local ok,methods=pcall(c.methods,settings.transposer);bulkSupported=ok and type(methods)=='table'and methods.getAllStacks~=nil end
  if bulkSupported then
   local ok,rows=pcall(function()
    local view=call('getAllStacks',side);assert(view.count()==10)
    local all=view.getAll();assert(type(all)=='table');local out={}
    -- OC Inventory.getAll() is zero-indexed, including empty slot tables.
    for slot=1,10 do local v=all[slot-1];assert(type(v)=='table')
     if v.name~=nil then assert(type(v.name)=='string'and type(v.size)=='number'and v.size>0);out[slot]=v end
    end
    return out
   end)
   if ok then return rows end;bulkSupported=false
  end
  local rows={};for slot=1,10 do rows[slot]=stack(side,slot)end;return rows
 end
 local function idleClosed()
  for _,i in ipairs(ids)do local n=cfg.nodes[i]
   assert(c.invoke(n.address,'getState')=='idle'and c.invoke(n.address,'isWorkAllowed')==false,'整组未空闲关闭接单，禁止搬盘')
  end
 end
 local function drives()
  for _,side in ipairs({settings.sourceSide,settings.productionSide})do
   assert(call('getInventoryName',side)=='tile.appliedenergistics2.BlockDrive'and call('getInventorySize',side)==10,'原料两侧必须是10槽ME驱动器')
  end
 end
 local function move(from,to,sourceSlot,destSlot,stage)
  enabled();assert(not stack(to,destSlot),'搬盘目标槽被占用')
  local before=stack(from,sourceSlot);assert(before and before.size==1 and before.name==record.cell,'原料盘已变化')
  record.pending={kind='move',from=from,to=to,sourceSlot=sourceSlot,destSlot=destSlot};save(stage)
  enabled();assert(call('transferItem',from,to,1,sourceSlot,destSlot)==1,'搬盘回执不确定，不重复搬运')
  local after=stack(to,destSlot)
  assert(not stack(from,sourceSlot)and after and after.name==record.cell and after.size==1,'搬盘后槽位不符，不重复搬运')
  record.pending=nil;save(stage..'-confirmed');return after
 end
 local function parallel(i,from,wanted)
  local n=cfg.nodes[i];local lo,hi=from.min,from.max
  if lo>wanted.max then c.invoke(n.address,'setMinParallel',wanted.min);lo=wanted.min end
  if hi<wanted.min then c.invoke(n.address,'setMaxParallel',wanted.max);hi=wanted.max end
  if lo~=wanted.min then c.invoke(n.address,'setMinParallel',wanted.min)end
  if hi~=wanted.max then c.invoke(n.address,'setMaxParallel',wanted.max)end
  assert(c.invoke(n.address,'getMinParallel')==wanted.min and c.invoke(n.address,'getMaxParallel')==wanted.max,'并行参数回读失败')
 end
 local function restore()
  record.pending={kind='restore-parallel',nodes=record.members};save('restoring')
  for _,i in ipairs(record.members)do local v=record.limits[i];local q=record.quota[i]
   parallel(i,{min=q,max=q},v)
  end
  record.pending=nil;save('restored')
 end
 -- All participants already have min=max=quota and an immediate-pause
 -- signal. Open them in one sweep, without waiting for earlier admissions.
 -- The shared durable intent replaces per-node batch-stop writes here only.
 local function waveWork(on)
  local stage=on and 'opening-nodes'or 'closing-nodes'
  record.pending={kind='admission-wave',enabled=on,nodes=record.members};save(stage)
  for _,i in ipairs(record.members)do
   if on then enabled()end
   local n=cfg.nodes[i]
   c.invoke(n.address,'setWorkAllowed',on)
  end
  -- Submit the entire wave before any delayed readback can wait for a tick.
  for _,i in ipairs(record.members)do
   local n=cfg.nodes[i]
   assert(c.invoke(n.address,'isWorkAllowed')==on,'整组接单许可回读失败：'..i)
  end
  if on then enabled()end
  if on then record.waveOpened=true else record.waveClosed=true end
  record.pending=nil;save(on and 'waiting-nodes'or 'nodes-closed')
 end
 local verified={}
 local function checkAdmission(i,state)
  local n=cfg.nodes[i]
  if state=='crafting'then
   assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'接单后暂停信号缺失')
   F.message='等待节点'..i..'进入暂停状态';return false
  end
  assert(state=='paused-immediate'or state=='nanite-tier-too-low','接单状态异常：'..tostring(state))
  assert(c.invoke(n.address,'getParallelRecipesInProgress')==record.quota[i],'实际接单数量与配额不符')
  local req=c.invoke(n.address,'getRequiredCondensate');local expected={}
  for _,v in ipairs(record.condensates)do expected[v.name]=(expected[v.name]or 0)+v.amount*record.quota[i]end
  assert(type(req)=='table','凝聚物需求不可读')
  for k,v in pairs(expected)do assert(req[k]==v,'接到的配方与原料盘不符')end
  for k in pairs(req)do assert(expected[k],'节点接到无关配方')end
  return true
 end
 local function admitWave()
  if not record.waveOpened then
   -- Check the whole wave before enabling its first node. Method values may
   -- be false for non-direct callbacks; presence, not truthiness, matters.
   for _,i in ipairs(record.members)do local n=cfg.nodes[i]
    local methods=c.methods(n.address)
    assert(methods and methods.setWorkAllowed~=nil and methods.isWorkAllowed~=nil,'传送节点缺少启停接口')
    assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'整组接单前暂停信号缺失')
    assert(c.invoke(n.address,'getState')=='idle'and c.invoke(n.address,'isWorkAllowed')==false,'整组接单前节点未空闲关闭')
   end
   local at=clock.uptime();waveWork(true);record.timings.opening=clock.uptime()-at
   return false
  end
  if not record.waveClosed then
   local waiting=false
   for _,i in ipairs(record.members)do local n=cfg.nodes[i];local state=c.invoke(n.address,'getState')
    if state=='idle'then waiting=true
    else
     assert(state=='crafting'or state=='paused-immediate'or state=='nanite-tier-too-low','接单状态异常：'..tostring(state))
    end
   end
   if waiting then F.message='固定配额同时接单：等待其余节点';return false end
   local at=clock.uptime();waveWork(false);record.timings.closing=clock.uptime()-at
  end
  local complete=true
  for _,i in ipairs(record.members)do if not verified[i]then
   if checkAdmission(i,c.invoke(cfg.nodes[i].address,'getState'))then verified[i]=true else complete=false end
  end end
  if not complete then return false end
  record.cursor=#record.members+1;save('nodes-admitted');return true
 end
 if resumeReady then
  -- Explicit ready-checkpoint recovery only: no admission, move or recipe replay.
  assert(cohort and cohort.version==2 and type(cohort.members)=='table'and type(cohort.entries)=='table'and type(cohort.normalized)=='table','生产组记录不可核对')
  assert(not old.openNode and not old.pending and type(old.members)=='table'and #old.members>0 and old.cursor==#old.members+1 and type(old.quota)=='table'and type(old.limits)=='table','原料盘就绪检查点无效')
  assert(#cohort.members==#old.members,'生产组成员数量变化')
  local binding={settings.transposer,settings.sourceSide,settings.productionSide,settings.sourceSlot,settings.productionSlot}
  assert(type(old.binding)=='table'and #old.binding==#binding,'原料盘接线记录无效')
  for i,v in ipairs(binding)do assert(old.binding[i]==v,'原料盘接线已变化')end
  local recipe;for _,r in ipairs(recipes)do if r.file==old.recipe then recipe=r end end;assert(recipe,'恢复时配方登记缺失')
  local per={};for _,v in ipairs(recipe.condensates)do per[v.name]=(per[v.name]or 0)+v.amount end
  local function same(a,b)assert(type(a)=='table'and type(b)=='table');for k,v in pairs(a)do assert(b[k]==v,'恢复配方或原料身份变化')end;for k in pairs(b)do assert(a[k]~=nil,'恢复配方含未知条目')end end
  same(per,cohort.normalized)
  for k,v in pairs(recipe.items)do assert(old.items[k]==v*old.count,'冻结原料身份变化')end
  for k in pairs(old.items)do assert(recipe.items[k],'冻结原料含未知物品')end
  local seen={};for pos,i in ipairs(old.members)do
   assert(cfg.nodes[i]and cfg.nodes[i].group==group and not seen[i]and cohort.members[pos]==i,'生产组成员变化');seen[i]=true
  end
  assert(seen[cohort.leader],'生产组主节点不在批次内')
  local total=0
  for _,i in ipairs(ids)do local n=cfg.nodes[i];local q=old.quota[i];local limits=old.limits[i]
   assert(whole(q)and limits and whole(limits.min)and limits.min>=1 and whole(limits.max)and limits.max>=limits.min,'原始配额/并行还原记录无效');total=total+q
   assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15 and c.invoke(n.address,'isWorkAllowed')==false,'恢复前整组必须暂停并关闭接单')
   local state=c.invoke(n.address,'getState');local p=c.invoke(n.address,'getParallelRecipesInProgress')
   if q>0 then
    local e=assert(cohort.entries[i]);assert(seen[i]and e.parallel==q,'生产组配额变化')
    assert(c.invoke(n.address,'getMinParallel')==q and c.invoke(n.address,'getMaxParallel')==q,'节点配额设置变化')
    local expected={};for k,v in pairs(per)do expected[k]=v*q end;same(expected,e.required)
    local used=c.invoke(n.address,'getConsumedCondensate');assert(type(used)=='table','消耗记录不可读')
    for k,v in pairs(expected)do local u=used[k]or 0;assert(whole(u)and u<=(v)and u>=(e.consumed and e.consumed[k]or 0),'节点消耗记录不符')
     if state=='idle'then assert(u==v,'空闲节点缺少完整消耗证明')end
    end
    for k,v in pairs(used)do assert(v==0 or expected[k],'消耗含无关凝聚物')end
    if state=='idle'then assert(p==0,'空闲节点并行异常')else
     assert(not e.finished and(state=='paused-immediate'or state=='nanite-tier-too-low')and p==q,'恢复时节点状态/并行异常');same(expected,c.invoke(n.address,'getRequiredCondensate'))
    end
   else assert(not seen[i]and state=='idle'and p==0,'未参与节点提前接单')end
  end
  assert(total==old.count,'批次总份数变化')
  drives()
  for _,side in ipairs({settings.sourceSide,settings.productionSide})do for slot=1,10 do
   local v=stack(side,slot)
   if side==settings.sourceSide and slot==settings.sourceSlot then assert(v and v.name==old.cell,'返回缓存侧的原料盘变化');M.describe(v)
   else assert(not v,'生产侧或其他槽位存在盘，拒绝恢复')end
  end end
  record=old;F.ready=true;F.message='已核对原就绪批次；继续已接单生产'
 end
 if resumeAdmission==true then
  -- Explicit repair entry, never selected by the normal engine constructor.
  -- Only confirmed pre-production admission can resume; no move is replayed.
  assert(old and old.stage=='waiting-node'and not old.pending and type(old.members)=='table'and type(old.quota)=='table'and type(old.limits)=='table','不支持恢复此原料批次')
  assert(old.openNode==old.members[old.cursor]and old.cell and old.recipe,'接单检查点无效')
  local binding={settings.transposer,settings.sourceSide,settings.productionSide,settings.sourceSlot,settings.productionSlot}
  assert(type(old.binding)=='table'and #old.binding==#binding)
  for i,v in ipairs(binding)do assert(old.binding[i]==v,'原料盘接线已变化')end
  drives();local recipe
  for _,r in ipairs(recipes)do if r.file==old.recipe then recipe=r end end;assert(recipe,'恢复时配方登记缺失')
  local total,accepted=0,0
  for _,i in ipairs(ids)do
   local n=cfg.nodes[i];local q=old.quota[i];assert(whole(q)and old.limits[i]);total=total+q
   assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15 and c.invoke(n.address,'isWorkAllowed')==false,'恢复前整组必须暂停并关闭接单')
   local state=c.invoke(n.address,'getState');local p=c.invoke(n.address,'getParallelRecipesInProgress')
   if state~='idle'then
    assert(state=='paused-immediate'or state=='nanite-tier-too-low','恢复时节点状态异常')
    assert(p==q and q>0,'恢复接单配额不符');local req=c.invoke(n.address,'getRequiredCondensate');local used=c.invoke(n.address,'getConsumedCondensate')
    assert(type(req)=='table'and type(used)=='table')
    local expected={};for _,v in ipairs(recipe.condensates)do expected[v.name]=(expected[v.name]or 0)+v.amount*q end
    for k,v in pairs(expected)do assert(req[k]==v and(used[k]or 0)==0,'生产已消耗或接到了其他配方')end
    for k,v in pairs(used)do assert(v==0,'生产已消耗凝聚物')end
    for k in pairs(req)do assert(expected[k],'恢复时需求含未知流体')end
    local position;for pos,j in ipairs(old.members)do if j==i then position=pos end end
    assert(position and position<=old.cursor,'后续节点提前接单');accepted=accepted+q
   else
    assert(p==0,'空闲节点并行不为零')
    for pos,j in ipairs(old.members)do assert(j~=i or pos>=old.cursor,'先前确认节点变为空闲')end
   end
   if q>0 then assert(c.invoke(n.address,'getMinParallel')==q and c.invoke(n.address,'getMaxParallel')==q,'恢复时节点配额设置变化')end
  end
  assert(total==old.count,'原始批次数量不符')
  for _,side in ipairs({settings.sourceSide,settings.productionSide})do for slot=1,10 do
   if side~=settings.productionSide or slot~=settings.productionSlot then assert(not stack(side,slot),'恢复时原料盘位置变化')end
  end end
  local disk=stack(settings.productionSide,settings.productionSlot);assert(disk and disk.name==old.cell)
  local items=M.describe(disk)
  for k,unit in pairs(recipe.items)do assert(old.items[k]==unit*old.count and(items[k]or 0)==unit*(old.count-accepted),'余料与已接单数量不符')end
  for k in pairs(items)do assert(recipe.items[k],'恢复时混入其他原料')end
  record=old
 end
 function F.observe()
  if record and not F.ready then return end -- the source disk is absent during admission
  if clock.uptime()<F.nextPoll then return end;F.nextPoll=clock.uptime()+1
  local v=stack(settings.sourceSide,settings.sourceSlot)
  if v and whole(v.storedItemCount)and v.storedItemCount>0 then F.since=F.since or clock.uptime()else F.since=nil end
 end
 function F.pending()if record then return true end;F.observe();return F.since~=nil end
 function F.step()
  enabled();if F.ready then return true end
  assert(not record or not record.pending,'原料盘有未确认操作，禁止自动重放')
  F.observe()
  if not record then
   if not F.since or clock.uptime()-F.since<(settings.collectSeconds or 10)then
    F.message=F.since and '同配方攒料10秒' or '等待缓存盘进料';return false
   end
   local checkedAt=clock.uptime()
   if not captureReady()then F.message='等待全部节点空闲';return false end
   drives();local capturedSlots={}
   for _,side in ipairs({settings.sourceSide,settings.productionSide})do
    local rows=inventory(side);capturedSlots[side]=rows
    for slot=1,10 do if side==settings.productionSide or slot~=settings.sourceSlot then assert(not rows[slot],'原料驱动器存在其他盘，禁止混批')end end
   end
   local v=assert(capturedSlots[settings.sourceSide][settings.sourceSlot],'原料盘不见了')
   local checkedSeconds=clock.uptime()-checkedAt;local captureAt=clock.uptime()
   record={version=1,kind='cell-feed',binding={settings.transposer,settings.sourceSide,settings.productionSide,settings.sourceSlot,settings.productionSlot},cell=v.name,limits={},quota={},members={}}
   save('capturing')
   local captured=move(settings.sourceSide,settings.productionSide,settings.sourceSlot,settings.productionSlot,'moving-to-production')
   local items=M.describe(captured);local recipe,count=M.match(items,recipes)
   E.log(ids[1],string.format('进料识别：准备检查 %.2f秒 / 搬盘与匹配 %.2f秒；攒料时间保持%d秒',checkedSeconds,clock.uptime()-captureAt,settings.collectSeconds or 10))
   record.items=items;record.recipe=recipe.file;record.count=count;record.condensates=recipe.condensates;record.outputs=recipe.outputs
   local planningAt=clock.uptime()
   local limits={}
   for _,i in ipairs(ids)do local n=cfg.nodes[i];local lo=c.invoke(n.address,'getMinParallel');local hi=c.invoke(n.address,'getMaxParallel')
    assert(whole(lo)and lo>=1 and whole(hi)and hi>=lo,'节点并行参数无效')
    record.limits[i]={min=lo,max=hi};limits[#limits+1]={index=i,max=settings.maxParallelPerNode or hi}
   end
   record.quota=M.allocate(count,limits);save('planned')
   local participating={};for _,i in ipairs(ids)do if record.quota[i]>0 then participating[#participating+1]=i end end
   -- One durable intent covers the entire closed/paused configuration block.
   -- Partial or unknown results retain this intent and are never replayed.
   record.pending={kind='set-parallel',nodes=participating};save('configuring')
   for _,i in ipairs(ids)do local q=record.quota[i];if q>0 then
    enabled();parallel(i,record.limits[i],{min=q,max=q})
    record.members[#record.members+1]=i
   end end
   record.pending=nil;record.timings={planning=clock.uptime()-planningAt,admissionStarted=clock.uptime()};save('configured')
   record.cursor=1;record.admissionMode=settings.concurrentAdmission~=false and 'quota-wave'or nil;save('admitting')
   F.message='原料盘已冻结：'..count..'份 / '..#record.members..'台'
   E.log(ids[1],F.message)
  end
  if record.admissionMode=='quota-wave'then
   if not admitWave()then return false end
  end
  local i=record.members[record.cursor]
  if i then
   local n=cfg.nodes[i];local state=c.invoke(n.address,'getState')
   if not record.openNode then
    assert(state=='idle','节点接单前不空闲');record.openNode=i;record.pending={kind='admission',node=i};save('opening-node')
    enabled();E.nodeWork(i,true);record.pending=nil;save('waiting-node');return false
   end
   if state=='idle'then return false end
   E.nodeWork(i,false)
   if not checkAdmission(i,state)then return false end
   record.openNode=nil;record.cursor=record.cursor+1;save('node-admitted');return false
  end
  -- The wave's closing transaction has already confirmed all participants;
  -- unused nodes have remained closed/paused since captureReady().
  if record.admissionMode~='quota-wave'then closeAll()end
  local disk=stack(settings.productionSide,settings.productionSlot);local _,remaining=M.describe(disk)
  assert(remaining==0,'接单后原料盘有余料，保持整组暂停')
  move(settings.productionSide,settings.sourceSide,settings.productionSlot,settings.sourceSlot,'returning-empty-cell')
  if record.timings then
   record.timings.admission=clock.uptime()-record.timings.admissionStarted
   E.log(ids[1],string.format('并行分配与回读 %.2f秒 / %s接单核对与回盘 %.2f秒',record.timings.planning,record.admissionMode=='quota-wave'and '固定配额同时'or '逐台',record.timings.admission))
  end
  save('ready');F.ready=true;F.since=nil;return true
 end
 function F.finish()
  assert(record and F.ready,'原料批次未就绪');closeAll();idleClosed();restore();save('stopped')
  record=nil;F.ready=false;F.message='等待下一批原料';F.observe()
 end
 function F.plan()return record end
 return F
end
return M
]=],supported={['24564:1506983870']=true}},{name='web.lua',source=[=[local c=require('component');local event=require('event');local clock=require('computer')
local ROOT='/home/bec_v2'
local function module(n)return assert(loadfile(ROOT..'/lib/'..n..'.lua'))()end
local C,B,W=module('config'),module('ochd_bindings'),module('web_json')
local address,count=nil,0;for a in c.list('hd_panel',true)do address=a;count=count+1 end
assert(count==1,'请只连接一面 OCHD 屏幕墙的主组件')
local methods=c.methods(address)
assert(methods.setWebApp~=nil and methods.publish~=nil,'需要支持 HTML 页面的 OCHD alpha7 或兼容版 JAR')
local f=assert(io.open(C.path('lib/web_page.html'),'r'));local page=f:read('*a');f:close()
local package={id='bec-v2-studio',title='BEC V2 结构绑定与运行',entry='index.html',files={['index.html']=page},
 events={'save_field','apply_bindings','start','pause','select_group','refresh','scan_components','patterns','cache','recheck_all'}}
local panel=c.proxy(address)
-- BEC_V3_WEB_SINGLE_INSTANCE_1: cached component proxies are shared by OpenOS
-- processes. Acquire before constructing a session or changing the panel.
local previous=rawget(panel,'_becWebOwner')
assert(not previous or previous.closed or coroutine.status(previous.root)=='dead',
 'BEC 网页程序已经运行，请使用现有页面；先在 OC 按 Q 正常退出后才能重开')
local owner={root=coroutine.running(),startedAt=clock.uptime(),closed=false}
rawset(panel,'_becWebOwner',owner)
local function session()
local H=module('web_session')(C,B,W)
local snapshot=H.snapshot
H.snapshot=function(...)
 local data=snapshot(...);owner.state=data;owner.updatedAt=clock.uptime()
 local engine=H.engine();owner.logs=engine and engine.logs
 return data
end
local T=module('web_transport')(panel,event,W,address);C.pulse=T.pulse
C.wait=T.poll -- Preserve web requests/Q while waiting for a server-thread write.
T.snapshot=function()return H.snapshot(true)end
T.observe=H.observe
T.canServe=H.canServeFast
local function handle(request)
 local success,message=pcall(function()return H.handle(request.name,request.args,request.request)end)
 if not success then H.notice=tostring(message)end
 T.publish(H.snapshot(true),{token=request.token,name=request.name,ok=success,message=tostring(message):sub(1,400)})
end
T.serve=handle
local ok,err=xpcall(function()
 while true do local accepted,reason=panel.setWebApp(package);assert(accepted~=nil,reason);if accepted then break end;event.pull(.6)end
 print('OCHD 已显示结构绑定与流程图。右键屏幕操作；OC 按 Q 退出并暂停。')
 local nextPush=0
 T.pulse(true)
 while not T.stopping do
  T.poll(.05)
  local request=T.take()
  if request then
   T.handling=true;handle(request);T.handling=false
   nextPush=clock.uptime()+.6
  end
  if T.stopping then break end
  H.step();T.pulse()
  if clock.uptime()>=nextPush then
   T.publish(H.snapshot(true));nextPush=clock.uptime()+.6
  end
 end
end,debug.traceback)
local errors=H.close();for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
pcall(function()panel.release()end)
assert(ok,err);assert(#errors==0,'暂停存在回读失败，请核对机器')
end
local success,reason=xpcall(session,debug.traceback)
owner.closed=true
if rawget(panel,'_becWebOwner')==owner then rawset(panel,'_becWebOwner',nil)end
assert(success,reason)
]=],supported={['3206:2519455272']=true}}}

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
local self='/home/bec_290_update.lua'
do
 local downloaded=read(self)
 local payload=downloaded and downloaded:match('^%-%- BEC_RELEASE_290_UPDATE_1\nlocal SELF_SIGNATURE=[^\n]*\n(.*)$')
 if payload and signature(payload)==SELF_SIGNATURE then
  pcall(fs.remove,self);print('已释放本次临时安装包；程序备份和运行记录保留。')
 end
 downloaded=nil;payload=nil;if type(collectgarbage)=='function'then pcall(collectgarbage,'collect')end
end
if identical then print('2.9.0兼容更新已安装，无需重复更新。');return end

local c=require('component')
for a in c.list('hd_panel',true)do
 local owner=rawget(c.proxy(a),'_becWebOwner')
 assert(not owner or owner.closed or owner.root and coroutine.status(owner.root)=='dead','先在OC按Q退出网页，等待完整收尾')
end
local C=assert(loadfile(root..'lib/config.lua'))();local cfg=C.load()
local function stopped(path,kind)
 local r=C.read(C.path(path));if not r then return end
 assert(r.stage=='stopped'and not r.pending and not r.plan and not r.incomplete,kind..'尚未完整结束，保留现场，不更新')
 for _,job in pairs(r.requests or{})do assert(job.state=='done'or job.state=='rejected'and job.preSubmissionFailed,'AE申请尚未确认，不更新')end
end
for group,g in ipairs(cfg.groups)do
 stopped('state/group-'..group..'/cell-feed.journal','原料盘')
 stopped('state/group-'..group..'/cohort.dat','生产组')
 stopped('state/group-'..group..'/cache.journal','缓存')
 local io=C.read(C.path('state/group-'..group..'/nanites-cell.journal'))
 assert(not io or io.stage=='done'and not io.pending,'蜂群IO尚未完成，不更新')
 for _,a in ipairs(g.generators)do assert(not c.invoke(a,'isWorkAllowed')and not c.invoke(a,'isMachineActive'),'纠缠器未完整停止，不更新')end
end
for i,n in ipairs(cfg.nodes)do
 stopped('state/node-'..i..'/production.journal','节点生产')
 assert(c.invoke(n.address,'getState')=='idle'and c.invoke(n.address,'isWorkAllowed')==false and c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'节点尚未空闲/关闭/暂停，不更新')
end

local disk=assert(fs.get(root));assert(disk.spaceTotal()-disk.spaceUsed()>=bytes+524288,'磁盘空间不足：更新后需保留512KiB')
local n=1
while true do
 local conflict=false;for _,row in ipairs(rows)do for _,suffix in ipairs({'.before-release290-','.release290-new-','.release290-failed-'})do if fs.exists(root..row.name..suffix..n)then conflict=true end end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(rows)do
 local temp=root..row.name..'.release290-new-'..n;local f=assert(io.open(temp,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(temp)==row.source,'临时文件回读失败，旧程序未改')
end
for i,row in ipairs(rows)do assert(read(root..row.name)==old[i],'更新期间程序改变，未替换')end
local backed,installed={},{}
local ok,reason=pcall(function()
 for i,row in ipairs(rows)do local target=root..row.name
  if old[i]then assert(fs.rename(target,target..'.before-release290-'..n),'备份失败');backed[i]=true end
  assert(fs.rename(target..'.release290-new-'..n,target),'替换失败');installed[i]=true
  assert(read(target)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#rows,1,-1 do local target=root..rows[i].name
  if installed[i]then assert(fs.rename(target,target..'.release290-failed-'..n),'移出失败程序失败，保留备份')end
  if backed[i]then assert(fs.rename(target..'.before-release290-'..n,target),'恢复失败，保留备份')end
 end
 error('更新失败，旧程序已恢复：'..tostring(reason))
end
print('2.9.0兼容更新已安装：异步写入确认、固定配额同时接单。')
print('已有地址、草稿、配置、配方和运行记录保留；未控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
