"""Stage latency call-count and regression tests; no real OC timing claim."""
import json
from pathlib import Path
import subprocess
import unittest
from lupa.lua52 import LuaRuntime
from test_read_optimization import fixture
from cell_fixture import SETUP,EXT
from test_cell_io import OPTIONS
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1];V2=HERE.parent/'files'

def old(name):return subprocess.check_output(['git','show','549df6e:reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')

def cell(baseline=False):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute(SETUP+EXT+OPTIONS)
 src=old('runtime/nanites_cell.lua')if baseline else (V2/'runtime/nanites_cell.lua').read_text(encoding='utf-8')
 return l,l.execute(src)

def cell_count(baseline=False):
 l,m=cell(baseline)
 l.execute(r'''
noBulk=true;stackReads=0;bankReads=0;outReads=0
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local x,y=...
 if a==T and m=='getStackInSlot'then stackReads=stackReads+1;if x==0 then bankReads=bankReads+1 end;if x~=0 and y>=7 then outReads=outReads+1 end end
 if a==T and m=='transferItem'and firstMoveReads==nil then firstMoveReads=stackReads;firstBankReads=bankReads end
 return invoke(a,m,...)
end
''')
 m.ensure()
 assert l.globals().heldCount==19612 and l.globals().moves==2
 return {k:int(l.globals()[k])for k in ['firstMoveReads','firstBankReads','stackReads','outReads']}

def gate_count(baseline=False,count=16):
 l=fixture()
 if baseline:
  for name in ['lib/bridge.lua','lib/engine.lua','runtime/controller.lua']:
   l.globals().s.files['/home/bec_v2/'+name]=old(name)
  l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')();factory=loadfile('/home/bec_v2/lib/engine.lua')()")
 l.execute('cfg.nodes={};nodes={};outputs={};configure('+str(count)+')')
 l.execute(r'''
gateReads=0;gateNodeReads=0;gateRsReads=0;gateRounds=0
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if gateWindow then
  gateReads=gateReads+1
  if nodes[a]then gateNodeReads=gateNodeReads+1 end
  if a:match('^rs')then gateRsReads=gateRsReads+1 end
  if a=='gate'and m=='isMachineActive'then gateRounds=gateRounds+1 end
 end
 return invoke(a,m,...)
end
E=factory(cfg,C,Bridge,false);local log=E.log
E.log=function(i,message)
 if message:find('配置韦门 / 三轮回读',1,true)then gateWindow=true end
 if message:find('麦克斯韦门过滤:',1,true)then gateWindow=false;gateMeasured=true end
 log(i,message)
end
''')
 # Baseline has no phase-start marker; insert the same marker just before its
 # existing configureGate guard, so both windows cover the same operations.
 if baseline:
  l.execute("s.files['/home/bec_v2/runtime/controller.lua']=s.files['/home/bec_v2/runtime/controller.lua']:gsub('local function configureGate%(required%)','local function configureGate(required) print(\"配置韦门 / 三轮回读\")',1)")
 l.execute("for i=1,100 do E.step();if gateMeasured then break end;s.now=s.now+.1 end;assert(gateMeasured,table.concat(E.logs,' / '));assert(gateRounds==3)")
 return {k:int(l.globals()[k])for k in ['gateReads','gateNodeReads','gateRsReads','gateRounds']}

class StageLatencyTests(unittest.TestCase):
 def test_bounded_bank_and_first_move_call_counts(self):
  before,after=cell_count(True),cell_count()
  self.assertEqual(before['firstBankReads'],244);self.assertEqual(after['firstBankReads'],11)
  self.assertLess(after['firstMoveReads'],before['firstMoveReads'])
  result={'scenario':'243-slot bank, getAllStacks unavailable; reads not elapsed time','before':before,'after':after,'gate16_before':gate_count(True),'gate16_after':gate_count()}
  out=ROOT/'outputs/v2_stage_latency';out.mkdir(parents=True,exist_ok=True);(out/'stage-counts.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result),flush=True)
 def test_outside_bank_slots_are_not_managed(self):
  l,m=cell();l.execute("inv[0][11]={name='not-a-bee-cell'}")
  self.assertTrue(m.ensure());self.assertEqual(l.eval('inv[0][11].name'),'not-a-bee-cell')
 def test_port_preflight_still_checks_every_slot(self):
  for slot in [2,6,8,12]:
   l,m=cell();l.execute(f'inv[3][{slot}]=disk(0)')
   with self.assertRaisesRegex(Exception,'已有硬盘'):m.ensure()
   self.assertEqual(l.globals().moves,0)
 def test_one_nanite_check_per_preparation_round(self):
  l=fixture()
  l.execute("s.files['/home/bec_v2/lib/bridge.lua']=s.files['/home/bec_v2/lib/bridge.lua']:gsub('ensure=function%(%)return false end','ensure=function()naniteChecks=(naniteChecks or 0)+1;return false end');Bridge=loadfile('/home/bec_v2/lib/bridge.lua')();E=factory(cfg,C,Bridge,false);E.step();assert(naniteChecks==1,tostring(naniteChecks))")
 def test_gate_three_rounds_keep_member_pause_and_recipe_guards(self):
  for kind in ['pause','recipe','filters']:
   l=fixture();l.globals().faultKind=kind
   l.execute(r'''
local c=require('component');local invoke=c.invoke;local rounds=0
c.invoke=function(a,m,...)
 local result=invoke(a,m,...)
 if armed and a=='gate'and m=='isMachineActive'then
  rounds=rounds+1
  if rounds==1 then
   if faultKind=='pause'then outputs['rs2-']=0 end
   if faultKind=='recipe'then nodes.node2.required.entangled_chromaticglass=144 end
   if faultKind=='filters'then filters={'wrong-fluid'}end
  end
 end
 return result
end
E=factory(cfg,C,Bridge,false);local log=E.log
E.log=function(i,message)if message:find('配置韦门 / 三轮回读',1,true)then armed=true end;log(i,message)end
for i=1,150 do E.step();s.now=s.now+.1 end
assert(E.tasks[1].fault,table.concat(E.logs,' / '));assert(releaseCount==0);assert(s.moves==0)
''')
 def test_gate_phase_reads_less_without_losing_rounds(self):
  before,after=gate_count(True),gate_count()
  self.assertLess(after['gateNodeReads'],before['gateNodeReads'])
  self.assertEqual(before['gateRounds'],after['gateRounds'])

if __name__=='__main__':unittest.main()
