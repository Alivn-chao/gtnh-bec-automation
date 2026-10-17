"""Small updater keeps all machine state and restores both files on failure."""
import subprocess,unittest
from pathlib import Path
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
NAMES=['lib/bridge.lua','runtime/controller.lua']
SCRIPT=(HERE/'update_cohort.lua').read_text(encoding='utf-8')
OLD={n:subprocess.check_output(['git','show','6bb05c6:reinstall_v2/files/'+n],cwd=HERE.parent).decode()for n in NAMES}
def make():
 l=fixture()
 for n,text in OLD.items():l.globals().files['/home/bec_v2/'+n]=text
 l.globals().files['/home/bec_v2/state/group-1/nanites-cell.journal']='unknown-keep'
 return l
class CohortUpdateTests(unittest.TestCase):
 def test_openos_install_and_idempotence_without_gc_or_self_remove(self):
  l=make();l.globals().files['/home/bec_cohort_update.lua']=SCRIPT
  l.execute("collectgarbage=nil;local fs=require('filesystem');fs.remove=function()return false,'busy'end")
  l.execute(SCRIPT)
  for n in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+n],(HERE/'files'/n).read_text(encoding='utf-8'))
  self.assertEqual(l.globals().files['/home/bec_v2/state/group-1/nanites-cell.journal'],'unknown-keep')
  self.assertEqual(l.globals().files['/home/bec_v2/bindings.draft.dat'],'draft-keep')
  count=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,count)
 def test_all_four_rename_failures_restore_both_originals(self):
  for failed in range(1,5):
   l=make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   for n,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],text)
 def test_unknown_local_change_low_space_and_flush_failure_leave_originals(self):
  for flag in ["files['/home/bec_v2/lib/bridge.lua']='custom'",'used=4100000','failFlush=true']:
   l=make();l.execute(flag)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/runtime/controller.lua'],OLD['runtime/controller.lua'])
if __name__=='__main__':unittest.main()
