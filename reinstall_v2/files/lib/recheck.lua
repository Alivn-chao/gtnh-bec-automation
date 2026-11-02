-- Explicit full inspection. Reads hardware only; never repairs/replays journals.
return function(C,cfg,E,storage,catalogue)
 local native=require('component');local c=C.component and C.component(native)or native;local clock=require('computer')
 local report={version=1,checked=0,issues={},at=clock.uptime(),routes={}}
 local function check(label,fn)
  report.checked=report.checked+1;local ok,err=pcall(fn)
  if not ok then report.issues[#report.issues+1]=label..'：'..tostring(err):gsub('^.-:%d+: ',''):sub(1,140)end
 end
 local function whole(n)return type(n)=='number'and n>=0 and n%1==0 end
 local function stopped(path,kind)
  local r=C.read(C.path(path));if not r then return end
  assert(r.stage==(kind=='io'and 'done'or 'stopped')and not r.pending and not r.plan and not r.incomplete,'未完成或有未确认操作，保留记录')
  assert(r.configOwned~=true,'供液配置尚未归还')
  for _,j in pairs(r.requests or{})do assert(j.state=='done'or j.state=='rejected'and j.preSubmissionFailed,'AE申请未确认')end
  for _,t in pairs(r.transfers or{})do assert(t.ok==true,'搬液回执未确认')end
 end
 check('磁盘',function()local d=storage.status();assert(d.known and d.ok,'剩余空间不足或不可读')end)
 check('设备绑定和方法',function()assert(C.validate(cfg,true))end)
 if E then check('工作器',function()
  for _,t in ipairs(E.tasks)do assert(not t.co,'生产工作器仍在收尾')end
  for group,owner in pairs(E.groupOwner)do assert(owner=='cache-'..group,'生产组仍占用资源')end
  assert(not E.fluidOwner or tostring(E.fluidOwner):match('^cache%-%d+$'),'供液资源仍被生产占用')
 end)end
 for i,n in ipairs(cfg.nodes)do
  check('节点'..i,function()
   assert(c.invoke(n.address,'getState')=='idle','节点未空闲')
   assert(c.invoke(n.address,'isWorkAllowed')==false,'接单许可未关闭')
   assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'立即暂停输出不是15')
   assert(c.invoke(n.address,'getParallelRecipesInProgress')==0,'仍有在途配方')
   local lo,hi=c.invoke(n.address,'getMinParallel'),c.invoke(n.address,'getMaxParallel')
   assert(whole(lo)and lo>=1 and whole(hi)and hi>=lo,'并行范围无效')
  end)
  check('节点'..i..'运行记录',function()stopped('state/node-'..i..'/production.journal')end)
 end
 local settings=C.read(C.path('cache.config'))or{target=cfg.cacheTarget,overrides={}}
 local rawNames={infinity='molten.infinity',chromaticglass='molten.chromaticglass',transcendentmetal='molten.transcendentmetal',
  dimshiftedsuperfluid='dimensionallyshiftedsuperfluid',neutronium='molten.neutronium',cosmicneutronium='molten.cosmicneutronium',
  bedrockium='molten.bedrockium',celestialtungsten='molten.celestialtungsten',hypogen='molten.hypogen',phononmedium='phononmedium',
  quarkgluonplasma='quarkgluonplasma',spacetime='molten.spacetime',time='temporalfluid',space='spatialfluid',cosmicsolder='boundlesscosmicsolder',
  mhdcsm='molten.magnetohydrodynamicallyconstrainedstarmatter',magmatter='molten.magmatter',universium='molten.universium',eternity='molten.eternity'}
 local gates={}
 for group,g in ipairs(cfg.groups)do
  for _,name in ipairs({'cell-feed.journal','cohort.dat','cache.journal','nanites-cell.journal','nanites.journal'})do
   check('组'..group..'/'..name,function()stopped('state/group-'..group..'/'..name,name:match('^nanites')and 'io'or nil)end)
  end
  for _,a in ipairs(g.generators)do check('纠缠器 '..a:sub(1,8),function()
   assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'尚未完整停机')
  end)end
  local stock={}
  check('组'..group..'约束场',function()
   assert(c.invoke(g.storage,'isWorkAllowed')==true,'约束场未开启')
   stock=c.invoke(g.storage,'getStoredCondensate');assert(type(stock)=='table','库存不可读')
   for _,n in pairs(stock)do assert(whole(n),'凝聚物库存无效')end
  end)
  check('组'..group..'原液及接口',function()
   local sub=c.invoke(g.subInterface,'getFluidsInNetwork');assert(type(sub)=='table','子网不可读')
   for _,f in pairs(sub)do assert((f.amount or f.size or 0)==0,'子网仍有原液，需核对旧批次')end
   for slot=0,5 do assert(c.invoke(cfg.mainInterface,'getFluidInterfaceConfiguration',slot)==nil,'主供液接口仍有配置')end
   for _,side in ipairs({g.mainSide,g.subSide})do
    local count=c.invoke(g.transposer,'getTankCount',side);assert(whole(count)and count>0,'常规供液接口缺失')
    for slot=1,count do local f=c.invoke(g.transposer,'getFluidInTank',side,slot);if f[1]then f=f[slot]or f[1]end;assert((f.amount or 0)==0,'常规供液接口有未处理流体')end
   end
  end)
  for _,n in ipairs(cfg.nodes)do if n.group==group and not gates[n.gate]then gates[n.gate]=true
   check('韦门 '..n.gate:sub(1,8),function()
    assert(c.invoke(n.gate,'getCondensateFilterCount')>=1 and type(c.invoke(n.gate,'getCondensateFilters'))=='table','过滤读数无效')
    assert(c.invoke(n.gate,'isWorkAllowed')==true and c.invoke(n.gate,'isMachineActive')==true,'韦门未运行')
   end)
  end end
  local h=g.nanites
  if h and h.enabled and h.mode=='cell-io'then
   check('组'..group..'蜂群及双IO',function()
    for _,pair in ipairs({{h.loadSide,h.loadRedstone,h.loadOutputSide},{h.returnSide,h.returnRedstone,h.returnOutputSide}})do
     assert(c.invoke(pair[2],'getOutput',pair[3])==0,'蜂群IO红石未关闭')
     for slot=1,12 do assert(not c.invoke(h.transposer,'getStackInSlot',pair[1],slot),'蜂群IO仍有硬盘')end
    end
    if h.hiveSource=='transposer'then
     local count=assert(loadfile(C.path('lib/hive_transposer.lua')))()(c,h,false).read()
     local old=C.read(C.path('state/group-'..group..'/nanites-cell.journal'))
     assert(not(count==0 and old and old.holding and(old.holding.count or 0)>0),'旧换蜂记录仍有蜂群但实体仓为空；需核对更换/取走记录')
    end
    local size=c.invoke(h.transposer,'getInventorySize',h.bankSide);assert(whole(size)and size>=1,'蜂群盘库缺失')
    for slot=1,math.min(10,size)do local disk=c.invoke(h.transposer,'getStackInSlot',h.bankSide,slot)
     if disk then
      assert(disk.size==1 and whole(disk.storedItemCount)and type(disk.getAvailableItems)=='table','蜂群盘不可读：'..slot)
      local total=0;for _,item in pairs(disk.getAvailableItems)do assert(whole(item.size),'盘内数量无效');total=total+item.size end
      assert(total==disk.storedItemCount,'蜂群盘总数不符：'..slot)
     end
    end
   end)
  end
  local feed=g.cellFeed
  if feed and feed.enabled then check('组'..group..'原料盘位',function()
   for _,side in ipairs({feed.sourceSide,feed.productionSide})do for slot=1,10 do
    local disk=c.invoke(feed.transposer,'getStackInSlot',side,slot)
    if side==feed.sourceSide and slot==feed.sourceSlot then
     if disk then assert(disk.size==1 and whole(disk.storedItemCount)and type(disk.getAvailableItems)=='table','缓存原料盘不可读')end
    else assert(not disk,'生产侧或额外槽位存在原料盘')end
   end end
  end)end
  local routes,duplicates={},{}
  for index,a in ipairs(g.bulkTransposers or{})do check('组'..group..'高速口'..index,function()
   local sources,receivers={},{}
   for side=0,5 do local ok,count=pcall(c.invoke,a,'getTankCount',side)
    if ok and(count==1 or count==6)then local cap=c.invoke(a,'getTankCapacity',side,1)
     if count==1 and cap==2147483647 then local f=c.invoke(a,'getFluidInTank',side,1);if f[1]then f=f[1]end
      if f.name then sources[#sources+1]={raw=f.name,from=side}end
     elseif count==6 and cap==16000 then
      receivers[#receivers+1]=side
      for slot=1,6 do local f=c.invoke(a,'getFluidInTank',side,slot);if f[1]then f=f[slot]or f[1]end;assert((f.amount or 0)==0,'接收口仍有未处理流体')end
     end
    end
   end
   assert(#receivers==1,'接收方向缺失或不唯一')
   for _,s in ipairs(sources)do if routes[s.raw]then duplicates[s.raw]=true end;routes[s.raw]={address=a,from=s.from,to=receivers[1]}end
  end)end
  check('组'..group..'供液类型',function()
   for raw in pairs(duplicates)do error('高速口重复：'..raw)end
   if settings.enabled then for _,row in ipairs(catalogue or{})do
    local kind=row[1];local target=settings.overrides[kind];if target==nil then target=settings.target end
    if (stock[kind]or 0)<target then
     local raw=assert(rawNames[kind:gsub('^entangled_','')],'未知凝聚物：'..kind)
     assert(routes[raw]or routes['fluid.'..raw]or routes['molten.'..raw]or routes['fluid.molten.'..raw],'供液口未配置：'..kind)
    end
   end end
  end)
  report.routes[group]=routes
 end
 if cfg.workshopInterface and cfg.workshopInterface~=''then check('样板工坊',function()assert(type(c.invoke(cfg.workshopInterface,'getItemsInNetwork'))=='table','工坊接口不可读')end)end
 report.ok=#report.issues==0;return report
end
