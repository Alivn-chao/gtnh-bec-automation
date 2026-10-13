import subprocess
import sys
import unittest
from pathlib import Path
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'fixes/idle_recovery'))
sys.path.insert(0,str(ROOT/'fixes/nanites_stage'))
import test_recovery as recoverytests
import test_stage as stagetests
PATCH=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
SOURCE=(ROOT/'fixes/nanites_io/bec_nanites.lua').read_text(encoding='utf-8')
def fixture():
 r=recoverytests.InstallationTests().runtime()
 r.execute((ROOT/'fixes/idle_recovery/patch_v1.lua').read_text(encoding='utf-8'))
 r.globals().files['/home/bec_nanites.lua']='old bee module'
 r.execute("local actualLoad=load;load=function(s,...)if s:find('M.fastStages=true',1,true)then return function()return {fastStages=true,preview=function()end}end end;return actualLoad(s,...)end")
 return r
def patched():
 r=fixture();r.execute(PATCH);return r.globals().files['/home/bec_auto.lua']
CONTROL=patched()
BODY=CONTROL[CONTROL.index('-- BEC_V1_NANITES_STAGE_V2:'):CONTROL.index('-- BEC_V1_BATCH_STOP_V1:')]
class FastStageTests(stagetests.StageTests):
 body=BODY
 def test_exact_hive_does_not_scan_bank(self):
  self.lua.execute("need=2;rname='Silver';seedHive(128,'Silver',101)")
  before=self.lua.globals().bulkReads;self.run_stage()
  self.assertEqual(self.lua.globals().bulkReads,before);self.assertEqual(self.lua.globals().moves,0)
 def test_fallback_hive_rechecks_new_exact_stock_in_half_second(self):
  self.lua.execute("need=2;rname='Silver';seedHive(128);inv[0][9]=disk(0)")
  self.run_stage();self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().calls,0)
  self.lua.execute("inv[0][10]=disk(64,'Silver',101);now=now+0.51")
  self.run_stage();self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteSilver')
 def test_switch_uses_fewer_component_reads_than_published_module(self):
  legacy=subprocess.check_output(['git','show','a464273b:fixes/nanites_io/bec_nanites.lua'],cwd=ROOT).decode('utf-8')
  counts=[]
  for module,body in [(legacy,stagetests.BODY),(SOURCE,BODY)]:
   lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(stagetests.SETUP+stagetests.EXT+stagetests.MOCK)
   lua.execute("c=require('component')")
   lua.execute("local orig=c.invoke;reads=0;c.invoke=function(a,m,...)if m~='transferItem' and m~='setOutput'then reads=reads+1 end;return orig(a,m,...)end")
   lua.globals().module=lua.eval('function(...)'+module+'\nend')()
   lua.execute(body)
   lua.execute("need=2;rname='Silver';seedHive(37604,'Silver',101);inv[0][9]=disk(0);inv[0][10]=disk(19612);need=4;rname='Transcendent';serviceNaniteStage()")
   counts.append(lua.globals().reads)
   self.assertEqual(lua.globals().heldCount,19612);self.assertEqual(lua.globals().moves,4)
  self.assertLess(counts[1],counts[0]*0.7,counts)
  print('Component reads for same switch: legacy=%s fast=%s'%tuple(counts))
 def test_bulk_port_polling_waits_for_delayed_output(self):
  self.lua.execute(r'''
   seedHive(19612);inv[0][9]=disk(0);inv[0][10]=disk(128,'Carbon',100)
   local orig=c.invoke;local hidden=0
   c.invoke=function(a,m,x,...)
    local result=orig(a,m,x,...)
    if a==T and m=='getAllStacks' and x==2 and rs[N]==15 and hidden<2 then
     local all=result.getAll;result.getAll=function()local rows=all();rows[7]={};hidden=hidden+1;return rows end
    end
    return result
   end
  ''')
  self.run_stage();self.assertGreater(self.lua.eval('used.a'),72)
  self.assertEqual(self.lua.globals().controlWrites,0)
class InstallerTests(unittest.TestCase):
 def test_verified_same_control_state_skips_duplicate_identity_reads(self):
  r=LuaRuntime(unpack_returned_tuples=True)
  r.execute(recoverytests.batchtests.MOCK)
  r.execute("local orig=call;reads=0;function call(...)reads=reads+1;return orig(...)end")
  r.execute(CONTROL[CONTROL.index('-- BEC_V1_BATCH_STOP_V1:'):CONTROL.index('local function serve()')])
  r.execute('prepareStreaming({})');before=r.globals().reads
  r.execute('pause(0)');self.assertEqual(r.globals().reads-before,1)
  self.assertFalse(r.globals().work)
 def test_two_files_backup_syntax_idempotence_and_previous_features(self):
  r=fixture();before=r.globals().files['/home/bec_auto.lua'];r.execute(PATCH)
  g=r.globals();current=g.files['/home/bec_auto.lua'];r.execute('assert(load(...))',current)
  self.assertEqual(g.files['/home/bec_nanites.lua'],SOURCE)
  self.assertEqual(g.files['/home/bec_auto.lua.before-fast-cycle-1'],before)
  self.assertEqual(g.files['/home/bec_nanites.lua.before-fast-cycle-1'],'old bee module')
  self.assertEqual(g.files['/home/bec_auto.journal'],'failed recipe preserve')
  for marker in ['BEC_V1_IDLE_RECOVERY_V1:','BEC_V1_BATCH_STOP_V1:','BEC_V1_NANITES_STAGE_V2:']:
   self.assertIn(marker,current)
  self.assertIn('stageCheckAt=computer.uptime()+0.5',current)
  self.assertIn('for i=1,100 do',current)
  n=g.writes;r.execute(PATCH);self.assertEqual(g.writes,n)
 def test_second_file_failure_rolls_back_first_file_too(self):
  r=fixture();before=r.globals().files['/home/bec_auto.lua']
  r.execute("local fs=require('filesystem');local orig=fs.rename;fs.rename=function(a,b)if a:find('bec_nanites.lua.fast-cycle-new',1,true)then return false end;return orig(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原两文件'):r.execute(PATCH)
  self.assertEqual(r.globals().files['/home/bec_auto.lua'],before)
  self.assertEqual(r.globals().files['/home/bec_nanites.lua'],'old bee module')
  self.assertEqual(r.globals().files['/home/bec_auto.journal'],'failed recipe preserve')
 def test_pending_io_does_not_install(self):
  r=fixture();before=r.globals().files['/home/bec_auto.lua']
  r.execute("files['/home/bec_nanites_io.journal']='pending';require('serialization').unserialize=function()return {stage='moving-cell'}end")
  with self.assertRaisesRegex(Exception,'换蜂尚未完成'):r.execute(PATCH)
  self.assertEqual(r.globals().files['/home/bec_auto.lua'],before)
  self.assertEqual(r.globals().files['/home/bec_nanites.lua'],'old bee module')
if __name__=='__main__':unittest.main()
