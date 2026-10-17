"""Viewing pages is read-only and independent of pending cache writes."""
import unittest,subprocess
from pathlib import Path
from test_cache_management import setup
from test_web_session import SETUP
from test_read_optimization import fixture as session_fixture
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
SCRIPT=(HERE/'update_browse.lua').read_text(encoding='utf-8')
NAMES=['lib/cache.lua','lib/web_session.lua','lib/web_page.html']
OLD={n:subprocess.check_output(['git','show','acfc08c:reinstall_v2/files/'+n],cwd=HERE.parent).decode()for n in NAMES}
class CacheBrowseTests(unittest.TestCase):
 def test_page_needs_no_settings_revision_scan_disk_write_or_machine_read(self):
  l=setup();l.execute(r'''
K.snapshot(1);local original=s.files[C.path('cache.config')]
local c=require('component');c.invoke=function()error('no hardware during page action')end
local fs=require('filesystem');fs.list=function()error('no recipe scan')end
K.action({mode='page',page=1});assert(K.snapshot(1,true).page==0)
assert(s.files[C.path('cache.config')]==original)
assert(not pcall(K.action,{mode='page',page=-1}))
''')
 def test_stale_group_page_request_is_rejected(self):
  l=session_fixture();l.execute(SETUP+"assert(not pcall(H.handle,'cache',{mode='page',page=0,group=2},99))")
 def make(self):
  l=fixture()
  for n,t in OLD.items():l.globals().files['/home/bec_v2/'+n]=t
  l.globals().files['/home/bec_v2/state/group-1/cache.journal']='pending-keep'
  return l
 def test_compact_patch_installs_exact_html_and_repeats_without_gc(self):
  l=self.make();l.globals().files['/home/bec_browse_update.lua']=SCRIPT
  l.execute("collectgarbage=nil;require('filesystem').remove=function()return false,'busy'end")
  l.execute(SCRIPT);l.execute(SCRIPT)
  for n in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+n],(HERE/'files'/n).read_text(encoding='utf-8'))
  self.assertEqual(l.globals().files['/home/bec_v2/state/group-1/cache.journal'],'pending-keep')
  self.assertEqual(l.globals().files['/home/bec_v2/bindings.draft.dat'],'draft-keep')
  self.assertLess(len(SCRIPT.encode()),70000)
 def test_all_six_rename_failures_restore_originals(self):
  for failure in range(1,7):
   l=self.make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failure)+"then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   for n,t in OLD.items():self.assertEqual(l.globals().files['/home/bec_v2/'+n],t)
 def test_unknown_html_low_space_flush_failure_preserve_originals(self):
  for change in ["files['/home/bec_v2/lib/web_page.html']='custom'",'used=4100000','failFlush=true']:
   l=self.make();l.execute(change)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().files['/home/bec_v2/lib/cache.lua'],OLD['lib/cache.lua'])
if __name__=='__main__':unittest.main()
