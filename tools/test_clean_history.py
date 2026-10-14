import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
SOURCE=Path(__file__).with_name('clean_history.lua').read_text(encoding='utf-8')
MOCK=r'''
files={};removed={};dirs={};paused=15;running=false
local fs={}
fs.list=function(path)
 assert(path=='/home');local names={};for p in pairs(files)do names[#names+1]=p:sub(7)end
 table.sort(names);local i=0;return function()i=i+1;return names[i]end
end
fs.isDirectory=function(p)return dirs[p]==true end
fs.lastModified=function(p)return files[p].time or 0 end
fs.size=function(p)return files[p].size end
fs.remove=function(p)removed[#removed+1]=p;files[p]=nil;return true end
fs.get=function()return {spaceTotal=function()return 4194304 end,spaceUsed=function()return 1000 end}end
function require(n)
 if n=='filesystem'then return fs end
 if n=='component'then return {invoke=function(a,m,...)
  if m=='getOutput'then return paused end
  if m=='isWorkAllowed'then return running end
  error('unexpected machine call: '..m)
 end}end
 error(n)
end
function add(name,time)files['/home/'..name]={time=time or 0,size=1000}end
print=function()end
'''
class CleanupTests(unittest.TestCase):
 def fixture(self,setup=''):
  r=LuaRuntime(unpack_returned_tuples=True);r.execute(MOCK+setup);return r
 def run_clean(self,r,mode='clean'):return r.eval('function(...)'+SOURCE+'\nend')(mode)
 def test_removes_only_old_history_keeps_current_and_all_recovery_evidence(self):
  r=self.fixture(r'''
for _,prefix in ipairs({'bec_cache.journal.stopped-','bec_auto.journal.stopped-','bec_auto.journal.before-resume-','bec_nanites_io.journal.before-run-'})do
 for i=1,200 do add(prefix..i,i)end
end
for _,name in ipairs({'bec_auto.lua','bec_nanites.lua','bec_cache.lua','bec_ui.lua','bec_cache.config',
 'bec_auto.journal','bec_auto.journal.previous','bec_nanites_io.journal','bec_nanites_io.journal.previous',
 'bec_cache.journal','bec_cache.journal.previous','bec_cache.reset','bec_auto.journal.failed-reset',
 'bec_cache.journal.before-reset-1','bec_auto.journal.before-initialize-1','bec_auto.journal.retired-initialize-2',
 'bec_nanites_io.journal.before-restart-1','bec_initialize-1.dat','bec/recipes/recipe.dat',
 'bec_auto.lua.before-overlap-2','bec_cache.config.backup-8','unrelated.stopped-10'})do add(name)end
''')
  self.run_clean(r);self.assertEqual(len(r.globals().removed),4*197)
  for name in ['bec_auto.journal','bec_nanites_io.journal.previous','bec_auto.lua.before-overlap-2','bec/recipes/recipe.dat','bec_cache.journal.before-reset-1']:
   self.assertIsNotNone(r.globals().files['/home/'+name])
  self.assertIsNotNone(r.globals().files['/home/bec_cache.journal.stopped-198'])
  count=len(r.globals().removed);self.run_clean(r);self.assertEqual(len(r.globals().removed),count)
 def test_modification_time_keeps_new_reused_low_number(self):
  r=self.fixture("for i=190,200 do add('bec_cache.journal.stopped-'..i,i)end;add('bec_cache.journal.stopped-1',1000)")
  self.run_clean(r)
  self.assertIsNotNone(r.globals().files['/home/bec_cache.journal.stopped-1'])
  self.assertIsNotNone(r.globals().files['/home/bec_cache.journal.stopped-200'])
  self.assertIsNotNone(r.globals().files['/home/bec_cache.journal.stopped-199'])
 def test_check_does_not_remove_anything(self):
  r=self.fixture("for i=1,20 do add('bec_auto.journal.before-resume-'..i,i)end")
  self.run_clean(r,'check');self.assertEqual(len(r.globals().removed),0)
 def test_active_controller_refused_without_removal(self):
  for setup in ['paused=0','running=true']:
   r=self.fixture("for i=1,20 do add('bec_cache.journal.stopped-'..i)end;"+setup)
   with self.assertRaises(Exception):self.run_clean(r)
   self.assertEqual(len(r.globals().removed),0)
 def test_subdirectories_and_lookalike_filenames_never_selected(self):
  r=self.fixture("add('bec_cache.journal.stopped-1.new');add('bec_cache.journal.stopped-2/');add('prefixbec_cache.journal.stopped-3');add('bec_cache.journal.stopped-4x')")
  self.run_clean(r);self.assertEqual(len(r.globals().removed),0)
 def test_zero_timestamp_uses_number_and_keeps_three(self):
  r=self.fixture("for i=1,10 do add('bec_nanites_io.journal.before-run-'..i)end")
  self.run_clean(r);self.assertEqual(len(r.globals().removed),7)
  self.assertIsNotNone(r.globals().files['/home/bec_nanites_io.journal.before-run-10'])

if __name__=='__main__':unittest.main()
