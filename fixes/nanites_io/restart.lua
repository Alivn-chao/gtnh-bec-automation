-- Restart only the installed whole-cell nanite exchange after manual ME IO repair.
local mode=(...)or 'restart'
assert(mode=='restart' or mode=='reset' or mode=='check','用法：restart / reset / check')
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local T='13070035-3a3f-4468-b896-1c084288fdc9';local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local PAUSE='266f65b5-20be-4543-8f2f-bfd2d0816611';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local SOUTH='4e31083a-e153-40e4-bf3f-e5ada363819d';local NORTH='4bfbed4a-5d62-4311-9d34-5761103e76ce'
local PATH='/home/bec_nanites_io.journal';local AUTO='/home/bec_auto.journal'
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'写入回读失败: '..p)end
local function decode(text)local t=ser.unserialize(text);assert(type(t)=='table','运行记录不可读');return t end
local function replace(path,expected,text,backup)
 local temp=backup..'.new';local replaced=backup..'.replaced';write(temp,text)
 assert(read(path)==expected,'替换前记录变化: '..path)
 if expected then assert(fs.rename(path,replaced),'原记录归档失败')end
 if not fs.rename(temp,path)then
  if expected then assert(fs.rename(replaced,path),'原记录还原失败')end
  error('状态替换失败，已保留原记录')
 end
 assert(read(path)==text,'状态替换回读失败')
end
local function whole(n)return type(n)=='number'and n>=0 and n%1==0 end
local function hive()
 local n=call(NODE,'getAvailableNanites');assert(whole(n),'蜂群仓读数不可读')
 local p=call(NODE,'getProvidedTier')
 if n>0 then assert(type(p)=='table'and whole(p.tier)and type(p.name)=='string','蜂群仓类型不可读')end
 return {reading=n,tier=n>0 and p.tier or nil,family=n>0 and p.name or nil}
end
local function stopped()
 assert(call(PAUSE,'getOutput',1)==15,'先按Q退出UI，再运行此命令')
 assert(call(GEN,'isWorkAllowed')==false and call(GEN,'isMachineActive')==false,'先等纠缠装置关闭且停稳')
 local state=call(NODE,'getState')
 assert(state=='paused-immediate' or state=='nanite-tier-too-low' or state=='idle' or state=='assembler-offline' or state=='unpowered','节点还在生产，先退出UI暂停')
end
local function ports()
 local occupied={}
 for _,side in ipairs({2,3})do
  assert(call(T,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort'and call(T,'getInventorySize',side)==12,'南北ME IO布局不符')
  for slot=1,12 do
   local item=call(T,'getStackInSlot',side,slot)
   if item then
    local label=(side==2 and '北面回收' or '南面装入')..'IO第'..slot..'槽'
    print(label..'：'..tostring(item.name)..'；盘内数量 '..tostring(item.storedItemCount))
    occupied[#occupied+1]=label
   end
  end
 end
 return occupied
end
local function low()
 for _,rs in ipairs({SOUTH,NORTH})do for side=0,5 do assert(call(rs,'getOutput',side)==0,'ME IO红石未关闭')end end
end
local ownsPorts=false
local function main()
 stopped()
 local ioText=read(PATH);local old=ioText and decode(ioText)
 assert(not old or old.version==2 and old.kind=='cell-io','这不是当前整盘换蜂日志')
 local autoText=read(AUTO);local auto=autoText and decode(autoText)
 if auto and auto.naniteStage then assert(type(auto.naniteStage)=='table'and auto.naniteStage.stage=='switching','不是可重开的阶段换蜂标记')end
 if mode=='check'then
  print('旧换蜂阶段：'..tostring(old and old.stage)..'；蜂群仓读数 '..hive().reading)
  ports();print('只读检查完成；没有重置或搬盘。');return
 end
 -- Backup before changing control outputs. Never replay the old pending move.
 local n=1
 while fs.exists(PATH..'.before-restart-'..n)or fs.exists(AUTO..'.before-bee-restart-'..n)do n=n+1 end
 local backup=PATH..'.before-restart-'..n
 if ioText then write(backup,ioText)end
 if auto and auto.naniteStage then write(AUTO..'.before-bee-restart-'..n,autoText)end
 ownsPorts=true
 for _,rs in ipairs({SOUTH,NORTH})do for side=0,5 do
  if call(rs,'getOutput',side)~=0 then call(rs,'setOutput',side,0)end
 end end
 low()
 local occupied=ports()
 assert(#occupied==0,'两端IO已关闭。请把 '..table.concat(occupied,'、')..' 的盘取回底部箱子前10格，再运行同一命令；旧日志未清除')
 local before=hive();os.sleep(.25);stopped();low()
 assert(#ports()==0,'检查期间端口出现盘，请停止其他搬盘程序')
 local after=hive();assert(before.reading==after.reading and before.tier==after.tier and before.family==after.family,'蜂群仍在变化，等端口停稳再运行')
 assert(read(PATH)==ioText and read(AUTO)==autoText,'检查期间日志变化，请退出其他自动化程序')
 local holding=old and old.holding
 if not(holding and before.reading<30720 and holding.count==before.reading and holding.family==before.family and holding.tier==before.tier)then holding=nil end
 local fresh={version=2,kind='cell-io',stage='done',holding=holding,
  exchangeRestart={kind='manual-restored-ports',backup=ioText and backup or nil,hive=before,
   abandonedStage=old and old.stage,abandonedPending=old and old.pending}}
 replace(PATH,ioText,ser.serialize(fresh,false),backup)
 if auto and auto.naniteStage then auto.naniteStage=nil;replace(AUTO,autoText,ser.serialize(auto,false),AUTO..'.before-bee-restart-'..n)end
 print('蜂群换盘状态已重置；旧记录备份：'..(ioText and backup or '原来没有日志'))
 if mode=='restart'then
  local module=assert(loadfile('/home/bec_nanites.lua','t',_ENV),'找不到已安装蜂群模块')()
  assert(type(module)=='table'and type(module.ensure)=='function','蜂群模块入口不符')
  print('重新读取当前需求和箱内存储盘，开始换蜂。')
  module.ensure({stage=true})
  local current=hive()
  print('换蜂检查完成；蜂群仓读数 '..current.reading..' / T'..tostring(current.tier))
  if current.reading<64 then print('蜂群尚不足64个；把满足当前等级的蜂群盘放在底部箱子前10格，再运行本命令。')end
 end
 print('返回自动化：lua /home/bec_ui.lua resume')
end
local ok,why=xpcall(main,debug.traceback)
if not ok then
 -- The installed module owns any new transfer journal. Only turn its ports off.
 if ownsPorts then for _,rs in ipairs({SOUTH,NORTH})do for side=0,5 do
  pcall(function()if call(rs,'getOutput',side)~=0 then call(rs,'setOutput',side,0)end end)
 end end end
 print('换蜂重开待处理：'..tostring(why))
end
return ok,why
