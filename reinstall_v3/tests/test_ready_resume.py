"""Explicit ready checkpoint recovery never replays admission or cell movement."""
import unittest
import test_cell_feed as cell_feed_tests

READY=r"""
F.step();s.now=10
for tick=1,100 do if F.step()then break end end
assert(F.ready and moves==2 and admitted==16)
local plan=F.plan();local entries={}
for i,n in ipairs(cfg.nodes)do entries[i]={parallel=plan.quota[i],required=nodes[n.address].required,consumed={}}end
C.write(C.path('state/group-1/cohort.dat'),{version=2,stage='interrupted',leader=16,members=plan.members,entries=entries,normalized={entangled_chromaticglass=288}})
C.write(C.path('state/node-16/production.journal'),{stage='watching',configOwned=false,requests={},transfers={}})
"""

class ReadyResumeTests(unittest.TestCase):
 def world(self):
  l=cell_feed_tests.CellFeedTests().world();l.execute(READY);return l

 def test_explicit_resume_is_read_only_and_finishes_with_original_limits(self):
  l=self.world();l.execute(r"""
assert(not pcall(M.new,cfg,1,C,E),'ordinary restart must still refuse')
local writes=s.writes;local next=M.new(cfg,1,C,E,'ready')
assert(next.ready and next.plan().count==1000 and next.step())
assert(moves==2 and admitted==16 and s.writes==writes)
for _,n in pairs(nodes)do n.done=true;n.consumed=n.required end
next.finish();assert(moves==2 and admitted==16)
for _,n in pairs(nodes)do assert(n.min==1 and n.max==256)end
assert(C.read(C.path('state/group-1/cell-feed.journal')).stage=='stopped')
""")

 def test_consumed_progress_and_next_cached_material_are_preserved(self):
  l=self.world();l.execute("nodes.node1.consumed=nodes.node1.required;disk[4]=makeDisk(7);local next=M.new(cfg,1,C,E,'ready');assert(next.ready and moves==2 and admitted==16 and disk[4].storedItemCount==70)")

 def test_invalid_identity_or_pending_action_is_refused_without_mutation(self):
  changes=[
   "local r=C.read(C.path('state/group-1/cell-feed.journal'));r.pending={kind='move'};C.write(C.path('state/group-1/cell-feed.journal'),r)",
   "cfg.groups[1].cellFeed.productionSide=3",
   "nodes.node1.parallel=1000",
   "nodes.node1.consumed={entangled_chromaticglass=999999}",
   "nodes.node1.done=true",
   "outputs['rs1-']=0",
   "nodes.node1.workAllowed=true",
   "disk[5]=makeDisk(1)",
   "local r=C.read(C.path('state/node-16/production.journal'));r.requests={{state='pending'}};C.write(C.path('state/node-16/production.journal'),r)",
   "local r=C.read(C.path('state/group-1/cohort.dat'));r.entries[1].required={entangled_chromaticglass=1};C.write(C.path('state/group-1/cohort.dat'),r)",
  ]
  for change in changes:
   with self.subTest(change=change):
    l=self.world();l.execute(change+";local writes=s.writes;assert(not pcall(M.new,cfg,1,C,E,'ready'));assert(moves==2 and admitted==16 and s.writes==writes)")

 def test_engine_can_explicitly_resume_and_clean_up_the_same_cohort(self):
  l=self.world();l.execute(r"""
local calls=0
local bridge={environment=function(config,index,engine)return function(mode)
 calls=calls+1;assert(mode=='resume'and engine.tasks[index].fixedBatch.count==1000)
 for _,n in pairs(nodes)do n.done=true;n.consumed=n.required end
end end}
E=factory(cfg,C,bridge,false,'ready');E.resumeNode(16);E.step()
assert(calls==1 and moves==2 and admitted==16 and not E.groupOwner[1])
assert(C.read(C.path('state/group-1/cohort.dat')).stage=='stopped')
assert(C.read(C.path('state/group-1/cell-feed.journal')).stage=='stopped')
""")

if __name__=='__main__':unittest.main()
