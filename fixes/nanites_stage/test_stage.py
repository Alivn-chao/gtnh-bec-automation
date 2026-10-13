"""Lua 5.2 executes the actual cell module and stage coordinator together."""
import ast
import sys
import subprocess
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
controlWrites=0
function pause(n)own=n;controlWrites=controlWrites+1 end
function generator(on)genEnabled=on;controlWrites=controlWrites+1 end
function verifyGate()assert(not badGate,'gate changed')end
function save(stage)record.stage=stage;calls=calls+1 end
function tick(dt)
 now=now+dt
 if active>0 then active=active-1 end
 if mutate then req={a=288,b=144}end
 if quit then stopping=true end
 if own==0 then used.a=used.a+1 end
end
loadfile=function()return function()return module end end
'''


class StageTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  ext=EXT.replace("Silver={2,'Silver'},", "Silver={2,'Silver'},Neutronium={2,'Neutronium'},Glowstone={1,'Glowstone'},")
  self.lua.execute(SETUP+ext+MOCK)
  self.lua.execute("c=require('component')")
  self.module=self.lua.eval('function(...)'+SOURCE+'\nend')()
  self.lua.globals().module=self.module
  self.lua.execute(getattr(self,'body',BODY))

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

 def test_generation_keeps_running_while_bees_exchange(self):
  self.lua.execute("seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100);active=2")
  self.run_stage()
  self.assertEqual(self.lua.globals().own,0)
  self.assertTrue(self.lua.globals().genEnabled)
  self.assertEqual(self.lua.globals().active,2)
  self.assertEqual(self.lua.globals().controlWrites,0)

 def test_partial_transfer_retains_both_journals_and_never_replays(self):
  self.lua.execute("seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100);partial=true")
  with self.assertRaises(Exception): self.run_stage()
  self.assertEqual(self.lua.globals().controlWrites,0)
  self.assertIsNotNone(self.lua.globals().record.naniteStage)
  moves=self.lua.globals().moves
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'): self.module.needsSwitch()
  self.assertEqual(self.lua.globals().moves,moves)

 def test_restore_existing_pause_and_generation_off(self):
  self.lua.execute("own=15;genEnabled=false;seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100)")
  self.run_stage()
  self.assertEqual(self.lua.globals().own,15)
  self.assertFalse(self.lua.globals().genEnabled)

 def test_quit_before_stage_check_does_not_switch(self):
  self.lua.execute("seedHive(19612);inv[0][9]=disk(0);inv[0][2]=disk(128,'Carbon',100);stopping=true")
  self.run_stage()
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().controlWrites,0)

 def test_inventory_scan_crosses_stage_boundary_reproduces_old_error(self):
  scenario=r'''
   seedHive(30720,'Silver',101);inv[0][9]=disk(0)
   inv[0][10]=disk(128,'Carbon',100);inv[0][11]=disk(19612)
   local invoke=c.invoke;local changed=false
   c.invoke=function(a,m,...)
    if a==T and m=='getAllStacks' and not changed then changed=true;need=4;rname='Transcendent' end
    return invoke(a,m,...)
   end
  '''
  try:
   old=subprocess.check_output(['git','show','eb0989f:fixes/nanites_stage/stage.lua.inc'],cwd=ROOT).decode('utf-8')
  except subprocess.CalledProcessError:
   self.skipTest('Legacy reproduction needs the published eb0989f Git object')
  legacy=StageTests();legacy.body=old;legacy.setUp();legacy.lua.execute(scenario)
  with self.assertRaisesRegex(Exception,'换蜂等待时阶段发生变化'): legacy.run_stage()
  self.assertEqual(legacy.lua.globals().moves,0)
  self.assertIsNone(legacy.lua.globals().record.naniteStage)
  self.lua.execute(scenario);self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteTranscendentMetal')
  self.assertEqual(self.lua.eval('inv[0][9].storedItemCount'),30720)
  self.assertEqual(self.lua.globals().own,0)
  self.assertEqual(self.lua.eval('used.a'),72)

 def test_stage_updates_during_recovery_selects_latest(self):
  self.lua.execute(r'''
   seedHive(30720,'Silver',101);inv[0][9]=disk(0)
   inv[0][10]=disk(128,'Carbon',100);inv[0][11]=disk(19612);active=2
   local invoke=c.invoke
   c.invoke=function(a,m,...)
    if a==NODE and m=='getState' and highs>0 then need=4;rname='Transcendent' end
    return invoke(a,m,...)
   end
  ''')
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteTranscendentMetal')
  self.assertEqual(self.lua.eval('inv[0][10].storedItemCount'),128)
  self.assertEqual(self.lua.globals().own,0)
  self.assertEqual(self.lua.globals().controlWrites,0)

 def test_latest_stage_already_compatible_does_not_move(self):
  self.lua.execute(r'''
   seedHive(30720,'Silver',101);inv[0][9]=disk(0);inv[0][10]=disk(128,'Carbon',100)
   local invoke=c.invoke;local changed=false
   c.invoke=function(a,m,...)
    if a==T and m=='getAllStacks' and not changed then changed=true;need=2;rname='Silver' end
    return invoke(a,m,...)
   end
  ''')
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteSilver')
  self.assertEqual(self.lua.globals().own,0)
  self.assertTrue(self.lua.globals().genEnabled)
  self.assertEqual(self.lua.globals().controlWrites,0)

 def test_stage_change_after_io_begins_reselects_compatible_bees(self):
  self.lua.execute(r'''
   seedHive(19612);inv[0][9]=disk(0);inv[0][10]=disk(128,'Carbon',100)
   local invoke=c.invoke
   c.invoke=function(a,m,...)
    if a==NODE and m=='getState' and highs>0 then need=2;rname='Silver' end
    return invoke(a,m,...)
   end
  ''')
  self.run_stage()
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteTranscendentMetal')
  self.assertEqual(self.lua.globals().controlWrites,0)
  self.assertIsNone(self.lua.globals().record.naniteStage)

 def test_progress_advances_during_io_wait_without_control_writes(self):
  self.lua.execute(r'''
   noBulk=true
   seedHive(19612);inv[0][9]=disk(0);inv[0][10]=disk(128,'Carbon',100)
   local invoke=c.invoke;local hidden=0
   c.invoke=function(a,m,x,y,...)
    if a==T and m=='getStackInSlot' and x==2 and y==7 and rs[N]==15 and hidden<2 then
     hidden=hidden+1;return nil
    end
    return invoke(a,m,x,y,...)
   end
  ''')
  self.run_stage()
  self.assertGreater(self.lua.eval('used.a'),72)
  self.assertEqual(self.lua.globals().controlWrites,0)
  self.assertEqual(self.lua.eval('heldItem.oreNames[1]'),'naniteCarbon')

 def test_no_compatible_stock_leaves_hardware_stall_without_error(self):
  self.lua.execute("need=4;rname='Transcendent';seedHive(30720,'Silver',101);inv[0][9]=disk(0);inv[0][10]=disk(128,'Carbon',100);stateOverride='nanite-tier-too-low'")
  self.run_stage()
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().controlWrites,0)
  self.assertIsNone(self.lua.globals().record.naniteStage)


class ProductionGuardTests(unittest.TestCase):
 def test_missing_bees_stall_node_without_guard_pausing_production(self):
  def literal(path,name):
   tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
   return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
  mock=literal('fixes/pipeline/test_pipeline.py','mock')
  mock=mock.replace("assert(not released,'assembler released too early')", "assert(not released,'unchanged used after release')").replace("assert(not released)\n", "\n")
  extra=literal('fixes/production_overlap/test_overlap.py','extra')
  scenario=r'''
   quitAt=10;beePauses=0
   c.methods=function()return {getRequiredTier=false}end
   serviceNaniteStage=function()end
   local invoke=call
   function call(a,m,...)
    if m=='getRequiredTier'then return {name=now>=4.3 and 'Transcendent' or 'Carbon',tier=now>=4.3 and 4 or 1}end
    if m=='getProvidedTier'then return {name='Silver',tier=2}end
    if m=='getAvailableNanites'then return 30720 end
    if m=='getState' and now>=4.3 and output==0 then return 'nanite-tier-too-low' end
    return invoke(a,m,...)
   end
   local write=pause
   function pause(n)if now>=4.3 and n==15 and not stopping then beePauses=beePauses+1 end;write(n)end
   local advance=tick
   function tick(dt)
    local running=released
    if now>=4.3 then released=false end
    advance(dt)
    released=running
   end
  '''
  old=(ROOT/'fixes/production_overlap/prepare.lua.inc').read_text(encoding='utf-8')
  new=old.replace('local function productionGuard()', 'local function productionGuard()\nserviceNaniteStage()')
  new=new.replace('else changed=true;reason="蜂群不足以运行当前阶段，等待旧窗口收尾" end', 'else neededTier=nextTier;tierCovered=true end')
  for source,legacy in [(old,True),(new,False)]:
   lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(mock+extra+scenario)
   lua.eval('function()'+source+'\nreturn prepareStreaming({a=1440,b=1440}) end')()
   if legacy:self.assertGreater(lua.globals().beePauses,0)
   else:self.assertEqual(lua.globals().beePauses,0)


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
  lua.execute('loadfile=function()return function()return {passiveStages=true,needsSwitch=function()return false end}end end')
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
  # Upgrade the actual previously published V1 installer, preserving each hook.
  old_patch=subprocess.check_output(['git','show','eb0989f:fixes/nanites_stage/patch_v1.lua'],cwd=ROOT).decode('utf-8')
  lua.globals().files['/home/bec_auto.lua']=original
  lua.execute(old_patch)
  legacy=lua.globals().files['/home/bec_auto.lua']
  lua.execute(patch)
  upgraded=lua.globals().files['/home/bec_auto.lua']
  lua.execute('assert(load(...))',upgraded)
  self.assertIn('BEC_V1_NANITES_STAGE_V2',upgraded)
  self.assertNotIn('BEC_V1_NANITES_STAGE_V1',upgraded)
  for marker in ['local serviceNaniteStage','local originalStageTick=tick','serviceNaniteStage()\n','old.naniteStage']:
   self.assertEqual(upgraded.count(marker),1,marker)
  self.assertIn(legacy,list(lua.globals().files.values()))
  lua.globals().files['/home/bec_auto.lua']=original
  lua.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('nanite-stage-new',1,true)then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原'): lua.execute(patch)
  self.assertEqual(lua.globals().files['/home/bec_auto.lua'],original)
  self.assertEqual(lua.globals().files['/home/bec_auto.journal'],'preserve')


if __name__=='__main__': unittest.main()
