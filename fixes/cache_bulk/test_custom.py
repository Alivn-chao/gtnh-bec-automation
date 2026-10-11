"""Actual mouse UI and worker per-fluid configuration tests (Lua 5.2 mocks)."""
import runpy
from pathlib import Path
g=runpy.run_path(str(Path(__file__).with_name('test_fast.py')))
LuaRuntime=g['LuaRuntime'];literal=g['literal'];ROOT=g['ROOT'];HERE=g['HERE']
source=(HERE/'bec_cache_custom.lua').read_text(encoding='utf-8')
patch=(HERE/'patch_custom.lua').read_text(encoding='utf-8')
for fast in (False,True):
 r=LuaRuntime(unpack_returned_tuples=True);r.execute(literal('fixes/process_reset/test_reset.py','installer'))
 for path,text in g['originals'].items():r.globals().files[path]=text
 if fast:r.eval('function()'+g['patch']+'\nend')()
 originals={path:r.globals().files[path] for path in g['originals']}
 r.globals().files['/home/bec_cache.config']='keep config';r.globals().files['/home/bec_cache.journal']='keep journal'
 r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if failUI and b=='/home/bec_cache_ui.lua' and a:find('cache-custom-new',1,true)then return false end return rename(a,b)end")
 install=r.eval('function()'+patch+'\nend');r.globals().failUI=True
 try:install();raise AssertionError('expected rollback')
 except Exception as e:assert '已还原' in str(e)
 for path,text in originals.items():assert r.globals().files[path]==text
 r.globals().failUI=False;install()
 assert r.globals().files['/home/bec_cache.lua']==source
 for path in originals:r.execute('assert(load(...))',r.globals().files[path])
 assert r.globals().files['/home/bec_cache.config']=='keep config'
 assert r.globals().files['/home/bec_cache.journal']=='keep journal'
 assert 'BEC_V1_PIPELINE_V1' in r.globals().files['/home/bec_auto.lua']
 writes=r.globals().writes;install();assert r.globals().writes==writes
ui=r.globals().files['/home/bec_cache_ui.lua']
print('Priority/fast upgrades compile; rollback, retry, idempotence, config/journal/pipeline preserved: PASS')
def run(setup):
 r=LuaRuntime(unpack_returned_tuples=True);r.execute(g['base']+g['extra']+setup)
 ok,error=r.eval('function(...)'+source+'\nend')('background-stock',144000)
 assert ok,(error,list(r.globals().s.logs.values()))
 return r
config="s.files['/home/bec_cache.config']=require('serialization').serialize({version=1,target=144000,overrides={entangled_chromaticglass=%s}},false)"
r=run(config%30000);assert r.globals().s.stock.entangled_chromaticglass>=30000 and r.globals().s.stock.entangled_chromaticglass<31000
r=run(config%0);assert r.globals().s.moves==0 and r.globals().s.requests==0
r=run(config%20000);assert r.globals().s.stock.entangled_chromaticglass>=20000 and r.globals().s.stock.entangled_chromaticglass<21000
r=run('');assert r.globals().s.stock.entangled_chromaticglass==144000
print('Worker uses individual targets, zero performs no refill, unset fluid uses default: PASS')
u=g['u'];u.execute("s.files['/home/bec_cache.config']=require('serialization').serialize({version=1,target=5000000},false)")
view=u.eval('function(...)'+ui+'\nend')('embedded');view.draw(True)
def event(**kw):view.handle(u.table_from({int(k):v for k,v in kw.items()}))
def touch(x,y,button=0):view.handle(u.table_from({1:'touch',2:'screen',3:x,4:y,5:button}));view.draw(True)
def key(ch,code=0):view.handle(u.table_from({1:'key_down',2:'keyboard',3:ch,4:code}))
def cfg():return u.eval("require('serialization').unserialize(s.files['/home/bec_cache.config'])")
# Fixture sorts Chromatic Glass before Transcendent Metal.
touch(5,9)
for ch in '30000':key(ord(ch))
touch(3,7)
assert cfg().target==5000000 and cfg().overrides.entangled_chromaticglass==30000
touch(5,10);key(48);touch(3,7)
assert cfg().overrides.entangled_transcendentmetal==0
touch(5,9);key(49);touch(20,7)
assert cfg().overrides.entangled_chromaticglass==30000
touch(5,9,1)
assert cfg().overrides.entangled_chromaticglass is None and cfg().overrides.entangled_transcendentmetal==0
key(101)
for ch in '100000':key(ord(ch))
key(13)
assert cfg().target==100000 and cfg().overrides.entangled_transcendentmetal==0
view=u.eval('function(...)'+ui+'\nend')('embedded');view.draw(True)
touch(5,9);key(48);touch(3,7)
assert cfg().target==100000 and cfg().overrides.entangled_chromaticglass==0
print('Actual embedded mouse save/cancel/right restore; global edit preserves overrides; reload and zero: PASS')
