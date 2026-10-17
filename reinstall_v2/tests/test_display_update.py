"""Display updater is independent of cache recovery journals and hardware."""
import subprocess,unittest
from pathlib import Path
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
NAMES=['lib/cache.lua','lib/web_session.lua','lib/web_transport.lua','lib/config.lua','web.lua']
SCRIPT=(HERE/'update_display.lua').read_text(encoding='utf-8')
OLD={n:subprocess.check_output(['git','show','a8c9b3e:reinstall_v2/files/'+n],cwd=HERE.parent).decode()for n in NAMES}
def make():
 l=fixture()
 for n,text in OLD.items():l.globals().files['/home/bec_v2/'+n]=text
 l.globals().files['/home/bec_v2/state/group-1/cache.journal']='unknown-keep'
 return l
class DisplayUpdateTests(unittest.TestCase):
 def test_install_and_repeat_without_gc_or_self_remove(self):
  l=make();l.globals().files['/home/bec_display_update.lua']=SCRIPT
  l.execute("collectgarbage=nil;require('filesystem').remove=function()return false,'busy'end")
  l.execute(SCRIPT)
  for n in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+n],(HERE/'files'/n).read_text(encoding='utf-8'))
  l.execute(SCRIPT)
  self.assertEqual(l.globals().files['/home/bec_v2/state/group-1/cache.journal'],'unknown-keep')
  self.assertEqual(l.globals().files['/home/bec_v2/bindings.draft.dat'],'draft-keep')
 def test_all_ten_rename_failures_restore_originals(self):
  for failed in range(1,11):
   l=make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   for n,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],text)
 def test_unknown_low_space_or_flush_failure_do_not_replace_programs(self):
  for flag in ["files['/home/bec_v2/web.lua']='custom'",'used=4100000','failFlush=true']:
   l=make();l.execute(flag)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/lib/cache.lua'],OLD['lib/cache.lua'])
if __name__=='__main__':unittest.main()
