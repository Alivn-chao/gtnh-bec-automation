-- BEC_V1_PRODUCTION_OVERLAP_V3: overlap independent AE jobs and conversion on bulk routes.
local sequentialPrepare=prepareStreaming
prepareStreaming=function(target)
 resolveRawNames(target)
 local ports,base,held=bulkPorts(),field(),network(SUB)
 for name,n in pairs(base) do assert(n==0 or mapping[name],"约束场有未知凝聚物") end
 local items,allowed,expected={},{},{}
 for name,need in pairs(target) do
  local raw,batch=mapping[name],units[name] or 144
  local amount=math.ceil(math.max(0,need-(base[name] or 0))/batch)*batch
  if amount>(held[raw] or 0) and not ports[raw] then
   print("缺少独立高速口，保留原顺序备料: "..raw)
   return sequentialPrepare(target)
  end
  assert((held[raw] or 0)<=amount and (held[raw] or 0)%batch==0,"子网原液超额或非整批: "..raw)
  allowed[raw]=true
  if amount>0 then expected[raw]=amount end
  items[#items+1]={raw=raw,name=name,amount=amount,batch=batch,initial=held[raw] or 0,delivered=0,attempts=0}
 end
 for raw in pairs(held) do assert(allowed[raw],"子网有无关原液: "..raw) end
 table.sort(items,function(a,b)return a.raw<b.raw end)
 unchanged();emptyConfig();tanks(4,nil);tanks(5,nil)
 assert(call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"流水备料开始前纠缠装置须停机")
 record.pipeline={base=base,initial=held,delivered={}}
 local recipe={};checkRecipe(record.required)
 for name,n in pairs(perRecipe) do recipe[name]=n end
 record.pipeline.recipe=recipe;record.pipeline.startConsumed={}
 for name,n in pairs(record.required) do record.pipeline.startConsumed[name]=n-record.remaining[name] end
 local halted,released=false,false
 local releasedAt;local lastFeedback;local feedbackAt=0
 local lastRequired=record.required
 local tierMethod=c.methods(NODE).getRequiredTier~=nil
 local function tierValue()local t=call(NODE,"getRequiredTier");return type(t)=="table" and t.tier or t end
 local neededTier=tierMethod and tierValue()
 local function productionGuard()
  if record.gateIntent then verifyGate(record.gateIntent.filters) end
  local state=call(NODE,"getState")
  local req=call(NODE,"getRequiredCondensate")
  local parallel=call(NODE,"getParallelRecipesInProgress")
  local normalized={}
  if type(req)=="table" and type(parallel)=="number" and parallel>0 then
   for name,n in pairs(req) do normalized[name]=integer(n)/parallel end
  end
  local changed=not same(normalized,recipe)
  local reason=changed and "配方需求变化，等待旧窗口收尾" or nil
  local tierCovered=false
  if not changed and tierMethod then
   local nextTier=tierValue()
   if nextTier~=neededTier or state=="nanite-tier-too-low" then
    local provided=call(NODE,"getProvidedTier")
    local count=call(NODE,"getAvailableNanites")
    tierCovered=type(nextTier)=="number" and type(provided)=="table" and type(provided.tier)=="number"
     and provided.tier>=nextTier and type(count)=="number" and count>=64
    if tierCovered then
     neededTier=nextTier
    else changed=true;reason="蜂群不足以运行当前阶段，等待旧窗口收尾" end
   end
  end
  if state~="crafting" and state~="paused-immediate" and not(state=="nanite-tier-too-low" and tierCovered) then
   changed=true;reason=reason or ("节点状态: "..tostring(state))
  end
  if released and releasedAt and computer.uptime()-releasedAt>=3 then
   local output=call(RS,"getOutput",sides.top)
   local feedback
   if output~=0 then
    feedback="本脚本已放行，但暂停输出被改为 "..tostring(output).."；检查其他运行脚本或红石控制"
   elseif state=="paused-immediate" then
    feedback="本脚本暂停输出=0，节点仍立即暂停；检查其他控制仓收到的红石信号"
   end
   if feedback and (feedback~=lastFeedback or computer.uptime()>=feedbackAt) then
    print("放行核对: "..feedback)
    record.pipeline.feedback={reason=feedback,output=output,state=state,at=computer.uptime()}
    save(record.stage);lastFeedback=feedback;feedbackAt=computer.uptime()+15
   elseif not feedback then lastFeedback=nil;record.pipeline.feedback=nil end
  end
  if changed then
   if not halted then print("生产暂停: "..reason.."；已提交的供液申请继续核对，不重复下单。") end
   pause(15);released=false;halted=true
   if state=="idle" and record.pipeline.overlap then
    local used=call(NODE,"getConsumedCondensate");assert(type(used)=="table","节点空闲后消耗记录不可读")
    for name,n in pairs(lastRequired)do assert(integer(used[name] or 0)>=n,"节点进入空闲但凝聚物未消耗完: "..name)end
   end
  else
   lastRequired=req
  end
  return req
 end
 local plans={};for _,item in ipairs(items) do plans[#plans+1]={raw=item.raw,name=item.name,amount=item.amount,batch=item.batch} end
 record.plan=plans;record.expected=expected;record.secured=held;save("pipeline-planned")
 local converting=false
 local deadline=computer.uptime()+1800
 for _,item in ipairs(items) do deadline=deadline+math.ceil(item.amount/item.batch)*180 end
 local function jobsAndRequests()
  -- Submit every eligible deficit before waiting for any one job to finish.
  for _,item in ipairs(items) do
   if stopping then return end
   local job,status=item.job,item.status
   if job and job.state=="submitted" then
    local canceled,why=status.isCanceled();assert(canceled==false,"主网原液申请失败/取消: "..tostring(why))
    local done=status.isDone();assert(type(done)=="boolean","AE 状态不可读")
    if done then job.state="done";item.doneAt=computer.uptime();save("pipeline-craft-done")
    else assert(computer.uptime()<item.jobDeadline,"主网原液合成超时，保留申请记录") end
   end
   local remaining=item.amount-item.initial-item.delivered
   if remaining>0 and (not job or job.state=="done") and (not item.doneAt or computer.uptime()-item.doneAt>=3) then
    local missing=math.max(0,remaining-(network(MAIN)[item.raw] or 0))
    if missing>0 then
     if job then assert(item.delivered>job.securedBefore,"原液合成已结束但没有收获，暂停核对竞争设备") end
     local free=false;local cpus=call(MAIN,"getCpus");assert(type(cpus)=="table","主网 CPU 状态不可读")
     for _,cpu in pairs(cpus) do if cpu.busy==false then free=true end end
     if free then
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
       job={raw=item.raw,amount=missing,unit="mB",state="pending",securedBefore=item.delivered}
       record.requests[#record.requests+1]=job;item.job=job;save("craft-request-pending")
       local status,why=item.craft.request(missing);assert(status~=nil,"AE 申请未确认: "..tostring(why))
       item.status=status;job.state="submitted";item.doneAt=nil;item.jobDeadline=computer.uptime()+1800
       save("pipeline-crafting");print("并行 AE 申请 "..item.raw.." "..missing.." mB")
      end
     end
    end
   end
  end
 end
 while not stopping do
  productionGuard();jobsAndRequests();if stopping then break end
  for _,item in ipairs(items) do
   if stopping then break end
   local remaining=item.amount-item.initial-item.delivered
   local amount=remaining>0 and math.floor(math.min(remaining,network(MAIN)[item.raw] or 0,2147483647)/item.batch)*item.batch or 0
   if amount>0 then
    local route=assert(ports[item.raw]);verifyBulk(route,item.raw);productionGuard()
    record.pending={raw=item.raw,amount=amount,address=route.address,from=route.from,to=route.to};save("transfer-pending")
    local ok,moved=call(route.address,"transferFluid",route.from,route.to,amount)
    record.transfers[#record.transfers+1]={raw=item.raw,ok=ok,amount=moved,requested=amount,address=route.address,from=route.from,to=route.to}
    save("transfer-returned");assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试")
    item.delivered=item.delivered+amount;record.pipeline.delivered[item.raw]=item.delivered
    record.pending=nil;save("pipeline-transfer-confirmed")
   end
  end
  if stopping then break end
  -- Read field before sub: conversion between reads can only lower this sum.
  local stock,sub=field(),network(SUB)
  for raw in pairs(sub) do assert(allowed[raw],"流水备料子网出现无关原液") end
  for name,n in pairs(base) do if not recipe[name] then assert((stock[name] or 0)==n,"无关凝聚物库存变化") end end
  local ready,hasRaw=true,false
  for _,item in ipairs(items) do
   local supplied=item.initial+item.delivered
   local liquid=integer(sub[item.raw] or 0);local condensate=integer(stock[item.name] or 0)
   assert(liquid+condensate<=supplied+(base[item.name] or 0),"流水备料库存超过已确认搬入量: "..item.raw)
   hasRaw=hasRaw or liquid>0
   if supplied<item.amount or liquid>0 or (item.job and item.job.state~="done") then ready=false end
  end
  local req=productionGuard()
  local funded=not halted
  local shortages={}
  if funded then
   local consumed=call(NODE,"getConsumedCondensate")
   assert(type(consumed)=="table","当前消耗记录不可读")
   for name,n in pairs(req) do
    local used=integer(consumed[name] or 0);assert(used<=n,"节点消耗超过当前需求")
    if (stock[name] or 0)<n-used then
     funded=false;shortages[#shortages+1]=name.." 缺 "..(n-used-(stock[name] or 0)).." mB"
    end
   end
  end
  if funded and not released then
   checkRecipe(req)
   record.pipeline.overlap=true;save("pipeline-production-release-pending")
   local releaseReq=productionGuard()
   if not halted and same(releaseReq,req) then pause(0);released=true;releasedAt=computer.uptime();save("pipeline-producing")
    print("当前配方材料已够，暂停输出已设0；节点运行状态持续核对，其余供液纠缠继续。") end
  elseif not funded and released then
   pause(15);released=false;save("pipeline-waiting-material")
   if #shortages>0 then print("生产等料: "..table.concat(shortages,"；").."；供液纠缠继续。") end
  end
  if ready and (halted or not funded) and (not converting or call(GEN,"isMachineActive")==false) then
   pause(15)
   if converting then generator(false) end
   record.plan=nil;record.pipeline=nil;record.productionOverlapHandled=true;record.expected={};record.secured={}
   save("stream-prepared");return {}
  end
  if hasRaw and not converting then
   productionGuard();save("pipeline-converting");generator(true);converting=true
   print("原液已到货，边收料边纠缠；当前配方够料即生产。")
  end
  assert(computer.uptime()<deadline,"流水备料超时，保留全部申请和搬液记录")
  tick(0.1)
 end
 return expected
end
