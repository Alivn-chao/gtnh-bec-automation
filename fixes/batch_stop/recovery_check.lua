-- Read-only: distinguish idle retained consumption from a genuinely active next recipe.
local c=require('component');local ser=require('serialization')
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local STORAGE='237a9cac-118a-4b74-8755-0d0b0ad216c0'
local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local function show(label,value)print(label..': '..ser.serialize(value,false))end
local function get(address,method)return c.invoke(address,method)end
print('BEC RECOVERY CHECK - READ ONLY')
local state=get(NODE,'getState')
local required=get(NODE,'getRequiredCondensate')
local consumed=get(NODE,'getConsumedCondensate')
local parallel=get(NODE,'getParallelRecipesInProgress')
show('node state',state);show('node parallel',parallel)
show('node required',required);show('node consumed',consumed)
show('pause output',c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1))
local f=assert(io.open('/home/bec_auto.journal','r'),'production journal missing')
local contents=f:read('*a');f:close()
local old=assert(ser.unserialize(contents),'production journal unreadable')
assert(type(old)=='table','invalid production journal')
show('journal stage',old.stage);show('journal required',old.required)
show('journal remaining',old.remaining);show('batch control',old.batchStop)
show('pending transfer',old.pending)
local stock=get(STORAGE,'getStoredCondensate')
assert(type(stock)=='table','field inventory unreadable')
local sub={};local rows=get(SUB,'getFluidsInNetwork')
assert(type(rows)=='table','subnet inventory unreadable')
for _,row in pairs(rows)do
 assert(type(row)=='table' and type(row.name)=='string','invalid subnet row')
 local amount=row.amount or row.size
 assert(type(amount)=='number' and amount>=0,'invalid subnet amount')
 sub[row.name]=(sub[row.name] or 0)+amount
end
show('subnet raw',sub)
local p=old.pipeline
if type(p)=='table' then
 show('pipeline recipe',p.recipe);show('start consumed',p.startConsumed)
 for _,item in ipairs(old.plan or {})do
  local budget=(p.base[item.name] or 0)+(p.initial[item.raw] or 0)+(p.delivered[item.raw] or 0)
  local present=(stock[item.name] or 0)+(sub[item.raw] or 0)
  show(item.name,{budget=budget,field=stock[item.name] or 0,raw=sub[item.raw] or 0,
   loss=budget-present,lastConsumed=type(consumed)=='table' and consumed[item.name] or nil,
   perRecipe=type(p.recipe)=='table' and p.recipe[item.name] or nil})
 end
end
for i,job in ipairs(old.requests or {})do show('request '..i,{raw=job.raw,amount=job.amount,state=job.state})end
if state=='idle' and required==nil and parallel==0 then
 print('IDLE: nonzero consumed may be the retained LAST recipe, not a new recipe.')
else print('ACTIVE: compare required/consumed against the old pipeline before recovery.')end
print('No items/fluids moved; no machine/configuration/journal changed.')
