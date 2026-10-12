"""V1 queued-order windowing; real Lua5.2 installation and refill behaviour."""
import ast
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
PATCH=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
HELPER=(HERE/'window.lua.inc').read_text(encoding='utf-8')

def literal(path,name):
    tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
    return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))

for path in [p for p in ['bec_auto.lua','outputs/nanites_switch/bec_auto.lua','outputs/nanites_switch/bec_auto_paste.lua'] if (ROOT/p).exists()]:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(literal('fixes/process_reset/test_reset.py','installer'))
    original=(ROOT/path).read_text(encoding='utf-8')
    lua.globals().files['/home/bec_auto.lua']=original
    lua.globals().files['/home/bec_auto.journal']='preserve unfinished journal'
    lua.globals().files['/home/bec_cache.journal']='preserve cache'
    install=lua.eval('function()'+PATCH+'\nend');install()
    patched=lua.globals().files['/home/bec_auto.lua']
    if path=='bec_auto.lua':program_main=patched
    lua.eval('function(text)assert(load(text))end')(patched)
    assert '整批需求过大' not in patched and 'refill=needsRefill(req,consumed,stock,windowQueue)' in patched
    assert lua.globals().files['/home/bec_auto.lua.before-window-1']==original
    assert lua.globals().files['/home/bec_auto.journal']=='preserve unfinished journal'
    assert lua.globals().files['/home/bec_cache.journal']=='preserve cache'
    writes=lua.globals().writes;install();assert lua.globals().writes==writes
    print(path+': install, syntax, backup, journals, repeat PASS')

if (ROOT/'outputs/nanites_switch/bec_auto.lua').exists():
    # Preserve earlier pipeline and bee/next-recipe guards on the actual packed V1.
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(literal('fixes/process_reset/test_reset.py','installer'))
    lua.globals().files['/home/bec_auto.lua']=(ROOT/'outputs/nanites_switch/bec_auto.lua').read_text(encoding='utf-8')
    lua.globals().files['/home/bec_ui.lua']='preserve UI'
    for path in ['fixes/pipeline/patch_v1.lua','fixes/order_window/patch_v1.lua']:
        lua.eval('function()'+(ROOT/path).read_text(encoding='utf-8')+'\nend')()
    patched=lua.globals().files['/home/bec_auto.lua']
    assert all(marker in patched for marker in ['BEC_V1_PIPELINE_V1','BEC_V1_ORDER_WINDOW_V1','local function switchNanites','local function configureGate'])
    lua.eval('function(text)assert(load(text))end')(patched)
    print('Prior streaming/bee/filter code preserved: PASS')
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(literal('fixes/process_reset/test_reset.py','installer'))
original=(ROOT/'bec_auto.lua').read_text(encoding='utf-8');lua.globals().files['/home/bec_auto.lua']=original
lua.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('window-new',1,true)then return false end;return rename(a,b)end")
try:lua.eval('function()'+PATCH+'\nend')();raise AssertionError('expected rollback')
except Exception as e:assert '已还原' in str(e),e
assert lua.globals().files['/home/bec_auto.lua']==original
print('Replacement failure rolls back: PASS')

lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute('''
units={a=144,b=144};perRecipe={a=9437184,b=9216};parallel=1;queue=1000000
function integer(n)assert(type(n)=='number'and n>=0 and n%1==0);return n end
function checkRecipe()return parallel end
function queuedRecipes()return queue end
''')
target,refill=lua.execute(HELPER+'\nreturn batchTarget,needsRefill')
req=lua.table_from({'a':9437184,'b':9216});remaining=lua.table_from(dict(req.items()))
stock,count,queued=target(req,remaining)
assert queued==1000000 and count==227
assert stock.a==9437184*227 and stock.a<=2147483520 and stock.b==9216*227
assert not refill(req,lua.table(),stock)
lua.globals().queue=1000000000
next_target,next_count,_=target(req,remaining);assert next_count==count and next_target.a==stock.a
assert not refill(req,lua.table(),next_target)
# A small decrease in stock must not restart preparation against the entire queue.
next_target.a-=9437184*10;next_target.b-=9216*10
assert not refill(req,lua.table(),next_target)
next_target.a=9437184
assert refill(req,lua.table(),next_target)
print('Million/billion recipe queues bounded; growth does not pause; low stock refills: PASS')

lua.globals().queue=3;small,small_count,_=target(req,remaining)
assert small_count==3 and small.a==9437184*3
lua.globals().queue=2
assert not refill(req,lua.table(),lua.table_from({'a':9437184*2,'b':9216*2}))
lua.globals().queue=1
assert not refill(req,lua.table(),lua.table_from({'a':9437184,'b':9216}))
print('Small orders complete without new-order cancellation or artificial refill: PASS')

lua.execute('parallel=64;perRecipe={a=144,b=1000};units={a=144,b=1000};queue=10000000')
req=lua.table_from({'a':144*64,'b':1000*64});remaining=lua.table_from({'a':144*32,'b':1000*32})
stock,count,_=target(req,remaining)
assert stock.a<=2147483520 and stock.b<=2147483000 and stock.b%1000==0
assert stock.a==144*(count-32) and stock.b==1000*(count-32)
print('Parallel, consumed remainder, limiting fluid and 1000mB alignment: PASS')

# Exercise the whole continuous controller. Hardware consumes one physical batch,
# not the full AE order; the previous fixture asserted the old whole-order policy.
base=literal('test_auto_once.py','MOCK').replace('/home/bec_auto_once.journal','/home/bec_auto.journal')
extra=literal('test_stream.py','EXTRA').replace('local need=288*math.max(1,queued())-consumed','local need=288*(s.group or 1)-consumed')
stream=literal('test_stream.py','STREAM')
lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(base+extra+stream)
lua.execute('''
s.total=1000000000;s.simultaneous=true
s.stock={entangled_chromaticglass=2147483520,entangled_transcendentmetal=2147483520}
local old=require
require=function(name)
 if name=='event'then local e=old(name);return {pull=function(sec)
  local a,b,c=e.pull(sec);if s.completed>=3 then return 'key_down','keyboard',113 end;return a,b,c
 end}end
 return old(name)
end
''')
lua.eval('function(...)'+program_main+'\nend')('run')
s=lua.globals().s;logs=list(s.logs.values())
assert s.total==1000000000 and s.completed==3 and s.reserveChecks==1,logs
assert s.output==15 and not s.enabled and s.requests==0,logs
print('Full controller: billion-order queue runs continuously, one release, Q preserves order: PASS')

# Small artificial API ceiling makes several windows observable in a short test.
# The actual ceiling and alignment were independently checked above.
lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(base+extra+stream)
lua.execute('s.total=8;s.simultaneous=true')
lua.eval('function(...)'+program_main.replace('2147483647','864')+'\nend')('run')
s=lua.globals().s;logs=list(s.logs.values())
assert s.completed==8 and s.total==8 and s.reserveChecks>=3,logs
assert s.output==15 and not s.enabled and s.cfg is None,logs
assert not any('程序停止:' in str(x) for x in logs),logs
print('Full controller: one AE order completes across multiple preparation windows: PASS')

# Consumption may add one slot to the bounded count while material target stays
# unchanged. New window journals are checked by material, not old whole-order count.
lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(base+extra+stream)
lua.execute('''
s.now=1;s.total=1000000000;s.simultaneous=true;s.active=true
s.consumed={entangled_chromaticglass=288,entangled_transcendentmetal=288}
s.stock={entangled_chromaticglass=2147483520,entangled_transcendentmetal=2147483520}
local old={version=1,kind='continuous',stage='converting',configOwned=false,windowed=true,
 batchCount=2147483520/288,required=s.required,remaining=s.required,target=s.stock,expected={},requests={},transfers={}}
s.files['/home/bec_auto.journal']=require('serialization').serialize(old,false)
s.stopEarly=true
''')
lua.eval('function(...)'+program_main+'\nend')('resume')
s=lua.globals().s;logs=list(s.logs.values())
assert not any('程序停止:' in str(x) for x in logs),logs
assert any('转换恢复核对通过' in str(x) for x in logs),logs
assert s.moves==0 and s.requests==0,logs
print('Window count can change after consumption; material-checked resume does not replay: PASS')
