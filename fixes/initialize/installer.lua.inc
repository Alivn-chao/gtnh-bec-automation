local fs=require('filesystem');local c=require('component')
local function read(p)local f=io.open(p,'r');if not f then return end;local text=f:read('*a');f:close();return text end
local function replace(s,from,to)local a,b=s:find(from,1,true);assert(a and not s:find(from,b+1,true),'入口缺失或重复: '..from);return s:sub(1,a-1)..to..s:sub(b+1)end
local autoPath='/home/bec_auto.lua';local uiPath='/home/bec_ui.lua';local cachePath='/home/bec_cache.lua'
local ui=assert(read(uiPath))
assert(ui:find('BEC_V1_UI_CACHE_RESET_V3',1,true),'需要缓存重置V3面板')
if not assert(read(autoPath)):find('BEC_V1_CPU_WAIT_V1:',1,true) or not ui:find('BEC_V1_CPU_WAIT_UI_V1:',1,true)then
 local function installCPU()
CPU_INSTALL
 end
 installCPU();ui=assert(read(uiPath))
end
local entries={}
local function add(path,old,new)
 if old==new then return end
 assert(load(new,'@'..path,'t',_ENV),'程序语法检查失败: '..path)
 entries[#entries+1]={path=path,old=old,new=new}
end
local seq=[====[SEQUENTIAL_BODY]====]
local function updateSupply(path,cache)
 local old=read(path);if not old then return end
 if old:find('BEC_V1_SEQUENTIAL_CPU_WAIT_V1:',1,true)then return end
 local text=old:gsub('\r\n','\n')
 local a,b=text:find('if status and job.state=="submitted" then',1,true)
 assert(a and not text:find('if status and job.state=="submitted" then',b+1,true),'顺序供液入口缺失或重复: '..path)
 local z,e=text:find('assert(computer.uptime()<deadline,"持续收料超时，保留子网已搬入原液")',b+1,true);assert(z,'顺序供液结束入口缺失')
 local body=seq:gsub('INLET_CREDIT',cache and 'bufferedInlet()'or 'tanks(4,raw)')
 body=body:gsub('PRIORITY_CHECK',cache and 'if productionWaiting()then return handoff()end'or '')
 if not cache then body='local priority=false\n'..body end
 text=text:sub(1,a-1)..body..text:sub(e+1)
 if cache then
  text=replace(text,'assert(job.state=="done","缓存申请尚未完成，不能交回生产")','assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"缓存申请尚未完成，不能交回生产")')
  text=replace(text,'assert(job.state=="done","缓存申请仍未确认")','assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"缓存申请仍未确认")')
  text=replace(text,'if job.state~="done" then save("craft-paused")','if job.state~="done" and not(job.state=="rejected" and job.preSubmissionFailed==true) then save("craft-paused")')
 end
 add(path,old,text)
end
updateSupply(autoPath,false);updateSupply(cachePath,true)
if not ui:find('BEC_V1_UI_INITIALIZE_V1:',1,true)then
 local modified=ui:gsub('\r\n','\n')
 local a=modified:find('-- BEC_V1_UI_PRODUCTION_RESET_V1:',1,true)or modified:find('local function cacheResetWorker()',1,true)
 assert(a,'重置入口缺失');local z=assert(modified:find('local function mainUI()',a,true),'UI入口缺失')
 modified=modified:sub(1,a-1)..'-- BEC_V1_UI_INITIALIZE_V1: new live-inventory session.\nlocal function cacheResetWorker()\n'..[====[RESET_BODY]====]..'\nend\n'..modified:sub(z)
 local label=modified:find('[ Z 确认未下单 / 重置 ]',1,true)and '[ Z 确认未下单 / 重置 ]'or '[ Z 放弃缓存 / 重置 ]'
 modified=replace(modified,label,'[ Z 初始化 / 重新投料 ]')
 modified=replace(modified,'local cpuReason=record.pipeline and record.pipeline.cpuWaitSummary','local supply=record.pipeline or record.supplyWait;local cpuReason=supply and supply.cpuWaitSummary')
 modified=replace(modified,'local rows=record.pipeline.cpuWait or {}','local rows=supply.cpuWait or {}')
 add(uiPath,ui,modified)
end
if #entries==0 then print('初始化与CPU持续等待补丁已安装');return end
assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先按Q退出UI')
assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false,'先按Q关闭纠缠装置')
local n=1
while true do local busy=false;for _,e in ipairs(entries)do busy=busy or fs.exists(e.path..'.before-initialize-ui-'..n)or fs.exists(e.path..'.initialize-ui-new-'..n)end;if not busy then break end;n=n+1 end
for _,e in ipairs(entries)do
 e.backup=e.path..'.before-initialize-ui-'..n;e.temp=e.path..'.initialize-ui-new-'..n
 local f=assert(io.open(e.temp,'w'));assert(f:write(e.new));assert(f:flush());f:close();assert(read(e.temp)==e.new)
 assert(read(e.path)==e.old,'安装期间文件变化')
end
local ok,why=pcall(function()for _,e in ipairs(entries)do
 assert(fs.rename(e.path,e.backup),'文件备份失败');e.backed=true
 assert(fs.rename(e.temp,e.path),'文件替换失败');e.installed=true
 assert(read(e.path)==e.new and read(e.backup)==e.old,'文件回读失败')
end end)
if not ok then
 for i=#entries,1,-1 do local e=entries[i];if e.backed then
  if e.installed then assert(fs.rename(e.path,e.temp))end
  assert(fs.rename(e.backup,e.path));assert(read(e.path)==e.old)
 end end
 error(tostring(why)..'；本次替换已还原')
end
print('已安装：Z 初始化/重新投料；生产高速、顺序供液及缓存CPU忙时持续等待。')
print('启动 lua /home/bec_ui.lua resume，然后按Z；旧记录归档，按实际库存新开供液流程。')
