local fs=require('filesystem');local c=require('component')
local function read(p)local f=io.open(p,'r');if not f then return end;local text=f:read('*a');f:close();return text end
local function replace(s,from,to)local a,b=s:find(from,1,true);assert(a and not s:find(from,b+1,true),'入口缺失或重复: '..from);return s:sub(1,a-1)..to..s:sub(b+1)end
local autoPath='/home/bec_auto.lua';local uiPath='/home/bec_ui.lua';local cachePath='/home/bec_cache.lua'
local ui=assert(read(uiPath))
assert(ui:find('BEC_V1_UI_CACHE_RESET_V3',1,true),'需要缓存重置V3面板')
if not assert(read(autoPath)):find('BEC_V1_CPU_WAIT_V1:',1,true) or not ui:find('BEC_V1_CPU_WAIT_UI_V1:',1,true)then
 local function installCPU()
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

 end
 installCPU();ui=assert(read(uiPath))
end
local entries={}
local function add(path,old,new)
 if old==new then return end
 assert(load(new,'@'..path,'t',_ENV),'程序语法检查失败: '..path)
 entries[#entries+1]={path=path,old=old,new=new}
end
local seq=[====[-- BEC_V1_SEQUENTIAL_CPU_WAIT_V1: keep both production fallback and cache alive while CPUs are occupied.
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
]====]
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
 modified=modified:sub(1,a-1)..'-- BEC_V1_UI_INITIALIZE_V1: new live-inventory session.\nlocal function cacheResetWorker()\n'..[====[-- BEC_V1_INITIALIZE_V1: explicitly abandon old bookkeeping and rebase on live hardware.
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local clock=require('computer');local event=require('event')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d';local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0';local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local JOURNAL='/home/bec_auto.journal'
local paths={JOURNAL,'/home/bec_cache.journal',JOURNAL..'.failed-reset','/home/bec_cache.reset','/home/bec_cache.abandon'}
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'初始化文件回读失败: '..p)end
local function integer(n)assert(type(n)=='number' and n>=0 and n%1==0,'实物数量不可读');return n end
local function same(a,b)for k,v in pairs(a)do if (b[k]or 0)~=v then return false end end;for k,v in pairs(b)do if (a[k]or 0)~=v then return false end end;return true end
local function stock()local t=call(FIELD,'getStoredCondensate');assert(type(t)=='table');local out={};for k,v in pairs(t)do out[k]=integer(v)end;return out end
local function rawStock()local rows=call(SUB,'getFluidsInNetwork');assert(type(rows)=='table');local out={}
 for _,row in pairs(rows)do local n=integer(row.amount or row.size or 0);if n>0 then assert(type(row.name)=='string');out[row.name]=(out[row.name]or 0)+n end end;return out end
local function snapshot()return {field=stock(),raw=rawStock(),required=call(NODE,'getRequiredCondensate'),consumed=call(NODE,'getConsumedCondensate')}end
local function tick()local _,_,ch=event.pull(.25,'key_down');assert(ch~=113 and ch~=81,'已退出初始化；记录备份和实物保留，再按Z从现场重新初始化')end
local audit,auditPath,armed
local function save(stage)audit.stage=stage;write(auditPath,ser.serialize(audit,false))end
local function guard()
 assert(call(RS,'getOutput',1)==15,'初始化暂停信号被改变')
 local state=call(NODE,'getState')
 assert(state=='idle' or state=='paused-immediate' or state=='assembler-offline' or state=='unpowered' or state=='nanite-tier-too-low','传送节点尚未确认停稳')
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do assert(call(MAIN,'getFluidInterfaceConfiguration',slot)==nil,'初始化期间供液配置被其他程序改变')end
end
local function main()
 local n=1
 while true do
  local occupied=fs.exists('/home/bec_initialize-'..n..'.dat')
  for _,p in ipairs(paths)do occupied=occupied or fs.exists(p..'.before-initialize-'..n) or fs.exists(p..'.retired-initialize-'..n) end
  if not occupied then break end;n=n+1
 end
 auditPath='/home/bec_initialize-'..n..'.dat'
 audit={version=1,kind='explicit-initialization',reason='user-reinitialize-unsubmitted-supply',files={},stage='backing-up'}
 -- Preserve original bytes, including corrupt or stale records. They are not runtime authority.
 for _,p in ipairs(paths)do local text=read(p);if text then
  local backup=p..'.before-initialize-'..n;write(backup,text)
  audit.files[#audit.files+1]={path=p,backup=backup,retired=p..'.retired-initialize-'..n}
 end end
 save('backed-up')
 assert(call(GEN,'getName')=='multi.bec.generator','纠缠装置地址不符')
 armed=true;call(RS,'setOutput',1,15);assert(call(RS,'getOutput',1)==15)
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do
  if call(MAIN,'getFluidInterfaceConfiguration',slot)~=nil then assert(call(MAIN,'setFluidInterfaceConfiguration',slot)==true,'清除供液配置失败')end
 end
 save('settling');print('初始化：已归档旧运行记录，等待机器当前转换完成。')
 while call(GEN,'isMachineActive')==true do guard();tick()end
 guard()
 -- A second stopped reading catches an API read that crossed a machine update.
 local before=snapshot();tick();guard();local current=snapshot()
 while not same(before.field,current.field) or not same(before.raw,current.raw)do
  before=current;tick();guard();current=snapshot()
 end
 audit.before=current;save('reading-live-inventory')
 -- The old equality assertion incorrectly counted input consumed by an active recipe as lost.
 -- Keep its expected/actual differences for diagnosis, but do not reuse that checkpoint.
 local checkpoint=read(JOURNAL..'.failed-reset')
 if checkpoint then
  local ok,old=pcall(ser.unserialize,checkpoint)
  if ok and type(old)=='table' then audit.previousExpected=old.expected end
 end
 local previous=current.raw;local lastProgress=clock.uptime();local lastMessage=-math.huge
 if next(current.raw)then
  save('draining-existing-material');call(GEN,'setWorkAllowed',true);assert(call(GEN,'isWorkAllowed')==true)
  print('初始化：转换子网现有原液；转换过程中等待产物入库，不按旧账判定缺料。')
  while true do
   guard();local active=call(GEN,'isMachineActive');local raw=rawStock()
   if not same(previous,raw) or active then previous=raw;lastProgress=clock.uptime()end
   if next(raw)==nil and active==false then break end
   if clock.uptime()-lastMessage>=5 then
    local total=0;for _,v in pairs(raw)do total=total+v end
    print('初始化：余液 '..total..' mB；'..(active and '转换正在进行，等待产物' or '等待纠缠装置处理余液'))
    lastMessage=clock.uptime()
   end
   if not active and clock.uptime()-lastProgress>=30 then
    audit.observed=snapshot();save('converter-not-processing')
    local rows={};for rawName,amount in pairs(raw)do rows[#rows+1]=rawName..' '..amount..' mB'end;table.sort(rows)
    error('纠缠装置30秒未处理余液：'..table.concat(rows,'；')..'；检查供电/输入仓/转换批量，再按Z')
   end
   tick()
  end
 end
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 while call(GEN,'isMachineActive')==true do guard();tick()end
 local after=snapshot();tick();guard();local stable=snapshot()
 while not same(after.field,stable.field) or not same(after.raw,stable.raw)do after=stable;tick();guard();stable=snapshot()end
 assert(next(stable.raw)==nil,'还有未转换余液，尚未重新投料')
 audit.after=stable;save('ready-to-reinitialize')
 -- Retire all old supply/cache/reset states. Settings, recipes, addresses and item IO stay intact.
 for _,entry in ipairs(audit.files)do
  assert(read(entry.path)==read(entry.backup),'初始化期间记录被其他程序改写: '..entry.path)
 end
 local fresh={version=1,kind='continuous',stage='watching',configOwned=false,requests={},transfers={},target={},
  initialized={audit=auditPath,reason='explicit-live-inventory-rebase'}}
 local freshText=ser.serialize(fresh,false);local temp=JOURNAL..'.initialize-new-'..n;write(temp,freshText)
 for _,entry in ipairs(audit.files)do
  if entry.path~=JOURNAL then assert(fs.rename(entry.path,entry.retired),'旧状态归档失败: '..entry.path);assert(read(entry.retired)==read(entry.backup))end
 end
 local oldEntry;for _,entry in ipairs(audit.files)do if entry.path==JOURNAL then oldEntry=entry end end
 if oldEntry then assert(fs.rename(JOURNAL,oldEntry.retired),'旧生产状态归档失败')end
 if not fs.rename(temp,JOURNAL)then
  if oldEntry then assert(fs.rename(oldEntry.retired,JOURNAL),'原生产记录还原失败')end
  error('新状态安装失败；再次按Z初始化')
 end
 assert(read(JOURNAL)==freshText,'新生产状态回读失败')
 save('done');armed=false
 print('初始化完成：旧生产/缓存/重置状态已归档；按当前配方和实际库存重新投料。')
 print('现场诊断记录：'..auditPath)
end
local ok,why=xpcall(main,debug.traceback)
if armed then pcall(call,GEN,'setWorkAllowed',false)end
if not ok then print('初始化待处理: '..tostring(why))end
return ok,why
]====]..'\nend\n'..modified:sub(z)
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
