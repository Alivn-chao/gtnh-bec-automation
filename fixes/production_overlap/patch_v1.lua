-- Upgrade the existing pipeline; preserve installed bee, filter and UI fixes.
local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original=read(path)
if original:find('BEC_V1_PRODUCTION_OVERLAP_V2',1,true)then print('生产/纠缠并行补丁V2已安装');return end
local function section(s,first,last,new)
 local a,b=s:find(first,1,true);assert(a and not s:find(first,b+1,true),'入口缺失或不唯一: '..first)
 local z=assert(s:find(last,b+1,true),'结束入口缺失: '..last)
 return s:sub(1,a-1)..new..s:sub(z)
end
local upgrading=original:find('BEC_V1_PRODUCTION_OVERLAP_V1',1,true)~=nil
local modified=section(original,upgrading and '-- BEC_V1_PRODUCTION_OVERLAP_V1:' or '-- BEC_V1_PIPELINE_V1:','local function serve()',[==[-- BEC_V1_PRODUCTION_OVERLAP_V2: overlap independent AE jobs and conversion on bulk routes.
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
  if funded then
   local consumed=call(NODE,"getConsumedCondensate")
   assert(type(consumed)=="table","当前消耗记录不可读")
   for name,n in pairs(req) do
    local used=integer(consumed[name] or 0);assert(used<=n,"节点消耗超过当前需求")
    if (stock[name] or 0)<n-used then funded=false end
   end
  end
  if funded and not released then
   checkRecipe(req)
   record.pipeline.overlap=true;save("pipeline-production-release-pending")
   local releaseReq=productionGuard()
   if not halted and same(releaseReq,req) then pause(0);released=true;save("pipeline-producing")
    print("当前配方材料已够，开始生产；其余收液、下单和纠缠继续。") end
  elseif not funded and released then
   pause(15);released=false;save("pipeline-waiting-material")
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
]==]..'\n')
modified=section(modified,'if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then','local streaming=',[==[if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then
 assert(mode=="resume" or mode=="restock","流水未完成，请用resume核对")
 assert(old.pending==nil and old.configOwned==false,"流水存在未确认搬液，保留日志核对")
 for _,job in ipairs(old.requests or {})do assert(job.state=="done","原液申请尚未确认完成，禁止重复下单")end
 for _,move in ipairs(old.transfers or {})do assert(move.ok==true and move.amount==move.requested and integer(move.amount)>0,"搬液未完整确认")end
 assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置停机")
 resolveRawNames(old.target)
 local p=old.pipeline
 assert(type(p.base)=="table" and type(p.initial)=="table" and type(p.delivered)=="table","流水守恒记录缺失")
 local stock,sub=field(),network(SUB);local allowed={};local completed
 local req=call(NODE,"getRequiredCondensate");local consumed=call(NODE,"getConsumedCondensate")
 local normalized={};local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)=="table" and type(parallel)=="number" and parallel>0 then for name,n in pairs(req)do normalized[name]=integer(n)/parallel end end
 local sameRecipe=p.recipe and same(normalized,p.recipe)
 for _,item in ipairs(old.plan)do
  local raw,name=item.raw,item.name;assert(mapping[name]==raw,"恢复原液映射变化");allowed[raw]=true
  local budget=integer(p.base[name] or 0)+integer(p.initial[raw] or 0)+integer(p.delivered[raw] or 0)
  local loss=budget-integer(stock[name] or 0)-integer(sub[raw] or 0)
  if p.overlap then
   assert(type(p.recipe)=="table" and type(p.startConsumed)=="table" and type(consumed)=="table","并行消耗记录缺失")
   local used=sameRecipe and integer(consumed[name] or 0) or 0
   if not sameRecipe then for _,n in pairs(consumed)do assert(integer(n)==0,"下一配方已有消耗，须核对旧流水")end end
   local batches=(loss+integer(p.startConsumed[name] or 0)-used)/assert(p.recipe[name])
   assert(loss>=0 and batches>=0 and batches%1==0 and (completed==nil or completed==batches),"生产消耗与流水库存不守恒: "..raw)
   completed=batches
  else assert(loss==0,"流水库存不守恒: "..raw)end
 end
 for name,n in pairs(p.base)do if not allowed[mapping[name]]then assert((stock[name] or 0)==n,"无关凝聚物变化")end end
 for raw in pairs(sub)do assert(allowed[raw],"子网有无关原液")end
 -- Drain only confirmed material before archiving; never repeat a request/move.
 local total={};for _,item in ipairs(old.plan)do total[item.name]=integer(stock[item.name] or 0)+integer(sub[item.raw] or 0)end
 local ok,reason=pcall(function()
  if next(sub)~=nil then
   generator(true);local deadline=computer.uptime()+1800
   while next(network(SUB))~=nil or call(GEN,"isMachineActive")==true do
    assert(not stopping and computer.uptime()<deadline,"恢复转换未完成，原日志保留")
    assert(call(RS,"getOutput",sides.top)==15,"恢复转换时节点意外放行")
    field()
    tick(0.1)
   end
  end
  local final=field();for name,n in pairs(total)do assert((final[name] or 0)==n,"恢复转换不守恒")end
 end)
 generator(false);assert(ok,reason)
 old.stage="watching";old.plan=nil;old.pipeline=nil
 print("并行生产消耗核对通过；已确认余液转换完成，按真实库存继续，不重复下单搬液。")
end
]==]..'\n')
if not upgrading then
local marker='local expected=prepareStreaming(target)'
local a,b=modified:find(marker,1,true);assert(a and not modified:find(marker,b+1,true),'生产入口不唯一')
modified=modified:sub(1,b)..' if record.productionOverlapHandled then record.productionOverlapHandled=nil else '..modified:sub(b+1)
local count
modified,count=modified:gsub('end%s+end%s+end%s+pause%(15%);generator%(false%);record.configOwned=false',
 'end end end end pause(15);generator(false);record.configOwned=false')
assert(count==1,'生产循环结束入口不唯一，原文件未改')
end
assert(load(modified,'@'..path,'t',_ENV),'并行生产补丁语法检查失败')
assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先在面板按Q正常停止')
assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
 and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'先等纠缠装置停机')
local n=1;while fs.exists(path..'.before-overlap-'..n)or fs.exists(path..'.overlap-new-'..n)do n=n+1 end
local backup,temp=path..'.before-overlap-'..n,path..'.overlap-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified,'临时文件回读失败')
assert(fs.rename(path,backup),'备份失败')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'备份还原失败');error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'文件回读失败')
print('生产/供液/纠缠并行补丁已安装；备份: '..backup)
print('配置、订单和日志保留。继续: lua /home/bec_ui.lua resume')
