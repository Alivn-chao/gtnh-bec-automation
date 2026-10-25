"""Batch-local fixed checks, pause-epoch invalidation and cold IO validation."""
import unittest
import test_hive_detection as hive
import test_representative as representative_tests

def session():
 f,l=hive.world()
 l.execute(r'''
files['/home/bec_v2/runtime/controller.lua']="return {hive=loadfile('/home/bec_nanites.lua')(),control=require('component')}"
session=Bridge.environment(cfg,1,engine)();assert(session.hive.ensure())
''')
 return f,l

class FixedHiveCheckTests(unittest.TestCase):
 def test_fixed_identity_and_paused_demand_are_reused_but_pause_is_live(self):
  l=representative_tests.RepresentativeTests().world();l.execute(r'''
R.inspection(true);R.inspection(true)
assert(reads['node16/getRequiredCondensate']==1 and reads['node16/getParallelRecipesInProgress']==1 and reads['node16/getRequiredTier']==1)
assert(reads['node16/getState']==2)
nodes.node16.tier=3;R.invalidateInspection();assert(R.inspection(true).requiredTier==3)
assert(reads['node16/getRequiredTier']==2 and reads['node16/getRequiredCondensate']==1)
outputs['rs16-']=0;assert(not pcall(R.inspection,true))
''')

 def test_repeated_stage_reuses_layout_and_ports_and_refreshes_demand(self):
  f,l=session()
  l.execute("session.control.invoke(P,'setOutput',1,0);session.control.invoke(P,'setOutput',1,15)")
  hive.prepare_switch(l);l.execute('assert(session.hive.ensure())')
  self.assertEqual(l.globals().moves,6);self.assertEqual(l.globals().heldCount,128)
  print('warm same-batch hive-switch callbacks:',int(l.globals().calls))
  self.assertLess(l.globals().calls,120)

 def test_new_worker_fully_checks_unmanaged_io_slots_again(self):
  f,l=session();l.execute('inv[3][12]=disk(0)')
  with self.assertRaisesRegex(Exception,'已有硬盘'):l.execute('local fresh=Bridge.environment(cfg,1,engine)();fresh.hive.ensure()')
  self.assertEqual(l.globals().moves,2)

 def test_uncertain_move_is_not_replayed_even_with_warm_port_cache(self):
  f,l=session();l.execute("session.control.invoke(P,'setOutput',1,0);session.control.invoke(P,'setOutput',1,15)")
  hive.prepare_switch(l);l.execute('broken=true')
  with self.assertRaises(Exception):l.execute('session.hive.ensure()')
  self.assertEqual(l.globals().moves,3)
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'):l.execute('session.hive.ensure()')
  self.assertEqual(l.globals().moves,3)

if __name__=='__main__':unittest.main()
