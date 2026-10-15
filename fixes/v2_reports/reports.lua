-- V2 fault outbox. Network polling never sleeps or controls a machine.
local fs=require('filesystem');local ser=require('serialization');local clock=require('computer')
local c=require('component')
local M={}
local MAX=49152
local function read(path,limit)
 local f=io.open(path,'r');if not f then return end
 local s=f:read((limit or MAX)+1)or '';f:close()
 if #s>(limit or MAX)then return nil,'oversize' end
 return s
end
local function quote(s)
 return '"'..s:gsub('[%z\1-\31\\"]',function(x)
  return ({['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'})[x] or string.format('\\u%04x',x:byte())
 end)..'"'
end
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(s)
 local out={}
 for i=1,#s,3 do
  local a,b,d=s:byte(i,i+2);local n=a*65536+(b or 0)*256+(d or 0)
  out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
   ..alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
   ..(b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1)or '=')
   ..(d and alphabet:sub(n%64+1,n%64+1)or '=')
 end
 return table.concat(out)
end
local function encode(s)return(s:gsub('[^%w%-%._~]',function(x)return string.format('%%%02X',x:byte())end))end
local function scrub(s,token)
 s=tostring(s)
 if token and #token>0 then s=s:gsub(token:gsub('([^%w])','%%%1'),'[REDACTED]')end
 return s:gsub('github_pat_[%w_]+','[REDACTED]'):gsub('gh[pousr]_[%w]+','[REDACTED]')
  :gsub('[Aa]uthorization[^\r\n]*','Authorization: [REDACTED]')
end
M.base64=base64
return setmetatable(M,{__call=function(_,cfg,C)
 local R={status='未配置 GitHub 上传'}
 local dir=C.path('diagnostics');local indexPath=dir..'/index.dat'
 local credentialPath=C.path('github-upload.dat')
 local function credentials()
  local v=C.read(credentialPath)
  if not v or type(v.token)~='string' or #v.token<10 then return end
  assert(v.owner=='Alivn-chao' and v.repo=='gtnh-bec-automation','Unexpected diagnostic repository')
  return v
 end
 local state=C.read(indexPath)or {version=1,next=1,reports={},overflow=0}
 assert(state.version==1 and type(state.reports)=='table' and type(state.next)=='number','Invalid diagnostic index')
 local function save()C.write(indexPath,state)end
 local function reportPath(row)
  assert(type(row.id)=='string' and row.id:match('^[%w%-]+$'),'Invalid report id')
  return dir..'/'..row.id..'.txt'
 end
 -- Complete an interrupted report/index transaction before accepting a new fault.
 local writing=C.read(dir..'/writing.dat')
 if writing and type(writing.row)=='table'then
  local row=writing.row;local exists=false
  for _,r in ipairs(state.reports)do if r.id==row.id then exists=true end end
  if not exists then
   local text=read(reportPath(row))
   if text then
    local ok,data=pcall(ser.unserialize,text)
    row.status=ok and type(data)=='table'and data.format=='bec-v2-diagnostic-v1'and 'pending'or 'incomplete'
    state.reports[#state.reports+1]=row;save()
   end
  end
 end
 local function prune()
  local uploaded={}
  for _,r in ipairs(state.reports)do if r.status=='uploaded'then uploaded[#uploaded+1]=r end end
  table.sort(uploaded,function(a,b)return a.sequence>b.sequence end)
  local removed={}
  for i=4,#uploaded do
   local r=uploaded[i];local p=reportPath(r)
   if not fs.exists(p)or fs.remove(p)then removed[r.id]=true end
  end
  if next(removed)then
   local keep={};for _,r in ipairs(state.reports)do if not removed[r.id]then keep[#keep+1]=r end end
   state.reports=keep;save()
  end
 end
 function R.capture(index,engine,reason)
  local pending=0
  for _,r in ipairs(state.reports)do if r.status~='uploaded'then pending=pending+1 end end
  local cred=credentials();local token=cred and cred.token
  if pending>=5 then
   state.overflow=state.overflow+1;state.lastOverflow=scrub(reason,token):sub(1,512);save()
   R.status='报告队列已满：保留5份待上传报告及简短摘要';return
  end
  local group=cfg.nodes[index]and cfg.nodes[index].group
  local parts={'BEC V2 FAULT REPORT','node='..tostring(index)..' group='..tostring(group),
   'reason='..scrub(reason,token),'uptime='..tostring(clock.uptime()),'LAST KNOWN NODE ENTRIES'}
  for i,n in ipairs(cfg.nodes)do if not group or n.group==group then
   local t=engine.tasks[i]or {}
   parts[#parts+1]=ser.serialize({index=i,name=n.name,address=n.address,group=n.group,status=t.status,
    fault=t.fault,entries=t.entries,members=t.members},false):sub(1,4096)
  end end
  parts[#parts+1]='RECENT EVENTS'
  for i=math.max(1,#engine.logs-19),#engine.logs do parts[#parts+1]=scrub(engine.logs[i],token):sub(1,1024)end
  local journals={}
  for i,n in ipairs(cfg.nodes)do if not group or n.group==group then journals[#journals+1]='state/node-'..i..'/production.journal' end end
  local groups=group and {group}or {};if not group then for i in ipairs(cfg.groups)do groups[#groups+1]=i end end
  for _,g in ipairs(groups)do for _,name in ipairs({'cohort.dat','generators.dat','nanites-cell.journal','nanites.journal'})do
   journals[#journals+1]='state/group-'..g..'/'..name
  end end
  for _,p in ipairs(journals)do
   local s,err=read(C.path(p),8192)
   if s then parts[#parts+1]='JOURNAL '..p..'\n'..scrub(s,token)
   elseif err then parts[#parts+1]='JOURNAL '..p..' omitted: '..err end
  end
  local text=scrub(table.concat(parts,'\n'),token)
  if #text>MAX then text=text:sub(1,MAX-32)..'\n[REPORT TRUNCATED]\n' end
  -- ASCII-safe serialized report avoids splitting a UTF-8 codepoint at the cap.
  text=ser.serialize({format='bec-v2-diagnostic-v1',text=text},false)
  if #text>MAX then text=ser.serialize({format='bec-v2-diagnostic-v1',text='Report exceeded encoded limit',reason=scrub(reason,token):sub(1,512)},false)end
  local device=clock.address():gsub('[^%w]',''):sub(1,12)
  local id=device..'-'..tostring(state.next)..'-'..string.format('%.0f',os.time())
  local row={id=id,sequence=state.next,status='pending',owner='Alivn-chao',repo='gtnh-bec-automation',branch='main'}
  row.remote='diagnostics/v2/'..id..'.txt'
  assert(not fs.exists(reportPath(row)),'Diagnostic id already exists')
  -- Reserve sequence before writing so a crash never reuses a published path.
  state.next=state.next+1;save()
  C.write(dir..'/writing.dat',{version=1,row=row})
  local f=assert(io.open(reportPath(row),'w'));assert(f:write(text));assert(f:flush());f:close()
  assert(read(reportPath(row))==text,'Diagnostic report read-back failed')
  state.reports[#state.reports+1]=row;save();prune()
  R.status='报告已排队：'..id
  return id
 end
 local current,blockedUntil=nil,0
 local maintenance
 R.historyWanted=true
 local function close()
  if current and current.handle then pcall(current.handle.close)end
  current=nil
 end
 local function fail(message)
  R.status=message;blockedUntil=clock.uptime()+60;close()
 end
 local function start(row,stage,text,cred)
  assert(row.owner=='Alivn-chao' and row.repo=='gtnh-bec-automation' and row.branch=='main'
   and row.remote=='diagnostics/v2/'..row.id..'.txt','Unexpected upload destination')
  local path=row.remote:gsub('[^/]+',encode)
  local url='https://api.github.com/repos/'..row.owner..'/'..row.repo..'/contents/'..path
  local method,body='GET',nil
  local headers={['User-Agent']='BEC-V2-diagnostics',['Authorization']='Bearer '..cred.token,
   ['Accept']='application/vnd.github.raw+json'}
  if stage=='put'then
   method='PUT';headers.Accept='application/vnd.github+json';headers['Content-Type']='application/json'
   body='{"message":'..quote('BEC V2 fault report '..row.id)..',"branch":'..quote(row.branch)..',"content":'..quote(base64(text))..'}'
  else url=url..'?ref='..encode(row.branch)end
  local net=c.internet
  if not net or type(net.request)~='function'then return fail('报告保留：需要互联网卡')end
  local ok,h=pcall(net.request,url,body,headers,method)
  if not ok or not h then return fail('报告保留：GitHub 请求未建立')end
  current={row=row,stage=stage,text=text,cred=cred,handle=h,deadline=clock.uptime()+20,chunks={},size=0,connected=false}
 end
 local function finish(code,body)
  local job=current;close()
  if job.stage=='check' then
   if code==404 then return start(job.row,'put',job.text,job.cred)end
   if code~=200 or body~=job.text then return fail('报告保留：远程报告未确认一致，HTTP '..tostring(code))end
  elseif job.stage=='put'then
   if code~=201 then return fail('报告保留：GitHub 未确认创建，HTTP '..tostring(code))end
   return start(job.row,'verify',job.text,job.cred)
  else
   if code~=200 or body~=job.text then return fail('报告保留：上传后回读未通过，HTTP '..tostring(code))end
  end
  job.row.status='uploaded'
  job.row.url='https://github.com/'..job.row.owner..'/'..job.row.repo..'/blob/'..job.row.branch..'/'..job.row.remote
  save();R.status='报告已上传：'..job.row.url;prune()
 end
 local function networkStep()
  if current then
   if clock.uptime()>current.deadline then return fail('报告保留：GitHub 请求超时')end
   local h=current.handle
   if not current.connected then
    local connected,err=h.finishConnect();if err then return fail('报告保留：连接失败')end
    if not connected then return end
    current.connected=true;return
   end
   local part,err=h.read(4096)
   if err then return fail('报告保留：网络读取失败')end
   if part then
    current.size=current.size+#part
    if current.size>131072 then return fail('报告保留：网络响应超出限制')end
    current.chunks[#current.chunks+1]=part;return
   end
   local code=h.response()
   return finish(code,table.concat(current.chunks))
  end
  if clock.uptime()<blockedUntil then return end
  local cred=credentials();if not cred then R.status='报告保留：尚未配置 GitHub 写入凭据';blockedUntil=clock.uptime()+60;return end
  for _,row in ipairs(state.reports)do if row.status=='pending'then
   local text=read(reportPath(row));if not text then return fail('报告文件缺失或过大，保留索引等待核对')end
   start(row,'check',text,cred);return
  end end
 end
 function R.step()
  local ok=pcall(networkStep)
  if not ok then fail('报告保留：上传暂时失败，稍后重试')end
  if R.historyWanted and not maintenance then
   R.historyWanted=false;maintenance=coroutine.create(R.pruneHistory)
  end
  if maintenance then
   local success=coroutine.resume(maintenance)
   if not success or coroutine.status(maintenance)=='dead'then maintenance=nil end
   if not success then R.status='旧历史清理失败，当前记录保持不变'end
  end
 end
 function R.close()close()end
 -- Only successfully completed runtime archives are eligible for deletion.
 function R.pruneHistory()
  local jobs={}
  for i in ipairs(cfg.nodes)do
   jobs[#jobs+1]={directory=C.path('state/node-'..i),stem='production.journal.stopped-',stage='stopped'}
   jobs[#jobs+1]={directory=C.path('state/node-'..i),stem='production.journal.before-resume-',stage='stopped'}
  end
  for i in ipairs(cfg.groups)do jobs[#jobs+1]={directory=C.path('state/group-'..i),stem='nanites-cell.journal.before-run-',stage='done'}end
  for _,job in ipairs(jobs)do if fs.exists(job.directory)then
   local candidates={}
   for name in fs.list(job.directory)do
    local suffix=name:sub(#job.stem+1)
    if name:sub(1,#job.stem)==job.stem and suffix:match('^%d+$')then
     local path=job.directory..'/'..name
     if not fs.isDirectory(path)then
      local text=read(path);local ok,r=pcall(function()return text and ser.unserialize(text)end)
      local complete=ok and type(r)=='table' and r.stage==job.stage and r.pending==nil and r.plan==nil
       and r.configOwned~=true and r.naniteStage==nil and r.pipeline==nil
      for _,move in ipairs(complete and r.transfers or {})do if move.ok~=true then complete=false end end
      for _,request in ipairs(complete and r.requests or {})do if request.state~='done'then complete=false end end
      if complete then candidates[#candidates+1]={path=path,index=tonumber(suffix),time=fs.lastModified(path)}end
     end
     coroutine.yield()
    end
   end
   table.sort(candidates,function(a,b)if a.time~=b.time then return a.time>b.time end;return a.index>b.index end)
   for i=4,#candidates do
    local row=candidates[i]
    assert(fs.lastModified(row.path)==row.time,'History changed during cleanup')
    assert(fs.remove(row.path),'Completed history cleanup failed');coroutine.yield()
   end
  end end
 end
 return R
end})
