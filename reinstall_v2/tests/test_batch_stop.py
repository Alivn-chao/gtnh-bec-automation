"""Node work permission gates next orders without cancelling active batches."""
import unittest
from test_read_optimization import fixture


class BatchStopTests(unittest.TestCase):
 def test_every_group_node_is_closed_before_any_release(self):
  l=fixture();l.execute(r'''
configure(16)
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local args={...}
 if a:match('^rs')and m=='setOutput'and args[2]==0 then
  for _,node in pairs(nodes)do assert(node.workAllowed==false,'open admission at release')end
 end
 return invoke(a,m,...)
end
E=factory(cfg,C,Bridge,false)
for tick=1,200 do E.step();s.now=s.now+.1;if releaseCount==16 then break end end
assert(releaseCount==16,table.concat(E.logs,' / '))
''')

 def test_finished_member_stays_closed_while_group_runs(self):
  l=fixture();l.execute(r'''
E=factory(cfg,C,Bridge,false)
local observed=false
for tick=1,200 do
 E.step()
 if nodes.node1.done and not nodes.node2.done then
  assert(E.groupOwner[1]);assert(nodes.node1.workAllowed==false);observed=true
 end
 if observed and not E.groupOwner[1]then break end
 s.now=s.now+.1
end
assert(observed)
E.step();assert(nodes.node1.workAllowed==true and nodes.node2.workAllowed==true)
assert(outputs['rs1-']==15 and outputs['rs2-']==15)
''')

 def test_failed_close_readback_never_releases(self):
  l=fixture();l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if a=='node2'and m=='setWorkAllowed'then return true end
 return invoke(a,m,...)
end
E=factory(cfg,C,Bridge,false);local ok,reason=pcall(E.step)
assert(not ok and tostring(reason):find('启停回读不符',1,true))
assert(releaseCount==0)
assert(nodes.node1.workAllowed==false)
''')

 def test_interrupted_cohort_never_reopens_on_startup(self):
  l=fixture();l.execute(r'''
for _,node in pairs(nodes)do node.done=true;node.workAllowed=false end
C.write(C.path('state/group-1/cohort.dat'),{stage='working',leader=1})
E=factory(cfg,C,Bridge,false);E.step()
assert(nodes.node1.workAllowed==false and nodes.node2.workAllowed==false)
assert(E.tasks[1].disabled and releaseCount==0)
''')

 def test_stop_and_monitor(self):
  l=fixture();l.execute(r'''
E=factory(cfg,C,Bridge,true);E.step();E.shutdown()
assert(nodes.node1.workAllowed==nil)
E=factory(cfg,C,Bridge,false);assert(#E.shutdown()==0)
assert(nodes.node1.workAllowed==false and nodes.node2.workAllowed==false)
local record=C.read(C.path('state/node-1/batch-stop.dat'))
assert(record.stage=='confirmed'and record.enabled==false)
''')

if __name__=='__main__':unittest.main()
