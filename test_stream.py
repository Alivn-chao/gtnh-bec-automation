"""Inventory-backed streaming mocks; not Minecraft hardware validation."""
import ast
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

def literal(file, name):
    return next(n.value.value for n in ast.parse(Path(file).read_text(encoding='utf-8')).body
                if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == name for t in n.targets))

MOCK = literal('test_auto_once.py', 'MOCK').replace('/home/bec_auto_once.journal', '/home/bec_auto.journal')
EXTRA = "\nlocal c=require('component');local invoke=c.invoke;local previousRequire=require\ns.total=15;s.completed=0;s.active=false;s.progress=0;s.queries=0;s.reserveChecks=0\ns.requests=0;s.craftReady=false\nlocal glass='entangled_chromaticglass';local metal='entangled_transcendentmetal'\nlocal function state()\n if s.now<0.5 or s.completed>=s.total then return 'idle' end\n if s.completed==5 and s.now<20 and not s.simultaneous and not s.appendAt then return 'idle' end\n if not s.active then\n  s.active=true;s.progress=0;s.consumed={}\n  s.group=math.min(s.parallel or 1,s.total-s.completed)\n end\n if s.output==15 then return 'paused-immediate' end\n return 'crafting'\nend\nlocal function queued()\n if s.completed>=s.total then return 0 end\n local finish=s.completed<5 and math.min(s.total,5) or s.total\n if s.completed==5 and s.now<20 and not s.simultaneous and not s.appendAt then return 0 end\n if s.simultaneous then finish=s.total end\n if s.appendAt and s.now>=s.appendAt then finish=s.total end\n return finish-s.completed\nend\nfunction c.invoke(a,m,...)\n local args={...}\n if m=='getFluidsInNetwork' and a:sub(1,2)=='3a' and s.mainStock then\n  local rows={} for name,amount in pairs(s.mainStock) do rows[#rows+1]={name=name,amount=amount} end\n  return rows\n elseif m=='getCpus' then\n  local count=queued()\n  if s.noCpuObject then return {{busy=true},{busy=false}} end\n  local function rows(n)\n   if n==0 then return {} end\n   return {{name='gregtech:gt.metaitem.03',damage=32307,size=n}}\n  end\n  local active=math.min(count,s.group or 1)\n  return {{busy=count>0,cpu={activeItems=function() return rows(active) end,\n   pendingItems=function() return rows(math.max(0,count-active)) end}}, {busy=s.cpuBusy==true}}\n elseif m=='getCraftables' then\n  if s.noRecipe then return {} end\n  local name=args[1].name\n  return {{getStack=function() return {name=name,amount=0,size=0,hasTag=false,isCraftable=true} end,\n   request=function(amount)\n    local record=require('serialization').unserialize(s.files['/home/bec_auto.journal'])\n    assert(record.stage=='craft-request-pending' and record.requests[#record.requests].amount==amount,\n     'missing durable craft intent')\n    s.requests=s.requests+1;s.requestAmount=amount\n    local started=s.now;local supplied=false\n    if s.uncertainCraft then error('uncertain AE request') end\n    if s.nilCraft then return nil,'no controller' end\n    return {isCanceled=function() return s.craftFailed==true,'missing resources' end,\n     isDone=function()\n      if s.craftNeverDone then return false end\n      if s.now-started>=2 then\n       s.shortage=false;s.craftReady=true\n       if s.mainStock and not supplied then\n        if not s.noDelivery then s.mainStock[name]=(s.mainStock[name] or 0)+amount end\n        if s.consumeCredit and not s.creditConsumed then\n         s.mainStock[name]=s.mainStock[name]-s.consumeCredit;s.creditConsumed=true\n        end\n        supplied=true\n       end\n       return true\n      end\n      return false\n     end}\n   end}}\n elseif m=='setOutput' then\n  s.mutations=s.mutations+1;s.output=args[2]\n  if args[2]==0 then\n   -- All outstanding recipe outputs (active + pending) must be fully funded.\n   local consumed=s.consumed[glass] or 0\n   local need=288*math.max(1,queued())-consumed\n   assert(s.stock[glass]>=need and s.stock[metal]>=need,'missing batch fluid')\n   s.reserveChecks=s.reserveChecks+1\n  end\n  return 15\n elseif m=='getState' then return state()\n elseif m=='getProvidedTier' then return {name='Transcendent',tier=4}\n elseif m=='getAvailableNanites' then return 64\n elseif m=='getMinParallel' then return 1\n elseif m=='getMaxParallel' then return s.parallel or 1\n elseif m=='getParallelRecipesInProgress' then return state()=='idle' and 0 or s.group or 1\n elseif m=='getRequiredCondensate' then\n  if state()=='idle' then return nil end\n  if s.foreign and s.completed>=2 then return {entangled_chromaticglass=144} end\n  if s.parallel then return {[glass]=288*s.group,[metal]=288*s.group} end\n  return s.required\n end\n return invoke(a,m,...)\nend\nlocal sleep=os.sleep\nlocal function advance(n)\n sleep(n)\n if s.shortage and s.restockAt and s.now>=s.restockAt then s.shortage=false end\n if s.active and s.output==0 then\n  if (s.consumed[glass] or 0)==0 then\n   local amount=288*(s.group or 1)\n   assert(s.stock[glass]>=amount and s.stock[metal]>=amount,'unprotected request started without stock')\n   s.stock[glass]=s.stock[glass]-amount;s.stock[metal]=s.stock[metal]-amount\n   s.consumed={[glass]=amount,[metal]=amount}\n  end\n  s.progress=s.progress+n\n  if s.progress>=0.5 then s.completed=s.completed+(s.group or 1);s.active=false end\n end\nend\nos.sleep=advance\nfunction require(name)\n if name=='event' then return {pull=function(seconds)\n  advance(seconds);s.queries=s.queries+1\n  if s.completed>=s.total or s.stopEarly or (s.stopAfterRequest and s.requests>0)\n   or s.queries>10000 then return 'key_down','keyboard',113 end\n end} end\n return previousRequire(name)\nend\n"
STREAM = r'''
local c=require('component');local old=c.invoke
s.mainStock={['molten.chromaticglass']=16000,['molten.transcendentmetal']=16000}
s.buffer=0;s.jobs={};s.midJobMoves=0;s.delivered={};s.requestTotals={}
local function fill()
 if s.cfg and not s.timeout then
  local name=s.cfg.name
  local n=math.min(math.max(0,s.cfg.amount-s.buffer),s.mainStock[name] or 0)
  s.mainStock[name]=(s.mainStock[name] or 0)-n;s.buffer=s.buffer+n
 end
end
local function refresh()
 for _,job in ipairs(s.jobs) do
  local fraction=math.min(1,(s.now-job.started)/2)
  local quantity=math.floor(job.amount*fraction/144)*144
  if fraction==1 then quantity=job.amount end
  if s.noDelivery or s.craftNeverDone then quantity=0 end
  local n=quantity-job.delivered
  if n>0 then
   s.mainStock[job.name]=(s.mainStock[job.name] or 0)+n
   s.delivered[job.name]=(s.delivered[job.name] or 0)+n;job.delivered=quantity
  end
 end
 fill()
 if s.competitor then
  for name in pairs(s.mainStock) do s.mainStock[name]=0 end
 end
end
function c.invoke(a,m,...)
 local args={...};refresh()
 if m=='setOutput' and args[2]==0 then
  s.stock.entangled_chromaticglass=s.stock.entangled_chromaticglass or 0
  s.stock.entangled_transcendentmetal=s.stock.entangled_transcendentmetal or 0
 end
 if m=='getFluidInTank' then
  if args[1]==4 and args[2]==1 and s.cfg then return {name=s.cfg.name,amount=s.buffer} end
  return {amount=0}
 elseif m=='setFluidInterfaceConfiguration' then
  if not args[2] and s.cfg then
   s.mainStock[s.cfg.name]=(s.mainStock[s.cfg.name] or 0)+s.buffer;s.buffer=0
  end
  local result=old(a,m,...);fill();return result
 elseif m=='transferFluid' then
  assert(not s.enabled and s.output==15,'generator running during collection')
  assert(args[3]<=s.buffer,'transfer exceeds real inlet inventory')
  for _,job in ipairs(s.jobs) do
   if s.now-job.started<2 then s.midJobMoves=s.midJobMoves+1 end
  end
  local ok,n=old(a,m,...);s.buffer=s.buffer-n
  return ok,n
 elseif m=='getCraftables' then
  if s.noRecipe then return {} end
  local name=args[1].name
  return {{getStack=function() return {name=name,amount=0,size=0,hasTag=false,isCraftable=true} end,
   request=function(amount)
    local record=require('serialization').unserialize(s.files['/home/bec_auto.journal'])
    assert(record.stage=='craft-request-pending' and record.requests[#record.requests].amount==amount)
    s.requests=s.requests+1;s.requestAmount=amount
    s.requestTotals[name]=(s.requestTotals[name] or 0)+amount
    if s.uncertainCraft then error('uncertain AE request') end
    if s.nilCraft then return nil,'no controller' end
    local job={name=name,amount=amount,started=s.now,delivered=0};s.jobs[#s.jobs+1]=job
    return {isCanceled=function() return s.craftFailed==true,'missing resources' end,
     isDone=function() refresh();return not s.craftNeverDone and s.now-job.started>=2 end}
   end}}
 end
 return old(a,m,...)
end
'''
SOURCE=Path('bec_auto.lua').read_text(encoding='utf-8')
passed=0
def run(label, setup='', success=True, mode='run'):
    global passed
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK+EXTRA+STREAM);lua.execute(setup)
    program=lua.eval('function(...) '+SOURCE+'\nend');program(mode)
    s=lua.globals().s;logs=list(s.logs.values())
    assert s.output==15 and s.enabled is False and s.cfg is None,(label,logs)
    if mode=='preview':
        assert s.mutations==0 and s.writes==0,(label,logs)
    else:
        assert any('已停止常驻服务' in x for x in logs)==success,(label,logs)
        if success and not s.stopEarly: assert s.completed==s.total,(label,logs)
        if not success:
            before=(s.moves,s.requests);program('run')
            assert (s.moves,s.requests)==before,(label,'unsafe retry')
    passed+=1;print(label+': PASS');return lua

run('read-only preview',mode='preview')
run('five then ten')
for count in [1,3,15,40,100]:
    run('whole batch '+str(count),f's.total={count};s.simultaneous=true')
for parallel in [2,6,1000]:
    run('actual parallel '+str(parallel),f's.total=10;s.simultaneous=true;s.parallel={parallel}')
run('append another ten','s.appendAt=7')
run('field stock credit','s.stock.entangled_chromaticglass=288;s.stock.entangled_transcendentmetal=288')
empty="s.mainStock={};s.simultaneous=true;s.total=40;"
lua=run('incremental output captured before job done',empty)
s=lua.globals().s
assert s.midJobMoves>0 and s.requests==2
assert s.requestTotals['molten.chromaticglass']==11520
assert s.requestTotals['molten.transcendentmetal']==11520
lua=run('competitor drains unprotected main inventory',empty+'s.competitor=true')
assert lua.globals().s.midJobMoves>0 and lua.globals().s.requests==2
lua=run('real stock and inlet credit',"s.total=1;s.simultaneous=true;s.mainStock={['molten.chromaticglass']=144,['molten.transcendentmetal']=144}")
assert lua.globals().s.requests==2 and lua.globals().s.requestAmount==144
for flag in ['partial','uncertain','timeout','noRecipe','craftFailed','uncertainCraft','nilCraft','craftNeverDone','noDelivery','cpuBusy']:
    run('failure '+flag,empty+'s.queries=-100000;s.'+flag+'=true',success=False)
run('Q retains active request',empty+'s.stopAfterRequest=true',success=False)
run('Q while idle','s.stopEarly=true')
run('foreign recipe remains paused','s.foreign=true',success=False)
for job_state in ['done','submitted']:
    setup="s.now=1;s.total=1;s.simultaneous=true;s.files['/home/bec_auto.journal']=require('serialization').serialize({version=1,kind='continuous',stage='craft-done',configOwned=false,transfers={},required=s.required,remaining=s.required,requests={{raw='molten.chromaticglass',amount=144,state='"+job_state+"'}}},false)"
    run('legacy resume '+job_state,setup,success=job_state=='done',mode='resume')
    if job_state=='done':
        for state in ['assembler-offline','unpowered','nanite-tier-too-low']:
            unavailable="""
local c=require('component');local original=c.invoke
function c.invoke(a,m,...)
 if m=='getState' and s.now<3 then return 'STATE' end
 if m=='transferFluid' or (m=='setFluidInterfaceConfiguration' and select(2,...)~=nil) then
  assert(s.now>=3,'moved or configured before machine became available')
 end
 return original(a,m,...)
end
""".replace('STATE',state)
            run('legacy resume waits for '+state,setup+unavailable,mode='resume')
for nanites in [64,128,1024]:
    override="local c=require('component');local old=c.invoke;function c.invoke(a,m,...) if m=='getAvailableNanites' then return "+str(nanites)+" end return old(a,m,...) end;"
    run('same tier nanites '+str(nanites),override+'s.total=3;s.simultaneous=true')
prepared="""
s.now=1;s.total=40;s.simultaneous=true
s.sub={['molten.chromaticglass']=11520,['molten.transcendentmetal']=11520}
s.files['/home/bec_auto.journal']=require('serialization').serialize({version=1,kind='continuous',
 stage='stream-prepared',configOwned=false,expected=s.sub,target={entangled_chromaticglass=11520,entangled_transcendentmetal=11520},
 transfers={{ok=true,amount=11520},{ok=true,amount=11520}},requests={{state='done'}}},false)
"""
lua=run('resume protected whole batch without new request or transfer',prepared,mode='resume')
assert lua.globals().s.moves==0 and lua.globals().s.requests==0
run('changed prepared inventory refuses resume',prepared+"s.sub['molten.chromaticglass']=11400",success=False,mode='resume')
converting=prepared.replace("stage='stream-prepared'", "stage='converting',required=s.required,remaining=s.required")
partial="s.sub['molten.chromaticglass']=10944;s.sub['molten.transcendentmetal']=1728;s.stock={entangled_chromaticglass=576,entangled_transcendentmetal=9792};"
lua=run('resume asymmetric partial conversion without request or transfer',converting+partial,mode='resume')
assert lua.globals().s.moves==0 and lua.globals().s.requests==0
finished="s.sub={};s.stock={entangled_chromaticglass=11520,entangled_transcendentmetal=11520};"
lua=run('resume completed conversion before watching saved',converting+finished,mode='resume')
assert lua.globals().s.moves==0 and lua.globals().s.requests==0
run('missing conversion inventory refuses replenishment',converting+partial+"s.sub['molten.chromaticglass']=10800",success=False,mode='resume')
run('excess conversion inventory refuses resume',converting+partial+"s.stock.entangled_chromaticglass=720",success=False,mode='resume')
waiting=prepared.replace("stage='stream-prepared'", "stage='waiting'")
run('resume idle wait with confirmed historical batch',waiting+'s.total=1;s.sub={};s.stock={};',mode='resume')
progressed=converting.replace("target={", "batchCount=40,target={")
consumed="""
s.completed=1;s.parallel=39;s.group=39;s.active=true
s.consumed={entangled_chromaticglass=11232,entangled_transcendentmetal=11232};s.sub={};s.stock={};
"""
lua=run('resume 39 parallel already consumed current batch',progressed+consumed,mode='resume')
assert lua.globals().s.moves==0 and lua.globals().s.requests==0
notConsumed=consumed.replace('=11232','=0')
run('empty stocks without node consumed credit refuses refill',progressed+notConsumed,success=False,mode='resume')
six="""
s.parallel=6;s.group=6;s.active=true;s.consumed={entangled_chromaticglass=1728,entangled_transcendentmetal=1728}
s.sub={['molten.chromaticglass']=9792,['molten.transcendentmetal']=9792};s.stock={};
"""
lua=run('changed parallel credits consumption and remaining raw',progressed+six,mode='resume')
assert lua.globals().s.moves==0 and lua.globals().s.requests==0
realEmpty="""
s.parallel=39;s.group=39;s.active=true;s.consumed={};s.sub={};s.stock={}
s.mainStock={['molten.chromaticglass']=4752,['molten.transcendentmetal']=3301448}
"""
lua=run('explicit restock verified empty current batch',progressed+realEmpty,mode='restock')
assert lua.globals().s.requests==1 and lua.globals().s.requestAmount==6768
run('plain resume still blocks empty unconsumed batch',progressed+realEmpty,success=False,mode='resume')
unconfirmed=progressed.replace("requests={{state='done'}}", "requests={{state='submitted'}}")
run('restock cannot repeat unconfirmed old request',unconfirmed+realEmpty,success=False,mode='restock')
run('restock refuses excess inventory',converting+partial+"s.stock.entangled_chromaticglass=720",success=False,mode='restock')
run('known pre-cached DSS survives normal production','s.stock.entangled_dimshiftedsuperfluid=1000')
run('known pre-cached Infinity survives normal production','s.stock.entangled_infinity=5760')
run('new spatial and spacetime caches survive shielding production',
    's.stock.entangled_space=18000;s.stock.entangled_spacetime=18000')
print(f'{passed} streaming scenarios passed (mock only).')
run('four irrelevant cached condensates block release',
    's.stock.entangled_space=144;s.stock.entangled_spacetime=144;s.stock.entangled_infinity=144;s.stock.entangled_dimshiftedsuperfluid=1000',success=False)
