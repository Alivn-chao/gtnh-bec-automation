-- BEC_V2_CONNECTION_UPDATE_1
local SELF_SIGNATURE='343030:1994883323'
print('BEC connection update; Q to exit the old UI first')
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
]=],supported={['14523:2427812688']=true}},{name='web.lua',added=false,source=[=[local c=require('component');local event=require('event');local clock=require('computer')
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
local ok,err=xpcall(function()
 while true do local accepted,reason=panel.setWebApp(package);assert(accepted~=nil,reason);if accepted then break end;event.pull(.6)end
 print('OCHD 已显示结构绑定与流程图。右键屏幕操作；OC 按 Q 退出并暂停。')
 local nextPush=0
 T.pulse(true)
 while not T.stopping do
  T.poll(.05)
  local request=T.take()
  if request then
   local success,message=pcall(function()return H.handle(request.name,request.args,request.request)end)
   if not success then H.notice=tostring(message)end
   T.publish(H.snapshot(),{token=request.token,name=request.name,ok=success,message=tostring(message):sub(1,400)})
   nextPush=clock.uptime()+2
  end
  if T.stopping then break end
  H.step();T.pulse()
  if clock.uptime()>=nextPush then
   T.publish(H.snapshot());nextPush=clock.uptime()+2
  end
 end
end,debug.traceback)
local errors=H.close();for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
pcall(function()panel.release()end)
assert(ok,err);assert(#errors==0,'暂停存在回读失败，请核对机器')
]=],supported={['2064:3017087304']=true}},{name='lib/web_session.lua',added=false,source=[=[-- HTML is a data client. Only this Lua allowlist can save bindings or run V2.
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
  if not ok then P.co=nil;P.status='failed';P.message=tostring(err):sub(1,400);patternLog('处理失败：',P.message);H.notice=P.message
  elseif coroutine.status(P.co)=='dead'then P.co=nil;P.status=P.stop and 'stopped'or 'done';P.message=P.stop and '已停止；已完成槽位和需求记录保留'or '本次样板检查/处理完成';H.notice=P.message end
 end
 local function cleanDraft()
  assert(expected and B.read(path)==expected,'请先应用绑定；正式配置若被外部修改，请重新打开网页')
  local formal={};for _,f in ipairs(B.v2Fields(cfg))do formal[f.key]=f.value end
  for _,f in ipairs(fields())do assert(f.value==formal[f.key],'草稿尚未应用，请先应用绑定')end
 end
 function H.handle(name,args,request)
  assert(type(args)=='table','页面参数必须为对象')
  assert(type(request)=='number'and request==math.floor(request)and request>0,'请求编号无效')
  if name=='cache'then
   if args.mode=='enable'then cleanDraft();C.validate(cfg,true)end
   if args.mode=='save'or args.mode=='enable'then local disk=storage.status();assert(disk.known and disk.ok,'磁盘不足，缓存配置未保存')end
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
   E=nil;K=nil;H.started=false;H.notice='绑定已校验并应用，点击启动自动化。';return H.notice
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
 function H.step()
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
 function H.snapshot()
  local now=clock.uptime();local values={}
  for _,f in ipairs(fields())do
   local g=f.key:match('^g(%d+)%.')
   if not g or tonumber(g)==H.group then values[f.key]=f.value end
  end
  local out={mode=H.running and 'running'or 'binding',revision=revision(),values=values,group=H.group,groupCount=#cfg.groups,
   configured=expected~=nil,notice=H.notice,scan=scanSnapshot(),now=now,machines={},nodes={},flow={},timeline={},logs={},disk=storage.status()}
  out.cache=cache().snapshot(H.group)
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
  if K then K.close()end
  if P and P.co then P.stop=true;patternStep()end
  H.running=false;if E then return E.shutdown()end;return {}
 end
 function H.engine()return E end
 return H
end
]=],supported={['16316:2774872648']=true}},{name='lib/web_page.html',added=false,source=[=[<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>BEC V2 · 结构绑定与自动化流程</title><meta name="description" content="用真实GTNH方块结构与贴图查看BEC装配线，旋转、分层、选模块并保存绑定草稿。"><style>:root{--ink:#263342;--muted:#8a95a3;--line:#e5eaf0;--blue:#2e77ee;--teal:#20a88e;--soft:#f5f8fc;--font:'Segoe UI','Microsoft YaHei',sans-serif}*{box-sizing:border-box}html,body{width:100%;height:100%;margin:0;overflow:hidden}body{font:13px/1.5 var(--font);color:var(--ink);background:#fff}button,input,select{font:inherit}button{cursor:pointer}button:focus-visible,input:focus-visible,select:focus-visible,a:focus-visible{outline:2px solid #6ba7ff;outline-offset:3px}button{transition:background .15s,color .15s,border .15s}button:hover{filter:brightness(.98)}button:disabled{cursor:not-allowed;opacity:.5}a{color:var(--blue);text-decoration:none}h1,h2,h3,p{margin:0}[hidden]{display:none!important}.topbar{height:70px;border-bottom:1px solid var(--line);display:flex;align-items:center;padding:0 26px;gap:26px;background:#fff;position:relative;z-index:3}.brand{display:flex;align-items:center;gap:12px;color:var(--ink);white-space:nowrap}.brand strong{font-size:17px;letter-spacing:.3px}.brand strong>span{font-weight:400;color:#9aa5b2;font-size:12px;letter-spacing:1.2px}.brand-icon{position:relative;width:27px;height:30px;display:block}.brand-icon i{position:absolute;width:15px;height:15px;border:2px solid var(--blue);transform:rotate(30deg) skewY(-10deg);border-radius:2px;left:2px;top:4px}.brand-icon i:nth-child(2){left:10px;top:9px;background:white}.brand-icon i:nth-child(3){left:2px;top:14px;background:#eaf2ff}.top-divider{height:25px;border-left:1px solid var(--line)}.project-name{font-size:13px;font-weight:600;white-space:nowrap}.pill{margin-left:12px;padding:3px 7px;font-size:10px;color:#4983d1;background:#edf4ff;border-radius:4px;font-weight:400}.top-actions{margin-left:auto;display:flex;align-items:center;gap:10px}.save-status{font-size:11px;color:#8995a4;margin-right:12px;white-space:nowrap}.save-status i,.statusbar i{display:inline-block;width:5px;height:5px;border-radius:50%;background:var(--teal);margin-right:7px;vertical-align:middle}.save-status.busy i{background:#e9ac40}.save-status.error i{background:#e48163}.button{height:34px;padding:0 13px;border:1px solid #dfe6ef;border-radius:5px;background:#fff;color:#687789;font-size:11px}.button.primary{background:var(--blue);border-color:var(--blue);color:white;box-shadow:0 2px 5px #2e77ee16}.workspace{display:grid;grid-template-columns:238px minmax(300px,1fr) 292px;height:calc(100% - 100px)}.sidebar{border-right:1px solid var(--line);display:flex;flex-direction:column;min-height:0;background:#fff}.side-head{padding:27px 22px 22px}.eyebrow{font-size:8px;font-weight:600;letter-spacing:1.8px;color:#9da8b5;display:block}.side-head h1{font-size:18px;letter-spacing:.3px;font-weight:600;margin-top:7px}.side-head p{font-size:10px;color:#a0a9b5;margin-top:9px;line-height:1.7}.search-box{display:flex;align-items:center;background:#f6f8fb;border:1px solid #edf0f5;border-radius:5px;margin:0 17px 24px;padding:7px 9px;gap:6px}.search-box>span{font-size:19px;line-height:15px;color:#97a4b4}.search-box input{background:none;border:0;outline:none;width:100%;min-width:0;font-size:10px;color:#68788b}.search-box kbd{border:1px solid #e2e7ee;border-radius:3px;font-size:9px;color:#a7b0bd;padding:0 4px}.line-header{display:flex;align-items:center;gap:8px;padding:0 20px 12px;color:#8592a3;font-size:10px}.line-header>b{color:#647487;font-weight:600}.count{margin-left:auto;background:#eff3f8;color:#98a5b4;padding:2px 6px;border-radius:4px;font:9px Consolas,monospace}.tree{overflow-y:auto;flex:1;padding:0 11px 20px}.tree-row{display:flex;align-items:center;gap:10px;width:100%;border:0;background:none;text-align:left;padding:10px 11px;border-radius:5px;margin:3px 0;color:#708094;position:relative;min-height:43px}.tree-row:hover{background:#f6f8fc}.tree-row.active{background:#edf4ff;color:#3478db}.tree-row.active:before{content:'';position:absolute;left:-11px;height:24px;width:3px;background:var(--blue);border-radius:0 3px 3px 0}.module-icon{font:17px var(--font);width:25px;height:25px;display:flex;align-items:center;justify-content:center;border:1px solid #dbe3ec;border-radius:5px;color:#8fa1b5;background:#f8fafc;flex-shrink:0}.tree-row.active .module-icon{border-color:#bdd3f4;color:var(--blue);background:#f6faff}.tree-title{font-size:11px;display:block;font-weight:500}.tree-role{font-size:8px;color:#a2acba;display:block;margin-top:2px}.state-dot{width:5px;height:5px;background:#bdc7d3;flex-shrink:0;display:inline-block;border-radius:50%;margin-left:auto}.state-dot.filled{background:var(--teal);box-shadow:0 0 0 3px #20a88e0a}.node-group-button{display:flex;align-items:center;gap:9px;width:100%;background:none;border:0;padding:12px 11px 6px;color:#8393a7;font-size:10px}.node-group-button .count{margin-left:auto}.node-rows{border-left:1px solid #eaf0f7;margin:6px 0 3px 22px;padding-left:9px}.node-rows .tree-row{min-height:33px;padding:7px 9px}.node-rows .tree-title{font-size:10px}.node-rows .tree-role{display:none}.node-rows .module-icon{width:19px;height:19px;font-size:12px}.node-rows .tree-row.active:before{left:-10px;height:18px;width:2px}.side-footer{padding:18px 22px;border-top:1px solid var(--line);background:#fbfcfe}.source-label{display:flex;align-items:center;gap:6px;font-size:10px;color:#8797a9}.verified{display:inline-flex;align-items:center;justify-content:center;border:1px solid #9fb7d2;border-radius:50%;width:12px;height:12px;font-size:8px;color:#6e96be}.side-footer p{font-size:9px;color:#a3adba;line-height:1.8;margin-top:7px}.text-button{background:none;border:0;padding:0;color:#729bd0;font-size:9px;margin-top:7px}.main{display:flex;flex-direction:column;min-height:0;min-width:0;background:#f1f4f8}.view-header{height:51px;display:flex;align-items:center;justify-content:space-between;gap:14px;padding:0 22px;border-bottom:1px solid #e1e8f0;background:#fafbfd;flex-shrink:0}.breadcrumb{display:flex;align-items:center;gap:10px;font-size:10px;color:#96a2b2;white-space:nowrap}.breadcrumb>span{color:#c0cad6;font-size:9px}.breadcrumb b{font-weight:500;color:#74879b}.view-modes{display:flex;background:#eef2f7;border:1px solid #e6ecf3;padding:3px;border-radius:5px}.view-modes button{background:none;border:0;padding:4px 10px;color:#9aa8b9;font-size:9px;border-radius:3px}.view-modes button.active{background:white;color:#4c7eb9;box-shadow:0 1px 3px #172b4510}.stage{position:relative;flex:1;overflow:hidden;min-height:250px;background:#f0f3f7}.stage>canvas{width:100%;height:100%;display:block;cursor:grab;touch-action:none}.stage>canvas.dragging{cursor:grabbing!important}.labels{position:absolute;inset:0;pointer-events:none}.device-label{position:absolute;transform:translate(-50%,-100%);white-space:nowrap;font-size:10px;border:1px solid #d4e0ed;background:#fffffff2;border-radius:4px;padding:4px 8px;box-shadow:0 2px 7px #39566f09;color:#607d99;pointer-events:auto;cursor:pointer;display:flex;align-items:center;gap:6px}.device-label:after{content:'';position:absolute;width:1px;height:13px;background:#a7bfd7;left:50%;top:100%}.device-label i{width:5px;height:5px;border-radius:2px;background:#6a9cd4}.device-label.node{font-size:8px;padding:3px 5px;color:#439984;border-color:#b6dbd0;background:#f9fffcf2}.device-label.node i{background:#41b18d}.device-label.selected{border-color:#69a3f1;color:#2875d9;box-shadow:0 0 0 3px #448bee0b}.stage-title{position:absolute;left:22px;top:20px;display:flex;align-items:center;gap:8px;color:#778b9f;font-size:10px;pointer-events:none}.live-dot{width:5px;height:5px;border-radius:50%;background:#729bc0}.stage-sub{color:#a5b2c0;font-size:9px;margin-left:3px}.viewport-tools{position:absolute;left:17px;top:58px;background:#fffffff2;border:1px solid #dfe6ef;border-radius:6px;box-shadow:0 2px 7px #2c435309;padding:4px;display:flex;flex-direction:column}.viewport-tools button{border:0;background:none;color:#8397ad;border-radius:3px;width:29px;height:30px;font-size:18px}.viewport-tools button:hover{background:#edf4fc;color:#347ede}.viewport-tools>div{border-top:1px solid #e8edf3;margin:3px}.orientation{position:absolute;right:16px;top:16px;display:flex;align-items:center;gap:3px;font-size:9px;color:#a0aebb}.orientation>span{margin-right:4px}.orientation button{border:1px solid #dce5ef;background:#f9fbfd;color:#95a6b9;font-size:8px;padding:4px 6px;border-radius:3px}.orientation button.active{border-color:#b5cdf0;background:#e8f1ff;color:#4f85cc}.model-callout{position:absolute;top:62px;left:64px;padding:15px 20px 14px 16px;border:1px solid #dde5ef;background:#fffffff0;border-radius:6px;pointer-events:auto;box-shadow:0 4px 18px #182c4205}.model-callout>span{font:7px Consolas,monospace;letter-spacing:1.5px;color:#a4b2c0;display:block}.model-callout strong{display:block;font-size:11px;font-weight:500;color:#70859c;margin:6px 0}.model-callout p{font-size:9px;color:#a4b0bf;line-height:1.8}.model-callout>button{position:absolute;right:7px;top:4px;border:0;background:none;color:#b4bfcd;font-size:15px}.axis-gizmo{position:absolute;bottom:26px;left:18px;width:73px;height:64px;opacity:.75}.axis-gizmo svg{width:100%;height:100%}.stage-help{position:absolute;bottom:13px;left:50%;transform:translateX(-50%);display:flex;align-items:center;gap:9px;white-space:nowrap;font-size:8px;color:#9fadb9}.stage-help>span{color:#b8c3ce}.mouse-icon{width:9px;height:13px;border:1px solid #9aabba;border-radius:4px;display:block;position:relative}.mouse-icon:after{content:'';width:1px;height:4px;background:#9aabba;position:absolute;left:3px;top:1px}.renderer-badge{position:absolute;right:13px;bottom:12px;font:7px Consolas,monospace;color:#a9b6c3;letter-spacing:.4px}.layer-bar{height:61px;background:#fafcfe;display:flex;align-items:center;border-top:1px solid #dfe7ef;padding:0 22px;gap:11px;flex-shrink:0}.layer-icon{font-size:23px;color:#91a4b8;margin-right:0}.layer-title{min-width:76px;display:flex;flex-direction:column;gap:2px}.layer-title strong{font-size:10px;font-weight:500;color:#74889e}.layer-title>span{font:8px Consolas,monospace;color:#a2afbf}.layer-bar input{flex:1;min-width:50px;accent-color:#4e8ee9;height:3px;cursor:pointer}.layer-step{font-size:12px;width:20px;height:23px;border:0;background:#f0f4f9;border-radius:4px;color:#9caec0}.mini-button{border:1px solid #d6e5fa;background:#edf4ff;padding:5px 7px;color:#6b9ad7;font-size:8px;border-radius:4px}.view-options{height:42px;display:flex;align-items:center;gap:16px;border-top:1px solid #e8edf3;background:#fff;padding:0 22px;flex-shrink:0;font-size:8px;color:#93a3b4;white-space:nowrap}.view-options label{display:flex;align-items:center;gap:4px;cursor:pointer}.view-options input{width:10px;height:10px;accent-color:#6f99d2;margin:0}.legend{display:flex;gap:5px;align-items:center;margin-left:auto;font-size:7px;color:#a6b3c0}.legend i{display:inline-block;width:5px;height:5px;background:#b8c4d0;border-radius:50%;margin-left:6px}.legend i.filled{background:#20a88e}.legend i.selected{background:#488eea}.inspector{border-left:1px solid var(--line);display:flex;flex-direction:column;min-height:0;overflow-y:auto;background:#fff}.inspector-head{display:flex;align-items:center;justify-content:space-between;padding:28px 23px 22px;border-bottom:1px solid #eef1f6}.inspector-head h2{font-size:16px;font-weight:600;margin-top:7px}.property-icon{font-size:18px;color:#bcc8d4}.module-summary{padding:21px 23px 17px}.module-summary .summary-icon{width:41px;height:41px;display:flex;align-items:center;justify-content:center;font-size:23px;border:1px solid #dbe7f5;border-radius:7px;color:#6b96c8;background:#f3f8fe;margin-bottom:14px}.module-summary h3{font-size:15px;font-weight:600;letter-spacing:.2px}.module-summary p{font-size:9px;color:#9aaabc;margin-top:5px;line-height:1.8}.module-state{display:inline-flex;align-items:center;font-size:8px;gap:5px;margin-top:12px;border-radius:3px;background:#f2f5f9;padding:3px 6px;color:#9cabbc}.module-state i{width:4px;height:4px;border-radius:50%;background:#bac6d1}.module-state.filled{background:#edf9f4;color:#6d9b8d}.module-state.filled i{background:var(--teal)}.properties{border-top:1px solid #edf1f6;padding:18px 23px}.properties-title{font-size:9px;letter-spacing:.5px;color:#75899f;font-weight:500;margin-bottom:15px}.field{margin:0 0 17px}.field>label{display:flex;align-items:center;justify-content:space-between;font-size:10px;color:#8799ac;margin-bottom:7px}.field small{color:#b1bdcb;font-size:8px}.field input,.field select{width:100%;background:#fbfcfe;border:1px solid #e1e8f1;border-radius:5px;padding:10px 9px;color:#5a708a;font-size:10px;outline:none;transition:border-color .2s}.field input{font-family:Consolas,'Microsoft YaHei',monospace;font-size:9px}.field input:focus,.field select:focus{border-color:#83afea;box-shadow:0 0 0 3px #528fea0b}.field input::placeholder{color:#b6c2cf;font-size:8px}.field input.invalid{border-color:#edc2ad;background:#fffdfb}.field .hint{font-size:8px;line-height:1.8;color:#abb8c6;margin-top:6px}.field .hint.error{color:#cd9a80}.direction-grid{display:grid;grid-template-columns:repeat(3,1fr);gap:5px}.direction-grid button{background:#fbfcfe;border:1px solid #e1e8f1;border-radius:4px;color:#a4b1c0;font-size:9px;height:27px}.direction-grid button.active{background:#edf4ff;border-color:#adcaf0;color:#4c82c5}.module-metadata{border-top:1px solid #edf1f6;padding:19px 23px;color:#a6b3c1}.metadata-row{display:flex;justify-content:space-between;font-size:9px;margin:8px 0}.metadata-row b{font:9px Consolas,monospace;font-weight:normal;color:#7e91a7}.metadata-row.role{display:block;font-size:8px;line-height:1.8}.metadata-row.role b{display:block;word-break:break-all;margin-top:4px;font-size:8px}.inspector-bottom{margin-top:auto;padding:17px 23px;border-top:1px solid #eef2f6;background:#fbfcfe;display:flex;gap:9px;align-items:flex-start;color:#a5b5c6}.inspector-bottom>span{font-size:16px;color:#b6c6d6}.inspector-bottom p{font-size:8px;line-height:1.8;color:#a6b4c3}.section-note{font-size:10px;color:#9caebf;line-height:1.95;background:#f7fafe;padding:12px;border:1px solid #e8eef6;border-radius:5px}.related-button{width:100%;margin-top:12px;border:1px solid #cfe0f6;background:#f1f6ff;padding:9px;border-radius:5px;color:#6b95ce;font-size:9px}.validation-state{display:flex;align-items:center;gap:6px;font-size:8px;color:#a0b0c1;background:#f7fafc;padding:9px;border:1px solid #edf2f6;border-radius:4px}.validation-state.valid{color:#5d9c88;background:#f1faf6;border-color:#def0e6}.statusbar{height:30px;border-top:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;padding:0 22px;font-size:8px;color:#a2afbd;background:#fbfcfe}.statusbar b{font:9px Consolas,monospace;color:#7f93a8;font-weight:normal}.status-divider{color:#d6dfe8;margin:0 12px}.toast{position:fixed;left:50%;bottom:55px;transform:translateX(-50%);z-index:10;padding:11px 18px;border:1px solid #dce7f3;background:#fffffff7;box-shadow:0 5px 25px #2b435318;border-radius:6px;font-size:11px;color:#6c8cac;max-width:90vw}.toast.error{border-color:#f1d2bd;color:#ba9277}dialog{border:1px solid #dae5f1;border-radius:10px;box-shadow:0 20px 100px #263b5229;max-width:510px;padding:32px;color:#506981;background:#fff}dialog::backdrop{background:#263c5150}dialog h2{font-size:22px;margin:10px 0 20px}dialog p{font-size:12px;line-height:1.9;color:#8b9fb3;margin-bottom:14px}dialog>a{display:inline-block;margin:8px 20px 12px 0;font-size:11px}.dialog-close{position:absolute;right:13px;top:9px;background:none;border:0;font-size:23px;color:#aab7c6}.license-note{font-size:9px!important;margin-top:12px}::-webkit-scrollbar{width:4px}::-webkit-scrollbar-thumb{background:#d7e0eb;border-radius:4px}@media(min-width:1600px){.workspace{grid-template-columns:260px minmax(300px,1fr) 320px}.side-head,.inspector-head{padding-top:30px}.view-options{font-size:10px}.legend{font-size:9px}.tree-title{font-size:12px}.node-rows .tree-title{font-size:11px}.stage-help{font-size:10px}.field input{font-size:10px}.field>label{font-size:11px}.field .hint{font-size:9px}.module-summary p{font-size:10px}.direction-grid button{font-size:10px}.metadata-row{font-size:10px}.validation-state{font-size:9px}.inspector-bottom p{font-size:9px}.device-label{font-size:12px}.device-label.node{font-size:10px}.tree-role{font-size:9px}.breadcrumb{font-size:11px}.stage-title{font-size:12px}.stage-sub{font-size:10px}}@media(max-width:1100px){.workspace{grid-template-columns:198px minmax(300px,1fr) 250px}.topbar{padding:0 18px;gap:16px}.top-actions{gap:7px}.save-status{display:none}.side-head{padding:23px 17px}.side-head p{font-size:9px}.inspector-head,.module-summary,.properties,.module-metadata{padding-left:18px;padding-right:18px}.view-header{padding:0 14px}.breadcrumb{gap:7px;font-size:9px}.view-modes button{font-size:8px;padding:4px 6px}.view-options{padding:0 12px;gap:10px;font-size:7px}.legend{display:none}.stage-sub{display:none}.model-callout{left:59px;padding:11px 15px}.model-callout p{font-size:8px}.top-divider{display:none}.brand strong>span{font-size:10px}.stage-help{font-size:7px;gap:5px}.renderer-badge{display:none}}@media(max-width:800px){.workspace{grid-template-columns:0 minmax(280px,1fr) 230px}.sidebar{overflow:hidden;border:0}.brand strong>span,.project-name .pill{display:none}.topbar{height:60px;padding:0 14px;gap:20px}.workspace{height:calc(100% - 86px)}.statusbar{height:26px}.statusbar>span:last-child{display:none}.top-actions .quiet{display:none}.project-name{font-size:11px}.button{padding:0 10px}.orientation{gap:2px;right:10px}.orientation>span{display:none}.orientation button{font-size:7px;padding:3px}.model-callout{display:none}.view-header{height:44px}.breadcrumb{display:none}.view-modes{margin-left:auto}.view-options{flex-wrap:wrap;height:52px;gap:6px 10px}.layer-bar{padding:0 12px;gap:7px}.layer-title{min-width:54px}.layer-icon{display:none}.stage-help{display:none}.stage-title{left:14px;font-size:9px}}@media(max-width:540px){.workspace{grid-template-columns:1fr;grid-template-rows:minmax(310px,55%) auto;overflow-y:auto}.main{min-height:360px}.inspector{border-left:0;border-top:1px solid var(--line);overflow:visible}.inspector-head{padding:17px 20px}.inspector-head h2{font-size:14px}.module-summary{padding:15px 20px}.module-summary .summary-icon{display:none}.properties{padding:15px 20px}.module-metadata{padding:15px 20px}.inspector-bottom{display:none}.topbar{gap:14px}.project-name{display:none}.top-actions{margin-left:auto}.statusbar{padding:0 13px}.stage-title{top:13px}.viewport-tools{top:44px;left:10px}.viewport-tools button{width:24px;height:26px}.axis-gizmo{width:50px;left:7px;bottom:10px}.view-options{height:40px}.layer-bar{height:48px}}@media(prefers-reduced-motion:reduce){*{transition:none!important}}.view-options{flex-wrap:wrap;min-height:54px;height:auto;padding-top:8px;padding-bottom:8px;row-gap:6px}.peripheral-heading{margin-top:12px;border-top:1px solid var(--line);padding-top:14px}.peripheral-heading+.tree-row{margin-top:4px}.tree-role{display:block;max-width:165px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.signal-links{position:absolute;inset:0;width:100%;height:100%;pointer-events:none;overflow:hidden;z-index:1}.labels{z-index:2}.device-label.channel-A{border-color:#9ec5ff;color:#2264c5;background:#f6faff}.device-label.channel-B{border-color:#c4afe6;color:#8055b4;background:#fbf8ff}.device-label.channel-B i{background:#9462d6}.io-guide{padding:20px 22px;border-top:1px solid var(--line)}.io-channel{border:1px solid #c5d9fa;background:#f7faff;border-radius:8px;padding:13px;margin:12px 0;--pair:#2e77ee}.io-channel.channel-B{--pair:#9462d6;border-color:#d6c8ee;background:#fbf8ff}.io-channel>strong{font-size:12px;color:var(--pair);display:flex;align-items:center;gap:8px}.io-channel>strong i{font-style:normal;background:var(--pair);color:white;border-radius:4px;padding:1px 6px}.io-flow{font-size:11px;margin:10px 0;color:var(--ink)}.io-pair-buttons{display:flex;flex-direction:column;gap:5px;align-items:stretch;text-align:center;margin:13px 0}.io-pair-buttons button{font-size:11px;border:1px solid #d1dceb;background:white;color:var(--pair);border-radius:5px;padding:8px 4px}.io-pair-buttons>span{font-size:9px;color:var(--pair)}.io-channel dl{font-size:11px;margin:0;line-height:1.7}.io-channel dt{color:#8592a4;margin-top:8px}.io-channel dd{margin:1px 0 0;color:#39485b}.io-binding-readout{border-top:1px dashed #d0dbea;padding-top:10px;margin-top:13px;font-size:10px;line-height:1.9;color:#687990}.io-channel .related-button{font-size:10px;margin-top:10px;width:100%;padding:8px 4px}.io-wiring-note{font-size:10px;line-height:1.9;color:#7a889a;margin:14px 0}.io-guide>.related-button{width:100%;font-size:10px}</style><style>.topbar{height:66px;padding:0 20px;gap:18px}.project-name{font-size:12px}.top-actions{gap:8px}.button{padding:8px 13px}.workspace{height:calc(100% - 96px)}.runtime-tabs{display:flex;gap:4px;margin-left:auto}.runtime-tabs button{border:0;background:transparent;color:#8491a5;padding:10px 14px;border-radius:7px}.runtime-tabs .active{background:#edf3ff;color:#2e77ee}.save-status{min-width:140px;font-size:11px}.run-button{background:#20a88e!important;color:white!important}.stop-button{color:#c25961!important;border-color:#edd3d6!important}.runtime-notice{border-top:1px solid #e5eaf0;padding:9px 18px;background:#fff;color:#6c7b91;font-size:11px;min-height:35px}.flow-panel{background:white;border-top:1px solid #e1e7f0;padding:18px 24px;flex:0 0 310px;overflow:auto}.flow-title{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:20px}.flow-title h2{font-size:17px;font-weight:600}.flow-title p{font-size:11px;color:#8d9aad;margin-top:4px}.elapsed{font-size:24px;font-variant-numeric:tabular-nums;letter-spacing:1px;color:#2e77ee}.elapsed small{font-size:10px;color:#8b98a9;display:block;text-align:right;letter-spacing:0}.flow-path{display:flex;gap:22px;align-items:stretch;margin-bottom:18px}.flow-step{position:relative;flex:1;min-width:72px;border:1px solid #e3e9f1;border-radius:9px;padding:11px 9px;background:#fbfcfe}.flow-step:not(:last-child):after{content:'→';position:absolute;right:-18px;top:26px;color:#a7b4c5}.flow-step .index{font-size:10px;color:#99a8bb;margin-bottom:4px}.flow-step strong{font-size:12px;display:block;white-space:nowrap}.flow-step time{display:block;font-size:11px;color:#8c9bb0;margin-top:8px;font-variant-numeric:tabular-nums}.flow-step.current{border-color:#5b92f5;background:#edf4ff;box-shadow:0 0 0 3px #2e77ee0a}.flow-step.current strong{color:#2e77ee}.flow-step.done{border-color:#d6eae4}.flow-step.done .index{color:#20a88e}.flow-step.fault{border-color:#d7737c;background:#fff5f6}.flow-bottom{display:grid;grid-template-columns:1fr 1.4fr;gap:24px}.flow-bottom h4{font-size:10px;letter-spacing:1px;color:#98a4b4;margin:0 0 8px}.node-list{display:flex;flex-wrap:wrap;gap:6px}.node-chip{border:1px solid #e5eaf1;border-radius:5px;padding:4px 8px;font-size:10px;color:#7b899b}.node-chip.active{border-color:#b2e3d6;color:#20a88e}.runtime-log{font:10px/1.8 'Consolas','Microsoft YaHei',monospace;color:#7d8b9e;max-height:70px;overflow:auto;word-break:break-all}.runtime-running .stage{min-height:190px}.runtime-running .model-callout{display:none}.runtime-running .stage-title{color:#20a88e}.device-label[data-live=active]{color:#168b74;border-color:#88d1bd;box-shadow:0 0 0 4px #20a88e14}.device-label[data-live=active] i{background:#20a88e;box-shadow:0 0 8px #20a88e}.device-label[data-live=phase]{border-color:#d7b877;color:#9d792e}.tree-row[data-live=active] .module-icon{color:#20a88e}.tree-row[data-live=active] .state-dot{background:#20a88e;box-shadow:0 0 7px #20a88e55}.runtime-legend{font-size:10px;color:#8a98aa;margin-top:10px}.runtime-legend b{color:#20a88e;font-weight:400}.runtime-legend em{color:#a48643;font-style:normal}.runtime-settings{border:1px solid #e1e8f2;border-radius:12px;padding:24px;width:530px;max-height:85vh;overflow:auto;box-shadow:0 20px 90px #24334b30}.runtime-settings::backdrop{background:#1d2e4844}.runtime-settings h2{font-size:19px;margin-bottom:7px}.runtime-settings p{font-size:12px;color:#8291a4;margin-bottom:17px}.runtime-settings label{display:block;font-size:12px;color:#65768b;margin-top:13px}.runtime-settings input{width:100%;padding:10px;border:1px solid #dce4ef;border-radius:5px;margin-top:5px}.runtime-settings select{padding:7px;border:1px solid #dce4ef;border-radius:5px}.runtime-settings footer{display:flex;justify-content:flex-end;margin-top:20px}.live-selection{font-size:11px;color:#20a88e;margin-top:8px}.inspector-bottom p{font-size:10px}.runtime-running input,.runtime-running .direction-grid button,.runtime-running #field-group{pointer-events:none;opacity:.55}.offline-alert{color:#c25961!important}.flow-full .flow-panel{flex:1;padding-top:40px}.flow-full .stage,.flow-full .layer-bar,.flow-full .view-options{display:none}.flow-full .flow-path{margin-top:35px;margin-bottom:35px}.flow-full .flow-step{padding:24px 12px}.flow-full .flow-step:not(:last-child):after{top:40px}.flow-full .flow-bottom{margin-top:30px}.flow-full .runtime-log{max-height:240px}.flow-full .flow-panel{min-height:330px}@media(max-width:1300px){.topbar{gap:8px;padding:0 12px}.top-divider,.project-name{display:none}.runtime-tabs button{padding:8px}.button{padding:8px 10px}.flow-panel{padding:15px 16px;flex-basis:295px}.flow-path{gap:15px}.flow-step:not(:last-child):after{right:-13px}.flow-step{padding:10px 5px;min-width:58px}.flow-step strong{font-size:10px}.elapsed{font-size:20px}.save-status{min-width:100px}}input,textarea{caret-color:#236ee8;cursor:text}input:focus,textarea:focus{outline:2px solid #75a8ff!important;outline-offset:1px;background:#f6faff!important;box-shadow:0 0 0 4px #2e77ee18}input::selection,textarea::selection{background:#aaceff;color:#153766}.field .clear-address{display:block;margin:6px 0 0 auto;padding:3px 9px;border:1px solid #dbe5f2;border-radius:5px;color:#517093;background:#fff;font-size:11px}.ochd-native-select{display:none!important}.ochd-select{display:block;width:100%;min-height:36px;text-align:left;padding:8px 30px 8px 11px;border:1px solid #dce4ef;border-radius:6px;background:#fff;color:#36506b;position:relative}.ochd-select:after{content:'▾';position:absolute;right:11px;color:#6d87a6}.ochd-select[aria-expanded=true],.ochd-select:focus{border-color:#69a4ff;outline:2px solid #bdd6ff}.ochd-select-menu{position:fixed;z-index:10000;max-height:230px;overflow:auto;overscroll-behavior:contain;background:white;border:1px solid #bcd2ed;border-radius:7px;box-shadow:0 8px 28px #25456933;padding:4px}.ochd-select-option{display:block;width:100%;padding:9px 11px;border:0;background:#fff;text-align:left;border-radius:4px;color:#36506b}.ochd-select-option:hover,.ochd-select-option.highlight{background:#e9f2ff;color:#236ee8}.ochd-select-option[aria-selected=true]{font-weight:600}.runtime-running .ochd-select,.runtime-running .clear-address{pointer-events:none;opacity:.55}.action-feedback{position:fixed;z-index:4;top:66px;left:0;right:0;min-height:44px;max-height:100px;overflow:auto;padding:11px 20px;background:#edf4ff;border-bottom:1px solid #ccdcf2;color:#315f94;font-size:12px;overflow-wrap:anywhere}.action-feedback.action-error{background:#fff0f0;color:#a52d3c;border-color:#efbdc4}.workspace{padding-top:44px}#binding-issues-list{display:grid;gap:8px;margin:12px 0 18px}#binding-issues-list button{text-align:left;border:1px solid #efc7cd;background:#fff6f7;color:#a52d3c;padding:10px;border-radius:6px}.pick-component{border:1px solid #bcd5f4;background:#edf4ff;color:#236ee8;padding:6px 10px;border-radius:5px;margin-top:6px}.component-choice{display:block;width:100%;text-align:left;border:1px solid #d7e3f3;border-radius:6px;padding:10px;margin:8px 0;background:#fff}.component-choice strong,.component-choice code,.component-choice small{display:block}.component-choice code{font-size:12px;user-select:text}.component-choice small{color:#73839a}#component-picker footer{gap:6px;flex-wrap:wrap}#picker-status{color:#315f94}#patterns-log{white-space:pre-wrap;overflow-wrap:anywhere;font:12px/1.7 Consolas,monospace;max-height:260px;overflow:auto;background:#f5f8fc;padding:10px;border-radius:5px}#patterns-status{color:#315f94}#patterns-dialog footer{gap:6px;flex-wrap:wrap}.pattern-busy input,.pattern-busy .direction-grid button,.pattern-busy .pick-component,.pattern-busy .clear-address,.pattern-busy .ochd-select{pointer-events:none;opacity:.55}#cache-panel{display:none;position:absolute;inset:110px 0 0;padding:26px 5%;overflow-y:scroll;overscroll-behavior:contain;background:#f6f9ff}body.cache-view .workspace{display:none}body.cache-view #cache-panel{display:block}#cache-panel h1{font-size:24px;margin:0 0 10px}#cache-panel p{line-height:1.7}.cache-actions{display:flex;align-items:center;gap:12px;flex-wrap:wrap;margin:14px 0}.cache-actions label{display:flex;align-items:center;gap:12px}#cache-panel input{border:1px solid #d7e1f0;border-radius:7px;padding:10px;width:170px;background:white;color:#24364c}.cache-row{display:grid;grid-template-columns:minmax(220px,1fr) 230px 180px 70px;gap:16px;align-items:center;padding:12px 18px;background:white;border-bottom:1px solid #e6edf7}.cache-row small{display:block;color:#8a9db5;margin-top:5px}#cache-log{white-space:pre-wrap;color:#7186a3;font-size:12px}#cache-feedback{color:#2876ef}.runtime-running #cache-panel input,.pattern-busy #cache-panel input{pointer-events:auto;opacity:1}#cache-nav{position:sticky;bottom:0;background:#f6f9ff;padding:8px 0}</style></head><body><header class="topbar"><a class="brand" href="#"><span class="brand-icon"><i></i><i></i><i></i></span><strong>BEC<span> / STUDIO</span></strong></a><div class="top-divider"></div><span class="project-name">装配线 01 <span class="pill">配置原型</span></span><div class="top-actions"><span id="save-status" class="save-status"><i></i>本地草稿已就绪</span><button class="button quiet" id="import-btn">↥ 导入草稿</button><button class="button primary" id="export-btn">↧ 导出配置</button><input id="import-file" type="file" accept="application/json,.json" hidden></div></header><div class="workspace"><aside class="sidebar"><div class="side-head"><span class="eyebrow">PROJECT EXPLORER</span><h1>装配线结构</h1><p>以实际设备为入口，完成每一处绑定。</p></div><div class="search-box"><span>⌕</span><input id="tree-search" placeholder="查找设备或地址" aria-label="查找设备或地址"><kbd>/</kbd></div><div class="line-header"><span>⌄</span><b>设备组 01</b><span id="binding-count" class="count">0 / 31</span></div><div id="structure-tree" class="tree"></div><div class="side-footer"><div class="source-label"><span class="verified">✓</span><span>GTNH 官方结构数据</span></div><p>GregTech 5.09.54.133<br>方块形状与材质来自原始资源</p><button class="text-button" id="source-button">查看数据来源 ↗</button></div></aside><main class="main"><div class="view-header"><div class="breadcrumb">工作区 <span>/</span> 装配线 01 <span>/</span><b id="view-title">整体结构</b></div><div class="view-modes"><button class="active" id="whole-button">整体视图</button><button id="isolate-button">只看选中</button></div></div><div class="stage" id="stage"><canvas id="scene" aria-label="BEC三维装配线，可拖动旋转，滚轮缩放，点击设备配置"></canvas><svg id="signal-links" class="signal-links" aria-label="A装入和B回收红石对应关系"></svg><div id="labels" class="labels"></div><div class="stage-title"><span class="live-dot"></span>结构配置<span class="stage-sub">/ 真实方块模型</span></div><div class="viewport-tools"><button id="fit-button" title="适应当前视图">⊡</button><button id="reset-button" title="恢复默认视角">↻</button><div></div><button id="zoom-in" title="放大">＋</button><button id="zoom-out" title="缩小">−</button></div><div class="orientation"><span>视角</span><button data-view="iso" class="active">等轴</button><button data-view="front">正面</button><button data-view="top">顶面</button></div><div class="model-callout" id="model-callout"><span>01 / STRUCTURE</span><strong>从模型开始配置</strong><p>点击任意设备，打开它的地址绑定。<br>拖动旋转 · 滚轮缩放 · 右键平移</p><button id="dismiss-callout" aria-label="关闭操作提示">×</button></div><div class="axis-gizmo"><svg viewBox="0 0 80 70" id="axes" aria-label="三维方向轴"></svg></div><div class="stage-help"><span class="mouse-icon"></span>左键旋转<span>·</span>右键平移<span>·</span>滚轮缩放</div><div class="renderer-badge" id="renderer-badge">准备模型…</div></div><div class="layer-bar"><div class="layer-icon">▱</div><div class="layer-title"><strong>分层查看</strong><span id="layer-value">全部层</span></div><button id="layer-down" class="layer-step" aria-label="降低一层">−</button><input type="range" id="layer-slider" min="-15" max="49" value="49" step="1" aria-label="显示到哪一层"><button id="layer-up" class="layer-step" aria-label="提高一层">＋</button><button id="all-layers" class="mini-button active">ALL</button></div><div class="view-options"><label><input type="checkbox" id="show-labels" checked>设备标签</label><label><input type="checkbox" id="show-nodes" checked>节点接入标记</label><label><input type="checkbox" id="full-nodes">展开节点结构</label><label><input type="checkbox" id="show-peripherals" checked>AE / OC 外设</label><label class="missing-option"><input type="checkbox" id="only-missing">仅看未填写</label><span class="legend"><i></i>未填写<i class="filled"></i>地址完整<i class="selected"></i>当前选中</span></div></main><aside class="inspector"><div class="inspector-head"><div><span class="eyebrow">MODULE INSPECTOR</span><h2>模块配置</h2></div><span class="property-icon">⚙</span></div><div id="inspector-content"></div><div class="inspector-bottom"><span>◈</span><p>这一版保存到当前浏览器。<br>尚未写入 OC 或修改生产配置。</p></div></aside></div><footer class="statusbar"><span><i></i><b id="status-module-count">35</b> 个模块<span class="status-divider">|</span><span id="status-selection">观测阵列 01</span></span><span>布局示意 · 主体采用官方结构<span class="status-divider">|</span>OCHD HTML PREVIEW</span></footer><div id="toast" class="toast" role="status" hidden></div><dialog id="sources-dialog"><button class="dialog-close" id="sources-close" aria-label="关闭">×</button><span class="eyebrow">SOURCE / PROVENANCE</span><h2>真实结构，真实材质。</h2><p>五类 BEC 主体来自 GTNewHorizons / GT5-Unofficial 的 5.09.54.133 版本，包含逐层结构、控制器位置与方块贴图。AE / OC 外设采用本机模组贴图及放大的方块示意；硬盘箱为占位材质。动画材质在该预览中使用首帧。</p><p>装配线间距、节点示意与外设布局为配置界面示意，不是经过游戏验证的搭建蓝图。绑定草稿由 OC 硬盘保存；机器状态来自 OC 快照。</p><a href="https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/tectech/thing/metaTileEntity/multi/structures/BECStructureDefinitions.java" target="_blank" rel="noreferrer">结构定义 ↗</a><a href="https://github.com/GTNewHorizons/GT5-Unofficial/tree/5.09.54.133/src/main/resources/assets/gregtech/textures/blocks/iconsets" target="_blank" rel="noreferrer">原始材质 ↗</a><p class="license-note">GTNH 主体资源遵循 LGPL-3.0；AE2 材质遵循 CC BY-NC-SA 3.0；OC 材质为 CC0。<a href="SOURCE-NOTICE.txt">查看全部来源与改动</a>。<a href="UPSTREAM-LICENSE.txt">查看许可证</a></p><details><summary>资源来源与许可证全文</summary><pre style="white-space:pre-wrap;font-size:10px">GTNH BEC structures and original texture sprites: GTNewHorizons/GT5-Unofficial, version 5.09.54.133, commit 74150cf3b624e504fd72746606317a3f5b423667. LGPL-3.0. https://github.com/GTNewHorizons/GT5-Unofficial/tree/5.09.54.133 ; texture atlas uses the first frame of the original animated sprites, controller faces composite the original casing/background/active layers. Layout of the line and peripheral icons is illustrative, not a verified construction schematic. Binding data is browser-local only in this prototype.

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

        http://creativecommons.org/publicdomain/zero/1.0/</pre></details></dialog><script>(function(){var r=["                   ","                                             ","                                                             ","                 "];window.BEC_DATA={"sourceRef":"5.09.54.133","sourceCommit":"74150cf3b624e504fd72746606317a3f5b423667","coordinateSystem":"x right,y up,z back; rows stored in original upstream order","models":{"BEC_GENERATOR":{"size":[19,19,34],"controller":[9,9,0],"sourceArrayOrder":"z,rowDown,x","rows":[[r[0],r[0],r[0],r[0],r[0],"       GDADG       ","      GE111EG      ","     GE1DDD1EG     ","     D1D111D1D     ","     A1D1~1D1A     ","     D1D111D1D     ","     GE1DDD1EG     ","      GE111EG      ","       GDADG       ",r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],"       GDADG       ","     GGGDADGGG     ","    GGG CAC GGG    ","    GG  CAC  GG    ","   GG  CECEC  GG   ","   DDCCEFFFECCDD   ","   AAAACF FCAAAA   ","   DDCCEFFFECCDD   ","   GG  CECEC  GG   ","    GG  CAC  GG    ","    GGG CAC GGG    ","     GGGDADGGG     ","       GDADG       ",r[0],r[0],r[0]],[r[0],r[0],"       GDADG       ","     GG CAC GG     ","    G         G    ","   G           G   ","   G           G   ","  G             G  ","  DC           CD  ","  AA           AA  ","  DC           CD  ","  G             G  ","   G           G   ","   G           G   ","    G         G    ","     GG CAC GG     ","       GDADG       ",r[0],r[0]],[r[0],r[0],"       EEAEE       ","     EEBBABBEE     ","    ECBCCCCCBCE    ","   ECBCFFFFFCBCE   ","   EBCF     FCBE   ","  EBCF       FCBE  ","  EBCF       FCBE  ","  AACF       FCAA  ","  EBCF       FCBE  ","  EBCF       FCBE  ","   EBCF     FCBE   ","   ECBCFFFFFCBCE   ","    ECBCCCCCBCE    ","     EEBBABBEE     ","       EEAEE       ",r[0],r[0]],[r[0],"        DAD        ","        CAC        ",r[0],r[0],r[0],r[0],r[0]," DC             CD "," AA             AA "," DC             CD ",r[0],r[0],r[0],r[0],r[0],"        CAC        ","        DAD        ",r[0]],[r[0],"        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0]," D               D "," A               A "," D               D ",r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ",r[0]],["        DAD        ","        CAC        ",r[0],r[0],r[0],r[0],r[0],r[0],"DC               CD","AA               AA","DC               CD",r[0],r[0],r[0],r[0],r[0],r[0],"        CAC        ","        DAD        "],["        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0],r[0],"D                 D","A                 A","D                 D",r[0],r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        "],["      EEEAEEE      ","    EEGGBABGGEE    ","   EGGGBBABBGGGE   ","  EBGGBCCCCCBGGBE  "," EGGBBCFFFFFCBBGGE "," EGGBCF     FCBGGE ","EGGBCF       FCBGGE","EGBCF         FCBGE","EBBCF         FCBBE","AAACF         FCAAA","EBBCF         FCBBE","EGBCF         FCBGE","EGGBCF       FCBGGE"," EGGBCF     FCBGGE "," EGGBBCFFFFFCBBGGE ","  EBGGBCCCCCBGGBE  ","   EGGGBBABBGGGE   ","    EEGGBABGGEE    ","      EEEAEEE      "],["        DAD        ","        CAC        ",r[0],r[0],r[0],r[0],r[0],r[0],"DC               CD","AA               AA","DC               CD",r[0],r[0],r[0],r[0],r[0],r[0],"        CAC        ","        DAD        "],[r[0],"        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0]," D               D "," A               A "," D               D ",r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ",r[0]],[r[0],"        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0]," D               D "," A               A "," D               D ",r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ",r[0]],[r[0],"        DAD        ","        CAC        ",r[0],r[0],r[0],r[0],r[0]," DC             CD "," AA             AA "," DC             CD ",r[0],r[0],r[0],r[0],r[0],"        CAC        ","        DAD        ",r[0]],[r[0],r[0],"        DAD        ",r[0],r[0],r[0],r[0],r[0],"  D             D  ","  A             A  ","  D             D  ",r[0],r[0],r[0],r[0],r[0],"        DAD        ",r[0],r[0]],[r[0],r[0],"       EEAEE       ","     EEBBABBEE     ","    ECBCCCCCBCE    ","   ECBCFFFFFCBCE   ","   EBCF     FCBE   ","  EBCF       FCBE  ","  EBCF       FCBE  ","  AACF       FCAA  ","  EBCF       FCBE  ","  EBCF       FCBE  ","   EBCF     FCBE   ","   ECBCFFFFFCBCE   ","    ECBCCCCCBCE    ","     EEBBABBEE     ","       EEAEE       ",r[0],r[0]],[r[0],r[0],"        DAD        ","        CAC        ",r[0],r[0],r[0],r[0],"  DC           CD  ","  AA           AA  ","  DC           CD  ",r[0],r[0],r[0],r[0],"        CAC        ","        DAD        ",r[0],r[0]],[r[0],r[0],r[0],"        DAD        ",r[0],r[0],r[0],r[0],"   D           D   ","   A           A   ","   D           D   ",r[0],r[0],r[0],r[0],"        DAD        ",r[0],r[0],r[0]],[r[0],r[0],r[0],"        DAD        ",r[0],r[0],r[0],r[0],"   D           D   ","   A           A   ","   D           D   ",r[0],r[0],r[0],r[0],"        DAD        ",r[0],r[0],r[0]],[r[0],r[0],r[0],"        DAD        ","        CAC        ",r[0],r[0],r[0],"   DC         CD   ","   AA         AA   ","   DC         CD   ",r[0],r[0],r[0],"        CAC        ","        DAD        ",r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],"        DAD        ",r[0],r[0],r[0],"    D         D    ","    A         A    ","    D         D    ",r[0],r[0],r[0],"        DAD        ",r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],"       EEAEE       ","     EEGBABGEE     ","     EBBCCCBBE     ","    EGBCFFFCBGE    ","    EBCF   FCBE    ","    AACF   FCAA    ","    EBCF   FCBE    ","    EGBCFFFCBGE    ","     EBBCCCBBE     ","     EEGBABGEE     ","       EEAEE       ",r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],"        DAD        ","        CAC        ",r[0],r[0],"    DC       CD    ","    AA       AA    ","    DC       CD    ",r[0],r[0],"        CAC        ","        DAD        ",r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],"        DAD        ",r[0],r[0],"     D       D     ","     A       A     ","     D       D     ",r[0],r[0],"        DAD        ",r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],"        DAD        ",r[0],r[0],"     D       D     ","     A       A     ","     D       D     ",r[0],r[0],"        DAD        ",r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],"        DAD        ","        CAC        ",r[0],"     DC     CD     ","     AA     AA     ","     DC     CD     ",r[0],"        CAC        ","        DAD        ",r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ",r[0],"      D     D      ","      A     A      ","      D     D      ",r[0],"        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],"       EEAEE       ","      EBBABBE      ","      EBCFCBE      ","      AAF FAA      ","      EBCFCBE      ","      EBBABBE      ","       EEAEE       ",r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ","        CAC        ","      DC   CD      ","      AA   AA      ","      DC   CD      ","        CAC        ","        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ","       D   D       ","       A   A       ","       D   D       ","        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ","       D   D       ","       A   A       ","       D   D       ","        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ","       DCACD       ","       AA AA       ","       DCACD       ","        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ","        A A        ","        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],r[0],r[0],"        EAE        ","        AFA        ","        EAE        ",r[0],r[0],r[0],r[0],r[0],r[0],r[0],r[0]],[r[0],r[0],r[0],r[0],r[0],r[0],r[0],r[0],"        DAD        ","        A2A        ","        DAD        ",r[0],r[0],r[0],r[0],r[0],r[0],r[0],r[0]]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"ElectromagneticWaveguide","1":"ElectromagneticallyIsolatedCasing","2":"FineStructureConstantManipulator"},"solidBlocks":1279,"surfaceFaces":3016},"BEC_CONTAINMENT_FIELD":{"size":[45,17,45],"controller":[22,2,16],"sourceArrayOrder":"z,rowDown,x","rows":[[r[1],r[1],r[1],r[1],r[1],r[1],"                    D   D                    ","                    DCBCD                    ","                    DB1BD                    ","                    DCBCD                    ","                    D   D                    ",r[1],r[1],r[1],r[1],r[1],r[1]],[r[1],r[1],r[1],r[1],r[1],"                  DEDDDDDED                  ","                  AAAAAAAAA                  ","                  HE FFF EH                  ","                  HE F F EH                  ","                  HE FFF EH                  ","                  AAAAAAAAA                  ","                  DEDDDDDED                  ",r[1],r[1],r[1],r[1],r[1]],[r[1],r[1],r[1],"                   EDHDHDE                   ","                   EDHDHDE                   ","               DDD         DDD               ","               AAAGGGGGGGGGAAA               ","               HHH         HHH               ","               HHH         HHH               ","               HHH         HHH               ","               AAAGGGGGGGGGAAA               ","               DDD         DDD               ","                   EDHDHDE                   ","                   EDHDHDE                   ",r[1],r[1],r[1]],[r[1],r[1],"                  AAAAAAAAA                  ","                   H     H                   ","                   B     B                   ","            DDD               DDD            ","            AAAGGG         GGGAAA            ","            HHH               HHH            ","            HHH               HHH            ","            HHH               HHH            ","            AAAGGG         GGGAAA            ","            DDD               DDD            ","                   B     B                   ","                   H     H                   ","                  AAAAAAAAA                  ",r[1],r[1]],[r[1],"                   EDHDHDE                   ","               AAA H     H AAA               ","                  CCCCCCCCC                  ","                   B     B                   ","           D                     D           ","           AGGG               GGGA           ","           H                     H           ","           H                     H           ","           H                     H           ","           AGGG               GGGA           ","           D                     D           ","                   B     B                   ","                  CCCCCCCCC                  ","               AAA H     H AAA               ","                   EDHDHDE                   ",r[1]],[r[1],"                   EDHDHDE                   ","             AA    B     B    AA             ","               CCC B     B CCC               ","                  FFFFFFFFF                  ","         DD                       DD         ","         AAG                     GAA         ","         HH                       HH         ","         HH                       HH         ","         HH                       HH         ","         AAG                     GAA         ","         DD                       DD         ","                  FFFFFFFFF                  ","               CCC B     B CCC               ","             AA    B     B    AA             ","                   EDHDHDE                   ",r[1]],["                   EDDDDDE                   ",r[1],"           AA                   AA           ","             CC               CC             ","               FFF         FFF               ","        D                           D        ","        AGG                       GGA        ","        H                           H        ","        H                           H        ","        H                           H        ","        AGG                       GGA        ","        D                           D        ","               FFF         FFF               ","             CC               CC             ","           AA                   AA           ",r[1],"                   EDDDDDE                   "],["                EEEEEEEEEEEEE                ",r[1],"          A                       A          ","           CC                   CC           ","             FF               FF             ","       D                             D       ","       AG                           GA       ","       H                             H       ","       H                             H       ","       H                             H       ","       AG                           GA       ","       D                             D       ","             FF               FF             ","           CC                   CC           ","          A                       A          ",r[1],"                EEEEEEEEEEEEE                "],["              EEBBBEBBBBBEBBBEE              ",r[1],"         A                         A         ","          C                       C          ","           FF                   FF           ","      D                               D      ","      AG                             GA      ","      H                               H      ","      H                               H      ","      H                               H      ","      AG                             GA      ","      D                               D      ","           FF                   FF           ","          C                       C          ","         A                         A         ",r[1],"              EEBBBEBBBBBEBBBEE              "],["             EBBEEEEEEEEEEEEEBBE             ",r[1],"        A                           A        ","         C                         C         ","          F        GGGGGGG        F          ","     D                                 D     ","     AG                               GA     ","     H                                 H     ","     H             GGGGGGG             H     ","     H                                 H     ","     AG                               GA     ","     D                                 D     ","          F        GGGGGGG        F          ","         C                         C         ","        A                           A        ",r[1],"             EBBEEEEEEEEEEEEEBBE             "],["            EBEE   AAAAAAA   EEBE            ","                   CD   DC                   ","       A           CD   DC           A       ","        C          CD   DC          C        ","         F       GGAAAAAAAGG       F         ","     D             CHHHHHC             D     ","     AG            CHHHHHC            GA     ","     H             CHHHHHC             H     ","     H           GGAAAAAAAGG           H     ","     H             CHHHHHC             H     ","     AG            CHHHHHC            GA     ","     D             CHHHHHC             D     ","         F       GGAAAAAAAGG       F         ","        C          CD   DC          C        ","       A           CD   DC           A       ","                   CD   DC                   ","            EBEE   AAAAAAA   EEBE            "],["           EBE   AAEDHAHDEAA   EBE           ","                  D       D                  ","      A           D       D           A      ","       C         DD       DD         C       ","        F      GGAA       AAGG      F        ","    D            HH       HH            D    ","    AG           HH       HH           GA    ","    H            HH       HH            H    ","    H          GGAA       AAGG          H    ","    H            HH       HH            H    ","    AG           HH       HH           GA    ","    D            HH       HH            D    ","        F      GGAA       AAGG      F        ","       C         DD       DD         C       ","      A           D       D           A      ","                  D       D                  ","           EBE   AAEDHAHDEAA   EBE           "],["          EBE  AA DEDHAHDED AA  EBE          ",r[1],"      A                               A      ","       C       DD           DD       C       ","        F     GAA           AAG     F        ","   D           HH           HH           D   ","   AG          HH           HH          GA   ","   H           HH           HH           H   ","   H          GAA           AAG          H   ","   H           HH           HH           H   ","   AG          HH           HH          GA   ","   D           HH           HH           D   ","        F     GAA           AAG     F        ","       C       DD           DD       C       ","      A                               A      ",r[1],"          EBE  AA DEDHAHDED AA  EBE          "],["         EBE  A   DEDHAHDED   A  EBE         ",r[1],"     A                                 A     ","      C       D               D       C      ","       F     GA               AG     F       ","   D          H               H          D   ","   AG         H               H         GA   ","   H          H               H          H   ","   H         GA               AG         H   ","   H          H               H          H   ","   AG         H               H         GA   ","   D          H               H          D   ","       F     GA               AG     F       ","      C       D               D       C      ","     A                                 A     ",r[1],"         EBE  A   DEDHAHDED   A  EBE         "],["        EBE  A    DEDHAHDED    A  EBE        ",r[1],"     A                                 A     ","      C      D                 D      C      ","       F    GA                 AG    F       ","   D         H                 H         D   ","   AG        H                 H        GA   ","   H         H                 H         H   ","   H        GA                 AG        H   ","   H         H                 H         H   ","   AG        H                 H        GA   ","   D         H                 H         D   ","       F    GA                 AG    F       ","      C      D                 D      C      ","     A                                 A     ",r[1],"        EBE  A    DEDHAHDED    A  EBE        "],["        EBE A     DEDHAHDED     A EBE        ",r[1],"    A                                   A    ","     C      D                   D      C     ","      F    GA                   AG    F      ","  D         H                   H         D  ","  AG        H                   H        GA  ","  H         H                   H         H  ","  H        GA                   AG        H  ","  H         H                   H         H  ","  AG        H                   H        GA  ","  D         H                   H         D  ","      F    GA                   AG    F      ","     C      D                   D      C     ","    A                                   A    ",r[1],"        EBE A     DEDHAHDED     A EBE        "],["       EBE  A     DEBBABBED     A  EBE       ","                    AHCHA                    ","    A               AHCHA               A    ","     C      D       AHCHA       D      C     ","      F    GA       AHCHA       AG    F      ","  D         H       AHCHA       H         D  ","  AG        H       AHCHA       H        GA  ","  H         H       AHCHA       H         H  ","  H        GA       AHCHA       AG        H  ","  H         H       AHCHA       H         H  ","  AG        H       AHCHA       H        GA  ","  D         H       AHCHA       H         D  ","      F    GA       AHCHA       AG    F      ","     C      D       AHCHA       D      C     ","    A               AH~HA               A    ","                    AHCHA                    ","       EBE  A     DEBBABBED     A  EBE       "],["       EBE A     DBBDDADDBBD     A EBE       ","                  HH     HH                  ","    A             HH     HH             A    ","     C     D      HH     HH      D     C     ","      F   GA      HH     HH      AG   F      ","  D        H      HH     HH      H        D  ","  AG       H      HH     HH      H       GA  ","  H        H      HH     HH      H        H  ","  H       GA      HH     HH      AG       H  ","  H        H      HH     HH      H        H  ","  AG       H      HH     HH      H       GA  ","  D        H      HH     HH      H        D  ","      F   GA      HH     HH      AG   F      ","     C     D      HH     HH      D     C     ","    A             HH     HH             A    ","                  HH     HH                  ","       EBE A     DBBDDADDBBD     A EBE       "],["       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       ","           D     HC       CH     D           ","   A       D     HC       CH     D       A   ","    C      D     HC       CH     D      C    ","     F    GA     HC       CH     AG    F     "," D         H     HC       CH     H         D "," AG        H     HC       CH     H        GA "," H         H     HC       CH     H         H "," H        GA     HC       CH     AG        H "," H         H     HC       CH     H         H "," AG        H     HC       CH     H        GA "," D         H     HC       CH     H         D ","     F    GA     HC       CH     AG    F     ","    C      D     HC       CH     D      C    ","   A       D     HC       CH     D       A   ","           D     HC       CH     D           ","       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       "],["      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      ","    EE    C      H   FDG   H      C    EE    ","   AHB    C      H   DFD   H      C    BHA   ","  EHCB    C      H   GDF   H      C    BCHE  ","  EBBF   GA      H   DGD   H      AG   FBBE  "," E        C      H   FDG   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   GDF   H      C        E "," E       GA      H   DGD   H      AG       E "," E        C      H   FDG   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   GDF   H      C        E ","  EBBF   GA      H   DGD   H      AG   FBBE  ","  EHCB    C      H   FDG   H      C    BCHE  ","   AHB    C      H   DFD   H      C    BHA   ","    EE    C      H   GDF   H      C    EE    ","      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      "],["      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      ","    DD    D     A   D   D   A     D    DD    ","   A      D     A   G   G   A     D      A   ","  D C     D     A   D   D   A     D     C D  ","  D  F   GA     A   F A F   A     AG   F  D  "," D        H     A   D   D   A     H        D ","DAG       H     A   G   G   A     H       GAD","D         H     A   D   D   A     H         D","D        GA     A   F A F   A     AG        D","D         H     A   D   D   A     H         D","DAG       H     A   G   G   A     H       GAD"," D        H     A   D   D   A     H        D ","  D  F   GA     A   F A F   A     AG   F  D  ","  D C     D     A   D   D   A     D     C D  ","   A      D     A   G   G   A     D      A   ","    DD    D     A   D   D   A     D    DD    ","      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      "],["      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      ","    HH          H  G     F  H          HH    ","   A            H  D     D  H            A   ","  H C           H  F     G  H           C H  ","  H  F   GA     H  D  A  D  H     AG   F  H  "," D        H     H  G     F  H     H        D "," AG       H     H  D     D  H     H       GA ","CF        H     H  F     G  H     H        FC","BF       GA     H  D  A  D  H     AG       FB","CF        H     H  G     F  H     H        FC"," AG       H     H  D     D  H     H       GA "," D        H     H  F     G  H     H        D ","  H  F   GA     H  D  A  D  H     AG   F  H  ","  H C           H  G     F  H           C H  ","   A            H  D     D  H            A   ","    HH          H  F     G  H          HH    ","      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      "],["      DEBEAAAAAAAAAAAAAAAAAAAAAAAAAEBED      ","    DD          C  D  A  D  C          DD    ","   A            C  F  A  F  C            A   ","  D C           C  D  A  D  C           C D  ","  D  F   GA     C  GAAAAAG  C     AG   F  D  "," D        H     C  D  A  D  C     H        D "," AG       H     C  F  A  F  C     H       GA ","BF        H     C  D  A  D  C     H        FB","1        GA     C  GAAAAAG  C     AG        1","BF        H     C  D  A  D  C     H        FB"," AG       H     C  F  A  F  C     H       GA "," D        H     C  D  A  D  C     H        D ","  D  F   GA     C  GAAAAAG  C     AG   F  D  ","  D C           C  D  A  D  C           C D  ","   A            C  F  A  F  C            A   ","    DD          C  D  A  D  C          DD    ","      DEBEAAAAAAAAAAAAAAAAAAAAAAAAAEBED      "],["      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      ","    HH          H  F     G  H          HH    ","   A            H  D     D  H            A   ","  H C           H  G     F  H           C H  ","  H  F   GA     H  D  A  D  H     AG   F  H  "," D        H     H  F     G  H     H        D "," AG       H     H  D     D  H     H       GA ","CF        H     H  G     F  H     H        FC","BF       GA     H  D  A  D  H     AG       FB","CF        H     H  F     G  H     H        FC"," AG       H     H  D     D  H     H       GA "," D        H     H  G     F  H     H        D ","  H  F   GA     H  D  A  D  H     AG   F  H  ","  H C           H  F     G  H           C H  ","   A            H  D     D  H            A   ","    HH          H  G     F  H          HH    ","      DEBEAHHHHHBDHBHHAHHBHDBHHHHHAEBED      "],["      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      ","    DD    D     A   D   D   A     D    DD    ","   A      D     A   G   G   A     D      A   ","  D C     D     A   D   D   A     D     C D  ","  D  F   GA     A   F A F   A     AG   F  D  "," D        H     A   D   D   A     H        D ","DAG       H     A   G   G   A     H       GAD","D         H     A   D   D   A     H         D","D        GA     A   F A F   A     AG        D","D         H     A   D   D   A     H         D","DAG       H     A   G   G   A     H       GAD"," D        H     A   D   D   A     H        D ","  D  F   GA     A   F A F   A     AG   F  D  ","  D C     D     A   D   D   A     D     C D  ","   A      D     A   G   G   A     D      A   ","    DD    D     A   D   D   A     D    DD    ","      DEBEADDDDDBDHBBHAHBBHDBDDDDDAEBED      "],["      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      ","    EE    C      H   GDF   H      C    EE    ","   AHB    C      H   DFD   H      C    BHA   ","  EHCB    C      H   FDG   H      C    BCHE  ","  EBBF   GA      H   DGD   H      AG   FBBE  "," E        C      H   GDF   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   FDG   H      C        E "," E       GA      H   DGD   H      AG       E "," E        C      H   GDF   H      C        E "," AG       C      H   DFD   H      C       GA "," E        C      H   FDG   H      C        E ","  EBBF   GA      H   DGD   H      AG   FBBE  ","  EHCB    C      H   GDF   H      C    BCHE  ","   AHB    C      H   DFD   H      C    BHA   ","    EE    C      H   FDG   H      C    EE    ","      EEEEAEEEEEEBDHBBABBHDBEEEEEEAEEEE      "],["       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       ","           D     HC       CH     D           ","   A       D     HC       CH     D       A   ","    C      D     HC       CH     D      C    ","     F    GA     HC       CH     AG    F     "," D         H     HC       CH     H         D "," AG        H     HC       CH     H        GA "," H         H     HC       CH     H         H "," H        GA     HC       CH     AG        H "," H         H     HC       CH     H         H "," AG        H     HC       CH     H        GA "," D         H     HC       CH     H         D ","     F    GA     HC       CH     AG    F     ","    C      D     HC       CH     D      C    ","   A       D     HC       CH     D       A   ","           D     HC       CH     D           ","       EBE ADDDDDBBDHHAHHDBBDDDDDA EBE       "],["       EBE A     DBBDDADDBBD     A EBE       ","                  HH     HH                  ","    A             HH     HH             A    ","     C     D      HH     HH      D     C     ","      F   GA      HH     HH      AG   F      ","  D        H      HH     HH      H        D  ","  AG       H      HH     HH      H       GA  ","  H        H      HH     HH      H        H  ","  H       GA      HH     HH      AG       H  ","  H        H      HH     HH      H        H  ","  AG       H      HH     HH      H       GA  ","  D        H      HH     HH      H        D  ","      F   GA      HH     HH      AG   F      ","     C     D      HH     HH      D     C     ","    A             HH     HH             A    ","                  HH     HH                  ","       EBE A     DBBDDADDBBD     A EBE       "],["       EBE  A     DEBBABBED     A  EBE       ","                    AHCHA                    ","    A               AHCHA               A    ","     C      D       AHCHA       D      C     ","      F    GA       AHCHA       AG    F      ","  D         H       AHCHA       H         D  ","  AG        H       AHCHA       H        GA  ","  H         H       AHCHA       H         H  ","  H        GA       AHCHA       AG        H  ","  H         H       AHCHA       H         H  ","  AG        H       AHCHA       H        GA  ","  D         H       AHCHA       H         D  ","      F    GA       AHCHA       AG    F      ","     C      D       AHCHA       D      C     ","    A               AHCHA               A    ","                    AHCHA                    ","       EBE  A     DEBBABBED     A  EBE       "],["        EBE A     DEDHAHDED     A EBE        ",r[1],"    A                                   A    ","     C      D                   D      C     ","      F    GA                   AG    F      ","  D         H                   H         D  ","  AG        H                   H        GA  ","  H         H                   H         H  ","  H        GA                   AG        H  ","  H         H                   H         H  ","  AG        H                   H        GA  ","  D         H                   H         D  ","      F    GA                   AG    F      ","     C      D                   D      C     ","    A                                   A    ",r[1],"        EBE A     DEDHAHDED     A EBE        "],["        EBE  A    DEDHAHDED    A  EBE        ",r[1],"     A                                 A     ","      C      D                 D      C      ","       F    GA                 AG    F       ","   D         H                 H         D   ","   AG        H                 H        GA   ","   H         H                 H         H   ","   H        GA                 AG        H   ","   H         H                 H         H   ","   AG        H                 H        GA   ","   D         H                 H         D   ","       F    GA                 AG    F       ","      C      D                 D      C      ","     A                                 A     ",r[1],"        EBE  A    DEDHAHDED    A  EBE        "],["         EBE  A   DEDHAHDED   A  EBE         ",r[1],"     A                                 A     ","      C       D               D       C      ","       F     GA               AG     F       ","   D          H               H          D   ","   AG         H               H         GA   ","   H          H               H          H   ","   H         GA               AG         H   ","   H          H               H          H   ","   AG         H               H         GA   ","   D          H               H          D   ","       F     GA               AG     F       ","      C       D               D       C      ","     A                                 A     ",r[1],"         EBE  A   DEDHAHDED   A  EBE         "],["          EBE  AA DEDHAHDED AA  EBE          ",r[1],"      A                               A      ","       C       DD           DD       C       ","        F     GAA           AAG     F        ","   D           HH           HH           D   ","   AG          HH           HH          GA   ","   H           HH           HH           H   ","   H          GAA           AAG          H   ","   H           HH           HH           H   ","   AG          HH           HH          GA   ","   D           HH           HH           D   ","        F     GAA           AAG     F        ","       C       DD           DD       C       ","      A                               A      ",r[1],"          EBE  AA DEDHAHDED AA  EBE          "],["           EBE   AAEDHAHDEAA   EBE           ","                  D       D                  ","      A           D       D           A      ","       C         DD       DD         C       ","        F      GGAA       AAGG      F        ","    D            HH       HH            D    ","    AG           HH       HH           GA    ","    H            HH       HH            H    ","    H          GGAA       AAGG          H    ","    H            HH       HH            H    ","    AG           HH       HH           GA    ","    D            HH       HH            D    ","        F      GGAA       AAGG      F        ","       C         DD       DD         C       ","      A           D       D           A      ","                  D       D                  ","           EBE   AAEDHAHDEAA   EBE           "],["            EBEE   AAAAAAA   EEBE            ","                   CD   DC                   ","       A           CD   DC           A       ","        C          CD   DC          C        ","         F       GGAAAAAAAGG       F         ","     D             CHHHHHC             D     ","     AG            CHHHHHC            GA     ","     H             CHHHHHC             H     ","     H           GGAAAAAAAGG           H     ","     H             CHHHHHC             H     ","     AG            CHHHHHC            GA     ","     D             CHHHHHC             D     ","         F       GGAAAAAAAGG       F         ","        C          CD   DC          C        ","       A           CD   DC           A       ","                   CD   DC                   ","            EBEE   AAAAAAA   EEBE            "],["             EBBEEEEEEEEEEEEEBBE             ",r[1],"        A                           A        ","         C                         C         ","          F        GGGGGGG        F          ","     D                                 D     ","     AG                               GA     ","     H                                 H     ","     H             GGGGGGG             H     ","     H                                 H     ","     AG                               GA     ","     D                                 D     ","          F        GGGGGGG        F          ","         C                         C         ","        A                           A        ",r[1],"             EBBEEEEEEEEEEEEEBBE             "],["              EEBBBEBBBBBEBBBEE              ",r[1],"         A                         A         ","          C                       C          ","           FF                   FF           ","      D                               D      ","      AG                             GA      ","      H                               H      ","      H                               H      ","      H                               H      ","      AG                             GA      ","      D                               D      ","           FF                   FF           ","          C                       C          ","         A                         A         ",r[1],"              EEBBBEBBBBBEBBBEE              "],["                EEEEEEEEEEEEE                ",r[1],"          A                       A          ","           CC                   CC           ","             FF               FF             ","       D                             D       ","       AG                           GA       ","       H                             H       ","       H                             H       ","       H                             H       ","       AG                           GA       ","       D                             D       ","             FF               FF             ","           CC                   CC           ","          A                       A          ",r[1],"                EEEEEEEEEEEEE                "],["                   EDDDDDE                   ",r[1],"           AA                   AA           ","             CC               CC             ","               FFF         FFF               ","        D                           D        ","        AGG                       GGA        ","        H                           H        ","        H                           H        ","        H                           H        ","        AGG                       GGA        ","        D                           D        ","               FFF         FFF               ","             CC               CC             ","           AA                   AA           ",r[1],"                   EDDDDDE                   "],[r[1],"                   EDHDHDE                   ","             AA    B     B    AA             ","               CCC B     B CCC               ","                  FFFFFFFFF                  ","         DD                       DD         ","         AAG                     GAA         ","         HH                       HH         ","         HH                       HH         ","         HH                       HH         ","         AAG                     GAA         ","         DD                       DD         ","                  FFFFFFFFF                  ","               CCC B     B CCC               ","             AA    B     B    AA             ","                   EDHDHDE                   ",r[1]],[r[1],"                   EDHDHDE                   ","               AAA H     H AAA               ","                  CCCCCCCCC                  ","                   B     B                   ","           D                     D           ","           AGGG               GGGA           ","           H                     H           ","           H                     H           ","           H                     H           ","           AGGG               GGGA           ","           D                     D           ","                   B     B                   ","                  CCCCCCCCC                  ","               AAA H     H AAA               ","                   EDHDHDE                   ",r[1]],[r[1],r[1],"                  AAAAAAAAA                  ","                   H     H                   ","                   B     B                   ","            DDD               DDD            ","            AAAGGG         GGGAAA            ","            HHH               HHH            ","            HHH               HHH            ","            HHH               HHH            ","            AAAGGG         GGGAAA            ","            DDD               DDD            ","                   B     B                   ","                   H     H                   ","                  AAAAAAAAA                  ",r[1],r[1]],[r[1],r[1],r[1],"                   EDHDHDE                   ","                   EDHDHDE                   ","               DDD         DDD               ","               AAAGGGGGGGGGAAA               ","               HHH         HHH               ","               HHH         HHH               ","               HHH         HHH               ","               AAAGGGGGGGGGAAA               ","               DDD         DDD               ","                   EDHDHDE                   ","                   EDHDHDE                   ",r[1],r[1],r[1]],[r[1],r[1],r[1],r[1],r[1],"                  DEDDDDDED                  ","                  AAAAAAAAA                  ","                  HE FFF EH                  ","                  HE F F EH                  ","                  HE FFF EH                  ","                  AAAAAAAAA                  ","                  DEDDDDDED                  ",r[1],r[1],r[1],r[1],r[1]],[r[1],r[1],r[1],r[1],r[1],r[1],"                    D   D                    ","                    DCBCD                    ","                    DB1BD                    ","                    DCBCD                    ","                    D   D                    ",r[1],r[1],r[1],r[1],r[1],r[1]]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"FineStructureConstantManipulator"},"solidBlocks":5333,"surfaceFaces":15518},"BEC_ASSEMBLER":{"size":[61,31,31],"controller":[30,15,1],"sourceArrayOrder":"z,rowDown,x","rows":[[r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","            E           E           E           E            ","           EBE         EBE         EBE         EBE           ","          EB3BE       EB3BE       EB3BE       EB3BE          ","           EBE         EBE         EBE         EBE           ","            E           E           E           E            ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","     AAAAAAAAAAAAAAAAAAAAAAAAA~AAAAAAAAAAAAAAAAAAAAAAAAA     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADDBDDADDCDDADDBD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    B C           C           C           C           C B    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    B C           C           C           C           C B    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],"            E           E           E           E            ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A   A     A     A     A     A     A     A     A     A   A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","            E           E           E           E            ",r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],"            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   CC    B     B     B     B     B     B     B     B    CC   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B                                                         B "," B                                                         B "," A    A     A     A     A     A     A     A     A     A    A "," B                                                         B "," B                                                         B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   CC    B     B     B     B     B     B     B     B    CC   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ",r[2],r[2],r[2]],[r[2],r[2],"            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  AC     F     F     F     F     F     F     F     F     CA  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AH   C     C     C     C     C     C     C     C     C   HA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  AC     F     F     F     F     F     F     F     F     CA  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ",r[2],r[2]],[r[2],r[2],"            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  C   B     B     B     B     B     B     B     B     B   C  "," BH   H     H     H     H     H     H     H     H     H   HB "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," BH   H     H     H     H     H     H     H     H     H   HB ","  C   B     B     B     B     B     B     B     B     B   C  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ",r[2],r[2]],[r[2],"            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," BH   H     H     H     H     H     H     H     H     H   HB "," CB   B     B     B     B     B     B     B     B     B   BC "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D "," A                                                         A "," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," CB   B     B     B     B     B     B     B     B     B   BC "," BH   H     H     H     H     H     H     H     H     H   HB ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ",r[2]],[r[2],"            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D ","EB                                                         BE","EBH                                                       HBE","ABH                                                       HBA","EBH                                                       HBE","EB                                                         BE"," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ",r[2]],[r[2],"            E           E           E           E            ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," C                                                         C ","EB                                                         BE","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","EB                                                         BE"," C                                                         C "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","            E           E           E           E            ",r[2]],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","DH                                                         HE","DH                                                         HE","DH                                                         HE","DH                                                         HE","DH                                                         HE","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","DH                                                         HE","DH                                                         HE","DG                                                         GE","DG                                                         GE","DG                                                         GE","DH                                                         HE","DH                                                         HE","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],["           EBE         EBE         EBE         EBE           ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EBH                                                       HBE","ACF                                                       FCA","BH                                                         HE","BG                                                         GD","B                                                           E","D                                                           E","D                                                           B","EG                                                         GB","DH                                                         HB","ACF                                                       FCA","EBH                                                       HBE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","           EBE         EBE         EBE         EBE           "],["          EB3BE       EB3BE       EB3BE       EB3BE          ","     AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA     ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","  A   A     A     A     A     A     A     A     A     A   A  "," A    A     A     A     A     A     A     A     A     A    A "," AH   C     C     C     C     C     C     C     C     C   HA "," AG   G     G     G     G     G     G     G     G     G   GA "," A                                                         A ","ABH                                                       HBA","ACF                                                       FCA","EH                                                         HE","EG                                                         GE","E                                                           E","2                                                           2","D                                                           D","DG                                                         GD","DH                                                         HD","ACF                                                       FCA","ABH                                                       HBA"," A                                                         A "," AG   G     G     G     G     G     G     G     G     G   GA "," AH   C     C     C     C     C     C     C     C     C   HA "," A    A     A     A     A     A     A     A     A     A    A ","  A   A     A     A     A     A     A     A     A     A   A  ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","     AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA     ","          EB3BE       EB3BE       EB3BE       EB3BE          "],["           EBE         EBE         EBE         EBE           ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EBH                                                       HBE","ACF                                                       FCA","EH                                                         HB","DG                                                         GB","E                                                           B","E                                                           D","B                                                           D","BG                                                         GE","BH                                                         HD","ACF                                                       FCA","EBH                                                       HBE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","           EBE         EBE         EBE         EBE           "],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  "," B                                                         B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","EH                                                         HD","EH                                                         HD","EG                                                         GD","EG                                                         GD","EG                                                         GD","EH                                                         HD","EH                                                         HD","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B                                                         B ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],["            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D ","EB                                                         BE","ACF                                                       FCA","EH                                                         HD","EH                                                         HD","EH                                                         HD","EH                                                         HD","EH                                                         HD","ACF                                                       FCA","EB                                                         BE"," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            "],[r[2],"            E           E           E           E            ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," C                                                         C ","EB                                                         BE","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","ACF                                                       FCA","EB                                                         BE"," C                                                         C "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","            E           E           E           E            ",r[2]],[r[2],"            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C           C           C           C           C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D ","EB                                                         BE","EBH                                                       HBE","ABH                                                       HBA","EBH                                                       HBE","EB                                                         BE"," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C           C           C           C           C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ",r[2]],[r[2],"            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  "," BH   H     H     H     H     H     H     H     H     H   HB "," CB   B     B     B     B     B     B     B     B     B   BC "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," D                                                         D "," D                                                         D "," A                                                         A "," D                                                         D "," D                                                         D "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," CB   B     B     B     B     B     B     B     B     B   BC "," BH   H     H     H     H     H     H     H     H     H   HB ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ",r[2]],[r[2],r[2],"            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  C   B     B     B     B     B     B     B     B     B   C  "," BH   H     H     H     H     H     H     H     H     H   HB "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," AG   G     G     G     G     G     G     G     G     G   GA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," BH   H     H     H     H     H     H     H     H     H   HB ","  C   B     B     B     B     B     B     B     B     B   C  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ",r[2],r[2]],[r[2],r[2],"            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","  AC     F     F     F     F     F     F     F     F     CA  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   H     H     H     H     H     H     H     H     H   E  "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," AH   C     C     C     C     C     C     C     C     C   HA "," DH   C     C     C     C     C     C     C     C     C   HD "," DH   C     C     C     C     C     C     C     C     C   HD "," B    H     H     H     H     H     H     H     H     H    B "," B    H     H     H     H     H     H     H     H     H    B ","  E   H     H     H     H     H     H     H     H     H   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  AC     F     F     F     F     F     F     F     F     CA  ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ",r[2],r[2]],[r[2],r[2],r[2],"            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   CC    B     B     B     B     B     B     B     B    CC   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  "," B                                                         B "," B                                                         B "," A    A     A     A     A     A     A     A     A     A    A "," B                                                         B "," B                                                         B ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  E   B     B     B     B     B     B     B     B     B   E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   CC    B     B     B     B     B     B     B     B    CC   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ",r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],"            E           E           E           E            ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A   A     A     A     A     A     A     A     A     A   A  ","  E                                                       E  ","  E                                                       E  ","  E                                                       E  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA    ","            E           E           E           E            ",r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","   E     H     H     H     H     H     H     H     H     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A   A  F  A  F  A  F  A  F  A  F  A  F  A  F  A  F  A   A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","  A      F     F     F     F     F     F     F     F      A  ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     H     H     H     H     H     H     H     H     E   ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    BDC  B     B  C  B     B  C  B     B  C  B     B  CDB    ","     DBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBDDADDCDDADDBD     ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","    B C           C           C           C           C B    ","   E  C           C           C           C           C  E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   A  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  C  A  A   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E     C     C     C     C     C     C     C     C     E   ","   E  C           C           C           C           C  E   ","    B C           C           C           C           C B    ","    B C  B     B  C  B     B  C  B     B  C  B     B  C B    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","      B  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  B      ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    A A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A  A A    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    B C           C           C           C           C B    ","    BDB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BDB    ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","     DB  A  C  A  B  A  C  A  B  A  C  A  B  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","     AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA     ","     DBDDADDCDDADD1DDADDCDDADD1DDADDCDDADD1DDADDCDDADDBD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","     DB  A  C  A  1  A  C  A  1  A  C  A  1  A  C  A  BD     ","            E           E           E           E            ","            E           E           E           E            ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2]],[r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],"            E           E           E           E            ","            E           E           E           E            ","           EBE         EBE         EBE         EBE           ","          EB3BE       EB3BE       EB3BE       EB3BE          ","           EBE         EBE         EBE         EBE           ","            E           E           E           E            ","            E           E           E           E            ",r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2],r[2]]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"ElectromagneticallyIsolatedCasing","2":"FineStructureConstantManipulator","3":"FineStructureConstantManipulator"},"solidBlocks":7994,"surfaceFaces":22980},"BEC_IO_NODE":{"size":[7,23,13],"controller":[3,11,0],"sourceArrayOrder":"z,rowDown,x","rows":[["       ","       ","       ","       ","       ","       ","       ","       ","       ","  BAB  "," BBABB "," AA~AA "," BBABB ","  BAB  ","       ","       ","       ","       ","       ","       ","       ","       ","       "],["       ","       ","       ","       ","       ","       ","       ","       ","  DAD  "," D C D ","D     D","AC   CA","D     D"," D C D ","  DAD  ","       ","       ","       ","       ","       ","       ","       ","       "],["       ","       ","       ","       ","       ","       ","   A   ","   A   ","  AAA  "," A   A ","A     A","A     A","A     A"," A   A ","  AAA  ","   A   ","   A   ","       ","       ","       ","       ","       ","       "],["       ","       ","       ","       ","   A   ","   A   ","   D   ","   D   ","  DBD  "," ECFCE ","DCF FCD","AF   FA","DCF FCD"," ECFCE ","  DBD  ","   D   ","   D   ","   A   ","   A   ","       ","       ","       ","       "],["       ","       ","       ","   A   ","   D   ","   D   ","  HBH  ","  HBH  "," DCGCD ","DCF FCD","CF   FC","A     A","CF   FC","DCF FCD"," DCGCD ","  HBH  ","  HBH  ","   D   ","   D   ","   A   ","       ","       ","       "],["       ","       ","   A   ","   D   ","  HBH  ","  HBH  ","  EGE  ","  EGE  "," DBGBD ","DF   FD","H     H","A     A","H     H","DF   FD"," DBGBD ","  EGE  ","  EGE  ","  HBH  ","  HBH  ","   D   ","   A   ","       ","       "],["       ","       ","   A   ","   D   ","  HBH  ","  EGE  ","  HBH  ","  HBH  "," DCBCD ","DCF FCD","CF   FC","A     A","CF   FC","DCF FCD"," DCBCD ","  HBH  ","  HBH  ","  EGE  ","  HBH  ","   D   ","   A   ","       ","       "],["       ","   A   ","   D   ","  HBH  ","  EGE  ","  HBH  ","  HBH  ","   D   ","  DDD  "," ECFCE ","DCF FCD","AF   FA","DCF FCD"," ECFCE ","  DDD  ","   D   ","  HBH  ","  HBH  ","  EGE  ","  HBH  ","   D   ","   A   ","       "],["       ","   A   ","   D   ","  HBH  ","  HBH  ","   D   ","   D   ","   A   ","  AAA  "," AGEGA ","AGEBEGA","AEB1BEA","AGEBEGA"," AGEGA ","  AAA  ","   A   ","   D   ","   D   ","  HBH  ","  HBH  ","   D   ","   A   ","       "],["   A   ","   D   ","  HBH  ","   D   ","   D   ","   A   ","   A   ","       ","  F F  ","       ","F     F","       ","F     F","       ","  F F  ","       ","   A   ","   A   ","   D   ","   D   ","  HBH  ","   D   ","   A   "],["   A   ","   D   ","   D   ","   A   ","   A   ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","   A   ","   A   ","   D   ","   D   ","   A   "],["   A   ","   D   ","   A   ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","   A   ","   D   ","   A   "],["   A   ","   A   ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","       ","   A   ","   A   "]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"FineStructureConstantManipulator"},"solidBlocks":430,"surfaceFaces":908},"BEC_DIODE":{"size":[17,11,11],"controller":[8,5,0],"sourceArrayOrder":"z,rowDown,x","rows":[[r[3],r[3],r[3],r[3],"  B  E  B  E  B  ","  B  E  ~  E  B  ","  B  E  B  E  B  ",r[3],r[3],r[3],r[3]],[r[3],r[3],"  B  E  B  E  B  "," DBDDEDDBDDEDDBD ","              CH ","AAAAAAAAAAAAAAAAA","              CH "," DBDDEDDBDDEDDBD ","  B  E  B  E  B  ",r[3],r[3]],[r[3],"  B  E  B  E  B  "," AAAAAAAAAAAAAAA ","C    H  H  H  F C","C    C  C  C  F C","D A  A  A  A  F E","C    C  C  C  F C","C    H  H  H  F C"," AAAAAAAAAAAAAAA ","  B  E  B  E  B  ",r[3]],[r[3]," DBDDEDDBDDEDDBD ","C    H  H  H  F C","  HHHCHHCHHC    H","  C  G  F  G    H","D A  G  F  G    E","  C  G  F  G    H","  HHHCHHCHHC    H","C    H  H  H  F C"," DBDDEDDBDDEDDBD ",r[3]],["  B  E  B  E  B  ","              CH ","C    C  C  C  F C","  C  G  F  G    H","D F             E","B F             B","D F             E","  C  G  F  G    H","C    C  C  C  F C","              CH ","  B  E  B  E  B  "],["  B  E  B  E  B  ","AAAAAAAAAAAAAAAAA","D A  A  A  A  F E","D A  G  F  G    E","B F             B","1               2","B F             B","D A  G  F  G    E","D A  A  A  A  F E","AAAAAAAAAAAAAAAAA","  B  E  B  E  B  "],["  B  E  B  E  B  ","              CH ","C    C  C  C  F C","  C  G  F  G    H","D F             E","B F             B","D F             E","  C  G  F  G    H","C    C  C  C  F C","              CH ","  B  E  B  E  B  "],[r[3]," DBDDEDDBDDEDDBD ","C    H  H  H  F C","  HHHC  CHHC    H","  C  G  F  G    H","D A  G  F  G    E","  C  G  F  G    H","  HHHCHHCHHC    H","C    H  H  H  F C"," DBDDEDDBDDEDDBD ",r[3]],[r[3],"  B  E  B  E  B  "," AAAAAAAAAAAAAAA ","C    H  H  H  F C","C    C  C  C  F C","D A  A  A  A  F E","C    C  C  C  F C","C    H  H  H  F C"," AAAAAAAAAAAAAAA ","  B  E  B  E  B  ",r[3]],[r[3],r[3],"  B  E  B  E  B  "," DBDDEDDBDDEDDBD ","              CH ","AAAAAAAAAAAAAAAAA","              CH "," DBDDEDDBDDEDDBD ","  B  E  B  E  B  ",r[3],r[3]],[r[3],r[3],r[3],r[3],"  B  E  B  E  B  ","  B  E  B  E  B  ","  B  E  B  E  B  ",r[3],r[3],r[3],r[3]]],"materials":{"A":"CoherencePreservingPlasmaConduit","B":"ElectromagneticallyIsolatedCasing","C":"FineStructureConstantManipulator","D":"ConflictInducementCasing","E":"PeaceEnforcementCasing","F":"CondensateTransformativeCoil","G":"CondensateGuidanceCoil","H":"ElectromagneticWaveguide","1":"FineStructureConstantManipulator","2":"FineStructureConstantManipulator"},"solidBlocks":620,"surfaceFaces":1966},"AE_INTERFACE":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[13,13,13,13,13,13],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"AE_IO":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[15,15,14,16,15,15],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"OC_TRANS":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[17,17,18,18,17,17],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"OC_RS":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[19,19,20,20,19,19],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}},"BANK_BOX":{"size":[4,4,4],"controller":[2,2,0],"cube":true,"faceTextures":[1,1,1,1,1,1],"solidBlocks":1,"surfaceFaces":6,"rows":[],"materials":{}}},"textureTiles":{"BEC_CONDUIT.png":0,"BEC_CASING.png":1,"BEC_MANIPULATOR.png":2,"BEC_CONFLICTCASING.png":3,"BEC_PEACECASING.png":4,"BEC_PRIMARYCOIL.png":5,"BEC_SECONDARYCOIL.png":6,"BEC_GLASS.png":7,"BEC_GENERATOR":8,"BEC_CONTAINMENT_FIELD":9,"BEC_ASSEMBLER":10,"BEC_IO_NODE":11,"BEC_DIODE":12},"materialTextures":{"CoherencePreservingPlasmaConduit":0,"ElectromagneticallyIsolatedCasing":1,"FineStructureConstantManipulator":2,"ConflictInducementCasing":3,"PeaceEnforcementCasing":4,"CondensateTransformativeCoil":5,"CondensateGuidanceCoil":6,"ElectromagneticWaveguide":7},"atlas":"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAYAAADDPmHLAAASBUlEQVR4nO2cf4xU1RXHz3szyy7sLixbWFh+rKgghKRuA+IPBLFq7a80Lco/NvqHaSQYY0wgNuk/NTZpmmg0IYRoYogN1tI2CmmINloVRAJVgbCoFMUqFSoIAou7sj9nXvO9M9+3Zy5vZmd38AfL+SQv77777nk/7jn33HPvfTNBc3NzJBUwbty4OJ3JZArO+cfZbLZgD8aMGVNSplgeGTVq1Dcq39nZ6ergzJkz7njy5MnS3t6eWHbGjBly4MABl66pqZHu7m6ZM2dOfL6lpcXtW1tb3X7evHluv2fPHrdva2tz+08++SSWWb169cOtra1b8+dvZD7yjh8/3ox0U1PTUf8cy6eRqK6uLnjQMAwLFOUfk56eHre/6qqrCvLffPNNaW529445cuRI/ILk4MGDbn/27NlzKov3JEll6urq3H779u0F+awoH1YsufrqqxONoKGhIVHeVyyUD0UC7kvJ+w2GHD9+3BkZ6oh1vGPHDkmlUi6NcwsXLnTviXpBPrampqZY0UePHp3d3Nz8PpTN6+o0lY6yUDzKIi9dVVVVUOG4MG7ImxDkoSxbAx6UsmD9+vVy6tQpV/kwgI0bN7o0rPfuu+92lf3QQw/F5R9++OGCSqCVg7lz5yZW3oMPPuj2uO7LL79ccO6mm26SofDaa6+VPB4M3g+tGDw9fry05g2ysapKZnz0UUH5Q5ddJqf6+qAVaevslBVnzzpZNIqjR4/KNddcE5dFC582bVpscDAo5C1atCgugzpmg/KVz5aPfOxxDnucZxmcQ9p5AFoV0Wk/T5+DEdAgoPzGxkbXypAHJbHFPf30064slAy3ppWtgfyWLVtk//79cSumDNO8LgzA90hseag4vxXqPFZs1pPnPXF934voPL6Xlofy5x0+7O6xt7HRKfdY3pAn79/v9jd1dLh775k+HS4tlmUdbtu2TfpgJCKucd1www0F+fCYzKcMW7NWPpTLFu93AdoI4i4A1ub3P8XQ/dChQ4cK8iELZROmKcP95s2bz3l5AOWzouE1NPfff3/i8/j9M5VLD8R3QotNMoyMJ8/3X7FiRdyNwTW/9dZbiYYR9+GZjLv2a/X17nD/rFmy5fTpOA1wjn4K1+b1YUi49quvvho/z8033+wUD6Bw7fFQVnd7xZTvdwG+EaBsGkEY+iBsYNeuXUWDHt8zQBZl4Y6wabl77rknfjmCF9JWroHbZ8uH8nUMgGs8+uijcuutt7qXR1pDpVD5cOd+l8A8ltGKbMgbBZV/3XXXyc6dOwvkEeegblgGMl988YUL6mAEcPto+eB7p065+yDoA2go9Aws054vg27Rb3R4T11PSCNPG8F9990Xe8Yk5eNYGwbSvhFgH151+rT8qq/PbWurq922s6nJbe9Pneo2HvM8y0MWwJJRYU899ZTbAPb33nuve1D0XVAiKgTWDOueOHFi/PBUtlY+gj7IYIM7RZClK0AHXVqRWvk4pnKRh3OlArS2trYC5eOYhgLlwwiKBZjo8+Hq0c9T+fCS2JBGHs6hjB8fPPHEE06ZcO+Ic6h8NChsSCMP51AGZSEDtKvXys8//41UOPP88qHru/LBi8usq3NBCiwaD4wNaeQxyAGQwbHqi5wls3/3hy7nC309vw/X56FotC5sVLr/LNkEebpllEWgio1y/ijGl0efj3pi0DZ27Fi30QhwjnEBQZ3Rs6KbW7NmjVP4ypUrZcOGDW5DGnk4x64QMpDVAZ8e9jEwxMaAT3sKpl0MsKez0ykUe/dQdXWu//r++PHuGGkahl+W6MCOFeOPW1mBPPa7mmLB4YVKQ0ND0TkBHfgmgVY+WDwGWXbdwyXNlk3FAua5YYvyCu7BlPJdXm2tS8N1I+jzAz4oG4pnwMhjVow2AvZpSS2T0HjYLRQL4nB9DjV5r6QKzXjyCPhYlsNWyumgNwm4dwR87YcPx10A4Pu3Tp/uyujuC6MnPgNbOPZ33nlnnI/WDtfPc6hnnIMsW7Y/EmDL5znGAf48QXrX+PGyK5+xrqdnoEISJl74MMLxPzxEb6+rNIzz/YCP4OWhMPbhnA1LmuTBSyLI05WkZ81KtSicY1+vA75igaEPFI1o3w/4QLHhK58T43zd8hn4uXP5NLpSdgEIFNlQECvh2nDzeHe4fT0KgvKh9DvuuMPVP8pCBrKNjY036pk9pKFYKDwpIOSwkek0Kp8Pyr3f1xFaNCsWewRsKI/WwnE6lM8ImNeC8qFAHO/bt8/lHTt2LL42AhxWsB/x6uEWn1HL6shcG4E/DNRltHLb1cgA+Qz4+OxQoI5pUEZP0gB4S4zzMdRDpH+qvj72mmj5jKlYRsuuXbvWBcsEitZGQOVrILNu3br4WCuYRpB0zp8tTGtFYlijFV2KJDdNFw4D0EakXSGUX6xv1ArTY27Icww/WJ/KMrfddlviucFoyytYV67/fBoYonum6dNzxifiDGDuwYMFE0FIcyJI6uvdHl4NhoW6x7X1zCq7VKYZKKIMykIGsrfcckvcwn0j8NcCkmYLnQHA9egpYSjXn4tnHhVPGW0IeCBM8uhxPvt8uP3BlM9W6Y/zy0VfN+kegxlPq/IKSfFCqaDMBciY4VNdA4d77CZcy1eegehRgG5IeiYVaC9EmaQJHj/aB8VmC4OmpqbIn+ChMehpSX1MEC+4F827e4IpSz3OZ0vBSpmfhwUdLKr46BiA8+1JZdLptOu3h7MYNG/ePCfPRaWhLgbhmAtpXBjz68KHgSTlsAbAyTdsaFDoDjDO14tB6PPh9vViELqp9evXf7/YYlASfllnAFIBUELSzF45S6lAV77frZQaDRAo8JuU7+7uTlwOTjJaxDH+cjBnN4lu/RwicpEN6EAUeatWrapoOTiYM2dOdL7W8y9G+fqaQGpqBpaT06nCrhP0Z7KJ+Wc6zkoqDCuSb5kyUfrUc1blvUYURdKPFduEhT1ysr0jFwNwPfyuu+4qWHl75plnSuafOHFCLnb5uu+MlR//vDBCL5fNG591iq1EHiz5wdJhyf/lT+vEeQBUAIdmpeC3AuDKK690FQD3dzHLT2uql58u/WXBlz3lgK7gxU3PSiRBRfJj62tl0S2/kOHwt2fXSYgXgoVrGGQkfRdAKFNKfseO3W4brvyFcP8wDOK8J598sqyNBGFYIP/YH347pHROPpSTJ0+67YVNfy5rY/kgCHNdgF5WxEu/8cZAVL1w4fw4P2natpT84sVXOxkqgdcqJY+ykPPhdXmNr+r+qby8/wy4RpI8+ufhUoks5XX/D1b95nclZbQBdZ7tzhmARlcyYOUlKSUJLb9s2Yvy3HM/ccdskfraPitX/trdx38G8MADq1zeYNdIki33/sXuw+dKkk8KzmbOnClJfPjhhyVlp615X+TTv5adhrwf5JXqyv79o9+LyIAB1I2pyRkAhxZ8QSoO8IX9VqSHI0z7LpPXSCJJvpxhYyn5Ui77q5KPyhgqFsOXPXL/bJF8Cy4nDfkom5Gurq74Gv984bniN8yfY/koykoaFc6oNklxrBRtCEhTRsuX8h5Ll24uaFm+PIwuN2P8SMGzJCnlX0t/KMvLuD+uCTZt+ln+y9ri9wd4Rv0MlBfZGhsmGwdl0A8XA9O04JVXXkk8n4kKvYB23+WkIR+EA/XTuiD3DWG5ZCORok/PIIgzVIkvUCQfleR/UZzkDbQ8zre0bC3r/tdueqnk/Sk/2HNmvHz/GWA4/nMjb7DrlktS9/F1yiP+dFfwo2Ao0K94RtSMBbQM02xhusX5HqGUvKaU4Q12fxoOlKcVWO79U2oKtpz7FwMtv1jrT2KoowDy2Wefua3t7W1lbSwPCkYBrEAd8Om+X48EikXRPjqeAKXkH3/8kTjg8uG5wUYBgzHY8z/u3cd/Ll/+fETylYBRQPUwRwHoAtL+fDeNgFAZxQKkUvJIwxuUGkn48qjsYr9RWL36sSHf3x8WDibv34f3T7p3MTfsR/ul0PJDHQWASkYB7v5+RIwX1tZfrC8tFsVreV/x5cqX02d/W+4ffQtGAR0dHUMaBbA8YoCgpaUlwvInLadUBWgwFYrlXKxqXczyl04d7+byhzOV+4+/b3DpSuTH1ddKbzhWhsOJTz8emAjCCw11MURzscsf8L5zHCqVyg8X5wEqWc+v9HuAC11+wrhqN6OGnjwjuXn9lEQuzXl+7eqx+IO4D11/Noqkq6u7YnkA+WxePpQon9afegwcZ7KBk+/q7pG0W89uqBv2enR7Z+85+UEQxJ+QYcPaNPf6HI57e79Z+Ynel0tDZffu3QOrORcg6bramorWo8982S9XXHGFO+Y3gqhY9KW6wvv7+12aEzyjR492n3Ihr1L5BQsWxJ9ZocVqeSgaeZB3L5xOuw3X3J7/geX8+aXXB4qxe3fySuOFRDqLwaCIPP/880MSvP322yUVDAyj3nnnndil8o8XoACc50ji9ddfdwqrra11f3hA5WLPIAzy/K085aEwpLdu3RrL4/eGWl4bCpSOvb4/Wzw2QIO62Enr9eihgnlwVCIWFVDRcMf41woqihWu3S++g4PbZUunEpDGh5X4pm4w+UmTJsUy2gjw62K2eCidPy7V3mTZsmXy7rvvFhjDUFr08uXLR0TLJ+lK17NzCgzct3VQDCuaX8mykuGe0bphIMyn8qE0tGr+MLOYPNw+vyxmq9fXwvZS5yH5MgilPR3I1N6MfIlrZ7NyKBXKjExW3rv+euetaDQ+Gz97r6T8ifnzR5YBVLKgQFkoAMMo/Zt65HHZEYqrGV3jjpGPIZVufVAEPnFGF6Hl+ZMxGBc2yl977bUFv1tgMOj6+Ujk82xWTmZE/hOJVEdZ6ejJSDYdyYyqQLq7uuJuIps0iZMgPxWLJvCUXvFKF4O+DYTnYyaL37MDKCIpMj/Tfsa1arR0/uY9vo4yBsiinN86+ak1fm7Nvp1AoexSDlehvw/kRDaSOsx0OQ/jgh35bxhKb/5397h/kOABkuRTYSBVmZz8SCNdaj17MLAezcCLQAn+N/HaE1DZbM060GO/7/8jGI9hPO6h02lnJJSHMimPsXEqEumJxCmxIQxkXHVKJkWBXJLJysf5rqXYj02ySv7trn6px8hjTE7+MsnKwC8Sh/YBybeVikwaXQADNCghG5X2JlRYf39fwficgZsflCXJM+jDl7yUB/xHjUv7clMgC0aFMhbKCxDppuUI7p33MPr+Plq+NgjcfLmWH2mc803gcGAXEKDqgiD+WRdbGY7ZunNj8oz7IlW7YCiEgRx/rKFjAD0qoOIon8nAA+XOZwORI739cjAjMrMmJVOCQPAXCpekAumQ3CgC99dBqAbyDaHIvv7IybeEhfIjjYpHAfyrOGxolfjOHu5dr1CBqVOnutZHl69/ZcP+G10ERgmQPZ3//yEARc2ePTvuNmgslO/rywV1ONeZz58c5JQGU5kUZQR/z0gPwPslAXlcYXqYmy715UcaYaWfFQEof+/eva51odWy5XPoB9Bn4zduCOYwXocM3TcneWg4jBnQ8tnvIw9fseDHGBxtUB4xCLuQuiiS746uklm1VVIfiUyJImmOIvk8DNxwrr+vP+4uwoT4B/IwrkwqSJQfaaQrGQWgf0Vl6X4YHgCKwJ5DLR21owXW19dLP2KG/FicP82CkXCeAHsEdpzRIzCECRMmxJ7DTQ9jpjCblcWLF8sfZ892XRF6bH1/N4yLRKKe7ngWMOu9OyZ5MM4H6IRghvzedjSWT2XkUdEogLKoUMzjY4iGSsV38WxhdNcoA+VxGJfJK49xAd0/jvFXbSjPeX+Ug3HBO2CySc8iugA0P+z84IMP3LIqDCfp/iyvp481mOAZSZM8QwoCMbc/HNiC0UfzmFOxeloWBnL55ZfHCtWBHH4ivmTJEnfMeXwqn2ncA+sHUK6exOH96IWw13MMSKfClISpXL5eFzBEgrmzpkeVrEf/73hHwVSsK+PN8um0VhzLfh3yNBq92gimTJki5QDDgwHxfpS/0JeDDcMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMMwDMOQc/g/z390b1xxdH8AAAAASUVORK5CYII="};})();</script><script>window.BEC_PERIPHERALS=[{id:'main-me',key:'AE_INTERFACE',title:'主网供液 ME 接口',p:[68,-7,50],role:'mainInterface',type:'ME INTERFACE',icon:'▧',description:'公共供液网络'},{id:'workshop-me',key:'AE_INTERFACE',title:'样板工坊 ME 接口',p:[80,-7,50],role:'workshopInterface',type:'ME INTERFACE',icon:'▧',description:'公共样板接口 · 可选'},{id:'sub-me',key:'AE_INTERFACE',title:'原液子网 ME 接口',p:[92,-7,50],role:'groups[1].subInterface',type:'ME INTERFACE',icon:'▧',description:'原液子网络'},{id:'fluid-transposer',key:'OC_TRANS',title:'供液转运器',p:[104,-7,50],role:'groups[1].transposer',type:'FLUID TRANSPOSER',icon:'⇄',description:'主网 → 原液子网',sides:[['mainSide','主网侧方向',4],['subSide','子网侧方向',5]]},{id:'bulk-transposer-1',key:'OC_TRANS',title:'高速供液转运器 01',p:[116,-7,50],role:'groups[1].bulkTransposers[1]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 01'},{id:'bulk-transposer-2',key:'OC_TRANS',title:'高速供液转运器 02',p:[128,-7,50],role:'groups[1].bulkTransposers[2]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 02'},{id:'bulk-transposer-3',key:'OC_TRANS',title:'高速供液转运器 03',p:[140,-7,50],role:'groups[1].bulkTransposers[3]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 03'},{id:'bulk-transposer-4',key:'OC_TRANS',title:'高速供液转运器 04',p:[152,-7,50],role:'groups[1].bulkTransposers[4]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 04'},{id:'bulk-transposer-5',key:'OC_TRANS',title:'高速供液转运器 05',p:[164,-7,50],role:'groups[1].bulkTransposers[5]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 05'},{id:'bulk-transposer-6',key:'OC_TRANS',title:'高速供液转运器 06',p:[116,-7,64],role:'groups[1].bulkTransposers[6]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 06'},{id:'bulk-transposer-7',key:'OC_TRANS',title:'高速供液转运器 07',p:[128,-7,64],role:'groups[1].bulkTransposers[7]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 07'},{id:'bulk-transposer-8',key:'OC_TRANS',title:'高速供液转运器 08',p:[140,-7,64],role:'groups[1].bulkTransposers[8]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 08'},{id:'bulk-transposer-9',key:'OC_TRANS',title:'高速供液转运器 09',p:[152,-7,64],role:'groups[1].bulkTransposers[9]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 09'},{id:'bulk-transposer-10',key:'OC_TRANS',title:'高速供液转运器 10',p:[164,-7,64],role:'groups[1].bulkTransposers[10]',type:'BULK TRANSPOSER',icon:'⇄',description:'高速供液口 10'},{id:'nanite-bank',key:'BANK_BOX',title:'蜂群硬盘箱',p:[6,-7,58],role:null,type:'CELL BANK',icon:'▣',description:'无独立 OC 地址 · 外形示意',related:'nanite-transposer',note:'硬盘箱通过蜂群转运器的箱子方向读取；不是另一个 OC 组件，不需要独立地址。箱体材质暂用示意。'},{id:'nanite-transposer',key:'OC_TRANS',title:'蜂群硬盘转运器',p:[36,-7,58],role:'groups[1].nanites.transposer',type:'CELL TRANSPOSER',icon:'⇄',description:'ME-IO 装入 / 回收',sides:[['bankSide','硬盘箱方向',0],['loadSide','装入端口方向',3],['returnSide','回收端口方向',2]]},{id:'load-io',key:'AE_IO',title:'ME-IO 装入端口',p:[30,-7,58],role:null,type:'ME IO PORT',icon:'▥',description:'由蜂群转运器访问',related:'nanite-transposer',note:'在蜂群硬盘转运器中设置装入端口方向；此端口无需独立 OC 组件地址。装入信号在装入红石模块中配置。'},{id:'return-io',key:'AE_IO',title:'ME-IO 回收端口',p:[42,-7,58],role:null,type:'ME IO PORT',icon:'▥',description:'由蜂群转运器访问',related:'nanite-transposer',note:'在蜂群硬盘转运器中设置回收端口方向；此端口无需独立 OC 组件地址。回收信号在回收红石模块中配置。'},{id:'load-redstone',key:'OC_RS',title:'蜂群装入红石',p:[30,-7,70],role:'groups[1].nanites.loadRedstone',type:'REDSTONE CONTROL',icon:'⚡',description:'装入端口信号',sides:[['loadOutputSide','装入红石输出方向',0]]},{id:'return-redstone',key:'OC_RS',title:'蜂群回收红石',p:[42,-7,70],role:'groups[1].nanites.returnRedstone',type:'REDSTONE CONTROL',icon:'⚡',description:'回收端口信号',sides:[['returnOutputSide','回收红石输出方向',0]]}];window.BEC_PERIPHERALS.forEach(function(m){var map={'load-io':['A','load-redstone','A · 装入 ME-IO'],'load-redstone':['A','load-io','A · 装入红石 I/O'],'return-io':['B','return-redstone','B · 回收 ME-IO'],'return-redstone':['B','return-io','B · 回收红石 I/O']};var v=map[m.id];if(v){m.channel=v[0];m.pair=v[1];m.label=v[2];m.description=v[0]+' 通道 · '+(v[0]==='A'?'硬盘 → 蜂群网':'蜂群网 → 硬盘');}});</script><script>(function(){'use strict';var FACE=[{n:[1,0,0],c:[[1,0,0],[1,1,0],[1,1,1],[1,0,1]]},{n:[-1,0,0],c:[[0,0,1],[0,1,1],[0,1,0],[0,0,0]]},{n:[0,1,0],c:[[0,1,1],[1,1,1],[1,1,0],[0,1,0]]},{n:[0,-1,0],c:[[0,0,0],[1,0,0],[1,0,1],[0,0,1]]},{n:[0,0,1],c:[[1,0,1],[1,1,1],[0,1,1],[0,0,1]]},{n:[0,0,-1],c:[[0,0,0],[0,1,0],[1,1,0],[1,0,0]]}];var I=[1,0,0,0,1,0,0,0,1],RY=[-1,0,0,0,1,0,0,0,-1],RX=[1,0,0,0,0,-1,0,1,0],RXN=[1,0,0,0,0,1,0,-1,0],RY90=[0,0,1,0,1,0,-1,0,0],RY270=[0,0,-1,0,1,0,1,0,0];function transform(r,v){return[r[0]*v[0]+r[1]*v[1]+r[2]*v[2],r[3]*v[0]+r[4]*v[1]+r[5]*v[2],r[6]*v[0]+r[7]*v[1]+r[8]*v[2]];}
function add(a,b){return[a[0]+b[0],a[1]+b[1],a[2]+b[2]];}function sub(a,b){return[a[0]-b[0],a[1]-b[1],a[2]-b[2]];}function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}function norm(v){var d=Math.sqrt(dot(v,v))||1;return v.map(function(n){return n/d;});}function cross(a,b){return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];}
function multiply(a,b){var o=new Float32Array(16);for(var c=0;c<4;c++)for(var r=0;r<4;r++)for(var k=0;k<4;k++)o[c*4+r]+=a[k*4+r]*b[c*4+k];return o;}
function modelMatrix(r,p){return new Float32Array([r[0],r[3],r[6],0,r[1],r[4],r[7],0,r[2],r[5],r[8],0,p[0],p[1],p[2],1]);}
function matPoint(m,p){return[m[0]*p[0]+m[4]*p[1]+m[8]*p[2]+m[12],m[1]*p[0]+m[5]*p[1]+m[9]*p[2]+m[13],m[2]*p[0]+m[6]*p[1]+m[10]*p[2]+m[14]];}
function buildMesh(data,key){var model=data.models[key],size=model.size,map=new Map(),faces=[],count=0;if(model.cube)return{key:key,size:size,blocks:1,faces:FACE.map(function(f,i){return{p:[0,0,0],n:f.n,c:f.c.map(function(v){return v.map(function(n,a){return n*size[a];});}),t:model.faceTextures[i],glass:false};})};model.rows.forEach(function(layer,z){layer.forEach(function(row,down){for(var x=0;x<row.length;x++){var ch=row[x];if(ch!==' '&&ch!=='-'&&ch!=='+'){var y=size[1]-1-down;map.set(x+','+y+','+z,ch);count++;}}});});map.forEach(function(ch,pos){var p=pos.split(',').map(Number),mat=model.materials[ch],tile=ch==='~'?data.textureTiles.BEC_CASING:data.materialTextures[mat];FACE.forEach(function(f,fi){var n=f.n;if(map.has((p[0]+n[0])+','+(p[1]+n[1])+','+(p[2]+n[2])))return;var t=ch==='~'&&fi===5?data.textureTiles[key]:tile;faces.push({p:p,n:n,c:f.c,t:t,glass:mat==='ElectromagneticWaveguide'});});});return{key:key,size:size,faces:faces,blocks:count};}
function cubeMesh(data){return{key:'marker',size:[3,3,3],faces:FACE.map(function(f,i){return{p:[0,0,0],n:f.n,c:f.c.map(function(v){return v.map(function(n){return n*3;});}),t:i===5?data.textureTiles.BEC_IO_NODE:data.textureTiles.BEC_CASING,glass:false};}),blocks:1};}
function makeModules(data){var a=[];function put(id,key,title,p,r,kind,role){var m={id:id,key:key,title:title,p:p,r:r||I,kind:kind,role:role,size:data.models[key].size};m.center=add(transform(m.r,m.size.map(function(v){return v/2;})),p);m.marker=add(transform(m.r,data.models[key].controller),p);a.push(m);return m;}
put('assembler','BEC_ASSEMBLER','观测阵列 01',[0,0,0],I,'assembler',null);put('field','BEC_CONTAINMENT_FIELD','约束场 01',[78,7,-7],I,'field','groups[1].storage');put('generator','BEC_GENERATOR','纠缠器 01',[164,6,6],RY270,'generator','groups[1].generators[1]');put('gate','BEC_DIODE','麦克斯韦门 01',[61,10,10],I,'gate','groups[1].gate');var i=0;[12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x-3,4,-14],I,'node','nodes['+i+'].address');});[12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x+3,4,44],RY,'node','nodes['+i+'].address');});[12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x-3,45,4],RX,'node','nodes['+i+'].address');});[12,24,36,48].forEach(function(x){put('node-'+(++i),'BEC_IO_NODE','传送节点 '+String(i).padStart(2,'0'),[x-3,-14,26],RXN,'node','nodes['+i+'].address');});(window.BEC_PERIPHERALS||[]).forEach(function(d){var m=put(d.id,d.key,d.title,d.p,I,'peripheral',d.role);Object.keys(d).forEach(function(k){if(k!=='p')m[k]=d[k];});});return a;}
function Scene(canvas,data,onSelect,onRender){this.canvas=canvas;this.data=data;this.onSelect=onSelect;this.onRender=onRender;this.modules=makeModules(data);this.meshes={};var self=this;Object.keys(data.models).forEach(function(k){self.meshes[k]=buildMesh(data,k);});this.markerMesh=cubeMesh(data);this.camera={target:[78,8,27],yaw:-.85,pitch:.62,distance:250};this.selected='assembler';this.hovered=null;this.layer=49;this.showNodes=true;this.fullNodes=false;this.showPeripherals=true;this.isolate=false;this.onlyMissing=false;this.statuses={};this.visibleModules=[];this.pending=false;this.drawCount=0;var gl=null;try{gl=canvas.getContext('webgl',{alpha:false,antialias:true,preserveDrawingBuffer:true});}catch(e){}this.gl=gl;this.mode=gl?'WebGL':'Canvas 2D';if(gl)this.initGL();else this.ctx=canvas.getContext('2d');this.atlas=new Image();this.atlas.onload=function(){if(gl){gl.bindTexture(gl.TEXTURE_2D,self.texture);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,self.atlas);}self.request();};this.atlas.src=data.atlas;this.bind();this.observer=new ResizeObserver(function(){self.request();});this.observer.observe(canvas);}
Scene.prototype.bind=function(){var self=this,drag=null;this.canvas.addEventListener('pointerdown',function(e){if(e.button!==0&&e.button!==1&&e.button!==2)return;drag={x:e.clientX,y:e.clientY,lastX:e.clientX,lastY:e.clientY,moved:false,pan:e.button!==0||e.shiftKey};self.canvas.setPointerCapture(e.pointerId);self.canvas.classList.add('dragging');});this.canvas.addEventListener('pointermove',function(e){if(drag){var dx=e.clientX-drag.lastX,dy=e.clientY-drag.lastY;if(Math.abs(e.clientX-drag.x)+Math.abs(e.clientY-drag.y)>4)drag.moved=true;if(drag.pan){var scale=self.camera.distance*.5/self.canvas.clientHeight;self.camera.target=add(self.camera.target,add(self.right.map(function(v){return-v*dx*scale;}),self.up.map(function(v){return v*dy*scale;})));}else{self.camera.yaw-=dx*.008;self.camera.pitch=Math.max(-1.3,Math.min(1.48,self.camera.pitch+dy*.008));}drag.lastX=e.clientX;drag.lastY=e.clientY;self.request();}else{var hit=self.pick(e.clientX,e.clientY);if(hit!==self.hovered){self.hovered=hit;self.canvas.style.cursor=hit?'pointer':'grab';self.request();}}});this.canvas.addEventListener('pointerup',function(e){if(drag&&!drag.moved&&e.button===0){var hit=self.pick(e.clientX,e.clientY);if(hit)self.onSelect(hit,true);}drag=null;self.canvas.classList.remove('dragging');});this.canvas.addEventListener('pointercancel',function(){drag=null;self.canvas.classList.remove('dragging');});this.canvas.addEventListener('contextmenu',function(e){e.preventDefault();});this.canvas.addEventListener('wheel',function(e){e.preventDefault();self.camera.distance=Math.max(18,Math.min(520,self.camera.distance*Math.exp(Math.max(-240,Math.min(240,(e.deltaMode===1?e.deltaY*32:e.deltaMode===2?e.deltaY*240:Math.abs(e.deltaY)<16?e.deltaY*32:e.deltaY)))*.002)));self.request();},{passive:false});};Scene.prototype.request=function(){if(this.pending)return;this.pending=true;var self=this;requestAnimationFrame(function(){self.pending=false;self.draw();});};Scene.prototype.cameraMatrices=function(){var c=this.camera,eye=add(c.target,[Math.sin(c.yaw)*Math.cos(c.pitch)*c.distance,Math.sin(c.pitch)*c.distance,Math.cos(c.yaw)*Math.cos(c.pitch)*c.distance]);this.eye=eye;var back=norm(sub(eye,c.target)),right=norm(cross([0,1,0],back)),up=cross(back,right);this.back=back;this.right=right;this.up=up;var view=new Float32Array([right[0],up[0],back[0],0,right[1],up[1],back[1],0,right[2],up[2],back[2],0,-dot(right,eye),-dot(up,eye),-dot(back,eye),1]);this.halfH=c.distance*.25;this.halfW=this.halfH*this.canvas.clientWidth/this.canvas.clientHeight;var l=-this.halfW,r=this.halfW,b=-this.halfH,t=this.halfH,n=.1,f=2000;var proj=new Float32Array([2/(r-l),0,0,0,0,2/(t-b),0,0,0,0,-2/(f-n),0,-(r+l)/(r-l),-(t+b)/(t-b),-(f+n)/(f-n),1]);this.vp=multiply(proj,view);};Scene.prototype.project=function(p){var v=sub(p,this.camera.target);return{x:(dot(v,this.right)/this.halfW+1)*this.canvas.clientWidth/2,y:(1-dot(v,this.up)/this.halfH)*this.canvas.clientHeight/2,depth:dot(v,this.back)};};Scene.prototype.meshFor=function(m){return m.kind==='node'&&!this.fullNodes&&!(this.isolate&&this.selected===m.id)?this.markerMesh:this.meshes[m.key];};Scene.prototype.matrixFor=function(m){return this.meshFor(m)===this.markerMesh?modelMatrix(I,sub(m.marker,[1,1,1])):modelMatrix(m.r,m.p);};Scene.prototype.list=function(){var self=this;return this.modules.filter(function(m){var values=self.runtimeValues||{},assigned=Number(values['n'+m.id.slice(5)+'.group']||1);if(m.kind==='node'&&values['n'+m.id.slice(5)+'.address']&&self.runtimeGroup&&assigned!==self.runtimeGroup)return false;return(!self.isolate||m.id===self.selected)&&(m.kind!=='peripheral'||self.showPeripherals||m.id===self.selected)&&(!self.onlyMissing||!self.statuses[m.id])&&(m.kind!=='node'||self.showNodes||m.id===self.selected);});};Scene.prototype.draw=function(){var ratio=Math.min(window.devicePixelRatio||1,1.6),w=Math.max(1,Math.round(this.canvas.clientWidth*ratio)),h=Math.max(1,Math.round(this.canvas.clientHeight*ratio));if(this.canvas.width!==w||this.canvas.height!==h){this.canvas.width=w;this.canvas.height=h;}this.cameraMatrices();this.visibleModules=this.list();if(this.gl)this.drawGL();else this.drawCanvas(ratio);this.drawCount++;if(this.onRender)this.onRender(this);};Scene.prototype.pick=function(clientX,clientY){if(!this.right)return null;var rect=this.canvas.getBoundingClientRect(),x=((clientX-rect.left)/rect.width*2-1)*this.halfW,y=(1-(clientY-rect.top)/rect.height*2)*this.halfH,origin=add(this.eye,add(this.right.map(function(v){return v*x;}),this.up.map(function(v){return v*y;}))),direction=this.back.map(function(v){return-v;}),best=Infinity,hit=null,self=this;this.visibleModules.forEach(function(m){var matrix=self.matrixFor(m),position=[matrix[12],matrix[13],matrix[14]],delta=sub(origin,position),r=[matrix[0],matrix[4],matrix[8],matrix[1],matrix[5],matrix[9],matrix[2],matrix[6],matrix[10]],inv=[r[0],r[3],r[6],r[1],r[4],r[7],r[2],r[5],r[8]],o=transform(inv,delta),d=transform(inv,direction),size=self.meshFor(m).size,near=-Infinity,far=Infinity;for(var a=0;a<3;a++){if(Math.abs(d[a])<1e-7){if(o[a]<0||o[a]>size[a])return;}else{var t0=-o[a]/d[a],t1=(size[a]-o[a])/d[a];near=Math.max(near,Math.min(t0,t1));far=Math.min(far,Math.max(t0,t1));}}var distance=Math.max(0,near);if(near<=far&&far>=0&&distance<best&&origin[1]+direction[1]*distance<=self.layer+1){best=distance;hit=m.id;}});return hit;};Scene.prototype.focus=function(id,isolated){var m=this.modules.find(function(v){return v.id===id;});if(!m)return;this.selected=id;if(isolated){this.isolate=true;this.camera.target=m.center.slice();this.camera.distance=Math.max.apply(null,m.size)*2.15;}this.request();};Scene.prototype.reset=function(){this.isolate=false;this.camera={target:[78,8,27],yaw:-.85,pitch:.62,distance:250};this.request();};Scene.prototype.initGL=function(){var g=this.gl,self=this;function shader(type,source){var s=g.createShader(type);g.shaderSource(s,source);g.compileShader(s);if(!g.getShaderParameter(s,g.COMPILE_STATUS))throw new Error(g.getShaderInfoLog(s));return s;}
var vs='attribute vec3 aPosition;attribute vec3 aNormal;attribute vec2 aUV;uniform mat4 uVP;uniform mat4 uModel;varying vec2 vUV;varying vec3 vNormal;varying float vY;void main(){vec4 p=uModel*vec4(aPosition,1.0);vY=p.y;vUV=aUV;vNormal=mat3(uModel)*aNormal;gl_Position=uVP*p;}';var fs='precision mediump float;uniform sampler2D uAtlas;uniform float uSlice;uniform float uSelected;uniform float uSolid;uniform vec4 uColor;varying vec2 vUV;varying vec3 vNormal;varying float vY;void main(){if(uSolid>0.5){gl_FragColor=uColor;return;}if(vY>uSlice)discard;vec4 c=texture2D(uAtlas,vUV);if(c.a<0.05)discard;float light=.6+.4*max(0.0,dot(normalize(vNormal),normalize(vec3(-.4,.85,.5))));vec3 rgb=c.rgb*light;rgb=mix(rgb,vec3(.08,.72,.87),uSelected*.26);gl_FragColor=vec4(rgb,c.a);}';this.program=g.createProgram();g.attachShader(this.program,shader(g.VERTEX_SHADER,vs));g.attachShader(this.program,shader(g.FRAGMENT_SHADER,fs));g.linkProgram(this.program);if(!g.getProgramParameter(this.program,g.LINK_STATUS))throw new Error(g.getProgramInfoLog(this.program));g.useProgram(this.program);this.loc={};['aPosition','aNormal','aUV'].forEach(function(n){self.loc[n]=g.getAttribLocation(self.program,n);});['uVP','uModel','uSlice','uSelected','uSolid','uColor'].forEach(function(n){self.loc[n]=g.getUniformLocation(self.program,n);});this.texture=g.createTexture();g.bindTexture(g.TEXTURE_2D,this.texture);g.texImage2D(g.TEXTURE_2D,0,g.RGBA,1,1,0,g.RGBA,g.UNSIGNED_BYTE,new Uint8Array([110,120,130,255]));g.texParameteri(g.TEXTURE_2D,g.TEXTURE_MIN_FILTER,g.NEAREST);g.texParameteri(g.TEXTURE_2D,g.TEXTURE_MAG_FILTER,g.NEAREST);g.texParameteri(g.TEXTURE_2D,g.TEXTURE_WRAP_S,g.CLAMP_TO_EDGE);g.texParameteri(g.TEXTURE_2D,g.TEXTURE_WRAP_T,g.CLAMP_TO_EDGE);Object.keys(this.meshes).forEach(function(k){self.upload(self.meshes[k]);});this.upload(this.markerMesh);var lines=[];for(var x=-25;x<=195;x+=5)lines.push(x,-16,-45,0,1,0,0,0,x,-16,75,0,1,0,0,0);for(var z=-45;z<=75;z+=5)lines.push(-25,-16,z,0,1,0,0,0,195,-16,z,0,1,0,0,0);this.grid=this.buffer(lines);};Scene.prototype.buffer=function(values){var g=this.gl,b=g.createBuffer();g.bindBuffer(g.ARRAY_BUFFER,b);g.bufferData(g.ARRAY_BUFFER,new Float32Array(values),g.STATIC_DRAW);return{buffer:b,count:values.length/8};};Scene.prototype.upload=function(mesh){var opaque=[],glass=[];mesh.faces.forEach(function(f){var a=f.glass?glass:opaque,u=(f.t%8)*16/128,v=Math.floor(f.t/8)*16/128,uv=[[u+.001,v+.124],[u+.001,v+.001],[u+.124,v+.001],[u+.124,v+.124]];[0,1,2,0,2,3].forEach(function(i){a.push(f.p[0]+f.c[i][0],f.p[1]+f.c[i][1],f.p[2]+f.c[i][2],f.n[0],f.n[1],f.n[2],uv[i][0],uv[i][1]);});});mesh.opaque=this.buffer(opaque);mesh.glass=this.buffer(glass);};Scene.prototype.drawBuffer=function(b,mode){if(!b.count)return;var g=this.gl;g.bindBuffer(g.ARRAY_BUFFER,b.buffer);g.enableVertexAttribArray(this.loc.aPosition);g.vertexAttribPointer(this.loc.aPosition,3,g.FLOAT,false,32,0);g.enableVertexAttribArray(this.loc.aNormal);g.vertexAttribPointer(this.loc.aNormal,3,g.FLOAT,false,32,12);g.enableVertexAttribArray(this.loc.aUV);g.vertexAttribPointer(this.loc.aUV,2,g.FLOAT,false,32,24);g.drawArrays(mode||g.TRIANGLES,0,b.count);};Scene.prototype.drawGL=function(){var g=this.gl,self=this;g.viewport(0,0,this.canvas.width,this.canvas.height);g.clearColor(.94,.954,.969,1);g.clear(g.COLOR_BUFFER_BIT|g.DEPTH_BUFFER_BIT);g.useProgram(this.program);g.enable(g.DEPTH_TEST);g.enable(g.CULL_FACE);g.enable(g.BLEND);g.blendFunc(g.SRC_ALPHA,g.ONE_MINUS_SRC_ALPHA);g.uniformMatrix4fv(this.loc.uVP,false,this.vp);g.uniform1f(this.loc.uSolid,1);g.uniform4f(this.loc.uColor,.76,.8,.85,.45);g.uniformMatrix4fv(this.loc.uModel,false,modelMatrix(I,[0,0,0]));this.drawBuffer(this.grid,g.LINES);g.uniform1f(this.loc.uSolid,0);g.uniform1f(this.loc.uSlice,this.layer+1);g.bindTexture(g.TEXTURE_2D,this.texture);this.visibleModules.forEach(function(m){g.uniformMatrix4fv(self.loc.uModel,false,self.matrixFor(m));g.uniform1f(self.loc.uSelected,(m.id===self.selected||m.pair===self.selected)?1:m.id===self.hovered?.45:(self.liveStates&&self.liveStates[m.id]==='active'?.7:0));self.drawBuffer(self.meshFor(m).opaque);});g.depthMask(false);this.visibleModules.slice().sort(function(a,b){return dot(sub(a.center,self.eye),self.back)-dot(sub(b.center,self.eye),self.back);}).forEach(function(m){g.uniformMatrix4fv(self.loc.uModel,false,self.matrixFor(m));g.uniform1f(self.loc.uSelected,(m.id===self.selected||m.pair===self.selected)?1:0);self.drawBuffer(self.meshFor(m).glass);});g.depthMask(true);};Scene.prototype.drawCanvas=function(ratio){var ctx=this.ctx,self=this,w=this.canvas.clientWidth,h=this.canvas.clientHeight;ctx.setTransform(ratio,0,0,ratio,0,0);ctx.fillStyle='#f0f3f7';ctx.fillRect(0,0,w,h);ctx.strokeStyle='#d9e0e8';ctx.lineWidth=.6;for(var x=-25;x<=195;x+=5){var a=this.project([x,-16,-45]),b=this.project([x,-16,75]);ctx.beginPath();ctx.moveTo(a.x,a.y);ctx.lineTo(b.x,b.y);ctx.stroke();}for(var z=-45;z<=75;z+=5){var c=this.project([-25,-16,z]),d=this.project([195,-16,z]);ctx.beginPath();ctx.moveTo(c.x,c.y);ctx.lineTo(d.x,d.y);ctx.stroke();}var faces=[];this.visibleModules.forEach(function(m){var matrix=self.matrixFor(m),mesh=self.meshFor(m);mesh.faces.forEach(function(f){var normal=matPoint(matrix,f.n).map(function(v,i){return v-matrix[12+i];});if(dot(normal,self.back)<=.03)return;var points=f.c.map(function(c){return matPoint(matrix,add(f.p,c));});if(points.every(function(p){return p[1]>self.layer+1;}))return;var screen=points.map(function(p){return self.project(p);});var depth=screen.reduce(function(sum,p){return sum+p.depth;},0)/4;faces.push({p:screen,t:f.t,depth:depth,selected:m.id===self.selected||m.pair===self.selected,n:normal});});});faces.sort(function(a,b){return a.depth-b.depth;});if(!this.atlas.complete)return;ctx.imageSmoothingEnabled=false;faces.forEach(function(f){var p=f.p,dx=p[3].x-p[0].x,dy=p[3].y-p[0].y,ex=p[1].x-p[0].x,ey=p[1].y-p[0].y;ctx.setTransform(dx/16*ratio,dy/16*ratio,-ex/16*ratio,-ey/16*ratio,p[1].x*ratio,p[1].y*ratio);ctx.drawImage(self.atlas,(f.t%8)*16,Math.floor(f.t/8)*16,16,16,0,0,16,16);var light=.6+.4*Math.max(0,dot(norm(f.n),norm([-.4,.85,.5])));ctx.fillStyle='rgba(0,0,0,'+(1-light)+')';ctx.fillRect(0,0,16,16);if(f.selected){ctx.fillStyle='rgba(20,178,205,.13)';ctx.fillRect(0,0,16,16);}});ctx.setTransform(ratio,0,0,ratio,0,0);};window.BECScene=Scene;})();</script><script>(function(){'use strict';var $=function(id){return document.getElementById(id);},KEY='bec-structure-studio.draft.v1',draft={version:1,modules:{}},timer,toastTimer,scene,expanded=true;var uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];});}
function toast(s){$('toast').textContent=s;$('toast').hidden=false;clearTimeout(toastTimer);toastTimer=setTimeout(function(){$('toast').hidden=true;},2600);}
function safeDraft(value){if(!value||value.version!==1||!value.modules||typeof value.modules!=='object')throw Error('不是此配置台的草稿文件');var out={version:1,modules:{}};['field','generator','gate'].concat(Array.from({length:15},function(_,i){return'generator-'+(i+2);})).concat((window.BEC_PERIPHERALS||[]).map(function(m){return m.id;})).concat(Array.from({length:16},function(_,i){return'node-'+(i+1);})).forEach(function(id){var item=value.modules[id];if(!item||typeof item!=='object')return;var v={};['address','redstone','gate'].forEach(function(k){if(typeof item[k]==='string')v[k]=item[k].slice(0,160);});if(Number.isInteger(item.group)&&item.group>=1&&item.group<=16)v.group=item.group;['pauseSide','mainSide','subSide','bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide'].forEach(function(k){if(Number.isInteger(item[k])&&item[k]>=0&&item[k]<=5)v[k]=item[k];});out.modules[id]=v;});return out;}
try{var stored=localStorage.getItem(KEY);if(stored)draft=safeDraft(JSON.parse(stored));}catch(e){}
function data(m){return draft.modules[m.id]||{};}
function sideFields(m){return m.kind==='node'?[['pauseSide','暂停信号方向',1]]:(m.sides||[]);}
function sideIssues(m){var v=data(m),keys=m.id==='fluid-transposer'?['mainSide','subSide']:m.id==='nanite-transposer'?['bankSide','loadSide','returnSide']:[];var values=keys.map(function(k){var f=sideFields(m).find(function(f){return f[0]===k;});return v[k]==null?f[2]:v[k];});return new Set(values).size!==values.length;}
function complete(m){var v=data(m);return!!m.role&&uuid.test(v.address||'')&&(m.kind!=='node'||uuid.test(v.redstone||''))&&!sideIssues(m);}
function save(){clearTimeout(timer);if(window.BEC_BINDING_DIRTY)window.BEC_BINDING_DIRTY(draft);$('save-status').innerHTML='<i></i>正在保存草稿…';timer=setTimeout(flush,300);}
function flush(){clearTimeout(timer);draft.updatedAt=new Date().toISOString();try{localStorage.setItem(KEY,JSON.stringify(draft));$('save-status').innerHTML='<i></i>草稿已自动保存';}catch(e){$('save-status').textContent='仅保留在本页 · 请导出草稿';}refreshStatus();if(window.BEC_BINDING_DIRTY)window.BEC_BINDING_DIRTY(draft);}
function refreshStatus(){var n=0;scene.modules.forEach(function(m){scene.statuses[m.id]=complete(m);if(complete(m))n++;});$('binding-count').textContent=n+' / '+scene.modules.filter(function(m){return!!m.role;}).length;renderTree();scene.request();}
function row(m){return'<button class="tree-row '+(m.id===scene.selected?'active':'')+'" data-module="'+m.id+'"><span class="module-icon">'+(m.icon||({assembler:'▤',field:'◎',generator:'◈',gate:'◇',node:'▣'})[m.kind])+'</span><span><span class="tree-title">'+esc(m.title)+'</span><span class="tree-role">'+(m.description||({assembler:'主体结构 · 16 个接入口',field:'凝聚物库存',generator:'凝聚物生成',gate:'阶段切换',node:'传送与暂停控制'})[m.kind])+'</span></span><i class="state-dot '+(complete(m)?'filled':'')+'"></i></button>';}
function renderTree(){var q=$('tree-search').value.trim().toLowerCase(),matches=function(m){return(m.title+' '+(data(m).address||'')).toLowerCase().indexOf(q)>=0;};var main=scene.modules.filter(function(m){return m.kind!=='node'&&m.kind!=='peripheral'&&matches(m);}),nodes=scene.modules.filter(function(m){return m.kind==='node'&&matches(m);});var extras=scene.modules.filter(function(m){return m.kind==='peripheral'&&matches(m);});$('structure-tree').innerHTML=main.map(row).join('')+(extras.length?'<div class="node-group-button peripheral-heading">AE / OC 外设 <span class="count">'+extras.length+'</span></div>'+extras.map(row).join(''):'')+(nodes.length?'<button class="node-group-button" id="node-toggle"><span>'+(expanded?'⌄':'›')+'</span> 传送节点 <span class="count">'+nodes.length+'</span></button><div class="node-rows" '+(!expanded&&!q?'hidden':'')+'>'+nodes.map(row).join('')+'</div>':'');$('structure-tree').querySelectorAll('[data-module]').forEach(function(b){b.onclick=function(){select(b.dataset.module);};});var toggle=$('node-toggle');if(toggle)toggle.onclick=function(){expanded=!expanded;renderTree();};}
function addressField(label,key,value){return'<div class="field"><label for="field-'+key+'">'+label+'</label><input id="field-'+key+'" data-field="'+key+'" value="'+esc(value||'')+'" placeholder="粘贴 OC 组件的完整 UUID" autocomplete="off" spellcheck="false" maxlength="160"><button type="button" class="clear-address" data-clear="'+key+'">清空</button><small class="hint" data-hint="'+key+'">支持 Ctrl + V，可先填一部分，稍后继续。</small></div>';}
function directionFields(m,v){return sideFields(m).map(function(f){return'<div class="field"><label>'+esc(f[1])+'</label><div class="direction-grid">'+[['下',0],['上',1],['南',3],['北',2],['东',5],['西',4]].map(function(d){return'<button data-side="'+d[1]+'" data-side-key="'+f[0]+'" class="'+((v[f[0]]==null?f[2]:v[f[0]])===d[1]?'active':'')+'">'+d[0]+'</button>';}).join('')+'</div></div>';}).join('');}
function ioGuide(m){if(!m.channel&&m.id!=='nanite-transposer')return'';var channels=m.channel?[m.channel]:['A','B'],v=data(scene.modules.find(function(x){return x.id==='nanite-transposer';})),names={0:'下',1:'上',2:'北',3:'南',4:'西',5:'东'};return'<section class="io-guide"><div class="properties-title">ME-IO 配置与控制对应</div>'+channels.map(function(ch){var load=ch==='A',io=load?'load-io':'return-io',rs=load?'load-redstone':'return-redstone',rsModule=scene.modules.find(function(x){return x.id===rs;}),rv=data(rsModule),side=load?'loadSide':'returnSide',out=load?'loadOutputSide':'returnOutputSide',sv=v[side]==null?(load?3:2):v[side],ov=rv[out]==null?0:rv[out];return'<article class="io-channel channel-'+ch+'"><strong><i>'+ch+'</i> '+(load?'装入通道':'回收通道')+'</strong><div class="io-flow">'+(load?'存储盘 → 蜂群收容子网':'蜂群收容子网 → 存储盘')+'</div><div class="io-pair-buttons"><button data-jump="'+rs+'">'+ch+' · '+(load?'装入':'回收')+'红石 I/O</button><span>↓ 红石控制</span><button data-jump="'+io+'">'+ch+' · '+(load?'装入':'回收')+' ME-IO</button></div><dl><dt>传输方向</dt><dd>'+(load?'存储盘 → 网络':'网络 → 存储盘')+'</dd><dt>完成后移盘</dt><dd>'+(load?'清空后移出（工序完成后移出）':'工序完成后移出；不要选等待装满')+'</dd><dt>红石模式</dt><dd>有红石信号时工作</dd><dt>升级卡</dt><dd>1 张红石卡、2 张超光速卡</dd></dl><div class="io-binding-readout">转运器连接此端口：'+names[sv]+' '+sv+'<br>对应红石 I/O 输出面：'+names[ov]+' '+ov+'<br>红石地址：'+(uuid.test(rv.address||'')?'格式完整 · 尚未检测设备':'未填完整')+'</div><button class="related-button" data-jump="'+(m.id===rs?io:rs)+'">配置对应的'+(m.id===rs?' ME-IO 端口':'红石 I/O')+' →</button></article>';}).join('')+'<p class="io-wiring-note">两端只连接蜂群收容子网，由该子网的存储总线访问蜂群仓。不要把它接到主网或备用大库。<br><br>转运器方向以转运器为准；红石输出方向以各自红石 I/O 为准，选择实际通向对应 ME-IO 的那一面。示意模型的位置不代表真实接线面。</p><button class="related-button" data-jump="nanite-transposer">配置硬盘箱 / 两端连接方向 →</button></section>';}
function refreshGuide(m){var old=$('inspector-content').querySelector('.io-guide');if(old)old.outerHTML=ioGuide(m);$('inspector-content').querySelectorAll('[data-jump]').forEach(function(b){b.onclick=function(){select(b.dataset.jump);};});}
function renderInspector(){var m=scene.modules.find(function(v){return v.id===scene.selected;}),v=data(m);$('inspector-content').innerHTML='<div class="module-summary"><span class="summary-icon">'+esc(m.icon||({assembler:'▤',field:'◎',generator:'◈',gate:'◇',node:'▣'})[m.kind])+'</span><h3>'+esc(m.title)+'</h3><p>'+esc(m.type||({assembler:'OBSERVATION ARRAY',field:'CONTAINMENT FIELD',generator:'ENTANGLEMENT GENERATOR',gate:'MAXWELL GATE',node:'TRANSFER NODE'})[m.kind])+'</p><span id="module-state" class="module-state">'+(m.role?'未填写':m.kind==='peripheral'?'转运器关联设备':'主体结构')+'</span></div>'+(m.role?'':ioGuide(m))+'<div class="properties"><div class="properties-title">'+(m.role?'地址绑定':'接入方式')+'</div>'+(m.role?addressField('设备组件地址','address',v.address)+(m.kind==='node'?addressField('暂停控制 · 红石组件','redstone',v.redstone)+addressField('独立韦门 · 可空，使用组韦门','gate',v.gate):'')+directionFields(m,v)+(m.kind==='node'?'<div class="field"><label for="field-group">所属设备组</label><select id="field-group">'+Array.from({length:16},function(_,i){return'<option value="'+(i+1)+'" '+((v.group||1)===i+1?'selected':'')+'>设备组 '+String(i+1).padStart(2,'0')+'</option>';}).join('')+'</select></div>':'')+'<div id="validation-state" class="validation-state">草稿允许留空，填写时自动保存。</div>':'<p class="section-note">'+esc(m.note||'观测阵列提供 16 个传送节点接入口。V2 通过节点地址配置，主体没有独立地址字段。')+'</p><button id="related-node" class="related-button">'+(m.related?'配置蜂群硬盘转运器':'配置传送节点 01')+' →</button>')+'</div>'+(m.role?ioGuide(m):'')+'<div class="module-metadata"><div class="properties-title">'+(m.kind==='peripheral'?'外设信息':'模型信息')+'</div><div class="metadata-row"><span>显示方式</span><b>'+(m.kind==='peripheral'?'放大方块示意':'官方主体结构')+'</b></div><div class="metadata-row"><span>结构方块</span><b>'+scene.meshes[m.key].blocks.toLocaleString()+'</b></div><div class="metadata-row"><span>转运方案</span><b>ME-IO</b></div>'+(m.role?'<div class="metadata-row role"><span>V2 字段</span><code>'+esc(m.role)+'</code></div>':'')+'</div><p class="section-note">'+(m.kind==='peripheral'?'外设位置为便于点选的配置示意；接线方向以游戏内实际设备为准。':'模型间距和节点位置用于界面展示。实际搭建与端口方向以游戏内机器为准。')+'</p>';$('inspector-content').querySelectorAll('[data-clear]').forEach(function(button){button.onclick=function(){var input=$('field-'+button.dataset.clear);input.value='';input.focus();input.dispatchEvent(new Event('input',{bubbles:true}));};});$('inspector-content').querySelectorAll('[data-field]').forEach(function(input){input.oninput=function(){var item=draft.modules[m.id]||(draft.modules[m.id]={});item[input.dataset.field]=input.value;validateInputs(m);refreshGuide(m);save();};});$('inspector-content').querySelectorAll('[data-side]').forEach(function(b){b.onclick=function(){var item=draft.modules[m.id]||(draft.modules[m.id]={}),key=b.dataset.sideKey;item[key]=Number(b.dataset.side);$('inspector-content').querySelectorAll('[data-side-key="'+key+'"]').forEach(function(x){x.classList.toggle('active',x===b);});validateInputs(m);refreshGuide(m);save();};});var group=$('field-group');if(group)group.onchange=function(){var item=draft.modules[m.id]||(draft.modules[m.id]={});item.group=Number(group.value);save();};var related=$('related-node');if(related)related.onclick=function(){select(m.related||'node-1');};$('inspector-content').querySelectorAll('[data-jump]').forEach(function(b){b.onclick=function(){select(b.dataset.jump);};});validateInputs(m);}
function validateInputs(m){if(!m.role)return;var v=data(m),has=false;['address','redstone'].forEach(function(key){var input=$('field-'+key);if(!input)return;var value=v[key]||'',bad=!!value&&!uuid.test(value),hint=$('inspector-content').querySelector('[data-hint="'+key+'"]');has=has||!!value;input.classList.toggle('invalid',bad);hint.classList.toggle('error',bad);hint.textContent=bad?'已保留草稿；完整地址应为 8-4-4-4-12 格式。':value?'地址格式正确 · 点击顶部「应用绑定」检测连接':'支持 Ctrl + V，可先填一部分，稍后继续。';});var done=complete(m);$('module-state').className='module-state'+(done?' filled':'');$('module-state').textContent=done?'地址完整':has?'草稿':'未填写';$('validation-state').className='validation-state'+(done?' valid':'');$('validation-state').textContent=sideIssues(m)?'方向有冲突：同一转运器的不同容器必须选择不同方向。草稿仍已保留。':done?'✓ 格式完整；请点击顶部「应用绑定」，由 OC 校验设备连接。':'草稿允许留空，填写时自动保存。';}
function select(id){scene.focus(id,scene.isolate);renderTree();renderInspector();document.querySelector('.inspector').scrollTop=0;$('status-selection').textContent=scene.modules.find(function(m){return m.id===id;}).title;$('view-title').textContent=scene.isolate?'单模块视图':'整体结构';}
function signalLinks(s){var svg=$('signal-links'),w=s.canvas.clientWidth,h=s.canvas.clientHeight;svg.setAttribute('viewBox','0 0 '+w+' '+h);var html='<defs><marker id="arrow-A" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6" fill="#2e77ee"/></marker><marker id="arrow-B" markerWidth="6" markerHeight="6" refX="5" refY="3" orient="auto"><path d="M0,0 L6,3 L0,6" fill="#9462d6"/></marker></defs>';if($('show-labels').checked)[['A','load-redstone','load-io','#2e77ee'],['B','return-redstone','return-io','#9462d6']].forEach(function(pair){var a=s.visibleModules.find(function(m){return m.id===pair[1];}),b=s.visibleModules.find(function(m){return m.id===pair[2];});if(!a||!b||s.layer<Math.max(a.center[1],b.center[1])-1)return;var p=s.project(a.center),q=s.project(b.center),dx=q.x-p.x,dy=q.y-p.y,n=Math.sqrt(dx*dx+dy*dy)||1,cut=Math.min(12,n*.25);html+='<path d="M'+(p.x+dx/n*cut)+','+(p.y+dy/n*cut)+' L'+(q.x-dx/n*cut)+','+(q.y-dy/n*cut)+'" stroke="'+pair[3]+'" stroke-width="2.5" stroke-dasharray="5 4" marker-end="url(#arrow-'+pair[0]+')" fill="none"/>';});svg.innerHTML=html;}
function labels(s){signalLinks(s);var show=$('show-labels').checked,visible=s.visibleModules;var html='';if(show)visible.forEach(function(m){if(m.kind==='node'&&m.id!==s.selected&&['node-1','node-5','node-9','node-13'].indexOf(m.id)<0)return;if(m.kind==='peripheral'&&!m.channel&&m.id!==s.selected&&['main-me','fluid-transposer','nanite-transposer'].indexOf(m.id)<0)return;var p=s.project(m.kind==='node'?m.marker:[m.center[0],m.p[1]+m.size[1]+4,m.center[2]]);if(p.x<0||p.y<0||p.x>s.canvas.clientWidth||p.y>s.canvas.clientHeight)return;html+='<button data-label="'+m.id+'" class="device-label '+(m.kind==='node'?'node ':'')+(m.id===s.selected||m.pair===s.selected?'selected ':'')+(m.channel?'channel-'+m.channel:'')+'" style="left:'+p.x.toFixed(1)+'px;top:'+p.y.toFixed(1)+'px"><i></i>'+esc(m.label||m.title)+'</button>';});$('labels').innerHTML=html;$('labels').querySelectorAll('[data-label]').forEach(function(b){b.onclick=function(){select(b.dataset.label);};});$('status-module-count').textContent=visible.length;$('renderer-badge').textContent=s.mode+' · '+(s.fullNodes?'完整节点':'节点标记');var origin=[35,39],vectors=[[1,0,0,'X','#d66c60'],[0,1,0,'Y','#59a58a'],[0,0,1,'Z','#6b91d1']];$('axes').innerHTML=vectors.map(function(v){var x=origin[0]+(v[0]*s.right[0]+v[1]*s.right[1]+v[2]*s.right[2])*23,y=origin[1]-(v[0]*s.up[0]+v[1]*s.up[1]+v[2]*s.up[2])*23;return'<line x1="35" y1="39" x2="'+x+'" y2="'+y+'" stroke="'+v[4]+'" stroke-width="2"/><text x="'+(x+4)+'" y="'+(y+3)+'" fill="'+v[4]+'" font-size="10">'+v[3]+'</text>';}).join('');}
scene=new BECScene($('scene'),BEC_DATA,select,labels);refreshStatus();renderInspector();$('tree-search').oninput=renderTree;function mode(isolate){scene.isolate=isolate;if(isolate)scene.focus(scene.selected,true);else scene.reset();$('whole-button').classList.toggle('active',!isolate);$('isolate-button').classList.toggle('active',isolate);$('view-title').textContent=isolate?'单模块视图':'整体结构';}
$('whole-button').onclick=function(){mode(false);};$('isolate-button').onclick=function(){mode(true);};$('reset-button').onclick=function(){mode(false);setLayer(49);toast('已恢复默认视角');};$('fit-button').onclick=function(){if(scene.isolate)scene.focus(scene.selected,true);else scene.reset();};$('zoom-in').onclick=function(){scene.camera.distance=Math.max(18,scene.camera.distance*.82);scene.request();};$('zoom-out').onclick=function(){scene.camera.distance=Math.min(520,scene.camera.distance/.82);scene.request();};document.querySelectorAll('[data-view]').forEach(function(b){b.onclick=function(){document.querySelectorAll('[data-view]').forEach(function(x){x.classList.toggle('active',x===b);});var view=b.dataset.view;scene.camera.yaw=view==='front'?Math.PI:view==='top'?-Math.PI/2:-.85;scene.camera.pitch=view==='top'?1.48:view==='front'?0:.62;scene.request();};});function setLayer(n){n=Math.max(-15,Math.min(49,Number(n)));scene.layer=n;$('layer-slider').value=n;$('layer-value').textContent=n===49?'全部层':'Y ≤ '+n;$('all-layers').classList.toggle('active',n===49);scene.request();}$('layer-slider').oninput=function(){setLayer(this.value);};$('layer-down').onclick=function(){setLayer(scene.layer-1);};$('layer-up').onclick=function(){setLayer(scene.layer+1);};$('all-layers').onclick=function(){setLayer(49);};[['show-peripherals','showPeripherals'],['show-nodes','showNodes'],['full-nodes','fullNodes'],['only-missing','onlyMissing']].forEach(function(pair){$(pair[0]).onchange=function(){scene[pair[1]]=this.checked;scene.request();};});$('show-labels').onchange=function(){scene.request();};$('dismiss-callout').onclick=function(){$('model-callout').hidden=true;};$('source-button').onclick=function(){if($('sources-dialog').showModal)$('sources-dialog').showModal();else $('sources-dialog').setAttribute('open','');};$('sources-close').onclick=function(){$('sources-dialog').close();};$('export-btn').onclick=function(){flush();var a=document.createElement('a'),url=URL.createObjectURL(new Blob([JSON.stringify(draft,null,2)],{type:'application/json'}));a.href=url;a.download='bec-structure-draft.json';a.click();setTimeout(function(){URL.revokeObjectURL(url);},3000);toast('已导出浏览器草稿，尚未写入 OC');};$('import-btn').onclick=function(){$('import-file').click();};$('import-file').onchange=function(){var file=this.files[0];if(!file)return;if(file.size>131072){toast('草稿文件超过 128 KiB');return;}var reader=new FileReader();reader.onload=function(){try{draft=safeDraft(JSON.parse(reader.result));flush();renderInspector();toast('已导入并保存草稿');}catch(e){toast('导入失败：'+e.message);}};reader.readAsText(file);this.value='';};window.addEventListener('pagehide',flush);document.addEventListener('keydown',function(e){if(e.key==='/'&&!/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)){e.preventDefault();$('tree-search').focus();}});window.BEC_APP={scene:scene,select:select,getDraft:function(){return JSON.parse(JSON.stringify(draft));},flush:flush,setLayer:setLayer,importDraft:function(v){draft=safeDraft(v);flush();renderInspector();}};})();</script><script>(function(){'use strict';var open=null;function close(){if(!open)return;open.menu.remove();open.button.setAttribute('aria-expanded','false');open=null;}
function enhance(select){if(select.dataset.ochdSelect)return;select.dataset.ochdSelect='1';select.classList.add('ochd-native-select');select.tabIndex=-1;var button=document.createElement('button');button.type='button';button.className='ochd-select';button.setAttribute('role','combobox');button.setAttribute('aria-haspopup','listbox');button.setAttribute('aria-expanded','false');var label=select.closest('label')||document.querySelector('label[for="'+select.id+'"]');button.setAttribute('aria-label',label?label.textContent.trim():'选择配置');select.parentNode.insertBefore(button,select.nextSibling);function refresh(){var option=select.options[select.selectedIndex],text=option?option.textContent:'请选择';if(button.textContent!==text)button.textContent=text;button.disabled=select.disabled;}
select._ochdRefresh=refresh;select.addEventListener('change',refresh);refresh();function show(){close();var menu=document.createElement('div');menu.className='ochd-select-menu';menu.setAttribute('role','listbox');var chosen=Math.max(0,select.selectedIndex);function highlight(index){chosen=Math.max(0,Math.min(select.options.length-1,index));Array.from(menu.children).forEach(function(row,i){row.classList.toggle('highlight',i===chosen);});if(menu.children[chosen])menu.children[chosen].scrollIntoView({block:'nearest'});}
function choose(index){if(select.options[index].disabled)return;select.selectedIndex=index;refresh();close();button.focus();select.dispatchEvent(new Event('change',{bubbles:true}));}
Array.from(select.options).forEach(function(option,index){var row=document.createElement('button');row.type='button';row.className='ochd-select-option';row.textContent=option.textContent;row.setAttribute('role','option');row.setAttribute('aria-selected',String(index===select.selectedIndex));row.disabled=option.disabled;row.onclick=function(){choose(index);};menu.appendChild(row);});document.body.appendChild(menu);var r=button.getBoundingClientRect(),height=Math.min(230,menu.scrollHeight);menu.style.left=Math.min(innerWidth-r.width-8,r.left)+'px';menu.style.width=r.width+'px';menu.style.top=(r.bottom+height>innerHeight-8?Math.max(8,r.top-height-4):r.bottom+4)+'px';button.setAttribute('aria-expanded','true');open={menu:menu,button:button,select:select,highlight:highlight,choose:choose,index:function(){return chosen;}};highlight(chosen);}
button.onclick=function(){if(open&&open.button===button)close();else show();};button.onkeydown=function(e){if(e.key==='Escape'){close();return;}if(e.key==='Tab'){close();return;}if(['ArrowDown','ArrowUp','Home','End','Enter',' '].indexOf(e.key)<0)return;e.preventDefault();var wasOpen=open&&open.button===button;if(!wasOpen)show();if(e.key==='ArrowDown')open.highlight(open.index()+1);else if(e.key==='ArrowUp')open.highlight(open.index()-1);else if(e.key==='Home')open.highlight(0);else if(e.key==='End')open.highlight(select.options.length-1);else if(wasOpen)open.choose(open.index());};}
function refresh(){if(open&&!open.select.isConnected)close();document.querySelectorAll('select').forEach(function(select){enhance(select);select._ochdRefresh();});}
document.addEventListener('pointerdown',function(e){if(open&&!open.menu.contains(e.target)&&e.target!==open.button)close();});document.addEventListener('scroll',function(e){if(open&&!open.menu.contains(e.target))close();},true);window.addEventListener('resize',close);new MutationObserver(refresh).observe(document.body,{childList:true,subtree:true});window.BEC_REFRESH_SELECTS=refresh;refresh();})();</script><script>(function(){'use strict';var $=function(id){return document.getElementById(id);},app=window.BEC_APP,last=null,online=false,seenAt=0,receiving=false,queue={},inflight=false,waiting=null,failed=false,group=1,switching=null,saveOp=null,actPending=null,actMessage=null,picking=null,pickWait=false,pickSeq=0,patPending=false;var requests={},seq=0,actTok=null,cacheTok=null;var order=['detect','nanites','gate','supply','convert','produce','finish'],titles={idle:'等待订单',detect:'读取配方',nanites:'蜂群检查',gate:'韦门确认',supply:'原液备料',convert:'凝聚物转换',produce:'配方运行',finish:'批次收尾',fault:'保护暂停'};function list(v){return Array.isArray(v)?v:[];}
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];});}
function time(n){n=Math.max(0,Number(n)||0);return n<60?n.toFixed(1)+'s':Math.floor(n/60)+'m '+(n%60).toFixed(1)+'s';}
function status(s,bad){$('save-status').textContent=s;$('save-status').classList.toggle('offline-alert',!!bad);}
function saving(){return inflight||!!waiting||!!Object.keys(queue).length;}
function showAction(message,bad){actMessage={text:message,bad:!!bad};buttons();}
function buttons(){var patternBusy=last&&last.patterns&&last.patterns.status==='running';var running=last&&last.mode==='running',reason=!online?'OC 未连接，暂不能启动。':running?'自动化运行中。':patternBusy?'样板处理中，请在样板处理窗口等待完成或停止。':saving()?'正在保存草稿，请稍候。':!last.configured?'草稿已保存还不等于绑定已应用。请先点击「应用绑定」，校验通过后再启动。':'绑定已应用，可以启动；修改地址后需重新应用绑定。';var hint=$('action-feedback');hint.textContent=actPending?({'apply_bindings':'正在校验并应用绑定…',start:'正在启动自动化…',pause:'正在暂停自动化…'}[actPending]):actMessage?actMessage.text:reason;hint.classList.toggle('action-error',!!(actMessage&&actMessage.bad&&!actPending));hint.setAttribute('role',actMessage&&actMessage.bad?'alert':'status');$('start-run').textContent=!online?'状态待确认':running?'运行中':'启动自动化';$('start-run').disabled=!online||running||!!actPending||patternBusy||saving();$('start-run').title=reason;$('apply-config').disabled=!online||running||!!actPending||patternBusy||saving();$('stop-run').disabled=!online||!running||!!actPending;}
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
document.querySelector('.top-actions').innerHTML='<span id="save-status" class="save-status">等待 OC 连接</span><button class="button quiet" id="patterns-open">样板处理</button><button class="button quiet" id="global-settings">公共设置</button><button class="button quiet" id="apply-config">应用绑定</button><button class="button primary run-button" id="start-run">启动自动化</button><button class="button quiet stop-button" id="stop-run">暂停</button>';var feedback=document.createElement('div');feedback.id='action-feedback';feedback.className='action-feedback';feedback.textContent='等待 OC 连接…';feedback.setAttribute('aria-live','polite');document.body.appendChild(feedback);var tabs=document.createElement('nav');tabs.className='runtime-tabs';tabs.innerHTML='<button class="active" data-tab="structure">结构 / 绑定</button><button data-tab="flow">运行流程</button><button data-tab="cache">缓存管理</button>';document.querySelector('.topbar').insertBefore(tabs,document.querySelector('.top-actions'));var cacheWait=false,cacheWaiting=null,cacheMessage='',cacheStamp='',cachePanel=document.createElement('section');cachePanel.id='cache-panel';cachePanel.innerHTML='<h1>缓存管理</h1><p>只补已登记配方流体，生产优先。单项留空用默认值，0 停补；按转换批量向上取整，库存可略超目标。</p><div class="cache-actions"><label>默认库存目标（mB） <input id="cache-default" inputmode="numeric" maxlength="10"></label><button id="cache-save-default" class="button">保存默认值</button><button id="cache-enable" class="button primary">启用自动补库</button><button id="cache-disable" class="button">停止补库</button><button id="cache-refresh" class="button">刷新库存</button></div><p id="cache-status" role="status"></p><p id="cache-feedback" role="status"></p><div id="cache-rows"></div><div id="cache-nav" class="cache-actions"><button id="cache-prev" class="button">上一页</button><span id="cache-page"></span><button id="cache-next" class="button">下一页</button></div><pre id="cache-log"></pre>';document.body.appendChild(cachePanel);function cacheAction(mode,name,value,page){if(cacheWait||!last||!last.cache)return;cacheWait=true;cacheWaiting=last.cache.revision;cacheMessage='正在提交…';cacheView();var args={mode:mode,name:name,value:value,page:page,revision:last.cache.revision},request=send('cache',args);cacheTok=args._token;request.then(function(r){cacheWait=false;cacheMessage=r.message||'已确认，等待库存更新';cacheView();}).catch(function(e){cacheWait=false;cacheMessage='未执行：'+e.message;cacheView();});}
function cacheView(){var k=last&&last.cache;if(!k)return;$('cache-status').textContent=(!online?'离线，显示最后状态 · ':last.transportBusy?'OC正在读取，显示上次机器状态 · ':'')+(k.enabled?'自动补库已启用':'自动补库未启用')+' · '+(last.mode==='running'?'自动化运行中':'启动自动化后开始补库')+' · '+(k.busy?'设备组 '+k.group+' 补库中 · ':'')+k.message;$('cache-feedback').textContent=cacheMessage;$('cache-log').textContent=list(k.logs).join('\n');if(cacheWaiting!==k.revision&&document.activeElement!==$('cache-default'))$('cache-default').value=k.target;var stamp=JSON.stringify([group,k.page,k.rows]);if(stamp!==cacheStamp&&!document.querySelector('#cache-rows input:focus')){cacheStamp=stamp;$('cache-rows').innerHTML=list(k.rows).map(function(r,i){return'<div class="cache-row"><div><strong>'+esc(r.label||r.name.replace(/^entangled_/,''))+'</strong><small>'+esc(r.name)+'</small></div><span>'+r.stock+' / '+r.target+' mB</span><input data-cache-index="'+i+'" inputmode="numeric" maxlength="10" placeholder="默认 '+k.target+'" aria-label="'+esc(r.name)+' 单项目标" value="'+(r.override==null?'':r.override)+'"><button class="button" data-cache-save="'+i+'">保存</button></div>';}).join('')||'<p>尚无已登记配方；请先通过样板处理登记需求，再刷新。</p>';$('cache-rows').querySelectorAll('[data-cache-save]').forEach(function(b){b.onclick=function(){var i=Number(b.dataset.cacheSave);cacheAction('save',list(last.cache.rows)[i].name,$('cache-rows').querySelector('[data-cache-index="'+i+'"]').value);};});}
$('cache-page').textContent=(k.page+1)+' / '+Math.max(1,Math.ceil(k.total/8));['cache-save-default','cache-enable','cache-disable','cache-refresh'].forEach(function(id){$(id).disabled=!online||cacheWait;});$('cache-prev').disabled=!online||cacheWait||k.page===0;$('cache-next').disabled=!online||cacheWait||(k.page+1)*8>=k.total;$('cache-enable').disabled=!online||cacheWait||!!k.blocked||k.enabled;}
$('cache-save-default').onclick=function(){cacheAction('save','default',$('cache-default').value);};$('cache-enable').onclick=function(){cacheAction('enable');};$('cache-disable').onclick=function(){cacheAction('disable');};$('cache-refresh').onclick=function(){cacheAction('refresh',null,null,last&&last.cache&&last.cache.page);};$('cache-prev').onclick=function(){cacheAction('refresh',null,null,last.cache.page-1);};$('cache-next').onclick=function(){cacheAction('refresh',null,null,last.cache.page+1);};var flowPanel=document.createElement('section');flowPanel.className='flow-panel';flowPanel.id='flow-panel';flowPanel.innerHTML='<div class="flow-title"><div><h2>自动化流程 <span id="flow-current">等待 OC</span></h2><p id="flow-stage-time">当前步骤 —</p></div><div><div class="elapsed" id="flow-elapsed">0.0s</div><small>当前 / 最近批次总耗时</small></div></div><div class="flow-path" id="flow-steps"></div><div class="flow-bottom"><div><h4>TRANSFER NODES / 接单控制</h4><div class="node-list" id="node-status-list"></div><div class="runtime-legend"><b>绿色：机器回读运行中</b> · <em>金色：当前步骤使用的外设</em><br>外设阶段占用不等同于硬件正在搬运</div></div><div><h4>EXECUTION / 阶段时间线</h4><div id="runtime-log" class="runtime-log" style="white-space:pre-wrap"></div></div></div>';document.querySelector('.main').appendChild(flowPanel);var notice=document.createElement('div');notice.id='runtime-notice';notice.className='runtime-notice';notice.textContent='等待 OC 数据，网页预览不控制机器。';document.querySelector('.main').appendChild(notice);var patternsDialog=document.createElement('dialog');patternsDialog.id='patterns-dialog';patternsDialog.className='runtime-settings';patternsDialog.innerHTML='<h2>样板处理</h2><p>将原加工样板的副本放入独立工坊 ME 接口。预览只读；处理一次会去除凝聚物输入并保存配方需求。请先暂停生产和纠缠器。</p><p id="patterns-target"></p><div id="patterns-status" role="status" aria-live="polite"></div><pre id="patterns-log"></pre><footer><button id="patterns-preview" class="button">只读预览</button><button id="patterns-run" class="button primary">处理一次</button><button id="patterns-stop" class="button">停止处理</button><button id="patterns-close" class="button">关闭</button></footer>';document.body.appendChild(patternsDialog);$('patterns-open').onclick=function(){$('patterns-dialog').showModal();renderPatterns();};$('patterns-close').onclick=function(){$('patterns-dialog').close();};$('patterns-preview').onclick=function(){patternAction('preview');};$('patterns-run').onclick=function(){patternAction('run');};$('patterns-stop').onclick=function(){patternAction('stop');};var pickerDialog=document.createElement('dialog');pickerDialog.id='component-picker';pickerDialog.className='runtime-settings';pickerDialog.innerHTML='<h2 id="picker-title">从 OC 选择设备</h2><p>只读取组件。点击候选地址填入草稿，不启动机器。</p><p>同类机器位置识别：暂停自动化后，仅断开目标适配器的 OC 信号分支，扫描一次；接回原线再「重新扫描」。新增/重新接入项就是候选。不要拆机器或适配器，也不要断整条共用主线。若出现多项新增，逐项确认，不按 UUID 排列猜位置。</p><div id="picker-status"></div><div id="picker-results"></div><footer><button id="picker-prev" class="button">上一页</button><button id="picker-next" class="button">下一页</button><button id="picker-refresh" class="button">重新扫描</button><button id="picker-close" class="button primary">关闭</button></footer>';document.body.appendChild(pickerDialog);$('picker-refresh').onclick=function(){scanPicker();};$('picker-close').onclick=closePicker;var issuesDialog=document.createElement('dialog');issuesDialog.id='binding-issues';issuesDialog.className='runtime-settings binding-issues';issuesDialog.innerHTML='<h2>绑定检查 / 当前设备组</h2><p>点击下列项目跳转填写。这里只检查填写内容；通过后还会由 OC 校验设备是否在线、方法和机器状态。</p><div id="binding-issues-list"></div><p>空传送节点会跳过。额外纠缠器、高速供液口、样板工坊可留空；自动换蜂的三项地址须全部填写或全部留空。每个节点须有独立韦门或使用本组公共韦门。</p><footer><button id="close-issues" class="button primary">返回修改</button></footer>';document.body.appendChild(issuesDialog);$('close-issues').onclick=function(){$('binding-issues').close();};var dialog=document.createElement('dialog');dialog.id='runtime-settings';dialog.className='runtime-settings';dialog.innerHTML='<h2>公共配置</h2><p>填写后自动暂存。应用绑定通过设备校验后，才能启动。</p><label>当前模型对应 <select id="group-select"></select></label><div id="extra-fields"></div><footer><button id="close-settings" class="button primary">完成</button></footer>';document.body.appendChild(dialog);document.querySelectorAll('[data-tab]').forEach(function(b){b.onclick=function(){document.querySelectorAll('[data-tab]').forEach(function(x){x.classList.toggle('active',x===b);});document.body.classList.toggle('flow-full',b.dataset.tab==='flow');document.body.classList.toggle('cache-view',b.dataset.tab==='cache');if(b.dataset.tab==='cache')cacheView();app.scene.request();};});document.querySelector('.inspector-bottom p').textContent='草稿由 OC 自动保存，支持 Ctrl+V。应用绑定前不控制机器。';$('model-callout').querySelector('p').innerHTML='点击机器填写地址，自动暂存到 OC。<br>拖动旋转 · 滚轮缩放 · 右键平移';document.querySelector('.pill').textContent='V2 / OCHD';document.querySelector('.stage-title').innerHTML='<span class="live-dot"></span>结构与机器状态<span class="stage-sub">/ 实际回读 + 阶段标记</span>';$('save-status').onclick=function(){if(failed){failed=false;pump();}};$('apply-config').onclick=function(){action('apply_bindings');};$('start-run').onclick=function(){action('start');};$('stop-run').onclick=function(){action('pause');};$('global-settings').onclick=settings;$('close-settings').onclick=function(){$('runtime-settings').close();};$('group-select').onchange=function(){if(inflight||waiting||Object.keys(queue).length){this.value=group;return;};switching=Number(this.value);send('select_group',{group:switching}).then(function(){$('runtime-settings').close();}).catch(function(e){switching=null;$('runtime-notice').textContent=e.message;});};window.BEC_CONTROL={receive:data,values:toValues,openPicker:openPicker,issues:bindingIssues,queue:function(){return queue;}};if(window.OC&&OC.onData)OC.onData(data);else{$('runtime-notice').textContent='浏览器预览：未连接 OC，所有机器操作禁用。';$('start-run').disabled=$('stop-run').disabled=$('apply-config').disabled=true;}
setInterval(function(){flow();if(last&&Date.now()-seenAt>7000){online=false;disconnect();status('OC 数据已过期',true);buttons();cacheView();}},250);})();</script></body></html>
]=],supported={['254230:29138424']=true}},{name='lib/web_transport.lua',added=true,source=[=[-- Heartbeats while large OC reads run. Receipt is not operation completion.
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
 function T.pulse(force)
  if polling then return end;polling=true
  for i=1,8 do local e={event.pull(0)};if not e[1]then break end;receive(e)end
  local now=clock.uptime()
  if force or now>=T.next then
   local data=T.pending or T.last
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
]=],supported={['0:1']=true}},{name='lib/config.lua',added=false,source=[=[local c=require('component')
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
   M.pulse();local values=table.pack(native[name](...));M.pulse();return table.unpack(values,1,values.n)
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
]=],supported={['7343:3682171505']=true}},{name='lib/engine.lua',added=false,source=[=[local c=require('component')
local clock=require('computer')
return function(cfg,C,Bridge,monitor)
 local c=C.component and C.component(c)or c
 local E={tasks={},groupOwner={},fluidOwner=nil,logs={},monitor=monitor,roundRobin={},pulse=C.pulse}
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
]=],supported={['11288:931933717']=true}},{name='lib/bridge.lua',added=false,source=[=[local c=require('component')
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
]=],supported={['16213:3509786521']=true}},{name='runtime/controller.lua',added=false,source=[=[local c = require("component") local ser = require("serialization") local computer = require("computer") local fs = require("filesystem")
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
local demand=call(NODE,"getRequiredTier");local family=type(demand)=="table"and demand.name or nil
local needed=type(demand)=="table" and demand.tier or demand
local supplied=call(NODE,"getProvidedTier")
if type(needed)=="number" and (needed~=lastNaniteTier or family~=lastNaniteFamily or type(supplied)~="table" or supplied.tier<needed) then
pause(15);waitUntil(10,function() local s=call(NODE,"getState");return s=="paused-immediate" or s=="nanite-tier-too-low" end)
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
]=],supported={['37299:3439879977']=true}}}

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
local self='/home/bec_connection_update.lua'
do
 local downloaded=read(self)
 local payload=downloaded and downloaded:match('^%-%- BEC_V2_CONNECTION_UPDATE_1\nlocal SELF_SIGNATURE=[^\n]*\n(.*)$')
 if payload and signature(payload)==SELF_SIGNATURE then
  local ok,removed,reason=pcall(fs.remove,self)
  if not fs.exists(self)then print('已释放临时安装包；程序备份和运行记录保留。')
  else print('临时包保留，继续检查可用空间：'..tostring(ok and reason or removed))end
 end
 downloaded=nil;payload=nil;collectgarbage('collect')
end
if identical then print('连接与换蜂恢复修复已安装，无需重复更新。');return end
local disk=assert(fs.get(root));assert(disk.spaceTotal()-disk.spaceUsed()>=bytes+524288,'磁盘空间不足：更新后需保留512KiB')
local n=1
while true do
 local conflict=false;for _,row in ipairs(rows)do for _,suffix in ipairs({'.before-connection-','.connection-new-','.connection-failed-'})do if fs.exists(root..row.name..suffix..n)then conflict=true end end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(rows)do
 local temp=root..row.name..'.connection-new-'..n;local f=assert(io.open(temp,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(temp)==row.source,'临时文件回读失败，旧程序未改')
end
for i,row in ipairs(rows)do assert(read(root..row.name)==old[i],'更新期间程序改变，未替换')end
local backed,installed={},{}
local ok,reason=pcall(function()
 for i,row in ipairs(rows)do local target=root..row.name
  if old[i]then assert(fs.rename(target,target..'.before-connection-'..n),'备份失败');backed[i]=true end
  assert(fs.rename(target..'.connection-new-'..n,target),'替换失败');installed[i]=true
  assert(read(target)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#rows,1,-1 do local target=root..rows[i].name
  if installed[i]then assert(fs.rename(target,target..'.connection-failed-'..n),'移出失败程序失败，保留备份')end
  if backed[i]then assert(fs.rename(target..'.before-connection-'..n,target),'恢复失败，保留备份')end
 end
 error('更新失败，旧程序已恢复：'..tostring(reason))
end
print('连接心跳与换蜂后恢复修复已安装；请重新打开网页。')
print('已有地址、草稿、配置、配方和运行记录保留；未控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
