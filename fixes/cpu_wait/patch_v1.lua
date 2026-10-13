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
 modified=modified:sub(1,a-1)..[==[ local function jobsAndRequests()
  -- BEC_V1_CPU_WAIT_V1: wait for free CPUs; proven rejected requests use manual supply.
  local waits={};local waiting=false
  local function cpus()
   local ok,rows=pcall(call,MAIN,"getCpus")
   local info={free=0,busy=0,total=0,known=0,maxFree=0,maxBusy=0,max=0}
   if not ok or type(rows)~="table" then info.unknown=true;return info end
   for _,cpu in pairs(rows) do
    info.total=info.total+1
    if type(cpu)~="table" or type(cpu.busy)~="boolean" then info.unknown=true
    else
     if cpu.busy then info.busy=info.busy+1 else info.free=info.free+1 end
     local storage=cpu.storage
     if type(storage)=="number" and storage>=0 then
      info.known=info.known+1;info.max=math.max(info.max,storage)
      if cpu.busy then info.maxBusy=math.max(info.maxBusy,storage)
      else info.maxFree=math.max(info.maxFree,storage) end
     end
    end
   end
   return info
  end
  local function capacityFailure(reason)
   local s=tostring(reason):lower()
   return s:find("insufficient storage",1,true) or s:find("not enough storage",1,true)
    or s:find("storage too small",1,true) or s:find("insufficient capacity",1,true)
    or s:find("容量不足",1,true)
  end
  local function wait(item,reason,info)
   waiting=true
   waits[item.raw]={reason=reason,free=info and info.free,busy=info and info.busy,
    maxFree=info and info.maxFree,maxBusy=info and info.maxBusy,maxStorage=info and info.max}
  end
  -- Each deficit is independent: a rejected request cannot block other fluids.
  for _,item in ipairs(items) do
   if stopping then return true end
   local job,status=item.job,item.status
   if job and job.state=="submitted" then
    local computing
    if type(status.isComputing)=="function" then computing=status.isComputing() end
    local failed,why
    if type(status.hasFailed)=="function" then failed,why=status.hasFailed() end
    if computing==false and failed==true then
     job.state="rejected";job.preSubmissionFailed=true;job.failure=tostring(why)
     job.manualSupply=true;item.status=nil
     save("pipeline-request-rejected")
    elseif computing==true then
     wait(item,"AE 正在计算合成计划")
    else
     local canceled,why=status.isCanceled()
     assert(canceled==false,"主网原液申请失败/取消（未证实未启动，不重复下单）: "..tostring(why))
     local done=status.isDone();assert(type(done)=="boolean","AE 状态不可读")
     if done then job.state="done";item.doneAt=computer.uptime();save("pipeline-craft-done")
     else wait(item,"AE 合成进行中，继续收料") end
    end
   end
   local remaining=item.amount-item.initial-item.delivered
   if remaining>0 and (not job or job.state=="done" or job.state=="rejected")
    and (not item.doneAt or computer.uptime()-item.doneAt>=3) then
    local missing=math.max(0,remaining-(network(MAIN)[item.raw] or 0))
    if missing>0 then
     if job and job.state=="done" then
      assert(item.delivered>job.securedBefore,"原液合成已结束但没有收获，暂停核对竞争设备")
     end
     local info=cpus()
     local reason
     if job and job.state=="rejected" then
      if info.unknown then reason="申请未成功；CPU 状态暂不可读"
      elseif info.busy>0 then reason="申请未成功，CPU 被占用或容量/原料不足"
      elseif capacityFailure(job.failure) then reason="CPU 容量不足：AE 拒绝了这笔申请"
      else reason="AE 未启动申请：容量或原料待核对" end
      reason=reason.."；请在 ME 手动申请 "..missing.." mB；自动收料继续"
     elseif info.unknown then reason="等待 CPU 状态恢复可读"
     elseif info.total==0 or (info.known==info.total and info.max==0) then reason="CPU 容量不足：没有可用合成存储"
     elseif info.free==0 then reason="等待合成 CPU 空闲，其他供液与生产继续"
     end
     if reason then
      wait(item,reason,info)
      waits[item.raw].amount=missing;waits[item.raw].manual=job and job.manualSupply or nil
      waits[item.raw].failure=job and job.failure or nil
     end
     if not(job and job.manualSupply) and not info.unknown and info.free>0
      and not(info.known==info.total and info.max==0) then
      if not item.craft then
       local rows=call(MAIN,"getCraftables",{name=item.raw});assert(type(rows)=="table","原液配方不可读")
       local count=0;for _,craft in pairs(rows) do item.craft=craft;count=count+1 end
       assert(count==1,"原液配方缺失或不唯一: "..item.raw)
       local f=item.craft.getStack()
       assert(type(f)=="table" and f.name==item.raw and f.isCraftable==true and type(f.amount)=="number" and f.amount==f.size and f.hasTag==false,"未验证的流体合成对象")
      end
      missing=math.max(0,remaining-(network(MAIN)[item.raw] or 0))
      if missing>0 then
       item.attempts=item.attempts+1;assert(item.attempts<=3,"原液仍被争抢，保留已收获库存")
       job={raw=item.raw,unit="mB"};record.requests[#record.requests+1]=job
       job.amount=missing;job.state="pending";job.securedBefore=item.delivered
       item.job=job;save("craft-request-pending")
       local newStatus,why=item.craft.request(missing)
       assert(newStatus~=nil,"AE 申请未确认: "..tostring(why))
       item.status=newStatus;job.state="submitted";item.doneAt=nil
       save("pipeline-crafting");print("并行 AE 申请 "..item.raw.." "..missing.." mB")
       wait(item,"AE 正在计算合成计划",info)
      end
     end
    end
   end
  end
  local lines={}
  for raw,row in pairs(waits) do lines[#lines+1]={text=raw..": "..row.reason,
   urgent=row.reason:find("手动申请",1,true) or row.reason:find("容量不足",1,true)} end
  table.sort(lines,function(a,b)if not not a.urgent~=not not b.urgent then return not not a.urgent end;return a.text<b.text end)
  for i,row in ipairs(lines)do lines[i]=row.text end
  local summary=table.concat(lines,"；")
  if summary~=record.pipeline.cpuWaitSummary then
   record.pipeline.cpuWait=waits;record.pipeline.cpuWaitSummary=summary
   save(record.stage)
   if summary~="" then print("供液等待: "..summary) end
  end
  return waiting
 end
]==]..'\n'..modified:sub(z)
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
