"""Real Magmatter ore spelling is recognized without weakening bank/transfer guards."""
from pathlib import Path
import unittest
import test_cell_io as cells

ROOT=Path(__file__).resolve().parents[2]
VERSIONS=['reinstall_v2/files/runtime/nanites_cell.lua',
          'fixes/fixed_hive_checks/files/runtime/nanites_cell.lua']

class MagmatterHiveTests(unittest.TestCase):
 def world(self,path):
  f=cells.ModuleTests();f.setUp()
  f.module=f.lua.execute((ROOT/path).read_text(encoding='utf-8'))
  return f

 def test_fifteen_magmatter_reserve_does_not_block_lower_tier_switch(self):
  for path in VERSIONS:
   with self.subTest(path=path):
    f=self.world(path);f.lua.execute("inv[0][8]=disk(15,'Magmatter',4143);need=4")
    self.assertTrue(f.module.ensure())
    self.assertEqual(f.lua.eval('inv[0][8].storedItemCount'),15)
    self.assertEqual(f.record()['holding']['family'],'Transcendent')

 def test_real_spelling_can_be_loaded_as_canonical_tier_ten(self):
  for path in VERSIONS:
   with self.subTest(path=path):
    f=self.world(path);f.lua.execute(r'''
need=10;inv[0][8]=disk(15,'Magmatter',4143)
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if a==NODE and m=='getProvidedTier'and heldCount>0 then return{tier=10,name='MagMatter'}end
 return invoke(a,m,...)
end
''')
    self.assertTrue(f.module.ensure())
    self.assertEqual(f.record()['holding']['family'],'MagMatter')
    self.assertEqual(f.record()['holding']['tier'],10)
    self.assertEqual(f.lua.globals().heldCount,15)

 def test_single_t8_can_load_and_remain_installed(self):
  for path in VERSIONS:
   with self.subTest(path=path):
    f=self.world(path);f.lua.execute(r'''
need=8;inv[0][8]=disk(1,'Universium',4144)
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if a==NODE and m=='getProvidedTier'and heldCount>0 then return{tier=8,name='Universium'}end
 return invoke(a,m,...)
end
''')
    self.assertTrue(f.module.ensure())
    self.assertEqual(f.record()['holding']['count'],1)
    self.assertFalse(f.module.ensure())
    self.assertEqual(f.lua.globals().moves,2)

 def test_physical_display_maps_same_alias_and_rejects_unknown_ore(self):
  f=self.world(VERSIONS[0]);f.lua.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local side,slot=...
 if a==T and side==4 then
  if m=='getInventoryName'then return 'gt.blockmachines'end
  if m=='getInventorySize'then return 3 end
  if m=='getStackInSlot'then return{name='gregtech:gt.metaitem.03',damage=4143,size=15,oreNames={unknown and 'naniteMagmatterTypo'or 'naniteMagmatter'}}end
 end
 return invoke(a,m,...)
end
''')
  source=(ROOT/'reinstall_v2/files/lib/hive_transposer.lua').read_text(encoding='utf-8')
  f.lua.globals().make=f.lua.execute(source)
  f.lua.execute(r'''
physical=make(require('component'),{transposer=T,hatchSide=4,bankSide=0,loadSide=3,returnSide=2},true)
local count,tier=physical.read();assert(count==15 and tier.tier==10 and tier.name=='MagMatter')
unknown=true;assert(not pcall(physical.read))
''')

 def test_unknown_bank_ore_still_stops_before_any_move(self):
  for path in VERSIONS:
   with self.subTest(path=path):
    f=self.world(path);f.lua.execute("inv[0][8]=disk(15,'MagmatterTypo',4143)")
    with self.assertRaisesRegex(Exception,'未知蜂群'):f.module.ensure()
    self.assertEqual(f.lua.globals().moves,0)

if __name__=='__main__':unittest.main()
