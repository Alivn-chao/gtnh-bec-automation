-- Explicitly abandon the interrupted spatial cache goal; never replay its AE request.
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local clock=require('computer');local event=require('event');local sides=require('sides')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d';local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0';local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local CACHE='/home/bec_cache.journal';local CONFIG='/home/bec_cache.config';local PROGRESS='/home/bec_cache.abandon'
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(path)local f=io.open(path,'r');if not f then return end local t=f:read('*a');f:close();return t end
local function decode(t)local v=ser.unserialize(t);assert(type(v)=='table','日志/配置不可读');return v end
local function write(path,value)local t=ser.serialize(value,false);local f=assert(io.open(path,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(path)==t,'保存回读不一致')end
local function backup(path)local t=assert(read(path));local n=1;while fs.exists(path..'.before-abandon-'..n)do n=n+1 end
 local dest=path..'.before-abandon-'..n;local f=assert(io.open(dest,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(dest)==t);return dest end
local function integer(n)assert(type(n)=='number' and n>=0 and n==math.floor(n),'数量无效');return n end
local function stock()assert(call(FIELD,'isWorkAllowed')==true,'约束场必须保持开启');local t=call(FIELD,'getStoredCondensate');assert(type(t)=='table');for _,n in pairs(t)do integer(n)end return t end
local function rawAmount()local rows=call(SUB,'getFluidsInNetwork');assert(type(rows)=='table','子网不可读');local total=0
 for _,f in pairs(rows)do local n=integer(f.amount or f.size or 0);if n>0 then assert(f.name=='spatialfluid','子网有其他原液，未重置');total=total+n end end return total end
local function guard()
 assert(call(RS,'getOutput',sides.top)==15,'请先Q停止生产服务')
 local state=call(NODE,'getState');assert(state=='idle' or state=='paused-immediate' or state=='assembler-offline' or state=='unpowered' or state=='nanite-tier-too-low','节点仍在生产，未重置')
 local cpus=call(MAIN,'getCpus');assert(type(cpus)=='table','AE CPU状态不可读，未重置')
 assert(next(cpus)~=nil,'没有读到AE CPU，未重置')
 for _,cpu in pairs(cpus)do assert(type(cpu.busy)=='boolean','AE CPU忙闲未知，未重置');assert(cpu.busy==false,'AE仍有运行任务：先等待完成或在ME取消，再重试')end
 for slot=0,5 do assert(call(MAIN,'getFluidInterfaceConfiguration',slot)==nil,'主网接口仍有供液配置，未重置')end
end
local armed=false
local function main()
 guard();assert(call(GEN,'getName')=='multi.bec.generator','纠缠装置不符')
 assert(call(GEN,'isWorkAllowed')==false and call(GEN,'isMachineActive')==false,'纠缠装置须已停机')
 local production=decode(assert(read('/home/bec_auto.journal')))
 assert(production.stage=='cache-working' and production.pending==nil and production.configOwned==false and production.plan==nil,'不是可放弃的缓存阶段，未重置')
 for _,j in pairs(production.requests or {})do assert(j.state=='done','生产还有未确认订单')end
 local progressText=read(PROGRESS);local p
 if progressText then p=decode(progressText);assert(p.kind=='abandon-space','重置记录不符');if p.stage=='done' then print('本轮补库已放弃，无需再次重置。');return end
 else
  local oldText=assert(read(CACHE));local old=decode(oldText)
  assert(old.kind=='cache' and old.background==true and old.stage=='stream-crafting' and old.pending==nil and old.configOwned==false,'缓存操作阶段不符，未重置')
  assert(type(old.target)=='table' and old.target.entangled_space==5000000 and next(old.target,'entangled_space')==nil,'不是本次500万空间缓存，未重置')
  for name in pairs(old.target)do assert(name=='entangled_space','有其他缓存目标')end
  assert(type(old.requests)=='table' and #old.requests==1 and old.requests[1].raw=='spatialfluid' and old.requests[1].state=='submitted','申请记录不符')
  local secured=0;for _,move in pairs(old.transfers or {})do assert(move.ok==true and move.raw=='spatialfluid' and move.requested==move.amount,'搬料有未确认操作');secured=secured+integer(move.amount)end
  local before=stock();local amount=rawAmount();assert(amount==576 and secured==576 and before.entangled_space==144000,'现场已变化：需要重新核对，未重置')
  local cfgText=assert(read(CONFIG),'缺少缓存配置');local cfg=decode(cfgText);assert(cfg.version==1 and type(cfg.target)=='number' and (cfg.overrides==nil or type(cfg.overrides)=='table'),'缓存配置不符')
  local worker=assert(read('/home/bec_cache.lua'));assert(worker:find('BEC_V1_CACHE_CUSTOM_V1',1,true),'请先安装单项缓存补丁，以免恢复后重复申请500万')
  p={version=1,kind='abandon-space',stage='prepared',before=before,raw=amount,oldCache=oldText,oldProduction=read('/home/bec_auto.journal'),cacheBackup=backup(CACHE),configBackup=backup(CONFIG)}
  write(PROGRESS,p)
 end
 assert(read('/home/bec_auto.journal')==p.oldProduction,'生产记录已改变，停止重置')
 local current=read(CACHE);assert(current==p.oldCache or (decode(current).abandonRecord==PROGRESS),'缓存记录已改变，停止重置')
 local function conserved(final)
  local live=stock();local raw=rawAmount()
  for name,n in pairs(p.before)do if name~='entangled_space' then assert((live[name] or 0)==n,'其他凝聚物变化，停止')end end
  for name,n in pairs(live)do if name~='entangled_space' then assert(n==(p.before[name] or 0),'有额外凝聚物变化，停止')end end
  assert((live.entangled_space or 0)+raw==p.before.entangled_space+p.raw,'空间原液/凝聚物数量不守恒，保留记录')
  if final then assert(raw==0,'子网仍有原液')end return live,raw
 end
 local _,left=conserved();if left>0 then
  p.stage='converting';write(PROGRESS,p);guard();armed=true
  call(GEN,'setWorkAllowed',true);assert(call(GEN,'isWorkAllowed')==true)
  print('放弃500万补库；仅转换已在子网的576mB，不申请新料。')
  local deadline=clock.uptime()+180
  while true do
   guard();local now=stock();local amount=rawAmount()
   if amount==0 and now.entangled_space==p.before.entangled_space+p.raw and call(GEN,'isMachineActive')==false then break end
   assert(clock.uptime()<deadline,'已有576mB转换超时；补充供电后可重试同一脚本')
   local _,_,ch=event.pull(.25,'key_down');assert(ch~=113 and ch~=81,'用户暂停重置，记录保留')
  end
  call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false);armed=false
 end
 guard();assert(call(GEN,'isMachineActive')==false);local final=conserved(true)
 local cfg=decode(assert(read(CONFIG)));cfg.overrides=cfg.overrides or {};cfg.overrides.entangled_space=0;write(CONFIG,cfg)
 -- A new closure record describes deliberate abandonment, not completion of the old AE job.
 write(CACHE,{version=1,kind='cache',background=true,stage='stopped',incomplete=false,configOwned=false,requests={},transfers={},target={entangled_space=final.entangled_space},abandoned=true,abandonRecord=PROGRESS,originalJournal=p.cacheBackup})
 p.stage='done';write(PROGRESS,p)
 print('已放弃本轮目标；空间凝聚物 '..final.entangled_space..'，子网原液0；空间自动缓存已设0。')
 print('旧订单记录备份: '..p.cacheBackup)
 print('继续生产: lua /home/bec_ui.lua resume')
end
local ok,err=xpcall(main,debug.traceback)
if armed then pcall(call,GEN,'setWorkAllowed',false)end
if not ok then print('重置未完成：'..tostring(err));print('原日志/重置记录保留；未申请新料。')end
return ok,err
