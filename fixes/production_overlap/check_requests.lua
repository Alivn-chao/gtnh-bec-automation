-- Read-only diagnosis for a submitted AE request surviving a UI/controller exit.
local c=require('component');local ser=require('serialization')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d'
local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0'
local function show(label,value)print(label..': '..ser.serialize(value,false))end
local f=assert(io.open('/home/bec_auto.journal','r'),'production journal missing')
local contents=f:read('*a');f:close()
local old=assert(ser.unserialize(contents),'journal unreadable');assert(type(old)=='table')
print('BEC REQUEST CHECK - READ ONLY')
show('journal',{stage=old.stage,pending=old.pending,configOwned=old.configOwned})
local wanted,unfinished={},0
for i,job in ipairs(old.requests or {})do
 if job.state~='done' then
  unfinished=unfinished+1
  if type(job.raw)=='string' then wanted[job.raw]=true end
  show('request '..i,{raw=job.raw,amount=job.amount,state=job.state,securedBefore=job.securedBefore})
 end
end
show('unfinished requests',unfinished)
local function inventory(address)
 local rows=c.invoke(address,'getFluidsInNetwork');assert(type(rows)=='table','inventory unreadable')
 local result={}
 for _,row in pairs(rows)do
  assert(type(row)=='table','invalid inventory row')
  if wanted[row.name] then
   local n=row.amount or row.size;assert(type(n)=='number' and n>=0,'invalid fluid amount')
   result[row.name]=(result[row.name] or 0)+n
  end
 end
 return result
end
local main,sub=inventory(MAIN),inventory(SUB)
local stock=c.invoke(FIELD,'getStoredCondensate');assert(type(stock)=='table','field unreadable')
local p=old.pipeline or {}
for _,item in ipairs(old.plan or {})do
 if wanted[item.raw] then
  local initial=(p.initial or {})[item.raw] or 0
  local delivered=(p.delivered or {})[item.raw] or 0
  show('supply '..item.raw,{planned=item.amount,initial=initial,confirmedDelivered=delivered,
   uncollected=type(item.amount)=='number' and item.amount-initial-delivered or nil,
   main=main[item.raw] or 0,sub=sub[item.raw] or 0,field=stock[item.name] or 0})
 end
end
local cpus=c.invoke(MAIN,'getCpus');assert(type(cpus)=='table','CPU status unreadable')
local busy,matched,unknown,total=0,0,0,0
for index,cpu in pairs(cpus)do
 total=total+1
 if type(cpu)~='table' or type(cpu.busy)~='boolean' then
  unknown=unknown+1;show('CPU unreadable',index)
 elseif cpu.busy then
  busy=busy+1;local hit,errors={},{}
  for _,method in ipairs({'activeItems','pendingItems'})do
   local fn=cpu.cpu and cpu.cpu[method]
   if type(fn)~='function' then errors[#errors+1]=method..' unavailable'
   else
    local ok,rows=pcall(fn)
    if not ok or type(rows)~='table' then errors[#errors+1]=method..' unreadable'
    else
     for _,row in pairs(rows)do
      if type(row)~='table' or type(row.name)~='string' then errors[#errors+1]=method..' invalid row'
      elseif wanted[row.name] then
       hit[#hit+1]={list=method,raw=row.name,amount=row.amount or row.size}
      end
     end
    end
   end
  end
  if #hit>0 then matched=matched+1 end
  if #errors>0 then unknown=unknown+1 end
  if #hit>0 or #errors>0 then show('CPU '..tostring(index),{name=cpu.name,matches=hit,errors=errors})end
 end
end
show('CPU summary',{total=total,busy=busy,matchingRaw=matched,unreadable=unknown})
print('A submitted journal entry is not proof the AE job is still running.')
print('No matching task is not proof of completion/cancellation when task data is unreadable.')
print('No requests, transfers, redstone writes or journal changes performed.')
