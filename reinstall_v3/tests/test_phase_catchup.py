"""Eight live 2026-10-26 nodes straddling T4, repeated T1, and final T2."""
import subprocess
import unittest
from pathlib import Path
from test_read_optimization import fixture
from test_representative import SETUP

ROOT=Path(__file__).resolve().parents[2]
LIVE=r'''
liveSteps={
 {start=0,['end']=66667,nanite={tier=4,name='Transcendent'}},
 {start=66667,['end']=133334,nanite={tier=1,name='Carbon'}},
 {start=133334,['end']=200001,nanite={tier=1,name='Carbon'}},
 {start=200001,['end']=266668,nanite={tier=2,name='Silver'}},
 {start=266668,['end']=333335,nanite={tier=1,name='Carbon'}},
 {start=333335,['end']=400001,nanite={tier=1,name='Carbon'}},
 {start=400001,['end']=466668,nanite={tier=4,name='Transcendent'}},
 {start=466668,['end']=533334,nanite={tier=1,name='Carbon'}},
 {start=533334,['end']=600001,nanite={tier=1,name='Carbon'}},
 {start=600001,['end']=666667,nanite={tier=1,name='Carbon'}},
 {start=666667,['end']=733334,nanite={tier=1,name='Carbon'}},
 {start=733334,['end']=800000,nanite={tier=2,name='Silver'}}}
while #task.members>8 do table.remove(task.members)end
physicalTier=1;task.released=true
for i=1,8 do
 local n=nodes['node'..i];n.parallel=1;n.required={entangled_time=1440,entangled_bedrockium=36864,entangled_neutronium=73728,entangled_cosmicneutronium=73728};n.consumed=n.required
 task.entries[i]={parallel=1,required=n.required,consumed={},tier=4};outputs['rs'..i..'-']=0
 progress['node'..i]=i==1 and 400001 or i==2 and 464656 or 700000
end
function need(a)
 for _,step in ipairs(liveSteps)do if progress[a]>=step.start and progress[a]<step['end']then return step.nanite or {tier=4,name='Transcendent'} end end
 return {tier=1,name='Carbon'}
end
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if m=='getRecipeSteps'then return liveSteps end
 if nodes[a]and m=='getRequiredTier'then reads[a..'/'..m]=(reads[a..'/'..m]or 0)+1;return need(a)end
 if nodes[a]and m=='getState'then
  if nodes[a].done then return 'idle'end
  if need(a).tier>physicalTier then return 'nanite-tier-too-low'end
  return outputs['rs'..a:match('%d+')..'-']==15 and 'paused-immediate'or 'crafting'
 end
 return invoke(a,m,...)
end
R=loadfile('/home/bec_v2/lib/representative.lua')()(c,cfg,task.members,task.entries,task,function()error('fallback')end)
assert(R.production().requiredTier==1)
for i=3,8 do progress['node'..i]=733334 end
function globalPause(value)
 R.invalidateInspection()
 for i=1,8 do outputs['rs'..i..'-']=value end
end
'''

class CatchupTests(unittest.TestCase):
 def world(self,old=False):
  l=fixture()
  if old:l.globals().s.files['/home/bec_v2/lib/representative.lua']=subprocess.check_output(['git','show','31f1dc4:reinstall_v2/files/lib/representative.lua'],cwd=ROOT).decode()
  l.execute(SETUP+LIVE);return l

 def test_old_source_reproduces_live_deadlock_for_forty_iterations(self):
  l=self.world(True);l.execute("for tick=1,40 do local v=R.production();assert(v.requiredTier==1);for i=1,8 do local a='node'..i;if outputs['rs'..i..'-']==0 and physicalTier>=need(a).tier then progress[a]=progress[a]+1 end end end;assert(progress.node1==400001 and progress.node2==464656);for i=3,8 do assert(outputs['rs'..i..'-']==15)end")

 def test_lagging_t4_controls_both_runtime_and_paused_hive_inspection(self):
  l=self.world();l.execute("local v=R.production();assert(v.requiredTier==4 and v.requiredFamily=='Transcendent');assert(R.inspection(true).requiredTier==4);assert(R.demand().tier==4);for i=1,7 do assert(not reads['node'..i..'/getRequiredTier'])end")

 def test_global_release_does_not_leave_leading_nodes_unheld(self):
  l=self.world();l.execute("assert(R.production().requiredTier==4);globalPause(15);assert(R.inspection(true).requiredTier==4);physicalTier=4;globalPause(0);R.production();for i=3,8 do assert(outputs['rs'..i..'-']==15,'barrier was lost')end;assert(outputs['rs1-']==0 and outputs['rs2-']==0)")

 def test_multiple_skipped_stages_catch_up_and_all_eight_finish(self):
  l=self.world();l.execute(r'''
local v
for tick=1,100 do
 v=R.production()
 if v.requiredTier~=physicalTier then
  globalPause(15);assert(R.inspection(true).requiredTier==v.requiredTier)
  physicalTier=v.requiredTier;globalPause(0);v=R.production()
 end
 if progress.node1>=733334 and progress.node2>=733334 then break end
 for i=1,2 do local a='node'..i
  if outputs['rs'..i..'-']==0 and physicalTier>=need(a).tier then progress[a]=math.min(733334,progress[a]+17000)end
 end
end
assert(progress.node1==733334 and progress.node2==733334)
v=R.production();assert(v.requiredTier==2)
globalPause(15);assert(R.inspection(true).requiredTier==2);physicalTier=2;globalPause(0)
for i=1,8 do progress['node'..i]=800000;nodes['node'..i].done=true end
v=R.snapshot();assert(v.allIdle)
for i=1,8 do assert(task.entries[i].finished and task.entries[i].consumedProven)end
''')

 def test_same_hive_barrier_requests_release_until_acknowledged(self):
  l=self.world();l.execute(r"""
progress.node1=266668;progress.node2=266668
liveSteps[5].nanite={tier=2,name='Silver'}
assert(R.production().requiredTier==2)
progress.node1=733334;progress.node2=733334
local v=R.production();assert(v.requiredTier==2 and v.phaseReleaseRequired)
assert(R.production().phaseReleaseRequired,'a refill snapshot must not consume the release request')
globalPause(15);assert(not R.production().phaseReleaseRequired)
""")

 def test_controller_releases_barrier_even_when_hive_demand_is_unchanged(self):
  l=fixture();l.execute(r"""
for _,n in pairs(nodes)do n.duration=10000 end
local c=require('component');local invoke=c.invoke;local releases=0;local releaseNeeded
c.invoke=function(a,m,...)
 local side,value=...
 if a:match('^rs')and m=='setOutput'and value==0 then releases=releases+1;if barrier then releaseNeeded=false end end
 return invoke(a,m,...)
end
local environment=Bridge.environment
Bridge.environment=function(config,index,engine)
 local loader=load;local worker
 load=function(source,path,mode,env)
  if path:find('runtime/controller.lua',1,true)then
   local snapshot=env.BEC_V2_NODE_SNAPSHOT
   env.BEC_V3_FIXED_BATCH_SNAPSHOT=function()
    local v=snapshot()
    if not barrier then
     barrier=true;releaseNeeded=true
     for _,n in ipairs(cfg.nodes)do c.invoke(n.redstone,'setOutput',n.pauseSide,15)end
    end
    if releaseNeeded then v.phaseReleaseRequired=true;v.state='paused-immediate'end
    return v
   end
  end
  return loader(source,path,mode,env)
 end
 worker=environment(config,index,engine);load=loader;return worker
end
E=factory(cfg,C,Bridge,false)
for tick=1,150 do E.step();s.now=s.now+.1;if releases>=4 then break end end
assert(releases==4 and barrier and not releaseNeeded,table.concat(E.logs,' / '))
assert(not E.tasks[1].fault and outputs['rs1-']==0 and outputs['rs2-']==0)
""")

 def test_missing_stage_demand_refuses_old_tier_fallback(self):
  l=self.world();l.execute('liveSteps[7].nanite=nil')
  with self.assertRaisesRegex(Exception,'追赶阶段蜂群需求不可读'):l.execute('R.production()')

 def test_invalid_lagging_progress_refuses_automatic_release(self):
  l=self.world();l.execute('progress.node1=-1')
  with self.assertRaisesRegex(Exception,'阶段同步进度不可读'):l.execute('R.production()')

if __name__=='__main__':unittest.main()
