"""Fast idle cache, actual locating patch and accurate completion display."""
import ast,sys,unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
def literal(path,name):
 tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
 return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
source=(HERE/'bec_cache_fast.lua').read_text(encoding='utf-8')
patch=(HERE/'patch_fast.lua').read_text(encoding='utf-8')
old=(HERE/'bec_cache_priority.lua').read_text(encoding='utf-8')
snapshot=Path(sys.argv[1])
originals={'/home/bec_cache.lua':old,'/home/bec_auto.lua':(snapshot/'bec_auto.lua').read_text(encoding='utf-8'),'/home/bec_cache_ui.lua':(snapshot/'bec_cache_ui.lua').read_text(encoding='utf-8')}
r=LuaRuntime(unpack_returned_tuples=True);r.execute(literal('fixes/process_reset/test_reset.py','installer'))
for path,text in originals.items():r.globals().files[path]=text
r.eval('function()'+(ROOT/'fixes/pipeline/patch_v1.lua').read_text(encoding='utf-8')+'\nend')()
originals['/home/bec_auto.lua']=r.globals().files['/home/bec_auto.lua']
r.globals().files['/home/bec_cache.journal']='keep cache journal'
r.globals().files['/home/bec_auto.journal']='keep production journal'
r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b) if failUI and b=='/home/bec_cache_ui.lua' and a:find('cache-fast-new',1,true)then return false end return rename(a,b)end")
install=r.eval('function()'+patch+'\nend');r.globals().failUI=True
try:install();raise AssertionError('expected rollback')
except Exception as e:assert '已还原' in str(e)
for path,text in originals.items():assert r.globals().files[path]==text,path
r.globals().failUI=False;install()
assert r.globals().files['/home/bec_cache.lua']==source
for path in originals:r.execute('assert(load(...))',r.globals().files[path])
assert r.globals().files['/home/bec_cache.journal']=='keep cache journal'
assert r.globals().files['/home/bec_auto.journal']=='keep production journal'
writes=r.globals().writes;install();assert r.globals().writes==writes
print('Actual cache UI/controller patch compiles; third-file failure restores all files; retry, idempotence, journals preserved: PASS')
patched_ui=r.globals().files['/home/bec_cache_ui.lua']
controller=r.globals().files['/home/bec_auto.lua']
assert 'BEC_V1_PIPELINE_V1' in controller
base=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
base=base.replace('/home/bec_auto_once.journal','/home/bec_cache.journal').replace('/home/bec_auto.journal','/home/bec_cache.journal')
base+=literal('test_cache.py','EXTRA')+literal('fixes/cache_bulk/test_bulk_cache.py','extra')
extra=literal('fixes/cache_bulk/test_priority.py','extra')+r'''
local c=require('component');local invoke=c.invoke
function c.invoke(a,m,...)
 if m=='getRequiredCondensate' and s.newOrderAt and s.now>=s.newOrderAt then return {entangled_transcendentmetal=288}end
 return invoke(a,m,...)
end
'''
def run(setup=''):
 r=LuaRuntime(unpack_returned_tuples=True);r.execute(base+extra+setup)
 worker=r.eval('function(...)'+source+'\nend');ok,error=worker('background-stock',144000)
 assert ok,(error,list(r.globals().s.logs.values()))
 return r
for setup in ('','s.unreadableQueue=true'):
 r=run(setup);s=r.globals().s
 assert s.stock.entangled_chromaticglass==144000 and s.moves==1 and s.requests==0
 assert not s.cacheEnabled
print('Idle cache fills entire 128016mB deficit in one bulk transfer; unreadable busy CPU no longer blocks it: PASS')
for setup in ('s.newOrderAt=0','s.queuedRecipe=true'):
 r=run(setup);s=r.globals().s
 assert s.moves==0 and s.requests==0 and s.writes==0
 assert any('后台缓存让位' in row for row in s.logs.values())
print('Confirmed node/AE recipe retains priority and reports why caching waits: PASS')
r=run('s.mainStock={};s.newOrderAt=.5');s=r.globals().s
assert s.requests==1 and s.stock.entangled_chromaticglass<144000
record=r.eval("require('serialization').unserialize(s.files['/home/bec_cache.journal'])")
assert record.yieldedToRecipe and not record.incomplete and record.requests[1].state=='done'
assert len(s.sub)==0 and not s.cacheEnabled
print('Recipe arriving during AE supply still stops collection and safely hands off after request confirmation: PASS')
# Exercise the exact display override inserted in real UI without invoking GPU setup.
start=patched_ui.index('-- BEC_V1_CACHE_STATUS_FAST_V2');end=patched_ui.index('line(8,',start)
display=patched_ui[start:end]
d=LuaRuntime(unpack_returned_tuples=True);d.execute("embedded=true;status='本轮完成；继续维护库存';stock={a=10,b=30};target=20;names={{'A','a'},{'B','b'}};function line(y,t)displayText=t end")
d.execute(display);assert '1 种未达标' in d.globals().displayText
d.execute('stock.a=20');d.execute(display);assert '已达标' in d.globals().displayText
print('Completion display checks actual stock against the full configured target: PASS')
# The controller now permits cache entry from no-recipe offline state, but not active demand.
start=controller.index('-- BEC_V1_IDLE_CACHE_FAST_V2');end=controller.index(' local input=',start)
guard=controller[start:end]
f=LuaRuntime(unpack_returned_tuples=True)
f.execute("function call()return req end")
test=f.eval('function(s,r)state=s;req=r;incomplete=false;'+guard+';return true end')
assert test('assembler-offline',None) is True
assert test('unpowered',f.table_from({'a':144})) is None
assert test('crafting',None) is None
print('No-recipe offline node may cache; real demand/unsupported active state still prevents competing cache entry: PASS')
u=LuaRuntime(unpack_returned_tuples=True)
u.globals().pyWidth=lambda t:sum(2 if unicodedata.east_asian_width(x) in ('W','F') else 1 for x in t)
u.globals().pySub=lambda t,a,b:t[int(a)-1:int(b) if b>=0 else len(t)+int(b)+1]
u.execute(base+extra+literal('test_ui.py','GPU')+r'''
function loadfile()return function()return true end end
s.width=100;s.height=30;s.registryReads=0;s.displayQueries=0
local fs=require('filesystem');local list=fs.list
fs.list=function(...)s.registryReads=s.registryReads+1;return list(...)end
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if m=='getStoredCondensate'then s.displayQueries=s.displayQueries+1 end;return invoke(a,m,...)end
''')
view=u.eval('function(...)'+patched_ui+'\nend')('embedded')
view.draw(True);view.draw(True);view.handle(u.table_from({1:'key_down',3:110}))
assert u.globals().s.registryReads==1 and u.globals().s.displayQueries==1
view.handle(u.table_from({1:'key_down',3:114}))
view.draw(True)
assert u.globals().s.registryReads==2 and u.globals().s.displayQueries==2,(u.globals().s.registryReads,u.globals().s.displayQueries)
print('Actual embedded UI paints/flips using one inventory/registry sample; R explicitly refreshes both: PASS')

