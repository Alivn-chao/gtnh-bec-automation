import unittest
from pathlib import Path
from test_io import LuaRuntime, SETUP

SOURCE=Path(__file__).with_name('bec_nanites.lua').read_text(encoding='utf-8')
EXT=r'''
PATH='/home/bec_nanites_io.journal'
need,heldItem,bulkReads=1,nil,0
local function copy(x) return require('serialization').unserialize(require('serialization').serialize(x,false)) end
function disk(n,material,damage)
 local d={name=CELL,size=1,storedItemCount=n,canHoldNewItem=n==0,remainingItemCount=1000000000,getAvailableItems={}}
 if n>0 then d.getAvailableItems={{name='gregtech:gt.metaitem.03',damage=damage or 4581,size=n,
   label=material or 'TranscendentMetal',oreNames={'nanite'..(material or 'TranscendentMetal')},hasTag=false}} end
 return d
end
inv[0][9]=disk(19612)
local family={Carbon={1,'Carbon'},Silver={2,'Silver'},TranscendentMetal={4,'Transcendent'},
 SixPhasedCopper={5,'SixPhasedCopper'},WhiteDwarfMatter={6,'WhiteDwarf'},MagMatter={10,'MagMatter'}}
local function provided()
 if heldCount==0 then return nil end
 local f=family[heldItem.oreNames[1]:sub(7)];return {tier=f[1],name=f[2]}
end
function seedHive(n,material,damage)
 heldCount=n;heldItem=disk(n,material,damage).getAvailableItems[1]
end
io.open=function(p,mode)
 if mode=='r' then
  if not files[p] then return nil end
  return {read=function() return files[p] end,close=function() end}
 end
 assert(mode=='w' and p:match('^/home/bec_nanites_io%.journal'))
 return {write=function(_,text)
  if diskFull and text:find('moving%-cell') then error('disk full') end
  files[p]=text;writes=writes+1;return true
 end,flush=function() return true end,close=function() end}
end
local c=require('component')
c.methods=function() return noBulk and {} or {getAllStacks=false} end
c.invoke=function(a,m,x,y,n,source,dest)
 if a==T then
  if m=='getInventoryName' then return x==0 and 'tile.CompressedChest' or 'tile.appliedenergistics2.BlockIOPort' end
  if m=='getInventorySize' then return x==0 and 243 or 12 end
  if m=='getStackInSlot' then return inv[x][y] end
  if m=='getAllStacks' then
   bulkReads=bulkReads+1
   local values={};for i=1,243 do values[i]=inv[0][i] and copy(inv[0][i]) or {} end
   if zeroIndex then values[0]=values[1] end
   if missingMetadata then for _,v in pairs(values) do v.storedItemCount=nil end end
   return {count=function() return 243 end,getAll=function() return values end}
  end
  if m=='transferItem' then
   assert(n==1 and inv[x][source] and not inv[y][dest])
   moves=moves+1;inv[y][dest]=inv[x][source];inv[x][source]=nil
   if broken then error('lost response') end
   return 1
  end
 elseif a==NODE then
  if m=='isWorkAllowed' then return allowed end
  if m=='getState' then return interfere and highs>0 and 'crafting' or
    (heldCount>0 and 'paused-immediate' or 'nanite-tier-too-low') end
  if m=='getRequiredTier' then return {tier=need} end
  if m=='getProvidedTier' then return provided() end
  if m=='getAvailableNanites' then
   if lagRemaining>0 then lagRemaining=lagRemaining-1;return 0 end
   return math.min(heldCount,30720)
  end
 else
  if m=='getOutput' then return a==P and (x==1 and 15 or 0) or (x==0 and rs[a] or 0) end
  if m=='setOutput' then
   assert((a==S or a==N) and x==0);rs[a]=y
   if y==15 then
    highs=highs+1;local side=a==S and 3 or 2;local d=assert(inv[side][1]);local amount
    if side==3 then
     amount=partial and math.floor(d.storedItemCount/2) or d.storedItemCount
     local bee=copy(d.getAvailableItems[1])
     assert(not heldItem or heldCount==0 or heldItem.damage==bee.damage,'mixed hive')
     heldItem=bee;heldCount=heldCount+amount
     d.storedItemCount=d.storedItemCount-amount
     d.getAvailableItems=d.storedItemCount>0 and {bee} or {}
     if d.storedItemCount>0 then bee.size=d.storedItemCount end
    else
     amount=partial and math.floor(heldCount/2) or heldCount
     d.storedItemCount=amount;local bee=copy(heldItem);bee.size=amount;d.getAvailableItems={bee}
     heldCount=heldCount-amount
    end
    d.canHoldNewItem=d.storedItemCount==0
    inv[side][1]=nil;inv[side][7]=d
    if lag then lagRemaining=3 end
   end
   return true
  end
 end
 error('unexpected '..m)
end
'''


class ModuleTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.execute(SETUP+EXT)
  self.module=self.lua.execute(SOURCE)

 def record(self):
  return self.lua.eval("require('serialization').unserialize(files[PATH])")

 def stopped(self):
  self.assertEqual(self.lua.eval('rs[S]'),0)
  self.assertEqual(self.lua.eval('rs[N]'),0)
  self.assertEqual(self.lua.eval("files['/home/bec_nanites.journal']"),'old-filling-record')

 def test_preview_and_bulk_read_false_method_flag(self):
  self.module.preview()
  self.assertEqual(self.lua.globals().bulkReads,1)
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().writes,0)

 def test_initial_load_and_noop(self):
  self.assertTrue(self.module.ensure())
  self.assertEqual(self.lua.globals().heldCount,19612)
  self.assertEqual(self.lua.globals().moves,2)
  self.assertFalse(self.module.ensure())
  self.assertEqual(self.lua.globals().moves,2)
  self.stopped()

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
