"""Fresh whole-cohort checks without repeated logical getter expansion."""
import subprocess,unittest
from pathlib import Path
from test_read_optimization import fixture,CAPTURE
ROOT=Path(__file__).resolve().parents[2]
def setup(baseline=False):
 l=fixture()
 if baseline:
  l.globals().s.files['/home/bec_v2/lib/bridge.lua']=subprocess.check_output(['git','show','3a796b2:reinstall_v2/files/lib/bridge.lua'],cwd=ROOT).decode()
  l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()")
 l.execute("cfg.nodes={};nodes={};outputs={};configure(16);cfg.groups[1].nanites={enabled=true,mode='cell-io'};"+CAPTURE)
 l.execute("reads=0;local c=require('component');local old=c.invoke;c.invoke=function(...)reads=reads+1;return old(...)end")
 return l
class HiveInspectionTests(unittest.TestCase):
 def test_sixteen_node_check_keeps_full_recipe_proof_with_fewer_calls(self):
  before=setup(True)
  before.execute("local b=captured.BEC_CELL_IO;local c=captured.require('component');b.checkGroup();c.invoke('rs1-','getOutput',1);c.invoke('node1','getState');c.invoke('node1','getRequiredTier');c.invoke('node1','getRequiredTier')")
  after=setup();after.execute("local v=captured.BEC_CELL_IO.inspect();assert(v.requiredTier==4 and v.allPaused);assert(v.parallel==16)")
  self.assertLess(after.eval('reads'),before.eval('reads')*.4)
  print('16-node hive check OC calls:',before.eval('reads'),'->',after.eval('reads'))
 def test_each_check_reads_fresh_and_rejects_recipe_batch_or_pause_change(self):
  changes=["nodes.node16.required.entangled_chromaticglass=144", "outputs['rs16-']=0", "nodes.node16.tier=0", "E.tasks[1].released=true;nodes.node16.parallel=2;nodes.node16.required={entangled_chromaticglass=576,entangled_transcendentmetal=576}"]
  for mutation in changes:
   l=setup();l.execute('captured.BEC_CELL_IO.inspect();'+mutation)
   with self.assertRaises(Exception):l.execute('captured.BEC_CELL_IO.inspect()')
 def test_outside_cohort_members_are_still_checked(self):
  l=setup();l.execute("E.tasks[1].members[16]=nil;outputs['rs16-']=0")
  with self.assertRaisesRegex(Exception,'暂停整组'):l.execute('captured.BEC_CELL_IO.inspect()')
 def test_cancel_and_generator_running_still_prevent_inspection(self):
  for mutation in ["E.tasks[1].cancel=true", "local c=require('component');local old=c.invoke;c.invoke=function(a,m,...)if a=='gen1'and m=='isWorkAllowed'then return true end;return old(a,m,...)end"]:
   l=setup();l.execute(mutation)
   with self.assertRaises(Exception):l.execute('captured.BEC_CELL_IO.inspect()')
if __name__=='__main__':unittest.main()
