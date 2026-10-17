"""Three-file update, journal preservation and rollback of every rename."""
import subprocess
import unittest
from pathlib import Path
from test_web_update import fixture

HERE=Path(__file__).resolve().parents[1]
NAMES=['lib/bridge.lua','runtime/controller.lua','runtime/nanites_cell.lua']
SCRIPT=(HERE/'update_dynamic_nanites.lua').read_text(encoding='utf-8')
OLD={n:subprocess.check_output(['git','show','dae5e0e:reinstall_v2/files/'+n],cwd=HERE.parent).decode()for n in NAMES}

def make():
 l=fixture()
 for n,text in OLD.items():l.globals().files['/home/bec_v2/'+n]=text
 l.globals().files['/home/bec_v2/state/group-1/cohort.dat']='interrupted-cohort-keep'
 l.globals().files['/home/bec_v2/state/group-1/nanites-cell.journal']='holding-gold-keep'
 l.globals().files['/home/bec_v2/recipes/test.dat']='recipe-keep'
 return l

class DynamicUpdateTests(unittest.TestCase):
 def test_only_programs_change_and_repeated_update_is_noop(self):
  l=make();l.execute(SCRIPT)
  for n,text in OLD.items():
   p='/home/bec_v2/'+n
   self.assertEqual(l.globals().files[p+'.before-dynamic-1'],text)
   self.assertEqual(l.globals().files[p],(HERE/'files'/n).read_text(encoding='utf-8'))
  for p,value in {'config.dat':'incomplete-keep','bindings.draft.dat':'draft-keep','state/node-1/production.journal':'pending-keep','state/group-1/cohort.dat':'interrupted-cohort-keep','state/group-1/nanites-cell.journal':'holding-gold-keep','recipes/test.dat':'recipe-keep'}.items():
   self.assertEqual(l.globals().files['/home/bec_v2/'+p],value)
  count=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,count)

 def test_all_six_rename_failures_restore_originals(self):
  for failed in range(1,7):
   with self.subTest(rename=failed):
    l=make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
    with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
    for n,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],text)

 def test_low_space_unknown_code_and_flush_failure_leave_originals(self):
  for flag in ['used=4100000','failFlush=true',"files['/home/bec_v2/runtime/controller.lua']='custom'"]:
   l=make();l.execute(flag)
   old={n:l.globals().files['/home/bec_v2/'+n]for n in NAMES}
   with self.assertRaises(Exception):l.execute(SCRIPT)
   for n,text in old.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],text)

if __name__=='__main__':unittest.main()
