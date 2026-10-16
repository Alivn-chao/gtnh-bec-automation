"""Actual V2 bridge + whole-cell runtime, shared physical hive simulation."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
from cell_fixture import SETUP, EXT
V2 = Path(__file__).resolve().parents[1]/'files'
BRIDGE_FIXTURE = r'''
local c=require('component');local old=c.invoke;local oldType=c.type
local oldMethods=c.methods
c.methods=function(a)if a==NODE or a:match('^member')then return {setWorkAllowed=false,isWorkAllowed=false}end;return oldMethods(a)end
function c.type(a)if a:match('^member')then return 'bec_io_node'end;return oldType(a)end
function c.invoke(a,m,...)
 local args={...}
 if a==P and m=='setOutput'then return true end
 if a=='gen'then if m=='isWorkAllowed'or m=='isMachineActive'then return generatorBusy or false end;if m=='setWorkAllowed'then generatorBusy=args[1];return true end end
 if a:match('^pause')then if m=='getOutput'then return unpaused and a=='pause2'and 0 or 15 end;if m=='setOutput'then return true end end
 if a==NODE or a:match('^member')then
  if m=='setWorkAllowed'then allowed=args[1];return true end
  if m=='getRequiredCondensate'then return {entangled_transcendentmetal=144}end
  if m=='getConsumedCondensate'then return {}end
  if m=='getParallelRecipesInProgress'then return 1 end
  if mismatch and a=='member2'and m=='getAvailableNanites'then return 10 end
  return old(NODE,m,...)
 end
 return old(a,m,...)
end
function loadfile(path,mode,env)return assert(load(assert(files[path],path),path,mode or 't',env or _G))end
local fs=require('filesystem');fs.path=function(path)return path:match('^(.*)/')end
cfg={version=2,mainInterface='main',recipeDirectory='/home/recipes',groups={{storage='field',gate='gate',subInterface='sub',transposer='fluid',mainSide=4,subSide=5,generators={'gen'},nanites={enabled=true,mode='cell-io',transposer=T,loadRedstone=S,returnRedstone=N,bankSide=0,loadSide=3,returnSide=2,loadOutputSide=0,returnOutputSide=0}}},nodes={}}
task={members={},entries={},normalized={entangled_transcendentmetal=144}}
function members(count)
 cfg.nodes={};task.members={};task.entries={}
 for i=1,count do
  cfg.nodes[i]={name='N'..i,address=i==1 and NODE or 'member'..i,redstone=i==1 and P or 'pause'..i,pauseSide=i==1 and 1 or 0,gate='gate',group=1}
  task.members[i]=i;task.entries[i]={tier=need,parallel=1,required={entangled_transcendentmetal=144},consumed={}}
 end
end
members(2)
engine={tasks={[1]=task},acquire=function()locks=(locks or 0)+1 end,release=function()end,log=function()end}
files['/home/bec_v2/runtime/controller.lua']="return loadfile('/home/bec_nanites.lua')().ensure()"
'''


class BridgeCellTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        # Fixture writes are RAM only, with V2 journal directories accepted.
        ext=EXT.replace("p:match('^/home/bec_nanites_io%.journal')", "p:match('^/home/bec_v2/state/')")
        self.lua.execute(SETUP+ext+BRIDGE_FIXTURE)
        for path in [V2/'lib/config.lua',V2/'lib/bridge.lua',V2/'lib/engine.lua',V2/'runtime/nanites_cell.lua']:
            self.lua.globals().files['/home/bec_v2/'+path.relative_to(V2).as_posix()]=path.read_text(encoding='utf-8')
        self.lua.execute("C=loadfile('/home/bec_v2/lib/config.lua')();Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()")

    def run_worker(self):
        return self.lua.eval('function()return Bridge.environment(cfg,1,engine)()end')()

    def test_two_and_sixteen_nodes_share_one_load(self):
        for count in [2,16]:
            self.setUp();self.lua.execute(f'members({count})')
            self.assertTrue(self.run_worker())
            self.assertEqual(self.lua.globals().moves,2)
            self.assertEqual(self.lua.globals().heldCount,19612)
            self.assertGreater(self.lua.globals().locks,0)
            record=self.lua.eval("C.read('/home/bec_v2/state/group-1/nanites-cell.journal')")
            self.assertEqual(record.stage,'done')
            self.assertEqual(self.lua.eval("files['/home/bec_nanites.journal']"),'old-filling-record')

    def test_unpaused_member_busy_generator_and_wrong_hive_stop_before_move(self):
        for flag in ['unpaused','generatorBusy','mismatch']:
            self.setUp();self.lua.execute(flag+'=true')
            with self.assertRaises(Exception):self.run_worker()
            self.assertEqual(self.lua.globals().moves,0)
            self.assertEqual(self.lua.eval('rs[S]'),0)
            self.assertEqual(self.lua.eval('rs[N]'),0)

    def test_other_mode_unfinished_journal_blocks_switch(self):
        self.lua.execute("files['/home/bec_v2/state/group-1/nanites.journal']=require('serialization').serialize({stage='filling'},false)")
        with self.assertRaisesRegex(Exception,'另一蜂群模式'):self.run_worker()
        self.assertEqual(self.lua.globals().moves,0)

    def test_config_rejects_shared_ports_invalid_sides_and_unknown_mode(self):
        self.lua.execute('assert(C.validate(cfg,false))')
        for change in ["cfg.groups[1].nanites.returnRedstone=S",'cfg.groups[1].nanites.bankSide=3',"cfg.groups[1].nanites.mode='bad'","cfg.nodes[2].redstone=S"]:
            self.setUp();self.lua.execute(change)
            self.assertFalse(self.lua.eval('function()return pcall(C.validate,cfg,false)end')()[0])

    def test_shutdown_stops_both_ports_even_without_resuming_worker(self):
        self.lua.execute("rs[S]=15;rs[N]=15;E=loadfile('/home/bec_v2/lib/engine.lua')()(cfg,C,Bridge,false);assert(#E.shutdown()==0)")
        self.assertEqual(self.lua.eval('rs[S]'),0);self.assertEqual(self.lua.eval('rs[N]'),0)

    def test_configured_directions_are_used_for_ports_bank_and_redstone(self):
        self.lua.execute(r'''
local c=require('component');local old=c.invoke
function c.invoke(a,m,...)
 local args={...}
 if a==T and type(args[1])=='number'then
  if m=='transferItem'then observedFrom=args[1];observedTo=args[2]end
  local function map(side)return side==1 and 0 or side==4 and 3 or side==5 and 2 or side end
  args[1]=map(args[1]);if m=='transferItem'then args[2]=map(args[2])end
 elseif a==S or a==N then
  local direction=a==S and 4 or 5
  if args[1]~=direction and m=='getOutput'then return 0 end
  assert(args[1]==direction);args[1]=0
 end
 return old(a,m,table.unpack(args))
end
local b=cfg.groups[1].nanites;b.bankSide=1;b.loadSide=4;b.returnSide=5;b.loadOutputSide=4;b.returnOutputSide=5
''')
        self.assertTrue(self.run_worker())
        self.assertEqual(self.lua.globals().observedFrom,4)
        self.assertEqual(self.lua.globals().observedTo,1)
        self.assertEqual(self.lua.globals().heldCount,19612)

    def test_shared_hive_read_delay_waits_without_repeating_load(self):
        self.lua.execute(r'''
local c=require('component');local old=c.invoke
function c.invoke(a,m,...)
 if a=='member2'and m=='getAvailableNanites'and highs>0 and not delayed then delayed=true;return 0 end
 return old(a,m,...)
end
local worker=coroutine.create(function()return Bridge.environment(cfg,1,engine)()end)
for i=1,40 do
 local ok,value,deadline=coroutine.resume(worker);assert(ok,tostring(value))
 if coroutine.status(worker)=='dead'then assert(value);break end
 now=math.max(now,deadline or now+0.1)
end
assert(coroutine.status(worker)=='dead')
''')
        self.assertTrue(self.lua.globals().delayed)
        self.assertEqual(self.lua.globals().moves,2)
        self.assertEqual(self.lua.globals().highs,1)


if __name__=='__main__':unittest.main()
