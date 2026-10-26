"""Real cache worker with asynchronous, capacity-limited AE jobs."""
from pathlib import Path
import subprocess
import unittest
from test_cache_management import setup

ROOT=Path(__file__).resolve().parents[2]
WORLD=r'''
jobs={};requestCount=0;nodeReads=0;cpuReads=0;planningDelay=0;slots=3
durations={['molten.chromaticglass']=8,['molten.infinity']=3,['molten.transcendentmetal']=5}
for raw in pairs(durations)do world.main[raw]=0 end
local c=require('component');local invoke=c.invoke
local function refresh()
 for _,j in ipairs(jobs)do if not j.failed and not j.canceled and s.now>=j.doneAt and not j.delivered then
  j.delivered=true;world.main[j.raw]=(world.main[j.raw]or 0)+j.amount
 end end
end
c.invoke=function(a,m,...)
 if a:match('^node%d+$')or a:match('^rs%d+%-')then nodeReads=nodeReads+1 end
 if a:match('^node%d+$')then a='node1'end
 if a:match('^rs%d+%-')then a='rs1-'end
 if a=='main'then
  refresh()
  if m=='getCpus'then
   cpuReads=cpuReads+1;local busy=0
   for _,j in ipairs(jobs)do if not j.failed and not j.delivered and not j.canceled and s.now>=j.planAt then busy=busy+1 end end
   local rows={};for i=1,slots do rows[i]={busy=i<=busy,storage=1000000,cpu={activeItems=function()return{}end,pendingItems=function()return{}end}}end
   return rows
  end
  if m=='getCraftables'then local filter=...;if not durations[filter.name]then return{}end;local raw=filter.name
   return{{getStack=function()return{name=raw,amount=1,size=1,hasTag=false,isCraftable=true}end,
    request=function(amount)
     requestCount=requestCount+1
     local j={raw=raw,amount=amount,at=s.now,planAt=s.now+planningDelay,doneAt=s.now+planningDelay+durations[raw],failed=raw==rejectRaw};jobs[#jobs+1]=j
     if unknownReceipt then return nil,'lost reply'end
     return{isComputing=function()return s.now<j.planAt end,hasFailed=function()return j.failed,'missing inputs'end,
      isCanceled=function()return j.canceled==true end,isDone=function()refresh();return j.delivered==true end}
    end}}
  end
 end
 return invoke(a,m,...)
end
change('save','default','1000');change('enable')
function runUntilRequests(n)
 for i=1,1000 do K.step(E,true);world.advance(.05);if requestCount>=n or K.blocked then break end end
end
'''

def world(old=False,nodes=1):
 l=setup()
 if old:
  for name in ['lib/cache.lua','runtime/cache.lua']:
   l.globals().s.files['/home/bec_v2/'+name]=subprocess.check_output(['git','show','b88c59f:reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')
  l.execute("factoryCache=loadfile('/home/bec_v2/lib/cache.lua')();K=factoryCache(C,B,cfg,disk)")
 l.execute(WORLD)
 if nodes>1:
  l.execute("for i=2,"+str(nodes)+" do cfg.nodes[i]={name='N'..i,address='node'..i,redstone='rs'..i..'-',pauseSide=1,group=1};E.tasks[i]={}end;E.nodeWork=function(i,on)require('component').invoke(cfg.nodes[i].address,'setWorkAllowed',on)end;C.write(C.path('config.dat'),cfg)")
 return l

class ParallelCacheTests(unittest.TestCase):
 def test_all_fluids_submit_before_first_completion_and_finish_exactly_once(self):
  l=world();l.execute(r'''
runUntilRequests(3);assert(requestCount==3)
local pending=C.read(C.path('state/group-1/cache.journal'))
for _,v in ipairs(pending.plan)do assert(not v.craft and not v.status and not v.job,'live AE handles leaked into journal')end
for _,j in ipairs(jobs)do assert(j.at<jobs[1].doneAt)end
steps(700);assert(not K.busy and not K.blocked,K.message)
assert(requestCount==3 and next(world.sub)==nil)
for k in pairs(durations)do assert(world.main[k]==0)end
for _,k in ipairs({'entangled_chromaticglass','entangled_infinity','entangled_transcendentmetal'})do assert(world.stock[k]==1008)end
local r=C.read(C.path('state/group-1/cache.journal'));assert(r.stage=='stopped'and not r.pending)
for _,j in ipairs(r.requests)do assert(j.state=='done')end
''')

 def test_a_slow_first_fluid_does_not_hold_back_arrived_fluids(self):
  l=world();l.execute(r'''
runUntilRequests(3);for i=1,80 do K.step(E,true);world.advance(.05)end
assert(world.sub['molten.infinity']==1008 and not world.sub['molten.chromaticglass'])
steps(600);assert(not K.busy and requestCount==3)
''')

 def test_planning_jobs_reserve_slots_before_ae_reports_cpus_busy(self):
  for count in (1,2):
   l=world();l.execute(f'slots={count};planningDelay=3;runUntilRequests({count});steps(20);assert(requestCount=={count})')
   l.execute('steps(1000);assert(requestCount==3 and not K.busy and not K.blocked,K.message)')

 def test_a_rejected_plan_does_not_block_other_fluids_or_auto_repeat(self):
  l=world();l.execute(r'''
rejectRaw='molten.chromaticglass';runUntilRequests(3);steps(350)
assert(not K.blocked and K.busy and requestCount==3)
assert(world.sub['molten.infinity']==1008 and world.sub['molten.transcendentmetal']==1008)
world.main[rejectRaw]=1008;steps(400);assert(not K.busy and requestCount==3)
local r=C.read(C.path('state/group-1/cache.journal'));assert(r.requests[1].state=='rejected'and r.requests[1].preSubmissionFailed)
''')

 def test_unknown_request_receipt_is_not_replayed_or_followed_by_more_requests(self):
  l=world();l.execute(r'''
unknownReceipt=true;runUntilRequests(3);assert(K.blocked and requestCount==1)
local r=C.read(C.path('state/group-1/cache.journal'));assert(r.requests[1].state=='pending')
K=factoryCache(C,B,cfg,disk);assert(not pcall(K.assertReady));assert(requestCount==1)
''')

 def test_canceling_a_submitted_job_preserves_all_requests(self):
  l=world();l.execute(r'''
runUntilRequests(3);jobs[1].canceled=true
for i=1,100 do K.step(E,true);world.advance(.05);if K.blocked then break end end
assert(K.blocked and requestCount==3)
local r=C.read(C.path('state/group-1/cache.journal'));assert(#r.requests==3 and r.requests[1].state=='submitted')
assert(not world.gen.gen1 and not world.gen.gen2)
''')

 def test_arriving_inputs_stop_new_submissions_and_drain_existing_jobs(self):
  l=world();l.execute(r'''
runUntilRequests(3);local before=requestCount;E.hasPendingFeed=function()return true end
steps(700);assert(not K.busy and not K.blocked and requestCount==before,K.message)
assert(not E.fluidOwner and not E.groupOwner[1]and next(world.sub)==nil)
local r=C.read(C.path('state/group-1/cache.journal'));assert(r.yieldedToRecipe and r.stage=='stopped')
for _,j in ipairs(r.requests)do assert(j.state=='done')end
''')

 def test_missing_optional_module_keeps_the_old_sequential_worker_working(self):
  l=world();l.execute("s.files['/home/bec_v2/lib/cache_pipeline.lua']=nil;steps(1000);assert(requestCount==3 and not K.busy and not K.blocked,K.message)")

 def test_changed_pause_is_rejected_before_any_request(self):
  l=world();l.execute(r'''
local c=require('component');local invoke=c.invoke;local count=0
c.invoke=function(a,m,...)
 local filter=...
 if a=='main'and m=='getCraftables'and filter.name=='molten.chromaticglass'then count=count+1;if count==2 then world.outputSignal=0 end end
 return invoke(a,m,...)
end
for i=1,300 do K.step(E,true);world.advance(.05);if K.blocked then break end end
assert(K.blocked and requestCount==0)
''')

 def test_parallel_wave_reduces_wait_time_and_group_reads_in_same_world(self):
  results=[]
  for old in (True,False):
   l=world(old,16);l.execute('steps(1200);assert(requestCount==3 and not K.busy and not K.blocked,K.message)')
   duration=max(l.eval(f'jobs[{i}].doneAt')for i in range(1,4))-l.eval('jobs[1].at')
   results.append({'sequential':old,'ae_span':duration,'node_reads':l.eval('nodeReads'),'cpu_reads':l.eval('cpuReads')})
  self.assertLess(results[1]['ae_span'],results[0]['ae_span']*.8)
  self.assertLess(results[1]['node_reads'],results[0]['node_reads']*.7)
  print('cache 3-fluid/16-node simulation:',results)

if __name__=='__main__':unittest.main()
