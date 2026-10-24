import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests')]
from lupa.lua52 import LuaRuntime
from cell_fixture import SETUP,EXT
from test_cell_io import OPTIONS
from test_cell_bridge import BridgeCellTests
BASE=Path(__file__).parent/'files'
SOURCE=(BASE/'runtime/nanites_cell.lua').read_text(encoding='utf-8')
class RefreshTests(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.l.execute(SETUP+EXT+OPTIONS)
  self.l.execute('''
BEC_CELL_IO.hiveSource='transposer'
BEC_CELL_IO.readPhysicalHive=function()return math.min(heldCount,64),require('component').invoke(NODE,'getProvidedTier')end
BEC_CELL_IO.arrayHiveReady=function(total,p)
 if stuck or cacheStale and highs<refreshAt then return false end
 if arrayLag and now<arrayLag then return false end
 return heldCount>0 and (not total or total==heldCount)
end
''')
  self.m=self.l.execute(SOURCE)
 def ready(self):self.assertTrue(self.m.ensure())
 def test_matching_hive_does_not_move(self):
  self.ready();self.assertFalse(self.m.ensure());self.assertEqual(self.l.globals().moves,2)
 def test_stale_cache_recovers_and_reloads_same_family_once(self):
  self.ready();self.l.execute('cacheStale=true;refreshAt=highs+2')
  self.assertTrue(self.m.ensure());self.assertEqual(self.l.globals().moves,6);self.assertEqual(self.l.globals().heldCount,19612)
  self.assertFalse(self.m.ensure());self.assertEqual(self.l.globals().moves,6)
 def test_no_empty_disk_stops_without_moving(self):
  self.ready();self.l.execute('cacheStale=true;refreshAt=highs+2;inv[0][9]=nil')
  with self.assertRaisesRegex(Exception,'空数字奇点'):self.m.ensure()
  self.assertEqual(self.l.globals().moves,2)
 def test_failed_refresh_keeps_journal_and_never_replays(self):
  self.ready();self.l.execute('stuck=true')
  with self.assertRaisesRegex(Exception,'观测阵列仍未识别'):self.m.ensure()
  self.assertEqual(self.l.eval("require('serialization').unserialize(files[PATH]).stage"),'verifying-array')
  self.assertEqual(self.l.globals().moves,6)
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'):self.m.ensure()
  self.assertEqual(self.l.globals().moves,6);self.assertEqual(self.l.eval('rs[S]+rs[N]'),0)
 def test_delayed_array_update_waits_without_extra_transfer(self):
  self.l.execute('arrayLag=2');self.ready();self.assertEqual(self.l.globals().moves,2)
 def test_partial_transfer_does_not_retry(self):
  self.ready();self.l.execute('cacheStale=true;refreshAt=highs+2;partial=true')
  with self.assertRaises(Exception):self.m.ensure()
  self.assertEqual(self.l.globals().moves,3);self.assertEqual(self.l.eval('rs[S]+rs[N]'),0)
 def test_unknown_old_operation_blocks_before_move(self):
  self.l.execute("files[PATH]=require('serialization').serialize({version=2,kind='cell-io',stage='moving-cell'},false)")
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'):self.m.ensure()
  self.assertEqual(self.l.globals().moves,0)
 def test_missing_physical_hive_with_known_holding_is_not_reloaded(self):
  self.ready();self.l.execute('heldCount=0')
  with self.assertRaisesRegex(Exception,'上次已确认'):self.m.ensure()
  self.assertEqual(self.l.globals().moves,2)
class WiringTests(unittest.TestCase):
 def test_real_bridge_checks_actual_node_cache(self):
  f=BridgeCellTests();f.setUp();l=f.lua
  for p in BASE.rglob('*.lua'):l.globals().files['/home/bec_v2/'+p.relative_to(BASE).as_posix()]=p.read_text(encoding='utf-8')
  l.execute('''
local c=require('component');local old=c.invoke
function c.invoke(a,m,...)
 local args={...}
 if a==T and args[1]==4 then
  if m=='getInventoryName'then return 'gt.blockmachines'end
  if m=='getInventorySize'then return 3 end
  if m=='getStackInSlot'then
   if args[2]==3 and heldCount>0 then local v={};for k,x in pairs(heldItem)do v[k]=x end;v.size=math.min(heldCount,64);return v end
   return nil
  end
 end
 if cacheStale and highs<refreshAt and (a==NODE or a=='member2')then
  if m=='getAvailableNanites'then return 0 end
  if m=='getProvidedTier'then return nil end
 end
 return old(a,m,...)
end
cfg.groups[1].nanites.hiveSource='transposer';cfg.groups[1].nanites.hatchSide=4
Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()
''')
  self.assertTrue(f.run_worker());l.execute('cacheStale=true;refreshAt=highs+2')
  self.assertTrue(f.run_worker());self.assertEqual(l.globals().moves,6)
  self.assertFalse(f.run_worker());self.assertEqual(l.globals().moves,6)
if __name__=='__main__':unittest.main()
