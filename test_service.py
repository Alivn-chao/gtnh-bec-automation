"""Full foreground UI / producer / idle cache integration with inventory mocks."""
import ast,sys,unicodedata
from pathlib import Path
sys.path.insert(0,str(Path('work/lua_runtime').resolve()))
from lupa.lua52 import LuaRuntime
def literal(file,name):
 return next(n.value.value for n in ast.parse(Path(file).read_text(encoding='utf-8')).body
  if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
base=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
base=base.replace("assert(record.stage=='craft-request-pending'", "if record.stage=='cache-working' then record=require('serialization').unserialize(s.files['/home/bec_cache.journal']) end\n assert(record.stage=='craft-request-pending'")
base=base.replace("local journal=ser.unserialize(s.files['/home/bec_auto_once.journal'])",
 "local journal=ser.unserialize(s.files['/home/bec_auto.journal']);if journal.stage=='cache-working' then journal=ser.unserialize(s.files['/home/bec_cache.journal']) end")
cache=literal('test_cache.py','EXTRA')
cache=cache.replace("if m=='getState' then return s.newOrderAt and s.now>=s.newOrderAt and 'paused-immediate' or 'idle' end",'')
gpu=literal('test_ui.py','GPU')
setup=r'''
local c=require('component');local previous=c.invoke
function c.invoke(a,m,...)
 if m=='getRequiredTier' then return {tier=4} end
 if m=='getState' and s.holdIdle and s.now<s.holdIdle then return 'idle' end
 return previous(a,m,...)
end
local events=require('event');local previousPull=events.pull
events.pull=function(n)
 local e={previousPull(n)}
 if s.steps and s.steps[1] and s.now>=s.steps[1][1] then
  local step=table.remove(s.steps,1);return 'key_down','keyboard',step[2],step[3]
 end
 if s.quitAt and s.now>=s.quitAt then return 'key_down','keyboard',113,16 end
 return table.unpack(e)
end
function loadfile(path)
 assert(s.sources[path],path);return assert(load(s.sources[path],'='..path,'t',_ENV))
end
'''
passed=0
def run(label,options):
 global passed
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.globals().pyWidth=lambda t:sum(2 if unicodedata.east_asian_width(x) in ('W','F') else 1 for x in t)
 lua.globals().pySub=lambda t,a,b:t[int(a)-1:int(b) if b>=0 else len(t)+int(b)+1]
 lua.execute(base+cache+gpu+setup)
 s=lua.globals().s;s.sources=lua.table()
 for name in ('auto','cache','cache_ui'):
  file=f'bec_{name}_paste.lua' if name in ('auto','cache') else f'bec_{name}.lua'
  s.sources[f'/home/bec_{name}.lua']=Path(file).read_text(encoding='utf-8')
 lua.execute("s.files['/home/bec_cache.config']=require('serialization').serialize({version=1,target=2880},false);"+options)
 lua.execute(Path('bec_ui.lua').read_text(encoding='utf-8'))
 logs=list(s.logs.values())
 assert not any('界面退出：' in x for x in logs),(label,logs)
 assert any('已停止常驻服务' in x for x in logs),(label,logs)
 assert s.width==80 and s.height==25 and not s.cacheEnabled and s.cfg is None
 passed+=1;print(label+': PASS');return lua
lua=run('idle normal UI automatically fills without opening settings','s.holdIdle=100;s.quitAt=6')
assert lua.globals().s.stock.entangled_chromaticglass==2880
assert lua.globals().s.stock.entangled_transcendentmetal==2880
lua=run('Q from settings returns while idle AE job continues',
 "s.holdIdle=100;s.mainStock={};s.quitAt=8;s.steps={{0.2,99},{0.4,113}}")
s=lua.globals().s
assert s.stock.entangled_chromaticglass==2880 and s.stock.entangled_transcendentmetal==2880
assert s.midJobMoves>0
assert any('BEC 预缓存' in x for x in s.draws.values())
lua=run('new order waits only for current cache portion then produces',"s.holdIdle=0.5;s.quitAt=20;s.total=5;s.simultaneous=true")
assert lua.globals().s.completed==5
lua=run('main UI Q during cache preserves unfinished AE request',"s.holdIdle=100;s.mainStock={};s.quitAt=0.6")
s=lua.globals().s
record=lua.eval("require('serialization').unserialize(s.files['/home/bec_cache.journal'])")
assert record.stage=='craft-paused' and record.incomplete
lua=run('editing target in settings while service continues',
 "s.holdIdle=100;s.quitAt=6;s.steps={{0.1,99},{0.2,101},{0.3,49},{0.4,56},{0.5,48},{0.6,48},{0.7,48},{0.8,13,28},{0.9,113}}")
assert lua.eval("require('serialization').unserialize(s.files['/home/bec_cache.config']).target")==18000
assert any('BEC 自动化' in x for x in lua.globals().s.draws.values())
assert lua.globals().s.moves>0
lua=run('confirmed raw remainder is finished before existing new order',
 "s.holdIdle=0.5;s.total=5;s.simultaneous=true;s.quitAt=20;"
 "s.sub={['molten.chromaticglass']=2880};"
 "s.files['/home/bec_cache.journal']=require('serialization').serialize({version=1,kind='cache',background=true,incomplete=true,stage='stopped',configOwned=false,requests={},transfers={},fixedStock=2880,target={entangled_chromaticglass=2880}},false)")
assert lua.globals().s.completed==5
lua=run('no idle topup starts ahead of already dispatched order',
 "s.now=1;s.total=5;s.simultaneous=true;s.quitAt=20")
assert lua.globals().s.completed==5
print(f'{passed} foreground service scenarios passed (mock only).')
