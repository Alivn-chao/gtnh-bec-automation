"""V3 vs the actual V2 parent; deterministic Lua, not Minecraft timing."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT/'work/lua_runtime'), str(ROOT/'reinstall_v2/tests')]
from test_read_optimization import fixture, COUNTER
from simulate_two_recipes import WORLD
import test_cell_bridge

BASE = 'a293a34'
FILES = ['runtime/controller.lua', 'runtime/nanites_cell.lua', 'lib/bridge.lua']

def old(name):
    return subprocess.check_output(['git','show',BASE+':reinstall_v2/files/'+name],cwd=ROOT).decode()

def setup(baseline=False):
    l=fixture()
    if baseline:
        for name in FILES:l.globals().s.files['/home/bec_v2/'+name]=old(name)
        l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()")
    return l

RUN = """
for step=1,1000 do
 E.step();if E.tasks[1].fault or not E.groupOwner[1] and releaseCount>0 then break end
 s.now=s.now+.1
end
"""

def batch(baseline=False,count=16):
    l=setup(baseline)
    l.execute('cfg.nodes={};nodes={};outputs={};configure('+str(count)+');'+COUNTER)
    l.execute("enabledGenerators=0;local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,on,...)if a:match('^gen')and m=='setWorkAllowed'and on then enabledGenerators=enabledGenerators+1 end;return invoke(a,m,on,...)end;E=factory(cfg,C,Bridge,false)"+RUN)
    assert not l.eval('E.tasks[1].fault'),l.eval("table.concat(E.logs,' / ')")
    assert l.eval('releaseCount')==count
    return {'node_reads':int(l.eval('nodeReads')),'first_release_seconds':round(float(l.eval('releaseTimes[1]')),2),'simulation_seconds':round(float(l.eval('s.now')),2),'generator_starts':int(l.eval('enabledGenerators'))}

def world(baseline=False):
    l=setup(baseline)
    l.execute("cfg.recipeDirectory='/home/bec_v2/recipes'")
    l.execute(WORLD)
    l.execute("recipeReads=0;local open=io.open;io.open=function(p,m)if m=='r'and p:find(cfg.recipeDirectory..'/',1,true)==1 then recipeReads=recipeReads+1 end;return open(p,m)end")
    return l

WORLD_RUN="""
for step=1,10000 do
 E.step();if E.tasks[1].fault or #world.outputs==2 and not E.groupOwner[1]then break end
 world.advance(.05)
end
"""

class PerformanceTests(unittest.TestCase):
    def test_stock_hit_still_requires_generator_shutdown_confirmation(self):
        l=setup()
        l.execute("local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,...)if a=='gen2'and m=='isWorkAllowed'then return true end;return invoke(a,m,...)end;E=factory(cfg,C,Bridge,false)"+RUN)
        self.assertTrue(l.eval('E.tasks[1].fault'))
        self.assertEqual(l.eval('releaseCount'),0)

    def test_stock_hit_releases_shared_supply_lock_while_production_runs(self):
        l=setup()
        l.execute("E=factory(cfg,C,Bridge,false);for i=1,100 do E.step();if releaseCount>0 then break end;s.now=s.now+.1 end;assert(releaseCount==2);assert(E.tasks[1].co);assert(E.groupOwner[1]==1)")
        self.assertIsNone(l.eval('E.fluidOwner'))

    def test_stock_hit_reduces_work_against_latest_v2_without_generator_start(self):
        rows=[]
        for count in (1,2,16):
            before,after=batch(True,count),batch(False,count)
            self.assertLess(after['node_reads'],before['node_reads']*.5)
            self.assertGreater(before['first_release_seconds']-after['first_release_seconds'],4.9)
            self.assertEqual(after['generator_starts'],0)
            rows.append({'nodes':count,'v2':before,'v3':after})
        output=ROOT/'reinstall_v3/evidence';output.mkdir(exist_ok=True)
        (output/'stock-hit.json').write_text(json.dumps({'baseline':BASE,'kind':'Lua simulation; zero component-call latency, not real game speed','rows':rows},indent=2)+'\n',encoding='utf-8')
        print(json.dumps(rows))

    def test_index_reads_each_registered_file_once_per_worker(self):
        before=world(True);before.execute(WORLD_RUN)
        after=world();after.execute(WORLD_RUN)
        for l in (before,after):
            self.assertFalse(l.eval('E.tasks[1].fault'),l.eval("table.concat(E.logs,' / ')"))
            self.assertEqual(l.eval('#world.outputs'),2)
        self.assertEqual(after.eval('recipeReads'),4)
        self.assertGreater(before.eval('recipeReads'),40)
        print('recipe file reads, two batches:',before.eval('recipeReads'),'->',after.eval('recipeReads'))

    def test_new_worker_reloads_catalogue_and_rejects_corrupt_registration(self):
        l=world()
        l.execute("for i=1,2000 do E.step();if #world.outputs==1 and not E.groupOwner[1]then break end;world.advance(.05)end;assert(#world.outputs==1);s.files[cfg.recipeDirectory..'/b.dat']='damaged'")
        l.execute(WORLD_RUN)
        self.assertTrue(l.eval('E.tasks[1].fault'))
        self.assertEqual(l.eval('#world.outputs'),1)
        self.assertIn('登记配方损坏',l.eval("table.concat(E.logs,' / ')"))

    def test_fast_release_rechecks_stock_raw_network_recipe_and_inlet(self):
        mutations={
          'stock':"s.stock.entangled_chromaticglass=0",
          'raw':"badRaw=true",
          'recipe':"nodes.node2.required.entangled_chromaticglass=144",
          'inlet':"badInlet=true",
        }
        for name,mutation in mutations.items():
            with self.subTest(name=name):
                l=setup()
                l.execute("local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,...)if badRaw and a=='sub'and m=='getFluidsInNetwork'then return {{name='molten.chromaticglass',amount=144}}end;if badInlet and a=='fluid'and m=='getFluidInTank'then return {name='molten.chromaticglass',amount=144}end;return invoke(a,m,...)end;E=factory(cfg,C,Bridge,false);local log=E.log;E.log=function(i,msg)log(i,msg);if msg:find('无需搬液和纠缠',1,true)then "+mutation+" end end"+RUN)
                self.assertTrue(l.eval('E.tasks[1].fault'))
                self.assertEqual(l.eval('releaseCount'),0)
                self.assertEqual(l.eval("outputs['rs1-']"),15)

    def test_existing_raw_never_takes_stock_hit_shortcut(self):
        l=setup()
        l.execute("local c=require('component');local invoke=c.invoke;c.invoke=function(a,m,...)if a=='sub'and m=='getFluidsInNetwork'then return {{name='molten.chromaticglass',amount=144}}end;return invoke(a,m,...)end;E=factory(cfg,C,Bridge,false)"+RUN)
        self.assertTrue(l.eval('E.tasks[1].fault'))
        self.assertEqual(l.eval('releaseCount'),0)
        self.assertNotIn('无需搬液和纠缠',l.eval("table.concat(E.logs,' / ')"))

    def test_real_bridge_noop_fewer_reads_preserves_topup_and_port_guards(self):
        counts=[]
        for baseline in (True,False):
            case=test_cell_bridge.BridgeCellTests();case.setUp();l=case.lua
            if baseline:
                for name in ['runtime/nanites_cell.lua','lib/bridge.lua']:
                    l.globals().files['/home/bec_v2/'+name]=old(name)
                l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()")
            l.execute('members(16)');self.assertTrue(case.run_worker())
            l.execute("calls=0;local c=require('component');local invoke=c.invoke;c.invoke=function(...)calls=calls+1;return invoke(...)end")
            self.assertFalse(case.run_worker());counts.append(int(l.eval('calls')))
            self.assertEqual(l.eval('moves'),2)
            l.execute('inv[0][10]=disk(2000)');self.assertTrue(case.run_worker())
            self.assertEqual(l.eval('heldCount'),21612)
            l.execute('inv[3][12]=disk(0)')
            with self.assertRaisesRegex(Exception,'已有硬盘'):case.run_worker()
        self.assertLess(counts[1],counts[0]);print('16-node confirmed hive reuse calls:',counts)

if __name__=='__main__':unittest.main()
