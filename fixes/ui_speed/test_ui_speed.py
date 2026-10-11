"""UI-only cache and event responsiveness, using the real uploaded V1 UI."""
import ast
import sys
import unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

def literal(path,name):
    tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
    return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign)
        and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))

source=(Path(__file__).parent/'patch_v1.lua').read_text(encoding='utf-8')
ui=Path(sys.argv[1]).read_text(encoding='utf-8')
runtime=LuaRuntime(unpack_returned_tuples=True)
runtime.execute(literal('fixes/process_reset/test_reset.py','installer'))
runtime.globals().files['/home/bec_ui.lua']=ui
runtime.globals().files['/home/bec_auto.lua']='preserve controller'
runtime.globals().files['/home/bec_auto.journal']='preserve journal'
install=runtime.eval('function()'+source+'\nend')
install()
patched=runtime.globals().files['/home/bec_ui.lua']
assert runtime.globals().files['/home/bec_ui.lua.before-ui-speed-1']==ui
assert runtime.globals().files['/home/bec_auto.lua']=='preserve controller'
assert runtime.globals().files['/home/bec_auto.journal']=='preserve journal'
writes=runtime.globals().writes
install()
assert runtime.globals().writes==writes
print('Actual UI patch syntax, unique backup, repeat install, unchanged controller/journals: PASS')

base=literal('test_auto_once.py','MOCK').replace('/home/bec_auto_once.journal','/home/bec_auto.journal')
base+=literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
gpu=literal('test_ui.py','GPU')
extra=r'''
local c=require('component');s.buffer=0
c.gpu.getActiveBuffer=function()return s.buffer end
c.gpu.allocateBuffer=function()return 1 end
c.gpu.setActiveBuffer=function(n)local old=s.buffer;s.buffer=n;return old end
c.gpu.bitblt=function()s.blits=(s.blits or 0)+1;return true end
c.gpu.freeBuffer=function()s.freed=true;return true end
local invoke=c.invoke
s.uiQueries={}
function c.invoke(a,m,...)
 s.uiQueries[m]=(s.uiQueries[m] or 0)+1
 if a=='cf2a0c4a-ab8d-4958-b1df-253094d6690c' then
  if m=='isMachineActive'then return true end
  if m=='getCondensateFilters'then return {'entangled_chromaticglass'} end
 end
 return invoke(a,m,...)
end
local ser=require('serialization')
s.files['/home/bec_nanites_io.journal']=ser.serialize({version=2,kind='cell-io',stage='done'},false)
s.files['/home/bec_nanites.journal']=ser.serialize({stage='filling'},false)
s.files['/home/bec_auto.journal']=ser.serialize({stage='watching'},false)
s.files['/home/bec_cache.config']=ser.serialize({target=144000},false)
s.controller=function()
 s.controllerStarted=true
 local e=require('event')
 while true do local name,_,char=e.pull(.1,'key_down');if name=='key_down'and char==113 then break end end
end
'''
def width(text):
    return sum(2 if unicodedata.east_asian_width(x) in ('W','F') else 1 for x in text)
def sub(text,a,b):
    return text[int(a)-1:int(b) if b>=0 else len(text)+int(b)+1]
def run(inject):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().pyWidth=width;lua.globals().pySub=sub
    lua.execute(base+gpu+extra+inject)
    lua.eval('function(...)'+patched+'\nend')('run')
    s=lua.globals().s
    assert s.width==80 and s.height==25 and s.cleared and s.freed
    assert not any('装入蜂群' in row for row in s.draws.values()), list(s.logs.values())
    assert s.mutations==0 and s.writes==0  # UI did not change production
    assert s.uiQueries.getConsumedCondensate is None
    return lua

flip=r'''
local events=require('event');local oldPull=events.pull;s.pageEvents=0
events.pull=function(n,...)
 if s.now>1 then return 'key_down','keyboard',113 end
 if (n or 0)>0 then s.pageEvents=s.pageEvents+1;return 'key_down','keyboard',110 end
 return oldPull(n,...)
end
'''
# Advance time for input events even though they arrive before the deadline.
flip=flip.replace("s.pageEvents=s.pageEvents+1;return", "s.pageEvents=s.pageEvents+1;s.now=s.now+.1;return")
lua=run(flip)
s=lua.globals().s
assert s.pageEvents>=5
assert s.uiQueries.getStoredCondensate==1,s.uiQueries.getStoredCondensate
assert s.uiQueries.getState==1,s.uiQueries.getState
assert any('关闭' in row for row in s.draws.values())  # cached false remains false
print('Rapid page clicks reuse one snapshot, false values and new IO done status preserved: PASS')

early=r'''
local events=require('event');local oldPull=events.pull;local c=require('component');local invoke=c.invoke
function c.invoke(a,m,...)
 if m=='getState'then s.armQuit=true end
 return invoke(a,m,...)
end
events.pull=function(n,...)
 if s.armQuit then return 'key_down','keyboard',113 end
 return oldPull(n,...)
end
'''
lua=run(early)
assert not lua.globals().s.controllerStarted
assert lua.globals().s.uiQueries.getStoredCondensate is None
print('Q during snapshot sampling skips remaining queries and never starts controller: PASS')
