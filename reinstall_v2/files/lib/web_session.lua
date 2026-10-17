-- HTML is a data client. Only this Lua allowlist can save bindings or run V2.
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
