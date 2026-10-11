"""Test actual V1 patch installation and asynchronous supply/conversion accounting."""
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
source=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
controller=Path(sys.argv[1]).read_text(encoding='utf-8')
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(literal('fixes/process_reset/test_reset.py','installer'))
lua.globals().files['/home/bec_auto.lua']=controller
lua.globals().files['/home/bec_ui.lua']=Path(sys.argv[1]).with_name('bec_ui.lua').read_text(encoding='utf-8')
lua.globals().files['/home/bec_auto.journal']='keep journal'
# Install preceding production fixes too; new installer must retain them.
lua.eval('function()'+(ROOT/'fixes/process_reset/patch_v1.lua').read_text(encoding='utf-8')+'\nend')()
previous=lua.globals().files['/home/bec_auto.lua']
install=lua.eval('function()'+source+'\nend');install()
patched=lua.globals().files['/home/bec_auto.lua']
lua.execute('assert(load(...))',patched)
assert 'BEC_V1_BEE_GUARD_V2' in patched and 'BEC_V1_NEXT_RECIPE_V1' in patched
assert lua.globals().files['/home/bec_auto.lua.before-pipeline-1']==previous
assert lua.globals().files['/home/bec_auto.journal']=='keep journal'
writes=lua.globals().writes;install();assert lua.globals().writes==writes
print('Real controller + prior guards compile, journals preserved, unique backup and repeat install: PASS')

prepare=(HERE/'prepare.lua.inc').read_text(encoding='utf-8')
recover=(HERE/'recover.lua.inc').read_text(encoding='utf-8')
mock=r'''
mapping={a='raw.a',b='raw.b'};units={a=144,b=144};MAIN='main';SUB='sub';GEN='gen';RS='rs';sides={top=1}
now=0;stopping=false;enabled=false;main={};sub={};stock={};jobs={};submissions={};logs={};record={configOwned=false,requests={},transfers={},required={a=144,b=144},remaining={a=144,b=144}}
computer={uptime=function()return now end}
function integer(n)assert(type(n)=='number' and n>=0 and n==math.floor(n));return n end
function same(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end for k,v in pairs(b)do if a[k]~=v then return false end end return true end
function copy(a)local b={};for k,v in pairs(a)do b[k]=v end;return b end
function field()return copy(stock)end
function network(a)return copy(a==MAIN and main or sub)end
function resolveRawNames()end
function bulkPorts()local routes={['raw.a']={address='pa',from=1,to=5}};if not noRoute then routes['raw.b']={address='pb',from=1,to=5}end;return routes end
function verifyBulk()end
function unchanged()assert(not recipeChanged,'recipe changed');assert(not released,'assembler released too early')end
function emptyConfig()end
function tanks()return 0 end
function save(stage)record.stage=stage;logs[#logs+1]=stage end
function generator(on)enabled=on;if on then firstConversion=firstConversion or now end end
function prepareStreaming()fallback=true;return {legacy=144}end
function call(a,m,...)
 local args={...}
 if m=='getOutput' then return 15 end
 if m=='isWorkAllowed' then return enabled end
 if m=='isMachineActive' then return active==true end
 if m=='getCpus' then
  local used=0;for _,job in pairs(jobs)do if now<job.finish then used=used+1 end end
  local rows={};for i=1,(cpuCount or 2)do rows[i]={busy=i<=used}end;return rows
 end
 if m=='getCraftables' then local raw=args[1].name;return {{
  getStack=function()return {name=raw,isCraftable=true,amount=0,size=0,hasTag=false}end,
  request=function(amount)
   local r=record.requests[#record.requests];assert(r.state=='pending' and r.raw==raw and r.amount==amount,'missing durable intent')
   submissions[#submissions+1]={raw=raw,time=now,amount=amount}
   if nilRequest then return nil,'uncertain' end
   local job={finish=now+(raw=='raw.a' and 1 or 4),raw=raw,amount=amount};jobs[#jobs+1]=job
   return {isCanceled=function()return canceled==true,'cancel' end,isDone=function()return now>=job.finish end}
  end}}
 end
 if m=='transferFluid' then
  assert(record.pending and record.pending.amount==args[3]);assert(not released)
  if uncertain then error('uncertain transfer')end
  local raw=a=='pa' and 'raw.a' or 'raw.b';local amount=args[3]-(partial and 1 or 0)
  main[raw]=(main[raw] or 0)-amount;sub[raw]=(sub[raw] or 0)+amount
  return true,amount
 end
 error('unexpected '..m)
end
function tick(dt)
 now=now+dt
 for _,job in pairs(jobs)do if not job.delivered and now>=job.finish then main[job.raw]=(main[job.raw] or 0)+job.amount;job.delivered=true end end
 if enabled and not stalled then
  for name,raw in pairs(mapping)do local n=sub[raw] or 0;if n>0 then stock[name]=(stock[name] or 0)+n;sub[raw]=nil end end
 end
 if firstConversion and now<4 and (stock.a or 0)>0 then convertedBeforeSlowJob=true end
 if quitAt and now>=quitAt then stopping=true end
 assert(now<100,'loop failed to finish')
end
function current()return copy(record.required),copy(record.remaining)end
print=function()end
'''
def run(setup='',ok=True):
    runtime=LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(mock+setup)
    fn=runtime.eval('function()'+prepare+'\nreturn prepareStreaming({a=288,b=288}) end')
    try:
        result=fn()
        assert ok, 'Expected refusal'
        return runtime,result
    except Exception:
        if ok: raise
        return runtime,None

r,out=run();g=r.globals()
assert len(g.submissions)==2 and g.submissions[1].time==0 and g.submissions[2].time==0
assert g.convertedBeforeSlowJob and g.firstConversion<4
assert g.stock.a==288 and g.stock.b==288 and not g.enabled and len(out)==0
assert all(job.state=='done' for job in g.record.requests.values())
assert g.record.plan is None and g.record.pipeline is None
print('Two AE jobs start without waiting; first fluid converts before slow job ends; final batch and jobs confirmed: PASS')
r,_=run('cpuCount=1');assert len(r.globals().submissions)==2
assert r.globals().submissions[2].time>=1 and r.globals().stock.b==288
print('Single available CPU queues next request when free and still overlaps conversion: PASS')
r,_=run("main={['raw.a']=288,['raw.b']=288}")
assert len(r.globals().submissions)==0 and r.globals().stock.a==288
r,_=run("sub={['raw.a']=144};stock={a=144};main={['raw.b']=288}")
assert r.globals().stock.a==288 and len(r.globals().submissions)==0
r,_=run('noRoute=true');assert r.globals().fallback
print('Existing stock/raw credited, no extra orders; missing bulk route retains legacy path: PASS')
for setting in ['partial=true','uncertain=true','nilRequest=true','canceled=true','recipeChanged=true']:
    r,_=run(setting,False)
    if setting in ('partial=true','uncertain=true'):assert r.globals().record.pending is not None
    if setting=='nilRequest=true':assert r.globals().record.requests[1].state=='pending'
print('Partial/uncertain moves, uncertain/canceled jobs and changed recipe refuse continuation: PASS')
r,_=run("main={['raw.a']=288,['raw.b']=288};stalled=true;quitAt=.2")
g=r.globals();assert g.stopping and g.record.pipeline is not None
# Completion of current conversion after Q is required before recovery.
g.enabled=False;g.old=g.record;g.mode='resume'
r.execute(recover)
assert g.old.stage=='stream-planned' and g.old.secured['raw.a']==288
g.sub['raw.a']=144
try:r.execute(recover);raise AssertionError('Expected conservation failure')
except Exception as err:assert '不守恒' in str(err)
r,_=run('quitAt=.2');g=r.globals();g.old=g.record;g.mode='resume';g.enabled=False
try:r.execute(recover);raise AssertionError('Expected unfinished request refusal')
except Exception as err:assert '申请未完成' in str(err)
print('Q retains pipeline; recovery validates mass and rejects unfinished jobs or missing inventory: PASS')

base=literal('test_auto_once.py','MOCK').replace('/home/bec_auto_once.journal','/home/bec_auto.journal')
base+=literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
integration=r'''
local c=require('component');local list,invoke=c.list,c.invoke
local G='cf2a0c4a-ab8d-4958-b1df-253094d6690c';local filter={}
s.total=5;s.simultaneous=true
function c.list(...)
 local iter=list(...);local i=0;local more={{G,'bec_diode'},{'pipe-glass','transposer'},{'pipe-metal','transposer'}}
 return function()local a,t=iter();if a then return a,t end;i=i+1;if more[i]then return table.unpack(more[i])end end
end
function c.invoke(a,m,...)
 local args={...}
 if a==G then
  if m=='getCondensateFilterCount'then return 9 end
  if m=='getCondensateFilters'then return filter end
  if m=='setCondensateFilters'then filter=args[1];return true end
  if m=='isWorkAllowed' or m=='isMachineActive'then return true end
 end
 if m=='getRequiredTier'then return {tier=1}end
 if a:sub(1,5)=='pipe-' then
  local raw=a=='pipe-glass' and 'molten.chromaticglass' or 'molten.transcendentmetal'
  if m=='getTankCount'then return args[1]==1 and 1 or args[1]==5 and 6 or 0 end
  if m=='getTankCapacity'then return args[1]==1 and 2147483647 or 16000 end
  if m=='getFluidInTank'then return args[1]==1 and {name=raw,amount=s.mainStock[raw] or 0} or {amount=0}end
  if m=='transferFluid'then
   local journal=require('serialization').unserialize(s.files['/home/bec_auto.journal'])
   assert(journal.pending and journal.pending.amount==args[3] and s.output==15)
   local n=args[3]-(s.partial and 144 or 0);s.mainStock[raw]=(s.mainStock[raw] or 0)-n
   s.sub[raw]=(s.sub[raw] or 0)+n;s.moves=s.moves+1
   if s.enabled then s.overlappedMoves=(s.overlappedMoves or 0)+1 end
   return true,n
  end
 end
 return invoke(a,m,...)
end
function loadfile(path)
 if path=='/home/bec_nanites.lua'then return function()return {ensure=function()assert(s.output==15)end}end end
 if path=='/home/bec_cache.lua'then return function()return true end end
 error(path)
end
'''
for setup,success in [("",True),("s.mainStock={}",True),("s.partial=true",False),("s.mainStock={};s.nilCraft=true",False)]:
    r=LuaRuntime(unpack_returned_tuples=True);r.execute(base+integration+setup)
    program=r.eval('function(...)'+patched+'\nend');program('run')
    s=r.globals().s;logs=list(s.logs.values())
    assert s.output==15 and not s.enabled and s.cfg is None,logs
    if success:
        assert s.completed==s.total and s.reserveChecks==1,logs
        if setup:assert s.requests==2 and s.overlappedMoves>=1,logs
    else:
        assert s.completed==0,logs
        before=(s.moves,s.requests);program('run');assert before==(s.moves,s.requests),logs
print('Full patched V1 controller finishes both stocked/parallel-crafted batches; partial/uncertain jobs stop and cannot replay: PASS')

