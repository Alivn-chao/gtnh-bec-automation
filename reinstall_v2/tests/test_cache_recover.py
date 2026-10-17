"""Explicit, bounded reconciliation; no AE task replay or inferred receipts."""
import unittest,subprocess
from pathlib import Path
from test_read_optimization import fixture
from simulate_two_recipes import WORLD
from test_cache_management import SETUP
SOURCE=(Path(__file__).resolve().parents[1]/'files/cache_recover.lua').read_text(encoding='utf-8')
def setup():
 l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27;BULK_COUNT=10")
 l.execute(WORLD.replace("entangled_infinity='molten.infinity'}","entangled_infinity='molten.infinity',entangled_space='spatialfluid'}")+SETUP)
 l.execute(r'''
local fs=require('filesystem');fs.get=function()return {spaceTotal=function()return 4000000 end,spaceUsed=function()return 1000000 end}end
os.sleep=function(dt)world.advance(dt)end
world.main.spatialfluid=1000;world.sub={spatialfluid=1522272};world.stock={entangled_space=1008,entangled_chromaticglass=123}
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if m=='getCraftables'or m=='getCpus'then error('AE must not be called')end
 if a=='bulk7'and(m=='getTankCapacity'or m=='getFluidInTank')then local from,i=...;return invoke(a,m,from==0 and 4 or from,i)end
 if a=='bulk7'and m=='transferFluid'then local from,to,n=...;assert(from==0);return invoke(a,m,4,to,n)end
 return invoke(a,m,...)
end
path=C.path('state/group-1/cache.journal')
local ts={};for _,n in ipairs({1466496,15840,15840,24096})do ts[#ts+1]={raw='spatialfluid',address='bulk7',from=0,to=5,amount=n,requested=n,ok=true}end
ts[4].requested=31680
C.write(path,{version=1,kind='cache',stage='transfer-returned',configOwned=false,background=true,
 requests={{raw='spatialfluid',amount=2533440,securedBefore=1466496,unit='mB',state='submitted'}},
 plan={{raw='spatialfluid',batch=144,amount=4000032}},target={entangled_space=4000000},
 secured={spatialfluid=1498176},expected={spatialfluid=4000032},transfers=ts,
 pending={address='bulk7',raw='spatialfluid',amount=31680,from=0,to=5}})
original=s.files[path];formal=s.files[C.path('config.dat')]
''')
 l.globals().RECOVERY=SOURCE
 return l
def run(l,mode='run',ack='ae-finished'):
 l.globals().MODE=mode;l.globals().ACK=ack
 l.execute("assert(load(RECOVERY,'@cache_recover.lua','t',_ENV))(MODE,ACK)")
class CacheRecoverTests(unittest.TestCase):
 def test_preview_is_read_only(self):
  l=setup();run(l,'preview')
  l.execute("assert(s.files[path]==original and not s.files[path..'.before-partial-recovery-1']);assert(world.calls.transferFluid==nil and world.calls.setWorkAllowed==nil)")
 def test_exact_real_receipts_pad_96_once_and_archive_original(self):
  l=setup();run(l)
  l.execute("assert(world.calls.transferFluid==1 and world.main.spatialfluid==904);assert(next(world.sub)==nil and world.stock.entangled_space==1523376 and world.stock.entangled_chromaticglass==123);assert(s.files[path..'.before-partial-recovery-1']==original and s.files[C.path('config.dat')]==formal);local r=C.read(path);assert(r.stage=='stopped'and not r.pending and not r.plan);assert(r.reconciliation.returnedAmount==24096 and r.reconciliation.originalAERequests[1].state=='submitted');assert(#r.requests==0 and r.transfers[5].amount==96);K=factoryCache(C,B,cfg,disk);K.assertReady();assert(not world.gen.gen1 and not world.gen.gen2 and not world.workAllowed and world.outputSignal==15)")
  with self.assertRaisesRegex(Exception,'其他未确认状态保留'):run(l)
  self.assertEqual(l.eval('world.calls.transferFluid'),1)
 def test_mismatch_active_node_no_ack_and_unknown_receipt_leave_original(self):
  for change in ["world.sub.spatialfluid=1498176","world.workAllowed=true","C.write(C.path('state/group-1/cohort.dat'),{stage='running'})","C.write(C.path('state/node-1/production.journal'),{stage='stopped',configOwned=false,requests={{state='submitted'}}})","local r=C.read(path);r.transfers[4].ok=false;C.write(path,r);original=s.files[path]"]:
   l=setup();l.execute(change)
   with self.assertRaises(Exception):run(l)
   l.execute("assert(s.files[path]==original and world.calls.transferFluid==nil)")
  l=setup()
  with self.assertRaisesRegex(Exception,'需先确认'):run(l,ack='')
  l.execute('assert(s.files[path]==original and world.calls.transferFluid==nil)')
 def test_unknown_padding_result_is_preserved_and_never_replayed(self):
  for result in ["return false,96","return true,nil","error('receipt lost')","return true,95"]:
   l=setup();l.execute("local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,...)if m=='transferFluid'then invoke(a,m,...);"+result+" end;return invoke(a,m,...)end")
   with self.assertRaises(Exception):run(l)
   l.execute("assert(C.read(path).pending and s.files[path..'.before-partial-recovery-1']==original);assert(not world.gen.gen1 and not world.gen.gen2)")
   with self.assertRaises(Exception):run(l)
   self.assertEqual(l.eval('world.calls.transferFluid'),1)
 def test_partial_padding_and_zero_return_only_complete_remaining_96(self):
  l=setup();l.execute("local c=require('component');local invoke=c.invoke;local calls=0;c.invoke=function(a,m,...)if m=='transferFluid'then calls=calls+1;if calls==1 then return true,0 end;local f,t,n=...;return invoke(a,m,f,t,math.min(n,32))end;return invoke(a,m,...)end")
  run(l);self.assertEqual(l.eval('world.main.spatialfluid'),904)
 def test_shortage_does_not_request_ae_or_start_conversion(self):
  l=setup();l.execute('world.main.spatialfluid=0')
  with self.assertRaisesRegex(Exception,'不申请AE'):run(l)
  l.execute("assert(s.files[path]==original and not s.files[path..'.before-partial-recovery-1'] and world.calls.transferFluid==nil and not world.gen.gen1 and not world.gen.gen2)")
 def test_main_inventory_over_int32_and_large_unrelated_field_are_valid(self):
  l=setup();l.execute('world.main.spatialfluid=5000000000;world.main.unrelated=1000000000000;world.stock.entangled_chromaticglass=7000000000;world.stock.entangled_space=3000000000')
  run(l)
  l.execute('assert(world.main.spatialfluid==4999999904 and world.stock.entangled_space==3001522368 and world.stock.entangled_chromaticglass==7000000000)')
 def test_reproduce_published_pretransfer_failure_then_resume_without_duplicate(self):
  l=setup();l.execute('world.main.unrelated=5000000000')
  old_source=subprocess.check_output(['git','show','166f844:reinstall_v2/files/cache_recover.lua'],cwd=Path(__file__).resolve().parents[2]).decode()
  l.globals().RECOVERY=old_source
  with self.assertRaisesRegex(Exception,'库存数量无效'):run(l)
  l.execute("assert(C.read(path).stage=='reconciling-partial'and not C.read(path).pending and world.calls.transferFluid==nil);assert(s.files[path..'.before-partial-recovery-1']==original)")
  l.globals().RECOVERY=SOURCE;run(l)
  l.execute("assert(world.calls.transferFluid==1 and world.main.spatialfluid==904 and C.read(path).stage=='stopped');assert(not s.files[path..'.before-partial-recovery-2']and s.files[path..'.before-partial-recovery-1']==original)")
 def test_pretransfer_resume_requires_exact_checkpoint_and_archive(self):
  for corruption in ["r.pending={raw='spatialfluid',amount=96}","r.transfers[4].amount=24095","r.reconciliation.operatorConfirmedAEFinished=false","r.target.entangled_space=r.target.entangled_space+144","s.files[r.reconciliation.archive]='bad archive'"]:
   l=setup();l.globals().RECOVERY=subprocess.check_output(['git','show','166f844:reinstall_v2/files/cache_recover.lua'],cwd=Path(__file__).resolve().parents[2]).decode()
   l.execute('world.main.unrelated=5000000000')
   with self.assertRaisesRegex(Exception,'库存数量无效'):run(l)
   l.execute('local r=C.read(path);'+corruption+';C.write(path,r);beforeResume=s.files[path]')
   l.globals().RECOVERY=SOURCE
   with self.assertRaises(Exception):run(l)
   l.execute('assert(world.calls.transferFluid==nil and s.files[path]==beforeResume)')
 def test_nonfinite_fractional_negative_and_inexact_inventory_rejected_read_only(self):
  for n in ['0/0','math.huge','-.5','1.5','9007199254740992']:
   l=setup();l.execute('world.main.invalid='+n)
   # WORLD inventory rows omit negative values, so inject malformed hardware rows.
   l.execute("local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,...)if a=='main'and m=='getFluidsInNetwork'then return {{name='invalid',amount=world.main.invalid}}end;return invoke(a,m,...)end")
   with self.assertRaisesRegex(Exception,'库存数量无效'):run(l)
   l.execute('assert(s.files[path]==original and world.calls.transferFluid==nil)')
 def test_generator_start_failure_closes_both_and_preserves_recovery(self):
  l=setup();l.execute("local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,...)if a=='gen2'and m=='setWorkAllowed'and (...)==true then error('generator failed')end;return invoke(a,m,...)end")
  with self.assertRaisesRegex(Exception,'generator failed'):run(l)
  l.execute("assert(not world.gen.gen1 and not world.gen.gen2);assert(C.read(path).stage=='recovery-converting'and s.files[path..'.before-partial-recovery-1']==original)")
  with self.assertRaises(Exception):run(l)
if __name__=='__main__':unittest.main()
