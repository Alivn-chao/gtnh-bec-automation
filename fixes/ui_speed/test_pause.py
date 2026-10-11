import runpy
from pathlib import Path
g=runpy.run_path(str(Path(__file__).with_name('test_ui_speed.py')))
patch=Path(__file__).with_name('patch_pause.lua').read_text(encoding='utf-8')
r=g['LuaRuntime'](unpack_returned_tuples=True)
r.execute(g['literal']('fixes/process_reset/test_reset.py','installer'))
r.globals().files['/home/bec_ui.lua']=g['patched']
install=r.eval('function()'+patch+'\nend');install()
patched=r.globals().files['/home/bec_ui.lua'];r.execute('assert(load(...))',patched)
writes=r.globals().writes;install();assert writes==r.globals().writes
g['run'].__globals__['patched']=patched
lua=g['run'](r'''
local gpu=require('component').gpu;local set=gpu.set;s.redReasons=0
local bg,fg=gpu.setBackground,gpu.setForeground
gpu.setBackground=function(v,...)s.testBg=v;return bg(v,...)end
gpu.setForeground=function(v,...)s.testFg=v;return fg(v,...)end
gpu.set=function(x,y,t,...)
 if t:find('暂停原因',1,true) then assert(s.testBg==0xb00020 and s.testFg==0xffffff);s.redReasons=s.redReasons+1 end
 return set(x,y,t,...)
end
s.attempts=0
s.controller=function(mode)
 s.attempts=s.attempts+1
 if s.attempts==1 then print('程序停止: /home/bec_auto.lua:310: 缓存恢复：缓存尚未确认完成\nstack traceback: hidden');return end
 assert(mode=='resume');s.resumed=true
 local _,_,char=require('event').pull(.1);assert(char==113)
end
local e=require('event');local oldPull=e.pull
e.pull=function(n,...)
 if (n or 0)>0 and s.attempts==1 then return 'touch','screen',65,28,0 end
 if (n or 0)>0 and s.attempts==2 then return 'key_down','keyboard',113 end
 return oldPull(n,...)
end
''')
assert lua.globals().s.resumed and lua.globals().s.attempts==2
assert lua.globals().s.redReasons>0
assert not any('stack traceback' in t for t in lua.globals().s.draws.values() if '暂停原因' in t)
print('Actual UI red reason, mouse retry enters resume once, no journal mutation, Q exit: PASS')
lua=g['run'](r'''
s.attempts=0;s.controller=function()s.attempts=s.attempts+1;error('unconfirmed request')end
local e=require('event');local oldPull=e.pull
e.pull=function(n,...)
 if (n or 0)>0 and s.attempts==1 then return 'key_down','keyboard',116 end
 if (n or 0)>0 and s.attempts==2 then return 'key_down','keyboard',113 end
 return oldPull(n,...)
end
''')
assert lua.globals().s.attempts==2
print('Controller exception remains on UI; retry failing again remains paused; Q exits: PASS')
