"""Completion fix never changes user state and restores its old program on failure."""
import unittest,subprocess
from pathlib import Path
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
SCRIPT=(HERE/'update_finish.lua').read_text(encoding='utf-8')
OLD=subprocess.check_output(['git','show','07522a8:reinstall_v2/files/runtime/controller.lua'],cwd=HERE.parent).decode()
class FinishUpdateTests(unittest.TestCase):
 def make(self):
  l=fixture();l.globals().files['/home/bec_v2/runtime/controller.lua']=OLD;l.globals().files['/home/bec_v2/state/node-1/production.journal']='watching-keep';return l
 def test_install_idempotence_without_gc_and_no_state_changes(self):
  l=self.make();l.execute('collectgarbage=nil');l.execute(SCRIPT);l.execute(SCRIPT)
  self.assertEqual(l.globals().files['/home/bec_v2/runtime/controller.lua'],(HERE/'files/runtime/controller.lua').read_text(encoding='utf-8'))
  self.assertEqual(l.globals().files['/home/bec_v2/state/node-1/production.journal'],'watching-keep')
 def test_both_rename_failures_restore_old(self):
  for failure in [1,2]:
   l=self.make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failure)+"then return false end;return rename(a,b)end")
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/runtime/controller.lua'],OLD)
 def test_low_space_unknown_program_or_missing_completion_bridge_do_not_install(self):
  for mutation in ['used=4100000',"files['/home/bec_v2/runtime/controller.lua']='custom'","files['/home/bec_v2/lib/bridge.lua']='return {}'"]:
   l=self.make();l.execute(mutation);before=l.globals().files['/home/bec_v2/runtime/controller.lua']
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/runtime/controller.lua'],before)
if __name__=='__main__':unittest.main()
