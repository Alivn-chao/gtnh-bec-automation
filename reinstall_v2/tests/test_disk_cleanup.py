"""Only recognized public program copies can be removed; all evidence survives."""
import unittest,subprocess
from pathlib import Path
from test_web_update import fixture
HERE=Path(__file__).resolve().parents[1]
SCRIPT=(HERE/'files/disk_cleanup.lua').read_text(encoding='utf-8')
def make():
 l=fixture();l.globals().CLEANUP=SCRIPT
 html=subprocess.check_output(['git','show','07522a8:reinstall_v2/files/lib/web_page.html'],cwd=HERE.parent).decode()
 l.globals().files['/home/bec_v2/lib/web_page.html']=html
 for n in [1,2,3]:l.globals().files['/home/bec_v2/lib/web_page.html.before-input-'+str(n)]=html
 l.globals().files['/home/bec_v2/lib/web_page.html.before-notes-4']='personal-note'
 l.globals().files['/home/bec_v2/lib/web_page.html.browse-new-1']=html
 l.globals().files['/home/bec_v2/state/group-1/cache.journal']='unconfirmed'
 l.globals().files['/home/bec_v2/recipes/a.dat']='recipe'
 l.globals().files['/home/bec_v2-stage-nanites-/unknown']='keep-stage'
 l.globals().files['/home/bec_hive_update.lua']=subprocess.check_output(['git','show','07522a8:reinstall_v2/update_hive.lua'],cwd=HERE.parent).decode()
 l.execute(r'''
local fs=require('filesystem');fs.list=function(dir)local names={};for p in pairs(files)do if p:match('^(.*)/')==dir then names[#names+1]=p:match('([^/]+)$')end end;local i=0;return function()i=i+1;return names[i]end end
fs.lastModified=function(p)return tonumber(p:match('(%d+)$'))or 0 end
''')
 return l
def run(l,mode='run'):l.globals().MODE=mode;l.execute("assert(load(CLEANUP,'@cleanup','t',_ENV))(MODE)")
class DiskCleanupTests(unittest.TestCase):
 def test_preview_does_not_remove_anything(self):
  l=make();run(l,'preview');self.assertIsNotNone(l.globals().files['/home/bec_hive_update.lua'])
  self.assertIsNotNone(l.globals().files['/home/bec_v2/lib/web_page.html.before-input-1'])
 def test_removes_old_known_copies_keeps_one_and_preserves_every_user_file(self):
  l=make();run(l)
  for n in [1,2]:self.assertIsNone(l.globals().files['/home/bec_v2/lib/web_page.html.before-input-'+str(n)])
  self.assertIsNotNone(l.globals().files['/home/bec_v2/lib/web_page.html.before-input-3'])
  self.assertIsNone(l.globals().files['/home/bec_hive_update.lua'])
  for p in ['config.dat','bindings.draft.dat','state/group-1/cache.journal','recipes/a.dat','lib/web_page.html.before-notes-4','lib/web_page.html.browse-new-1']:self.assertIsNotNone(l.globals().files['/home/bec_v2/'+p])
  self.assertEqual(l.globals().files['/home/bec_v2-stage-nanites-/unknown'],'keep-stage')
  run(l)
 def test_unknown_current_program_and_replaced_download_are_not_cleaned(self):
  l=make();l.execute("files['/home/bec_v2/lib/web_page.html']='custom';files['/home/bec_hive_update.lua']='replaced-note'");run(l)
  self.assertIsNotNone(l.globals().files['/home/bec_v2/lib/web_page.html.before-input-1'])
  self.assertEqual(l.globals().files['/home/bec_hive_update.lua'],'replaced-note')
 def test_failed_remove_preserves_file_and_does_not_claim_reclaimed_bytes(self):
  l=make();l.execute("require('filesystem').remove=function()return false,'busy'end");run(l)
  self.assertIsNotNone(l.globals().files['/home/bec_hive_update.lua'])
 def test_current_program_change_during_cleanup_stops_remaining_deletions(self):
  l=make();l.execute("local fs=require('filesystem');local remove=fs.remove;fs.remove=function(p)local result=remove(p);files['/home/bec_v2/lib/web_page.html']='changed-during-cleanup';return result end")
  with self.assertRaisesRegex(Exception,'当前程序或保留备份变化'):run(l)
  self.assertIsNotNone(l.globals().files['/home/bec_v2/lib/web_page.html.before-input-1'])
  self.assertIsNotNone(l.globals().files['/home/bec_v2/lib/web_page.html.before-input-3'])
if __name__=='__main__':unittest.main()
