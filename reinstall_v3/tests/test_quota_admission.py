"""Concurrent fixed quotas with asynchronous nodes; model timings, not game FPS."""
import unittest
from test_batch_overhead import feed_world


DELAYED=r'''
local c=require('component');local invoke=c.invoke
queued={};opened={};openCalls=0
c.invoke=function(a,m,...)
 local n=nodes[a]
 if n and m=='setWorkAllowed'and select(1,...)==true then
  openCalls=openCalls+1;opened[a]=s.now;queued[a]=s.now+(delays[a]or 1)
  n.workAllowed=true;return
 end
 if n and m=='getState'and queued[a]and s.now>=queued[a]then
  queued[a]=nil;invoke(a,'setWorkAllowed',true)
 end
 return invoke(a,m,...)
end
'''


class QuotaAdmissionTests(unittest.TestCase):
 def test_all_quotas_and_pause_signals_precede_first_open(self):
  l=feed_world(1000);l.execute(r'''
local c=require('component');local invoke=c.invoke;opening=false
c.invoke=function(a,m,...)
 if nodes[a]and m=='setWorkAllowed'and select(1,...)then
  if not opening then
   opening=true
   for i=1,16 do local n=nodes['node'..i]
    assert(n.min==F.plan().quota[i]and n.max==n.min and not n.workAllowed)
    assert(outputs['rs'..i..'-']==15)
   end
  end
 end
 return invoke(a,m,...)
end
F.step();s.now=10;assert(not F.step());assert(admitted==16 and moves==1)
assert(F.plan().admissionMode=='quota-wave')
assert(F.step()and F.ready and moves==2)
for _,n in pairs(nodes)do assert(not n.workAllowed)end
''')

 def test_slow_out_of_order_nodes_do_not_serialize_the_wave(self):
  l=feed_world(1000);l.execute("delays={node1=8,node2=3,node16=5};"+DELAYED+r'''
F.step();s.now=10;assert(not F.step());assert(openCalls==16 and admitted==0)
for i=1,16 do assert(opened['node'..i]==10)end
s.now=11;assert(not F.step());assert(admitted==13 and not F.ready and moves==1)
s.now=13;assert(not F.step());assert(admitted==14)
s.now=15;assert(not F.step());assert(admitted==15)
s.now=18;assert(F.step());assert(admitted==16 and F.ready and moves==2)
assert(F.plan().timings.admission==8)
''')

 def test_unused_nodes_never_open_and_one_node_works_too(self):
  for count in (1,3):
   l=feed_world(count);l.execute('admit()')
   self.assertEqual(l.globals().admitted,count)
   l.execute('for i=1,16 do local n=nodes["node"..i];assert(not n.workAllowed);assert(i<=batch or n.done)end;complete()')

 def test_waiting_transient_crafting_is_closed_and_not_reopened(self):
  l=feed_world(16);l.execute(r'''
F.step();s.now=10;F.step()
local c=require('component');local invoke=c.invoke;transient=true
c.invoke=function(a,m,...)if a=='node16'and m=='getState'and transient then return 'crafting'end;return invoke(a,m,...)end
assert(not F.step());assert(F.plan().waveClosed and admitted==16 and moves==1)
for _,n in pairs(nodes)do assert(not n.workAllowed)end
transient=false;assert(F.step()and F.ready and admitted==16 and moves==2)
''')

 def test_unknown_open_or_close_preserves_intent_and_never_replays(self):
  for enabled in (True,False):
   l=feed_world(16);l.globals().failing=enabled;l.execute(r'''
local c=require('component');local invoke=c.invoke;failures=0
c.invoke=function(a,m,...)
 local v=invoke(a,m,...)
 if a=='node3'and m=='setWorkAllowed'and select(1,...)==failing then failures=failures+1;error('callback lost after mutation')end
 return v
end
F.step();s.now=10
if not failing then assert(not F.step())end
assert(not pcall(F.step));assert(failures==1)
local r=C.read(C.path('state/group-1/cell-feed.journal'))
assert(r.pending.kind=='admission-wave'and r.pending.enabled==failing and #r.pending.nodes==16)
local count=admitted
assert(not pcall(F.step)and admitted==count and failures==1)
assert(not pcall(M.new,cfg,1,C,E)and not pcall(M.new,cfg,1,C,E,true))
assert(moves==1 and not F.ready)
''')

 def test_bad_quota_recipe_and_leftovers_do_not_return_cell_or_produce(self):
  for change in (
   'nodes.node16.parallel=2',
   'nodes.node16.required={foreign=288}',
   'nodes.node16.required.entangled_chromaticglass=144',
   'disk[5]=makeDisk(1)',
  ):
   l=feed_world(16);l.execute('F.step();s.now=10;F.step();'+change+r'''
assert(not pcall(F.step)and not F.ready and moves==1)
for _,n in pairs(nodes)do assert(not n.workAllowed)end
''')

 def test_pause_at_wave_intent_never_opens_and_keeps_record(self):
  l=feed_world(16);l.execute(r'''
local write=C.write
C.write=function(path,r)write(path,r);if r.stage=='opening-nodes'then E.tasks[1].disabled=true end end
F.step();s.now=10;assert(not pcall(F.step));assert(admitted==0 and moves==1)
assert(C.read(C.path('state/group-1/cell-feed.journal')).pending.kind=='admission-wave')
''')

 def test_preflight_rejects_missing_pause_or_methods_before_any_node_opens(self):
  for failure in ('pause','methods'):
   l=feed_world(16);l.globals().failure=failure;l.execute(r'''
local write=C.write
C.write=function(path,r)
 write(path,r)
 if r.stage=='admitting'then
  if failure=='pause'then outputs['rs16-']=0
  else local c=require('component');local methods=c.methods;c.methods=function(a)if a=='node16'then return {}end;return methods(a)end end
 end
end
F.step();s.now=10;assert(not pcall(F.step)and admitted==0 and moves==1)
''')

 def test_false_method_values_are_present(self):
  l=feed_world(16);l.execute(r'''
local c=require('component');local methods=c.methods
c.methods=function(a)local out=methods(a);if nodes[a]then out.setWorkAllowed=false;out.isWorkAllowed=false end;return out end
admit();assert(F.ready and admitted==16)
''')

 def test_engine_closes_entire_group_after_partial_open_failure(self):
  l=feed_world(16);l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local v=invoke(a,m,...)
 if a=='node3'and m=='setWorkAllowed'and select(1,...)==true then error('lost open reply')end
 return v
end
local starts=0
E=factory(cfg,C,{environment=function()starts=starts+1;error('must not produce')end},false)
E.step();s.now=10;E.step();assert(E.tasks[1].fault and starts==0 and admitted==3 and moves==1)
for i=1,16 do assert(not nodes['node'..i].workAllowed and outputs['rs'..i..'-']==15)end
E.step();assert(admitted==3)
''')

 def test_group_checkpoints_replace_per_node_open_and_close_records(self):
  results=[]
  for concurrent in (False,True):
   l=feed_world(1000);l.globals().concurrent=concurrent;l.execute(r'''
cfg.groups[1].cellFeed.concurrentAdmission=concurrent
-- Exercise the real engine's durable single-node setter in the legacy path.
local engine=factory(cfg,C,{},false);E.nodeWork=engine.nodeWork
local write=C.write;writes=0
C.write=function(path,r)writes=writes+1;write(path,r)end
admit();measured=writes
''')
   results.append(l.globals().measured)
  self.assertLess(results[1],results[0]/2)
  print('16-node admission journal writes, serial/wave:',results)


if __name__=='__main__':unittest.main()
