local c=require('component');local fs=require('filesystem');local ser=require('serialization')
local PATH='/home/bec_nanites.lua'
local MARK='BEC_NANITES_BANK_FIRST10_V1'
local PORTMARK='BEC_NANITES_IO_SLOTS_1_7_V1'
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
local function emptyInstallPorts()
 local T='13070035-3a3f-4468-b896-1c084288fdc9'
 for _,side in ipairs({2,3})do
  assert(c.invoke(T,'getInventorySize',side)==12,'IO must have 12 slots')
  for slot=1,12 do assert(c.invoke(T,'getStackInSlot',side,slot)==nil,'Empty both IO ports before installing')end
 end
 for _,rs in ipairs({'4e31083a-e153-40e4-bf3f-e5ada363819d','4bfbed4a-5d62-4311-9d34-5761103e76ce'})do
  for side=0,5 do assert(c.invoke(rs,'getOutput',side)==0,'IO redstone must be zero')end
 end
end
local original=read(PATH)
assert(original:find('M.fastStages=true',1,true),'Current fast nanite module required')
stopped()
if original:find(MARK,1,true) and original:find(PORTMARK,1,true)then print('ALREADY INSTALLED: bank 1..10, IO 1 and 7');return end
local modified=original
local function replace(needle,replacement)
 local a,b=modified:find(needle,1,true);assert(a and not modified:find(needle,b+1,true),'Module source does not match; no files changed')
 modified=modified:sub(1,a-1)..replacement..modified:sub(b+1)
end
if not original:find(MARK,1,true)then replace(old,new)end
if not original:find(PORTMARK,1,true)then
 replace([=[local function emptyPorts()
 for _,side in ipairs({2,3}) do
 local rows=slotSnapshot(side,12)
 for slot=1,12 do
  assert(snapshotStack(rows,side,slot)==nil,'蜂群IO已有硬盘，保留未完成操作')
 end end
end]=],[=[-- BEC_NANITES_IO_SLOTS_1_7_V1: exclusively shuttle one disk through input 1/output 7.
local function emptyPorts()
 for _,side in ipairs({2,3}) do
 for _,slot in ipairs({1,7}) do
  assert(stack(side,slot)==nil,'蜂群IO已有硬盘，保留未完成操作')
 end end
end]=])
 replace([=[  local rows=slotSnapshot(side,12)
  -- Read stationary output first; input/output readings can straddle an AE tick.
  for slot=7,12 do local item=snapshotStack(rows,side,slot);if item then
   assert(not at,'IO输出口出现多张盘');at=slot;n,row=describe(item)
  end end
  if not at then local item=snapshotStack(rows,side,1);if item then n,row=describe(item) end end]=],[=[  -- Output 7 is free before each one-cell operation; read it before input 1.
  local item=stack(side,7)
  if item then at=7;n,row=describe(item) end
  if not at then item=stack(side,1);if item then n,row=describe(item) end end]=])
end
emptyInstallPorts()
assert(load(modified,'@'..PATH,'t',_ENV),'Modified source failed syntax check')
local n=1
while fs.exists(PATH..'.before-first10-'..n)or fs.exists(PATH..'.first10-new-'..n)or fs.exists(PATH..'.first10-failed-'..n)do n=n+1 end
local backup=PATH..'.before-first10-'..n
local temp=PATH..'.first10-new-'..n
write(temp,modified);stopped();emptyInstallPorts();assert(read(PATH)==original,'Source changed during checks')
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
print('INSTALLED: scan chest slots 1..10; IO input 1 and output 7 only.')
print('Keep all other IO slots empty; these ports are exclusively for this controller.')
print('Keep bee disks AND an eligible empty recovery disk within slots 1..10.')
print('BACKUP: '..backup)
