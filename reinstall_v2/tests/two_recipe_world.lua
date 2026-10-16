-- Deterministic hardware world for the real V2 Lua engine/bridge/controllers.
-- Test recipes, not claimed GTNH recipe entries. Component calls cost zero
-- simulated time; hardware and scheduler advance on 50-ms world steps.
world={events={},calls={},outputs={},current=1,readyAt=nil,progress=0,outputSignal=15,
 held=0,heldItem=nil,bank={[9]={tier=4,count=19612,family='Transcendent',material='TranscendentMetal',damage=4581},[10]={tier=5,count=12000,family='SixPhasedCopper',material='SixPhasedCopper',damage=5001}},
 io={[2]={},[3]={}},rs={load=0,ret=0},gen={},sub={},stock={},main={},filters={},cfg=nil}
local W=world
W.recipes={
 {id='A',tier=4,seconds=10,required={entangled_chromaticglass=288,entangled_transcendentmetal=288},output='simulation:product_a'},
 {id='B',tier=5,seconds=15,required={entangled_chromaticglass=576,entangled_infinity=288},output='simulation:product_b'}}
local raw={entangled_chromaticglass='molten.chromaticglass',entangled_transcendentmetal='molten.transcendentmetal',entangled_infinity='molten.infinity'}
local inverse={};for k,v in pairs(raw)do inverse[v]=k;W.main[v]=1000000 end
local CELL='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'
local function copy(v)if type(v)~='table'then return v end;local out={};for k,x in pairs(v)do out[k]=copy(x)end;return out end
local function mark(kind,extra)W.events[#W.events+1]={time=s.now,recipe=W.current,kind=kind,detail=extra}end
function W.recipe()return W.recipes[W.current]end
function W.state()
 if W.finished then return 'idle'end
 if W.held==0 or W.heldItem.tier<W.recipe().tier then return 'nanite-tier-too-low'end
 return W.outputSignal==15 and 'paused-immediate'or 'crafting'
end
local function hardwareTick(dt)
 if W.ioJob and s.now>=W.ioJob.at-1e-8 then
  local j=W.ioJob;local cell=assert(W.io[j.side][1]);W.io[j.side][1]=nil;W.io[j.side][7]=cell
  if j.side==3 then W.held=W.held+cell.count;W.heldItem=copy(cell);cell.count=0
  else cell.tier=W.heldItem.tier;cell.family=W.heldItem.family;cell.material=W.heldItem.material;cell.damage=W.heldItem.damage;cell.count=W.held;W.held=0;W.heldItem=nil end
  W.ioJob=nil;mark('io-complete',j.side==3 and 'load'or 'return')
 end
 if W.conversionAt and s.now>=W.conversionAt-1e-8 then
  for name,amount in pairs(W.sub)do local target=assert(inverse[name]);W.stock[target]=(W.stock[target]or 0)+amount end
  W.sub={};W.conversionAt=nil;mark('condensate-ready')
 end
 if not W.finished and W.started and W.outputSignal==0 then
  W.progress=W.progress+dt
  if W.progress>=W.recipe().seconds-1e-8 then
   for k,n in pairs(W.recipe().required)do assert(W.consumed[k]==n,'output without full consumption')end
   W.outputs[#W.outputs+1]={recipe=W.current,item=W.recipe().output,count=1,time=s.now};mark('product-output',W.recipe().output)
   W.finished=true;W.readyAt=s.now+.05
  end
 end
 -- Smart-blocking example: next different input arrives one tick after output,
 -- while the paused controller finishes its current cohort in that same tick.
 if W.finished and W.current==1 and W.workAllowed~=false and s.now>=W.readyAt-1e-8 and (not CONTROLLED_INPUT or not E.groupOwner[1])then
  W.current=2;W.finished=false;W.started=false;W.progress=0;W.consumed={};W.readyAt=nil;mark('input-ready','different recipe B')
 end
end
W.frame=0
function W.advance(dt)
 local target=s.now+dt
 while (W.frame+1)/20<=target+1e-9 do
  W.frame=W.frame+1;s.now=W.frame/20;hardwareTick(.05)
 end
 s.now=target
end
W.consumed={};mark('input-ready','recipe A ingredients already inserted')
local function stack(cell)
 if not cell then return nil end
 return {name=CELL,size=1,storedItemCount=cell.count,canHoldNewItem=cell.count==0,remainingItemCount=1000000000,
 getAvailableItems=cell.count>0 and {{name='gregtech:gt.metaitem.03',damage=cell.damage,size=cell.count,hasTag=false,oreNames={'nanite'..cell.material},label=cell.material}}or {}}
end
local function rows(inv)local result={};for name,amount in pairs(inv)do if amount>0 then result[#result+1]={name=name,amount=amount}end end;return result end
local c=require('component');local fs=require('filesystem')
-- Explicit spelling avoids Lua's and/or boolean short-circuit type ambiguity.
c.type=function(a)if a=='node1'then return 'bec_io_node'end;if a=='bee'or a=='fluid'or a:match('^bulk')then return 'transposer'end;if a=='load'or a=='ret'or a=='rs1-'then return 'redstone'end;return 'gt_machine'end
c.methods=function()return setmetatable({},{__index=function()return false end})end
c.list=function()
 local items={{'gen1','gt_machine'},{'gen2','gt_machine'},{'gate','bec_diode'},{'node1','bec_io_node'},{'rs1-','redstone'},{'bee','transposer'},{'fluid','transposer'}}
 for i=1,(BULK_COUNT or 5)do items[#items+1]={'bulk'..i,'transposer'}end
 local i=0;return function()i=i+1;if items[i]then return table.unpack(items[i])end end
end
local bulkRaw={'molten.chromaticglass','molten.transcendentmetal','molten.infinity','molten.neutronium','dimensionallyshiftedsuperfluid'}
if BULK_COUNT==10 then
 bulkRaw[3]='molten.cosmicneutronium';bulkRaw[6]='molten.hypogen';bulkRaw[7]='spatialfluid';bulkRaw[8]='temporalfluid';bulkRaw[9]='molten.eternity';bulkRaw[10]='molten.infinity'
end
c.invoke=function(a,m,...)
 local args={...};W.calls[m]=(W.calls[m]or 0)+1
 if a=='node1'then
  if m=='isWorkAllowed'then return W.workAllowed~=false end
  if m=='setWorkAllowed'then W.workAllowed=args[1];mark('node-work-allowed',tostring(args[1]));return true end
  if m=='getState'then if not W.detected or W.detected~=W.current then W.detected=W.current;mark('node-first-read')end;return W.state()end
  if m=='getRequiredCondensate'then return not W.finished and copy(W.recipe().required)or nil end
  if m=='getConsumedCondensate'then return copy(W.consumed)end
  if m=='getParallelRecipesInProgress'then return W.finished and 0 or 1 end
  if m=='getRequiredTier'then return not W.finished and {tier=W.recipe().tier}or nil end
  if m=='getProvidedTier'then return W.held>0 and {tier=W.heldItem.tier,name=W.heldItem.family}or nil end
  if m=='getAvailableNanites'then return math.min(W.held,30720)end
  if m=='getMinParallel'or m=='getMaxParallel'then return 1 end
  if m=='isWorkAllowed'then return false end
 end
 if a=='rs1-'then
  if m=='getOutput'then return W.outputSignal end
  if m=='setOutput'then
   W.outputSignal=args[2]
   if args[2]==0 and not W.started then
    assert(not W.finished and W.held>=64 and W.heldItem.tier>=W.recipe().tier,'bad release')
    for k,n in pairs(W.recipe().required)do assert((W.stock[k]or 0)>=n,'release before condensates');W.stock[k]=W.stock[k]-n end
    W.consumed=copy(W.recipe().required);W.started=true;mark('craft-start')
   end
   return true
  end
 end
 if a=='load'or a=='ret'then
  if m=='getOutput'then return args[1]==0 and W.rs[a]or 0 end
  if m=='setOutput'then
   W.rs[a]=args[2]
   if args[2]==15 then assert(not W.ioJob,'overlapping IO');local side=a=='load'and 3 or 2;assert(W.io[side][1]);W.ioJob={side=side,at=s.now+2};mark('io-start',a)end
   return true
  end
 end
 if a=='bee'then
  if m=='getInventoryName'then return args[1]==0 and 'tile.chest'or 'tile.appliedenergistics2.BlockIOPort'end
  if m=='getInventorySize'then return args[1]==0 and BANK_SIZE or 12 end
  if m=='getStackInSlot'then return stack((args[1]==0 and W.bank or W.io[args[1]])[args[2]])end
  if m=='getAllStacks'then error('scenario: bulk item metadata unavailable')end
  if m=='transferItem'then
   local source=args[1]==0 and W.bank or W.io[args[1]];local dest=args[2]==0 and W.bank or W.io[args[2]]
   assert(args[3]==1 and source[args[4]]and not dest[args[5]],'bad disk move')
   dest[args[5]]=source[args[4]];source[args[4]]=nil;mark('disk-transfer',args[1]..'>'..args[2]);return 1
  end
 end
 if a=='gen1'or a=='gen2'then
  if m=='getName'then return 'multi.bec.generator'end
  if m=='isWorkAllowed'then return W.gen[a]or false end
  if m=='isMachineActive'then return W.conversionAt~=nil end
  if m=='setWorkAllowed'then
   W.gen[a]=args[1]
   if args[1]and next(W.sub)and not W.conversionAt then W.conversionAt=s.now+3;mark('conversion-start')end
   return true
  end
 end
 if a=='gate'then
  if m=='getCondensateFilterCount'then return 9 end
  if m=='getCondensateFilters'then return copy(W.filters)end
  if m=='setCondensateFilters'then W.filters=copy(args[1]);mark('filter-written',table.concat(W.filters,','));return true end
  if m=='isMachineActive'or m=='isWorkAllowed'then return true end
 end
 if a=='field'then if m=='getStoredCondensate'then return copy(W.stock)end;if m=='isWorkAllowed'then return true end end
 if a=='main'or a=='sub'then
  if m=='getFluidsInNetwork'then return rows(a=='main'and W.main or W.sub)end
  if m=='getFluidInterfaceConfiguration'then return nil end
  if m=='setFluidInterfaceConfiguration'then W.cfg=args[2];return true end
  if m=='getCraftables'or m=='getCpus'then return {}end
 end
 if a:match('^bulk')then
  local rawName=bulkRaw[tonumber(a:match('%d+'))]
  if m=='getTankCount'then return args[1]==4 and 1 or args[1]==5 and 6 or 0 end
  if m=='getTankCapacity'then return args[1]==4 and 2147483647 or 16000 end
  if m=='getFluidInTank'then return args[1]==4 and {name=rawName,amount=W.main[rawName]or 1000000}or {amount=0}end
  if m=='transferFluid'then assert(args[1]==4 and args[2]==5);assert((W.main[rawName]or 0)>=args[3]);W.main[rawName]=W.main[rawName]-args[3];W.sub[rawName]=(W.sub[rawName]or 0)+args[3];mark('fluid-transfer',rawName..':'..args[3]);mark('fluid-port',a);return true,args[3]end
 end
 if a=='fluid'then
  if m=='getTankCount'then return 6 end
  if m=='getFluidInTank'then return {amount=0}end
 end
 error('unmodeled component call '..a..' '..m)
end
local exists=fs.exists
fs.exists=function(path)return path==cfg.recipeDirectory or exists(path)end
fs.list=function(path)local names=path==cfg.recipeDirectory and {'a.dat','b.dat'}or {};local i=0;return function()i=i+1;return names[i]end end
cfg.nodes={cfg.nodes[1]};cfg.nodes[1].address='node1';cfg.nodes[1].redstone='rs1-'
cfg.groups[1].bulkTransposers={};for i=1,(BULK_COUNT or 5)do cfg.groups[1].bulkTransposers[i]='bulk'..i end
cfg.groups[1].nanites={enabled=true,mode='cell-io',transposer='bee',loadRedstone='load',returnRedstone='ret',bankSide=0,loadSide=3,returnSide=2,loadOutputSide=0,returnOutputSide=0}
local ser=require('serialization')
for i,r in ipairs(W.recipes)do
 local f={state='converted',outputs={{name=r.output,size=1}},condensates={}}
 for name,amount in pairs(r.required)do f.condensates[#f.condensates+1]={name=name,amount=amount}end
 s.files[cfg.recipeDirectory..'/'..(i==1 and 'a.dat'or 'b.dat')]=ser.serialize(f,false)
end
E=factory(cfg,C,Bridge,false);local log=E.log
E.log=function(i,message)mark('log',message);log(i,message)end

if RPC_LATENCY and RPC_LATENCY>0 then
 local invoke=c.invoke
 c.invoke=function(...)
  local result=table.pack(invoke(...))
  W.advance(RPC_LATENCY)
  return table.unpack(result,1,result.n)
 end
end
