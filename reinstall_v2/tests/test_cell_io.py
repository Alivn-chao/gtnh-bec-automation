import unittest
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
from cell_fixture import SETUP, EXT
V2=Path(__file__).resolve().parents[1]/'files'
SOURCE=(V2/'runtime/nanites_cell.lua').read_text(encoding='utf-8')
OPTIONS='''BEC_CELL_IO={transposer=T,loadRedstone=S,returnRedstone=N,redstone=P,node=NODE,path=PATH,pauseSide=1,bankSide=0,loadSide=3,returnSide=2,loadOutputSide=0,returnOutputSide=0,checkGroup=function() guardCalls=(guardCalls or 0)+1;assert(not groupUnsafe,'whole group unsafe') end}'''
class ModuleTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute(SETUP+EXT+OPTIONS)
  self.module=self.lua.execute(SOURCE)

 def record(self):
  return self.lua.eval("require('serialization').unserialize(files[PATH])")

 def test_group_becomes_unsafe_during_io_stops_without_replay(self):
  self.lua.execute("BEC_CELL_IO.checkGroup=function() assert(highs==0,'group started during IO')end")
  with self.assertRaisesRegex(Exception,'group started'):
   self.module.ensure()
  self.assertEqual(self.lua.globals().moves,1)
  self.stopped()
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'):
   self.module.ensure()

 def stopped(self):
  self.assertEqual(self.lua.eval('rs[S]'),0)
  self.assertEqual(self.lua.eval('rs[N]'),0)
  self.assertEqual(self.lua.eval("files['/home/bec_nanites.journal']"),'old-filling-record')

 def test_preview_reads_bounded_bank_without_bulk_export(self):
  self.module.preview()
  self.assertEqual(self.lua.globals().bulkReads,0)
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().writes,0)

 def test_initial_load_and_noop(self):
  self.assertTrue(self.module.ensure())
  self.assertEqual(self.lua.globals().heldCount,19612)
  self.assertEqual(self.lua.globals().moves,2)
  self.assertFalse(self.module.ensure())
  self.assertEqual(self.lua.globals().moves,2)
  self.stopped()

 def test_reload_zero_cache_cannot_insert_another_family(self):
  self.module.ensure()
  self.lua.execute("inv[0][8]=disk(7562,'SixPhasedCopper',4147);local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,...)if a==NODE and m=='getAvailableNanites'then return 0 end;if a==NODE and m=='getProvidedTier'then return nil end;return invoke(a,m,...)end")
  before=(self.lua.globals().moves,self.lua.globals().writes,self.lua.eval('files[PATH]'))
  with self.assertRaisesRegex(Exception,'蜂群读数为0，但上次已确认'):
   self.module.ensure()
  self.assertEqual((self.lua.globals().moves,self.lua.globals().writes,self.lua.eval('files[PATH]')),before)
  self.assertEqual(self.lua.globals().heldCount,19612)
  self.assertEqual(self.lua.eval('inv[0][8].storedItemCount'),7562)

 def test_reload_zero_cache_recovers_when_runtime_reading_is_refreshed(self):
  self.module.ensure()
  self.lua.execute("local c=require('component');local invoke=c.invoke;stale=true;c.invoke=function(a,m,...)if stale and a==NODE and m=='getAvailableNanites'then return 0 end;if stale and a==NODE and m=='getProvidedTier'then return nil end;return invoke(a,m,...)end")
  with self.assertRaisesRegex(Exception,'蜂群读数为0，但上次已确认'):
   self.module.ensure()
  self.lua.execute('stale=false')
  self.assertFalse(self.module.ensure())
  self.assertEqual(self.lua.globals().moves,2)

 def physical_hatch(self,stale=False,material='TranscendentMetal',damage=4581):
  self.lua.execute("""
seedHive(23737,'TranscendentMetal',4581)
inv[0][9]=disk(0);inv[0][8]=disk(7562,'SixPhasedCopper',4147)
local ghost=disk(64,'"""+material+"',"+str(damage)+""").getAvailableItems[1]
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,x,y,...)
 if a==T and x==4 then
  if m=='getInventoryName'then return 'gt.blockmachines'end
  if m=='getInventorySize'then return 3 end
  if m=='getStackInSlot'then assert(y==3);return ghost end
 end
"""+("if a==NODE and m=='getAvailableNanites'then return 0 end;if a==NODE and m=='getProvidedTier'then return nil end;"if stale else '')+"return invoke(a,m,x,y,...)end")

 def test_physical_hatch_detects_false_empty_without_old_journal(self):
  self.physical_hatch(stale=True)
  with self.assertRaisesRegex(Exception,'实体收容总线展示槽有蜂群'):
   self.module.ensure()
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().writes,0)

 def test_physical_display_64_is_not_used_as_total_23737(self):
  self.physical_hatch()
  self.assertFalse(self.module.ensure())
  self.assertEqual(self.lua.globals().heldCount,23737)
  self.assertEqual(self.lua.globals().moves,0)

 def test_physical_hatch_type_conflict_blocks_before_moves(self):
  self.physical_hatch(material='SixPhasedCopper',damage=4147)
  with self.assertRaisesRegex(Exception,'实体收容总线与观测阵列蜂群类型不符'):
   self.module.ensure()
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().writes,0)

 def test_same_type_extra_is_loaded_without_recovery(self):
  self.module.ensure()
  self.lua.execute('inv[0][10]=disk(2000)')
  self.assertTrue(self.module.ensure())
  self.assertEqual(self.lua.globals().heldCount,21612)
  self.assertEqual(self.lua.globals().moves,4)
  self.assertEqual(self.lua.eval('inv[0][9].storedItemCount'),0)

 def test_over_30720_is_transferred_and_effective_reading_is_capped(self):
  self.lua.execute('inv[0][9]=disk(40000)')
  self.module.ensure()
  self.assertEqual(self.lua.globals().heldCount,40000)
  self.assertEqual(self.record()['holding']['count'],40000)
  self.stopped()

 def test_multiple_same_type_cells_combined(self):
  self.lua.execute('inv[0][10]=disk(20000)')
  self.module.ensure()
  self.assertEqual(self.lua.globals().heldCount,39612)
  self.assertEqual(self.lua.globals().moves,4)

 def test_lowest_adequate_tier_and_localized_label(self):
  self.lua.execute("inv[0][2]=disk(80,'Carbon',100);inv[0][2].getAvailableItems[1].label='碳蜂群'")
  self.module.ensure()
  self.assertEqual(self.lua.globals().heldCount,80)
  self.assertEqual(self.record()['holding']['family'],'Carbon')
  self.assertEqual(self.lua.eval('inv[0][9].storedItemCount'),19612)

 def test_tier_switch_recovers_old_to_its_empty_home(self):
  self.module.ensure()
  self.lua.execute("need=5;inv[0][10]=disk(128,'SixPhasedCopper',101)")
  self.module.ensure()
  self.assertEqual(self.lua.eval('inv[0][9].storedItemCount'),19612)
  self.assertEqual(self.lua.globals().heldCount,128)
  self.assertEqual(self.record()['holding']['tier'],5)
  self.assertEqual(self.lua.globals().moves,6)

 def test_unknown_saturated_hive_raw_count_is_read_by_recovery(self):
  self.lua.execute("inv[0][9]=nil;inv[0][1]=disk(0);seedHive(40000);inv[0][10]=disk(64,'Carbon',100)")
  self.module.ensure()
  self.assertEqual(self.lua.eval('inv[0][1].storedItemCount'),40000)
  self.assertEqual(self.lua.globals().heldCount,64)
  self.stopped()

 def test_unknown_hive_same_type_extra_recovers_before_identifying(self):
  self.lua.execute('seedHive(1000);inv[0][1]=disk(0)')
  self.module.ensure()
  self.assertEqual(self.lua.globals().heldCount,20612)
  self.assertEqual(self.lua.globals().moves,6)

 def test_saturated_known_count_is_recovered_before_further_topup(self):
  self.lua.execute('inv[0][9]=disk(40000);inv[0][1]=disk(0)')
  self.module.ensure()
  self.lua.execute('inv[0][10]=disk(5000)')
  self.module.ensure()
  self.assertEqual(self.lua.globals().heldCount,45000)
  self.assertEqual(self.record()['holding']['count'],45000)

 def test_partial_operation_not_replayed(self):
  self.lua.execute('partial=true')
  with self.assertRaisesRegex(Exception,'未完成'):
   self.module.ensure()
  self.assertEqual(self.lua.globals().moves,1)
  self.stopped()
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'):
   self.module.ensure()

 def test_uncertain_move_pending_retained(self):
  self.lua.execute('broken=true')
  with self.assertRaisesRegex(Exception,'lost response'):
   self.module.ensure()
  self.assertIsNotNone(self.record()['pending'])
  self.stopped()

 def test_unknown_item_and_missing_stock_stop_before_moves(self):
  for snippet in ["inv[0][9].getAvailableItems[1].oreNames={};inv[0][9].getAvailableItems[1].damage=999",'need=10']:
   self.setUp();self.lua.execute(snippet)
   with self.assertRaises(Exception): self.module.ensure()
   self.assertEqual(self.lua.globals().moves,0)

 def test_missing_empty_recovery_cell_does_not_move(self):
  self.lua.execute("seedHive(1000);need=5;inv[0][9]=disk(128,'SixPhasedCopper',101)")
  with self.assertRaisesRegex(Exception,'缺少.*空'):
   self.module.ensure()
  self.assertEqual(self.lua.globals().moves,0)

 def test_bulk_fallbacks_and_cache_delay(self):
  for snippet in ['noBulk=true','zeroIndex=true','missingMetadata=true','lag=true']:
   self.setUp();self.lua.execute(snippet);self.module.ensure()
   self.assertEqual(self.lua.globals().heldCount,19612)

 def test_ctrl_q_during_wait_stops_ports(self):
  self.lua.execute('ctx={tick=function(dt) now=now+dt end,stopping=function() return highs>0 end}')
  with self.assertRaisesRegex(Exception,'已暂停'):
   self.module.ensure(self.lua.globals().ctx)
  self.stopped()

 def test_current_and_reserve_small_counts_can_reach_minimum_together(self):
  self.lua.execute('seedHive(50);inv[0][9]=disk(20);inv[0][1]=disk(0)')
  self.module.ensure()
  self.assertEqual(self.lua.globals().heldCount,70)

 def test_non_direct_methods_can_be_called(self):
  self.lua.execute("inv[0][9]=disk(64,'WhiteDwarfMatter',200);need=6")
  self.module.ensure()
  self.assertEqual(self.record()['holding']['tier'],6)


if __name__=='__main__': unittest.main()
