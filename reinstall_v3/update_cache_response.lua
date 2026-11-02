-- BEC_V3_CACHE_RESPONSE_UPDATE_1
local SELF_SIGNATURE='175237:1812600371'
print('BEC V3 cache response update; Q to exit the old UI first')
local function sig(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local rows={{name='lib/cache.lua',added=false,source=[=[-- V1 cache worker, scheduled under the same V2 group and shared-fluid leases.
local c=require('component');local clock=require('computer');local fs=require('filesystem');local ser=require('serialization')
local labels={chromaticglass='彩色玻璃',transcendentmetal='超时空金属',infinity='无尽',neutronium='中子素',cosmicneutronium='宇宙中子素',bedrockium='基岩锭',celestialtungsten='天体钨',hypogen='海珀珍',phononmedium='声子介质',quarkgluonplasma='夸克胶子等离子体',space='空间',time='时间',spacetime='时空',cosmicsolder='宇宙焊锡',dimshiftedsuperfluid='维度偏移超流体',mhdcsm='磁流体动力学约束星体物质',magmatter='磁物质',universium='宇宙素',eternity='永恒'}
return function(C,B,cfg,storage)
 local c=C.component and C.component(c)or c
 local path=C.path('cache.config');local raw=B.read(path)
 local fallback=cfg.cacheTarget
 if type(fallback)~='number'or fallback<1 or fallback>2147483647 or fallback%1~=0 then fallback=144000 end
 local settings=raw and C.read(path)or {version=1,target=fallback,overrides={},enabled=false}
 local K={busy=false,logs={},message='空闲时按目标补库；生产订单优先',page=0}
 local active,nextScan,nextGroup,names=nil,0,1,{}
 -- BEC_V3_PAUSE_RESPONSE_1: memory-only cancellation, safe between callbacks.
 function K.requestStop()if active then active.stop=true;active.deadline=0 end end
 local catalogueReady=false;local displayedStock={}
 local catalogueIndex
 if fs.exists(C.path('lib/cache_catalogue.lua'))then catalogueIndex=assert(loadfile(C.path('lib/cache_catalogue.lua')))()(C,cfg.recipeDirectory,storage)end
 local discoveryByGroup,discoveredCatalogue={},nil;local skipSavedDiscovery=false -- BEC_V3_FIXED_DISCOVERY_1
 local function integer(n,min)return type(n)=='number'and n>=min and n<=2147483647 and n%1==0 end
 local function validate(v)
  assert(v.version==1 and integer(v.target,1)and type(v.overrides)=='table'and type(v.enabled)=='boolean','缓存配置无效')
  local count=0;for name,n in pairs(v.overrides)do count=count+1;assert(count<=64 and type(name)=='string'and #name<=80 and name:match('^[%w_]+$')and integer(n,0),'单项缓存目标无效')end
 end
 validate(settings)
 local function log(text)K.message=tostring(text):sub(1,300);K.logs[#K.logs+1]=K.message;while #K.logs>4 do table.remove(K.logs,1)end end
 local function journal(group)return C.path('state/group-'..group..'/cache.journal')end
 local function confirmed(r)
  if not r then return true end
  if r.kind~='cache'or r.stage~='stopped'or r.pending~=nil or r.plan~=nil or r.configOwned~=false then return false end
  if r.incomplete then
   local v=r.reconciliation
   if not(type(v)=='table'and v.version==1 and v.kind=='confirmed-zero-transfer'and v.aeFinishedByOperator==true
    and type(v.subnet)=='table'and type(v.archive)=='string'and type(r.requests)=='table'and #r.requests==0 and type(r.transfers)=='table'and #r.transfers==0)then return false end
  end
  for _,move in ipairs(r.transfers or {})do if move.ok~=true then return false end end
  for _,job in ipairs(r.requests or {})do if job.state~='done'and not(job.state=='rejected'and job.preSubmissionFailed==true)then return false end end
  return true
 end
 local function prune(group)
  local directory=C.path('state/group-'..group);if not fs.exists(directory)then return end
  local rows={};local scanned=0
  for name in fs.list(directory)do
   scanned=scanned+1;if scanned>512 then break end
   local id=name:match('^cache%.journal%.stopped%-(%d+)$')
   if id then
    local p=directory..'/'..name;local f=io.open(p,'r');local text
    if f then text=f:read(65537);f:close()end
    if text and #text<=65536 then local ok,r=pcall(ser.unserialize,text)
     if ok and type(r)=='table'and confirmed(r)then rows[#rows+1]={path=p,id=tonumber(id),modified=fs.lastModified and fs.lastModified(p)or 0}end
    end
   end
  end
  table.sort(rows,function(a,b)if a.modified==b.modified then return a.id>b.id end;return a.modified>b.modified end)
  for i=3,#rows do assert(fs.remove(rows[i].path),'缓存已完成归档清理失败')end
 end
 function K.assertReady()
  assert(not K.blocked,'缓存操作未确认，保留记录核对：'..tostring(K.blocked))
  for group in ipairs(cfg.groups)do assert(confirmed(C.read(journal(group))),'设备组 '..group..' 有未确认缓存操作，保留 cache.journal 核对，禁止重复申请')end
 end
 function K.clearCheckedFault(E)
  assert(not active and not K.busy,'缓存工作器尚未收尾')
  for group in ipairs(cfg.groups)do
   local r=C.read(journal(group));assert(confirmed(r)and not(r and r.incomplete),'缓存记录仍需人工核对')
   if E then
    assert(not E.groupOwner[group]or E.groupOwner[group]=='cache-'..group,'资源正被生产占用')
   end
  end
  if E then
   for _,t in ipairs(E.tasks)do assert(not t.co,'生产工作器尚未收尾')end
   assert(not E.fluidOwner or tostring(E.fluidOwner):match('^cache%-%d+$'),'供液资源正被生产占用')
   for group in ipairs(cfg.groups)do if E.groupOwner[group]=='cache-'..group then E.groupOwner[group]=nil end end
   if E.fluidOwner then E.fluidOwner=nil end
  end
  K.blocked=nil;discoveryByGroup={};skipSavedDiscovery=true;nextScan=0
  log('全量检查通过，已解除旧缓存故障；可启动自动化。')
 end
 local function scan(force)
  if catalogueReady and not force then return end
  if force then discoveryByGroup={};skipSavedDiscovery=true end
  local found
  if catalogueIndex then found,discoveredCatalogue,K.catalogueStats=catalogueIndex.scan(force)else
  local totals,outputs={},{},{};found={};local count,valid=0,true
  if fs.exists(cfg.recipeDirectory)then for name in fs.list(cfg.recipeDirectory)do if name:match('%.dat$')then
   local r=C.read(cfg.recipeDirectory..'/'..name)
   if r and r.state=='converted'then
    count=count+1;local demand={}
    for _,f in ipairs(r.condensates or {})do
     assert(type(f.name)=='string'and #f.name<=80,'配方流体名称无效');found[f.name]=true
     if not integer(f.amount,1)then valid=false else demand[f.name]=(demand[f.name]or 0)+f.amount end
    end
    if not next(demand)then valid=false end
    for k,v in pairs(demand)do if not integer(v,1)then valid=false end;totals[k]=math.max(totals[k]or 0,v)end
    for _,v in ipairs(r.outputs or {})do outputs[tostring(v.name)..':'..tostring(tonumber(v.damage or 0))]=true end
   else valid=false end
  end end end
  discoveredCatalogue=valid and count>0 and {totals=totals,outputs=outputs,count=count}or nil
  end
  names={};for name in pairs(found)do names[#names+1]=name end;table.sort(names);assert(#names<=64,'登记缓存类型超过64种');catalogueReady=true
 end
 function K.invalidateCatalogue()
  catalogueReady=false;discoveredCatalogue=nil
  for _,memo in pairs(discoveryByGroup)do memo.catalogue=nil end
 end
 -- Only these small settings/page operations may run between worker reads.
 function K.canServeFast(args)return catalogueReady and (args.mode=='page'or args.mode=='save')end
 function K.catalogueStep()scan()end
 function K.inspectionCatalogue()scan();local rows={};for _,name in ipairs(names)do rows[#rows+1]={name}end;return rows end
 function K.refreshStock(group)
  local ok,stock=pcall(c.invoke,cfg.groups[group].storage,'getStoredCondensate')
  displayedStock[group]=ok and type(stock)=='table'and stock or {}
 end
 function K.observeStock(group,stock)if type(stock)=='table'then displayedStock[group]=stock end end
 function K.action(args)
  -- BEC_CACHE_BROWSE_1: viewing pages is independent of settings writes.
  if args.mode=='page'then local page=tonumber(args.page);assert(integer(page,0),'分页无效');K.page=math.min(page,math.max(0,math.ceil(#names/8)-1));return '已读取缓存分页'end
  if args.mode=='refresh'then scan(true);local page=tonumber(args.page)or 0;assert(integer(page,0),'分页无效');K.page=math.min(math.floor(page),math.max(0,math.ceil(#names/8)-1));return '已刷新缓存目录；库存随状态更新'end
  assert(args.revision==B.revision(raw or ''),'缓存设置已变化，等待最新数据后重试')
  assert(B.read(path)==raw,'缓存设置被其他程序修改，请重新打开网页')
  local next={version=1,target=settings.target,enabled=settings.enabled,overrides={}}
  for name,n in pairs(settings.overrides)do next.overrides[name]=n end
  if args.mode=='enable'then K.assertReady();scan();assert(#names>0,'请先用样板处理登记配方，再启用补库');next.enabled=true
  elseif args.mode=='disable'then next.enabled=false;if active then active.stop=true end
  elseif args.mode=='save'then
   assert(type(args.value)=='string'and #args.value<=10 and(args.value==''or args.value:match('^%d+$')),'目标量请输入整数mB')
   local value=args.value==''and nil or tonumber(args.value)
   if args.name=='default'then assert(integer(value,1),'默认目标须为1到2147483647的整数mB');next.target=value
   else
    scan();local known=false;for _,name in ipairs(names)do if name==args.name then known=true end end
    assert(known,'只能设置已登记配方中的流体');assert(value==nil or integer(value,0),'单项目标须为整数mB；0停补，留空使用默认')
    next.overrides[args.name]=value
   end
  else error('未知缓存操作')end
  validate(next);local disk=storage.status();assert(disk.known and disk.ok,'磁盘不足，缓存设置未保存')
  C.write(path,next);settings=next;raw=B.read(path)
  return args.mode=='disable'and '已停补；已申请/搬入部分核对并收尾后退出'or '缓存设置已保存；运行中的补库在本轮结束后使用新目标'
 end
 local function worker(group,E,ctx)
  local g=cfg.groups[group];local leader
  for i,n in ipairs(cfg.nodes)do if n.group==group then leader=leader or i end end
  assert(leader,'缓存设备组没有节点');local n=cfg.nodes[leader]
  if E.hasPendingFeed and E.hasPendingFeed(group)then log('原料缓存盘已到料，交回生产调度。');return true end
  -- State reads and workAllowed writes are separate server callbacks. An idle
  -- node may already have admitted an order before the cache closed admission.
  -- Yield the leases BEFORE loading the cache runtime or creating its journal.
  for _,member in ipairs(cfg.nodes)do if member.group==group then
   if c.invoke(member.address,'getState')~='idle'then
    log('节点已接单或不再空闲，缓存尚未搬液/下单，交回生产调度。')
    return true
   end
  end end
  local function guard()
   assert(E.fluidOwner==ctx.token and E.groupOwner[group]==ctx.token,'缓存资源锁变化')
   assert(B.read(C.path('config.dat'))==ctx.formal,'缓存期间绑定变化，保留记录')
   local disk=storage.status();assert(disk.known and disk.ok,'缓存期间磁盘不足，保留记录')
   for _,member in ipairs(cfg.nodes)do if member.group==group then
    assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15,'缓存期间节点暂停信号变化')
    assert(c.invoke(member.address,'isWorkAllowed')==false,'缓存期间节点接单许可被重新开启')
    local s=c.invoke(member.address,'getState');assert(s=='idle'or s=='paused-immediate'or s=='nanite-tier-too-low','缓存期间节点状态异常：'..tostring(s))
   end end
  end
  local native={};for key,value in pairs(c)do native[key]=value end
  local allowed={[g.transposer]=true};for _,a in ipairs(g.bulkTransposers or {})do allowed[a]=true end
  native.list=function(...)
   local iter=c.list(...);return function()while true do local a,t=iter();if not a then return end;if t~='transposer'or allowed[a]then return a,t end end end
  end
  native.invoke=function(a,m,...)
   local args={...}
   if E.hasPendingFeed and E.hasPendingFeed(group)then ctx.stop=true end
   if m=='transferFluid'or m=='setFluidInterfaceConfiguration'or m=='setWorkAllowed'or m=='setOutput'then guard()end
   if a==n.address and (m=='getState'or m=='getRequiredCondensate')then
    local state='idle';local req={}
    for _,member in ipairs(cfg.nodes)do if member.group==group then
     local s=c.invoke(member.address,'getState');if s~='idle'then state=s end
     if m=='getRequiredCondensate'then for key,v in pairs(c.invoke(member.address,m)or {})do req[key]=(req[key]or 0)+v end end
    end end
    return m=='getState'and state or req
   end
   if a==n.redstone and (m=='getOutput'or m=='setOutput')then
    for _,member in ipairs(cfg.nodes)do if member.group==group then
     if m=='getOutput'then if c.invoke(member.redstone,m,member.pauseSide)~=15 then return 0 end
     else assert(args[2]==15,'缓存禁止放行节点');c.invoke(member.redstone,m,member.pauseSide,args[2])end
    end end;return m=='getOutput'and 15 or true
   end
   if a==g.generators[1]then
    if m=='setWorkAllowed'then for _,address in ipairs(g.generators)do c.invoke(address,m,args[1]);assert(c.invoke(address,'isWorkAllowed')==args[1],'缓存纠缠器回读失败')end;return true end
    if m=='isWorkAllowed'or m=='isMachineActive'then for _,address in ipairs(g.generators)do if c.invoke(address,m)then return true end end;return false end
   end
   if a==g.transposer and type(args[1])=='number'then local function side(s)return s==4 and g.mainSide or s==5 and g.subSide or s end;args[1]=side(args[1]);if m=='transferFluid'then args[2]=side(args[2])end end
   return c.invoke(a,m,table.unpack(args))
  end
  local env=setmetatable({},{__index=_G});env._ENV=env
  local memo=discoveryByGroup[group]
  local discoveryPath=C.path('state/group-'..group..'/cache-discovery.dat')
  local function validSaved(v)
   if type(v)~='table'or v.version~=1 or v.binding~=ctx.formal or type(v.ports)~='table'or type(v.rawNames)~='table'then return false end
   local allowed={};for _,a in ipairs(g.bulkTransposers or {})do allowed[a]=true end
   local count=0
   for raw,r in pairs(v.ports)do
    count=count+1;if count>64 or type(raw)~='string'or #raw>80 or type(r)~='table'or not allowed[r.address]
     or not integer(r.from,0)or r.from>5 or not integer(r.to,0)or r.to>5 or r.from==r.to then return false end
   end
   count=0;for kind,raw in pairs(v.rawNames)do count=count+1;if count>64 or type(kind)~='string'or #kind>80 or type(raw)~='string'or #raw>80 then return false end end
   return true
  end
  if not memo then
   memo={rawNames={}}
   if not skipSavedDiscovery then local ok,saved=pcall(C.read,discoveryPath);if ok and validSaved(saved)then memo.ports=saved.ports;memo.rawNames=saved.rawNames;memo.persisted=ser.serialize(saved,false)end end
  end
  memo.catalogue=discoveredCatalogue;discoveryByGroup[group]=memo
  env.BEC_V3_CACHE_DISCOVERY=memo
  env.BEC_V3_CACHE_SAVE_DISCOVERY=function()
   if not memo.ports then return end
   local saved={version=1,binding=ctx.formal,ports=memo.ports,rawNames=memo.rawNames};local text=ser.serialize(saved,false)
   if text~=memo.persisted then C.write(discoveryPath,saved);memo.persisted=text end
  end
  env.BEC_V2_CACHE_GUARD=guard
  -- Waiting polls share the group/binding/disk read for at most one second.
  -- Every physical write still runs native.invoke's fresh guard above.
  local nextPollGuard=0
  env.BEC_V3_CACHE_POLL=function()
   assert(E.fluidOwner==ctx.token and E.groupOwner[group]==ctx.token,'缓存资源锁变化')
   if clock.uptime()>=nextPollGuard then guard();nextPollGuard=clock.uptime()+1 end
  end
  env.BEC_V3_CACHE_REQUEST_GUARD=guard
  if fs.exists(C.path('lib/cache_pipeline.lua'))then env.BEC_V3_CACHE_PIPELINE=assert(loadfile(C.path('lib/cache_pipeline.lua')))()end
  env.BEC_V2_CACHE_PRUNE=function()if not ctx.pruned then prune(group);ctx.pruned=true end end
  env.BEC_V2_CACHE_YIELD=function()
   if ctx.stop then return true end
   for _,t in ipairs(E.tasks)do if t.co and t.waitKind=='lock'then return true end end
   return false
  end
  env.print=function(...)local rows={...};for i,v in ipairs(rows)do rows[i]=tostring(v)end;log(table.concat(rows,' '));if C.pulse then C.pulse()end end
  local sleeping={};for k,v in pairs(os)do sleeping[k]=v end
  sleeping.sleep=function(seconds)coroutine.yield(clock.uptime()+(seconds or .1))end;env.os=sleeping
  env.require=function(name)
   if name=='component'then return native end
   if name=='event'then return {pull=function(seconds)coroutine.yield(clock.uptime()+(seconds or .1))end}end
   return require(name)
  end
  local f=assert(io.open(C.path('runtime/cache.lua'),'r'));local text=f:read('*a');f:close()
  local mapping={['3afdc4cf-04e3-4ae9-8be6-e753c23a249d']=cfg.mainInterface,
   ['86311657-33d1-41b5-a0d9-0aee7b5c2c50']=g.subInterface,['66fb280f-080d-4623-8d54-0dffd5cd5aad']=g.transposer,
   ['237a9cac-118a-4b74-8755-0d0b0ad216c0']=g.storage,['b04787f9-5423-4b03-8549-c786d4ef38d0']=n.address,
   ['c1ae3f7c-f714-4c27-baf3-392d94a0aa50']=g.generators[1]}
  text=text:gsub('%x+%-%x+%-%x+%-%x+%-%x+',function(a)return mapping[a]or a end)
  local function replace(before,after)text=text:gsub(before:gsub('([^%w])','%%%1'),function()return after end)end
  replace('"266f65b5"',string.format('%q',n.redstone));replace('"c1ae3f7c"',string.format('%q',g.generators[1]))
  replace('"/home/bec/recipes"',string.format('%q',cfg.recipeDirectory));replace('"/home/bec/recipes/"',string.format('%q',cfg.recipeDirectory..'/'))
  replace('"/home/bec_cache.journal"',string.format('%q',journal(group)));replace('"/home/bec_cache.config"',string.format('%q',path))
  guard();return assert(load(text,C.path('runtime/cache.lua'),'t',env))('background-stock',settings.target)
 end
 local function stopGenerators(group)for _,a in ipairs(cfg.groups[group].generators)do pcall(function()if c.invoke(a,'isWorkAllowed')~=false then c.invoke(a,'setWorkAllowed',false)end end)end end
 function K.step(E,running)
  if active then
   if not running or not settings.enabled then active.stop=true end
   if E.hasPendingFeed and E.hasPendingFeed(active.group)then active.stop=true;active.deadline=0 end
   if not active.stop and clock.uptime()<(active.deadline or 0)then return end
   local ok,result,reason=coroutine.resume(active.co)
   if ok and coroutine.status(active.co)~='dead'then active.deadline=result or clock.uptime();return end
   local group=active.group;stopGenerators(group)
   local record=C.read(journal(group));local clean=confirmed(record)
   if not ok or result==false or not clean then
    K.blocked=tostring(not ok and result or reason or '缓存记录未确认');log('缓存保护暂停：'..K.blocked)
   else
    E.groupOwner[group]=nil;if E.fluidOwner==active.token then E.fluidOwner=nil end
   end
   active=nil;K.busy=false;nextScan=clock.uptime()+5
   return
  end
  if not E or not running or K.blocked or not settings.enabled or clock.uptime()<nextScan or E.fluidOwner then return end
  nextScan=clock.uptime()+5
  scan();if #names==0 then K.message='尚无已登记配方，等待样板处理登记需求';return end
  for offset=0,#cfg.groups-1 do
   local group=(nextGroup+offset-1)%#cfg.groups+1;local g=cfg.groups[group]
   if not E.groupOwner[group]and not(E.hasPendingFeed and E.hasPendingFeed(group))then
   local ok,stock=pcall(c.invoke,g.storage,'getStoredCondensate');local needs=false
   if ok and type(stock)=='table'then for _,name in ipairs(names)do
    local amount=stock[name]or 0;local target=settings.overrides[name];if target==nil then target=settings.target end
    if type(amount)~='number'or amount<0 or amount%1~=0 then ok=false;break end
    if amount<target then needs=true end
   end else ok=false end
   if ok then displayedStock[group]=stock else K.message='缓存库存暂不可读，等待下次检查'end
   if ok and needs then
   local safe=true;local members=0
   local saved=C.read(C.path('state/group-'..group..'/cohort.dat'));if saved and saved.stage~='stopped'then safe=false end
   for i,n in ipairs(cfg.nodes)do if n.group==group then members=members+1
    local t=E.tasks[i];if t.disabled or t.fault or c.invoke(n.address,'getState')~='idle'then safe=false end
    local old=C.read(C.path('state/node-'..i..'/production.journal'))
    if old then
     if old.stage~='stopped'or old.pending~=nil or old.configOwned~=false then safe=false end
     for _,job in ipairs(old.requests or {})do if job.state~='done'then safe=false end end
    end
   end end
   for _,a in ipairs(g.generators)do if c.invoke(a,'isWorkAllowed')or c.invoke(a,'isMachineActive')then safe=false end end
   if safe and members>0 then
    K.assertReady();prune(group);local disk=storage.status();if not disk.known or not disk.ok then return end
    -- Cache owns the same physical supply path as production. Closing work
    -- permission prevents a new recipe from racing guard() as crafting while
    -- the immediate-pause signal is still being processed. AE priority checks
    -- remain active; admission is reopened by E only after clean lease release.
    for i,n in ipairs(cfg.nodes)do if n.group==group then if c.invoke(n.redstone,'getOutput',n.pauseSide)~=15 then c.invoke(n.redstone,'setOutput',n.pauseSide,15);assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'缓存暂停回读失败')end;E.nodeWork(i,false)end end
    active={group=group,token='cache-'..group,formal=B.read(C.path('config.dat')),pruned=true}
    E.groupOwner[group]=active.token;E.fluidOwner=active.token
    active.co=coroutine.create(function()return worker(group,E,active)end)
    K.busy=true;K.group=group;nextGroup=group%#cfg.groups+1;return
   end
   end end -- a busy group or a full stock needs no cache worker/admission scan
  end
 end
 function K.snapshot(group,fast)
  if not fast then local ok,err=pcall(scan);if not ok then K.message=tostring(err):sub(1,300)end;K.refreshStock(group)end
  local out={revision=B.revision(raw or ''),enabled=settings.enabled,target=settings.target,busy=K.busy,group=K.group or group,blocked=K.blocked~=nil,message=K.message,logs=K.logs,page=K.page,total=#names,rows={},catalogue={}}
  local stock=displayedStock[group]or {}
  -- Compact tuples let the browser show an unvisited page without an OC round
  -- trip. Production never consumes this display-only catalogue or inventory.
  for _,name in ipairs(names)do local value=settings.overrides[name]
   if value==nil then value=false end
   out.catalogue[#out.catalogue+1]={name,labels[name:gsub('^entangled_','')]or name,stock[name]or 0,value}
  end
  for i=K.page*8+1,math.min(#names,K.page*8+8)do local name=names[i];local override=settings.overrides[name]
   out.rows[#out.rows+1]={name=name,label=labels[name:gsub('^entangled_','')]or name,stock=stock[name]or 0,target=override~=nil and override or settings.target,override=override}
  end
  return out
 end
 function K.close()if active then active.stop=true;stopGenerators(active.group)end end
 return K
end
]=],supported={['15289:2748686704']=true,['15885:712537433']=true,['21604:3646529438']=true}},{name='lib/web_session.lua',added=false,source=[=[-- HTML is a data client. Only this Lua allowlist can save bindings or run V2.
local c=require('component');local clock=require('computer');local ser=require('serialization')
return function(C,B,W,options)
 local c=C.component and C.component(c)or c
 options=options or {}
 local H={running=false,group=1,notice='点击机器填写地址；草稿自动存到 OC，应用绑定后再启动。'}
 local path=C.path('config.dat');local expected=B.read(path)
 local cfg=expected and C.read(path)or {version=2,mainInterface='',recipeDirectory=C.path('recipes'),cacheTarget=144000,
  groups={{name='设备组 01',storage='',gate='',subInterface='',transposer='',mainSide=4,subSide=5,generators={},bulkTransposers={},nanites={enabled=false,mode='cell-io'}}},nodes={}}
 local draftPath=C.path('bindings.draft.dat');local raw=B.read(draftPath);local draft=raw and ser.unserialize(raw)
 local E,P,K
 local displayed={};local displayJobs,displayIndex,displayGroup,displayNext=nil,1,nil,0
 local displayedDisk={known=false,ok=false,reserve=524288}
 local storage=options.storage or assert(loadfile(C.path('lib/storage.lua')))()(C)
 -- BEC_WEB_CACHE_1: independent settings; worker shares production resource locks.
 local function cache()if not K then K=assert(loadfile(C.path('lib/cache.lua')))()(C,B,cfg,storage)end;return K end
 local function revision()return B.revision((expected or '')..'|'..(raw or ''))end
 local function fields()return B.draftFields(cfg,draft,expected)end
 local function payload(change)
  local out={'_revision='..revision()}
  for _,f in ipairs(fields())do out[#out+1]=f.key..'='..(change and change.key==f.key and change.value or f.value)end
  return table.concat(out,'\n')
 end
 -- BEC_COMPONENT_PICKER_1: on-demand, read-only discovery, six rows per snapshot.
 local scan,scanHistory
 scanHistory={}
 local required={storage={'getStoredCondensate','isWorkAllowed'},node={'getState','getRequiredCondensate','getRequiredTier','setWorkAllowed','isWorkAllowed'},
  generator={'getName','setWorkAllowed','isWorkAllowed','isMachineActive'},gate={'setCondensateFilters','getCondensateFilters','getCondensateFilterCount'},
  fluid={'transferFluid','getFluidInTank'},items={'transferItem','getInventorySize','getStackInSlot'},redstone={'setOutput','getOutput'},
  mainme={'getFluidsInNetwork','getCraftables','getCpus','setFluidInterfaceConfiguration'},subme={'getFluidsInNetwork'},workshop={'getItemsInNetwork','setInterfaceConfiguration','getInterfaceConfiguration'}}
 local function scanStep()
  if not scan or scan.status~='scanning'then return end
  for _=1,4 do
   local ok,a,kind=pcall(scan.iterator)
   if not ok then scan.status='failed';scan.message='组件枚举失败：'..tostring(a);return end
   if not a then
    local previous=scanHistory[scan.role];local current={};scan.baseline=previous~=nil
    for _,r in ipairs(scan.rows)do current[r.address]=true;r.fresh=previous~=nil and not previous[r.address]end
    scan.removed=0;if previous then for address in pairs(previous)do if not current[address]then scan.removed=scan.removed+1 end end end
    scanHistory[scan.role]=current
    table.sort(scan.rows,function(x,y)if x.fresh~=y.fresh then return x.fresh end;return x.address<y.address end);scan.status='done';return end
   scan.checked=scan.checked+1
   if scan.checked>2048 then scan.status='done';scan.message='扫描已达2048组件上限，请缩小OC网络后重扫';return end
   local success,m=pcall(c.methods,a)
   local match=success and type(m)=='table'
   if match then for _,method in ipairs(required[scan.role])do if m[method]==nil then match=false;break end end end
   local name=''
   if match and m.getName~=nil then
    local good,value=pcall(c.invoke,a,'getName');if good and type(value)=='string'then name=value:sub(1,80)end
   end
   if match and scan.role=='generator'and name~='multi.bec.generator'then match=false end
   if match then
    scan.rows[#scan.rows+1]={address=tostring(a):sub(1,64),kind=tostring(kind):sub(1,64),name=name}
    if #scan.rows>=512 then scan.status='done';scan.message='匹配已达512项，请缩小OC网络后重扫';return end
   end
  end
 end
 local function scanSnapshot()
  if not scan then return nil end
  local out={role=scan.role,token=scan.token,status=scan.status,page=scan.page,total=#scan.rows,checked=scan.checked,message=scan.message or '',removed=scan.removed or 0,baseline=scan.baseline==true,rows={}}
  local bound={};for _,f in ipairs(fields())do if f.kind=='uuid'and f.value~=''then bound[f.value]=(bound[f.value]and bound[f.value]..', 'or '')..f.key end end
  for i=scan.page*6+1,math.min(#scan.rows,scan.page*6+6)do local r=scan.rows[i]
   out.rows[#out.rows+1]={address=r.address,kind=r.kind,name=r.name,fresh=r.fresh==true,used=(bound[r.address]or ''):sub(1,140)}
  end
  return out
 end
 local function idleEditor()
  assert(not H.running,'先暂停自动化再编辑绑定')
  assert(not(P and P.co),'先等待样板处理结束或停止后再编辑绑定')
  assert(not(K and(K.busy or K.blocked)),'先暂停并等待缓存补库收尾；未确认缓存记录须保留核对，再编辑绑定')
  if E then for _,t in ipairs(E.tasks)do assert(not t.co,'等待工作器退出并保留日志后再编辑')end end
 end
 local function read(a,m,...)
  if not a or a==''then return nil end
  local ok,value=pcall(c.invoke,a,m,...);if ok then return value end
 end
 -- BEC_WEB_PATTERNS_1: resumes only between completed slot transactions.
 local function patternLog(...)
  local text={};for i=1,select('#',...)do text[i]=tostring(select(i,...))end
  local line=table.concat(text,' ')
  if P.slot>0 then P.rows[P.slot]=((P.rows[P.slot]or '')..line..'\n'):sub(1,380)end
  P.logs[#P.logs+1]=line:sub(1,220);while #P.logs>6 do table.remove(P.logs,1)end
 end
 local function patternStep()
  if not(P and P.co)then return end
  local ok,err=coroutine.resume(P.co)
  if not ok then P.co=nil;P.status='failed';P.message=tostring(err):sub(1,400);patternLog('处理失败：',P.message);H.notice=P.message;if K and P.mode~='preview'then K.invalidateCatalogue()end
  elseif coroutine.status(P.co)=='dead'then P.co=nil;P.status=P.stop and 'stopped'or 'done';P.message=P.stop and '已停止；已完成槽位和需求记录保留'or '本次样板检查/处理完成';H.notice=P.message;if K and P.mode~='preview'then K.invalidateCatalogue()end end
 end
 local function cleanDraft()
  assert(expected and B.read(path)==expected,'请先应用绑定；正式配置若被外部修改，请重新打开网页')
  local formal={};for _,f in ipairs(B.v2Fields(cfg))do formal[f.key]=f.value end
  for _,f in ipairs(fields())do assert(f.value==formal[f.key],'草稿尚未应用，请先应用绑定')end
 end
 -- BEC_V3_PAUSE_RESPONSE_1: cache edits and pause can run between callbacks.
 function H.canServeFast(request)
  return request.name=='pause'or request.name=='cache'and type(request.args)=='table'and K and K.canServeFast(request.args)
 end
 function H.handle(name,args,request)
  assert(type(args)=='table','页面参数必须为对象')
  assert(type(request)=='number'and request==math.floor(request)and request>0,'请求编号无效')
  if name=='recheck_all'then
   assert(not H.running and not(P and P.co),'请先暂停自动化并等待工作器收尾')
   assert(not cache().busy,'缓存工作器尚未收尾，请稍候再检查')
   assert(args.revision==revision(),'绑定已变化，请等待最新页面');cleanDraft()
   cache().action({mode='refresh'})
   local result=assert(loadfile(C.path('lib/recheck.lua')))()(C,cfg,E,storage,cache().inspectionCatalogue())
   local disk=storage.status();assert(disk.known and disk.ok,'磁盘不足，无法保存检查报告')
   C.write(C.path('diagnostics/recheck-last.dat'),result)
   H.recheck=result
   assert(result.ok,'全量检查未通过：'..table.concat(result.issues,'；'):sub(1,320))
   cache().clearCheckedFault(E);displayed={};displayJobs=nil
   H.notice='全量检查通过（'..result.checked..'项），可点击启动自动化。';return H.notice
  elseif name=='cache'then
   if args.mode=='page'or args.mode=='save'then assert(args.group==nil or args.group==H.group,'设备组已变化，忽略旧缓存请求')end
   if args.mode=='enable'then cleanDraft();C.validate(cfg,true)end
   H.notice=cache().action(args);return H.notice
  elseif name=='patterns'then
   if args.mode=='stop'then
    if P and P.co then P.stop=true;P.message='正在停止，当前槽位完成核对后退出';return P.message end
    return '没有正在执行的样板处理'
   end
   idleEditor();assert(args.mode=='preview'or args.mode=='run','仅支持预览或处理一次')
   assert(args.revision==revision(),'绑定已变化，请等待保存并应用后再试');cleanDraft()
   assert(cfg.workshopInterface and cfg.workshopInterface~='','先绑定并应用独立的样板工坊ME接口')
   local formal=expected;local mode=args.mode;scan=nil
   P={mode=mode,status='running',slot=0,logs={},rows={},message=mode=='preview'and '正在只读预览'or '正在处理样板副本'}
   P.co=coroutine.create(function()
    local hooks={raiseErrors=true,shouldStop=function()return P.stop==true end,
     beforeSlot=function(slot)
      assert(B.read(path)==formal,'样板处理期间正式配置变化，保留现场停止');P.slot=slot
      if mode=='run'then local disk=storage.status();assert(disk.known and disk.ok,'磁盘空间不足，停止样板处理并保留记录')end
     end,onSlot=function(slot)if not P.rows[slot]then P.rows[slot]='槽 '..slot..'：空槽'end;coroutine.yield()end}
    assert(loadfile(C.path('lib/patterns.lua')))()(C,mode,{print=patternLog,hooks=hooks})
   end)
   return P.message
  elseif name=='scan_components'then
   if args.close==true then scan=nil;return '已关闭组件选择'end
   assert(type(args.role)=='string'and required[args.role],'未知设备用途')
   local token=args.token or request;assert(type(token)=='number'and token>0 and token==math.floor(token)and token<=2147483647,'扫描标识无效')
   if args.page~=nil then
    assert(scan and scan.role==args.role and scan.status=='done','请先完成组件扫描')
    assert(type(args.page)=='number'and args.page==math.floor(args.page)and args.page>=0 and args.page<=math.floor(math.max(0,#scan.rows-1)/6),'组件页码无效');scan.page=args.page;scan.token=token
   else
    local iterator=c.list();scan={role=args.role,token=token,status='scanning',page=0,rows={},checked=0,iterator=iterator}
   end
   return '正在从这台OC的组件网络读取，未操作机器'
  elseif name=='select_group'then
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
   E=nil;K=nil;displayed={};displayJobs=nil;displayGroup=nil;H.started=false;H.notice='绑定已校验并应用，点击启动自动化。';return H.notice
  elseif name=='start'then
   assert(not H.running,'自动化已经运行')
   assert(not(P and P.co),'先停止或等待样板处理结束，再启动自动化')
   assert(B.read(path)==expected,'正式配置已被其他程序修改，请退出页面后重新打开')
   storage.prune(cfg);local disk=storage.status()
   assert(disk.known and disk.ok,'磁盘剩余空间不足或不可读：至少保留512KiB，暂停启动并保留恢复记录')
   assert(args.revision==revision(),'绑定已变化，请等最新快照后启动')
   local formal={};for _,f in ipairs(B.v2Fields(cfg))do formal[f.key]=f.value end
   for _,f in ipairs(fields())do assert(f.value==formal[f.key],'草稿尚未应用，请先应用绑定')end
   cfg=C.load();C.validate(cfg,true)
   cache().assertReady()
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
   H.running=true;H.notice='自动化运行中；节点按批次关闭接单，整组完成后再接下一单。'
   for _,g in ipairs(cfg.groups)do if g.cellFeed and g.cellFeed.enabled then H.notice='原料盘批次模式运行中：攒料10秒，搬盘后计数，自动分配最多16台节点。'end end
   return H.notice
  elseif name=='pause'then
   H.running=false;if P and P.co then P.stop=true end;if K then K.requestStop()end;if E then E.pauseAll()end;H.notice='已请求暂停；工作器收尾，未确认记录保留。';return H.notice
  elseif name=='refresh'then return '页面在线'
  end
  error('不支持的页面事件')
 end
 -- Display reads are spread across loop iterations. They never feed control guards.
 function H.observe(a,m,value)
  if m=='getState'or m=='isWorkAllowed'or m=='isMachineActive'then
   displayed[a]=displayed[a]or {};displayed[a][m]={value=value,at=clock.uptime()}
  elseif m=='getStoredCondensate'and K then
   for group,g in ipairs(cfg.groups)do if g.storage==a then K.observeStock(group,value)end end
  end
 end
 function H.displayStep()
  if displayGroup~=H.group then displayJobs=nil;displayNext=0;displayGroup=H.group end
  if not displayJobs then
   if clock.uptime()<displayNext then return end
   displayJobs={};displayIndex=1;local group=H.group;local g=cfg.groups[group]
   local function add(a,m)
    if not a or a==''then return end
    displayJobs[#displayJobs+1]=function()
     local recent=displayed[a]and displayed[a][m];if recent and clock.uptime()-recent.at<1 then return end
     local v=read(a,m);displayed[a]=displayed[a]or {};displayed[a][m]={value=v,at=clock.uptime()}
    end
   end
   add(g.storage,'isMachineActive');add(g.gate,'isMachineActive')
   for _,a in ipairs(g.generators)do add(a,'isMachineActive')end
   for _,n in ipairs(cfg.nodes)do if n.group==group then add(n.address,'getState');add(n.address,'isWorkAllowed')end end
   displayJobs[#displayJobs+1]=function()cache().refreshStock(group)end
   displayJobs[#displayJobs+1]=function()displayedDisk=storage.status()end
   displayJobs[#displayJobs+1]=function()cache().catalogueStep()end
  end
  local job=displayJobs[displayIndex];displayIndex=displayIndex+1
  if job then pcall(job)end
  if displayIndex>#displayJobs then displayJobs=nil;displayNext=clock.uptime()+.2 end
 end
 function H.step()
  H.displayStep()
  scanStep();patternStep()
  if K then
   local ok,err=pcall(K.step,E,H.running)
   if not ok then K.blocked=tostring(err);K.message=tostring(err):sub(1,300)end
   if K.blocked then local was=H.running;H.running=false;H.notice='缓存保护暂停：'..K.message;if E and was then E.pauseAll()end end
  end
  if not E then return end
  local draining=false;for _,t in ipairs(E.tasks)do if t.co then draining=true end end
  if H.running or draining then E.step()end
  if E.diskLow then H.running=false;H.notice='磁盘空间不足，自动化已暂停；当前及未确认日志保留，请腾出至少512KiB。'end
 end
 function H.snapshot(fast)
  local now=clock.uptime();local values={}
  for _,f in ipairs(fields())do
   local g=f.key:match('^g(%d+)%.')
   if not g or tonumber(g)==H.group then values[f.key]=f.value end
  end
  local out={mode=H.running and 'running'or 'binding',revision=revision(),values=values,group=H.group,groupCount=#cfg.groups,
   configured=expected~=nil,notice=H.notice,scan=scanSnapshot(),now=now,machines={},nodes={},flow={},timeline={},logs={},disk=fast and displayedDisk or storage.status()}
  out.cache=cache().snapshot(H.group,fast)
  if H.recheck then out.recheck={ok=H.recheck.ok,checked=H.recheck.checked,at=H.recheck.at,issues={}}
   for i=1,math.min(24,#H.recheck.issues)do out.recheck.issues[i]=H.recheck.issues[i]end
   out.recheck.more=math.max(0,#H.recheck.issues-24)
  end
  if P then out.patterns={mode=P.mode,status=P.status,slot=P.slot,message=P.message,logs=P.logs,rows=P.rows}end
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
  local function sample(a,m)
   if not fast then return read(a,m)end
   local item=displayed[a]and displayed[a][m]
   if item and now-item.at<=10 then return item.value end
  end
  local function actual(id,a)
   local active=sample(a,'isMachineActive');out.machines[id]=active==nil and 'unknown'or active and 'active'or 'idle'
  end
  actual('field',g.storage);actual('gate',g.gate)
  for j=1,math.max(1,#g.generators)do actual(j==1 and 'generator'or 'generator-'..j,g.generators[j])end
  local supply=out.phase=='supply';out.machines['fluid-transposer']=supply and 'phase'or 'idle'
  for j=1,10 do out.machines['bulk-transposer-'..j]=supply and 'phase'or 'idle'end
  out.machines['nanite-transposer']=out.phase=='nanites'and 'phase'or 'idle'
  for i,n in ipairs(cfg.nodes)do if n.group==H.group then
   local state=sample(n.address,'getState')or 'offline';local allowed=sample(n.address,'isWorkAllowed')
   out.nodes[#out.nodes+1]={slot=n.slot or i,state=state,workAllowed=allowed==true,name=n.name}
   out.machines['node-'..(n.slot or i)]=state=='crafting'and 'active'or state=='offline'and 'unknown'or 'idle'
  end end
  -- Leave room for transport metadata/completion within OCHD's 512-value,
  -- 16-KiB snapshot limits. Large catalogues retain the fast server page path.
  if out.cache and out.cache.catalogue then
   local function quoted(s)return #s+2+select(2,s:gsub('[%z\1-\31\\"]',''))*5 end
   local function cost(v)
    if type(v)~='table'then return 1,type(v)=='string'and quoted(v)or #tostring(v)end
    local nodes,bytes=1,2
    for k,x in pairs(v)do local n,b=cost(x);nodes=nodes+n;bytes=bytes+quoted(tostring(k))+b+2 end
    return nodes,bytes
   end
   local nodes,bytes=cost(out)
   if nodes>470 or bytes>14000 then out.cache.catalogue=nil end
  end
  return out
 end
 function H.close()
  if K then K.close()end
  if P and P.co then P.stop=true;patternStep()end
  H.running=false;if E then return E.shutdown()end;return {}
 end
 function H.engine()return E end
 return H
end
]=],supported={['18504:2508797642']=true,['19392:3751895150']=true,['19680:2005263336']=true}},{name='lib/web_transport.lua',added=false,source=[=[-- Heartbeats while large OC reads run. Receipt is not operation completion.
local clock=require('computer')
return function(panel,event,W,address)
 local T={queue={},next=0,last={mode='binding',values={},group=1,groupCount=1,configured=false,notice='正在读取 OC 配置和设备状态'},stopping=false}
 local polling=false
 local function receive(e)
  if e[1]=='key_down'and(e[3]==113 or e[3]==81)then T.stopping=true;return end
  if e[1]~='hd_panel_web'or e[2]~=address then return end
  local ok,args=pcall(W.decode,e[6])
  if not ok or type(args)~='table'then panel.ack(e[5],false,'页面参数无效');return end
  if #T.queue>=16 then panel.ack(e[5],false,'OC 请求队列已满，请等待当前操作完成');return end
  local token=args._token
  if type(token)~='string'or #token>64 then panel.ack(e[5],false,'网页版本不匹配，请重新打开页面');return end
  T.queue[#T.queue+1]={name=e[3],args=args,request=e[5],token=token}
  panel.ack(e[5],true,'BEC_REQUEST_ACCEPTED')
 end
 function T.pulse(force,address,method,value)
  if T.observe and address then T.observe(address,method,value)end
  if polling then return end;polling=true
  for i=1,8 do local e={event.pull(0)};if not e[1]then break end;receive(e)end
  -- BEC_V3_CACHE_RESPONSE_1: serve at most the queue head between worker calls.
  -- Keep FIFO, do not overwrite an undelivered completion, and never nest a
  -- handler inside another handler (C.write itself pulses during persistence).
  local request=T.queue[1]
  if request and not T.stopping and not T.handling and not T.pending and T.canServe and T.serve and T.canServe(request)then
   table.remove(T.queue,1);T.handling=true
   local ok,err=pcall(T.serve,request);T.handling=false
   assert(ok,err);T.next=0
  end
  local now=clock.uptime()
  if force or now>=T.next then
   local data=T.pending or(T.snapshot and T.snapshot())or T.last
   data.reply=T.reply
   data.transportProtocol=1;data.transportBusy=T.pending==nil;data.transportAt=now
   local accepted,reason=panel.publish(data)
   assert(accepted~=nil,reason)
   if accepted then T.last=data;T.pending=nil;T.next=clock.uptime()+.6 else T.next=clock.uptime()+.1 end
  end
  polling=false
 end
 function T.publish(data,reply)
  if reply then T.reply=reply end
  data.reply=T.reply;T.pending=data;T.pulse()
 end
 function T.poll(seconds)receive({event.pull(seconds or .05)});T.pulse()end
 function T.take()if not T.pending then return table.remove(T.queue,1)end end
 return T
end
]=],supported={['1959:2130565450']=true,['2480:4007365451']=true}},{name='web.lua',added=false,source=[=[local c=require('component');local event=require('event');local clock=require('computer')
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
]=],supported={['2184:2645903512']=true,['2306:1012168104']=true,['3206:2519455272']=true,['3288:275313463']=true}},{name='lib/web_page.html',added=false,source=(function()local f=assert(io.open('/home/bec_v2/lib/web_page.html','r'));local old=f:read('*a');f:close();old=old:gsub('\r\n','\n');if sig(old)=='234743:4111998488'then return old end;local known={['232745:4075596562']=true,['233112:3384946455']=true};assert(known[sig(old)],'未知本地网页，保留未覆盖');local new=old:sub(1,198594)..[=[,recheck_all:'正在全量重新检查设备和运行记录…'}[actPending]):actMessage?actMessage.text:reason;hint.classList.toggle('action-error',!!(actMessage&&actMessage.bad&&!actPending));hint.setAttribute('role',actMessage&&actMessage.bad?'alert':'status');$('start-run').textContent=!online?'状态待确认':running?'运行中':'启动自动化';$('start-run').disabled=!online||running||!!actPending||patternBusy||saving();$('start-run').title=reason;$('apply-config').disabled=!online||running||!!actPending||patternBusy||saving();$('stop-run').disabled=!online||!running||!!actPending;$('recheck-all').disabled=!online||running||!!actPending||patternBusy||saving();$('recheck-again').disabled=$('recheck-all').disabled;if(actPending==='recheck_all')$('recheck-report').textContent='正在检查全部设备和记录，请稍候…';else if(last&&last.recheck){var r=last.recheck;$('recheck-report').textContent=(r.ok?'全量检查通过，可启动自动化。':'全量检查未通过，请处理以下项目后再检查。')+'\n检查 '+r.checked+' 项\n'+list(r.issues).join('\n')+(r.more?'\n另有 '+r.more+' 项，完整报告在 OC diagnostics/recheck-last.dat':'');}}
function send(name,args){if(!online)return Promise.reject(Error('OC 未连接，未执行操作'));args=args||{};var token=String(Date.now())+'-'+(++seq);args._token=token;return new Promise(function(resolve,reject){requests[token]={resolve:resolve,reject:reject};OC.emit(name,args).then(function(r){if(r&&r.message==='BEC_REQUEST_ACCEPTED')return;if(requests[token]){delete requests[token];resolve(r||{});}}).catch(function(e){if(requests[token]){delete requests[token];reject(e);}});});}
function disconnect(){Object.keys(requests).forEach(function(k){var p=requests[k];delete requests[k];p.reject({message:'OC连接中断，操作结果待核对'});});}
function reply(r){if(!r)return;var p=requests[r.token];if(p){delete requests[r.token];r.ok?p.resolve(r):p.reject(r);}if(r.token===actTok){actPending=null;showAction(r.message,!r.ok);}if(r.token===cacheTok){cacheWait=false;cacheMessage=(r.ok?'':'未执行：')+r.message;}}
function key(id,k){var m={'field':'g'+group+'.storage','generator':'g'+group+'.generator1','gate':'g'+group+'.gate','main-me':'mainInterface','workshop-me':'workshopInterface','sub-me':'g'+group+'.subInterface','fluid-transposer':'g'+group+'.transposer','nanite-transposer':'g'+group+'.bee_transposer','load-redstone':'g'+group+'.bee_loadRedstone','return-redstone':'g'+group+'.bee_returnRedstone'};if(id.indexOf('node-')===0)return'n'+id.slice(5)+'.'+(k==='address'?'address':k==='redstone'?'redstone':k);if(k==='address')return m[id]||(id.indexOf('generator-')===0?'g'+group+'.generator'+id.slice(10):id.indexOf('bulk-transposer-')===0?'g'+group+'.bulk'+id.slice(16):null);return'g'+group+'.'+(['bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide'].indexOf(k)>=0?'bee_':'')+k;}
function fieldKeys(m){return['address'].concat(m.kind==='node'?['redstone','group','pauseSide','gate']:(m.sides||[]).map(function(f){return f[0];}));}
function toValues(draft){var out={};app.scene.modules.forEach(function(m){var v=draft.modules[m.id];if(!v||!m.role)return;fieldKeys(m).forEach(function(k){if(v[k]!=null){var name=key(m.id,k);if(name)out[name]=String(v[k]);}});});return out;}
function importValues(values){var draft={version:1,modules:{}};app.scene.modules.forEach(function(m){if(!m.role)return;var v={};fieldKeys(m).forEach(function(k){var value=values[key(m.id,k)];if(value!=null)v[k]=k==='address'||k==='redstone'||k==='gate'?value:Number(value);});draft.modules[m.id]=v;});receiving=true;app.importDraft(draft);receiving=false;}
function dirty(draft){if(receiving||switching||!last||last.mode==='running'||last.patterns&&last.patterns.status==='running')return;var values=toValues(draft);Object.keys(values).forEach(function(k){if(values[k]!==last.values[k]||(saveOp&&saveOp.key===k&&saveOp.value!==values[k])||(waiting&&waiting.key===k&&waiting.value!==values[k]))queue[k]=values[k];});status('正在保存到 OC…');pump();}
window.BEC_BINDING_DIRTY=dirty;function pump(){if(inflight||waiting||failed||switching||!online||!last)return;var keys=Object.keys(queue);if(!keys.length){status('草稿已保存到 OC');return;}var k=keys[0],v=queue[k],revision=last.revision;delete queue[k];inflight=true;saveOp={key:k,value:v};status('正在保存到 OC…');send('save_field',{key:k,value:v,revision:revision}).then(function(){inflight=false;saveOp=null;waiting={revision:revision,key:k,value:v};if(last&&(last.revision!==revision||last.values[k]===v)){waiting=null;pump();}}).catch(function(e){inflight=false;saveOp=null;if(!Object.prototype.hasOwnProperty.call(queue,k))queue[k]=v;failed=true;status('保存未确认 · 点击重试',true);$('runtime-notice').textContent=e.message;});}
function syncModels(d){var scene=app.scene,base=scene.modules.find(function(m){return m.id==='generator';});if(!base)return;var count=Math.min(16,Math.max(4,d.generatorSlots||4));scene.modules=scene.modules.filter(function(m){return m.id.indexOf('generator-')!==0||Number(m.id.slice(10))<=count;});if(!scene.modules.some(function(m){return m.id===scene.selected;}))scene.selected='assembler';for(var j=2;j<=count;j++)if(!scene.modules.some(function(m){return m.id==='generator-'+j;})){var m=Object.assign({},base),dx=Math.floor((j-1)/4)*40,dz=((j-1)%4)*26;m.id='generator-'+j;m.title='纠缠器 '+String(j).padStart(2,'0');m.role='groups['+group+'].generators['+j+']';m.p=[base.p[0]+dx,base.p[1],base.p[2]+dz];m.center=[base.center[0]+dx,base.center[1],base.center[2]+dz];m.marker=[base.marker[0]+dx,base.marker[1],base.marker[2]+dz];scene.modules.push(m);}
scene.modules.forEach(function(m){if(m.role)m.role=m.role.replace(/^groups\[\d+\]/,'groups['+group+']');if(m.kind==='generator')m.role='groups['+group+'].generators['+(m.id==='generator'?1:m.id.slice(10))+']';});scene.runtimeGroup=group;scene.runtimeValues=d.values||{};scene.request();}
function markMachines(){if(!last)return;app.scene.liveStates=last.machines||{};document.querySelectorAll('[data-label],[data-module]').forEach(function(el){el.dataset.live=(last.machines||{})[el.dataset.label||el.dataset.module]||'unknown';});}
var render=app.scene.onRender;app.scene.onRender=function(s){render(s);markMachines();pickerButtons();};function flow(){if(!last)return;var age=online?Math.min(3,(Date.now()-seenAt)/1000):0,active=last.mode==='running'&&last.phase!=='idle'&&last.phase!=='finish'&&!last.fault;var elapsed=(last.elapsed||0)+(active?age:0);$('flow-elapsed').textContent=time(elapsed);$('flow-current').textContent=titles[last.phase]||last.phase;$('flow-stage-time').textContent='当前步骤 '+time((last.phaseElapsed||0)+(active?age:0));$('flow-steps').innerHTML=order.map(function(p,i){var duration=Number((last.flow||{})[p]||0)+(active&&p===last.phase?age:0),current=last.phase===p,done=duration>0&&!current;return'<div class="flow-step '+(current?'current ':done?'done ':'')+(current&&last.fault?'fault':'')+'"><div class="index">'+(done?'✓ ':String(i+1).padStart(2,'0'))+'</div><strong>'+titles[p]+'</strong><time>'+((duration>0||current)?time(duration):'待执行')+'</time></div>';}).join('');$('node-status-list').innerHTML=(Array.isArray(last.nodes)?last.nodes:[]).map(function(n){return'<span class="node-chip '+(n.state==='crafting'?'active':'')+'">N'+String(n.slot).padStart(2,'0')+' · '+esc(n.state)+' · '+(n.workAllowed?'允许接单':'关闭接单')+'</span>';}).join('')||'<span class="node-chip">尚未绑定节点</span>';var machines=Object.keys(last.machines||{}).filter(function(id){return id==='field'||id==='gate'||id.indexOf('generator')===0;}).map(function(id){var active=last.machines[id]==='active';return'<span class="node-chip '+(active?'active':'')+'">'+(id==='field'?'约束场':id==='gate'?'韦门':id==='generator'?'纠缠器 1':'纠缠器 '+id.split('-')[1])+' · '+(active?'运行中':last.machines[id]==='unknown'?'不可读':'未运行')+'</span>';}).join('');$('node-status-list').innerHTML=machines+$('node-status-list').innerHTML;var events=(Array.isArray(last.timeline)?last.timeline:[]).map(function(e){return'+'+time(e.offset)+'  '+(titles[e.phase]||e.phase);});$('runtime-log').textContent=events.concat(Array.isArray(last.logs)?last.logs:[]).join('\n');}
function data(d){var changed=group!==(d.group||1);last=d;online=d._online!==false;seenAt=Date.now();group=d.group||1;if(switching===group)switching=null;if(waiting&&(waiting.revision!==d.revision||(d.values||{})[waiting.key]===waiting.value))waiting=null;reply(d.reply);if(!online)disconnect();syncModels(d);if(!switching&&!inflight&&!waiting&&!Object.keys(queue).length&&(changed||!/INPUT|TEXTAREA/.test(document.activeElement.tagName)))importValues(d.values||{});$('runtime-notice').textContent=(online?'':'OC 离线，显示最后快照。')+(d.notice||'')+(d.disk&&d.disk.known?' · 磁盘剩余 '+(d.disk.free/1024).toFixed(0)+' KiB / 保留 '+(d.disk.reserve/1024).toFixed(0)+' KiB':' · 磁盘容量不可读');$('runtime-notice').classList.toggle('offline-alert',!online);document.body.classList.toggle('runtime-running',d.mode==='running');$('flow-panel').hidden=false;buttons();$('global-settings').disabled=d.mode==='running'||!!(d.patterns&&d.patterns.status==='running');document.body.classList.toggle('pattern-busy',!!(d.patterns&&d.patterns.status==='running'));renderPatterns();cacheView();if(!online)status('OC 离线 · 未保存操作',true);else if(failed)status('保存未确认 · 点击重试',true);else if(!inflight&&!waiting&&!Object.keys(queue).length)status('OC 已连接 · 草稿已保存');if($('group-select').options.length!==d.groupCount){$('group-select').innerHTML=Array.from({length:d.groupCount||1},function(_,i){return'<option value="'+(i+1)+'">设备组 '+String(i+1).padStart(2,'0')+'</option>';}).join('');}$('group-select').value=group;if(window.BEC_REFRESH_SELECTS)window.BEC_REFRESH_SELECTS();markMachines();flow();pump();renderPicker(d.scan);}
function pickerRole(id,field){if(field==='redstone'||id==='load-redstone'||id==='return-redstone')return'redstone';if(field==='gate'||id==='gate')return'gate';if(id.indexOf('node-')===0)return'node';if(id==='field')return'storage';if(id.indexOf('generator')===0)return'generator';if(id==='main-me')return'mainme';if(id==='sub-me')return'subme';if(id==='workshop-me')return'workshop';if(id==='nanite-transposer')return'items';return'fluid';}
function pickerButtons(){['address','redstone','gate'].forEach(function(field){var input=$('field-'+field);if(!input||!input.parentNode)return;var existing=input.parentNode.querySelector('.pick-component');if(existing){existing.disabled=!online||last&&last.mode==='running';return;}var b=document.createElement('button');b.type='button';b.className='pick-component';b.textContent='从 OC 识别 / 选择';b.disabled=!online||last&&last.mode==='running';b.onclick=function(){openPicker(app.scene.selected,field);};input.parentNode.appendChild(b);});}
function openPicker(id,field){if(pickWait){showAction('请等待上一次扫描请求返回，再打开选择框。',true);return;}
if(!online||last.mode==='running'){showAction('先连接 OC 并暂停自动化，再识别绑定。',true);return;}
if(saving()){showAction('请先等待草稿保存完成。',true);return;}
picking={id:id,field:field,key:key(id,field),role:pickerRole(id,field)};$('component-picker').showModal();var model=app.scene.modules.find(function(m){return m.id===id;});$('picker-title').textContent='识别 / '+(model?model.title:id)+' · '+({address:'设备地址',redstone:'暂停红石',gate:'独立韦门'}[field]||field);scanPicker();}
function scanPicker(page){if(!picking||pickWait)return;pickWait=true;$('picker-status').textContent='读取 OC 组件中…';$('picker-results').innerHTML='';picking.token=++pickSeq;var args={role:picking.role,token:picking.token};if(page!=null)args.page=page;send('scan_components',args).then(function(){pickWait=false;}).catch(function(e){pickWait=false;$('picker-status').textContent='扫描失败：'+e.message;});}
function closePicker(){picking=null;$('component-picker').close();}
function bindingName(k){var n=k.match(/^n(\d+)\.(.+)$/),g=k.match(/^g(\d+)\.(.+)$/),labels={address:'节点组件',redstone:'暂停红石',gate:'韦门',storage:'约束场',subInterface:'原液子网ME接口',transposer:'供液转运器',bee_transposer:'蜂群转运器',bee_loadRedstone:'装入端口红石',bee_returnRedstone:'回收端口红石',mainInterface:'主网ME接口',workshopInterface:'样板工坊ME接口'};if(n)return'节点'+n[1]+' '+(labels[n[2]]||n[2]);if(g)return'组'+g[1]+' '+(labels[g[2]]||g[2].replace('generator','纠缠器').replace('bulk','高速供液口'));return labels[k]||k;}
function renderPicker(scan){pickerButtons();if(!picking||!scan||scan.role!==picking.role||scan.token!==picking.token||pickWait)return;$('picker-status').textContent=scan.status==='scanning'?'扫描中，已检查 '+scan.checked+' 个组件…':scan.status==='failed'?scan.message:'找到 '+scan.total+' 项 · 第 '+(scan.page+1)+' 页'+(scan.baseline?' · 比上次减少 '+scan.removed+' 项':' · 首次扫描作为比较基准')+(scan.message?' · '+scan.message:'');$('picker-results').innerHTML=list(scan.rows).map(function(r){return'<button class="component-choice" type="button" data-address="'+esc(r.address)+'"><strong>'+(r.fresh?'新增 / 重新接入 · ':'')+esc(r.kind)+'</strong><code>'+esc(r.address)+'</code><small>'+esc(r.name||'')+(r.used?' · 已填写于 '+esc(r.used.split(', ').map(bindingName).join('、')):' · 尚未填写')+'</small></button>';}).join('')||(scan.status==='done'?'<p>没有匹配设备。当前 OC 组件网络看不到这种设备，检查适配器连接及 P2P。</p>':'');$('picker-results').querySelectorAll('button').forEach(function(b){b.onclick=function(){if(!picking||!online||last.mode==='running'||saving()){showAction('状态已改变，请等待保存完成并保持暂停后重新选择。',true);return;}
var selected=picking;app.select(selected.id);var input=$('field-'+selected.field);if(!input){$('picker-status').textContent='当前字段不可用，请关闭后重试';return;}
input.value=b.dataset.address;input.dispatchEvent(new Event('input',{bubbles:true}));closePicker();showAction('已选择 OC 实际地址，正在保存草稿；方向和节点配对仍需按实物确认。',false);};});$('picker-prev').disabled=scan.status!=='done'||scan.page===0;$('picker-next').disabled=scan.status!=='done'||(scan.page+1)*6>=scan.total;$('picker-prev').onclick=function(){scanPicker(scan.page-1);};$('picker-next').onclick=function(){scanPicker(scan.page+1);};}
function bindingIssues(){var v=last&&last.values||{},p='g'+group+'.',issues=[],uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;function value(k){return String(v[k]||'').trim();}
function add(label,id,field){issues.push({label:label,id:id,field:field||'address'});}
function address(k,label,id,required,field){var x=value(k);if(!x&&required)add(label+'：未填写',id,field);else if(x&&!uuid.test(x))add(label+'：地址需为完整 UUID',id,field);}
address('mainInterface','主网供液 ME 接口','main-me',true);address(p+'storage','约束场','field',true);address(p+'subInterface','原液子网 ME 接口','sub-me',true);address(p+'transposer','供液转运器','fluid-transposer',true);var generators=0;for(var j=1;j<=Math.max(4,last.generatorSlots||4);j++){var k=p+'generator'+j;if(value(k))generators++;address(k,'纠缠器 '+j,j===1?'generator':'generator-'+j,false);}if(!generators)add('至少填写一台纠缠器','generator');address(p+'gate','公共韦门','gate',false);address('workshopInterface','样板工坊 ME 接口','workshop-me',false);for(var j=1;j<=10;j++)address(p+'bulk'+j,'高速供液口 '+j,'bulk-transposer-'+j,false);var bees=[['transposer','蜂群转运器','nanite-transposer'],['loadRedstone','装入端口红石','load-redstone'],['returnRedstone','回收端口红石','return-redstone']],beeOn=bees.some(function(b){return!!value(p+'bee_'+b[0]);});bees.forEach(function(b){address(p+'bee_'+b[0],b[1],b[2],beeOn);});if(v[p+'mainSide']===v[p+'subSide'])add('供液主网侧与子网侧不能相同','fluid-transposer');if(beeOn){var sides=['bankSide','loadSide','returnSide'].map(function(k){return v[p+'bee_'+k];});if(sides.some(function(x,i){return sides.indexOf(x)!==i;}))add('蜂群箱子、装入端口、回收端口必须是三个不同方向','nanite-transposer');}
var total=0,localCount=0;for(var i=1;i<=16;i++){var n='n'+i+'.';if(!value(n+'address')&&!value(n+'redstone'))continue;total++;if(Number(v[n+'group'])!==group)continue;localCount++;address(n+'address','节点 '+i+' 组件','node-'+i,true);address(n+'redstone','节点 '+i+' 暂停红石','node-'+i,true,'redstone');address(n+'gate','节点 '+i+' 独立韦门','node-'+i,false,'gate');if(!value(n+'gate')&&!value(p+'gate'))add('节点 '+i+' 需要韦门：填写独立韦门或本组公共韦门','node-'+i,'gate');}
if(!total)add('至少填写一组传送节点和暂停红石，空位会自动跳过','node-1');else if(!localCount)add('当前设备组还没有分配传送节点','node-1','group');if(!value('recipeDirectory'))add('配方目录：未填写','settings');return issues;}
function showIssues(issues){$('binding-issues-list').innerHTML=issues.map(function(x){return'<button type="button" data-issue-module="'+esc(x.id)+'" data-issue-field="'+esc(x.field)+'">'+esc(x.label)+' → 去填写</button>';}).join('');$('binding-issues-list').querySelectorAll('button').forEach(function(b){b.onclick=function(){$('binding-issues').close();if(b.dataset.issueModule==='settings'){settings();return;}document.body.classList.toggle('flow-full',false);app.select(b.dataset.issueModule);var field=$('field-'+b.dataset.issueField);if(field)field.focus();};});$('binding-issues').showModal();showAction('当前设备组有 '+issues.length+' 项绑定需要补充或修正，点击清单可跳转。',true);}
function action(name){if(actPending)return;if(saving()){showAction('请先等待草稿保存完成。',true);return;}
if(name==='start'&&last&&!last.configured){showAction('尚未应用绑定：请先点击「应用绑定」。如果校验失败，这里会显示具体原因。',true);return;}
if(name==='apply_bindings'){var issues=bindingIssues();if(issues.length){showIssues(issues);return;}}
actMessage=null;actPending=name;buttons();var args={revision:last&&last.revision},request=send(name,args);actTok=args._token;request.then(function(r){actPending=null;showAction(r.message||'请求已确认，等待 OC 状态更新。',false);}).catch(function(e){actPending=null;showAction((name==='apply_bindings'?'应用绑定失败：':name==='start'?'启动失败：':'暂停失败：')+e.message,true);});}
function renderPatterns(){var p=last&&last.patterns,busy=p&&p.status==='running';$('patterns-status').textContent=p?({running:'进行中',done:'已完成',failed:'处理失败',stopped:'已停止'}[p.status]||p.status)+' · 槽位 '+p.slot+' / 9 · '+p.message:!last||!last.configured?'请先绑定并应用独立的样板工坊 ME 接口。':'先预览工坊接口内的样板，再处理原样板的副本。';$('patterns-log').textContent=p?(list(p.rows).join('\n')+'\n'+list(p.logs).join('\n')):'';['patterns-preview','patterns-run'].forEach(function(id){$(id).disabled=!online||!last||last.mode==='running'||!last.configured||busy||patPending||saving();});$('patterns-stop').disabled=!online||!busy||patPending;$('patterns-open').textContent=busy?'样板处理中':'样板处理';$('patterns-target').textContent=last?'工坊接口：'+(last.values.workshopInterface||'未绑定')+' · 配方目录：'+(last.values.recipeDirectory||'未设置'):'';}
function patternAction(mode){if(patPending)return;if(mode!=='stop'&&saving()){$('patterns-status').textContent='请先等待草稿保存完成。';return;}
patPending=true;renderPatterns();$('patterns-status').textContent=mode==='stop'?'正在请求停止…':'正在提交样板操作…';send('patterns',{mode:mode,revision:last&&last.revision}).then(function(r){patPending=false;renderPatterns();$('patterns-status').textContent=r.message||'请求已确认，等待处理状态。';}).catch(function(e){patPending=false;renderPatterns();$('patterns-status').textContent='未执行：'+e.message;showAction('样板操作失败：'+e.message,true);});}
function settings(){if(!last)return;var specs=[['recipeDirectory','配方目录']];for(var i=1;i<=Math.max(4,last.generatorSlots||4);i++)specs.push(['g'+group+'.generator'+i,'纠缠器 '+i+'（多余可空）']);$('extra-fields').innerHTML=specs.map(function(f){return'<label>'+f[1]+'<input data-config="'+f[0]+'" value="'+esc(last.values[f[0]]||'')+'" maxlength="160" spellcheck="false"></label>';}).join('');$('extra-fields').querySelectorAll('input').forEach(function(input){input.onchange=function(){queue[input.dataset.config]=input.value;pump();};});$('runtime-settings').showModal();}
document.querySelector('.top-actions').innerHTML='<span id="save-status" class="save-status">等待 OC 连接</span><button class="button quiet" id="patterns-open">样板处理</button><button class="button quiet" id="global-settings">公共设置</button><button class="button quiet" id="apply-config">应用绑定</button><button class="button quiet" id="recheck-all">全量重新检查</button><button class="button primary run-button" id="start-run">启动自动化</button><button class="button quiet stop-button" id="stop-run">暂停</button>';var recheckDialog=document.createElement('dialog');recheckDialog.id='recheck-dialog';recheckDialog.className='runtime-settings';recheckDialog.innerHTML='<h2>全量重新检查</h2><p>检查全部设备组、节点、供液、蜂群、盘位和运行记录。修好设备后可再次检查；未确认申请或搬运会继续保留保护。</p><pre id="recheck-report" style="white-space:pre-wrap">等待检查</pre><footer><button id="recheck-again" class="button">再次检查</button><button id="recheck-close" class="button primary">关闭</button></footer>';document.body.appendChild(recheckDialog);$('recheck-all').onclick=function(){$('recheck-dialog').showModal();$('recheck-report').textContent='正在检查全部设备和记录，请稍候…';action('recheck_all');};$('recheck-again').onclick=function(){action('recheck_all');};$('recheck-close').onclick=function(){$('recheck-dialog').close();};var feedback=document.createElement('div');feedback.id='action-feedback';feedback.className='action-feedback';feedback.textContent='等待 OC 连接…';feedback.setAttribute('aria-live','polite');document.body.appendChild(feedback);var tabs=document.createElement('nav');tabs.className='runtime-tabs';tabs.innerHTML='<button class="active" data-tab="structure">结构 / 绑定</button><button data-tab="flow">运行流程</button><button data-tab="cache">缓存管理</button>';document.querySelector('.topbar').insertBefore(tabs,document.querySelector('.top-actions'));var cacheUI={},cacheRead=false,cacheReadNext=null,cacheWait=false,cacheWaiting=null,cacheMessage='',cachePageMessage='',cacheStamp='',cachePanel=document.createElement('section');cachePanel.id='cache-panel';cachePanel.innerHTML='<h1>缓存管理</h1><p>只补已登记配方流体，生产优先。单项留空用默认值，0 停补；按转换批量向上取整，库存可略超目标。</p><div class="cache-actions"><label>默认库存目标（mB） <input id="cache-default" inputmode="numeric" maxlength="10"></label><button id="cache-save-default" class="button">保存默认值</button><button id="cache-enable" class="button primary">启用自动补库</button><button id="cache-disable" class="button">停止补库</button><button id="cache-refresh" class="button">刷新库存</button></div><p id="cache-status" role="status"></p><p id="cache-feedback" role="status"></p><div id="cache-rows"></div><div id="cache-nav" class="cache-actions"><button id="cache-prev" class="button">上一页</button><span id="cache-page"></span><button id="cache-next" class="button">下一页</button></div><pre id="cache-log"></pre>';document.body.appendChild(cachePanel);function cacheState(){var k=last.cache,u=cacheUI[group];if(!u)u=cacheUI[group]={page:k.page,pages:{},edits:{},total:k.total};return u;}
function cacheBrowse(page){if(!last||!last.cache)return;var u=cacheState();u.page=Math.max(0,Math.min(page,Math.max(0,Math.ceil(u.total/8)-1)));cacheStamp='';cacheView();if(online&&!Array.isArray(last.cache.catalogue)){cacheReadNext={group:group,page:u.page};cacheReadPage();}}
function cacheReadPage(){if(cacheRead||!cacheReadNext||!online)return;var q=cacheReadNext;cacheReadNext=null;if(q.group!==group)return;cacheRead=true;send('cache',{mode:'page',page:q.page,group:q.group}).then(function(){cacheRead=false;cachePageMessage='';cacheReadPage();cacheView();}).catch(function(e){cacheRead=false;if(q.group===group)cachePageMessage='翻页未确认：'+e.message;cacheReadPage();cacheView();});}
function cacheAction(mode,name,value,page){if(cacheWait||!last||!last.cache)return;cacheWait=true;cacheWaiting=last.cache.revision;cacheMessage='正在提交…';cacheView();var args={mode:mode,name:name,value:value,page:page,group:group,revision:last.cache.revision},request=send('cache',args);cacheTok=args._token;request.then(function(r){cacheWait=false;cacheMessage=r.message||'已确认，等待库存更新';cacheView();}).catch(function(e){cacheWait=false;cacheMessage='未执行：'+e.message;cacheView();});}
function cacheView(){var k=last&&last.cache;if(!k)return;$('cache-status').textContent=(!online?'离线，显示最后状态 · ':last.transportBusy?'OC正在读取，显示上次机器状态 · ':'')+(k.enabled?'自动补库已启用':'自动补库未启用')+' · '+(last.mode==='running'?'自动化运行中':'启动自动化后开始补库')+' · '+(k.busy?'设备组 '+k.group+' 补库中 · ':'')+k.message;var u=cacheState();if(u.total!==k.total){u.pages={};u.total=k.total;u.page=Math.min(u.page,Math.max(0,Math.ceil(k.total/8)-1));}u.pages[k.page]=list(k.rows);var allRows=Array.isArray(k.catalogue)?k.catalogue.map(function(r){return{name:r[0],label:r[1],stock:r[2],override:r[3]===false?null:r[3],target:r[3]===false?k.target:r[3]};}):null;if(allRows){u.pages={};for(var page=0;page<Math.ceil(allRows.length/8);page++)u.pages[page]=allRows.slice(page*8,page*8+8);}
(allRows||list(k.rows)]=]..old:sub(-9689);assert(sig(new)=='234743:4111998488','网页补丁核对失败，原文件未改');return new end)(),supported={['232745:4075596562']=true,['233112:3384946455']=true}},{name='runtime/cache.lua',added=false,source=[=[-- V2 adapter of V1 bec_cache.lua; original transfer/AE/conversion protocol retained.
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
if not enabled and call(GEN,"isWorkAllowed")==false then return end -- no-op stop needs no write/group guard
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
end
local discovery=BEC_V3_CACHE_DISCOVERY -- Session memo; bindings recreate the host.
if discovery then for kind,raw in pairs(discovery.rawNames)do
 local base=mapping[kind]
 local valid=base and (raw==base or raw=='fluid.'..base or kind=='entangled_space'and(raw=='spatialfluid'or raw=='fluid.spatialfluid')or kind=='entangled_time'and(raw=='temporalfluid'or raw=='fluid.temporalfluid'))
 if not valid then discovery.rawNames[kind]=nil end
end end
local function probeRoute(route,raw)
 if call(route.address,"getTankCount",route.from)~=1 or call(route.address,"getTankCapacity",route.from,1)~=2147483647
  or call(route.address,"getTankCount",route.to)~=6 or call(route.address,"getTankCapacity",route.to,1)~=16000 then return false end
 local f=call(route.address,"getFluidInTank",route.from,1);if type(f)=="table"and type(f[1])=="table"then f=f[1]end
 return type(f)=="table"and (f.name==raw or not f.name and tonumber(f.amount or 0)==0)
end
local function bulkPorts(required)
 if discovery and discovery.ports then
  local valid=true
  for kind in pairs(required or {})do
   local raw=mapping[kind];local route=discovery.ports[raw]
   local ok,match=false,false;if route then ok,match=pcall(probeRoute,route,raw)end
   if not ok or not match then valid=false;break end
  end
  if valid then return discovery.ports end
  discovery.ports=nil;discovery.rawNames={}
 end
 local allowed,ports,ambiguous={},{},{}
for _,raw in pairs(mapping) do allowed[raw]=true;allowed["fluid."..raw]=true end
for _,raw in ipairs({"spatialfluid","fluid.spatialfluid","temporalfluid","fluid.temporalfluid"}) do allowed[raw]=true end for address,kind in c.list("transposer") do if kind=="transposer" and address~=TRANS then
local sources,receivers={},{} for side=0,5 do local ok,count=pcall(call,address,"getTankCount",side)
if ok and count==1 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==2147483647 then
local f=call(address,"getFluidInTank",side,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end if type(f)=="table" and allowed[f.name] then sources[#sources+1]={from=side,raw=f.name} end
end elseif ok and count==6 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1)
if readable and capacity==16000 then receivers[#receivers+1]=side end end end
if #sources>0 then assert(#receivers==1,"高速供液口接收方向缺失或不唯一: "..address) for _,source in ipairs(sources) do
local previous=ports[source.raw]
if previous and(previous.address~=address or previous.from~=source.from or previous.to~=receivers[1])then ambiguous[source.raw]=true;ports[source.raw]=nil
elseif not ambiguous[source.raw]then ports[source.raw]={address=address,from=source.from,to=receivers[1]}end end
end end end
-- Alias discovery scans all configured ports, even when only one kind is
-- missing. Omit unrelated ambiguous sources; never choose one arbitrarily.
for raw in pairs(ambiguous)do for kind in pairs(required or{})do local base=mapping[kind]
local needed=raw==base or raw=='fluid.'..base or kind=='entangled_time'and(raw=='temporalfluid'or raw=='fluid.temporalfluid')or kind=='entangled_space'and(raw=='spatialfluid'or raw=='fluid.spatialfluid')
assert(not needed,'高速供液口重复绑定: '..raw)end end
if discovery then discovery.ports=ports;if BEC_V3_CACHE_SAVE_DISCOVERY then BEC_V3_CACHE_SAVE_DISCOVERY()end end
return ports end local function verifyBulk(route,raw,allowEmpty)
local f=call(route.address,"getFluidInTank",route.from,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end assert(type(f)=="table" and (f.name==raw or allowEmpty and not f.name and integer(f.amount or 0)==0)
and call(route.address,"getTankCapacity",route.from,1)==2147483647,"高速缓存口绑定已变化") assert(call(route.address,"getTankCount",route.to)==6,"高速接收接口已变化") for i=1,6 do
local tank=call(route.address,"getFluidInTank",route.to,i) if type(tank)=="table" and type(tank[1])=="table" then tank=tank[i] or tank[1] end assert(type(tank)=="table" and integer(tank.amount or 0)==0,"高速接收接口有未处理缓存")
end end local function unchanged()
if BEC_V3_CACHE_POLL then BEC_V3_CACHE_POLL();return field()end
local state=call(NODE,"getState") local blocked={idle=true,["paused-immediate"]=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true} assert(state=="idle" or (background and blocked[state]),"节点状态变化，停止预缓存并保留已有库存")
assert(call(RS,"getOutput",sides.top)==15,"暂停信号变化") return field() end
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

local function prepareStreaming(target) local ports=bulkPorts(target) local stock,previous=field(),network(SUB)
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
local partialCredit=false
if record.initialRawCredit then for name in pairs(target)do local raw=mapping[name];local n=previous[raw]or 0
 assert(n==(record.initialRawCredit[raw]or 0),'恢复后原液信用变化')
 if n%(units[name]or 144)~=0 then partialCredit=true end
end end
if productionWaiting()and not partialCredit then return handoff() end

for name,need in pairs(target) do local raw=mapping[name]
local batch=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0
assert(amount==0 or ports[raw],"缺少高速供液口："..raw.."；禁止普通接口回退")
assert(existing<=amount and(existing%batch==0 or record.initialRawCredit and record.initialRawCredit[raw]==existing),"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end raws[#raws+1]={raw=raw,amount=amount,batch=batch}
end for raw in pairs(previous) do local allowed=false
for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end
for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned")
if BEC_V3_CACHE_PIPELINE then
 return BEC_V3_CACHE_PIPELINE({items=raws,record=record,previous=previous,expected=expected,ports=ports,
  main=MAIN,sub=SUB,call=call,network=network,same=same,save=save,log=print,now=computer.uptime,
  emptyConfig=emptyConfig,tanks=tanks,verifyBulk=verifyBulk,waitUntil=waitUntil,unchanged=unchanged,tick=tick,
  stopping=function()return stopping end,productionWaiting=productionWaiting,handoff=handoff,
  requestGuard=BEC_V3_CACHE_REQUEST_GUARD,
  poll=function()assert(same(unchanged(),stock),"备料时约束场库存变化");assert(same(network(SUB),previous),"备料时子网库存变化")end})
end
for _,item in ipairs(raws) do if productionWaiting()and not partialCredit then return handoff() end local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw]
local chunk=math.floor(2147483647/batch)*batch local function bufferedInlet() return 0 end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=false;save("stream-configuring")
assert(route,"高速供液口不可用："..raw);verifyBulk(route,raw,true)
print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to)
print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt
local attempts=0 local inletOpen=false local deadline=computer.uptime()+1800
while not stopping do unchanged();assert(same(field(),stock),"备料时约束场库存变化") assert(same(network(SUB),previous),"备料时子网库存变化")
priority=priority or productionWaiting()
local remaining=need-(previous[raw] or 0) local settling=(batch-(previous[raw]or 0)%batch)%batch
local buffered=network(MAIN)[raw] or 0 local amount=math.floor(math.min(priority and settling or remaining,buffered,chunk))
if amount>0 then verifyBulk(route,raw);local address,from,to=route.address,route.from,route.to
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to}
save("transfer-returned") assert((ok==true or ok==false and moved==0) and type(moved)=="number" and moved>=0 and moved<=amount and moved==math.floor(moved),"搬运返回值未确认，停止且不重试") if moved>0 then previous[raw]=(previous[raw] or 0)+moved end
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
if discovery and discovery.catalogue then
 for name,n in pairs(discovery.catalogue.totals)do assert(mapping[name],"未登记原液映射: "..name);totals[name]=n*copies;assert(totals[name]<=2147483647,"缓存目标过大")end
 count=discovery.catalogue.count;productionOutputs=discovery.catalogue.outputs
else
assert(fs.exists("/home/bec/recipes"),"没有已登记配方") for filename in fs.list("/home/bec/recipes") do if background and BEC_V2_CACHE_YIELD and BEC_V2_CACHE_YIELD()then return {} end if filename:sub(-4)==".dat" then local f=assert(io.open("/home/bec/recipes/"..filename,"r"));local text=f:read("*a");f:close()
local recipe=ser.unserialize(text) assert(type(recipe)=="table" and recipe.state=="converted" and type(recipe.condensates)=="table","配方记录未完成: "..filename) local demand={}
for _,out in ipairs(recipe.outputs or {}) do productionOutputs[tostring(out.name)..":"..tostring(tonumber(out.damage or 0))]=true end
for _,fluid in ipairs(recipe.condensates) do assert(mapping[fluid.name],"未登记原液映射: "..tostring(fluid.name)) demand[fluid.name]=(demand[fluid.name] or 0)+integer(fluid.amount)
end assert(next(demand),"配方没有凝聚物需求: "..filename) for name,need in pairs(demand) do
assert(need*copies<=2147483647,"缓存目标过大") totals[name]=math.max(totals[name] or 0,need*copies) end
count=count+1 print("配方 "..count.."："..filename) end end
end
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
selectedBackground=selected
if BEC_V3_CACHE_PIPELINE then
 for name,need in pairs(totals)do if(stock[name]or 0)>=need then totals[name]=nil end end
else totals={[selected]=totals[selected]}end end end
local live,stock={},field();local visibleRoutes=bulkPorts();local waiting
local unknown=false;for kind in pairs(totals)do if not(discovery and discovery.rawNames[kind])then unknown=true end end
if unknown then live=network(MAIN);for raw,n in pairs(network(SUB))do live[raw]=math.max(live[raw]or 0,n)end end
for kind in pairs(totals) do local raw=mapping[kind]
if discovery and discovery.rawNames[kind]then mapping[kind]=discovery.rawNames[kind]else
local candidates={[raw]=true} candidates["fluid."..raw]=true if kind=="entangled_space" or kind=="entangled_time" then
local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" candidates[stem]=true;candidates["fluid."..stem]=true end
local found={} for name in pairs(candidates) do if (live[name] or 0)>0 or visibleRoutes[name] then found[name]=true end end for name in pairs(candidates) do
local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败") for _,craft in pairs(rows) do local stack=craft.getStack()
if type(stack)=="table" and stack.name==name and type(stack.amount)=="number" then found[name]=true end end end
local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"原液名称不唯一: "..kind)
if n==0 and (stock[kind] or 0)<totals[kind] then waiting="等待原液库存/样板可见: "..kind.." / "..raw end
if n==1 then mapping[kind]=name;if discovery then discovery.rawNames[kind]=name;if BEC_V3_CACHE_SAVE_DISCOVERY then BEC_V3_CACHE_SAVE_DISCOVERY()end end end
end end
if productionWaiting() then return totals end local routes=bulkPorts(totals);local stored=field()
for kind,need in pairs(totals) do
 if (stored[kind] or 0)<need and not routes[mapping[kind]] then waiting="等待高速口流体可见: "..kind.." / "..mapping[kind].."；空口暂不能识别绑定，稍后重扫" end
end
if selectedBackground then
 if BEC_V3_CACHE_PIPELINE then local n=0;for _ in pairs(totals)do n=n+1 end;print("空闲并行补库："..n.." 种原液同时补缺口；有配方优先让位。")
 else print("空闲高速补库：直接补本种完整缺口到 "..totals[selectedBackground].." mB；有配方优先让位。")end
end if fixedStock then
print("登记配方 "..count.."；默认目标 "..fixedStock.." mB，单项设置优先，0停补；只补差额。") else print("登记配方 "..count.."；每配方 "..copies.." 份，共用流体按最大用量缓存。") end return totals,waiting
end local function cacheMain() assert(mode=="preview" or mode=="run","用法: preview / run [每配方份数，默认1]")
RS=resolve("266f65b5","redstone");GEN=resolve("c1ae3f7c","gt_machine") assert(call(GEN,"getName")=="multi.bec.generator","纠缠装置名称不符") local target,waiting=cacheTarget(cacheCopies)
if background and BEC_V2_CACHE_YIELD and BEC_V2_CACHE_YIELD()then return end
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
local initialRawCredit,recoveryArchive
if fs.exists(JOURNAL) then local f=assert(io.open(JOURNAL,"r"));local text=f:read("*a");f:close() local old=ser.unserialize(text)
assert(type(old)=="table" and old.kind=="cache" and old.stage=="stopped" and old.pending==nil and old.configOwned==false,"旧缓存有未确认操作，请保留日志核对") for _,job in ipairs(old.requests or {}) do assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"缓存申请仍未确认") end
if old.reconciliation and old.reconciliation.kind=='confirmed-zero-transfer'and old.reconciliation.version==1 then
 assert(old.reconciliation.aeFinishedByOperator==true and type(old.reconciliation.subnet)=='table','零搬运恢复凭据无效')
 assert(same(network(SUB),old.reconciliation.subnet),'零搬运恢复后子网库存变化，保留记录')
 initialRawCredit=old.reconciliation.subnet;recoveryArchive=old.reconciliation.archive
 assert(BEC_V3_CACHE_PIPELINE,'零搬运恢复需要并行缓存模块；原记录保留')
end
archiveJournal(text) end record={version=1,kind="cache",requests={},transfers={},configOwned=false,target=target,copies=cacheCopies,fixedStock=fixedStock,background=background,initialRawCredit=initialRawCredit,recoveryArchive=recoveryArchive}
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
]=],supported={['28964:1580602570']=true,['33518:3060193974']=true}},{name='runtime/controller.lua',added=false,source=[=[-- BEC_V3_LARGE_BATCH_1: long-sized totals; bounded per-call fluid requests.
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
 local allowed,ports,ambiguous={},{},{}
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
   for _,source in ipairs(sources)do local previous=ports[source.raw]
    if previous and(previous.address~=address or previous.from~=source.from or previous.to~=receivers[1])then ambiguous[source.raw]=true;ports[source.raw]=nil
    elseif not ambiguous[source.raw]then ports[source.raw]={address=address,from=source.from,to=receivers[1]}end
   end
  end
 end end
 -- An unused duplicate must not block another recipe. Required duplicates
 -- still stop before any request or transfer, including raw-name aliases.
 for raw in pairs(ambiguous)do for kind in pairs(required)do assert(not rawAlias(kind,raw),'高速供液口重复绑定: '..raw)end end
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
]=],supported={['40703:4045976240']=true,['40716:3145313717']=true,['51037:689723367']=true}},{name='lib/recheck.lua',added=true,source=[=[-- Explicit full inspection. Reads hardware only; never repairs/replays journals.
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
]=],supported={['0:1']=true}}}

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
local self='/home/bec_v3_cache_update.lua'
do
 local downloaded=read(self)
 local payload=downloaded and downloaded:match('^%-%- BEC_V3_CACHE_RESPONSE_UPDATE_1\nlocal SELF_SIGNATURE=[^\n]*\n(.*)$')
 if payload and signature(payload)==SELF_SIGNATURE then
  pcall(fs.remove,self)
 end
 downloaded=nil;payload=nil;if type(collectgarbage)=='function'then pcall(collectgarbage,'collect')end
end
if identical then print('V3缓存翻页与保存响应修复已安装，无需重复更新。');return end
local disk=assert(fs.get(root));assert(disk.spaceTotal()-disk.spaceUsed()>=bytes+524288,'磁盘空间不足：更新后需保留512KiB')
local n=1
while true do
 local conflict=false;for _,row in ipairs(rows)do for _,suffix in ipairs({'.before-v3-cache-','.v3-cache-new-','.v3-cache-failed-'})do if fs.exists(root..row.name..suffix..n)then conflict=true end end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(rows)do
 local temp=root..row.name..'.v3-cache-new-'..n;local f=assert(io.open(temp,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(temp)==row.source,'临时文件回读失败，旧程序未改')
end
for i,row in ipairs(rows)do assert(read(root..row.name)==old[i],'更新期间程序改变，未替换')end
local backed,installed={},{}
local ok,reason=pcall(function()
 for i,row in ipairs(rows)do local target=root..row.name
  if old[i]then assert(fs.rename(target,target..'.before-v3-cache-'..n),'备份失败');backed[i]=true end
  assert(fs.rename(target..'.v3-cache-new-'..n,target),'替换失败');installed[i]=true
  assert(read(target)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#rows,1,-1 do local target=root..rows[i].name
  if installed[i]then assert(fs.rename(target,target..'.v3-cache-failed-'..n),'移出失败程序失败，保留备份')end
  if backed[i]then assert(fs.rename(target..'.before-v3-cache-'..n,target),'恢复失败，保留备份')end
 end
 error('更新失败，旧程序已恢复：'..tostring(reason))
end
print('V3缓存响应修复已安装：本地翻页，后台读取间隙处理缓存值保存。')
print('已有地址、草稿、配置、配方和运行记录保留；未控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
