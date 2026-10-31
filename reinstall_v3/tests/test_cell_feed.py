"""Frozen-cell batch scheduling, simulated callbacks; hardware checked separately."""
import unittest
from test_read_optimization import fixture

SETUP=r'''
configure(16)
local c=require('component');local fs=require('filesystem');local original=c.invoke
for _,n in pairs(nodes)do n.done=true;n.workAllowed=false;n.min=1;n.max=256 end
local settings={enabled=true,transposer='items',sourceSide=4,productionSide=5,sourceSlot=1,productionSlot=1,collectSeconds=10}
cfg.groups[1].cellFeed=settings
local recipe={state='converted',ordinaryInputs={{name='iron',size=8},{name='board',size=2}},condensates={{name='entangled_chromaticglass',amount=288}},outputs={{name='product',size=1}}}
C=loadfile('/home/bec_v2/lib/config.lua')()
C.write(cfg.recipeDirectory..'/a.dat',recipe)
fs.list=function(path)local done=false;return function()if not done then done=true;return 'a.dat'end end end
M=loadfile('/home/bec_v2/lib/cell_feed.lua')()
function makeDisk(count)return {name='cell',size=1,storedItemCount=count*10,getAvailableItems=count>0 and {{name='iron',size=count*8},{name='board',size=count*2}}or {}}end
disk={[4]=makeDisk(1000)};moves=0;readsAfterCapture=0;admitted=0
c.invoke=function(a,m,...)
 local args={...}
 if a=='items'then
  if m=='getInventoryName'then return 'tile.appliedenergistics2.BlockDrive'end
  if m=='getInventorySize'then return 10 end
  if m=='getStackInSlot'then if args[2]~=1 then return nil end;if args[1]==5 and disk[5]then readsAfterCapture=readsAfterCapture+1 end;return disk[args[1]]end
  if m=='transferItem'then
   moves=moves+1;assert(args[3]==1 and args[4]==1 and args[5]==1)
   if moveFailure then return 0 end
   if addAtCapture and args[1]==4 then disk[4]=makeDisk(1008)end
   disk[args[2]]=disk[args[1]];disk[args[1]]=nil;return 1
  end
 end
 local n=nodes[a]
 if n then
  if m=='getMinParallel'then return n.min end
  if m=='getMaxParallel'then return n.max end
  if m=='setMinParallel'then n.min=args[1];return end
  if m=='setMaxParallel'then n.max=args[1];return end
  if m=='setWorkAllowed'and args[1]then
   admitted=admitted+1;n.done=false;n.parallel=n.min;n.required={entangled_chromaticglass=288*n.min};n.consumed={}
   disk[5]=makeDisk(disk[5].storedItemCount/10-n.min)
  end
 end
 return original(a,m,...)
end
E={tasks={},log=function()end}
for i=1,16 do E.tasks[i]={}end
E.nodeWork=function(i,on)c.invoke(cfg.nodes[i].address,'setWorkAllowed',on)end
F=M.new(cfg,1,C,E)
'''

class CellFeedTests(unittest.TestCase):
 def world(self,concurrent=True):
  l=fixture();l.execute(SETUP)
  if not concurrent:l.execute('cfg.groups[1].cellFeed.concurrentAdmission=false')
  return l

 def test_balanced_1000_and_small_batches(self):
  l=self.world();l.execute(r'''
local limits={};for i=1,16 do limits[i]={index=i,max=256}end
local q=M.allocate(1000,limits);local total,n62,n63=0,0,0
for _,n in pairs(q)do total=total+n;if n==62 then n62=n62+1 elseif n==63 then n63=n63+1 end end
assert(total==1000 and n62==8 and n63==8)
q=M.allocate(3,limits);local used=0;for _,n in pairs(q)do if n>0 then assert(n==1);used=used+1 end end;assert(used==3)
assert(not pcall(M.allocate,4097,limits))
local q=M.allocate(10,{{index=1,max=1},{index=2,max=9}});assert(q[1]==1 and q[2]==9)
''')

 def test_capture_then_count_full_distribution_and_restore(self):
  l=self.world();l.execute(r'''
assert(not F.step());assert(moves==0)
s.now=9;assert(not F.step());assert(moves==0)
addAtCapture=true;s.now=10;assert(not F.step());assert(moves==1 and readsAfterCapture>0)
assert(F.plan().count==1008)
for tick=1,100 do s.now=s.now+.2;if F.step()then break end end
assert(F.ready and admitted==16 and moves==2 and disk[4].storedItemCount==0)
for _,n in pairs(nodes)do assert(n.workAllowed==false and(n.parallel==63));n.done=true end
F.finish();assert(C.read(C.path('state/group-1/cell-feed.journal')).stage=='stopped')
for _,n in pairs(nodes)do assert(n.min==1 and n.max==256)end
''')

 def test_signal_does_not_reset_timer_and_group_busy_prevents_move(self):
  l=self.world();l.execute(r'''
F.observe();local first=F.since;s.now=5;disk[4]=makeDisk(2000);F.observe();assert(F.since==first)
nodes.node1.done=false;s.now=10
assert(not F.step());assert(moves==0)
''')

 def test_uncertain_move_never_replayed_and_restart_refuses(self):
  l=self.world();l.execute(r'''
F.step();s.now=10;moveFailure=true;assert(not pcall(F.step));assert(moves==1)
moveFailure=false;assert(not pcall(F.step));assert(moves==1)
assert(not pcall(M.new,cfg,1,C,E));assert(moves==1 and admitted==0)
''')

 def test_unknown_mixed_or_ambiguous_recipe_keeps_nodes_closed(self):
  for case in ('mixed','partial','ambiguous'):
   with self.subTest(case=case):
    l=self.world();l.globals().case=case;l.execute(r'''
if case=='mixed'then disk[4].getAvailableItems[3]={name='other',size=1};disk[4].storedItemCount=disk[4].storedItemCount+1
elseif case=='partial'then disk[4].getAvailableItems[2].size=1999;disk[4].storedItemCount=9999
else
 local r={items={['iron:0']=8,['board:0']=2}}
 assert(not pcall(M.match,{['iron:0']=8,['board:0']=2},{r,r}));return
end
F.step();s.now=10;assert(not pcall(F.step));assert(admitted==0 and moves==1)
for _,n in pairs(nodes)do assert(n.workAllowed==false)end
''')

 def test_interrupted_production_prevents_new_capture(self):
  l=self.world();l.execute(r'''
C.write(C.path('state/group-1/cohort.dat'),{stage='working'})
assert(not pcall(M.new,cfg,1,C,E));assert(moves==0)
''')

 def test_pause_before_capture_or_admission_blocks_work(self):
  l=self.world();l.execute(r'''
F.step();s.now=10;E.tasks[2].disabled=true
assert(not pcall(F.step));assert(moves==0 and admitted==0)
''')

 def test_engine_waits_for_every_quota_before_starting_worker(self):
  l=self.world();l.execute(r'''
local started=0
local bridge={environment=function(config,index,engine)
 return function()
  started=started+1;assert(admitted==16 and #engine.tasks[index].members==16)
  for _,i in ipairs(engine.tasks[index].members)do
   local n=nodes['node'..i];assert(not n.workAllowed);n.done=true;n.consumed=n.required
  end
 end
end}
E=factory(cfg,C,bridge,false)
E.step();s.now=9;E.step();assert(started==0 and moves==0)
for tick=1,100 do s.now=10+tick*.2;E.step();if started>0 then break end end
assert(started==1 and admitted==16 and moves==2)
assert(C.read(C.path('state/group-1/cohort.dat')).stage=='stopped')
assert(C.read(C.path('state/group-1/cell-feed.journal')).stage=='stopped')
for _,n in pairs(nodes)do assert(n.workAllowed==false and n.max==256)end
''')

 def test_transient_crafting_during_admission_waits_for_pause(self):
  l=self.world(False);l.execute(r'''
F.step();s.now=10;F.step();assert(admitted==1)
local c=require('component');local old=c.invoke;local once=true
c.invoke=function(a,m,...)if a=='node1'and m=='getState'and once then once=false;return 'crafting'end;return old(a,m,...)end
assert(not F.step());assert(admitted==1 and nodes.node1.workAllowed==false)
assert(not F.step());assert(F.plan().cursor==2 and admitted==1)
''')

 def test_explicit_confirmed_admission_resume_does_not_replay_first_node(self):
  l=self.world(False);l.execute(r'''
F.step();s.now=10;F.step();assert(admitted==1 and moves==1)
E.nodeWork(1,false)
local next=M.new(cfg,1,C,E,true)
assert(not next.step());assert(admitted==1 and moves==1 and next.plan().cursor==2)
for tick=1,100 do if next.step()then break end end
assert(next.ready and admitted==16 and moves==2)
''')

 def test_admission_resume_rejects_consumption_or_wrong_remaining_stock(self):
  for bad in ('consumption','remaining'):
   l=self.world(False);l.globals().bad=bad;l.execute(r'''
F.step();s.now=10;F.step();E.nodeWork(1,false)
if bad=='consumption'then nodes.node1.consumed={entangled_chromaticglass=1}else disk[5]=makeDisk(999)end
assert(not pcall(M.new,cfg,1,C,E,true));assert(admitted==1 and moves==1)
''')

 def test_cache_does_not_claim_group_when_cell_has_waiting_material(self):
  from test_cache_management import setup
  l=setup();l.execute(r'''
E.hasPendingFeed=function(group)return group==1 end
change('enable');steps(200)
assert(not K.busy and not world.calls.transferFluid)
''')

 def test_cache_finishes_submitted_request_then_yields_to_cell(self):
  from test_cache_management import setup, AE
  l=setup();l.execute(AE+r'''
cpuBusy=false
for tick=1,200 do K.step(E,true);world.advance(.05);if requests==1 then break end end
assert(requests==1)
E.hasPendingFeed=function()return true end
steps(1000)
assert(requests==1 and not K.busy)
local j=C.read(C.path('state/group-1/cache.journal'));assert(j.stage=='stopped'and not j.pending and not j.plan)
''')

if __name__=='__main__':unittest.main()
