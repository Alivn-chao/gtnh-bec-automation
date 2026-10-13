-- Recover ONLY the verified failed first empty-cell move; never moves items.
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local T='13070035-3a3f-4468-b896-1c084288fdc9'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local PAUSE='266f65b5-20be-4543-8f2f-bfd2d0816611'
local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local SOUTH='4e31083a-e153-40e4-bf3f-e5ada363819d'
local NORTH='4bfbed4a-5d62-4311-9d34-5761103e76ce'
local PATH='/home/bec_nanites_io.journal';local AUTO='/home/bec_auto.journal'
local CELL='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'
local MARK='verified-unmoved-empty-cell-v1'
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(path)
 local f=assert(io.open(path,'r'),'Missing '..path);local s=f:read('*a');f:close();return s
end
local function write(path,s)
 local f=assert(io.open(path,'w'));assert(f:write(s));assert(f:flush());f:close();assert(read(path)==s,'Read-back failed '..path)
end
local function backup(path,s)
 local n=1;while fs.exists(path..'.before-empty-move-recovery-'..n)do n=n+1 end
 local p=path..'.before-empty-move-recovery-'..n;write(p,s);print('BACKUP: '..p)
end
local text=read(PATH);local record=ser.unserialize(text)
assert(type(record)=='table' and record.version==2 and record.kind=='cell-io','Unknown IO journal')
local resumed=record.stage=='done' and record.emptyMoveRecovery and record.emptyMoveRecovery.kind==MARK
local evidence=resumed and record.emptyMoveRecovery.original or record
assert(type(evidence)=='table' and evidence.stage=='moving-cell' and evidence.holding==nil,'Not the first failed recovery move')
local p=evidence.pending
assert(type(p)=='table' and p.from==0 and p.to==2 and p.source==2 and p.dest==1 and p.count==0 and p.key==nil,'Pending move does not match confirmed incident')
assert(call(PAUSE,'getOutput',1)==15,'Exit the controller first (pause must be 15)')
assert(call(GEN,'isWorkAllowed')==false and call(GEN,'isMachineActive')==false,'Generator must be off and inactive')
for _,rs in ipairs({SOUTH,NORTH})do for side=0,5 do assert(call(rs,'getOutput',side)==0,'IO output is not zero')end end
for _,side in ipairs({2,3})do
 assert(call(T,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort' and call(T,'getInventorySize',side)==12,'IO layout changed')
 for slot=1,12 do assert(call(T,'getStackInSlot',side,slot)==nil,'IO contains a disk; recovery refused')end
end
local name=call(T,'getInventoryName',0);local size=call(T,'getInventorySize',0)
assert(type(size)=='number' and size>=2 and size<=54 and name~='gt.blockmachines','Replace the input bus with a small ordinary chest, preserving slots')
local disk=call(T,'getStackInSlot',0,2)
assert(type(disk)=='table' and disk.name==CELL and disk.size==1 and disk.storedItemCount==0 and type(disk.getAvailableItems)=='table' and next(disk.getAvailableItems)==nil,'Slot 2 must still contain the original empty cell')
local count=call(NODE,'getAvailableNanites')
assert(count==evidence.beforeReading,'Hive reading changed; recovery refused')
assert(count==30720,'This recovery is only for the confirmed saturated hive reading')
local autoText=read(AUTO);local auto=ser.unserialize(autoText)
assert(type(auto)=='table','Invalid production journal')
if auto.naniteStage then
 local s=auto.naniteStage;local r=s.required
 assert(type(s)=='table' and s.stage=='switching' and type(r)=='table' and r.name==evidence.requiredFamily and r.tier==evidence.requiredTier,'Controller exchange marker differs from failed operation')
end
-- Recheck both journal files before saving; do not overwrite another controller.
assert(read(PATH)==text and read(AUTO)==autoText,'Journals changed during check; stop other controllers')
if not resumed then
 backup(PATH,text);backup(AUTO,autoText)
 record.pending=nil;record.stage='done'
 record.emptyMoveRecovery={kind=MARK,original=ser.unserialize(text),bankName=name,bankSize=size,hiveReading=count}
 write(PATH,ser.serialize(record,false))
end
if auto.naniteStage then
 if resumed then backup(AUTO,autoText)end
 auto.naniteStage=nil
 write(AUTO,ser.serialize(auto,false))
end
print('RECOVERED: failed empty-cell move was verified unmoved; journals backed up.')
print('No items moved; no machine/redstone/configuration changes. Resume with lua /home/bec_ui.lua resume')
