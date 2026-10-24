import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests')]
from test_read_optimization import fixture
ACTUAL=Path(__file__).parent/'files/runtime/controller.lua'
class SlowRecipeTests(unittest.TestCase):
 def begin(self,actual=False):
  l=fixture()
  if actual:l.globals().s.files['/home/bec_v2/runtime/controller.lua']=ACTUAL.read_text(encoding='utf-8')
  l.execute('''
for _,n in pairs(nodes)do n.duration=7200 end
E=factory(cfg,C,Bridge,false)
for i=1,100 do E.step();if releaseCount>0 then break end;s.now=s.now+.1 end
assert(releaseCount==2,table.concat(E.logs,' / '))
''');return l
 def test_two_hour_recipe_survives_unchanged_stock_and_completes(self):
  for actual in [False,True]:
   with self.subTest(actual=actual):
    l=self.begin(actual);l.execute('''
for i=1,70 do s.now=s.now+100;E.step();assert(not E.tasks[1].fault,table.concat(E.logs,' / '))end
assert(E.groupOwner[1]==1 and not nodes.node1.done)
for i=1,10 do s.now=s.now+100;E.step();if not E.groupOwner[1]then break end end
assert(nodes.node1.done and nodes.node2.done);assert(not E.tasks[1].fault)
assert(C.read(C.path('state/group-1/cohort.dat')).stage=='stopped')
assert(s.moves==0 and releaseCount==2)
''')
 def test_explicit_pause_still_stops_long_recipe(self):
  for actual in [False,True]:
   l=self.begin(actual);l.execute('''s.now=s.now+1800;E.step();assert(not E.tasks[1].fault);E.pauseAll();E.step();assert(outputs['rs1-']==15 and outputs['rs2-']==15);assert(not E.groupOwner[1])''')
 def test_machine_failure_still_stops_long_recipe(self):
  for actual in [False,True]:
   l=self.begin(actual);l.execute('''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if nodes[a]and m=='getState'then return 'assembler-offline'end;return invoke(a,m,...)end
s.now=s.now+1800;E.step();assert(E.tasks[1].fault);assert(outputs['rs1-']==15 and outputs['rs2-']==15)
''')
if __name__=='__main__':unittest.main()
