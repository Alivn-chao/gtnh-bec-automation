"""Cache updater adds two modules; preserves settings/journals on every failure."""
import subprocess
import unittest
from pathlib import Path
from test_web_update import fixture

HERE=Path(__file__).resolve().parents[1]
SCRIPT=(HERE/'update_cache.lua').read_text(encoding='utf-8')
NAMES=['lib/cache.lua','runtime/cache.lua','web.lua','lib/web_session.lua','lib/web_page.html']
OLD={n:subprocess.check_output(['git','show','d26100c:reinstall_v2/files/'+n],cwd=HERE.parent).decode()for n in NAMES[2:]}

def make():
 l=fixture()
 for n in NAMES[:2]:l.globals().files['/home/bec_v2/'+n]=None
 for n,text in OLD.items():l.globals().files['/home/bec_v2/'+n]=text
 l.globals().files['/home/bec_v2/cache.config']='custom-targets-keep'
 l.globals().files['/home/bec_v2/state/group-1/cache.journal']='submitted-keep'
 return l

class CacheUpdateTests(unittest.TestCase):
 def test_verified_temporary_download_is_released_before_staging_on_small_disk(self):
  l=make();l.globals().files['/home/bec_cache_update.lua']=SCRIPT
  l.globals().downloadSize=len(SCRIPT.encode('utf-8'))
  l.execute("local fs=require('filesystem');fs.get=function()return {spaceTotal=function()return 4194304 end,spaceUsed=function()return 4194304-1000000+(files['/home/bec_cache_update.lua']and downloadSize or 0)end}end")
  l.eval('function(text)return assert(load(text,"@/home/bec_cache_update.lua"))end')(SCRIPT)()
  self.assertIsNone(l.globals().files['/home/bec_cache_update.lua'])
  self.assertEqual(l.globals().files['/home/bec_v2/cache.config'],'custom-targets-keep')
  l.globals().files['/home/bec_cache_update.lua']=SCRIPT;count=l.globals().count
  l.eval('function(text)return assert(load(text,"@/home/bec_cache_update.lua"))end')(SCRIPT)()
  self.assertIsNone(l.globals().files['/home/bec_cache_update.lua']);self.assertEqual(l.globals().count,count)

 def test_changed_temporary_file_is_preserved(self):
  l=make();l.globals().files['/home/bec_cache_update.lua']='user-replaced-file'
  l.eval('function(text)return assert(load(text,"@/home/bec_cache_update.lua"))end')(SCRIPT)()
  self.assertEqual(l.globals().files['/home/bec_cache_update.lua'],'user-replaced-file')

 def test_five_files_installed_and_existing_settings_and_unknown_state_preserved(self):
  l=make();l.execute(SCRIPT)
  for n in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+n],(HERE/'files'/n).read_text(encoding='utf-8'))
  for p,value in {'config.dat':'incomplete-keep','bindings.draft.dat':'draft-keep','state/node-1/production.journal':'pending-keep','state/group-1/cache.journal':'submitted-keep','cache.config':'custom-targets-keep'}.items():
   self.assertEqual(l.globals().files['/home/bec_v2/'+p],value)
  count=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,count)

 def test_every_rename_failure_rolls_back_old_and_added_files(self):
  for failed in range(1,9):
   l=make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failed)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   for n,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],text)
   for n in NAMES[:2]:self.assertIsNone(l.globals().files['/home/bec_v2/'+n])

 def test_unknown_added_module_or_low_disk_is_not_overwritten(self):
  for flag in ["files['/home/bec_v2/lib/cache.lua']='custom'",'used=4100000','failFlush=true']:
   l=make();l.execute(flag)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   for n,text in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],text)

if __name__=='__main__':unittest.main()
