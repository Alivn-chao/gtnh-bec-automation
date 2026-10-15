local fs=require('filesystem');local c=require('component')
local ROOT='/home/bec_v2'
local function read(path)local f=assert(io.open(path,'r'));local s=f:read('*a');f:close();return s end
local function write(path,s)local f=assert(io.open(path,'w'));assert(f:write(s));assert(f:flush());f:close();assert(read(path)==s,'Read-back failed')end
local C=assert(loadfile(ROOT..'/lib/config.lua'))()
local cfg=C.load()
local function stopped()
 for _,n in ipairs(cfg.nodes)do assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'Pause all nodes and exit V2 first')end
 for _,g in ipairs(cfg.groups)do for _,a in ipairs(g.generators)do
  assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'Stop all generators before installing')
 end end
end
stopped()
local paths={ROOT..'/lib/engine.lua',ROOT..'/main.lua',ROOT..'/lib/reports.lua',ROOT..'/report_setup.lua'}
local originals={}
for i,p in ipairs(paths)do originals[i]=fs.exists(p)and read(p)or false end
local engine,main=originals[1],originals[2]
local MARK='BEC_V2_GITHUB_REPORTS_V1'
if engine:find(MARK,1,true)then
 assert(originals[3]==REPORT_SOURCE and originals[4]==SETUP_SOURCE,'Different report module already installed')
 print('ALREADY INSTALLED: GitHub reports and bounded history');return
end
local function replace(text,old,new)
 local a,b=text:find(old,1,true);assert(a and not text:find(old,b+1,true),'V2 source mismatch; no programs changed')
 return text:sub(1,a-1)..new..text:sub(b+1)
end
engine=replace(engine,' for i in ipairs(cfg.nodes)do',
 ' -- BEC_V2_GITHUB_REPORTS_V1\n local reports\n if not monitor then\n  local ok,result=pcall(function()return assert(loadfile(C.path("lib/reports.lua")))()(cfg,C)end)\n  reports=ok and result or {status="报告初始化失败，生产日志保留",step=function()end,close=function()end,capture=function()end}\n end\n E.reports=reports\n function E.reportFault(i,reason)\n  if reports then local ok=pcall(reports.capture,i,E,reason);if not ok then reports.status="故障报告保存失败，现场日志保留" end end\n end\n for i in ipairs(cfg.nodes)do')
engine=replace(engine,"  E.release(i);E.groupOwner[group]=nil;E.roundRobin[group]=i;t.co=nil",
 '  if reports then\n   reports.historyWanted=true\n   if t.fault and not t.cancel then E.reportFault(i,E.logs[#E.logs]or "worker failure")end\n  end\n  E.release(i);E.groupOwner[group]=nil;E.roundRobin[group]=i;t.co=nil')
engine=replace(engine,'  if monitor then return {}end','  if monitor then return {}end\n  if reports then reports.close()end')
engine=replace(engine,'  if monitor then return end','  if monitor then return end\n  if reports then\n   reports.step()\n   if E.reportStatus~=reports.status then E.reportStatus=reports.status;E.log(1,reports.status)end\n  end')
main=replace(main,"if not ok then print('V2已停止：'..tostring(err))end",
 'if not ok then E.reportFault(UI.selected(),tostring(err));print("V2已停止："..tostring(err))end\nif E.reports then print(E.reports.status)end')
local modified={engine,main,REPORT_SOURCE,SETUP_SOURCE}
local sequence=1
while fs.exists(ROOT..'/lib/engine.lua.before-reports-'..sequence)or fs.exists(paths[1]..'.reports-new-'..sequence)do sequence=sequence+1 end
for i,p in ipairs(paths)do
 assert(load(modified[i],'@'..p,'t',_ENV),'Syntax check failed')
 assert(not fs.exists(p..'.before-reports-'..sequence)and not fs.exists(p..'.reports-new-'..sequence),'Backup collision')
 write(p..'.reports-new-'..sequence,modified[i])
end
stopped()
for i,p in ipairs(paths)do assert(originals[i]and read(p)==originals[i]or not originals[i]and not fs.exists(p),'Source changed during installation')end
local retired,installed={},{}
local ok,reason=pcall(function()
 for i,p in ipairs(paths)do
  if originals[i]then assert(fs.rename(p,p..'.before-reports-'..sequence));retired[i]=true end
  assert(fs.rename(p..'.reports-new-'..sequence,p));installed[i]=true
  assert(read(p)==modified[i],'Installed file read-back failed')
 end
end)
if not ok then
 for i=#paths,1,-1 do local p=paths[i]
  if installed[i]then assert(fs.rename(p,p..'.reports-failed-'..sequence))end
  if retired[i]then assert(fs.rename(p..'.before-reports-'..sequence,p))end
 end
 error('Install failed; originals restored: '..tostring(reason))
end
print('INSTALLED: V2 GitHub fault reports + bounded completed histories.')
print('One-time credential setup: lua /home/bec_v2/report_setup.lua')
print('Then start V2 normally. Existing config, recipes and journals were not changed.')
