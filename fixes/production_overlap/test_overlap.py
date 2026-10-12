"""Lua 5.2 simulation of installed V1 and durable streaming overlap."""
import ast
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
def literal(path,name):
    tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
    return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
patch=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
for name in ['bec_auto.lua','outputs/nanites_switch/bec_auto.lua','outputs/nanites_switch/bec_auto_paste.lua']:
    path=ROOT/name
    if not path.exists():continue
    r=LuaRuntime(unpack_returned_tuples=True);r.execute(literal('fixes/process_reset/test_reset.py','installer'))
    r.globals().files['/home/bec_auto.lua']=path.read_text(encoding='utf-8')
    r.globals().files['/home/bec_auto.journal']='keep unfinished'
    # Pipeline installer expects the packed recovery entry.
    if name=='bec_auto.lua':
        text=r.globals().files['/home/bec_auto.lua']
        text=text.replace('end\nlocal function serve()','end local function serve()').replace('local old=ser.unserialize(contents)\n','local old=ser.unserialize(contents) local streaming=false\n')
        r.globals().files['/home/bec_auto.lua']=text
    for p in ['fixes/pipeline/patch_v1.lua','fixes/order_window/patch_v1.lua']:
        r.eval('function()'+(ROOT/p).read_text(encoding='utf-8')+'\nend')()
    original=r.globals().files['/home/bec_auto.lua']
    install=r.eval('function()'+patch+'\nend');install()
    result=r.globals().files['/home/bec_auto.lua']
    r.execute('assert(load(...))',result)
    assert r.globals().files['/home/bec_auto.lua.before-overlap-1']==original
    assert r.globals().files['/home/bec_auto.journal']=='keep unfinished'
    writes=r.globals().writes;install();assert r.globals().writes==writes
    if name.endswith('/bec_auto.lua'):program=result
    print(name+': installation/syntax/backup/journal/idempotence PASS')

r=LuaRuntime(unpack_returned_tuples=True);r.execute(literal('fixes/process_reset/test_reset.py','installer'))
r.globals().files['/home/bec_auto.lua']=original
r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('overlap-new',1,true)then return false end;return rename(a,b)end")
try:r.eval('function()'+patch+'\nend')();raise AssertionError('expected rollback')
except Exception as e:assert '已还原' in str(e)
assert r.globals().files['/home/bec_auto.lua']==original
print('Failed replacement restores original controller PASS')

mock=literal('fixes/pipeline/test_pipeline.py','mock')
mock=mock.replace("assert(not released,'assembler released too early')", "assert(not released,'unchanged used after release')")
mock=mock.replace("assert(not released)\n", "\n")
extra=r'''
NODE='node';c={methods=function()return {}end};ser={serialize=function()return ''end}
perRecipe={a=144,b=144};consumed={};orders=10;completed=0;progress=0;output=15
function checkRecipe()perRecipe={a=144,b=144};return 1 end
function pause(n)output=n;released=n==0 end
local previous=call
function call(a,m,...)
 if m=='getState'then return completed>=orders and 'idle' or output==15 and 'paused-immediate' or 'crafting' end
 if m=='getRequiredCondensate'then
  if completed>=orders then return nil end
  if recipeChanged then return {a=144,b=288}end
  return {a=144,b=144}
 end
 if m=='getParallelRecipesInProgress'then return completed>=orders and 0 or 1 end
 if m=='getConsumedCondensate'then return copy(consumed)end
 return previous(a,m,...)
end
function tick(dt)
 now=now+dt
 for _,job in pairs(jobs)do
  if not job.delivered and now>=job.finish then main[job.raw]=(main[job.raw] or 0)+job.amount;job.delivered=true end
 end
 if enabled and not stalled then
  for name,raw in pairs(mapping)do
   local n=math.min(144,sub[raw] or 0)
   if n>0 then stock[name]=(stock[name] or 0)+n;sub[raw]=sub[raw]-n;if sub[raw]==0 then sub[raw]=nil end end
  end
 end
 if released then
  if next(sub)~=nil and enabled then ranWhileConverting=true end
  if not consumed.a then
   assert(stock.a>=144 and stock.b>=144,'unfunded production')
   stock.a=stock.a-144;stock.b=stock.b-144;consumed={a=144,b=144}
  end
  progress=progress+dt
  if progress>=.5 then completed=completed+1;progress=0
   if completed<orders then consumed={}end
  end
 end
 if switchAfter and completed>=switchAfter then recipeChanged=true end
 if quitAt and now>=quitAt then stopping=true end
 assert(now<100,'loop stalled')
end
'''
prepare=(HERE/'prepare.lua.inc').read_text(encoding='utf-8')
recover=(HERE/'recover.lua.inc').read_text(encoding='utf-8')
def run(setup='',success=True):
    r=LuaRuntime(unpack_returned_tuples=True);r.execute(mock+extra+setup)
    try:r.eval('function()'+prepare+'\nreturn prepareStreaming({a=1440,b=1440}) end')();assert success
    except Exception:
        if success:raise
    return r
r=run();g=r.globals()
assert g.completed==10 and g.ranWhileConverting and len(g.submissions)==2
assert not g.enabled and g.output==15 and g.record.productionOverlapHandled and g.record.pipeline is None
print('Production during conversion; both orders submitted concurrently; all ten products completed PASS')
r=run('switchAfter=2');g=r.globals()
assert g.completed==2 and g.output==15 and not g.enabled and len(g.sub)==0
assert g.stock.a==1152 and g.stock.b==1152
print('Recipe change pauses production, drains old confirmed supply, leaves remaining inventory PASS')
for setting in ['partial=true','uncertain=true','nilRequest=true','canceled=true']:
    r=run(setting,False);g=r.globals();assert g.completed==0
    if setting in ('partial=true','uncertain=true'):assert g.record.pending is not None
    if setting=='nilRequest=true':assert g.record.requests[1].state=='pending'
print('Uncertain jobs/transfers remain unreplayed PASS')
r=run('quitAt=4.8');g=r.globals()
assert g.record.pipeline.overlap and g.record.pipeline is not None and g.completed>=1
g.old=g.record;g.mode='resume';g.enabled=False;g.stopping=False;g.output=15;g.released=False
before=len(g.submissions)
r.execute(recover)
assert g.old.stage=='watching' and g.old.plan is None and len(g.sub)==0 and len(g.submissions)==before
print('Interrupted production resumes by accounting for consumed batches; no new requests/moves PASS')
r=run('quitAt=4.8');g=r.globals();g.old=g.record;g.mode='resume';g.enabled=False;g.output=15;g.released=False;g.stopping=False
g.stock.a-=1
try:r.execute(recover);raise AssertionError('expected conservation refusal')
except Exception as e:assert '不守恒' in str(e)
print('Unexplained inventory loss rejected PASS')

# Actual packed controller: same supply bridge, gradual rather than instant conversion.
base=literal('test_auto_once.py','MOCK').replace('/home/bec_auto_once.journal','/home/bec_auto.journal')
base+=literal('test_stream.py','EXTRA').replace('local need=288*math.max(1,queued())-consumed','local need=288*(s.group or 1)-consumed')
base+=literal('test_stream.py','STREAM')
integration=literal('fixes/pipeline/test_pipeline.py','integration').replace(' and s.output==15','')
integration+=r'''
s.noConvert=true
local c=require('component');local invoke=c.invoke
function c.invoke(a,m,...)
 local args={...}
 if a=='237a9cac-118a-4b74-8755-0d0b0ad216c0' and m=='getStoredCondensate'then
  if s.enabled then
   for raw,n in pairs(s.sub)do
    local name=raw=='molten.chromaticglass' and 'entangled_chromaticglass' or 'entangled_transcendentmetal'
    local moved=math.min(144,n);s.stock[name]=(s.stock[name] or 0)+moved
    s.sub[raw]=n-moved;if s.sub[raw]==0 then s.sub[raw]=nil end
   end
  end
  local copy={};for name,n in pairs(s.stock)do copy[name]=n end;return copy
 end
 if m=='setOutput' and args[2]==0 and s.enabled then
  if next(s.sub) then s.productionOverlap=true end
  for _,job in ipairs(s.jobs)do if s.now-job.started<2 then s.productionOverlap=true end end
 end
 if m=='transferFluid' and a:sub(1,5)=='pipe-' and s.output==0 then s.liveSupply=true end
 return invoke(a,m,...)
end
'''
for setup in ['', 's.mainStock={}', 's.parallel=2', 's.partial=true', 's.mainStock={};s.nilCraft=true']:
    r=LuaRuntime(unpack_returned_tuples=True);r.execute(base+integration+setup)
    r.eval('function(...)'+program+'\nend')('run')
    s=r.globals().s;logs=list(s.logs.values())
    assert s.output==15 and not s.enabled,logs
    if 'partial' not in setup and 'nilCraft' not in setup:
        assert s.completed==s.total and s.productionOverlap,(s.completed,s.productionOverlap,logs[-15:])
        assert not any('程序停止:' in str(x) for x in logs),logs
        if setup=='s.mainStock={}':assert s.requests==2 and s.liveSupply,logs
    else:
        assert s.completed==0,logs
        counts=(s.moves,s.requests)
        r.eval('function(...)'+program+'\nend')('run');assert counts==(s.moves,s.requests)
print('Actual V1 controller: live supply/conversion/production, uncertainty stop without replay PASS')

r=LuaRuntime(unpack_returned_tuples=True);r.execute(base+integration+r'''
local c=require('component');local invoke=c.invoke
function c.invoke(a,m,...)
 if m=='getState' and s.quitOnFirst and s.completed>=1 then s.stopEarly=true end
 return invoke(a,m,...)
end
s.quitOnFirst=true
''')
fn=r.eval('function(...)'+program+'\nend');fn('run')
s=r.globals().s
assert s.completed>=1 and s.completed<s.total and s.output==15 and not s.enabled
moves,requests=s.moves,s.requests
s.quitOnFirst=False;s.stopEarly=False
fn('resume')
logs=list(s.logs.values())
assert s.completed==s.total and s.moves==moves and s.requests==requests,logs[-8:]
assert any('并行生产消耗核对通过' in str(x) for x in logs),logs[-8:]
print('Actual installed controller Q/resume accounts for production and retains original requests/moves PASS')
