import ast
import json
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
SOURCE=(HERE/'install_network.lua').read_text(encoding='utf-8')
ENV=r'''
files={};dirs={['/home']=true};downloads={};calls=0;oldAttached=false;space=4194304
local fs={}
fs.exists=function(p)return files[p]~=nil or dirs[p]==true end
fs.isDirectory=function(p)return dirs[p]==true end
fs.makeDirectory=function(p)dirs[p]=true;return true end
fs.list=function(p)
 local prefix=p:gsub('/+$','')..'/';local names={};local seen={}
 for path in pairs(files)do if path:sub(1,#prefix)==prefix then
  local n=path:sub(#prefix+1):match('^[^/]+');if not seen[n]then seen[n]=true;names[#names+1]=n end
 end end
 table.sort(names);local i=0;return function()i=i+1;return names[i]end
end
local disk={address='new',spaceTotal=function()return space end,spaceUsed=function()local size=0;for p,t in pairs(files)do if p:sub(1,5)~='/mnt/'then size=size+#t end end;return size end}
fs.get=function(p)return disk end
fs.mounts=function()
 local rows={{disk,'/'}};if oldAttached then rows[#rows+1]={{address='old'},'/mnt/old/'}end
 local i=0;return function()i=i+1;if rows[i]then return table.unpack(rows[i])end end
end
fs.rename=function(a,b)if renameFailure==a then return false end;assert(files[a]and not files[b]);files[b]=files[a];files[a]=nil;return true end
fs.remove=function(p)
 if dirs[p]then for f in pairs(files)do assert(f:sub(1,#p+1)~=p..'/','nonempty')end;dirs[p]=nil else files[p]=nil end;return true
end
local ser={unserialize=function(t)return assert(load('return '..t,'data','t',{}))()end}
local internet={request=function(url)
 local name=url:match('/([^/]+)$');downloads[#downloads+1]=url
 if badFile==name then return function()error('network failed')end end
 local data=payloads[name];assert(data,'unexpected URL '..url)
 if corruptFile==name then data=data..'corrupt'end
 local sent=false;return function()if not sent then sent=true;return data end end
end}
require=function(n)
 if n=='filesystem'then return fs elseif n=='serialization'then return ser elseif n=='internet'then return internet end
 calls=calls+1;error('Installer attempted hardware access: '..n)
end
io={open=function(p,m)
 if m=='r'and not files[p]then return nil end
 local t=m=='w'and ''or files[p]
 return {read=function()return t end,write=function(_,s)t=t..s;return true end,
 flush=function()files[p]=t;return true end,close=function()end}
end}
print=function()end
'''
OLD=r'''
oldAttached=true;dirs['/mnt/old/home']=true;dirs['/mnt/old/home/bec/recipes']=true
files['/mnt/old/home/bec_auto.lua']='old controller'
files['/mnt/old/home/bec_cache.config']='{version=1,target=1000000000,overrides={entangled_space=200000}}'
files['/mnt/old/home/bec/recipes/test.dat']='{state="converted",condensates={{name="entangled_space",amount=144}}}'
files['/mnt/old/home/bec/recipes/test.dat.backup-1']='do not copy this'
files['/mnt/old/home/bec_auto.journal']='old unfinished supply'
files['/mnt/old/home/bec_nanites_io.journal']='old pending IO'
files['/mnt/old/home/bec_auto.journal.before-resume-50']='old history'
'''

class InstallTests(unittest.TestCase):
 def fixture(self,extra=''):
  r=LuaRuntime(unpack_returned_tuples=True)
  r.globals().payloads=r.table_from({p.name:p.read_text(encoding='utf-8')for p in (HERE/'files').iterdir()})
  r.execute(ENV+extra);return r
 def install(self,r,*args):return r.eval('function(...)'+SOURCE+'\nend')(*args)
 def test_complete_install_all_payloads_and_hd_without_machine_operations(self):
  r=self.fixture();self.install(r);g=r.globals()
  for name,text in g.payloads.items():self.assertEqual(g.files['/home/'+name],text)
  self.assertEqual(g.calls,0);self.assertIsNone(g.files['/home/bec_auto.journal'])
  self.assertIsNone(g.files['/home/bec_nanites_io.journal']);self.assertIsNone(g.dirs['/home/bec_install_stage'])
 def test_single_file_complete_installer_needs_no_extra_downloads(self):
  r=self.fixture(OLD)
  r.eval('function(...)'+(HERE/'install.lua').read_text(encoding='utf-8')+'\nend')()
  self.assertEqual(len(r.globals().downloads),0);self.assertEqual(r.globals().calls,0)
  for name,text in r.globals().payloads.items():
   if name!='bec_cache.config':self.assertEqual(r.globals().files['/home/'+name],text)
  self.assertIsNotNone(r.globals().files['/home/bec/recipes/test.dat'])
 def test_old_drive_import_preserves_exact_recipes_settings_leaves_history_behind(self):
  r=self.fixture(OLD);self.install(r);g=r.globals()
  self.assertEqual(g.files['/home/bec_cache.config'],g.files['/mnt/old/home/bec_cache.config'])
  self.assertEqual(g.files['/home/bec/recipes/test.dat'],g.files['/mnt/old/home/bec/recipes/test.dat'])
  for name in ['bec_auto.journal','bec_nanites_io.journal','bec_auto.journal.before-resume-50','bec/recipes/test.dat.backup-1']:
   self.assertIsNone(g.files['/home/'+name])
  self.assertEqual(g.files['/mnt/old/home/bec_nanites_io.journal'],'old pending IO')
 def test_existing_program_disk_is_refused_without_overwriting(self):
  r=self.fixture("files['/home/bec_auto.lua']='current program'")
  with self.assertRaisesRegex(Exception,'当前文件已存在'):self.install(r)
  self.assertEqual(r.globals().files['/home/bec_auto.lua'],'current program');self.assertEqual(len(r.globals().downloads),0)
 def test_all_downloads_checked_before_exposing_any_program_retry_reuses_stage(self):
  r=self.fixture("badFile='bec_nanites.lua'")
  with self.assertRaisesRegex(Exception,'下载失败'):self.install(r)
  self.assertIsNone(r.globals().files['/home/bec_auto.lua'])
  before=len(r.globals().downloads);r.execute('badFile=nil');self.install(r)
  self.assertLess(len(r.globals().downloads)-before,len(list(r.globals().payloads.items())))
 def test_corrupt_download_not_installed(self):
  r=self.fixture("corruptFile='bec_ui.lua'")
  with self.assertRaisesRegex(Exception,'下载内容超出预期'):self.install(r)
  self.assertIsNone(r.globals().files['/home/bec_ui.lua'])
 def test_partial_rename_failure_can_continue_without_replacing_existing_program(self):
  r=self.fixture("renameFailure='/home/bec_install_stage/bec_cache.lua'")
  with self.assertRaisesRegex(Exception,'改名失败'):self.install(r)
  before=r.globals().files['/home/bec_auto.lua'];self.assertIsNotNone(before)
  r.execute('renameFailure=nil');self.install(r)
  self.assertEqual(r.globals().files['/home/bec_auto.lua'],before)
 def test_late_attach_old_drive_can_import_after_new_program_install(self):
  r=self.fixture();self.install(r);g=r.globals();auto=g.files['/home/bec_auto.lua']
  r.execute(OLD);self.install(r,'import')
  self.assertEqual(g.files['/home/bec/recipes/test.dat'],g.files['/mnt/old/home/bec/recipes/test.dat'])
  self.assertEqual(g.files['/home/bec_auto.lua'],auto)
  self.assertEqual(g.files['/home/bec_cache.config.before-import-1'],g.payloads['bec_cache.config'])
 def test_bad_old_recipe_or_settings_aborts_before_installing(self):
  for extra in ["files['/mnt/old/home/bec/recipes/test.dat']='{state=\"broken\"}'", "files['/mnt/old/home/bec_cache.config']='{version=1,target=-1}'"]:
   r=self.fixture(OLD+extra)
   with self.assertRaises(Exception):self.install(r)
   self.assertIsNone(r.globals().files['/home/bec_auto.lua'])
 def test_out_of_space_fails_before_downloading(self):
  r=self.fixture('space=100')
  with self.assertRaisesRegex(Exception,'空间不足'):self.install(r)
  self.assertEqual(len(r.globals().downloads),0)

class BundleTests(unittest.TestCase):
 def test_integrated_actual_controller_contains_all_user_fixes_and_gate_nanites(self):
  auto=(HERE/'files/bec_auto.lua').read_text(encoding='utf-8')
  for marker in ['BEC_V1_NEXT_RECIPE_V1','BEC_V1_BEE_GUARD_V2','BEC_V1_PRODUCTION_OVERLAP_V3',
    'BEC_V1_ORDER_WINDOW_V1','BEC_V1_IDLE_CACHE_FAST_V2','BEC_V1_BATCH_STOP_V1','BEC_V1_IDLE_RECOVERY_V1',
    'BEC_V1_CPU_WAIT_V1:','BEC_V1_SEQUENTIAL_CPU_WAIT_V1:','local NANITES=','local function configureGate']:
   self.assertTrue(marker in auto,marker)
  bees=(HERE/'files/bec_nanites.lua').read_text(encoding='utf-8')
  self.assertIn('BEC_NANITES_BANK_FIRST10_V1',bees);self.assertIn('BEC_NANITES_IO_SLOTS_1_7_V1',bees)
  self.assertIn('BEC_V1_UI_INITIALIZE_V1:',(HERE/'files/bec_ui.lua').read_text(encoding='utf-8'))
 def test_archive_retention_is_bounded_and_active_files_are_never_removed(self):
  sys.path.insert(0,str(ROOT/'tools'));import test_clean_history
  r=test_clean_history.CleanupTests().fixture("for i=1,100 do add('bec_cache.journal.stopped-'..i,i)end;add('bec_cache.journal');add('bec_cache.journal.previous');add('bec_cache.journal.before-reset-1')")
  mod=r.execute((HERE/'files/bec_history.lua').read_text(encoding='utf-8'));mod.prune('/home/bec_cache.journal.stopped-',2)
  self.assertEqual(len(r.globals().removed),98)
  self.assertIsNotNone(r.globals().files['/home/bec_cache.journal.previous'])
  with self.assertRaises(Exception):mod.prune('/home/bec_cache.journal.before-reset-',0)
 def test_new_disk_launcher_initializes_then_selects_hd_without_second_controller(self):
  r=LuaRuntime(unpack_returned_tuples=True)
  r.execute(r'''
calls={};local fs={exists=function()return true end,list=function()local once=false;return function()if not once then once=true;return 'recipe.dat'end end end}
require=function(n)if n=='filesystem'then return fs end;return {list=function()local once=false;return function()if not once and hasHD then once=true;return 'panel'end end end}end
loadfile=function(path)return function(mode,panel)calls[#calls+1]={path,mode,panel};return true end end
hasHD=true
''')
  r.eval('function(...)'+(HERE/'files/bec_start.lua').read_text(encoding='utf-8')+'\nend')('initialize')
  calls=r.globals().calls;self.assertEqual(len(calls),3)
  self.assertEqual(calls[1][1],'/home/bec_initialize.lua')
  self.assertEqual(calls[2][1],'/home/bec_bee_restart.lua');self.assertEqual(calls[2][2],'reset')
  self.assertEqual(calls[3][1],'/home/bec_hd.lua');self.assertEqual(calls[3][2],'resume')
 def test_full_published_controller_runs_a_stocked_batch_with_gate_and_history_module(self):
  def literal(path,name):
   tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
   return next(n.value.value for n in ast.walk(tree)if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id==name for t in n.targets))
  base=literal('test_auto_once.py','MOCK').replace('/home/bec_auto_once.journal','/home/bec_auto.journal')
  base+=literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
  integration=literal('fixes/pipeline/test_pipeline.py','integration')
  r=LuaRuntime(unpack_returned_tuples=True)
  r.globals().historySource=(HERE/'files/bec_history.lua').read_text(encoding='utf-8')
  r.execute(base+integration+r'''
s.total=1;s.work=false
local c=require('component');local list,invoke,methods=c.list,c.invoke,c.methods
c.list=function(...)local it=list(...);local sent=false;return function()local a,t=it();if a then return a,t end;if not sent then sent=true;return 'batch-control','gt_machine'end end end
c.methods=function(a)
 if a=='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'then return {isWorkAllowed=false,setWorkAllowed=false,getName=false,isMachineActive=false}end
 if a=='batch-control'or a=='b04787f9-5423-4b03-8549-c786d4ef38d0'then return methods(a)end
 return setmetatable({},{__index=function(_,k)if k~='getRequiredCondensate'then return false end end})
end
c.invoke=function(a,m,...)
 if a=='batch-control'then
  if m=='setWorkAllowed'then s.work=(...);return end
  if m=='isWorkAllowed'then return s.work end
  return invoke('b04787f9-5423-4b03-8549-c786d4ef38d0',m,...)
 end
 return invoke(a,m,...)
end
local req=require;local fs=req('filesystem');fs.list=function()return function()end end
require=function(n)if n=='filesystem'then return fs end;return req(n)end
loadfile=function(path)
 if path=='/home/bec_nanites.lua'then return function()return {fastStages=true,passiveStages=true,ensure=function()return false end,needsSwitch=function()return false end}end end
 if path=='/home/bec_cache.lua'then return function()return true end end
 if path=='/home/bec_history.lua'then return assert(load(historySource))end
 error(path)
end
''')
  r.eval('function(...)'+(HERE/'files/bec_auto.lua').read_text(encoding='utf-8')+'\nend')('run')
  s=r.globals().s;logs=list(s.logs.values())
  self.assertEqual(s.completed,1,logs[-5:]);self.assertEqual(s.requests,0)
  self.assertFalse(s.enabled);self.assertEqual(s.output,15)
  self.assertFalse(any('程序停止:' in row for row in logs),logs[-5:])

if __name__=='__main__':unittest.main()
