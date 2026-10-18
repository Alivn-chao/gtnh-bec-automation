-- BEC_V3_CACHE_RESPONSE_UPDATE_1
local SELF_SIGNATURE='46297:2646247237'
print('BEC V3 cache response update; Q to exit the old UI first')
local function sig(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local rows={{name='lib/cache.lua',source=[=[-- V1 cache worker, scheduled under the same V2 group and shared-fluid leases.
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
 local catalogueReady=false;local displayedStock={}
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
 local function scan(force)
  if catalogueReady and not force then return end
  local found={};if fs.exists(cfg.recipeDirectory)then for name in fs.list(cfg.recipeDirectory)do if name:match('%.dat$')then
   local r=C.read(cfg.recipeDirectory..'/'..name)
   if r and r.state=='converted'then for _,f in ipairs(r.condensates or {})do
    assert(type(f.name)=='string'and #f.name<=80,'配方流体名称无效');found[f.name]=true
   end end
  end end end
  names={};for name in pairs(found)do names[#names+1]=name end;table.sort(names);assert(#names<=64,'登记缓存类型超过64种');catalogueReady=true
 end
 function K.invalidateCatalogue()catalogueReady=false end
 -- Only these small settings/page operations may run between worker reads.
 function K.canServeFast(args)return catalogueReady and (args.mode=='page'or args.mode=='save')end
 function K.catalogueStep()scan()end
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
]=],supported={['15289:2748686704']=true}},{name='lib/web_session.lua',source=[=[-- HTML is a data client. Only this Lua allowlist can save bindings or run V2.
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
  if not ok then P.co=nil;P.status='failed';P.message=tostring(err):sub(1,400);patternLog('处理失败：',P.message);H.notice=P.message;if K then K.invalidateCatalogue()end
  elseif coroutine.status(P.co)=='dead'then P.co=nil;P.status=P.stop and 'stopped'or 'done';P.message=P.stop and '已停止；已完成槽位和需求记录保留'or '本次样板检查/处理完成';H.notice=P.message;if K then K.invalidateCatalogue()end end
 end
 local function cleanDraft()
  assert(expected and B.read(path)==expected,'请先应用绑定；正式配置若被外部修改，请重新打开网页')
  local formal={};for _,f in ipairs(B.v2Fields(cfg))do formal[f.key]=f.value end
  for _,f in ipairs(fields())do assert(f.value==formal[f.key],'草稿尚未应用，请先应用绑定')end
 end
 -- BEC_V3_CACHE_RESPONSE_1: no hardware controls or binding edits in this lane.
 function H.canServeFast(request)
  return request.name=='cache'and type(request.args)=='table'and K and K.canServeFast(request.args)
 end
 function H.handle(name,args,request)
  assert(type(args)=='table','页面参数必须为对象')
  assert(type(request)=='number'and request==math.floor(request)and request>0,'请求编号无效')
  if name=='cache'then
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
   H.running=true;H.notice='自动化运行中；节点按批次关闭接单，整组完成后再接下一单。';return H.notice
  elseif name=='pause'then
   H.running=false;if P and P.co then P.stop=true end;if E then E.pauseAll()end;H.notice='已请求暂停；工作器收尾，未确认记录保留。';return H.notice
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
]=],supported={['18504:2508797642']=true}},{name='lib/web_transport.lua',source=[=[-- Heartbeats while large OC reads run. Receipt is not operation completion.
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
]=],supported={['1959:2130565450']=true}},{name='web.lua',source=[=[local c=require('component');local event=require('event');local clock=require('computer')
local ROOT='/home/bec_v2'
local function module(n)return assert(loadfile(ROOT..'/lib/'..n..'.lua'))()end
local C,B,W=module('config'),module('ochd_bindings'),module('web_json')
local address,count=nil,0;for a in c.list('hd_panel',true)do address=a;count=count+1 end
assert(count==1,'请只连接一面 OCHD 屏幕墙的主组件')
local methods=c.methods(address)
assert(methods.setWebApp~=nil and methods.publish~=nil,'需要支持 HTML 页面的 OCHD alpha7 或兼容版 JAR')
local f=assert(io.open(C.path('lib/web_page.html'),'r'));local page=f:read('*a');f:close()
local package={id='bec-v2-studio',title='BEC V2 结构绑定与运行',entry='index.html',files={['index.html']=page},
 events={'save_field','apply_bindings','start','pause','select_group','refresh','scan_components','patterns','cache'}}
local panel=c.proxy(address);local H=module('web_session')(C,B,W)
local T=module('web_transport')(panel,event,W,address);C.pulse=T.pulse
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
]=],supported={['2184:2645903512']=true}},{name='lib/web_page.html',source=(function()local f=assert(io.open('/home/bec_v2/lib/web_page.html','r'));local old=f:read('*a');f:close();old=old:gsub('\r\n','\n');if sig(old)=='233112:3384946455'then return old end;assert(sig(old)=='232745:4075596562','未知本地网页，保留未覆盖');local new=old:sub(1,221487)..[=[&&!Array.isArray(last.cache.catalogue)){cacheReadNext={group:group,page:u.page};cacheReadPage();}}
function cacheReadPage(){if(cacheRead||!cacheReadNext||!online)return;var q=cacheReadNext;cacheReadNext=null;if(q.group!==group)return;cacheRead=true;send('cache',{mode:'page',page:q.page,group:q.group}).then(function(){cacheRead=false;cachePageMessage='';cacheReadPage();cacheView();}).catch(function(e){cacheRead=false;if(q.group===group)cachePageMessage='翻页未确认：'+e.message;cacheReadPage();cacheView();});}
function cacheAction(mode,name,value,page){if(cacheWait||!last||!last.cache)return;cacheWait=true;cacheWaiting=last.cache.revision;cacheMessage='正在提交…';cacheView();var args={mode:mode,name:name,value:value,page:page,group:group,revision:last.cache.revision},request=send('cache',args);cacheTok=args._token;request.then(function(r){cacheWait=false;cacheMessage=r.message||'已确认，等待库存更新';cacheView();}).catch(function(e){cacheWait=false;cacheMessage='未执行：'+e.message;cacheView();});}
function cacheView(){var k=last&&last.cache;if(!k)return;$('cache-status').textContent=(!online?'离线，显示最后状态 · ':last.transportBusy?'OC正在读取，显示上次机器状态 · ':'')+(k.enabled?'自动补库已启用':'自动补库未启用')+' · '+(last.mode==='running'?'自动化运行中':'启动自动化后开始补库')+' · '+(k.busy?'设备组 '+k.group+' 补库中 · ':'')+k.message;var u=cacheState();if(u.total!==k.total){u.pages={};u.total=k.total;u.page=Math.min(u.page,Math.max(0,Math.ceil(k.total/8)-1));}u.pages[k.page]=list(k.rows);var allRows=Array.isArray(k.catalogue)?k.catalogue.map(function(r){return{name:r[0],label:r[1],stock:r[2],override:r[3]===false?null:r[3],target:r[3]===false?k.target:r[3]};}):null;if(allRows){u.pages={};for(var page=0;page<Math.ceil(allRows.length/8);page++)u.pages[page]=allRows.slice(page*8,page*8+8);}
(allRows||list(k.rows)]=]..old:sub(-9689);assert(sig(new)=='233112:3384946455','网页补丁核对失败，原文件未改');return new end)(),supported={['232745:4075596562']=true}}}

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
