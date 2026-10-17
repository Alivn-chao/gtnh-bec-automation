-- Explicit reconciliation of the old spatialfluid partial-return failure.
-- Does not request/cancel AE jobs. The operator must confirm the original job ended.
local mode,ack,group=...;mode=mode or 'preview';group=tonumber(group)or 1
assert(mode=='preview'or mode=='run','用法: preview / run ae-finished [设备组]')
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local c=require('component');local fs=require('filesystem');local clock=require('computer')
local cfg=C.load();C.validate(cfg,false);local g=assert(cfg.groups[group],'设备组不存在')
local path=C.path('state/group-'..group..'/cache.journal')
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local currentBytes=assert(read(path),'没有缓存日志');local original=currentBytes;local formal=assert(read(C.path('config.dat')))
local old=assert(C.read(path));local resumed
-- Only the pre-transfer recovery checkpoint can be resumed. Any pending move,
-- returned padding receipt or conversion stage remains quarantined.
if old.stage=='reconciling-partial'and old.reconciliation then
 resumed=old
 local archive=old.reconciliation.archive
 assert(type(archive)=='string'and archive:sub(1,#path)==path and archive:sub(#path+1):match('^%.before%-partial%-recovery%-%d+$'),'原日志归档路径无效')
 original=assert(read(archive),'原日志归档缺失');assert(#original==old.reconciliation.originalBytes,'原日志归档长度不符')
 old=assert(C.read(archive))
end
local raw='spatialfluid';local kind='entangled_space';local batch=144
local function whole(n)return type(n)=='number'and n>=0 and n<=2147483647 and n%1==0 end
local function quantity(n)return type(n)=='number'and n>=0 and n<=9007199254740991 and n%1==0 end
local function same(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;for k,v in pairs(b)do if a[k]~=v then return false end end;return true end
local function equal(a,b)if type(a)~='table'or type(b)~='table'then return a==b end;for k,v in pairs(a)do if not equal(v,b[k])then return false end end;for k in pairs(b)do if a[k]==nil then return false end end;return true end
local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
assert(old.version==1 and old.kind=='cache'and old.stage=='transfer-returned'and old.configOwned==false and not old.reconciliation,'仅核对此前空间流体部分返回；其他未确认状态保留')
assert(type(old.plan)=='table'and #old.plan==1 and old.plan[1].raw==raw and old.plan[1].batch==batch,'不是单种空间流体缓存，保留日志')
assert(type(old.target)=='table'and whole(old.target[kind]),'原目标不可读')
for name in pairs(old.target)do assert(name==kind,'原目标包含其他流体，保留日志')end
local pending=assert(old.pending,'没有待核对搬运');local transfers=assert(old.transfers);local last=assert(transfers[#transfers])
assert(pending.raw==raw and whole(pending.amount)and pending.amount>0,'搬运意图无效')
for _,key in ipairs({'raw','address','from','to'})do assert(last[key]==pending[key],'最后回执与搬运意图不对应')end
assert(last.ok==true and whole(last.amount)and last.amount>0 and last.amount<last.requested and last.requested==pending.amount,'不是明确成功的部分返回，禁止猜测恢复')
local before=0
for i=1,#transfers-1 do local t=transfers[i]
 assert(t.raw==raw and t.ok==true and whole(t.amount)and t.amount==t.requested,'前序搬运未完整确认')
 assert(t.address==pending.address and t.from==pending.from and t.to==pending.to,'前序搬运路线不一致')
 before=before+t.amount
end
assert(type(old.secured)=='table'and same(old.secured,{[raw]=before}),'前序回执与已确认库存不一致')
local arrived=before+last.amount
assert(type(old.expected)=='table'and whole(old.expected[raw])and arrived<=old.expected[raw]and old.expected[raw]==old.plan[1].amount,'原计划与回执不一致')
assert(type(old.requests)=='table'and #old.requests<=1,'原AE申请不唯一，需另外核对')
for _,job in ipairs(old.requests)do
 assert(job.raw==raw and whole(job.amount)and(job.state=='submitted'or job.state=='done'or job.state=='rejected'and job.preSubmissionFailed),'原AE申请状态不支持此恢复')
end
local permitted=false;for _,a in ipairs(g.bulkTransposers or {})do if a==pending.address then permitted=true end end
assert(permitted,'原高速口已不在当前绑定内')
local function fluids(address)
 local result={};local rows=c.invoke(address,'getFluidsInNetwork');assert(type(rows)=='table','网络库存不可读')
 for _,f in pairs(rows)do local n=f.amount or f.size or 0;assert(quantity(n),'库存数量无效：'..tostring(f.name)..' / '..tostring(n));if n>0 then assert(type(f.name)=='string','库存流体名称无效');local total=(result[f.name]or 0)+n;assert(quantity(total),'库存合计超出精确整数范围');result[f.name]=total end end
 return result
end
local function field()
 assert(c.invoke(g.storage,'isWorkAllowed')==true,'约束场须保持开启')
 local v=c.invoke(g.storage,'getStoredCondensate');assert(type(v)=='table','凝聚物库存不可读');for _,n in pairs(v)do assert(quantity(n),'凝聚物数量无效')end;return v
end
local function tank(side,i)local t=c.invoke(pending.address,'getFluidInTank',side,i);assert(type(t)=='table','高速口不可读');if type(t[1])=='table'then t=t[i]or t[1]end;return t end
local function port()
 assert(c.invoke(pending.address,'getTankCapacity',pending.from,1)==2147483647 and c.invoke(pending.address,'getTankCount',pending.to)==6,'高速口方向/类型变化')
 assert(tank(pending.from,1).name==raw,'高速口源流体变化')
 for i=1,6 do assert((tank(pending.to,i).amount or 0)==0,'接收接口尚有缓存，等待入网后再核对')end
end
local function guard(converting)
 assert(read(C.path('config.dat'))==formal,'核对期间绑定变化')
 local cohort=C.read(C.path('state/group-'..group..'/cohort.dat'));assert(not cohort or cohort.stage=='stopped','生产批次尚未收尾，保留日志')
 for i,n in ipairs(cfg.nodes)do if n.group==group then
  local production=C.read(C.path('state/node-'..i..'/production.journal'))
  if production then
   assert(production.stage=='stopped'and production.pending==nil and production.configOwned==false,'生产记录未确认，保留日志')
   for _,job in ipairs(production.requests or {})do assert(job.state=='done','生产AE申请未确认，保留日志')end
  end
  assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15 and c.invoke(n.address,'isWorkAllowed')==false,'先Q退出网页，暂停并关闭整组接单')
  local state=c.invoke(n.address,'getState');assert(state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low','节点状态不适合收尾')
 end end
 for _,a in ipairs(g.generators)do
  assert(c.invoke(a,'isWorkAllowed')==converting,'纠缠器工作许可变化')
  if not converting then assert(c.invoke(a,'isMachineActive')==false,'先等待全部纠缠器停机')end
 end
end
guard(false);port()
assert(same(fluids(g.subInterface),{[raw]=arrived}),'实际子网库存不等于前序确认量加最后返回量；未修改日志')
local baseline=field();local padding=(batch-arrived%batch)%batch;local aligned=arrived+padding
local target=copy(baseline);target[kind]=(baseline[kind]or 0)+aligned
assert(quantity(target[kind]),'收尾目标超出范围')
local archive=resumed and resumed.reconciliation.archive
local function recoveryRecord(archive)
 return {version=1,kind='cache',stage='reconciling-partial',configOwned=false,requests={},transfers=transfers,
 target={[kind]=target[kind]},expected={[raw]=aligned},secured={[raw]=arrived},plan={{raw=raw,amount=aligned,batch=batch}},
 reconciliation={archive=archive,originalBytes=#original,originalAERequests=old.requests,operatorConfirmedAEFinished=true,returnedAmount=last.amount,requestedAmount=last.requested,verifiedStock=arrived}}
end
if resumed then assert(equal(resumed,recoveryRecord(archive)),'恢复记录已发生其他操作，不允许重放；保留核对')end
print('回执与实物核对通过：已搬入 '..arrived..'；只补整批余量 '..padding..'；收尾原液合计 '..aligned)
for _,job in ipairs(old.requests)do print('原AE申请 '..job.amount..'，日志状态 '..job.state..'；本工具不会重新下单或取消。')end
if mode=='preview'then print('只读核对结束；原AE任务完成后使用 run ae-finished。');return end
assert(ack=='ae-finished','需先确认原AE任务已完成；用 run ae-finished 收尾，不重下单')
assert((fluids(cfg.mainInterface)[raw]or 0)>=padding,'主网空间流体不足以补齐整批；未开始恢复，不申请AE')
local disk=assert(fs.get(C.ROOT));assert(disk.spaceTotal()-disk.spaceUsed()>=524288+65536,'磁盘不足，未开始恢复；需保留512KiB及日志空间')
assert(read(path)==currentBytes,'核对期间原日志变化')
if not archive then
 local index=1;while fs.exists(path..'.before-partial-recovery-'..index)do index=index+1 end
 archive=path..'.before-partial-recovery-'..index
 local f=assert(io.open(archive,'w'));assert(f:write(original));assert(f:flush());f:close();assert(read(archive)==original,'原日志归档回读失败')
end
assert(read(path)==currentBytes,'归档期间原日志变化')
local record=recoveryRecord(archive)
local function save(stage)record.stage=stage;C.write(path,record)end
local function stopGenerators()for _,a in ipairs(g.generators)do pcall(c.invoke,a,'setWorkAllowed',false)end end
local ok,reason=xpcall(function()
 save('reconciling-partial');local total=arrived;local deadline=clock.uptime()+30
 while total<aligned do
  guard(false);port();assert(same(field(),baseline)and same(fluids(g.subInterface),{[raw]=total}),'补整批前库存变化')
  local amount=aligned-total;assert((fluids(cfg.mainInterface)[raw]or 0)>=amount,'主网空间流体不足以补齐整批；不申请AE，保留恢复记录')
  record.pending={raw=raw,amount=amount,address=pending.address,from=pending.from,to=pending.to};save('recovery-transfer-pending')
  local accepted,moved=c.invoke(pending.address,'transferFluid',pending.from,pending.to,amount)
  local row={raw=raw,address=pending.address,from=pending.from,to=pending.to,requested=amount,ok=accepted,amount=moved}
  record.transfers[#record.transfers+1]=row;save('recovery-transfer-returned')
  assert(accepted==true and whole(moved)and moved<=amount,'补整批回执未确认，保留现场，不重试')
  total=total+moved;local untilAt=clock.uptime()+10
  while not same(fluids(g.subInterface),{[raw]=total})do guard(false);assert(clock.uptime()<untilAt,'补整批库存未确认，保留现场');os.sleep(.25)end
  if moved==0 then table.remove(record.transfers)end
  record.pending=nil;record.secured={[raw]=total};save('recovery-transfer-confirmed')
  assert(total==aligned or clock.uptime()<deadline,'补整批无进展，保留现场');if total<aligned then os.sleep(.25)end
 end
 guard(false);port();assert(same(field(),baseline)and same(fluids(g.subInterface),{[raw]=aligned}),'转换前库存不符')
 save('recovery-converting')
 for _,a in ipairs(g.generators)do c.invoke(a,'setWorkAllowed',true);assert(c.invoke(a,'isWorkAllowed')==true,'纠缠器开启回读失败')end
 local deadline=clock.uptime()+180+math.ceil(aligned/batch)*180
 while true do
  guard(true);local stock=field();local sub=fluids(g.subInterface)
  if same(stock,target)and next(sub)==nil then break end
  assert((stock[kind]or 0)<=target[kind],'转换超过核对目标，保留现场')
  for name,value in pairs(stock)do if name~=kind then assert(value==baseline[name],'其他凝聚物库存变化')end end
  assert(clock.uptime()<deadline,'收尾转换超时，保留恢复记录');os.sleep(.25)
 end
 stopGenerators();local deadline=clock.uptime()+10
 while true do local stopped=true;for _,a in ipairs(g.generators)do if c.invoke(a,'isMachineActive')then stopped=false end end;if stopped then break end;assert(clock.uptime()<deadline,'纠缠器尚未停机');os.sleep(.25)end
 guard(false);assert(same(field(),target)and next(fluids(g.subInterface))==nil,'最终收尾库存不符')
 record.expected={};record.secured={};record.plan=nil;record.pending=nil;record.incomplete=false;record.reconciliation.finalStock=target[kind]
 save('stopped')
end,debug.traceback)
if not ok then stopGenerators();error(tostring(reason)..'\n原日志及恢复记录保留，不要删除重跑。')end
print('缓存收尾核对完成；原日志保留：'..archive)
print('未重新申请AE。请重新打开网页；原缓存目标保留，可继续样板处理或补库。')
