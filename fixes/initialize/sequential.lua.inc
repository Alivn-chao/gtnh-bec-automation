-- BEC_V1_SEQUENTIAL_CPU_WAIT_V1: keep both production fallback and cache alive while CPUs are occupied.
local supplyWaiting=false
local function supplyWait(reason,manual,missing,failure)
 supplyWaiting=true
 local summary=raw..': '..reason
 if not record.supplyWait or record.supplyWait.cpuWaitSummary~=summary then
  record.supplyWait={cpuWaitSummary=summary,cpuWait={[raw]={reason=reason,manual=manual,amount=missing,failure=failure}}}
  save(record.stage);print('供液等待: '..summary)
 end
end
if status and job.state=='submitted' then
 local computing=type(status.isComputing)=='function' and status.isComputing()
 local failed,why
 if type(status.hasFailed)=='function' then failed,why=status.hasFailed()end
 if computing==false and type(status.isComputing)=='function' and failed==true then
  job.state='rejected';job.preSubmissionFailed=true;job.manualSupply=true;job.failure=tostring(why)
  status=nil;save('stream-request-rejected')
 elseif computing then supplyWait('AE 正在计算计划，继续收料')
 else
  local canceled,why=status.isCanceled();assert(canceled==false,'AE任务取消且结果未确认: '..tostring(why))
  local done=status.isDone();assert(type(done)=='boolean','AE 状态不可读')
  if done then job.state='done';job.securedAfter=previous[raw] or 0;doneAt=computer.uptime();save('stream-craft-done')
  else supplyWait('AE 合成进行中，继续收料')end
 end
end
if priority and (not job or job.state=='done' or job.state=='rejected')then return handoff()end
if remaining==0 and (not job or job.state=='done' or job.state=='rejected')then record.supplyWait=nil;break end
if not priority and remaining>0 and (not job or job.state=='done' or job.state=='rejected')then
 local function deficit()return math.max(0,need-(previous[raw]or 0)-INLET_CREDIT-(network(MAIN)[raw]or 0))end
 local missing=deficit()
 if missing>0 and (not doneAt or computer.uptime()-doneAt>=3)then
  if job and job.state=='done'then assert((previous[raw]or 0)>job.securedBefore,'原液合成已结束但没有收获，核对竞争设备')end
  local ok,cpus=pcall(call,MAIN,'getCpus');local free,total,known,maxStorage=0,0,0,0;local unknown=not ok or type(cpus)~='table'
  if not unknown then for _,cpu in pairs(cpus)do
   total=total+1
   if type(cpu)~='table' or type(cpu.busy)~='boolean'then unknown=true
   else if not cpu.busy then free=free+1 end
    if type(cpu.storage)=='number'and cpu.storage>=0 then known=known+1;maxStorage=math.max(maxStorage,cpu.storage)end
   end
  end end
  if job and job.manualSupply then
   supplyWait('AE未启动申请；请在 ME 手动申请 '..missing..' mB；自动收料继续',true,missing,job.failure)
  elseif unknown then supplyWait('等待 CPU 状态恢复可读')
  elseif total==0 or (known==total and maxStorage==0)then supplyWait('CPU 容量不足：没有可用合成存储')
  elseif free==0 then supplyWait('等待合成 CPU 空闲，自动化继续运行')
  else
   if not craft then
    local rows=call(MAIN,'getCraftables',{name=raw});assert(type(rows)=='table','原液配方不可读')
    local count=0;for _,v in pairs(rows)do craft=v;count=count+1 end
    assert(count==1,'原液配方缺失或不唯一: '..raw)
    local f=craft.getStack();assert(type(f)=='table'and f.name==raw and f.isCraftable==true and type(f.amount)=='number'and f.amount==f.size and f.hasTag==false,'未验证的流体合成对象')
   end
   missing=deficit()
   if missing>0 then
    PRIORITY_CHECK
    attempts=attempts+1;assert(attempts<=3,'原液被其他设备争抢，保留已收库存')
    job={raw=raw,amount=missing,unit='mB',state='pending',securedBefore=previous[raw]or 0}
    record.requests[#record.requests+1]=job;save('craft-request-pending')
    local why;status,why=craft.request(missing);assert(status~=nil,'AE申请结果不明: '..tostring(why))
    job.state='submitted';doneAt=nil;save('stream-crafting')
    supplyWait('AE 正在计算计划，继续收料')
   end
  end
 end
end
if supplyWaiting then deadline=math.max(deadline,computer.uptime()+1800)end
assert(computer.uptime()<deadline,'持续收料超时，保留子网已搬入原液')
