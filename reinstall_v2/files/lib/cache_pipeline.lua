-- Independent AE requests share a poll; physical transfers remain serialized.
return function(o)
 local record,previous=o.record,o.previous
 -- record.plan is durable data. AE proxies/closures must stay in this worker.
 local items={}
 for i,v in ipairs(o.items)do items[i]={raw=v.raw,amount=v.amount,batch=v.batch}end
 local priority=false;local nextCpuCheck=0;local cpuInfo
 local function terminal(job)
  return not job or job.state=='done'or job.state=='rejected'and job.preSubmissionFailed==true
 end
 local function cpuCapacity()
  local ok,rows=pcall(o.call,o.main,'getCpus');local info={free=0,total=0,known=0,max=0}
  if not ok or type(rows)~='table'then info.unknown=true;return info end
  for _,cpu in pairs(rows)do
   info.total=info.total+1
   if type(cpu)~='table'or type(cpu.busy)~='boolean'then info.unknown=true
   else
    if not cpu.busy then info.free=info.free+1 end
    if type(cpu.storage)=='number'and cpu.storage>=0 then info.known=info.known+1;info.max=math.max(info.max,cpu.storage)end
   end
  end
  return info
 end
 local function supplyWait(reason)
  if record.supplyWait and record.supplyWait.cpuWaitSummary==reason then return end
  record.supplyWait=reason~=''and{cpuWaitSummary=reason}or nil
  o.save(record.stage);if reason~=''then o.log('供液等待: '..reason)end
 end
 for _,item in ipairs(items)do item.attempts=0;item.deadline=o.now()+1800 end
 o.emptyConfig();o.tanks(4,nil)
 while not o.stopping()do
  o.poll();priority=priority or o.productionWaiting()
  local now=o.now();local planning,waiting,changed=0,false,false
  -- One status sample per request. Pending/unknown outcomes are never replayed.
  for _,item in ipairs(items)do
   local job,status=item.job,item.status
   item.computing=false
   if job and job.state=='submitted'then
    local computing=type(status.isComputing)=='function'and status.isComputing()
    if computing==true then item.computing=true;planning=planning+1;waiting=true
    else
     local failed,why
     if type(status.hasFailed)=='function'then failed,why=status.hasFailed()end
     if computing==false and type(status.isComputing)=='function'and failed==true then
      job.state='rejected';job.preSubmissionFailed=true;job.manualSupply=true;job.failure=tostring(why);item.status=nil;changed=true
     else
      local canceled,why=status.isCanceled();assert(canceled==false,'AE任务取消且结果未确认: '..tostring(why))
      local done=status.isDone();assert(type(done)=='boolean','AE 状态不可读')
      if done then job.state='done';job.securedAfter=previous[item.raw]or 0;item.doneAt=now;changed=true
      else
       waiting=true
       if type(status.isComputing)~='function'then planning=planning+1 end
      end
     end
    end
   end
  end
  if changed then o.save('stream-jobs-updated')end
  local main=o.network(o.main);local movedAny=false
  -- A slow fluid does not hold up collecting another fluid that already arrived.
  for _,item in ipairs(items)do
   local raw,need,batch=item.raw,item.amount,item.batch
   local held=previous[raw]or 0;local remaining=need-held
   local settling=(batch-held%batch)%batch
   local amount=math.floor(math.min(priority and settling or remaining,main[raw]or 0,math.floor(2147483647/batch)*batch))
   if amount>0 then
    local route=assert(o.ports[raw],'高速供液口不可用: '..raw);o.verifyBulk(route,raw)
    record.pending={raw=raw,amount=amount,address=route.address,from=route.from,to=route.to};o.save('transfer-pending')
    local ok,moved=o.call(route.address,'transferFluid',route.from,route.to,amount)
    record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=route.address,from=route.from,to=route.to}
    o.save('transfer-returned')
    assert(ok==true and type(moved)=='number'and moved>=0 and moved<=amount and moved==math.floor(moved),'搬运返回值未确认，停止且不重试')
    if moved>0 then previous[raw]=held+moved;main[raw]=math.max(0,(main[raw]or 0)-moved);item.deadline=o.now()+1800;movedAny=true end
    o.waitUntil(10,function()return o.same(o.network(o.sub),previous)end,o.unchanged)
    if moved==0 then table.remove(record.transfers);record.zeroTransfers=(record.zeroTransfers or 0)+1 end
    record.pending=nil;record.secured=previous;o.save('stream-transfer-confirmed')
    o.log(raw..' 已入子网 '..(previous[raw]or 0)..' / '..need..' mB')
   end
  end
  local complete,settled,jobsDone=true,true,true
  for _,item in ipairs(items)do
   if(previous[item.raw]or 0)<item.amount then complete=false end
   if(previous[item.raw]or 0)%item.batch~=0 then settled=false end
   if not terminal(item.job)then jobsDone=false end
  end
  if priority and settled and jobsDone then return o.handoff()end
  if complete and jobsDone then
   assert(o.same(o.network(o.sub),o.expected),'整批子网原液不符')
   record.supplyWait=nil;record.plan=nil;o.save('stream-prepared');return o.expected
  end
  -- CPU occupancy is fetched once for a wave, not once per fluid. Plans that
  -- have not acquired a CPU reserve free slots until their state is known.
  local candidates={}
  for _,item in ipairs(items)do
   local held=previous[item.raw]or 0
   local need=priority and(item.batch-held%item.batch)%item.batch or item.amount-held
   if need>0 and terminal(item.job)and not(item.job and item.job.manualSupply)
    and(not item.doneAt or now-item.doneAt>=3)and need>(main[item.raw]or 0)then
    if item.job and item.job.state=='done'then assert(held>item.job.securedBefore,'原液合成已结束但没有收获，核对竞争设备')end
    candidates[#candidates+1]=item
   end
  end
  local submitted=0;local reason=''
  if #candidates>0 and now>=nextCpuCheck then
   cpuInfo=cpuCapacity();nextCpuCheck=now+1
   local slots=math.max(0,cpuInfo.free-planning)
   if cpuInfo.unknown then reason='等待 CPU 状态恢复可读'
   elseif cpuInfo.total==0 or cpuInfo.known==cpuInfo.total and cpuInfo.max==0 then reason='CPU 容量不足：没有可用合成存储'
   elseif slots==0 then reason='等待合成 CPU 空闲，已有任务与收料继续'
   else
    local wave={}
    for _,item in ipairs(candidates)do
     if #wave>=slots or o.stopping()then break end
     if not item.craft then
      local rows=o.call(o.main,'getCraftables',{name=item.raw});assert(type(rows)=='table','原液配方不可读')
      local count=0;for _,v in pairs(rows)do item.craft=v;count=count+1 end
      assert(count==1,'原液配方缺失或不唯一: '..item.raw)
      local f=item.craft.getStack()
      assert(type(f)=='table'and f.name==item.raw and f.isCraftable==true and type(f.amount)=='number'and f.amount==f.size and f.hasTag==false,'未验证的流体合成对象')
     end
     wave[#wave+1]=item
    end
    if #wave>0 and not o.stopping()then
     priority=priority or o.productionWaiting()
     if o.requestGuard then o.requestGuard()end
     -- Fresh inventory after potentially expensive craft-object discovery.
     main=o.network(o.main)
     for _,item in ipairs(wave)do
      priority=priority or o.productionWaiting()
      if o.stopping()then break end
      local held=previous[item.raw]or 0
      local need=priority and(item.batch-held%item.batch)%item.batch or item.amount-held
      local missing=math.min(math.max(0,need-(main[item.raw]or 0)),math.floor(2147483647/item.batch)*item.batch)
      if missing>0 then
       item.attempts=item.attempts+1;assert(item.attempts<=3,'原液被其他设备争抢，保留已收库存')
       local job={raw=item.raw,amount=missing,unit='mB',state='pending',securedBefore=held}
       item.job=job;record.requests[#record.requests+1]=job;o.save('craft-request-pending')
       local status,why=item.craft.request(missing);assert(status~=nil,'AE申请结果不明: '..tostring(why))
       item.status=status;job.state='submitted';item.doneAt=nil;o.save('stream-crafting')
       submitted=submitted+1;waiting=true
       o.log('并行 AE 申请 '..item.raw..' '..missing..' mB')
      end
     end
    end
   end
  end
  for _,item in ipairs(items)do if item.job and item.job.manualSupply and(previous[item.raw]or 0)<item.amount then
   waiting=true;reason=item.raw..' AE未启动申请；请在 ME 手动申请，其他原液继续'
  end end
  if submitted>0 then reason='已并行提交 '..submitted..' 笔申请，到账独立收料'
  elseif reason==''and waiting then reason='AE 合成进行中，其他供液与生产继续'end
  -- Do not rewrite a wait log just because this poll reused its CPU snapshot.
  if reason~=''then supplyWait(reason)end
  for _,item in ipairs(items)do
   if waiting or #candidates>0 then item.deadline=math.max(item.deadline,o.now()+1800)end
   assert(o.now()<item.deadline,'持续收料超时，保留子网已搬入原液')
  end
  o.tick(movedAny and 0 or .25)
 end
 return o.expected
end
