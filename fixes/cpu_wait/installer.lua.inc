local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua';local uiPath='/home/bec_ui.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local function replace(s,from,to)
 local a,b=s:find(from,1,true);assert(a and not s:find(from,b+1,true),'入口缺失或不唯一: '..from)
 return s:sub(1,a-1)..to..s:sub(b+1)
end
local original=read(path);local ui=read(uiPath)
if original:find('BEC_V1_CPU_WAIT_V1:',1,true) and ui:find('BEC_V1_CPU_WAIT_UI_V1:',1,true)then print('CPU等待补丁已安装');return end
local modified=original:gsub('\r\n','\n');local newUI=ui:gsub('\r\n','\n')
if not modified:find('BEC_V1_CPU_WAIT_V1:',1,true)then
 assert(modified:find('BEC_V1_PRODUCTION_OVERLAP_V3:',1,true),'需要生产并行V3')
 local first=' local function jobsAndRequests()'
 local a,b=modified:find(first,1,true);assert(a and not modified:find(first,b+1,true),'并行下单入口不唯一')
 local z=assert(modified:find(' while not stopping do',b+1,true),'下单结束入口缺失')
 modified=modified:sub(1,a-1)..[==[JOBS_BODY]==]..'\n'..modified:sub(z)
 modified=replace(modified,'productionGuard();jobsAndRequests();if stopping then break end',
  'productionGuard();local cpuWaiting=jobsAndRequests();if cpuWaiting then deadline=math.max(deadline,computer.uptime()+1800) end;if stopping then break end')
 modified=replace(modified,'(item.job and item.job.state~="done")',
  '(item.job and item.job.state~="done" and not(item.job.state=="rejected" and item.job.preSubmissionFailed==true))')
 modified=replace(modified,'assert(job.state=="done","原液申请尚未确认完成，禁止重复下单")',
  [=[assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"原液申请尚未确认完成，禁止重复下单")
  if job.manualSupply then
   local received=integer((old.pipeline.delivered or {})[job.raw] or 0)-integer(job.securedBefore or 0)
   local available=integer(network(MAIN)[job.raw] or 0)
   assert(received+available>=integer(job.amount),"手动补料尚未收齐：继续等待手动任务完成后再恢复，禁止自动重复下单")
  end
]=])
end
if not newUI:find('BEC_V1_CPU_WAIT_UI_V1:',1,true)then
 assert(newUI:find('BEC_V1_UI_PAUSE_V1',1,true),'需要已有暂停原因UI补丁')
 newUI=replace(newUI,'local reason=pauseReason',[=[
-- BEC_V1_CPU_WAIT_UI_V1: waiting for supply does not put the controller in fault.
local cpuReason=record.pipeline and record.pipeline.cpuWaitSummary
if not fault and type(cpuReason)=="string" and cpuReason~="" then
 local rows=record.pipeline.cpuWait or {};local manual={}
 for raw,row in pairs(rows)do if row.manual then manual[#manual+1]=raw end end
 table.sort(manual)
 if #manual>0 then
  local index=math.floor(computer.uptime()/5)%#manual+1
  local raw=manual[index];local row=rows[raw]
  text(3,22,"手动申请 "..index.."/"..#manual..": "..raw.."  "..row.amount.." mB",w-5,0xffffff,0xb00020)
  if h>25 then text(3,23,"AE拒绝: "..tostring(row.failure).."；下单后自动收料继续",w-5,0xffffff,0xb00020) end
 else
 local shortage=cpuReason:find("CPU 容量不足",1,true) or cpuReason:find("手动申请",1,true)
 text(3,22,"供液状态："..cpuReason,w-5,0xffffff,shortage and 0xb00020 or 0x23505b)
 if h>25 then text(3,23,"失败后在 ME 手动申请；程序继续收料，够料即生产",w-5,0xffffff,0x23505b) end
 end
end
local reason=pauseReason]=])
end
local control,controlErr=load(modified,'@'..path,'t',_ENV)
local uiChunk,uiErr=load(newUI,'@'..uiPath,'t',_ENV)
assert(control,'控制器语法检查失败: '..tostring(controlErr))
assert(uiChunk,'UI语法检查失败: '..tostring(uiErr))
local function stopped()
 assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先按Q正常退出UI')
 assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
  and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'先等纠缠装置停稳')
end
stopped();assert(read(path)==original and read(uiPath)==ui,'检查期间文件变化')
local n=1
while fs.exists(path..'.before-cpu-wait-'..n) or fs.exists(uiPath..'.before-cpu-wait-'..n)
 or fs.exists(path..'.cpu-wait-new-'..n) or fs.exists(uiPath..'.cpu-wait-new-'..n)do n=n+1 end
local entries={{path,original,modified},{uiPath,ui,newUI}}
for _,e in ipairs(entries)do
 e.backup=e[1]..'.before-cpu-wait-'..n;e.temp=e[1]..'.cpu-wait-new-'..n
 local f=assert(io.open(e.temp,'w'));assert(f:write(e[3]));assert(f:flush());f:close()
 assert(read(e.temp)==e[3],'临时文件回读失败')
end
stopped();assert(read(path)==original and read(uiPath)==ui,'写入期间文件变化')
local ok,why=pcall(function()
 for _,e in ipairs(entries)do
  assert(fs.rename(e[1],e.backup),'备份失败');e.backed=true
  assert(fs.rename(e.temp,e[1]),'替换失败');e.installed=true
  assert(read(e[1])==e[3] and read(e.backup)==e[2],'安装回读失败')
 end
end)
if not ok then
 for i=#entries,1,-1 do local e=entries[i]
  if e.backed then
   if e.installed then assert(fs.rename(e[1],e.temp),'失败文件保留失败')end
   assert(fs.rename(e.backup,e[1]),'备份还原失败');assert(read(e[1])==e[2],'还原回读失败')
  end
 end
 error(tostring(why)..'；已还原')
end
print('CPU等待补丁已安装；备份编号: '..n)
print('CPU忙时等待；申请失败显示手动补料，不自动重下；已有订单与日志保留。')
print('旧submitted记录仍须核对完成，不会盲目重下。继续: lua /home/bec_ui.lua resume')
