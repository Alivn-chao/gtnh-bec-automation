-- V1 module: whole-cell transfers through the verified south/north ME IO ports.
local c=require('component')
local ser=require('serialization')
local fs=require('filesystem')
local clock=require('computer')
local T='13070035-3a3f-4468-b896-1c084288fdc9'
local SOUTH='4e31083a-e153-40e4-bf3f-e5ada363819d'
local NORTH='4bfbed4a-5d62-4311-9d34-5761103e76ce'
local PAUSE='266f65b5-20be-4543-8f2f-bfd2d0816611'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local PATH='/home/bec_nanites_io.journal'
local CELL='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'
local DISPLAY_CAP,MIN=30720,64 -- Machine reading limit, not a transfer limit.
-- NaniteTier enum -> material ore name. Labels may be localized.
local tiers={Carbon={1,'Carbon'},Glowstone={1,'Glowstone'},Silver={2,'Silver'},
 Neutronium={2,'Neutronium'},Gold={3,'Gold'},TranscendentMetal={4,'Transcendent'},
 SixPhasedCopper={5,'SixPhasedCopper'},WhiteDwarfMatter={6,'WhiteDwarf'},
 BlackDwarfMatter={7,'BlackDwarf'},Universium={8,'Universium'},Eternity={9,'Eternity'},MagMatter={10,'MagMatter'}}
local record,context
local function call(a,m,...) return c.invoke(a,m,...) end
local function whole(n) return type(n)=='number' and n>=0 and n%1==0 end
local function read(path)
 local f=io.open(path,'r');if not f then return end
 local v=f:read('*a');f:close();return v
end
local function write(path,text)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(path)==text,'蜂群IO日志回读失败')
end
local function oldRecord()
 local text=read(PATH);if not text then return end
 local r=ser.unserialize(text)
 assert(type(r)=='table' and r.version==2 and r.kind=='cell-io','蜂群IO日志损坏，保留现场')
 return r
end
local function save(stage)
 record.stage=stage
 local old=read(PATH);if old then write(PATH..'.previous',old) end
 write(PATH,ser.serialize(record,false))
end
local function archive()
 local old=read(PATH);if not old then return end
 local n=1;while fs.exists(PATH..'.before-run-'..n) do n=n+1 end
 write(PATH..'.before-run-'..n,old)
end
local function needed()
 local v=call(NODE,'getRequiredTier');return type(v)=='table' and v.tier or v
end
local function hive()
 local n=call(NODE,'getAvailableNanites');assert(whole(n),'蜂群仓数量无效')
 local p=call(NODE,'getProvidedTier')
 if n==0 then return 0 end
 assert(type(p)=='table' and whole(p.tier) and type(p.name)=='string','蜂群仓类型不可读')
 return n,p
end
local function guard()
 assert(call(PAUSE,'getOutput',1)==15,'换蜂必须保持传送节点暂停红石15')
 local s=call(NODE,'getState')
 assert(s=='paused-immediate' or s=='nanite-tier-too-low' or
  s=='idle' and call(NODE,'isWorkAllowed')==false,'节点状态不适合换蜂：'..tostring(s))
 assert(needed()==record.requiredTier,'换蜂过程中配方等级变化，保留现场')
 if context and context.check then context.check() end
 if context and context.stopping and context.stopping() then error('换蜂已暂停，保留现场') end
end
local function tick()
 if context and context.tick then context.tick(0.1) else os.sleep(0.1) end
 guard()
end
local function output(a,n)
 call(a,'setOutput',0,n);assert(call(a,'getOutput',0)==n,'IO向下红石回读失败')
end
local function off()
 local a,e=pcall(output,SOUTH,0);local b,f=pcall(output,NORTH,0)
 assert(a and b,'关闭IO红石失败，手动关闭两端：'..tostring(e)..'; '..tostring(f))
end
local function stack(side,slot) return call(T,'getStackInSlot',side,slot) end
local function describe(item)
 assert(type(item)=='table' and item.name==CELL and item.size==1,'蜂群硬盘必须是单个数字奇点')
 assert(whole(item.storedItemCount) and type(item.getAvailableItems)=='table','盘内数量不可读')
 local row
 for _,v in pairs(item.getAvailableItems) do
  assert(not row and type(v.name)=='string' and whole(v.size) and v.size>0 and not v.hasTag,'盘内不能混料或放带NBT蜂群')
  local material
  for _,ore in pairs(v.oreNames or {}) do
   local candidate=type(ore)=='string' and ore:match('^nanite(.+)$')
   if candidate and tiers[candidate] then
    assert(not material or material==candidate,'蜂群矿辞类型不唯一');material=candidate
   end
  end
  -- This exact item was read from, loaded into, and recovered from the real rig.
  if not material and v.name=='gregtech:gt.metaitem.03' and v.damage==4581 then material='TranscendentMetal' end
  assert(material,'未知蜂群，请保留编号和oreNames：'..tostring(v.name)..':'..tostring(v.damage))
  local t=tiers[material]
  row={name=v.name,damage=v.damage or 0,count=v.size,tier=t[1],family=t[2],label=v.label or material}
  row.key=row.name..':'..row.damage
 end
 local n=row and row.count or 0
 assert(n==item.storedItemCount,'盘内数量与清单不一致')
 return n,row
end
local function discover()
 for a,kind in pairs({[T]='transposer',[SOUTH]='redstone',[NORTH]='redstone',[PAUSE]='redstone',[NODE]='bec_io_node'}) do
  assert(c.type(a)==kind,'组件缺失或类型错误：'..a)
 end
 for _,side in ipairs({2,3}) do
  assert(call(T,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort' and call(T,'getInventorySize',side)==12,'南北面应为12槽ME IO端口')
 end
 local size=call(T,'getInventorySize',0)
 assert(whole(size) and size>=1 and size<=1024,'底面硬盘盒不可读或过大')
 for _,a in ipairs({SOUTH,NORTH}) do for side=0,5 do
  assert(call(a,'getOutput',side)==0,'蜂群IO已有红石输出，不能叠加操作')
 end end
 return size
end
local function emptyPorts()
 for _,side in ipairs({2,3}) do for slot=1,12 do
  assert(stack(side,slot)==nil,'蜂群IO已有硬盘，保留未完成操作')
 end end
end
local function bank(size)
 local cells={}
 local ok,rows=pcall(function()
  if c.methods(T).getAllStacks==nil then return end
  local reader=call(T,'getAllStacks',0)
  assert(reader.count()==size,'批量槽数不符')
  local values=reader.getAll();assert(type(values)=='table')
  for index in pairs(values) do assert(whole(index) and index>=1 and index<=size,'批量槽号不符') end
  return values
 end)
 if not ok then rows=nil end
 for slot=1,size do
  local item
  if rows then
   item=rows[slot]
   if type(item)=='table' and item.name==nil then item=nil end
   if item and (item.storedItemCount==nil or type(item.getAvailableItems)~='table') then item=stack(0,slot) end
  else item=stack(0,slot) end
  if item then
   local n,row=describe(item)
   cells[#cells+1]={slot=slot,count=n,item=row,
    empty=n==0 and item.canHoldNewItem==true and (item.remainingItemCount or 0)>0}
  end
 end
 return cells
end
local function pack(cells,key)
 local candidates={}
 for _,disk in ipairs(cells) do
  if disk.item and disk.item.key==key then candidates[#candidates+1]=disk end
 end
 table.sort(candidates,function(a,b) return a.count>b.count or a.count==b.count and a.slot<b.slot end)
 local picked,n={},0
 for _,disk in ipairs(candidates) do picked[#picked+1]=disk;n=n+disk.count end
 return picked,n
end
local function choose(cells,need)
 local seen,best={},nil
 for _,disk in ipairs(cells) do if disk.item and not seen[disk.item.key] then
  local item=disk.item;seen[item.key]=true
  local picked,n=pack(cells,item.key)
  if item.tier>=need and n>=MIN and (not best or item.tier<best.item.tier or item.tier==best.item.tier and n>best.count) then
   best={item=item,count=n,picked=picked}
  end
 end end
 return best
end
local function move(from,to,source,dest,expected,key)
 guard()
 local n,row=describe(stack(from,source))
 assert(n==expected and (not key or row and row.key==key) and stack(to,dest)==nil,'搬盘前槽位/内容变化')
 record.pending={from=from,to=to,source=source,dest=dest,count=expected,key=key}
 save('moving-cell')
 assert(call(T,'transferItem',from,to,1,source,dest)==1,'搬盘返回值未确认，不重试')
 local actual,result=describe(stack(to,dest))
 assert(stack(from,source)==nil and actual==expected and (not key or result and result.key==key),'搬盘后槽位/内容不符，不重试')
 record.pending=nil;save('cell-moved')
end
local function runPort(side,rs,endDisk,endHive,kind,key)
 save('waiting-port');output(rs,15)
 local deadline=clock.uptime()+30
 while true do
  guard()
  local at,n,row
  -- Read stationary output first; input/output readings can straddle an AE tick.
  for slot=7,12 do local item=stack(side,slot);if item then
   assert(not at,'IO输出口出现多张盘');at=slot;n,row=describe(item)
  end end
  if not at then local item=stack(side,1);if item then n,row=describe(item) end end
  local h,p=hive()
  if record.operationTotal then
   assert(not n or n<=record.operationTotal,'盘内数量超出本次目标')
   assert(h<=math.min(record.operationTotal,DISPLAY_CAP),'仓内读数超出本次目标')
  end
  if row then assert(row.family==kind.family and row.tier==kind.tier and (not key or row.key==key),'IO盘内蜂群类型变化') end
  if at then
   output(rs,0)
   local diskOK=endDisk==nil and row and math.min(n,DISPLAY_CAP)==record.beforeReading or n==endDisk
   if diskOK and h==math.min(endHive,DISPLAY_CAP) then
    if h>0 then assert(p.tier==kind.tier and p.name==kind.family,'节点蜂群类型不符') end
    save('port-complete');return at,row
   end
  end
  assert(clock.uptime()<deadline,'IO转移未完成：盘内'..tostring(n)..'，仓内'..h..'；保留现场，不重试')
  tick()
 end
end
local function recover(cells)
 local h,p=hive();assert(h>0,'回收前蜂群已变化')
 local chosen
 for _,disk in ipairs(cells) do if disk.empty then
  if not chosen or record.holding and disk.slot==record.holding.home then chosen=disk end
 end end
 assert(chosen,'缺少可接收新类型的空数字奇点盘，旧蜂群未搬运')
 record.operationTotal=record.holding and record.holding.count or nil
 record.beforeReading=h;save('recovering')
 local known=record.holding and record.holding.key
 move(0,2,chosen.slot,1,0)
 local at,row=runPort(2,NORTH,record.operationTotal,0,{family=p.name,tier=p.tier},known)
 assert(row,'回收盘没有蜂群清单')
 move(2,0,at,chosen.slot,row.count,row.key)
 record.holding=nil;save('recovered')
 print('整盘回收：T'..row.tier..' / '..row.count..' 个，盘槽 '..chosen.slot)
end
local function loadCell(disk)
 local base,p=hive();local item=disk.item
 assert(item and item.count>0,'装入盘没有蜂群')
 if base>0 then assert(record.holding and record.holding.key==item.key and p.name==item.family and p.tier==item.tier,'追加蜂群身份未确认') end
 local actualBase=record.holding and record.holding.count or 0
 assert(base==math.min(actualBase,DISPLAY_CAP),'追加前节点数量变化')
 record.operationTotal=actualBase+item.count;save('loading')
 move(0,3,disk.slot,1,item.count,item.key)
 local at=runPort(3,SOUTH,0,record.operationTotal,item,item.key)
 move(3,0,at,disk.slot,0)
 record.holding={key=item.key,name=item.name,damage=item.damage,tier=item.tier,family=item.family,count=record.operationTotal,home=disk.slot}
 save('loaded')
 print('整盘装入：T'..item.tier..' / 仓内'..record.operationTotal..' 个，空盘槽 '..disk.slot)
end
local M={}
function M.preview()
 local size=discover();local h,p=hive();local cells=bank(size)
 print('蜂群IO：南3装入，北2回收，底0硬盘盒 '..size..' 槽；整盘搬运，数量由放盘控制')
 print('仓内：'..h..' 个 / T'..tostring(p and p.tier)..'；需求T'..tostring(needed()))
 for _,disk in ipairs(cells) do if disk.item then
  print('盘槽 '..disk.slot..'：T'..disk.item.tier..' / '..disk.count..' 个 / '..disk.item.label)
 end end
 local r=oldRecord();print('蜂群IO日志：'..tostring(r and r.stage or '无')..'；旧接口日志不重放')
 emptyPorts()
end
function M.ensure(ctx)
 local need=needed();if not whole(need) or need<1 then return false end
 context=ctx;local size=discover()
 local old=oldRecord();assert(not old or old.stage=='done','旧蜂群IO未完成，保留盘和日志，不自动重放')
 emptyPorts()
 local cells=bank(size);local h,p=hive();local best=choose(cells,need)
 local known=old and old.holding
 -- A saturated node reading cannot prove the current raw quantity. Recover to
 -- read the actual quantity before another operation, even with an old record.
 if not (known and known.count==h and h<DISPLAY_CAP and p and known.family==p.name and known.tier==p.tier) then known=nil end
 local sameFamily=0
 if p then for _,disk in ipairs(cells) do if disk.item and disk.item.family==p.name then sameFamily=sameFamily+disk.count end end end
 local keeping=h>0 and p.tier>=need and h+sameFamily>=MIN and (not best or best.item.tier>=p.tier)
 local extra={}
 if keeping then
  if known then extra=pack(cells,known.key)
  else for _,disk in ipairs(cells) do if disk.item and disk.item.family==p.name then extra={disk};break end end end
  if #extra==0 then return false end
 else assert(best,'硬盘盒缺少满足T'..need..'的至少64个蜂群') end
 if h>0 and (not keeping or not known) then
  local hasEmpty=false;for _,disk in ipairs(cells) do if disk.empty then hasEmpty=true;break end end
  assert(hasEmpty,'缺少可接收新类型的空数字奇点盘，旧蜂群未搬运')
 end
 record={version=2,kind='cell-io',requiredTier=need,holding=known,stage='prepared'}
 guard();archive();save('prepared')
 local ok,result=xpcall(function()
  if h>0 and (not keeping or not known) then recover(cells);cells=bank(size);best=choose(cells,need);assert(best,'回收后没有可装入蜂群') end
  local picked
  if keeping and known then picked=extra else picked=best.picked end
  for _,disk in ipairs(picked) do loadCell(disk) end
  emptyPorts();guard()
  local n,t=hive();assert(n>=MIN and t.tier>=need,'换蜂后数量或等级不足')
  assert(record.holding and math.min(record.holding.count,DISPLAY_CAP)==n and record.holding.family==t.name,'换蜂后身份核对失败')
  save('done');print('蜂群IO完成：T'..t.tier..' / '..n..' 个；节点仍暂停')
  return true
 end,debug.traceback)
 local cut,cutError=pcall(off)
 assert(cut,tostring(cutError));assert(ok,tostring(result)..'\n保留现场，不重试。')
 return result
end
local mode=(...)
if mode=='preview' then M.preview() elseif mode=='test' then M.ensure();M.preview()
elseif mode~=nil then error('用法：preview / test；或由V1控制器加载') end
return M
