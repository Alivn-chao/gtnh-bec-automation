local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original=read(path)
if original:find('BEC_V1_IDLE_RECOVERY_V1:',1,true)then print('空闲末批恢复补丁已安装');return end
assert(original:find('BEC_V1_PRODUCTION_OVERLAP_V3:',1,true),'需要生产并行V3')
assert(original:find('BEC_V1_BATCH_STOP_V1:',1,true),'先安装逐批关机补丁，避免恢复后继续跨批缺料')
local start='if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then'
local a,b=original:find(start,1,true);assert(a and not original:find(start,b+1,true),'流水恢复入口缺失或不唯一')
local finish=assert(original:find('local streaming=',b+1,true),'流水恢复结束入口缺失')
local modified=original:sub(1,a-1)..[==[if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then
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
 -- BEC_V1_IDLE_RECOVERY_V1: Beta 3 keeps the last consumed table when idle.
 local idleRetained=call(NODE,"getState")=="idle" and req==nil and parallel==0
 local sameRecipe=p.recipe and same(normalized,p.recipe)
 local idleAudit
 if idleRetained and p.overlap then
  assert(type(consumed)=="table" and type(old.required)=="table" and type(p.recipe)=="table","空闲末批消耗记录缺失")
  for name,n in pairs(consumed)do
   assert(p.recipe[name]~=nil or integer(n)==0,"空闲消耗有旧配方以外的流体: "..name)
   assert(integer(n)<=integer(old.required[name] or 0),"空闲末批消耗超过已记录需求: "..name)
  end
  idleAudit={kind="idle-retained-consumption",sourceJournal=contents,retainedConsumed=consumed,
   recordedRequired=old.required,field=stock,subnet=sub,missingAgainstRecorded={}}
  for name,n in pairs(old.required)do idleAudit.missingAgainstRecorded[name]=integer(n)-integer(consumed[name] or 0)end
 end
 for _,item in ipairs(old.plan)do
  local raw,name=item.raw,item.name;assert(mapping[name]==raw,"恢复原液映射变化");allowed[raw]=true
  local budget=integer(p.base[name] or 0)+integer(p.initial[raw] or 0)+integer(p.delivered[raw] or 0)
  local loss=budget-integer(stock[name] or 0)-integer(sub[raw] or 0)
  if p.overlap then
   assert(type(p.recipe)=="table" and type(p.startConsumed)=="table" and type(consumed)=="table","并行消耗记录缺失")
   local used=(sameRecipe or idleRetained) and integer(consumed[name] or 0) or 0
   if not sameRecipe and not idleRetained then for _,n in pairs(consumed)do assert(integer(n)==0,"下一配方已有消耗，须核对旧流水")end end
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
 if idleAudit then
  -- The retained batch is separate from fully completed prior recipe units.
  -- Never count its partial consumption as delivered products or replay it.
  idleAudit.completedBeforeRetained=completed
  idleAudit.finalField=field()
  local index=1;while fs.exists(JOURNAL..".idle-recovery-"..index)do index=index+1 end
  local auditPath=JOURNAL..".idle-recovery-"..index
  writeVerified(auditPath,ser.serialize(idleAudit,false))
  print("空闲末批消耗核对通过；之前完整消耗 "..tostring(completed).." 份；末批单独记录: "..auditPath)
  print("末批缺口相对原记录: "..ser.serialize(idleAudit.missingAgainstRecorded,false).."；不伪造成品，不重放旧单。")
 end
 old.stage="watching";old.plan=nil;old.pipeline=nil
 print("并行生产消耗核对通过；已确认余液转换完成，按真实库存继续，不重复下单搬液。")
end
]==]..'\n'..original:sub(finish)
assert(load(modified,'@'..path,'t',_ENV),'恢复补丁语法检查失败')
local function stopped()
 assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先按Q正常退出UI')
 assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
  and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'先等纠缠装置停稳')
end
stopped();assert(read(path)==original,'检查期间控制器变化')
local n=1;while fs.exists(path..'.before-idle-recovery-'..n)or fs.exists(path..'.idle-recovery-new-'..n)do n=n+1 end
local backup,temp=path..'.before-idle-recovery-'..n,path..'.idle-recovery-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified,'临时文件回读失败')
stopped();assert(read(path)==original,'写入期间控制器变化')
assert(fs.rename(path,backup),'控制器备份失败')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'备份还原失败');error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'安装回读失败')
print('空闲末批恢复补丁已安装；备份: '..backup)
print('原日志未修改。恢复时保存末批消耗审计并归档旧流水；继续: lua /home/bec_ui.lua resume')
