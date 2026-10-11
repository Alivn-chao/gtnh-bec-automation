import ast,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
def literal(path,name):
 tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
 return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
base=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
source=Path(__file__).with_name('abandon_space.lua').read_text(encoding='utf-8')
setup=r'''
local ser=require('serialization');s.left=576;s.space=144000;s.busy=false;s.enabled=false;s.starts=0
s.files['/home/bec_auto.journal']=ser.serialize({stage='cache-working',requests={},transfers={},configOwned=false},false)
s.files['/home/bec_cache.journal']=ser.serialize({version=1,kind='cache',background=true,stage='stream-crafting',configOwned=false,target={entangled_space=5000000},requests={{raw='spatialfluid',state='submitted',amount=4855536}},transfers={{ok=true,raw='spatialfluid',requested=576,amount=576}}},false)
s.files['/home/bec_cache.config']=ser.serialize({version=1,target=5000000,overrides={entangled_infinity=30000}},false)
s.files['/home/bec_cache.lua']='-- BEC_V1_CACHE_CUSTOM_V1'
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if m=='getCpus'then return {{busy=s.busy}}end
 if m=='getFluidInterfaceConfiguration'then return nil end
 if m=='getState'then return 'idle'end
 if m=='getName'then return 'multi.bec.generator'end
 if a=='237a9cac-118a-4b74-8755-0d0b0ad216c0' then
  if m=='isWorkAllowed'then return true end
  if m=='getStoredCondensate'then
   if s.enabled and not s.failConvert then s.space=s.space+s.left;s.left=0 end
   return {entangled_space=s.space,entangled_infinity=5000112}
  end
 end
 if a=='86311657-33d1-41b5-a0d9-0aee7b5c2c50' and m=='getFluidsInNetwork'then return s.left>0 and {{name='spatialfluid',amount=s.left}}or {}end
 if a=='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'then
  if m=='isWorkAllowed'then return s.enabled end
  if m=='isMachineActive'then return false end
  if m=='setWorkAllowed'then s.enabled=(...);if s.enabled then s.starts=s.starts+1 end;return end
 end
 return invoke(a,m,...)
end
'''
def run(extra=''):
 r=LuaRuntime(unpack_returned_tuples=True);r.execute(base+setup+extra)
 before=r.globals().s.files['/home/bec_auto.journal'];cache=r.globals().s.files['/home/bec_cache.journal']
 ok,err=r.eval('function()'+source+'\nend')()
 assert r.globals().s.files['/home/bec_auto.journal']==before
 return r,ok,err,cache
r,ok,err,old=run();assert ok,err;s=r.globals().s
assert s.space==144576 and s.left==0 and not s.enabled and s.starts==1
assert s.files['/home/bec_cache.journal.before-abandon-1']==old
closed=r.eval("require('serialization').unserialize(s.files['/home/bec_cache.journal'])")
assert closed.abandoned and closed.incomplete is False and len(closed.requests)==0 and closed.target.entangled_space==144576
cfg=r.eval("require('serialization').unserialize(s.files['/home/bec_cache.config'])")
assert cfg.overrides.entangled_space==0 and cfg.overrides.entangled_infinity==30000 and cfg.target==5000000
writes=s.writes;assert r.eval('function()'+source+'\nend')()[0];assert s.writes==writes and s.starts==1
print('Abandon preserves original submitted request archive, converts only held 576, closes new record, config override0, retry idempotent: PASS')
for extra in ('s.busy=true','s.left=575','s.space=144001',"s.files['/home/bec_cache.lua']='old worker'"):
 r,ok,err,old=run(extra);assert not ok and r.globals().s.starts==0
 assert r.globals().s.files['/home/bec_cache.journal']==old
print('Busy AE, changed amounts and unsupported worker stop before conversion or journal reset: PASS')
r,ok,err,old=run('s.failConvert=true');assert not ok and not r.globals().s.enabled
assert r.globals().s.files['/home/bec_cache.journal']==old
r.execute('s.failConvert=false');assert r.eval('function()'+source+'\nend')()[0]
assert r.globals().s.space==144576 and r.globals().s.left==0
print('Conversion timeout turns GEN off, preserves old journal; recorded retry finishes without requesting or re-transferring: PASS')
