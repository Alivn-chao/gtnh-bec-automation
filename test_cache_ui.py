"""Editable cache UI integration mocks; no hardware validation."""
import ast
import sys
import unicodedata
from pathlib import Path
sys.path.insert(0,str(Path('work/lua_runtime').resolve()))
from lupa.lua52 import LuaRuntime
def literal(file,name):
    return next(n.value.value for n in ast.parse(Path(file).read_text(encoding='utf-8')).body
                if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
base=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
base=base.replace('/home/bec_auto_once.journal','/home/bec_cache.journal').replace('/home/bec_auto.journal','/home/bec_cache.journal')
base+=literal('test_cache.py','EXTRA')
gpu=literal('test_ui.py','GPU').replace("assert(path=='/home/bec_auto.lua')","assert(path=='/home/bec_cache.lua')")
ui=Path('bec_cache_ui.lua').read_text(encoding='utf-8')
worker=Path('bec_cache.lua').read_text(encoding='utf-8')
passed=0
def run(label,events,setup='',writes=False):
    global passed
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().pyWidth=lambda t:sum(2 if unicodedata.east_asian_width(x) in ('W','F') else 1 for x in t)
    lua.globals().pySub=lambda t,a,b:t[int(a)-1:int(b) if b>=0 else len(t)+int(b)+1]
    lua.execute(base+gpu)
    lua.execute(setup)
    lua.globals().s.controller=lua.eval('function(...) '+worker+'\nend')
    lua.execute('''s.events={'''+events+'''}
local e=require('event')
e.pull=function(n)
 s.now=s.now+(n or 0)
 if #s.events>0 then return table.unpack(table.remove(s.events,1)) end
 local text=s.files['/home/bec_cache.journal']
 local record=text and require('serialization').unserialize(text)
 if record and record.stage=='stopped' then return 'key_down','kb',113 end
 assert(s.now<5000,'UI did not exit')
end
''')
    lua.eval('function(...) '+ui+'\nend')('standalone')
    s=lua.globals().s
    assert s.width==80 and s.height==25 and s.cleared
    assert s.frames>0
    if not writes: assert s.writes==0 and s.mutations==0
    passed+=1;print(label+': PASS');return lua
run('opening cache settings has no mutations',"{'key_down','kb',113}")
keys=lambda text:','.join("{'key_down','kb',%d}"%ord(ch) for ch in text)
edit="{'key_down','kb',101},"+keys('144000')+",{'key_down','kb',13,28},{'key_down','kb',112},{'key_down','kb',113}"
lua=run('edit save and readonly preview',edit,writes=True)
assert lua.globals().s.mutations==0
assert lua.eval("require('serialization').unserialize(s.files['/home/bec_cache.config']).target")==144000
saved="s.files['/home/bec_cache.config']=require('serialization').serialize({version=1,target=18000},false)"
lua=run('saved target used by cache worker',"{'key_down','kb',98}",setup=saved,writes=True)
assert lua.globals().s.stock.entangled_chromaticglass==18000
assert lua.globals().s.stock.entangled_transcendentmetal==18000
lua=run('editing invalid value does not save or run',"{'key_down','kb',101},{'key_down','kb',48},{'key_down','kb',13,28},{'key_down','kb',113}")
assert lua.globals().s.files['/home/bec_cache.config'] is None
lua=run('cancel editing retains configured target',"{'key_down','kb',101},"+keys('5')+",{'key_down','kb',0,1},{'key_down','kb',113}",saved)
assert any('18000' in x for x in lua.globals().s.draws.values())
run('small screen bounds',"{'key_down','kb',113}","s.maxWidth=80;s.maxHeight=25")
lua=run('cache entry touch is not an exit on next screen',"{'touch','screen',35,29,0},"+edit,writes=True)
assert lua.globals().s.files['/home/bec_cache.config'] is not None,'entry touch closed cache UI'
lua=run('refresh button does not exit cache settings',"{'touch','screen',90,29,0},"+edit,writes=True)
assert lua.globals().s.files['/home/bec_cache.config'] is not None,'refresh touch closed cache UI'
coal="addRecipe('coal_umv',{{name='entangled_space',amount=3456},{name='entangled_spacetime',amount=1728},{name='entangled_dimshiftedsuperfluid',amount=10000}})"
lua=run('registered UMV additional fluids appear without editing UI',"{'key_down','kb',113}",coal)
assert any('空间：' in x for x in lua.globals().s.draws.values())
assert any('时空：' in x for x in lua.globals().s.draws.values())
setup="for i=1,12 do addRecipe('new'..i,{{name='entangled_test'..i,amount=144}}) end"
lua=run('registered fluids paginate on minimum screen',"{'key_down','kb',110},{'key_down','kb',113}",setup+";s.maxWidth=80;s.maxHeight=25")
assert any('第 2 / 2 页' in x for x in lua.globals().s.draws.values())
print(f'{passed} cache UI scenarios passed (mock only).')
