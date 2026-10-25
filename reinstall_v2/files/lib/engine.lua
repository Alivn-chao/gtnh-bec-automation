local c=require('component')
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
 E.cellFeeds={}
 if not monitor then
  for group,g in ipairs(cfg.groups)do if g.cellFeed and g.cellFeed.enabled then
   E.cellFeeds[group]=assert(loadfile(C.path('lib/cell_feed.lua')))().new(cfg,group,C,E)
  end end
 end
 function E.hasPendingFeed(group)
  local feed=E.cellFeeds[group];return feed and feed.pending()or false
 end
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
  else
   if E.cellFeeds[group]then E.cellFeeds[group].finish()end
   for _,j in ipairs(t.members)do E.tasks[j].status='等待订单'end
  end
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
  for _,feed in pairs(E.cellFeeds)do feed.observe()end
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
   local feed=E.cellFeeds[group]
   local feedReady=true
   if feed then
    local disabled,leader=false,nil
    for i,n in ipairs(cfg.nodes)do if n.group==group then leader=leader or i;if E.tasks[i].disabled or E.tasks[i].fault then disabled=true end end end
    feedReady=false
    if not disabled then
     local ok,result=pcall(feed.step)
     if ok then
      feedReady=result
      if not result then for i,n in ipairs(cfg.nodes)do if n.group==group then E.tasks[i].status=feed.message end end end
     else
      E.log(leader,'原料盘保护暂停：'..tostring(result));local t=E.tasks[leader];t.fault=true;t.startedAt=t.startedAt or clock.uptime();t.endedAt=clock.uptime();E.phase(leader,'fault');E.pauseNode(leader)
     end
    end
   end
   if feedReady then
   local saved=C.read(cohortPath(group));local unfinished=saved and saved.stage~='stopped'
   -- Reopen only after the previous cohort has finished its cleanup. Never
   -- reopen on restart with an interrupted cohort awaiting manual review.
   if not unfinished and not feed then
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
      t.fixedBatch=feed and feed.plan()or nil
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
   end
  end end
 end
 return E
end
