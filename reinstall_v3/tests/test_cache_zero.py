"""GTNH OC false/zero is a no-op; unknown outcomes remain quarantined."""
from pathlib import Path
import unittest
from test_cache_parallel import world
from test_cache_management import setup

SOURCE=(Path(__file__).resolve().parents[2]/'reinstall_v2/files/cache_zero_recover.lua').read_text(encoding='utf-8')

def recovery():
 l=setup();l.globals().RECOVERY=SOURCE;l.execute(r'''
local fs=require('filesystem');fs.get=function()return{spaceTotal=function()return 4000000 end,spaceUsed=function()return 1000000 end}end
change('save','default','1000');change('save','entangled_infinity','0');change('save','entangled_transcendentmetal','0');change('enable')
world.stock={entangled_chromaticglass=288};world.sub={['molten.chromaticglass']=45}
path=C.path('state/group-1/cache.journal')
local route={raw='molten.chromaticglass',address='bulk1',from=4,to=5}
C.write(path,{version=1,kind='cache',background=true,stage='transfer-returned',configOwned=false,fixedStock=1000,copies=1,
 target={entangled_chromaticglass=1000},plan={{raw=route.raw,batch=144,amount=1008}},expected={[route.raw]=1008},secured={[route.raw]=333},
 requests={{raw=route.raw,amount=1008,state='submitted',unit='mB'}},
 transfers={{raw=route.raw,address=route.address,from=4,to=5,requested=333,amount=333,ok=true},{raw=route.raw,address=route.address,from=4,to=5,requested=675,amount=0,ok=false}},
 pending={raw=route.raw,address=route.address,from=4,to=5,amount=675}})
original=s.files[path]
function reconcile(mode,ack)return assert(load(RECOVERY,'zero-recovery','t',_ENV))(mode or 'run',ack or 'ae-finished')end
''');return l

class CacheZeroTests(unittest.TestCase):
 def test_confirmed_false_zero_waits_then_collects_without_duplicate_ae(self):
  for pipeline in (True,False):
   l=world();l.globals().pipeline=pipeline;l.execute(r'''
if not pipeline then s.files[C.path('lib/cache_pipeline.lua')]=nil end
local c=require('component');local invoke=c.invoke;zeros=0
c.invoke=function(a,m,...)if m=='transferFluid'and zeros<3 then zeros=zeros+1;return false,0 end;return invoke(a,m,...)end
steps(1500);assert(not K.blocked and not K.busy and requestCount==3,K.message)
local r=C.read(C.path('state/group-1/cache.journal'));assert(zeros==3 and not r.pending);if pipeline then assert(r.zeroTransfers==3)end
for _,t in ipairs(r.transfers)do assert(t.ok and t.amount>0)end
''')

 def test_false_zero_with_changed_inventory_is_not_cleared_or_replayed(self):
  l=world();l.execute(r'''
local c=require('component');local invoke=c.invoke;attempts=0
c.invoke=function(a,m,...)if m=='transferFluid'then attempts=attempts+1;invoke(a,m,...);return false,0 end;return invoke(a,m,...)end
for i=1,1200 do K.step(E,true);world.advance(.05);if K.blocked then break end end
assert(K.blocked and attempts==1 and C.read(C.path('state/group-1/cache.journal')).pending)
for i=1,50 do K.step(E,true)end;assert(attempts==1)
''')

 def test_recovery_archives_and_credits_manually_converted_inventory(self):
  l=recovery();l.execute(r'''
reconcile();assert(world.calls.transferFluid==nil and world.calls.getCpus==nil)
assert(s.files[path..'.before-zero-recovery-1']==original)
local r=C.read(path);assert(r.stage=='stopped'and r.incomplete and not r.pending and #r.requests==0)
assert(r.reconciliation.originalAERequests[1].state=='submitted'and r.reconciliation.subnet['molten.chromaticglass']==45)
E.groupOwner[1]=nil;E.fluidOwner=nil;K=factoryCache(C,B,cfg,disk);K.assertReady();steps(800)
assert(not K.blocked and next(world.sub)==nil and world.stock.entangled_chromaticglass==1008,K.message)
assert(world.calls.transferFluid==1,'replayed original 333 or 675 intent')
''')

 def test_preview_and_missing_ack_leave_original_and_hardware_unchanged(self):
  l=recovery();l.execute("reconcile('preview');assert(s.files[path]==original and world.calls.transferFluid==nil)")
  with self.assertRaisesRegex(Exception,'需确认'):l.execute("reconcile('run','')")
  l.execute('assert(s.files[path]==original and world.calls.transferFluid==nil)')

 def test_unknown_receipt_unexplained_raw_or_prior_mismatch_refuses_recovery(self):
  for change in ("r.transfers[2].amount=1","r.transfers[1].ok=false","world.sub['molten.chromaticglass']=334","r.secured['molten.chromaticglass']=332"):
   l=recovery();l.execute("local r=C.read(path);"+change+";C.write(path,r);original=s.files[path]")
   with self.assertRaises(Exception):l.execute('reconcile()')
   l.execute('assert(s.files[path]==original and world.calls.transferFluid==nil)')

 def test_credit_change_after_recovery_prevents_new_transfer(self):
  l=recovery();l.execute(r'''
reconcile();world.sub['molten.chromaticglass']=46
K=factoryCache(C,B,cfg,disk)
for i=1,500 do K.step(E,true);world.advance(.05);if K.blocked then break end end
assert(K.blocked and world.calls.transferFluid==nil)
''')

if __name__=='__main__':unittest.main()
