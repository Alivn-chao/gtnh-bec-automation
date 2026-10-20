import unittest
from pathlib import Path
from test_web_update import fixture
from build_cache_admission_update import BASES,NAME,baseline

ROOT=Path(__file__).resolve().parents[2]
SCRIPT=(ROOT/'reinstall_v3/update_cache_admission.lua').read_text(encoding='utf-8')
NEW=(ROOT/'reinstall_v2/files'/NAME).read_text(encoding='utf-8')

class CacheAdmissionUpdateTests(unittest.TestCase):
 def make(self,ref='499d433'):
  l=fixture();l.globals().files['/home/bec_v2/'+NAME]=baseline(ref)
  for name in ['cache.config','state/group-1/cache.journal','state/group-1/nanites-cell.journal']:
   l.globals().files['/home/bec_v2/'+name]='unconfirmed-keep'
  return l
 def test_both_published_versions_and_idempotence_keep_all_records(self):
  for ref in BASES:
   l=self.make(ref);l.execute('collectgarbage=nil');l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/'+NAME],NEW)
   before=l.eval('count');l.execute(SCRIPT);self.assertEqual(before,l.eval('count'))
   for name in ['cache.config','state/group-1/cache.journal','state/group-1/nanites-cell.journal']:
    self.assertEqual(l.globals().files['/home/bec_v2/'+name],'unconfirmed-keep')
 def test_two_rename_failures_restore_original(self):
  for failure in [1,2]:
   l=self.make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failure)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/'+NAME],baseline('499d433'))
 def test_unknown_source_low_space_flush_and_crlf(self):
  for change in ["files['/home/bec_v2/lib/cache.lua']='custom'",'used=4100000','failFlush=true']:
   l=self.make();l.execute(change);before=l.globals().files['/home/bec_v2/'+NAME]
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/'+NAME],before)
  l=self.make();l.globals().files['/home/bec_v2/'+NAME]=baseline('499d433').replace('\n','\r\n');l.execute(SCRIPT)
  self.assertEqual(l.globals().files['/home/bec_v2/'+NAME],NEW)

if __name__=='__main__':unittest.main()
