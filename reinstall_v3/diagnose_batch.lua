-- Read-only diagnosis. No pause/start, inventory move, AE request or disk write.
local group=tonumber((...))or 1
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local c=require('component');local cfg=C.load();C.validate(cfg,false)
assert(cfg.groups[group],'设备组不存在')
local LIMIT=2147483647
local function read(a,m)
 local ok,v=pcall(c.invoke,a,m);if ok then return v end
 print('READ FAILED '..m..': '..tostring(v));return nil
end
local function number(n)return type(n)=='number'and n>=0 and n%1==0 and n<=9007199254740991 end
local function fmt(n)return string.format('%.0f',n)end
local function ordered(t)local keys={};for k in pairs(t)do keys[#keys+1]=k end;table.sort(keys);return keys end
print('BEC V3 BATCH CHECK / READ ONLY')
print('group='..group..' / per-fluid limit='..fmt(LIMIT)..' mB')
local cohort=C.read(C.path('state/group-'..group..'/cohort.dat'))
local members
if cohort and type(cohort.members)=='table'and #cohort.members>0 then
 members={};for _,i in ipairs(cohort.members)do members[i]=true end
 print('saved cohort='..tostring(cohort.stage)..' / leader='..tostring(cohort.leader))
else print('No saved cohort; showing all bound nodes of this group.')end
local totals,unknown={},false
for i,n in ipairs(cfg.nodes)do if n.group==group and(not members or members[i])then
 local state=read(n.address,'getState');local required=read(n.address,'getRequiredCondensate')
 local used=read(n.address,'getConsumedCondensate');local p=read(n.address,'getParallelRecipesInProgress')
 print('N'..(n.slot or i)..' / '..tostring(state)..' / parallel='..tostring(p))
 if type(required)=='table'and next(required)then
  if type(used)~='table'then unknown=true;print('  consumed unreadable; no remaining estimate')
  else
   local biggest,name=0,nil
   for kind,amount in pairs(required)do
    local consumed=used[kind]or 0
    if not number(amount)or not number(consumed)or consumed>amount then unknown=true;print('  inconsistent getters: '..tostring(kind))
    else local left=amount-consumed;totals[kind]=(totals[kind]or 0)+left
     if left>biggest then biggest=left;name=kind end
     if left>LIMIT then print('  NODE OVER LIMIT '..kind..' = '..fmt(left)..' mB')end
    end
   end
   if name then print('  largest remaining: '..name..' = '..fmt(biggest)..' mB')end
  end
 elseif state~='idle'then unknown=true;print('  requirement unreadable; no estimate')end
end end
print('--- COHORT REMAINING / live getter estimates ---')
local exceeded=false
for _,kind in ipairs(ordered(totals))do
 local amount=totals[kind];print((amount>LIMIT and 'OVER LIMIT 'or 'OK ')..kind..' = '..fmt(amount)..' mB')
 if amount>LIMIT then exceeded=true end
end
if not exceeded then print('No live total above limit; capture original journal/error before changing the batch.')end
if unknown then print('Some reads inconsistent; do not use these estimates to replay transfers.')end
print('No machine state or log was changed. Keep the paused batch and existing journals.')
