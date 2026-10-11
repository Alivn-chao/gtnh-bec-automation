import runpy
from pathlib import Path
g=runpy.run_path(str(Path(__file__).with_name('test_pause.py')))
base=g['g'];patch=Path(__file__).with_name('patch_targets.lua').read_text(encoding='utf-8')
r=base['LuaRuntime'](unpack_returned_tuples=True);r.execute(base['literal']('fixes/process_reset/test_reset.py','installer'))
r.globals().files['/home/bec_ui.lua']=g['patched']
install=r.eval('function()'+patch+'\nend');install();patched=r.globals().files['/home/bec_ui.lua']
assert 'BEC_V1_UI_PAUSE_V1' in patched and 'BEC_V1_UI_SPEED_V2' in patched
writes=r.globals().writes;install();assert r.globals().writes==writes
base['run'].__globals__['patched']=patched
lua=base['run'](r'''
s.stock={entangled_chromaticglass=20000,entangled_transcendentmetal=144000}
s.files['/home/bec_cache.config']=require('serialization').serialize({version=1,target=5000000,overrides={entangled_chromaticglass=30000,entangled_transcendentmetal=0}},false)
local e=require('event');local oldPull=e.pull
e.pull=function(n,...)if s.now>1 then return 'key_down','keyboard',113 end return oldPull(n,...)end
''')
draws=list(lua.globals().s.draws.values())
assert any('30.0k mB' in t for t in draws),draws
assert any('停补' in t for t in draws),draws
# Verify default remains 5M and zero remains an override in the exact target helper.
block=patched.split('-- BEC_V1_UI_TARGETS_V1:',1)[1].split('registry();',1)[0]
block='--'+block
f=base['LuaRuntime'](unpack_returned_tuples=True)
get=f.eval('function(config) local goal=config.target;'+block+' return cacheGoal end')
get=get(f.table_from({'target':5000000,'overrides':f.table_from({'a':200000,'b':0})}))
assert get('a')==200000 and get('b')==0 and get('c')==5000000
print('Actual pause/V2 UI preserves patches; individual target/zero painted; unset default unchanged; installer idempotent: PASS')
