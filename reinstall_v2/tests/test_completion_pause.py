"""A cohort finishing during pause must be verified, not wait for a busy state."""
import unittest,subprocess
from pathlib import Path
from test_read_optimization import fixture
from simulate_two_recipes import WORLD
ROOT=Path(__file__).resolve().parents[2]
def setup(old=False,proof=True):
 l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes'")
 if old:l.globals().s.files['/home/bec_v2/runtime/controller.lua']=subprocess.check_output(['git','show','07522a8:reinstall_v2/files/runtime/controller.lua'],cwd=ROOT).decode()
 world=WORLD.replace("if m=='getRequiredTier'then return not W.finished and {tier=W.recipe().tier}or nil end", "if m=='getRequiredTier'then if W.started and not W.finished then W.finishAtPause=true;return {tier=5}end;return not W.finished and {tier=W.recipe().tier}or nil end")
 completion="W.outputSignal=args[2];if args[2]==15 and W.finishAtPause and not W.finished then W.finished=true;W.readyAt=math.huge;W.outputs[#W.outputs+1]={item='completed'};"
 if not proof:completion+="W.consumed={};E.tasks[1].entries[1].consumed={};"
 world=world.replace('W.outputSignal=args[2]',completion+'end')
 l.execute(world+"for step=1,2000 do E.step();world.advance(.05);if E.tasks[1].fault or #world.outputs>0 and not E.groupOwner[1]then break end end")
 return l
class CompletionPauseTests(unittest.TestCase):
 def test_published_version_reproduces_idle_pause_timeout(self):
  l=setup(old=True);self.assertTrue(l.eval('E.tasks[1].fault'))
  self.assertIn('等待超时，停止',l.eval("table.concat(E.logs,' / ')"))
  self.assertEqual(l.eval("C.read(C.path('state/node-1/production.journal')).stage"),'watching')
 def test_completed_idle_exits_without_another_hive_swap_or_ae_submission(self):
  l=setup();self.assertFalse(l.eval('E.tasks[1].fault'),l.eval("table.concat(E.logs,' / ')"))
  self.assertEqual(l.eval('#world.outputs'),1)
  self.assertIsNone(l.eval('E.groupOwner[1]'))
  self.assertEqual(l.eval("C.read(C.path('state/node-1/production.journal')).stage"),'stopped')
  self.assertIn('无需再换蜂',l.eval("table.concat(E.logs,' / ')"))
 def test_idle_without_consumption_proof_remains_faulted_and_closed(self):
  l=setup(proof=False);self.assertTrue(l.eval('E.tasks[1].fault'))
  self.assertIn('节点空闲但未消耗完需求',l.eval("table.concat(E.logs,' / ')"))
  self.assertFalse(l.eval('world.workAllowed'))
if __name__=='__main__':unittest.main()
