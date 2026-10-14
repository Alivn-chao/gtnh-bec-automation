import sys
import unittest
from pathlib import Path
HERE=Path(__file__).parent
sys.path.insert(0,str(HERE))
from test_module import LuaRuntime, SETUP, EXT, SOURCE
SCRIPT=(HERE/'restart.lua').read_text(encoding='utf-8')

class RestartTests(unittest.TestCase):
 def fixture(self,extra=''):
  r=LuaRuntime(unpack_returned_tuples=True)
  r.execute(SETUP+EXT+r'''
local ser=require('serialization')
files[PATH]=ser.serialize({version=2,kind='cell-io',stage='waiting-port',requiredTier=4,
 requiredFamily='Transcendent',operationTotal=19612,beforeReading=0,
 pending=nil},false)
files['/home/bec_auto.journal']=ser.serialize({stage='pipeline-converting',plan={{keep=1}},requests={{state='submitted',amount=123}},
 naniteStage={stage='switching',required={tier=4,name='Transcendent'}}},false)
originalIO=files[PATH];originalAuto=files['/home/bec_auto.journal']
need=4;heldCount=0
io.open=function(path,mode)
 if mode=='r'then if not files[path]then return end;return {read=function()return files[path]end,close=function()end}end
 local text=''
 return {write=function(_,t)assert(not failWrite or not path:find(failWrite,1,true),'disk write failed');text=text..t;return true end,
 flush=function()files[path]=text;writes=writes+1;return true end,close=function()end}
end
local fs=require('filesystem');fs.rename=function(a,b)
 if failRename and a:find(failRename,1,true)then return false end
 files[b]=files[a];files[a]=nil;return true
end
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if a=='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'and(m=='isWorkAllowed'or m=='isMachineActive')then return false end
 if a==P and m=='getOutput'and unpaused then return 0 end
 return invoke(a,m,...)
end
'''+extra)
  module=r.execute('return assert(load(...))()',SOURCE)
  r.globals().installed=module
  r.execute("loadfile=function(path)assert(path=='/home/bec_nanites.lua');return function()return installed end end")
  return r
 def execute(self,r,mode='restart'):return r.eval('function(...)'+SCRIPT+'\nend')(mode)
 def test_empty_restored_ports_restarts_real_module_loading_cell(self):
  r=self.fixture();ok,why=self.execute(r);self.assertTrue(ok,why);g=r.globals()
  self.assertEqual(g.heldCount,19612);self.assertEqual(g.moves,2);self.assertEqual(g.rs[g.S],0);self.assertEqual(g.rs[g.N],0)
  self.assertEqual(g.files['/home/bec_nanites_io.journal.before-restart-1'],g.originalIO)
  self.assertEqual(g.files['/home/bec_auto.journal.before-bee-restart-1'],g.originalAuto)
  r.execute("local ser=require('serialization');local a=ser.unserialize(files['/home/bec_auto.journal']);assert(a.naniteStage==nil and a.plan[1].keep==1 and a.requests[1].amount==123);assert(ser.unserialize(files[PATH]).stage=='done')")
  self.assertEqual(g.inv[0][9].storedItemCount,0)
 def test_port_disk_requires_return_to_box_and_does_not_clear_old_journal(self):
  for side,slot in [(2,1),(2,7),(2,12),(3,1),(3,7)]:
   r=self.fixture(f'inv[{side}][{slot}]=inv[0][9];inv[0][9]=nil')
   ok,why=self.execute(r);self.assertFalse(ok);self.assertIn('取回底部箱子前10格',why)
   self.assertEqual(r.globals().moves,0);self.assertEqual(r.globals().files[r.globals().PATH],r.globals().originalIO)
 def test_returning_stranded_disk_to_bank_allows_same_command(self):
  r=self.fixture('inv[3][7]=inv[0][9];inv[0][9]=nil');self.assertFalse(self.execute(r)[0])
  r.execute('inv[0][9]=inv[3][7];inv[3][7]=nil')
  self.assertTrue(self.execute(r)[0]);self.assertEqual(r.globals().moves,2)
 def test_check_is_read_only_even_with_occupied_ports(self):
  r=self.fixture('inv[3][1]=inv[0][9];inv[0][9]=nil');writes=r.globals().writes
  self.assertTrue(self.execute(r,'check')[0]);self.assertEqual(r.globals().writes,writes);self.assertEqual(r.globals().moves,0)
 def test_no_pause_refuses_without_touching_port_outputs(self):
  r=self.fixture('unpaused=true;rs[S]=15');self.assertFalse(self.execute(r)[0])
  self.assertEqual(r.globals().rs[r.globals().S],15);self.assertEqual(r.globals().files[r.globals().PATH],r.globals().originalIO)
 def test_reset_only_and_repeat_restart_do_not_add_to_compatible_hive(self):
  r=self.fixture();self.assertTrue(self.execute(r,'reset')[0]);self.assertEqual(r.globals().moves,0)
  self.assertTrue(self.execute(r)[0]);moves=r.globals().moves
  self.assertTrue(self.execute(r)[0]);self.assertEqual(r.globals().moves,moves)
 def test_state_replace_failure_restores_original_without_any_cell_transfer(self):
  r=self.fixture("failRename='.before-restart-1.new'")
  self.assertFalse(self.execute(r)[0]);self.assertEqual(r.globals().files[r.globals().PATH],r.globals().originalIO);self.assertEqual(r.globals().moves,0)
 def test_auto_write_failure_can_retry_without_replaying_old_transfer(self):
  r=self.fixture("failWrite='/home/bec_auto.journal.before-bee-restart-1.new'")
  self.assertFalse(self.execute(r)[0]);self.assertEqual(r.globals().moves,0)
  self.assertEqual(r.globals().files['/home/bec_auto.journal'],r.globals().originalAuto)
  r.execute('failWrite=nil');self.assertTrue(self.execute(r)[0]);self.assertEqual(r.globals().moves,2)
 def test_unknown_new_transfer_is_retained_and_ports_closed(self):
  r=self.fixture('broken=true');self.assertFalse(self.execute(r)[0])
  self.assertEqual(r.globals().moves,1);self.assertEqual(r.eval("require('serialization').unserialize(files[PATH]).stage"),'moving-cell')
  self.assertEqual(r.globals().rs[r.globals().S],0);self.assertEqual(r.globals().rs[r.globals().N],0)
 def test_current_first10_and_io_1_7_module_is_reused_unchanged(self):
  r=self.fixture();g=r.globals();g.files['/home/bec_nanites.lua']=SOURCE
  r.execute("savedIO=files[PATH];files[PATH]=require('serialization').serialize({version=2,kind='cell-io',stage='done'},false);local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,x,...)if a==T and x==0 then if m=='getInventorySize'then return 27 elseif m=='getInventoryName'then return 'minecraft:chest'end end;return invoke(a,m,x,...)end")
  r.execute((HERE.parent/'nanites_perf/patch_first10.lua').read_text(encoding='utf-8'))
  patched=g.files['/home/bec_nanites.lua'];g.installed=r.execute('return assert(load(...))()',patched)
  r.execute("files[PATH]=savedIO;inv[0][11]={name='ignored outside first10'}")
  self.assertTrue(self.execute(r)[0]);self.assertEqual(g.moves,2)
  self.assertEqual(g.files['/home/bec_nanites.lua'],patched)
 def test_saturated_compatible_hive_is_not_treated_as_exact_physical_count(self):
  r=self.fixture("seedHive(37604);rs[N]=15")
  self.assertTrue(self.execute(r)[0]);self.assertEqual(r.globals().heldCount,37604);self.assertEqual(r.globals().moves,0)
  self.assertIsNone(r.eval("require('serialization').unserialize(files[PATH]).holding"))

if __name__=='__main__':unittest.main()
