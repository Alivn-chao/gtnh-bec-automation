-- Deliberate cache abandonment. No AE request, fluid transfer, or production reset.
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local clock=require('computer');local event=require('event');local sides=require('sides')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d';local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0';local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local CACHE='/home/bec_cache.journal';local CONFIG='/home/bec_cache.config';local PROGRESS='/home/bec_cache.reset'
local mapping={entangled_infinity='molten.infinity',entangled_chromaticglass='molten.chromaticglass',entangled_transcendentmetal='molten.transcendentmetal',entangled_dimshiftedsuperfluid='dimensionallyshiftedsuperfluid',entangled_neutronium='molten.neutronium',entangled_cosmicneutronium='molten.cosmicneutronium',entangled_bedrockium='molten.bedrockium',entangled_celestialtungsten='molten.celestialtungsten',entangled_hypogen='molten.hypogen',entangled_phononmedium='phononmedium',entangled_quarkgluonplasma='quarkgluonplasma',entangled_spacetime='molten.spacetime',entangled_time='molten.temporalfluid',entangled_space='molten.spatialfluid',entangled_cosmicsolder='boundlesscosmicsolder',entangled_mhdcsm='molten.magnetohydrodynamicallyconstrainedstarmatter',entangled_magmatter='molten.magmatter',entangled_universium='molten.universium',entangled_eternity='molten.eternity'}
local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000,entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000}
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(path)local f=io.open(path,'r');if not f then return end local t=f:read('*a');f:close();return t end
local function decode(t)local v=ser.unserialize(t);assert(type(v)=='table','记录不可读');return v end
local function write(path,value)local t=ser.serialize(value,false);local f=assert(io.open(path,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(path)==t,'记录保存回读失败')end
local function backup(path)local t=assert(read(path));local n=1;while fs.exists(path..'.before-reset-'..n)do n=n+1 end
 local dest=path..'.before-reset-'..n;local f=assert(io.open(dest,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(dest)==t);return dest end
local function integer(n)assert(type(n)=='number' and n>=0 and n==math.floor(n),'库存数量无效');return n end
local function same(a,b)for k,n in pairs(a)do if (b[k] or 0)~=n then return false end end for k,n in pairs(b)do if (a[k] or 0)~=n then return false end end return true end
local function stock()assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启');local t=call(FIELD,'getStoredCondensate');assert(type(t)=='table','约束场库存不可读');for _,n in pairs(t)do integer(n)end return t end
local function rawStock()local rows=call(SUB,'getFluidsInNetwork');assert(type(rows)=='table','子网库存不可读');local t={}
 for _,f in pairs(rows)do local n=integer(f.amount or f.size or 0);if n>0 then assert(type(f.name)=='string');t[f.name]=(t[f.name] or 0)+n end end return t end
local function guard()
 assert(call(RS,'getOutput',sides.top)==15,'节点未暂停：请先停止生产')
 local state=call(NODE,'getState');assert(state=='idle' or state=='paused-immediate' or state=='assembler-offline' or state=='unpowered' or state=='nanite-tier-too-low','节点正在运行，不能重置缓存')
 local cpus=call(MAIN,'getCpus');assert(type(cpus)=='table' and next(cpus)~=nil,'AE CPU状态不可读')
 for _,cpu in pairs(cpus)do assert(cpu.busy==false,'AE仍有运行任务或忙闲未知：在ME等待完成或取消后，再按Z')end
 for slot=0,5 do assert(call(MAIN,'getFluidInterfaceConfiguration',slot)==nil,'供液接口仍有配置，不能盲目重置')end
end
local function cfg()local t=decode(assert(read(CONFIG),'缺少缓存配置'));assert(t.version==1 and type(t.target)=='number' and t.target>0 and (t.overrides==nil or type(t.overrides)=='table'),'缓存配置不符');return t end
local function isRaw(name,kind)
 local expected=mapping[kind];if name==expected or name=='fluid.'..expected then return true end
 if kind=='entangled_space' then return name=='spatialfluid' or name=='fluid.spatialfluid' end
 if kind=='entangled_time' then return name=='temporalfluid' or name=='fluid.temporalfluid' end
 return false
end
local armed=false
local function main()
 guard();assert(call(GEN,'getName')=='multi.bec.generator','纠缠装置不符')
 assert(call(GEN,'isWorkAllowed')==false and call(GEN,'isMachineActive')==false,'纠缠装置尚未停机：等待当前工作结束再按Z')
 local productionText=assert(read('/home/bec_auto.journal'),'没有生产记录');local production=decode(productionText)
 assert(production.stage=='cache-working' and production.pending==nil and production.configOwned==false and production.plan==nil,'该错误不是后台缓存中断：重置键不会删除生产订单')
 assert(type(production.requests)=='table' and type(production.transfers)=='table','生产操作记录缺失')
 for _,job in pairs(production.requests)do assert(job.state=='done','生产还有未确认申请')end
 for _,move in pairs(production.transfers)do assert(move.ok==true and move.amount==move.requested,'生产搬料未确认')end
 local cacheText=assert(read(CACHE));local old=decode(cacheText)
 local progressText=read(PROGRESS);local p=progressText and decode(progressText)
 if p then assert(p.kind=='cache-reset' and p.version==1,'重置进度不可读')
  if p.stage=='done' then
   if old.resetRecord==PROGRESS and old.originalJournal==p.cacheBackup then print('本轮缓存已重置，继续核对恢复生产。');return end
   backup(PROGRESS);p=nil
  end
 end
 if not p then
  assert(old.kind=='cache' and old.version==1 and old.background==true,'不是后台缓存记录，未重置')
  assert(old.configOwned==false,'接口供液配置仍归本轮持有，未重置')
  assert(type(old.target)=='table' and next(old.target)~=nil and type(old.requests)=='table' and type(old.transfers)=='table','缓存记录缺失')
  for _,job in pairs(old.requests)do assert(job.state=='submitted' or job.state=='done','AE申请处于不明提交阶段，未重置')end
  for _,move in pairs(old.transfers)do assert(move.ok==true and integer(move.amount)==move.requested,'缓存搬料结果未确认，未重置')end
  local worker=assert(read('/home/bec_cache.lua'));assert(worker:find('BEC_V1_CACHE_CUSTOM_V1',1,true),'缺少单项缓存模块，不能暂停本轮类型')
  cfg();local before=stock();local raw=rawStock();local routes={};local targets={}
  local secured={};for name,n in pairs(old.secured or {})do secured[name]=integer(n)end
  local reconciliation
  if old.pending~=nil then
   local pending=old.pending
   assert(old.stage=='transfer-pending' and type(pending)=='table' and type(pending.raw)=='string' and type(pending.address)=='string' and (pending.from==0 or pending.from==1) and pending.to==5 and integer(pending.amount)>0,'待确认操作不是支持的独立高速口搬液；未重置')
   assert(type(old.secured)=='table','缺少搬液前子网快照')
   local known=false;for _,move in pairs(old.transfers)do if move.raw==pending.raw and move.address==pending.address and move.from==pending.from and move.to==pending.to then known=true end end
   assert(known,'待确认搬液接口没有已确认的同路记录，不能推断结果')
   local base=secured[pending.raw] or 0;local actual=raw[pending.raw] or 0
   assert(actual==base or actual==base+pending.amount,'搬液核对不符：'..pending.raw..'；未搬 '..base..'/整搬 '..(base+pending.amount)..'/实测 '..actual)
   for name,n in pairs(secured)do if name~=pending.raw then assert((raw[name] or 0)==n,'其他子网原液变化：'..name)end end
   for name,n in pairs(raw)do if name~=pending.raw then assert(n==(secured[name] or 0),'出现其他子网原液：'..name)end end
   guard();assert(same(rawStock(),raw),'核对期间子网数量变化，未重置')
   secured[pending.raw]=actual
   reconciliation={raw=pending.raw,before=base,actual=actual,requested=pending.amount,outcome=actual==base and 'not-transferred' or 'transferred'}
   print('待确认搬液已核对：'..pending.raw..'，之前 '..base..'，现在 '..actual..'；不重搬这一笔。')
  end
  for kind,n in pairs(old.target)do assert(mapping[kind],'未知缓存类型：'..tostring(kind));integer(n);targets[kind]=true end
  for name,n in pairs(raw)do
   local kind;for candidate in pairs(targets)do if isRaw(name,candidate)then assert(not kind,'原液对应多种目标');kind=candidate end end
   assert(kind,'子网原液不属于本轮缓存：'..name)
   assert(n%(units[kind] or 144)==0,'子网原液不是完整转换批次：'..name)
   assert(type(old.secured)=='table' and integer(secured[name] or 0)>=n,'子网有日志未确认搬入的原液：'..name)
   routes[name]=kind
  end
  local expected={};for kind,n in pairs(before)do expected[kind]=n end
  for name,n in pairs(raw)do local kind=routes[name];expected[kind]=(expected[kind] or 0)+n end
  p={version=1,kind='cache-reset',stage='prepared',oldCache=cacheText,oldProduction=productionText,before=before,raw=raw,routes=routes,expected=expected,targets=targets,reconciliation=reconciliation,cacheBackup=backup(CACHE),configBackup=backup(CONFIG)}
  write(PROGRESS,p)
 end
 assert(productionText==p.oldProduction,'生产记录已改变，停止重置')
 assert(cacheText==p.oldCache or (old.resetRecord==PROGRESS and old.originalJournal==p.cacheBackup),'缓存记录已改变，停止重置')
 local function conserved(final)
  local live=stock();local raw=rawStock();local total={};for kind,n in pairs(live)do total[kind]=n end
  for name,n in pairs(raw)do local kind=p.routes[name];assert(kind and n<=p.raw[name],'出现额外子网原液');total[kind]=(total[kind] or 0)+n end
  assert(same(total,p.expected),'原液与凝聚物数量不守恒，保留重置进度')
  if final then assert(next(raw)==nil,'子网仍有原液')end return live,raw
 end
 local _,remaining=conserved()
 if next(remaining)~=nil then
  p.stage='converting';write(PROGRESS,p);guard();armed=true
  call(GEN,'setWorkAllowed',true);assert(call(GEN,'isWorkAllowed')==true)
  print('缓存重置：仅转换已搬入的原液，不再申请新料。')
  local deadline=clock.uptime()+600
  while true do
   guard();local live=stock();local raw=rawStock()
   if next(raw)==nil and same(live,p.expected) and call(GEN,'isMachineActive')==false then break end
   assert(clock.uptime()<deadline,'剩余原液转换超时：检查供电后，再按Z接续重置')
   local _,_,ch=event.pull(.25,'key_down');assert(ch~=113 and ch~=81,'用户暂停重置，下次按Z接续')
  end
  call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false);armed=false
 end
 guard();assert(call(GEN,'isMachineActive')==false);local final=conserved(true)
 local config=cfg();config.overrides=config.overrides or {}
 for kind in pairs(p.targets)do config.overrides[kind]=0 end
 write(CONFIG,config)
 local target={};for kind in pairs(p.targets)do target[kind]=final[kind] or 0 end
 write(CACHE,{version=1,kind='cache',background=true,stage='stopped',incomplete=false,configOwned=false,requests={},transfers={},target=target,abandoned=true,resetRecord=PROGRESS,originalJournal=p.cacheBackup})
 p.stage='done';write(PROGRESS,p)
 print('缓存重置完成：旧记录已备份，库存保留；本轮类型已停补，可在C里重新设置。')
end
local ok,err=xpcall(main,debug.traceback)
if armed then pcall(call,GEN,'setWorkAllowed',false)end
if not ok then print('缓存重置停止：'..tostring(err))end
return ok,err
