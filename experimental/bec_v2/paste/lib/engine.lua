local c=require('component')
local clock=require('computer')
return function(cfg,C,Bridge,monitor)
 local E={tasks={},groupOwner={},fluidOwner=nil,logs={},monitor=monitor,roundRobin={}}
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
  local errors={}
  for i,t in ipairs(E.tasks)do
   t.cancel=true;t.disabled=true
   local ok,e=pcall(pause,i);if not ok then errors[#errors+1]=tostring(e)end
  end
  for _,g in ipairs(cfg.groups)do for _,a in ipairs(g.generators)do
   local ok,e=pcall(function()c.invoke(a,'setWorkAllowed',false);assert(c.invoke(a,'isWorkAllowed')==false)end)
   if not ok then errors[#errors+1]=a..': '..tostring(e)end
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
