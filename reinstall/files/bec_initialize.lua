-- BEC_V1_INITIALIZE_V1: explicitly abandon old bookkeeping and rebase on live hardware.
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local clock=require('computer');local event=require('event')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d';local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0';local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local JOURNAL='/home/bec_auto.journal'
local paths={JOURNAL,'/home/bec_cache.journal',JOURNAL..'.failed-reset','/home/bec_cache.reset','/home/bec_cache.abandon'}
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'初始化文件回读失败: '..p)end
local function integer(n)assert(type(n)=='number' and n>=0 and n%1==0,'实物数量不可读');return n end
local function same(a,b)for k,v in pairs(a)do if (b[k]or 0)~=v then return false end end;for k,v in pairs(b)do if (a[k]or 0)~=v then return false end end;return true end
local function stock()local t=call(FIELD,'getStoredCondensate');assert(type(t)=='table');local out={};for k,v in pairs(t)do out[k]=integer(v)end;return out end
local function rawStock()local rows=call(SUB,'getFluidsInNetwork');assert(type(rows)=='table');local out={}
 for _,row in pairs(rows)do local n=integer(row.amount or row.size or 0);if n>0 then assert(type(row.name)=='string');out[row.name]=(out[row.name]or 0)+n end end;return out end
local function snapshot()return {field=stock(),raw=rawStock(),required=call(NODE,'getRequiredCondensate'),consumed=call(NODE,'getConsumedCondensate')}end
local function tick()local _,_,ch=event.pull(.25,'key_down');assert(ch~=113 and ch~=81,'已退出初始化；记录备份和实物保留，再按Z从现场重新初始化')end
local audit,auditPath,armed
local function save(stage)audit.stage=stage;write(auditPath,ser.serialize(audit,false))end
local function guard()
 assert(call(RS,'getOutput',1)==15,'初始化暂停信号被改变')
 local state=call(NODE,'getState')
 assert(state=='idle' or state=='paused-immediate' or state=='assembler-offline' or state=='unpowered' or state=='nanite-tier-too-low','传送节点尚未确认停稳')
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do assert(call(MAIN,'getFluidInterfaceConfiguration',slot)==nil,'初始化期间供液配置被其他程序改变')end
end
local function main()
 local n=1
 while true do
  local occupied=fs.exists('/home/bec_initialize-'..n..'.dat')
  for _,p in ipairs(paths)do occupied=occupied or fs.exists(p..'.before-initialize-'..n) or fs.exists(p..'.retired-initialize-'..n) end
  if not occupied then break end;n=n+1
 end
 auditPath='/home/bec_initialize-'..n..'.dat'
 audit={version=1,kind='explicit-initialization',reason='user-reinitialize-unsubmitted-supply',files={},stage='backing-up'}
 -- Preserve original bytes, including corrupt or stale records. They are not runtime authority.
 for _,p in ipairs(paths)do local text=read(p);if text then
  local backup=p..'.before-initialize-'..n;write(backup,text)
  audit.files[#audit.files+1]={path=p,backup=backup,retired=p..'.retired-initialize-'..n}
 end end
 save('backed-up')
 assert(call(GEN,'getName')=='multi.bec.generator','纠缠装置地址不符')
 armed=true;call(RS,'setOutput',1,15);assert(call(RS,'getOutput',1)==15)
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do
  if call(MAIN,'getFluidInterfaceConfiguration',slot)~=nil then assert(call(MAIN,'setFluidInterfaceConfiguration',slot)==true,'清除供液配置失败')end
 end
 save('settling');print('初始化：已归档旧运行记录，等待机器当前转换完成。')
 while call(GEN,'isMachineActive')==true do guard();tick()end
 guard()
 -- A second stopped reading catches an API read that crossed a machine update.
 local before=snapshot();tick();guard();local current=snapshot()
 while not same(before.field,current.field) or not same(before.raw,current.raw)do
  before=current;tick();guard();current=snapshot()
 end
 audit.before=current;save('reading-live-inventory')
 -- The old equality assertion incorrectly counted input consumed by an active recipe as lost.
 -- Keep its expected/actual differences for diagnosis, but do not reuse that checkpoint.
 local checkpoint=read(JOURNAL..'.failed-reset')
 if checkpoint then
  local ok,old=pcall(ser.unserialize,checkpoint)
  if ok and type(old)=='table' then audit.previousExpected=old.expected end
 end
 local previous=current.raw;local lastProgress=clock.uptime();local lastMessage=-math.huge
 if next(current.raw)then
  save('draining-existing-material');call(GEN,'setWorkAllowed',true);assert(call(GEN,'isWorkAllowed')==true)
  print('初始化：转换子网现有原液；转换过程中等待产物入库，不按旧账判定缺料。')
  while true do
   guard();local active=call(GEN,'isMachineActive');local raw=rawStock()
   if not same(previous,raw) or active then previous=raw;lastProgress=clock.uptime()end
   if next(raw)==nil and active==false then break end
   if clock.uptime()-lastMessage>=5 then
    local total=0;for _,v in pairs(raw)do total=total+v end
    print('初始化：余液 '..total..' mB；'..(active and '转换正在进行，等待产物' or '等待纠缠装置处理余液'))
    lastMessage=clock.uptime()
   end
   if not active and clock.uptime()-lastProgress>=30 then
    audit.observed=snapshot();save('converter-not-processing')
    local rows={};for rawName,amount in pairs(raw)do rows[#rows+1]=rawName..' '..amount..' mB'end;table.sort(rows)
    error('纠缠装置30秒未处理余液：'..table.concat(rows,'；')..'；检查供电/输入仓/转换批量，再按Z')
   end
   tick()
  end
 end
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 while call(GEN,'isMachineActive')==true do guard();tick()end
 local after=snapshot();tick();guard();local stable=snapshot()
 while not same(after.field,stable.field) or not same(after.raw,stable.raw)do after=stable;tick();guard();stable=snapshot()end
 assert(next(stable.raw)==nil,'还有未转换余液，尚未重新投料')
 audit.after=stable;save('ready-to-reinitialize')
 -- Retire all old supply/cache/reset states. Settings, recipes, addresses and item IO stay intact.
 for _,entry in ipairs(audit.files)do
  assert(read(entry.path)==read(entry.backup),'初始化期间记录被其他程序改写: '..entry.path)
 end
 local fresh={version=1,kind='continuous',stage='watching',configOwned=false,requests={},transfers={},target={},
  initialized={audit=auditPath,reason='explicit-live-inventory-rebase'}}
 local freshText=ser.serialize(fresh,false);local temp=JOURNAL..'.initialize-new-'..n;write(temp,freshText)
 for _,entry in ipairs(audit.files)do
  if entry.path~=JOURNAL then assert(fs.rename(entry.path,entry.retired),'旧状态归档失败: '..entry.path);assert(read(entry.retired)==read(entry.backup))end
 end
 local oldEntry;for _,entry in ipairs(audit.files)do if entry.path==JOURNAL then oldEntry=entry end end
 if oldEntry then assert(fs.rename(JOURNAL,oldEntry.retired),'旧生产状态归档失败')end
 if not fs.rename(temp,JOURNAL)then
  if oldEntry then assert(fs.rename(oldEntry.retired,JOURNAL),'原生产记录还原失败')end
  error('新状态安装失败；再次按Z初始化')
 end
 assert(read(JOURNAL)==freshText,'新生产状态回读失败')
 save('done');armed=false
 print('初始化完成：旧生产/缓存/重置状态已归档；按当前配方和实际库存重新投料。')
 print('现场诊断记录：'..auditPath)
end
local ok,why=xpcall(main,debug.traceback)
if armed then pcall(call,GEN,'setWorkAllowed',false)end
if not ok then print('初始化待处理: '..tostring(why))end
return ok,why
