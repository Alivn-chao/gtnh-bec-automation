import unittest
import test_cell_feed as feed_tests
from test_read_optimization import fixture

def feed_world(count):
 l=feed_tests.CellFeedTests().world();l.globals().batch=count
 l.execute(r'''
disk[4]=makeDisk(batch);setters,noops=0,0
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local n=nodes[a];local v=...
 if n and(m=='setMinParallel'or m=='setMaxParallel')then
  setters=setters+1;if(m=='setMinParallel'and n.min or n.max)==v then noops=noops+1 end
  assert(m~='setMinParallel'or v<=n.max,'min above max');assert(m~='setMaxParallel'or v>=n.min,'max below min')
 end
 return invoke(a,m,...)
end
function admit()
 F.step();s.now=10
 for i=1,100 do if F.step()then break end;s.now=s.now+.2 end
 assert(F.ready)
end
function complete()for _,n in pairs(nodes)do n.done=true end;F.finish()end
''');return l

def disk_world(disabled=True):
 l=fixture();l.globals().disabled=disabled
 l.execute(r'''
local fs=require('filesystem');fs.get=function()return{}end
s.files[C.path('lib/storage.lua')]=[[return function()
 return{status=function()checks=(checks or 0)+1;return{known=not unreadable,ok=not low and not unreadable}end,
 prune=function()prunes=(prunes or 0)+1;if frees then low=false end end}
end]]
prunes,checks=0,0;E=factory(cfg,C,Bridge,false)
if disabled then for _,t in ipairs(E.tasks)do t.disabled=true end end
''');return l

class ParameterDeltaTests(unittest.TestCase):
 def test_only_changed_parameters_are_written(self):
  counts=[]
  for n,writes in ((3,6),(16,32),(1000,64)):
   l=feed_world(n);l.execute('admit();complete()')
   self.assertEqual(l.globals().setters,writes);self.assertEqual(l.globals().noops,0)
   l.execute('for _,n in pairs(nodes)do assert(n.min==1 and n.max==256)end')
   counts.append((n,writes))
  print('parallel setters for 3/16/1000-run batches:',counts)

 def test_range_order_and_already_matching_limits(self):
  for low,high,writes in ((5,10,64),(1,1,0)):
   l=feed_world(16);l.globals().low=low;l.globals().high=high
   l.execute('for _,n in pairs(nodes)do n.min=low;n.max=high end;admit();complete();for _,n in pairs(nodes)do assert(n.min==low and n.max==high)end')
   self.assertEqual(l.globals().setters,writes)

 def test_unused_nodes_are_not_restored(self):
  l=feed_world(3);l.execute('admit();nodes.node4.min=7;nodes.node4.max=9;complete();assert(nodes.node4.min==7 and nodes.node4.max==9)')
  self.assertEqual(l.globals().setters,6)

 def test_unknown_setter_response_preserves_intent_without_replay(self):
  l=feed_world(16);l.execute(r'''
local c=require('component');local invoke=c.invoke;attempts=0
c.invoke=function(a,m,...)local result=invoke(a,m,...);if m=='setMaxParallel'then attempts=attempts+1;error('lost setter response')end;return result end
F.step();s.now=10;assert(not pcall(F.step));assert(attempts==1 and F.plan().pending.kind=='set-parallel')
assert(not pcall(F.step)and attempts==1);assert(not pcall(M.new,cfg,1,C,E))
''')

class DiskMaintenanceTests(unittest.TestCase):
 def test_periodic_space_checks_do_not_scan_archives(self):
  l=disk_world();l.execute('E.step();assert(prunes==1);for i=1,5 do s.now=i*10;E.step()end;assert(prunes==1 and checks==7)')

 def test_archive_scan_waits_until_cache_releases_resources(self):
  l=disk_world();l.execute("E.fluidOwner='cache-1';E.groupOwner[1]='cache-1';E.step();assert(prunes==0);E.fluidOwner=nil;E.groupOwner[1]=nil;E.step();assert(prunes==1)")

 def test_low_space_cleanup_is_immediate_but_rate_limited(self):
  l=disk_world();l.execute("E.fluidOwner='cache-1';E.groupOwner[1]='cache-1';low=true;frees=true;E.step();assert(prunes==1 and not E.diskLow);low=true;s.now=10;E.step();assert(prunes==1 and E.diskLow);s.now=61;E.step();assert(prunes==2 and not E.diskLow)")

 def test_first_low_space_event_is_not_delayed_by_regular_cleanup(self):
  l=disk_world();l.execute('E.step();assert(prunes==1);s.now=10;low=true;frees=true;E.step();assert(prunes==2 and not E.diskLow)')

 def test_successful_batch_requests_one_idle_cleanup(self):
  l=disk_world(False);l.execute('for i=1,150 do E.step();s.now=s.now+.1;if releaseCount==#cfg.nodes and not E.groupOwner[1]then break end end;assert(releaseCount==#cfg.nodes and not E.groupOwner[1]);assert(prunes==2)')

 def test_unreadable_disk_pauses_without_archive_scan(self):
  l=disk_world();l.execute('unreadable=true;E.step();assert(E.diskLow and prunes==0 and E.tasks[1].disabled)')

if __name__=='__main__':unittest.main()
