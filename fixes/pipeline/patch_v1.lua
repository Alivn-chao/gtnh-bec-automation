-- Upgrade only the installed production controller, preserving every journal.
local fs=require('filesystem')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return assert(text)end
local function replace(text,from,to)
 local a,b=text:find(from,1,true)
 assert(a and not text:find(from,b+1,true),'流水补丁入口缺失或不唯一，原文件未改')
 return text:sub(1,a-1)..to..text:sub(b+1)
end
local original=read(path)
if original:find('BEC_V1_PIPELINE_V1',1,true)then print('流水备料补丁已安装');return end
local modified=original:gsub('\r\n','\n')
local prepare=[=[-- BEC_V1_PIPELINE_V1: overlap independent AE jobs and conversion on bulk routes.
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
  unchanged();jobsAndRequests();if stopping then break end
  for _,item in ipairs(items) do
   if stopping then break end
   local remaining=item.amount-item.initial-item.delivered
   local amount=math.floor(math.min(remaining,network(MAIN)[item.raw] or 0,2147483647)/item.batch)*item.batch
   if amount>0 then
    local route=assert(ports[item.raw]);verifyBulk(route,item.raw);unchanged()
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
  for name,n in pairs(base) do assert((stock[name] or 0)>=n,"暂停备料时已有凝聚物减少") end
  local ready,hasRaw=true,false
  for _,item in ipairs(items) do
   local supplied=item.initial+item.delivered
   local liquid=integer(sub[item.raw] or 0);local condensate=integer(stock[item.name] or 0)
   assert(condensate>=(base[item.name] or 0) and liquid+condensate<=supplied+(base[item.name] or 0),"流水备料库存超过已确认搬入量: "..item.raw)
   hasRaw=hasRaw or liquid>0
   if supplied<item.amount or condensate<target[item.name] or liquid>0 or (item.job and item.job.state~="done") then ready=false end
  end
  if ready and (not converting or call(GEN,"isMachineActive")==false) then
   if converting then generator(false) end
   record.plan=nil;record.pipeline=nil;record.pipelineComplete=true;record.expected={};record.secured={}
   save("stream-prepared");return {}
  end
  if hasRaw and not converting then
   unchanged();save("pipeline-converting");generator(true);converting=true
   print("原液已到货，边收料边纠缠；装配端保持暂停。")
  end
  assert(computer.uptime()<deadline,"流水备料超时，保留全部申请和搬液记录")
  tick(0.1)
 end
 return expected
end
]=]
local recover=[=[if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then
 assert(mode=="resume" or mode=="restock","流水备料未完成，请核对后用resume，不重新下单")
 assert(old.pending==nil and old.configOwned==false,"流水备料有未确认搬运")
 for _,job in ipairs(old.requests or {}) do assert(job.state=="done","流水备料申请未完成，保留日志，禁止重复申请") end
 for _,move in ipairs(old.transfers or {}) do assert(move.ok==true and move.amount==move.requested and integer(move.amount)>0,"流水搬液未完整确认") end
 assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"流水恢复须节点暂停且纠缠装置完成当前转换后停机")
 local req,left=current(true);assert(same(req,old.required) and same(left,old.remaining),"流水恢复订单变化，保留日志核对")
 resolveRawNames(old.target)
 local p=old.pipeline;assert(type(p.base)=="table" and type(p.initial)=="table" and type(p.delivered)=="table","流水守恒记录缺失")
 local stock,sub=field(),network(SUB);local allowed={}
 for _,item in ipairs(old.plan) do
  local raw,name=item.raw,item.name;assert(mapping[name]==raw,"流水恢复原液映射变化")
  allowed[raw]=true
  assert(integer(stock[name] or 0)+integer(sub[raw] or 0)==integer(p.base[name] or 0)+integer(p.initial[raw] or 0)+integer(p.delivered[raw] or 0),"流水恢复库存不守恒: "..raw)
 end
 for name,n in pairs(p.base) do assert((stock[name] or 0)>=n,"流水恢复已有凝聚物减少") end
 for raw in pairs(sub) do assert(allowed[raw],"流水恢复子网有无关原液") end
 -- Normalize in memory only; the archived journal keeps the complete pipeline.
 old.stage="stream-planned";old.secured=sub
 print("流水恢复守恒核对通过，抵扣已转换/剩余原液，不重放旧申请。")
end
]=]
modified=replace(modified,'end local function serve()', 'end\n'..prepare..'\nlocal function serve()')
modified=replace(modified,'local old=ser.unserialize(contents) local streaming=',
 'local old=ser.unserialize(contents)\n'..recover..'\nlocal streaming=')
modified=replace(modified,'for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end',
 'if record.pipelineComplete then unchanged();assert(next(network(SUB))==nil,"流水转换后子网非空");record.pipelineComplete=nil else for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end end')
assert(load(modified,'@'..path,'t',_ENV),'流水补丁后语法检查失败')
local n=1;while fs.exists(path..'.before-pipeline-'..n) or fs.exists(path..'.pipeline-new-'..n)do n=n+1 end
local backup,temp=path..'.before-pipeline-'..n,path..'.pipeline-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close()
assert(read(temp)==modified,'流水临时文件回读失败')
assert(fs.rename(path,backup),'备份失败，原文件保留')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'还原失败，原文件在 '..backup);error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'流水替换或备份回读失败')
print('并行下单/收液纠缠补丁已安装；备份: '..backup)
print('未启停机器或改日志。正常Q停止后继续: lua /home/bec_ui.lua run')
