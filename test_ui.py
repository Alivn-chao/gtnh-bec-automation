"""Dashboard bounds, cleanup and controller integration mocks."""
import ast
import sys
import unicodedata
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
def literal(path,name):
    return next(n.value.value for n in ast.parse(Path(path).read_text(encoding='utf-8')).body
                if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
base=literal('test_auto_once.py','MOCK').replace('/home/bec_auto_once.journal','/home/bec_auto.journal')
base+=literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
UI=Path('bec_ui.lua').read_text(encoding='utf-8')
SOURCE=Path('bec_auto.lua').read_text(encoding='utf-8')
GPU=r'''
local c=require('component');local oldRequire=require
local stableEvent=oldRequire('event')
s.width=80;s.height=25;s.frames=0;s.draws={};s.fg=0xffffff;s.bg=0
c.gpu={getResolution=function() return s.width,s.height end,
 getForeground=function() return s.fg,false end,getBackground=function() return s.bg,false end,
 maxResolution=function() return s.maxWidth or 160,s.maxHeight or 50 end,
 setResolution=function(w,h) s.width=w;s.height=h end,
 setForeground=function(color) s.fg=color end,setBackground=function(color) s.bg=color end,
 fill=function(x,y,w,h,char) assert(x>=1 and y>=1 and x+w-1<=s.width and y+h-1<=s.height) end,
 set=function(x,y,text)
  assert(x>=1 and y>=1 and y<=s.height and x+pyWidth(text)-1<=s.width,text)
  s.draws[#s.draws+1]=text;if y==2 then s.frames=s.frames+1 end
  if text:find('程序已退出',1,true) then s.faultDrawn=true end
 end}
local unicode={wlen=function(text) return pyWidth(text) end,
 sub=function(text,a,b) return pySub(text,a,b) end}
function require(name)
 if name=='event' then return stableEvent end
 if name=='unicode' then return unicode end
 if name=='term' then return {clear=function() s.cleared=true end,setCursor=function() end} end
 return oldRequire(name)
end
function loadfile(path) assert(path=='/home/bec_auto.lua');return s.controller end
'''
def width(text):
    return sum(2 if unicodedata.east_asian_width(x) in ('W','F') else 1 for x in text)
def sub(text,a,b):
    a=int(a);b=int(b)
    return text[a-1: b if b>=0 else len(text)+b+1]
def run(label,setup='',mode='run',completed=True):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals().pyWidth=width;lua.globals().pySub=sub
    lua.execute(base+GPU);lua.execute(setup)
    s=lua.globals().s
    s.controller=lua.eval('function(...) '+SOURCE+'\nend')
    oldPull=lua.eval('require("event").pull')
    oldSleep=lua.globals().os.sleep;oldPrint=lua.globals().print
    lua.eval('function(...) '+UI+'\nend')(mode)
    lua.globals().savedPull=oldPull;lua.globals().savedSleep=oldSleep;lua.globals().savedPrint=oldPrint
    assert lua.eval('require("event").pull==savedPull and os.sleep==savedSleep and print==savedPrint')
    assert s.width==80 and s.height==25 and s.fg==0xffffff and s.bg==0
    assert s.frames>0 and s.cleared is True
    if mode=='monitor': assert s.mutations==0 and s.writes==0
    elif completed:
        assert s.completed==s.total and s.output==15 and s.enabled is False and s.cfg is None,list(s.logs.values())
    print(label+': PASS');return lua

lua=run('full service with Chinese dashboard')
assert lua.globals().s.frames>2
run('80 by 25 display bounds','s.maxWidth=80;s.maxHeight=25')
lua=run('large batch streamed with UI',"s.total=40;s.simultaneous=true;s.mainStock={}")
assert lua.globals().s.midJobMoves>0
run('read-only monitor exits without machine writes','s.stopEarly=true',mode='monitor')
# The original mock event factory creates a new table on each require. Use a
# stable event table for touch injection, like real OpenOS package caching.
touch=r'''
local originalRequire=require;local events=originalRequire('event');local oldPull=events.pull
function require(name) if name=='event' then return events end return originalRequire(name) end
events.pull=function(seconds,...)
 local result={oldPull(seconds,...)}
 if s.now>1 then return 'touch','screen',3,s.height-1,0 end
 return table.unpack(result)
end
'''
lua=run('touch stop passes through controller',touch,completed=False)
assert lua.globals().s.output==15 and lua.globals().s.enabled is False
fault="""
s.noCpuObject=true
local e=require('event');local original=e.pull
e.pull=function(n,...)
 local result={original(n,...)}
 if s.now>2 then return 'key_down','keyboard',113 end
 return table.unpack(result)
end
"""
lua=run('controller fault stays visible until exit',fault,completed=False)
assert lua.globals().s.faultDrawn is True
waiting="""
s.now=1;s.total=1;s.simultaneous=true
s.files['/home/bec_auto.journal']=require('serialization').serialize({version=1,kind='continuous',
 stage='waiting',configOwned=false,target={entangled_chromaticglass=288,entangled_transcendentmetal=288},
 transfers={{ok=true,amount=288}},requests={{state='done'}}},false)
"""
lua=run('run with retained wait journal displays fault without writing machines',waiting+fault.replace('s.noCpuObject=true',''),completed=False)
assert lua.globals().s.faultDrawn is True and lua.globals().s.mutations==0
run('UI resume retained wait journal',waiting,mode='resume')
restock="""
s.now=1;s.total=40;s.simultaneous=true;s.parallel=39;s.group=39;s.active=true
s.sub={};s.stock={};s.consumed={}
s.mainStock={['molten.chromaticglass']=4752,['molten.transcendentmetal']=3301448}
s.files['/home/bec_auto.journal']=require('serialization').serialize({version=1,kind='continuous',
 stage='converting',configOwned=false,batchCount=40,plan=nil,required=s.required,remaining=s.required,
 target={entangled_chromaticglass=11520,entangled_transcendentmetal=11520},
 expected={['molten.chromaticglass']=11520,['molten.transcendentmetal']=11520},
 transfers={{ok=true,amount=11520},{ok=true,amount=11520}},requests={{state='done'}}},false)
"""
lua=run('UI explicit restock current deficit',restock,mode='restock')
assert lua.globals().s.requests==1 and lua.globals().s.requestAmount==6768
handoff=touch.replace("return 'touch','screen',3,s.height-1,0", "if not s.cacheOpened then return 'key_down','keyboard',99,46 end;return 'key_down','keyboard',113,16")+r'''
local originalLoad=loadfile
function loadfile(path,...)
 if path=='/home/bec_cache_ui.lua' then return function(mode)
  assert(mode=='embedded')
  s.cacheOpened=true
  return {draw=function()end,log=function()end,handle=function(e)
   if e[1]=='key_down' and e[3]==113 then
    s.cacheReturned=true
    assert(not s.files['/home/bec_auto.journal']:find('stopped'),'cache Q stopped production')
    return 'back'
   end
  end}
 end end
 return originalLoad(path,...)
end
'''
lua=run('cache settings Q returns without stopping production',handoff,completed=False)
assert lua.globals().s.cacheOpened and lua.globals().s.cacheReturned
patterns=touch.replace("return 'touch','screen',3,s.height-1,0", "if not s.patternInvoked then return 'key_down','keyboard',115,31 end;return 'key_down','keyboard',113,16")+r'''
local originalLoad=loadfile
function loadfile(path,...)
 if path=='/home/bec_patterns.lua' then return function(mode)
  assert(mode=='run');s.patternInvoked=true
  print('槽 1：转换完成并登记：Primitive Waveguide')
 end end
 return originalLoad(path,...)
end
'''
lua=run('S runs workshop handler and captures results without leaving UI',patterns,completed=False)
assert lua.globals().s.patternInvoked
assert any('Primitive Waveguide' in x for x in lua.globals().s.draws.values())
monitorPatterns=patterns.replace('if not s.patternInvoked then', 'if not s.readOnlyAttempt then s.readOnlyAttempt=true;')
lua=run('monitor refuses sample writes',monitorPatterns,mode='monitor')
assert not lua.globals().s.patternInvoked
print('12 dashboard scenarios passed (mock only).')
