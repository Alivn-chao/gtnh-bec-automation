"""Full read-only inspection and guarded clearing of obsolete cache faults."""
from pathlib import Path
import unittest
from test_read_optimization import fixture
from test_cache_management import setup
from test_production_routes import world,helpers

ROOT=Path(__file__).resolve().parents[2]
SETUP=r'''
for _,n in pairs(nodes)do n.done=true;n.workAllowed=false end
cfg.nodes={cfg.nodes[1]};local g=cfg.groups[1];g.generators={'gen1'};g.bulkTransposers={'bulk'}
g.nanites={enabled=false};g.cellFeed={enabled=false}
C.write(C.path('cache.config'),{version=1,target=1000,overrides={},enabled=true})
local c=require('component');local original=c.invoke
writes=0
c.invoke=function(a,m,...)
 assert(not m:match('^set')and not m:match('^transfer'),'inspection must be read-only')
 if a=='field'and m=='getStoredCondensate'then return{}end
 if a=='sub'and m=='getFluidsInNetwork'then return dirtySub and {{name='unknown',amount=1}}or{}end
 if m=='getFluidInterfaceConfiguration'then return nil end
 if a=='fluid'then
  if m=='getTankCount'then return 6 end
  if m=='getFluidInTank'then return{amount=0}end
 end
 if a=='bulk'then
  local side=...
  if m=='getTankCount'then return side==4 and 1 or side==5 and 6 or 0 end
  if m=='getTankCapacity'then return side==4 and 2147483647 or 16000 end
  if m=='getFluidInTank'then return side==4 and{amount=0,name=not missing and 'quarkgluonplasma'or nil}or{amount=0}end
 end
 return original(a,m,...)
end
E={tasks={{}},groupOwner={[1]='cache-1'},fluidOwner='cache-1'}
disk={status=function()return{known=true,ok=true}end}
function inspect()return loadfile(C.path('lib/recheck.lua'))()(C,cfg,E,disk,{{'entangled_quarkgluonplasma'}})end
'''

class FullRecheckTests(unittest.TestCase):
 def make(self):
  l=fixture();l.execute(SETUP);return l

 def test_read_only_complete_inspection_keeps_old_lock_and_journal(self):
  l=self.make();l.execute(r'''
C.write(C.path('state/group-1/cache.journal'),{kind='cache',stage='stopped',configOwned=false,requests={},transfers={}})
local before=s.files[C.path('state/group-1/cache.journal')];local count=s.writes
local r=inspect();assert(r.ok and r.checked>=13,table.concat(r.issues,' / '))
assert(E.fluidOwner=='cache-1'and E.groupOwner[1]=='cache-1')
assert(s.files[C.path('state/group-1/cache.journal')]==before and s.writes==count)
''')

 def test_lists_multiple_faults_and_rechecks_current_hardware(self):
  l=self.make();l.execute(r'''
missing=true;dirtySub=true;nodes.node1.workAllowed=true
local r=inspect();assert(not r.ok and #r.issues==3)
missing=false;dirtySub=false;nodes.node1.workAllowed=false
assert(inspect().ok)
''')

 def test_unconfirmed_receipts_and_incomplete_records_are_not_reset(self):
  for record in (
   "{stage='waiting-nodes'}",
   "{stage='stopped',pending={}}",
   "{stage='stopped',requests={{state='submitted'}}}",
   "{stage='stopped',transfers={{ok=false}}}",
  ):
   l=self.make();l.execute("C.write(C.path('state/group-1/cache.journal'),"+record+");local before=s.files[C.path('state/group-1/cache.journal')];assert(not inspect().ok);assert(s.files[C.path('state/group-1/cache.journal')]==before)")

 def test_production_resource_owner_prevents_clear(self):
  l=self.make();l.execute('E.fluidOwner=1;E.groupOwner[1]=1;assert(not inspect().ok)')

 def test_completed_hive_record_must_match_a_physically_empty_replacement_bus(self):
  l=self.make();l.execute(r'''
cfg.groups[1].nanites={enabled=true,mode='cell-io',hiveSource='transposer',transposer='bee',hatchSide=4,bankSide=0,loadSide=3,returnSide=2,loadRedstone='lrs',returnRedstone='rrs',loadOutputSide=0,returnOutputSide=0}
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if(a=='lrs'or a=='rrs')and m=='getOutput'then return 0 end
 if a=='bee'then
  local side=...
  if m=='getInventoryName'then return side==4 and 'gt.blockmachines'or 'tile.appliedenergistics2.BlockIOPort'end
  if m=='getInventorySize'then return side==4 and 3 or side==0 and 10 or 12 end
  if m=='getStackInSlot'then return nil end
 end
 return invoke(a,m,...)
end
local path=C.path('state/group-1/nanites-cell.journal')
C.write(path,{version=2,kind='cell-io',stage='done',holding={count=30745}})
local r=inspect();assert(not r.ok and table.concat(r.issues,' / '):find('旧换蜂记录',1,true))
local old=C.read(path);old.holding=nil;C.write(path,old)
assert(not table.concat(inspect().issues,' / '):find('旧换蜂记录',1,true))
''')

 def test_clear_checked_cache_fault_releases_only_stale_cache_lock(self):
  l=setup();l.execute(r'''
K.blocked='old duplicate';K.busy=false;E.groupOwner[1]='cache-1';E.fluidOwner='cache-1'
K.clearCheckedFault(E);assert(not K.blocked and not E.groupOwner[1]and not E.fluidOwner)
K.blocked='must keep';E.groupOwner[1]=1;E.fluidOwner=1
assert(not pcall(K.clearCheckedFault,E)and K.blocked=='must keep'and E.groupOwner[1]==1)
''')

 def test_clear_does_not_bypass_pending_journal(self):
  l=setup();l.execute(r'''
K.blocked='original';C.write(C.path('state/group-1/cache.journal'),{kind='cache',stage='stopped',pending={},configOwned=false})
assert(not pcall(K.clearCheckedFault,E)and K.blocked=='original')
''')

 def test_web_full_check_clears_old_fault_without_starting_or_rewriting_journal(self):
  from test_web_session import SETUP as WEB
  l=setup();l.execute(r'''
local loader=loadfile
loadfile=function(path,...)
 if path==C.path('lib/cache.lua')then return function()return function()return K end end end
 if path==C.path('lib/recheck.lua')then return function()return function()return {version=1,ok=not badCheck,checked=64,issues=badCheck and {'未确认操作'}or{},at=s.now}end end end
 return loader(path,...)
end
'''+WEB+r'''
K.blocked='old duplicate'
local before=s.files[C.path('state/group-1/cache.journal')]
local result=H.handle('recheck_all',{revision=H.snapshot(true).revision},901)
assert(not H.running and not K.blocked and H.recheck.ok and H.recheck.checked==64)
assert(s.files[C.path('state/group-1/cache.journal')]==before)
assert(C.read(C.path('diagnostics/recheck-last.dat')).ok)
K.blocked='must keep';badCheck=true
assert(not pcall(H.handle,'recheck_all',{revision=H.snapshot(true).revision},902))
assert(K.blocked=='must keep'and not H.recheck.ok and not H.running)
''')

 def test_unused_duplicate_is_omitted_but_required_duplicate_still_fails(self):
  l=world();l.execute("fluid.port2='raw2';fluid.port3='raw2'");p=helpers(l)
  routes=p.ports(l.table_from({'cond1':True}));self.assertEqual(routes.raw1.address,'port1');self.assertIsNone(routes.raw2)
  with self.assertRaisesRegex(Exception,'重复绑定'):p.ports(l.table_from({'cond2':True}))

 def test_cache_ignores_unused_time_duplicate_without_changing_selected_fluid(self):
  l=setup();l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if (a=='bulk2'or a=='bulk3')and m=='getFluidInTank'and select(1,...)==4 then return{name='temporalfluid',amount=0}end;return invoke(a,m,...)end
change('save','default','1000');change('save','entangled_infinity','0');change('save','entangled_transcendentmetal','0');change('enable')
steps(600);assert(not K.blocked and world.stock.entangled_chromaticglass==1008)
local r=C.read(C.path('state/group-1/cache.journal'));assert(r.stage=='stopped'and #r.transfers==1 and r.transfers[1].raw=='molten.chromaticglass')
''')

 def test_cache_required_duplicate_still_blocks_before_transfer_or_ae(self):
  l=setup();l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if a=='bulk2'and m=='getFluidInTank'and select(1,...)==4 then return{name='molten.chromaticglass',amount=1000000}end;return invoke(a,m,...)end
change('save','default','1000');change('save','entangled_infinity','0');change('save','entangled_transcendentmetal','0');change('enable')
for i=1,100 do K.step(E,true);world.advance(.05);if K.blocked then break end end
assert(K.blocked and K.blocked:find('重复绑定',1,true)and not world.calls.transferFluid)
assert(not C.read(C.path('state/group-1/cache.journal')))
''')


if __name__=='__main__':unittest.main()
