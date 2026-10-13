"""Lua 5.2 executes the actual cell module and stage coordinator together."""
import ast
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'fixes/nanites_io'))
from test_module import LuaRuntime, SETUP, EXT, SOURCE

HERE = Path(__file__).parent
BODY = (HERE / 'stage.lua.inc').read_text(encoding='utf-8')
MOCK = r'''
c=require('component');computer=require('computer');sides={top=1};RS=P;GEN='gen'
record={stage='watching'};perRecipe={a=144,b=144};req={a=144,b=144};used={a=72,b=72}
rname='Carbon';own=0;genEnabled=true;active=0;stopping=false;calls=0
local invoke=c.invoke
c.invoke=function(a,m,...)
 if a==NODE then
  if m=='getRequiredTier'then return {name=rname,tier=need}end
  if m=='getRequiredCondensate'then return req end
  if m=='getConsumedCondensate'then return used end
  if m=='getParallelRecipesInProgress'then return 1 end
  if m=='getState'then return stateOverride or (own==0 and 'crafting' or 'paused-immediate')end
 elseif a==GEN then
  if m=='isWorkAllowed'then return genEnabled end
  if m=='isMachineActive'then return active>0 end
 elseif a==P and m=='getOutput'then return own end
 return invoke(a,m,...)
end
function call(a,m,...)return c.invoke(a,m,...)end
function integer(n)assert(type(n)=='number' and n>=0 and n%1==0);return n end
function same(a,b)
 if type(a)~='table' or type(b)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
function pause(n)own=n end
function generator(on)genEnabled=on end
function verifyGate()assert(not badGate,'gate changed')end
function save(stage)record.stage=stage;calls=calls+1 end
function tick(dt)
 now=now+dt
 if active>0 then active=active-1 end
 if mutate then req={a=288,b=144}end
 if quit then stopping=true end
 if genEnabled or own~=15 then error('transfer wait without stopped machines')end
end
loadfile=function()return function()return module end end
'''


class StageTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  ext=EXT.replace("Silver={2,'Silver'},", "Silver={2,'Silver'},Neutronium={2,'Neutronium'},Glowstone={1,'Glowstone'},")
  self.lua.execute(SETUP+ext+MOCK)
  self.module=self.lua.eval('function(...)'+SOURCE+'\nend')()
  self.lua.globals().module=self.module
  self.lua.execute(BODY)

 def run_stage(self): self.lua.globals().serviceNaniteStage()

 def test_downgrade_then_mid_recipe_upgrade_preserves_consumption(self):
  self.lua.execute("inv[0][9]=disk(0);seedHive(19612);inv[0][10]=disk(128,'Carbon',100);inv[0][11]=disk(256,'Silver',101)")
  self.run_stage()
  self.assertEqual(self.lua.globals().heldCount,128)
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteCarbon')
  self.assertEqual(self.lua.eval('inv[0][9].storedItemCount'),19612)
  self.lua.execute("need=2;rname='Silver'")
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteSilver')
  self.assertEqual(self.lua.eval('used.a'),72)
  self.assertEqual(self.lua.globals().own,0)
  self.assertTrue(self.lua.globals().genEnabled)
  self.assertIsNone(self.lua.globals().record.naniteStage)
  moves=self.lua.globals().moves
  self.run_stage()
  self.assertEqual(self.lua.globals().moves,moves)

 def test_exact_family_beats_larger_same_tier_disk(self):
  self.lua.execute("need=2;rname='Silver';inv[0][2]=disk(1000,'Neutronium',102);inv[0][3]=disk(64,'Silver',101)")
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteSilver')

 def test_same_tier_family_change_switches_when_stocked(self):
  self.lua.execute("seedHive(128,'Glowstone',104);inv[0][1]=disk(0);inv[0][2]=disk(64,'Carbon',100)")
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteCarbon')

 def test_no_exact_stock_keeps_compatible_hive_without_moves(self):
  self.lua.execute('seedHive(19612);inv[0][9]=disk(0)')
  self.run_stage()
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().own,0)

 def test_compatible_lower_tier_fallback_and_undersized_exact_ignored(self):
  self.lua.execute("seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(63,'Carbon',100);inv[0][3]=disk(128,'Silver',101)")
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteSilver')

 def test_new_stock_detected_without_stage_change(self):
  self.lua.execute('seedHive(19612);inv[0][9]=disk(0)')
  self.run_stage()
  self.lua.execute("inv[0][2]=disk(128,'Carbon',100);now=now+2")
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteCarbon')

 def test_recipe_change_does_not_reuse_old_gate_or_move(self):
  self.lua.execute("req={a=144,b=288};seedHive(19612);inv[0][2]=disk(128,'Carbon',100)")
  self.run_stage()
  self.assertEqual(self.lua.globals().moves,0)

 def test_generation_wait_detects_recipe_change_before_transfer(self):
  self.lua.execute("seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100);active=2;mutate=true")
  with self.assertRaisesRegex(Exception,'配方发生变化'): self.run_stage()
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().own,15)
  self.assertFalse(self.lua.globals().genEnabled)

 def test_partial_transfer_retains_both_journals_and_never_replays(self):
  self.lua.execute("seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100);partial=true")
  with self.assertRaises(Exception): self.run_stage()
  self.assertEqual(self.lua.globals().own,15)
  self.assertFalse(self.lua.globals().genEnabled)
  self.assertIsNotNone(self.lua.globals().record.naniteStage)
  moves=self.lua.globals().moves
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'): self.module.needsSwitch()
  self.assertEqual(self.lua.globals().moves,moves)

 def test_restore_existing_pause_and_generation_off(self):
  self.lua.execute("own=15;genEnabled=false;seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100)")
  self.run_stage()
  self.assertEqual(self.lua.globals().own,15)
  self.assertFalse(self.lua.globals().genEnabled)

 def test_quit_while_waiting_does_not_switch_or_resume(self):
  self.lua.execute("seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100);active=2;quit=true")
  self.run_stage()
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().own,15)
  self.assertFalse(self.lua.globals().genEnabled)


class InstallerTests(unittest.TestCase):
 def test_patch_backup_idempotence_and_recovery_guard(self):
  # Execute actual pipeline/overlap installers before this patch on the baseline.
  # The baseline only supplies syntax/installation coverage, not bee-aware runtime coverage.
  tree=ast.parse((ROOT/'fixes/process_reset/test_reset.py').read_text(encoding='utf-8'))
  setup=next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='installer' for t in n.targets))
  lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(setup)
  text=(ROOT/'bec_auto.lua').read_text(encoding='utf-8').replace('end\nlocal function serve()','end local function serve()').replace('local old=ser.unserialize(contents)\n','local old=ser.unserialize(contents) local streaming=false\n')
  text="-- fixture: /home/bec_nanites.lua\n"+text
  lua.globals().files['/home/bec_auto.lua']=text
  lua.globals().files['/home/bec_auto.journal']='preserve'
  for path in ['fixes/pipeline/patch_v1.lua','fixes/production_overlap/patch_v1.lua']:
   lua.execute((ROOT/path).read_text(encoding='utf-8'))
  original=lua.globals().files['/home/bec_auto.lua']
  lua.execute('loadfile=function()return function()return {needsSwitch=function()return false end}end end')
  patch=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
  lua.execute(patch)
  modified=lua.globals().files['/home/bec_auto.lua']
  lua.execute('assert(load(...))',modified)
  self.assertEqual(lua.globals().files['/home/bec_auto.lua.before-nanite-stage-1'],original)
  self.assertEqual(lua.globals().files['/home/bec_auto.journal'],'preserve')
  self.assertIn('old.naniteStage',modified)
  count=lua.globals().writes;lua.execute(patch)
  self.assertEqual(lua.globals().writes,count)
  self.assertEqual(modified.count('local serviceNaniteStage'),1)
  lua.globals().files['/home/bec_auto.lua']=original
  lua.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('nanite-stage-new',1,true)then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原'): lua.execute(patch)
  self.assertEqual(lua.globals().files['/home/bec_auto.lua'],original)
  self.assertEqual(lua.globals().files['/home/bec_auto.journal'],'preserve')


if __name__=='__main__': unittest.main()
