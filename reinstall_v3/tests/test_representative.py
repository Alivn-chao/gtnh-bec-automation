"""Representative demand sampling for frozen, verified same-recipe cohorts."""
import unittest
from test_read_optimization import fixture

SETUP=r'''
configure(16)
local c=require('component');local original=c.invoke
task={released=false,fixedBatch={count=1000},members={},entries={},normalized={entangled_chromaticglass=288,entangled_transcendentmetal=288}}
reads={};progress={};local steps={{start=0,['end']=100},{start=100,['end']=200}}
for i=1,16 do
 local n=nodes['node'..i];local q=i<=8 and 62 or 63
 n.parallel=q;n.required={entangled_chromaticglass=288*q,entangled_transcendentmetal=288*q};n.workAllowed=false;n.tier=2
 task.members[i]=i;task.entries[i]={parallel=q,required={entangled_chromaticglass=288*q,entangled_transcendentmetal=288*q},consumed={}}
 progress['node'..i]=50
end
c.invoke=function(a,m,...)
 if nodes[a]then reads[a..'/'..m]=(reads[a..'/'..m]or 0)+1 end
 if m=='getWorkProgress'then return progress[a]end
 if m=='getRecipeSteps'then return steps end
 return original(a,m,...)
end
local function fallback()error('unexpected full cohort fallback')end
R=loadfile('/home/bec_v2/lib/representative.lua')()(c,cfg,task.members,task.entries,task,fallback)
'''

class RepresentativeTests(unittest.TestCase):
 def world(self):
  l=fixture();l.execute(SETUP);return l

 def test_largest_parallel_and_last_tie_is_the_only_demand_source(self):
  l=self.world();l.execute(r'''
local v=R.snapshot(true);assert(v.reference==16 and v.parallel==1000 and v.requiredTier==2 and v.allPaused)
for i=1,16 do
 assert((reads['node'..i..'/getRequiredTier']or 0)==(i==16 and 1 or 0))
 assert((reads['node'..i..'/getRequiredCondensate']or 0)==(i==16 and 1 or 0))
 assert((reads['node'..i..'/getParallelRecipesInProgress']or 0)==(i==16 and 1 or 0))
 assert(reads['node'..i..'/getState']==1)
end
assert(R.parallel()==1000 and R.required().entangled_chromaticglass==288000)
''')

 def test_reference_recipe_or_batch_change_is_rejected(self):
  for mutation in ('nodes.node16.parallel=64','nodes.node16.required.entangled_chromaticglass=1'):
   l=self.world();l.execute(mutation+';assert(not pcall(R.snapshot,true))')

 def test_non_reference_fault_pause_and_completion_are_still_checked(self):
  for mutation in ("outputs['rs3-']=0", "nodes.node3.done=true"):
   l=self.world();l.execute(mutation+';assert(not pcall(R.snapshot,true))')
  l=self.world();l.execute(r'''
local c=require('component');local old=c.invoke
c.invoke=function(a,m,...)if a=='node3'and m=='getState'then return 'unpowered'end;return old(a,m,...)end
assert(not pcall(R.snapshot))
''')

 def test_finished_reference_selects_next_largest_and_requires_closed_admission(self):
  l=self.world();l.execute(r'''
nodes.node16.done=true;nodes.node16.consumed=nodes.node16.required
local v=R.snapshot(true);assert(v.reference==15 and task.entries[16].finished)
nodes.node16.workAllowed=true;assert(not pcall(R.snapshot,true))
''')

 def test_stage_barrier_uses_progress_without_reading_other_tiers(self):
  l=self.world();l.execute(r'''
task.released=true
for i,n in pairs(nodes)do outputs['rs'..i:match('%d+')..'-']=0;n.consumed=n.required end
R.production();reads={}
nodes.node16.tier=3;progress.node16=100
for i=1,15 do progress['node'..i]=100 end
progress.node1=90
local v=R.production();assert(v.requiredTier==2 and outputs['rs16-']==15 and outputs['rs1-']==0)
progress.node1=100;v=R.production();assert(v.requiredTier==3 and v.state=='paused-immediate')
for i=1,15 do assert(not reads['node'..i..'/getRequiredTier'])end
''')

 def test_consumption_is_read_until_real_proof_and_not_scaled_from_reference(self):
  l=self.world();l.execute(r'''
task.released=true
for i,n in pairs(nodes)do outputs['rs'..i:match('%d+')..'-']=0;n.consumed=n.required end
nodes.node1.consumed={}
local v=R.snapshot();assert(v.consumed.entangled_chromaticglass==288*(1000-62))
nodes.node1.consumed=nodes.node1.required;v=R.snapshot();assert(v.consumed.entangled_chromaticglass==288000)
local count=reads['node16/getConsumedCondensate'];R.snapshot();assert(reads['node16/getConsumedCondensate']==count)
''')

 def test_full_bridge_cell_inspection_keeps_all_pause_checks_but_one_demand(self):
  l=self.world();l.execute(r'''
cfg.groups[1].cellFeed={enabled=true,representativeChecks=true}
cfg.groups[1].nanites={enabled=true,mode='cell-io'}
local e={tasks={[1]=task},acquire=function()end,release=function()end,log=function()end}
local old=load
load=function(source,path,mode,env)if path:find('runtime/controller.lua',1,true)then captured=env;return function()end end;return old(source,path,mode,env)end
Bridge.environment(cfg,1,e);load=old;reads={}
local v=captured.BEC_CELL_IO.inspect();assert(v.reference==16 and v.requiredTier==2)
for i=1,15 do assert(not reads['node'..i..'/getRequiredTier']and not reads['node'..i..'/getRequiredCondensate'])end
assert(reads['node16/getRequiredTier']==1)
reads={};local c=captured.require('component');assert(c.invoke('node1','getParallelRecipesInProgress')==1000)
assert(c.invoke('node1','getRequiredCondensate').entangled_chromaticglass==288000);assert(not next(reads))
outputs['rs3-']=0;assert(not pcall(captured.BEC_CELL_IO.inspect))
''')

 def test_full_sixteen_node_controller_finishes_with_representative_sampling(self):
  l=fixture();l.execute(r'''
configure(16)
cfg.groups[1].cellFeed={enabled=false,representativeChecks=true}
local environment=Bridge.environment
Bridge.environment=function(config,index,engine)
 engine.tasks[index].fixedBatch={count=16}
 return environment(config,index,engine)
end
E=factory(cfg,C,Bridge,false)
for tick=1,300 do
 E.step();s.now=s.now+.1
 if releaseCount==16 and not E.groupOwner[1]then break end
end
assert(releaseCount==16 and not E.groupOwner[1],table.concat(E.logs,' / '))
local cohort=C.read(C.path('state/group-1/cohort.dat'));assert(cohort.stage=='stopped')
for i=1,16 do assert(cohort.entries[i].finished and not E.tasks[i].fault)end
''')

 def test_real_controller_reduces_component_reads_for_same_completed_batch(self):
  counts=[]
  for enabled in (False,True):
   l=fixture();l.globals().enabled=enabled;l.execute(r'''
configure(16);cfg.groups[1].cellFeed={enabled=false,representativeChecks=enabled}
local c=require('component');local invoke=c.invoke;calls=0
c.invoke=function(a,m,...)if nodes[a]then calls=calls+1 end;return invoke(a,m,...)end
local environment=Bridge.environment
Bridge.environment=function(config,index,engine)engine.tasks[index].fixedBatch={count=16};return environment(config,index,engine)end
E=factory(cfg,C,Bridge,false)
for tick=1,300 do E.step();s.now=s.now+.1;if releaseCount==16 and not E.groupOwner[1]then break end end
assert(releaseCount==16 and not E.groupOwner[1]and not E.tasks[1].fault,table.concat(E.logs,' / '))
''');counts.append(l.eval('calls'))
  self.assertLess(counts[1],counts[0]*.7)
  print('fixed-batch node callbacks, old vs representative:',counts)

if __name__=='__main__':unittest.main()
