"""Nine-file migration from the user's cache release, including rollback."""
import subprocess,unittest
from pathlib import Path
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
NAMES=['lib/cache.lua','web.lua','lib/web_session.lua','lib/web_page.html','lib/web_transport.lua','lib/config.lua','lib/engine.lua','lib/bridge.lua','runtime/controller.lua']
OLD={n:subprocess.check_output(['git','show','9afccb3:reinstall_v2/files/'+n],cwd=HERE.parent).decode()for n in NAMES if n!='lib/web_transport.lua'}
SCRIPT=(HERE/'update_connection.lua').read_text(encoding='utf-8')
def make():
 l=fixture()
 for n,text in OLD.items():l.globals().files['/home/bec_v2/'+n]=text
 l.globals().files['/home/bec_v2/cache.config']='keep-targets'
 l.globals().files['/home/bec_v2/state/group-1/cache.journal']='keep-unconfirmed'
 return l
class ConnectionUpdateTests(unittest.TestCase):
 def test_self_remove_failure_is_optional_but_disk_reserve_still_required(self):
  for behavior in ["return false,'busy'", "error('busy')", "return nil,'busy'"]:
   for low in [False,True]:
    with self.subTest(behavior=behavior,low=low):
     l=make();l.globals().files['/home/bec_connection_update.lua']=SCRIPT
     l.execute("local fs=require('filesystem');fs.remove=function()"+behavior+" end")
     if low:
      l.execute('used=4100000')
      with self.assertRaisesRegex(Exception,'磁盘空间不足'):l.execute(SCRIPT)
      self.assertEqual(l.globals().files['/home/bec_v2/web.lua'],OLD['web.lua'])
     else:
      l.execute(SCRIPT)
      for n in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+n],(HERE/'files'/n).read_text(encoding='utf-8'))
     self.assertEqual(l.globals().files['/home/bec_connection_update.lua'],SCRIPT)

 def test_install_release_temporary_without_debug_source_and_preserve_state(self):
  l=make();l.globals().files['/home/bec_connection_update.lua']=SCRIPT
  l.globals().downloadSize=len(SCRIPT.encode())
  l.execute("local fs=require('filesystem');fs.get=function()return {spaceTotal=function()return 4194304 end,spaceUsed=function()return 4194304-950000+(files['/home/bec_connection_update.lua']and downloadSize or 0)end}end")
  l.execute(SCRIPT)
  for n in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+n],(HERE/'files'/n).read_text(encoding='utf-8'))
  self.assertIsNone(l.globals().files['/home/bec_connection_update.lua'])
  self.assertEqual(l.globals().files['/home/bec_v2/cache.config'],'keep-targets')
  self.assertEqual(l.globals().files['/home/bec_v2/state/group-1/cache.journal'],'keep-unconfirmed')
  self.assertEqual(l.globals().files['/home/bec_v2/state/node-1/production.journal'],'pending-keep')
  count=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,count)
 def test_every_rename_failure_restores_all_originals(self):
  for failed in range(1,18):
   l=make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   for n,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],text)
   self.assertIsNone(l.globals().files['/home/bec_v2/lib/web_transport.lua'])
 def test_unknown_local_program_and_disk_shortage_preserve_everything(self):
  for flag in ["files['/home/bec_v2/lib/engine.lua']='custom'",'used=4100000','failFlush=true']:
   l=make();l.execute(flag)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/web.lua'],OLD['web.lua'])
if __name__=='__main__':unittest.main()
