import runpy
from pathlib import Path
g=runpy.run_path(str(Path(__file__).with_name('test_abandon.py')))
source=Path(__file__).with_name('reset_cache.lua').read_text(encoding='utf-8')
prepare=r'''
local ser=require('serialization')
local old=ser.unserialize(s.files['/home/bec_cache.journal']);old.secured={spatialfluid=576};s.files['/home/bec_cache.journal']=ser.serialize(old,false)
'''
def run(extra='',setup=None):
 r=g['LuaRuntime'](unpack_returned_tuples=True);r.execute(g['base']+(setup or g['setup'])+prepare+extra)
 before=r.globals().s.files['/home/bec_auto.journal'];old=r.globals().s.files['/home/bec_cache.journal']
 ok,err=r.eval('function()'+source+'\nend')()
 assert r.globals().s.files['/home/bec_auto.journal']==before
 return r,ok,err,old
r,ok,err,old=run();assert ok,err;s=r.globals().s
assert s.space==144576 and s.left==0 and s.starts==1 and not s.enabled
assert s.files['/home/bec_cache.journal.before-reset-1']==old
closed=r.eval("require('serialization').unserialize(s.files['/home/bec_cache.journal'])")
assert closed.abandoned and closed.target.entangled_space==144576 and len(closed.requests)==0
cfg=r.eval("require('serialization').unserialize(s.files['/home/bec_cache.config'])")
assert cfg.overrides.entangled_space==0 and cfg.overrides.entangled_infinity==30000
w=s.writes;assert r.eval('function()'+source+'\nend')()[0];assert s.writes==w
# A later independent failure must start a new reset instead of reusing the completed one.
r.execute(g['setup']+prepare);assert r.eval('function()'+source+'\nend')()[0]
assert s.files['/home/bec_cache.reset.before-reset-1'] is not None
print('General cache reset, new closure with original archive, inventory/config preserved, repeated and later reset: PASS')
for extra in ('s.busy=true',"local old=require('serialization').unserialize(s.files['/home/bec_cache.journal']);old.pending={};s.files['/home/bec_cache.journal']=require('serialization').serialize(old,false)", 's.left=577'):
 r,ok,err,old=run(extra);assert not ok and r.globals().s.starts==0 and r.globals().s.files['/home/bec_cache.journal']==old
print('Busy AE / pending transfer / non-integral batch refuse reset: PASS')
r,ok,err,old=run('s.failConvert=true');assert not ok and not r.globals().s.enabled
r.execute('s.failConvert=false');assert r.eval('function()'+source+'\nend')()[0]
assert r.globals().s.space==144576
# An interrupted reset with a partially converted inventory continues only the remainder.
r,ok,err,old=run('s.failConvert=true');assert not ok
r.execute('s.space=144288;s.left=288;s.failConvert=false');assert r.eval('function()'+source+'\nend')()[0]
assert r.globals().s.space==144576
r,ok,err,old=run('s.failConvert=true');assert not ok
r.execute('s.space=144287;s.left=288;s.failConvert=false');ok,err=r.eval('function()'+source+'\nend')()
assert not ok and not r.globals().s.enabled and r.globals().s.files['/home/bec_cache.journal']==old
print('Timeout/Q preserves reset checkpoint; partially converted remainder resumes with conservation check: PASS')
multi=r'''
local ser=require('serialization');s.raws={['molten.chromaticglass']=288,phononmedium=1000};s.stocks={entangled_chromaticglass=12000,entangled_phononmedium=2000,entangled_space=144000}
local old=ser.unserialize(s.files['/home/bec_cache.journal']);old.target={entangled_chromaticglass=5000000,entangled_phononmedium=200000};old.secured=s.raws;old.requests={};old.transfers={};s.files['/home/bec_cache.journal']=ser.serialize(old,false)
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if a=='237a9cac-118a-4b74-8755-0d0b0ad216c0' and m=='getStoredCondensate'then
  if s.enabled then s.stocks.entangled_chromaticglass=s.stocks.entangled_chromaticglass+(s.raws['molten.chromaticglass']or 0);s.stocks.entangled_phononmedium=s.stocks.entangled_phononmedium+(s.raws.phononmedium or 0);s.raws={}end
  local out={};for k,v in pairs(s.stocks)do out[k]=v end return out
 end
 if a=='86311657-33d1-41b5-a0d9-0aee7b5c2c50' and m=='getFluidsInNetwork'then local out={};for k,v in pairs(s.raws)do out[#out+1]={name=k,amount=v}end return out end
 return invoke(a,m,...)
end
'''
r,ok,err,old=run(multi);assert ok,err
assert r.globals().s.stocks.entangled_chromaticglass==12288 and r.globals().s.stocks.entangled_phononmedium==3000
assert r.globals().s.stocks.entangled_space==144000
print('Different fluids and 144/1000 batch sizes reset together; unrelated condensate unchanged: PASS')
# Actual patched pause UI: install the embedded worker, mouse Z, then automatic resume.
u=runpy.run_path(str(Path(__file__).parents[1]/'ui_speed/test_targets.py'))
uiBase=u['base'];installRuntime=uiBase['LuaRuntime'](unpack_returned_tuples=True)
installRuntime.execute(uiBase['literal']('fixes/process_reset/test_reset.py','installer'))
installRuntime.globals().files['/home/bec_ui.lua']=u['patched']
patch=Path(__file__).with_name('patch_reset_button.lua').read_text(encoding='utf-8')
installRuntime.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if failSwap and b=='/home/bec_ui.lua' and a:find('ui-reset-new',1,true)then return false end return rename(a,b)end")
install=installRuntime.eval('function()'+patch+'\nend');installRuntime.globals().failSwap=True
try:install();raise AssertionError('expected install rollback')
except Exception as e:assert '已还原' in str(e)
assert installRuntime.globals().files['/home/bec_ui.lua']==u['patched']
installRuntime.globals().failSwap=False;install();patched=installRuntime.globals().files['/home/bec_ui.lua']
w=installRuntime.globals().writes;install();assert w==installRuntime.globals().writes
assert 'BEC_V1_UI_TARGETS_V1' in patched and 'BEC_V1_UI_PAUSE_V1' in patched
r=uiBase['LuaRuntime'](unpack_returned_tuples=True);r.globals().pyWidth=uiBase['width'];r.globals().pySub=uiBase['sub']
r.execute(uiBase['base']+uiBase['gpu']+uiBase['extra']+g['setup']+prepare+r'''
s.attempts=0
s.controller=function(mode)
 s.attempts=s.attempts+1
 if s.attempts==1 then print('程序停止: 缓存尚未确认完成');return end
 assert(mode=='resume');s.resumed=true
 local _,_,ch=require('event').pull(.1);assert(ch==113)
end
local e=require('event');local oldPull=e.pull;s.clicked=false
e.pull=function(n,...)
 if (n or 0)>0 and s.attempts==1 and not s.clicked then s.clicked=true;return 'touch','screen',10,28,0 end
 if (n or 0)>0 and s.resumed then return 'key_down','keyboard',113 end
 return oldPull(n,...)
end
''')
r.eval('function(...)'+patched+'\nend')('resume')
assert r.globals().s.resumed and r.globals().s.attempts==2 and r.globals().s.space==144576
assert r.globals().s.left==0 and not r.globals().s.enabled
print('Actual V2/pause/targets UI install rollback/retry/idempotence; mouse Z converts held fluid and starts resume once: PASS')
