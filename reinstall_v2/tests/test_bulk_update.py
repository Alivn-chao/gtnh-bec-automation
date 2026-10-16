"""Ten-port update can run while bindings are incomplete; never touches hardware."""
import subprocess,unittest
from pathlib import Path
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
NAMES=['lib/ochd_bindings.lua','lib/web_session.lua','lib/web_page.html']
SCRIPT=(HERE/'update_bulk10.lua').read_text(encoding='utf-8')
OLD={name:subprocess.check_output(['git','show','f60f785:reinstall_v2/files/'+name],cwd=HERE.parent).decode()for name in NAMES}
def make():
 l=fixture()
 for name,text in OLD.items():l.globals().files['/home/bec_v2/'+name]=text
 return l
class BulkUpdateTests(unittest.TestCase):
 def test_partial_config_and_draft_survive_three_file_update(self):
  l=make();l.execute(SCRIPT)
  for name,text in OLD.items():
   p='/home/bec_v2/'+name
   self.assertEqual(l.globals().files[p+'.before-bulk10-1'],text)
   self.assertEqual(l.globals().files[p],(HERE/'files'/name).read_text(encoding='utf-8'))
  self.assertEqual(l.globals().files['/home/bec_v2/config.dat'],'incomplete-keep')
  self.assertEqual(l.globals().files['/home/bec_v2/bindings.draft.dat'],'draft-keep')
  self.assertEqual(l.globals().files['/home/bec_v2/state/node-1/production.journal'],'pending-keep')
  count=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,count)
 def test_every_rename_failure_restores_all_three_originals(self):
  for failed in range(1,7):
   with self.subTest(failed=failed):
    l=make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
    with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
    for name,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+name],text)
 def test_unknown_module_preserves_all_files(self):
  l=make();l.globals().files['/home/bec_v2/lib/ochd_bindings.lua']='custom'
  with self.assertRaisesRegex(Exception,'未知本地程序'):l.execute(SCRIPT)
  self.assertEqual(l.globals().count,0)
 def test_low_space_and_failed_flush_preserve_originals(self):
  for flag in ['used=4100000','failFlush=true']:
   l=make();l.execute(flag)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   for name,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+name],text)
if __name__=='__main__':unittest.main()
