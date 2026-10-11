"""Background cache yields to registered recipes at a confirmed boundary."""
import ast,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
def literal(path,name):
 tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
 return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
source=(HERE/'bec_cache_priority.lua').read_text(encoding='utf-8')
original=(HERE/'bec_cache.lua').read_text(encoding='utf-8')
patch=(HERE/'patch_priority.lua').read_text(encoding='utf-8')
r=LuaRuntime(unpack_returned_tuples=True)
r.execute(literal('fixes/process_reset/test_reset.py','installer').replace('next-new','priority-new'))
r.globals().files['/home/bec_cache.lua']=original
r.globals().files['/home/bec_cache.journal']='keep current'
r.globals().files['/home/bec_auto.lua']='keep controller'
install=r.eval('function()'+patch+'\nend')
r.globals().failInstall=True
try:install();raise AssertionError('expected rollback')
except Exception as e:assert '已还原' in str(e)
assert r.globals().files['/home/bec_cache.lua']==original
r.globals().failInstall=False;install()
assert r.globals().files['/home/bec_cache.lua']==source
assert r.globals().files['/home/bec_cache.journal']=='keep current'
assert r.globals().files['/home/bec_auto.lua']=='keep controller'
r.execute('assert(load(...))',source)
writes=r.globals().writes;install();assert r.globals().writes==writes
print('Locating installer, syntax, rollback, unique backup, repeat install and production/journal preservation: PASS')
base=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
base=base.replace('/home/bec_auto_once.journal','/home/bec_cache.journal').replace('/home/bec_auto.journal','/home/bec_cache.journal')
base+=literal('test_cache.py','EXTRA')+literal('fixes/cache_bulk/test_bulk_cache.py','extra')
extra=r'''
local c=require('component');local invoke=c.invoke
function c.invoke(a,m,...)
 if m=='getCpus' then
  if s.unreadableQueue then return {{busy=true}}end
  if s.queuedRecipe then return {{busy=true,cpu={activeItems=function()return {{name='gregtech:gt.metaitem.03',damage=32316,size=2}}end,pendingItems=function()return {}end}}}end
  return {{busy=false}}
 end
 return invoke(a,m,...)
end
'''
def run(setup='',mode='background-stock',ok=True):
 r=LuaRuntime(unpack_returned_tuples=True);r.execute(base+extra+setup)
 worker=r.eval('function(...)'+source+'\nend');result,error=worker(mode,144000)
 assert bool(result)==ok,(error,list(r.globals().s.logs.values()))
 return r,worker
for setup in ['s.newOrderAt=0','s.queuedRecipe=true','s.unreadableQueue=true']:
 r,_=run(setup);s=r.globals().s
 assert s.moves==0 and s.requests==0 and s.writes==0
print('Node recipe, registered AE queued recipe and unreadable busy queue all prevent a fresh cache batch: PASS')
r,_=run();s=r.globals().s
assert s.stock.entangled_chromaticglass==31968 and s.moves==1 and s.requests==0
assert not s.cacheEnabled
print('Idle background cache uses at most 15984 mB instead of filling 128016 mB in one batch: PASS')
r,_=run('s.mainStock={};s.newOrderAt=.5');s=r.globals().s
assert s.requests==1 and s.stock.entangled_chromaticglass<31968
record=r.eval("require('serialization').unserialize(s.files['/home/bec_cache.journal'])")
assert record.yieldedToRecipe and not record.incomplete and record.stage=='stopped'
assert all(job.state=='done' for job in record.requests.values())
assert len(s.sub)==0 and not s.cacheEnabled and s.now>=2
print('New recipe during AE job stops further collection/orders; confirms existing request and converts only secured raw before handoff: PASS')
r,_=run(r'''
s.newOrderAt=0;s.noPort=true;s.sub={['molten.chromaticglass']=144}
s.files['/home/bec_cache.journal']=require('serialization').serialize({kind='cache',stage='stopped',background=true,incomplete=true,pending=nil,configOwned=false,requests={},transfers={},target={entangled_chromaticglass=31968}},false)
''');s=r.globals().s
assert s.moves==0 and s.requests==0 and s.stock.entangled_chromaticglass==16128 and len(s.sub)==0
record=r.eval("require('serialization').unserialize(s.files['/home/bec_cache.journal'])")
assert not record.incomplete and record.yieldedToRecipe
print('Incomplete old cache yields after finishing its held raw, without resuming the original full target: PASS')
r,worker=run("s.newOrderAt=0;s.sub={['wrong.raw']=144};s.files['/home/bec_cache.journal']=require('serialization').serialize({kind='cache',stage='stopped',background=true,incomplete=true,pending=nil,configOwned=false,requests={},transfers={},target={entangled_chromaticglass=31968}},false)",ok=False)
assert not r.globals().s.cacheEnabled and r.globals().s.moves==0
r,_=run("s.sub={['molten.chromaticglass']=144};s.files['/home/bec_cache.journal']=require('serialization').serialize({kind='cache',stage='stopped',background=true,incomplete=true,pending=nil,configOwned=false,requests={{state='submitted'}},transfers={},target={entangled_chromaticglass=31968}},false)",ok=False)
assert r.globals().s.moves==0 and r.globals().s.requests==0
print('Unrelated held raw and unsettled prior AE requests refuse handoff/replay: PASS')
r,_=run(mode='run-stock');s=r.globals().s
assert s.stock.entangled_chromaticglass==144000 and s.moves==1
print('Explicit manual cache still fills the requested complete target: PASS')
