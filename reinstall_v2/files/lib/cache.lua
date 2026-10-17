-- V1 cache worker, scheduled under the same V2 group and shared-fluid leases.
local c=require('component');local clock=require('computer');local fs=require('filesystem');local ser=require('serialization')
local labels={chromaticglass='彩色玻璃',transcendentmetal='超时空金属',infinity='无尽',neutronium='中子素',cosmicneutronium='宇宙中子素',bedrockium='基岩锭',celestialtungsten='天体钨',hypogen='海珀珍',phononmedium='声子介质',quarkgluonplasma='夸克胶子等离子体',space='空间',time='时间',spacetime='时空',cosmicsolder='宇宙焊锡',dimshiftedsuperfluid='维度偏移超流体',mhdcsm='磁流体动力学约束星体物质',magmatter='磁物质',universium='宇宙素',eternity='永恒'}
return function(C,B,cfg,storage)
 local path=C.path('cache.config');local raw=B.read(path)
 local fallback=cfg.cacheTarget
 if type(fallback)~='number'or fallback<1 or fallback>2147483647 or fallback%1~=0 then fallback=144000 end
 local settings=raw and C.read(path)or {version=1,target=fallback,overrides={},enabled=false}
 local K={busy=false,logs={},message='空闲时按目标补库；生产订单优先',page=0}
 local active,nextScan,nextGroup,names=nil,0,1,{}
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
  if r.kind~='cache'or r.stage~='stopped'or r.pending~=nil or r.plan~=nil or r.configOwned~=false or r.incomplete then return false end
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
 local function scan()
  local found={};if fs.exists(cfg.recipeDirectory)then for name in fs.list(cfg.recipeDirectory)do if name:match('%.dat$')then
   local r=C.read(cfg.recipeDirectory..'/'..name)
   if r and r.state=='converted'then for _,f in ipairs(r.condensates or {})do
    assert(type(f.name)=='string'and #f.name<=80,'配方流体名称无效');found[f.name]=true
   end end
  end end end
  names={};for name in pairs(found)do names[#names+1]=name end;table.sort(names);assert(#names<=64,'登记缓存类型超过64种')
 end
 function K.action(args)
  if args.mode=='refresh'then scan();local page=tonumber(args.page)or 0;assert(integer(page,0),'分页无效');K.page=math.min(math.floor(page),math.max(0,math.ceil(#names/8)-1));return '已刷新缓存库存'end
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
  local function guard()
   assert(E.fluidOwner==ctx.token and E.groupOwner[group]==ctx.token,'缓存资源锁变化')
   assert(B.read(C.path('config.dat'))==ctx.formal,'缓存期间绑定变化，保留记录')
   local disk=storage.status();assert(disk.known and disk.ok,'缓存期间磁盘不足，保留记录')
   for _,member in ipairs(cfg.nodes)do if member.group==group then
    assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15,'缓存期间节点暂停信号变化')
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
  env.BEC_V2_CACHE_GUARD=guard
  env.BEC_V2_CACHE_PRUNE=function()prune(group)end
  env.BEC_V2_CACHE_YIELD=function()
   if ctx.stop then return true end
   for _,t in ipairs(E.tasks)do if t.co and t.waitKind=='lock'then return true end end
   return false
  end
  env.print=function(...)local rows={...};for i,v in ipairs(rows)do rows[i]=tostring(v)end;log(table.concat(rows,' '))end
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
 local function stopGenerators(group)for _,a in ipairs(cfg.groups[group].generators)do pcall(c.invoke,a,'setWorkAllowed',false)end end
 function K.step(E,running)
  if active then
   if not running or not settings.enabled then active.stop=true end
   if clock.uptime()<(active.deadline or 0)then return end
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
   local group=(nextGroup+offset-1)%#cfg.groups+1;local g=cfg.groups[group];local safe=not E.groupOwner[group];local members=0
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
    -- Keep immediate pause asserted, but allow idle nodes to admit a new order
    -- so the V1 priority check can see physical inputs as well as AE queues.
    for i,n in ipairs(cfg.nodes)do if n.group==group then c.invoke(n.redstone,'setOutput',n.pauseSide,15);E.nodeWork(i,true)end end
    active={group=group,token='cache-'..group,formal=B.read(C.path('config.dat'))}
    E.groupOwner[group]=active.token;E.fluidOwner=active.token
    active.co=coroutine.create(function()return worker(group,E,active)end)
    K.busy=true;K.group=group;nextGroup=group%#cfg.groups+1;return
   end
  end
 end
 function K.snapshot(group)
  if #names==0 then local ok,err=pcall(scan);if not ok then K.message=tostring(err):sub(1,300)end end
  local out={revision=B.revision(raw or ''),enabled=settings.enabled,target=settings.target,busy=K.busy,group=K.group or group,blocked=K.blocked~=nil,message=K.message,logs=K.logs,page=K.page,total=#names,rows={}}
  local g=cfg.groups[group];local ok,stock=pcall(c.invoke,g.storage,'getStoredCondensate');if not ok or type(stock)~='table'then stock={}end
  for i=K.page*8+1,math.min(#names,K.page*8+8)do local name=names[i];local override=settings.overrides[name]
   out.rows[#out.rows+1]={name=name,label=labels[name:gsub('^entangled_','')]or name,stock=stock[name]or 0,target=override~=nil and override or settings.target,override=override}
  end
  return out
 end
 function K.close()if active then active.stop=true;stopGenerators(active.group)end end
 return K
end
