import unittest
from test_read_optimization import fixture

SETUP=r'''
local c=require('component');configure(2)
local task={released=true};local entries={};local fullCalls=0
for i=1,2 do
 local n=nodes['node'..i];n.tier=2;n.workAllowed=false;n.consumed=n.required;outputs['rs'..i..'-']=0
 entries[i]={parallel=1,required=n.required,consumed={}}
end
local function full()fullCalls=fullCalls+1;return {requiredTier=2,requiredFamily=nil,state='crafting'}end
poll=loadfile('/home/bec_v2/lib/fixed_batch.lua')()(c,cfg,{1,2},entries,task,full)
getFullCalls=function()return fullCalls end
getEntry=function(i)return entries[i]end
poll()
'''

class FixedBatchTests(unittest.TestCase):
 def world(self):
  l=fixture();l.execute(SETUP);return l

 def test_faster_node_waits_for_slowest_before_tier_switch(self):
  l=self.world();l.execute(r'''
nodes.node2.tier=3
local v=poll();assert(v.requiredTier==2 and v.state=='crafting')
assert(outputs['rs2-']==15 and outputs['rs1-']==0)
nodes.node1.tier=3;v=poll();assert(v.requiredTier==3)
assert(getFullCalls()==1)
''')

 def test_fixed_identity_and_completed_consumption_not_repeated(self):
  l=self.world();l.execute(r'''
local c=require('component');local old=c.invoke;local consumed=0
c.invoke=function(a,m,...)if m=='getRequiredCondensate'or m=='getParallelRecipesInProgress'then error('repeated identity scan')end;if m=='getConsumedCondensate'then consumed=consumed+1 end;return old(a,m,...)end
for i=1,10 do poll()end
assert(consumed==2 and getFullCalls()==1)
''')

 def test_idle_requires_real_consumption_and_closed_admission(self):
  for bad in ('consumption','admission'):
   l=self.world();l.globals().bad=bad;l.execute(r'''
nodes.node2.done=true
if bad=='consumption'then nodes.node2.consumed={}else nodes.node2.workAllowed=true end
assert(not pcall(poll))
''')

 def test_finished_member_does_not_block_remaining_phase(self):
  l=self.world();l.execute(r'''
nodes.node2.done=true;nodes.node1.tier=3
local v=poll();assert(v.requiredTier==3 and getEntry(2).finished and outputs['rs2-']==15)
''')

 def test_cancel_and_fault_do_not_release(self):
  l=self.world();l.execute(r'''
local c=require('component');local old=c.invoke
c.invoke=function(a,m,...)if a=='node1'and m=='getState'then return 'unpowered'end;return old(a,m,...)end
assert(not pcall(poll))
''')

 def test_multiple_unobserved_phases_fall_back_without_leaving_holds(self):
  l=fixture();l.execute(SETUP+r'''
nodes.node2.tier=3;poll();assert(getEntry(2).phaseHeld)
nodes.node2.tier=4;nodes.node1.tier=3
local v=poll();assert(getFullCalls()==2 and not getEntry(2).phaseHeld and outputs['rs2-']==0)
''')

 def test_partial_consumption_is_rechecked_until_proven(self):
  l=self.world();l.execute(r'''
nodes.node1.consumed={};poll();assert(not getEntry(1).consumedProven)
nodes.node1.consumed=nodes.node1.required;poll();assert(getEntry(1).consumedProven)
''')

if __name__=='__main__':unittest.main()
