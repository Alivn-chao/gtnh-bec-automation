 local function jobsAndRequests()
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
