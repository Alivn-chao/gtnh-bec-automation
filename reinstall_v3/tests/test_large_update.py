import unittest
from pathlib import Path
from test_web_update import fixture
from build_large_update import baseline,NAME
ROOT=Path(__file__).resolve().parents[2]
SCRIPT=(ROOT/'reinstall_v3/update_large.lua').read_text(encoding='utf-8')
NEW=(ROOT/'reinstall_v2/files'/NAME).read_text(encoding='utf-8')
class LargeUpdateTests(unittest.TestCase):
 def make(self):
  l=fixture()
  for name in [NAME,'lib/engine.lua','lib/bridge.lua']:l.globals().files['/home/bec_v2/'+name]=baseline(name)
  for name in ['state/group-1/cohort.dat','state/group-1/nanites-cell.journal','state/node-6/production.journal']:
   l.globals().files['/home/bec_v2/'+name]='interrupted-keep'
  return l
 def test_update_idempotence_keeps_entire_cohort_and_journals(self):
  l=self.make();l.execute('collectgarbage=nil');l.execute(SCRIPT)
  self.assertEqual(l.globals().files['/home/bec_v2/'+NAME],NEW)
  before=l.eval('count');l.execute(SCRIPT);self.assertEqual(l.eval('count'),before)
  for name in ['state/group-1/cohort.dat','state/group-1/nanites-cell.journal','state/node-6/production.journal']:
   self.assertEqual(l.globals().files['/home/bec_v2/'+name],'interrupted-keep')
 def test_each_rename_failure_restores_controller(self):
  for failure in [1,2]:
   l=self.make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failure)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/'+NAME],baseline())
 def test_low_space_flush_unknown_and_core_mismatch_refuse_update(self):
  for change in ['used=4100000','failFlush=true',"files['/home/bec_v2/runtime/controller.lua']='custom'","files['/home/bec_v2/lib/bridge.lua']='custom'"]:
   l=self.make();l.execute(change);before=l.globals().files['/home/bec_v2/'+NAME]
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/'+NAME],before)
if __name__=='__main__':unittest.main()
