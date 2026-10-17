"""Restart after physical completion must not leave an idle worker owning a group."""
import subprocess,unittest
from pathlib import Path
from test_read_optimization import fixture
ROOT=Path(__file__).resolve().parents[2]
SCENARIO=r'''
cfg.nodes={};nodes={};outputs={};configure(4)
for i=2,4 do nodes['node'..i].done=true;nodes['node'..i].workAllowed=false end
E=factory(cfg,C,Bridge,false)
for tick=1,300 do E.step();if nodes.node1.started then break end;s.now=s.now+.1 end
assert(nodes.node1.started and E.groupOwner[1]==1)
s.now=s.now+2
assert(require('component').invoke('node1','getState')=='idle')
assert(#E.shutdown()==0)
local old=C.read(C.path('state/group-1/cohort.dat'));assert(old.stage=='working'and old.leader==1)
nodes.node4.done=false;nodes.node4.consumed={};nodes.node4.started=nil
nodes.node4.workAllowed=true
E=factory(cfg,C,Bridge,false);E.resumeNode(1)
'''
class IdleCohortTests(unittest.TestCase):
 def test_old_version_reproduces_idle_wait_despite_another_pending_node(self):
  l=fixture()
  for name in ['lib/bridge.lua','runtime/controller.lua']:
   l.globals().s.files['/home/bec_v2/'+name]=subprocess.check_output(['git','show','6bb05c6:reinstall_v2/files/'+name],cwd=ROOT).decode()
  l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()"+SCENARIO)
  l.execute("for tick=1,100 do E.step();s.now=s.now+.1 end;assert(E.groupOwner[1]==1 and E.tasks[1].co and not E.tasks[1].fault);assert(not nodes.node4.started);assert(table.concat(E.logs,' / '):find('等待订单/机器就绪: idle',1,true))")
 def test_reviewed_completed_cohort_returns_group_and_runs_new_node(self):
  l=fixture();l.execute(SCENARIO)
  l.execute("for tick=1,400 do E.step();s.now=s.now+.1;if nodes.node4.done then break end end;assert(nodes.node4.done,table.concat(E.logs,' / '));assert(not E.tasks[1].fault and not E.tasks[4].fault)")
 def test_idle_without_consumption_proof_stays_closed_for_review(self):
  l=fixture();l.execute(SCENARIO+"nodes.node1.consumed={}")
  l.execute("for tick=1,100 do E.step();s.now=s.now+.1;if E.tasks[1].fault then break end end;assert(E.tasks[1].fault);assert(nodes.node4.workAllowed==false and not nodes.node4.started);assert(C.read(C.path('state/group-1/cohort.dat')).stage=='interrupted')")
 def test_unconfirmed_old_request_is_preserved_and_blocks_handoff(self):
  l=fixture();l.execute(SCENARIO)
  l.execute("local path=C.path('state/node-1/production.journal');local r=C.read(path);r.requests={{state='pending',raw='unknown',amount=100}};C.write(path,r);local before=s.files[path];for tick=1,50 do E.step();s.now=s.now+.1;if E.tasks[1].fault then break end end;assert(E.tasks[1].fault and not nodes.node4.started);assert(s.files[path]==before)")
 def test_finished_group_without_new_order_reopens_idle_admission(self):
  l=fixture();l.execute(SCENARIO+'nodes.node4.done=true')
  l.execute("for tick=1,50 do E.step();s.now=s.now+.1 end;assert(not E.groupOwner[1] and not E.tasks[1].fault);for _,n in pairs(nodes)do assert(n.workAllowed==true)end;assert(C.read(C.path('state/group-1/cohort.dat')).stage=='stopped')")
if __name__=='__main__':unittest.main()
