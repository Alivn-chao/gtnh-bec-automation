"""Live phase tiers through the real bridge/controller/cell IO; simulated hardware."""
import subprocess
import unittest
from pathlib import Path
from test_read_optimization import fixture, CAPTURE
from simulate_two_recipes import WORLD
from cell_fixture import SETUP, EXT

ROOT=Path(__file__).resolve().parents[2]

class DynamicNaniteTests(unittest.TestCase):
 def test_post_swap_pause_grace_restarts_and_remains_bounded(self):
  for baseline,delay in [(True,.25),(False,.25),(False,31)]:
   with self.subTest(baseline=baseline,delay=delay):
    l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes'")
    if baseline:
     l.globals().s.files['/home/bec_v2/runtime/controller.lua']=subprocess.check_output(['git','show','9afccb3:reinstall_v2/files/runtime/controller.lua'],cwd=ROOT).decode()
    world=WORLD.replace("if W.finished then return 'idle'end", "if W.finished then return 'idle'end\n if W.resumeUntil and s.now<W.resumeUntil and W.outputSignal==0 then return 'paused-immediate'end")
    world=world.replace('local function hardwareTick(dt)', "local function hardwareTick(dt)\n if W.progress>=2 then W.recipe().tier=4 end")
    world=world.replace('if not W.finished and W.started and W.outputSignal==0 then',"if not W.finished and W.started and W.outputSignal==0 and W.state()=='crafting' then")
    world=world.replace('W.outputSignal=args[2]', 'W.outputSignal=args[2];if args[2]==0 and W.started then W.resumeUntil=s.now+'+str(delay)+' end')
    l.execute(world)
    l.execute("world.recipes[1].tier=3;world.bank[8]={tier=3,count=39392,family='Gold',material='Gold',damage=4086}")
    l.execute('for step=1,20000 do E.step();if E.tasks[1].fault or #world.outputs>=1 then break end;world.advance(.05)end')
    if baseline or delay>30:
     self.assertTrue(l.eval('E.tasks[1].fault'))
     self.assertIn('节点运行异常: paused-immediate',l.eval("table.concat(E.logs,' / ')"))
     self.assertEqual(l.eval('world.outputSignal'),15)
     self.assertEqual(l.eval('#world.outputs'),0)
    else:
     self.assertFalse(l.eval('E.tasks[1].fault'),l.eval("table.concat(E.logs,' / ')"))
     self.assertEqual(l.eval('#world.outputs'),1)

 def test_v1_exact_family_preference_at_same_tier(self):
  from lupa.lua52 import LuaRuntime
  l=LuaRuntime(unpack_returned_tuples=True)
  l.execute(SETUP+EXT+'''
need=1
local c=require('component');local old=c.invoke
c.invoke=function(a,m,...)
 if a==NODE and m=='getRequiredTier'then return {tier=1,name='Glowstone'}end
 if a==NODE and m=='getProvidedTier'then return heldCount>0 and {tier=1,name=heldItem.damage==4001 and 'Glowstone'or 'Carbon'}or nil end
 return old(a,m,...)
end
local function bee(count,mat,damage)
 local d=disk(count);local b=d.getAvailableItems[1];b.damage=damage;b.oreNames={'nanite'..mat};return d
end
inv[0][9]=bee(1000,'Carbon',4000);inv[0][10]=bee(64,'Glowstone',4001)
BEC_CELL_IO={transposer=T,loadRedstone=S,returnRedstone=N,redstone=P,node=NODE,path=PATH,pauseSide=1,bankSide=0,loadSide=3,returnSide=2,loadOutputSide=0,returnOutputSide=0,checkGroup=function()end}
''')
  module=l.execute((ROOT/'reinstall_v2/files/runtime/nanites_cell.lua').read_text(encoding='utf-8'))
  self.assertTrue(module.ensure())
  self.assertEqual(l.eval('heldCount'),64)
  self.assertEqual(l.eval('heldItem.damage'),4001)

 def test_live_maximum_includes_staggered_members_and_old_cohort(self):
  l=fixture();l.execute('configure(2);'+CAPTURE)
  l.execute('E.tasks[1].entries[1].tier=3;E.tasks[1].entries[2].tier=3;nodes.node1.tier=4;nodes.node2.tier=3')
  self.assertEqual(l.eval('captured.BEC_V2_NODE_SNAPSHOT().requiredTier'),4)
  l.execute('E.tasks[1].released=true;nodes.node1.tier=1;nodes.node2.tier=4')
  self.assertEqual(l.eval('captured.BEC_V2_NODE_SNAPSHOT().requiredTier'),4)
  l.execute('nodes.node2.tier=1')
  self.assertEqual(l.eval('captured.BEC_V2_NODE_SNAPSHOT().requiredTier'),1)
  self.assertEqual(l.eval('E.tasks[1].entries[1].tier'),3)

 def test_changed_recipe_batch_and_invalid_tier_still_block(self):
  for mutation,reason in [('nodes.node2.required.entangled_chromaticglass=144','不同配方'),
                           ('nodes.node2.parallel=2;nodes.node2.required={entangled_chromaticglass=576,entangled_transcendentmetal=576}','批量变化'),
                           ('nodes.node2.tier=0','等级不可读'),('nodes.node2.tier=1.5','等级不可读')]:
   with self.subTest(mutation=mutation):
    l=fixture();l.execute('configure(2);'+CAPTURE+'E.tasks[1].released=true;'+mutation)
    with self.assertRaisesRegex(Exception,reason):l.execute('captured.BEC_V2_NODE_SNAPSHOT()')

 def test_running_recipe_switches_gold_to_transcendent_and_finishes(self):
  # Baseline must reproduce the user's exact guard failure, before any T4 load.
  for baseline in [True,False]:
   with self.subTest(baseline=baseline):
    l=fixture()
    if baseline:
     l.globals().s.files['/home/bec_v2/lib/bridge.lua']=subprocess.check_output(['git','show','dae5e0e:reinstall_v2/files/lib/bridge.lua'],cwd=ROOT).decode()
     l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()")
    l.execute("cfg.recipeDirectory='/home/bec_v2/recipes'")
    world=WORLD.replace('local function hardwareTick(dt)', '''local function hardwareTick(dt)
 if W.current==1 then
  local tier=W.progress>=7 and 1 or W.progress>=2 and 4 or 3
  if tier~=W.recipe().tier then W.recipe().tier=tier;mark('phase-tier',tier) end
 end''').replace('if not W.finished and W.started and W.outputSignal==0 then',"if not W.finished and W.started and W.outputSignal==0 and W.state()=='crafting' then")
    l.execute(world)
    l.execute("world.recipes[1].tier=3;world.bank[8]={tier=3,count=39392,family='Gold',material='Gold',damage=4086};world.bank[7]={count=0};world.bank[6]={tier=1,count=1000,family='Carbon',material='Carbon',damage=4000}")
    l.execute('''
for step=1,20000 do
 E.step()
 if E.tasks[1].fault or #world.outputs>=1 then break end
 world.advance(.05)
end
''')
    if baseline:
     self.assertTrue(l.eval('E.tasks[1].fault'))
     self.assertIn('组内配方蜂群等级变化',l.eval("table.concat(E.logs,' / ')"))
     self.assertEqual(l.eval('#world.outputs'),0)
     # Install fixed code, recreate the engine as after Q/reopen, and resume the
     # actual interrupted cohort + watching journal without resetting either.
     l.globals().s.files['/home/bec_v2/lib/bridge.lua']=(ROOT/'reinstall_v2/files/lib/bridge.lua').read_text(encoding='utf-8')
     l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')();E=factory(cfg,C,Bridge,false);E.resumeNode(1);for step=1,20000 do E.step();if E.tasks[1].fault or #world.outputs>=1 then break end;world.advance(.05)end")
    self.assertFalse(l.eval('E.tasks[1].fault'),l.eval("table.concat(E.logs,' / ')"))
    self.assertEqual(l.eval('#world.outputs'),1)
    self.assertEqual(l.eval('world.heldItem.tier'),1,l.eval("table.concat(E.logs,' / ')"))
    self.assertEqual(l.eval('world.held'),1000)
    self.assertEqual(l.eval("(function()for _,disk in pairs(world.bank)do if disk.family=='Gold' then return disk.count end end end)()"),39392)
    self.assertEqual(l.eval("(function()for _,disk in pairs(world.bank)do if disk.family=='Transcendent' then return disk.count end end end)()"),19612)
    self.assertEqual(l.eval("C.read(C.path('state/group-1/nanites-cell.journal')).stage"),'done')
    self.assertEqual(l.eval("(function()local n=0;for _,e in ipairs(world.events)do if e.kind=='disk-transfer'then n=n+1 end end;return n end)()"),10)
    self.assertEqual(l.eval("(function()for _,side in ipairs({2,3})do for i=1,12 do assert(world.io[side][i]==nil)end end;return true end)()"),True)

if __name__=='__main__':unittest.main()
