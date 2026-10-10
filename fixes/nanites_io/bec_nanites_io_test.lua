-- Isolated V1 cell-shuttle test. Never starts production or edits old journals.
local c=require('component')
local ser=require('serialization')
local fs=require('filesystem')
local clock=require('computer')
local T='13070035-3a3f-4468-b896-1c084288fdc9'
local SOUTH='4e31083a-e153-40e4-bf3f-e5ada363819d'
local NORTH='4bfbed4a-5d62-4311-9d34-5761103e76ce'
local PAUSE='266f65b5-20be-4543-8f2f-bfd2d0816611'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local PATH='/home/bec_nanites_io_test.journal'
local CELL='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'
local BEE='gregtech:gt.metaitem.03'
local DAMAGE, TIER, MAX=4581,4,30720
local mode,slot=...
slot=tonumber(slot) or 9
mode=mode or 'preview'
assert(mode=='preview' or mode=='load' or mode=='return','用法：preview / load [盘槽] / return [盘槽]')
local record
local function call(a,m,...) return c.invoke(a,m,...) end
local function whole(n) return type(n)=='number' and n>=0 and n%1==0 end
local function read(path)
 local f=io.open(path,'r');if not f then return end
 local text=f:read('*a');f:close();return text
end
local function write(path,text)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(path)==text,'日志回读失败，保持暂停')
end
local function save(stage)
 record.stage=stage
 local old=read(PATH);if old then write(PATH..'.previous',old) end
 write(PATH,ser.serialize(record,false))
end
local function previous()
 local text=read(PATH);if not text then return end
 local r=ser.unserialize(text)
 assert(type(r)=='table' and r.version==1,'测试日志损坏，保留现场')
 return r
end
local function archive()
 local text=read(PATH);if not text then return end
 local n=1;while fs.exists(PATH..'.before-run-'..n) do n=n+1 end
 write(PATH..'.before-run-'..n,text)
end
local function stack(side,index) return call(T,'getStackInSlot',side,index) end
local function cell(item)
 assert(type(item)=='table' and item.name==CELL and item.size==1,'目标必须是单个数字奇点存储盘')
 assert(whole(item.storedItemCount) and type(item.getAvailableItems)=='table','当前驱动不能读取盘内数量')
 local n,types=0,0
 for _,bee in pairs(item.getAvailableItems) do
  assert(bee.name==BEE and bee.damage==DAMAGE and not bee.hasTag,'测试盘只允许T4超时空金属蜂群')
  assert(whole(bee.size) and bee.size>0,'盘内蜂群数量无效')
  n=n+bee.size;types=types+1
 end
 assert(types<=1 and n==item.storedItemCount,'盘内清单与总数量不一致')
 assert(n<=MAX,'盘内超过30720：先限量，不能用红石轮询截断超量')
 return n
end
local function needed()
 local v=call(NODE,'getRequiredTier');return type(v)=='table' and v.tier or v
end
local function held() return call(NODE,'getAvailableNanites') end
local function grade()
 local v=call(NODE,'getProvidedTier');return type(v)=='table' and v.tier or v
end
local function guard(required)
 assert(call(PAUSE,'getOutput',1)==15,'传送节点暂停红石不是15')
 assert(call(NODE,'isWorkAllowed')==false,'节点仍允许生产，先保持停机')
 local state=call(NODE,'getState')
 assert(state=='idle' or state=='paused-immediate' or state=='nanite-tier-too-low','节点状态不适合搬盘：'..tostring(state))
 if required~=nil then assert(needed()==required,'配方蜂群需求已变化，停止搬盘') end
end
local function output(a,n)
 call(a,'setOutput',0,n)
 assert(call(a,'getOutput',0)==n,'IO端口向下红石输出回读失败')
end
local function off()
 -- Attempt both independently, including when one port is disconnected.
 local ok1,e1=pcall(output,SOUTH,0);local ok2,e2=pcall(output,NORTH,0)
 return ok1 and ok2,tostring(e1)..'; '..tostring(e2)
end
local function discover()
 for a,kind in pairs({[T]='transposer',[SOUTH]='redstone',[NORTH]='redstone',[PAUSE]='redstone',[NODE]='bec_io_node'}) do
  assert(c.type(a)==kind,'组件缺失或类型错误：'..a)
 end
 for _,side in ipairs({2,3}) do
  assert(call(T,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort','南北面必须为ME IO端口')
  assert(call(T,'getInventorySize',side)==12,'ME IO端口必须为12槽')
 end
 local size=call(T,'getInventorySize',0)
 assert(whole(size) and size>=slot and slot>=1 and slot%1==0,'底部硬盘盒槽号无效')
 for _,a in ipairs({SOUTH,NORTH}) do
  for side=0,5 do assert(call(a,'getOutput',side)==0,'IO控制端口已有红石输出，请保留现场核对') end
 end
end
local function emptyPorts()
 for _,side in ipairs({2,3}) do
  for index=1,12 do assert(stack(side,index)==nil,'ME IO端口已有硬盘，不能叠加新操作') end
 end
end
local function move(from,to,source,dest,expected)
 guard(record.required)
 assert(cell(stack(from,source))==expected and stack(to,dest)==nil,'搬盘前槽位或盘内数量变化')
 record.pending={from=from,to=to,source=source,dest=dest,count=expected}
 save('moving-cell')
 local n=call(T,'transferItem',from,to,1,source,dest)
 assert(n==1,'搬盘结果未确认，不自动重试')
 assert(stack(from,source)==nil and cell(stack(to,dest))==expected,'搬盘后槽位不符，不自动重试')
 record.pending=nil;save('cell-moved')
end
local function finishPort(side,rs,expectedDisk,expectedHive)
 record.port=side;save('waiting-port')
 output(rs,15)
 local deadline=clock.uptime()+30
 while true do
  guard(record.required)
  local at,n
  for index=1,12 do
   local item=stack(side,index)
   if item then
    assert(not at,'IO端口出现多张盘，停止')
    at=index;n=cell(item)
   end
  end
  assert(at,'IO端口内硬盘丢失，保留现场')
  local h=held();assert(whole(h) and h<=MAX,'蜂群仓数量无效或超限')
  assert(n<=record.count and h<=record.count,'盘内或蜂群仓数量超出本次目标，保持暂停')
  if at>=7 then
   output(rs,0)
   -- Sequential readings may straddle an AE tick or a node-cache update.
   -- An output cell is stationary, so wait for both endpoint counts to agree.
   if n==expectedDisk and h==expectedHive then
    if h>0 then assert(grade()==TIER,'节点蜂群等级不符，保持暂停') end
    record.outputSlot=at;save('port-complete');return at
   end
  end
  assert(clock.uptime()<deadline,'ME IO数量未完成或超时：盘内'..n..'，仓内'..h..'；检查模式、方向与网络，不重试')
  os.sleep(0.1)
 end
end
discover()
local disk=stack(0,slot)
local diskCount=disk and cell(disk)
print('南3装入 / 北2回收 / 底0硬盘盒；两只红石均向下0')
print('硬盘槽 '..slot..'：'..tostring(diskCount)..' 个；蜂群仓：'..tostring(held())..' 个；上限30720')
print('节点：'..tostring(call(NODE,'getState'))..'；需求T'..tostring(needed()))
local old=previous()
if mode=='preview' then
 print('测试日志：'..tostring(old and old.stage or '无')..'；只读，未启停或搬盘')
 return
end
assert(not old or old.stage=='done','旧搬盘测试未完成，保留日志和槽位，不自动重放')
guard();emptyPorts()
local required=needed()
if mode=='load' then
 assert(held()==0,'此轮独立测试要求蜂群仓为空，不在已有蜂群上追加')
 assert(diskCount and diskCount>0,'选中盘没有蜂群')
 assert(whole(required) and required>=1 and required<=TIER,'T4不满足当前配方需求')
else
 assert(old and old.action=='load' and old.slot==slot,'回收只允许上一轮本脚本成功装入的同一槽盘')
 assert(diskCount==0 and held()==old.count and grade()==TIER,'蜂群数量或等级与上一轮装入不符')
end
archive()
record={version=1,action=mode,slot=slot,count=mode=='load' and diskCount or old.count,required=required}
save('prepared')
local ok,err=xpcall(function()
 local side,rs=mode=='load' and 3 or 2,mode=='load' and SOUTH or NORTH
 move(0,side,slot,1,diskCount)
 local endDisk,endHive=mode=='load' and 0 or record.count,mode=='load' and record.count or 0
 local fromSlot=finishPort(side,rs,endDisk,endHive)
 move(side,0,fromSlot,slot,endDisk)
 emptyPorts();guard(record.required)
 assert(cell(stack(0,slot))==endDisk and held()==endHive,'最终数量变化，保留现场')
 save('done')
 print((mode=='load' and '装入完成：' or '回收完成：')..record.count..' 个T4；硬盘回到底部槽 '..slot)
end,debug.traceback)
local stopped,stopError=off()
assert(stopped,'IO红石关闭失败；手动关闭两端，保留日志：'..stopError)
assert(ok,tostring(err)..'\n节点保持暂停；不要重跑、删日志或手动开始生产。')
print('两端红石已归零；未启动生产；旧蜂群/生产/缓存日志均保留。')
