-- Explicit recovery of OC's known (false, 0) receipt after manual conversion.
-- Does not transfer, order, cancel or convert anything. Keep the original ledger.
local mode,ack,group=...;mode=mode or 'preview';group=tonumber(group)or 1
assert(mode=='preview'or mode=='run','用法: preview / run ae-finished [设备组]')
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))();local cfg=C.load();C.validate(cfg,false)
local c=require('component');local fs=require('filesystem');local clock=require('computer');local g=assert(cfg.groups[group])
local path=C.path('state/group-'..group..'/cache.journal')
local function bytes(p)local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return text end
local original=bytes(path);local formal=bytes(C.path('config.dat'));local old=C.read(path)
local function quantity(n)return type(n)=='number'and n>=0 and n<=9007199254740991 and n%1==0 end
local function same(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;for k,v in pairs(b)do if a[k]~=v then return false end end;return true end
assert(old.version==1 and old.kind=='cache'and old.stage=='transfer-returned'and old.configOwned==false,'不是待核对零搬运；原记录保留')
local pending=assert(old.pending);local ts=assert(old.transfers);local last=assert(ts[#ts])
assert(last.ok==false and last.amount==0 and quantity(last.requested)and last.requested>0,'只接受明确false/0；不猜测未知或部分回执')
for _,key in ipairs({'raw','address','from','to'})do assert(last[key]==pending[key],'回执与意图不符')end
assert(last.requested==pending.amount,'申请量不符')
local permitted=false;for _,a in ipairs(g.bulkTransposers or{})do if a==pending.address then permitted=true end end;assert(permitted,'原供液口绑定变化')
local secured={};for i=1,#ts-1 do local t=ts[i]
 assert(t.ok==true and quantity(t.amount)and t.amount>0 and quantity(t.requested)and t.amount<=t.requested,'前序回执未确认')
 secured[t.raw]=(secured[t.raw]or 0)+t.amount
end
assert(type(old.secured)=='table'and same(secured,old.secured),'已确认量与前序回执不符')
local planned={};for _,v in ipairs(assert(old.plan))do assert(quantity(v.amount)and quantity(v.batch)and v.batch>0);planned[v.raw]=v.amount end
for raw,n in pairs(secured)do assert(planned[raw]and n<=planned[raw],'前序搬运超出计划')end
for _,j in ipairs(old.requests or{})do assert(j.state=='done'or j.state=='submitted'or j.state=='rejected'and j.preSubmissionFailed,'申请状态不支持恢复')end
local function snapshot()
 assert(bytes(C.path('config.dat'))==formal,'核对期间配置变化')
 local cohort=C.read(C.path('state/group-'..group..'/cohort.dat'));assert(not cohort or cohort.stage=='stopped','生产组尚未结束')
 for i,n in ipairs(cfg.nodes)do if n.group==group then
  assert(c.invoke(n.address,'getState')=='idle'and c.invoke(n.address,'isWorkAllowed')==false and c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'整组须空闲、暂停并关闭接单')
  local j=C.read(C.path('state/node-'..i..'/production.journal'));if j then
   assert(j.stage=='stopped'and not j.pending and j.configOwned==false,'生产记录未确认')
   for _,job in ipairs(j.requests or{})do assert(job.state=='done','生产AE请求未确认')end
  end
 end end
 for _,a in ipairs(g.generators)do assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'纠缠器须停机')end
 for slot=0,5 do assert(c.invoke(cfg.mainInterface,'getFluidInterfaceConfiguration',slot)==nil,'主网供液配置未清空')end
 local sub={};for _,v in pairs(c.invoke(g.subInterface,'getFluidsInNetwork'))do local n=v.amount or v.size;assert(quantity(n));if n>0 then sub[v.name]=(sub[v.name]or 0)+n end end
 for raw,n in pairs(sub)do assert(planned[raw]and n<=(secured[raw]or 0),'实际原液超出已确认搬入量')end
 local stock=c.invoke(g.storage,'getStoredCondensate');assert(type(stock)=='table');for _,n in pairs(stock)do assert(quantity(n))end
 return sub,stock
end
local sub,stock=snapshot()
print('零搬运回执确认；按实际原液/凝聚物抵扣，旧申请与搬运不重放。')
if mode=='preview'then print('只读核对结束；须确认所有旧缓存AE申请已结束，再run ae-finished。');return end
assert(ack=='ae-finished','需确认旧缓存AE任务已结束；禁止重复申请')
assert(bytes(path)==original,'原记录变化')
local disk=assert(fs.get(C.ROOT));assert(disk.spaceTotal()-disk.spaceUsed()>524288+#original*3,'恢复日志空间不足')
local index=1;while fs.exists(path..'.before-zero-recovery-'..index)do index=index+1 end
local archive=path..'.before-zero-recovery-'..index
local f=assert(io.open(archive,'w'));assert(f:write(original));assert(f:flush());f:close();assert(bytes(archive)==original)
local again,actual=snapshot();assert(same(sub,again)and same(stock,actual),'归档期间库存变化；原记录保留')
assert(bytes(path)==original)
local repaired={version=1,kind='cache',stage='stopped',background=old.background,configOwned=false,incomplete=true,
 target=old.target,fixedStock=old.fixedStock,copies=old.copies,requests={},transfers={},secured=sub,expected=sub,
 reconciliation={version=1,kind='confirmed-zero-transfer',aeFinishedByOperator=true,archive=archive,originalBytes=#original,
  originalAERequests=old.requests,subnet=sub,stock=stock,at=clock.uptime()}}
C.write(path,repaired)
print('ZERO_RECOVERY_READY; 原记录已归档；下一工作器按实际库存补差，不重放旧搬运/AE申请。')
