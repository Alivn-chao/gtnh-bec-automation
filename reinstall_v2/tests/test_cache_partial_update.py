"""Small cache updater preserves journals and rolls back both existing/new files."""
import subprocess,unittest
from pathlib import Path
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
SCRIPT=(HERE/'update_cache_partial.lua').read_text(encoding='utf-8')
OLD=subprocess.check_output(['git','show','5ad2b03:reinstall_v2/files/runtime/cache.lua'],cwd=HERE.parent).decode()
def make():
 l=fixture();l.globals().files['/home/bec_v2/runtime/cache.lua']=OLD
 l.globals().files['/home/bec_v2/state/group-1/cache.journal']='unknown-keep'
 return l
class CachePartialUpdateTests(unittest.TestCase):
 def test_replace_published_helper_and_rollback_all_four_renames(self):
  helper=subprocess.check_output(['git','show','166f844:reinstall_v2/files/cache_recover.lua'],cwd=HERE.parent).decode()
  runtime=(HERE/'files/runtime/cache.lua').read_text(encoding='utf-8')
  for failed in [None,1,2,3,4]:
   l=make();l.globals().files['/home/bec_v2/cache_recover.lua']=helper;l.globals().files['/home/bec_v2/runtime/cache.lua']=runtime
   if failed:
    l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
    with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
    self.assertEqual(l.globals().files['/home/bec_v2/cache_recover.lua'],helper)
   else:
    l.execute(SCRIPT)
    self.assertEqual(l.globals().files['/home/bec_v2/cache_recover.lua'],(HERE/'files/cache_recover.lua').read_text(encoding='utf-8'))
   self.assertEqual(l.globals().files['/home/bec_v2/runtime/cache.lua'],runtime)
   self.assertEqual(l.globals().files['/home/bec_v2/state/group-1/cache.journal'],'unknown-keep')
 def test_install_idempotence_without_gc_or_self_remove(self):
  l=make();l.globals().files['/home/bec_cache_partial_update.lua']=SCRIPT
  l.execute("collectgarbage=nil;require('filesystem').remove=function()return false,'busy'end")
  l.execute(SCRIPT)
  for name in ['runtime/cache.lua','cache_recover.lua']:
   self.assertEqual(l.globals().files['/home/bec_v2/'+name],(HERE/'files'/name).read_text(encoding='utf-8'))
  l.execute(SCRIPT)
  self.assertEqual(l.globals().files['/home/bec_v2/state/group-1/cache.journal'],'unknown-keep')
  self.assertEqual(l.globals().files['/home/bec_v2/bindings.draft.dat'],'draft-keep')
 def test_every_rename_failure_restores_old_and_removes_new_helper(self):
  for failed in range(1,4):
   l=make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/runtime/cache.lua'],OLD)
   self.assertIsNone(l.globals().files['/home/bec_v2/cache_recover.lua'])
 def test_unknown_local_change_low_space_and_failed_flush_leave_old(self):
  for change in ["files['/home/bec_v2/cache_recover.lua']='custom'",'used=4100000','failFlush=true']:
   l=make();l.execute(change)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/runtime/cache.lua'],OLD)
if __name__=='__main__':unittest.main()
