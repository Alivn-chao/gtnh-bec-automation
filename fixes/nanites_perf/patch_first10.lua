local c=require('component');local fs=require('filesystem');local ser=require('serialization')
local PATH='/home/bec_nanites.lua'
local MARK='BEC_NANITES_BANK_FIRST10_V1'
local old=[=[local function bank(size)
 local cells={}
 local rows=slotSnapshot(0,size)
 for slot=1,size do
  local item=snapshotStack(rows,0,slot)
  if item then
   local n,row=describe(item)
   cells[#cells+1]={slot=slot,count=n,item=row,
    empty=n==0 and item.canHoldNewItem==true and (item.remainingItemCount or 0)>0}
  end
 end
 return cells
end]=]
local new=[=[-- BEC_NANITES_BANK_FIRST10_V1: only physical slots 1..10 belong to the bee bank.
local function bank(size)
 local cells={}
 for slot=1,math.min(size,10) do
  local item=stack(0,slot)
  if item then
   local n,row=describe(item)
   cells[#cells+1]={slot=slot,count=n,item=row,
    empty=n==0 and item.canHoldNewItem==true and (item.remainingItemCount or 0)>0}
  end
 end
 return cells
end]=]
local function read(path)
 local f=assert(io.open(path,'r'));local text=f:read('*a');f:close();return text
end
local function write(path,text)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close();assert(read(path)==text,'Read-back failed')
end
local function stopped()
 assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'Exit UI with Q first')
 local gen='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
 assert(c.invoke(gen,'isWorkAllowed')==false and c.invoke(gen,'isMachineActive')==false,'Wait for generator to stop')
 local journal='/home/bec_nanites_io.journal'
 if fs.exists(journal)then
  local r=ser.unserialize(read(journal));assert(type(r)=='table' and r.stage=='done','Recover the failed cell move before installing')
 end
 local T='13070035-3a3f-4468-b896-1c084288fdc9'
 local size=c.invoke(T,'getInventorySize',0);local name=c.invoke(T,'getInventoryName',0)
 assert(type(size)=='number' and size>=10 and size<=54 and name~='gt.blockmachines','Use a small ordinary chest below the transposer')
end
local original=read(PATH)
assert(original:find('M.fastStages=true',1,true),'Current fast nanite module required')
stopped()
if original:find(MARK,1,true)then print('ALREADY INSTALLED: bee bank slots 1..10');return end
local a,b=original:find(old,1,true);assert(a and not original:find(old,b+1,true),'Bank source does not match; no files changed')
local modified=original:sub(1,a-1)..new..original:sub(b+1)
assert(load(modified,'@'..PATH,'t',_ENV),'Modified source failed syntax check')
local n=1
while fs.exists(PATH..'.before-first10-'..n)or fs.exists(PATH..'.first10-new-'..n)or fs.exists(PATH..'.first10-failed-'..n)do n=n+1 end
local backup=PATH..'.before-first10-'..n
local temp=PATH..'.first10-new-'..n
write(temp,modified);stopped();assert(read(PATH)==original,'Source changed during checks')
assert(fs.rename(PATH,backup),'Backup rename failed')
local installed=false
local ok,reason=pcall(function()
 assert(fs.rename(temp,PATH),'Install rename failed');installed=true
 assert(read(PATH)==modified and read(backup)==original,'Installed file verification failed')
end)
if not ok then
 if installed then assert(fs.rename(PATH,PATH..'.first10-failed-'..n),'Failed version preservation failed')end
 assert(fs.rename(backup,PATH),'Rollback failed');assert(read(PATH)==original,'Rollback verification failed')
 error('Installation failed; original restored: '..tostring(reason))
end
print('INSTALLED: scan only chest slots 1..10; IO port checks unchanged.')
print('Keep bee disks AND an eligible empty recovery disk within slots 1..10.')
print('BACKUP: '..backup)
