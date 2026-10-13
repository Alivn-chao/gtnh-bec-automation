-- BEC_V1_PRODUCTION_RESET_V1: explicit human confirmation that unfinished raw orders never started.
local confirmation=...
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local clock=require('computer');local event=require('event');local sides=require('sides')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d';local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0';local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local JOURNAL='/home/bec_auto.journal';local CHECKPOINT=JOURNAL..'.failed-reset'
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(path)local f=io.open(path,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function decode(s)local v=ser.unserialize(s);assert(type(v)=='table','记录不可读');return v end
local function integer(n)assert(type(n)=='number' and n>=0 and n%1==0,'数量无效');return n end
local function same(a,b)for k,v in pairs(a)do if (b[k] or 0)~=v then return false end end;for k,v in pairs(b)do if (a[k] or 0)~=v then return false end end;return true end
local function writeText(path,s)local f=assert(io.open(path,'w'));assert(f:write(s));assert(f:flush());f:close();assert(read(path)==s,'写入回读失败')end
local function guard()
 assert(call(RS,'getOutput',sides.top)==15,'先按Q退出UI，保持节点暂停')
 local state=call(NODE,'getState')
 assert(state=='idle' or state=='paused-immediate' or state=='assembler-offline' or state=='unpowered' or state=='nanite-tier-too-low','节点仍在运行，不能重置')
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do assert(call(MAIN,'getFluidInterfaceConfiguration',slot)==nil,'供液接口仍有配置，不能重置')end
end
local function stock()local rows=call(FIELD,'getStoredCondensate');assert(type(rows)=='table');for _,n in pairs(rows)do integer(n)end;return rows end
local function rawStock()
 local rows=call(SUB,'getFluidsInNetwork');assert(type(rows)=='table');local out={}
 for _,row in pairs(rows)do local n=integer(row.amount or row.size or 0)
  if n>0 then assert(type(row.name)=='string');out[row.name]=(out[row.name] or 0)+n end
 end
 return out
end
local armed=false
local function main()
 assert(confirmation=='confirmed-not-submitted','只有你确认本轮原液申请未成功，才使用 confirmed-not-submitted')
 guard();assert(call(GEN,'getName')=='multi.bec.generator','纠缠装置不符')
 assert(call(GEN,'isWorkAllowed')==false and call(GEN,'isMachineActive')==false,'先等纠缠装置停稳')
 local original=assert(read(JOURNAL),'没有生产记录');local old=decode(original)
 if old.failedRequestReset and old.stage=='watching' and old.plan==nil and old.pipeline==nil then
  local text=read(CHECKPOINT);local completed=text and decode(text)
  if completed and completed.stage~='done' then
   assert(completed.backup==old.failedRequestReset.backup and read(completed.backup)==completed.sourceJournal,'重置完成记录与原备份不符')
   completed.stage='done';writeText(CHECKPOINT,ser.serialize(completed,false))
  end
  print('这轮未成功原液申请已重置；继续: lua /home/bec_ui.lua resume');return
 end
 assert(old.version==1 and old.kind=='continuous' and type(old.pipeline)=='table' and type(old.plan)=='table','当前不是可接管的生产供液流水')
 assert(old.pending==nil and old.configOwned==false and old.naniteStage==nil,'仍有未确认搬液、接口或换蜂操作，不重置')
 assert(type(old.requests)=='table' and type(old.transfers)=='table' and type(old.target)=='table','操作记录缺失')
 for _,move in pairs(old.transfers)do
  assert(move.ok==true and integer(move.amount)>0 and move.amount==move.requested,'历史搬液未完整确认')
 end
 local allowed={};local p=old.pipeline
 assert(type(p.initial)=='table' and type(p.delivered)=='table','已确认供液数量缺失')
 for _,item in ipairs(old.plan)do
  assert(type(item.raw)=='string' and type(item.name)=='string' and old.target[item.name]~=nil,'供液计划类型不符')
  assert(not allowed[item.raw],'供液计划重复原液')
  allowed[item.raw]={name=item.name,batch=integer(item.batch or 144)}
  assert(allowed[item.raw].batch>0,'转换单位无效')
 end
 local failed,settled={},{}
 for _,job in ipairs(old.requests)do
  assert(type(job)=='table' and allowed[job.raw] and integer(job.amount)>0,'申请记录不符')
  if job.state=='done' then settled[#settled+1]=job
  else
   assert(job.state=='submitted' or (job.state=='rejected' and job.preSubmissionFailed==true),'申请在不明提交阶段，不能当作未下成')
   failed[#failed+1]=job
  end
 end
 assert(#failed>0,'没有待处理的未成功申请，使用正常resume')
 local checkpointText=read(CHECKPOINT);local reset=checkpointText and decode(checkpointText)
 if reset and reset.sourceJournal~=original and reset.stage=='done' then
  local n=1;while fs.exists(CHECKPOINT..'.before-reset-'..n)do n=n+1 end
  writeText(CHECKPOINT..'.before-reset-'..n,checkpointText);reset=nil
 end
 if reset then
  assert(reset.kind=='production-failed-request-reset' and reset.sourceJournal==original,'重置进度属于另一份生产记录，不能复用')
 else
  local before,raw=stock(),rawStock();local expected={}
  for name,n in pairs(before)do expected[name]=n end
  for name,n in pairs(raw)do
   local item=assert(allowed[name],'子网有本轮以外的原液: '..name)
   assert(n%item.batch==0 and n<=integer(p.initial[name] or 0)+integer(p.delivered[name] or 0),'子网原液未确认或不是整批: '..name)
   expected[item.name]=(expected[item.name] or 0)+n
  end
  local index=1
  while fs.exists(JOURNAL..'.before-failed-reset-'..index) or fs.exists(JOURNAL..'.failed-reset-new-'..index)do index=index+1 end
  local backup=JOURNAL..'.before-failed-reset-'..index
  assert(read(JOURNAL)==original,'检查期间生产记录变化')
  writeText(backup,original)
  reset={version=1,kind='production-failed-request-reset',sourceJournal=original,backup=backup,
   confirmation='user-confirmed-not-submitted',requests=failed,before=before,raw=raw,expected=expected,
   required=call(NODE,'getRequiredCondensate'),consumed=call(NODE,'getConsumedCondensate'),stage='prepared'}
  writeText(CHECKPOINT,ser.serialize(reset,false))
 end
 local function conserved()
  local total=stock();local live=rawStock()
  for name,n in pairs(live)do
   local item=assert(allowed[name],'出现额外子网原液')
   assert(n<=integer(reset.raw[name] or 0),'子网原液增加，停止重置')
   total[item.name]=(total[item.name] or 0)+n
  end
  assert(same(total,reset.expected),'转换期间数量不守恒，保留进度')
  return live
 end
 if next(conserved())~=nil then
  reset.stage='converting';writeText(CHECKPOINT,ser.serialize(reset,false));guard()
  armed=true;call(GEN,'setWorkAllowed',true);assert(call(GEN,'isWorkAllowed')==true)
  local deadline=clock.uptime()+1800
  while true do
   guard();local raw=conserved()
   if next(raw)==nil and call(GEN,'isMachineActive')==false then break end
   assert(clock.uptime()<deadline,'已确认余液转换超时，修复供电后重试')
   local _,_,ch=event.pull(.1,'key_down');assert(ch~=113 and ch~=81,'用户停止重置，原记录与进度保留')
  end
  call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false);armed=false
 end
 guard();assert(next(conserved())==nil and call(GEN,'isMachineActive')==false,'余料转换未完成')
 assert(read(JOURNAL)==original,'重置期间生产记录变化')
 old.retainedRequests=old.retainedRequests or {}
 for _,job in ipairs(failed)do old.retainedRequests[#old.retainedRequests+1]={request=job,disposition='user-confirmed-not-submitted'}end
 old.requests=settled;old.stage='watching';old.plan=nil;old.pipeline=nil
 old.failedRequestReset={backup=reset.backup,checkpoint=CHECKPOINT,confirmation='user-confirmed-not-submitted',count=#failed}
 local text=ser.serialize(old,false)
 local temp=reset.backup..'.new';writeText(temp,text)
 local replaced=reset.backup..'.replaced';assert(not fs.exists(replaced),'替换备份已存在，原记录未改')
 assert(read(JOURNAL)==original,'替换前生产记录变化')
 assert(fs.rename(JOURNAL,replaced),'生产记录备份失败')
 if not fs.rename(temp,JOURNAL)then assert(fs.rename(replaced,JOURNAL),'原记录还原失败');error('替换失败，已还原')end
 assert(read(JOURNAL)==text and read(reset.backup)==original and read(replaced)==original,'替换回读失败')
 reset.stage='done';writeText(CHECKPOINT,ser.serialize(reset,false))
 print('已按你的确认放弃 '..#failed..' 笔未成功原液申请；原文备份: '..reset.backup)
 print('没有标记旧申请已完成；已有物料保留，按当前库存重新备料。继续: lua /home/bec_ui.lua resume')
end
local ok,why=xpcall(main,debug.traceback)
if armed then pcall(call,GEN,'setWorkAllowed',false)end
if not ok then print('生产重置停止: '..tostring(why))end
return ok,why
