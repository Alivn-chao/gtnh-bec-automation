"""Overlap real hive/gate/supply controllers; validate moving conversion totals."""
import unittest
from test_read_optimization import fixture
from simulate_two_recipes import WORLD

def world(overlap=True,delayed=False,io_delay=2):
 l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27;CONTROLLED_INPUT=true")
 if not overlap:l.execute("s.files['/home/bec_v2/lib/preparation.lua']=nil")
 text=WORLD.replace('s.now+2','s.now+'+str(io_delay))
 l.execute(text+r'''
cfg.groups[1].cellFeed={enabled=false,representativeChecks=true}
local environment=Bridge.environment
Bridge.environment=function(config,index,engine)engine.tasks[index].fixedBatch={count=1};return environment(config,index,engine)end
E=factory(cfg,C,Bridge,false);requestCount=0
-- The original serial fixture only scheduled on a false->true write. Model
-- the real enabled entangler also consuming raw that arrives subsequently.
local advance=world.advance
world.advance=function(dt)
 if(world.gen.gen1 or world.gen.gen2)and not world.conversionAt and next(world.sub)then world.conversionAt=s.now+3 end
 advance(dt)
end
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local values=table.pack(invoke(a,m,...))
 if(a=='gen1'or a=='gen2')and m=='setWorkAllowed'and not world.gen.gen1 and not world.gen.gen2 then world.conversionAt=nil end
 return table.unpack(values,1,values.n)
end
function advanceUntil(condition,limit)
 for i=1,limit or 3000 do E.step();world.advance(.05);if condition()then return end end
 error('condition not reached: '..table.concat(E.logs,' / '))
end
''')
 if delayed:l.execute(r'''
world.main['molten.transcendentmetal']=0
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local filter=...
 if a=='main'and m=='getCpus'then return{{busy=false,storage=1000000}}end
 if a=='main'and m=='getCraftables'then
  if filter.name~='molten.transcendentmetal'then return{}end
  return{{getStack=function()return{name=filter.name,size=1,amount=1,hasTag=false,isCraftable=true}end,
   request=function(n)requestCount=requestCount+1;local at=s.now+10;local delivered=false
    return{isCanceled=function()return false end,isDone=function()
     if s.now<at then return false end
     if not delivered then world.main[filter.name]=(world.main[filter.name]or 0)+n;delivered=true end
     return true
    end}
   end}}
 end
 return invoke(a,m,...)
end
''')
 return l

class PreparationTests(unittest.TestCase):
 def test_waits_overlap_and_report_wall_time_without_summing(self):
  l=fixture();l.execute(r'''
local P=loadfile('/home/bec_v2/lib/preparation.lua')();local now=0;local result;local starts={}
local jobs={};for name,d in pairs({nanites=5,gate=2,supply=7})do jobs[#jobs+1]={name=name,run=function()starts[name]=now;coroutine.yield('wait',now+d)end}end
local co=coroutine.create(function()result=P.run(jobs,{now=function()return now end,stopping=function()return false end,abort=function()error('unexpected abort')end,cleanup=function()error('unexpected cleanup')end})end)
while coroutine.status(co)~='dead'do local ok,kind,due=coroutine.resume(co);assert(ok,kind);if due then now=due end end
assert(result.elapsed==7 and result.durations.gate==2 and result.durations.nanites==5 and result.durations.supply==7)
for _,at in pairs(starts)do assert(at==0)end
''')

 def test_sibling_failure_unwinds_started_io_and_skips_unstarted_requests(self):
  l=fixture();l.execute(r'''
local P=loadfile('/home/bec_v2/lib/preparation.lua')();local stop=false;local now=0;local io=0;local submitted=0;local clean=0
local co=coroutine.create(function()P.run({
 {name='nanites',run=function()io=15;local ok=pcall(function()coroutine.yield('wait',1);assert(not stop)end);io=0;assert(ok)end},
 {name='gate',run=function()error('bad gate')end},
 {name='supply',run=function()submitted=submitted+1 end}
},{now=function()return now end,stopping=function()return stop end,abort=function()stop=true end,cleanup=function()clean=clean+1;io=0 end})end)
local failed=false
while coroutine.status(co)~='dead'do local ok,kind,due=coroutine.resume(co);if not ok then failed=true;break end;now=due end
assert(failed and io==0 and clean==1 and submitted==0)
''')

 def test_inventory_brackets_conversion_between_three_getters(self):
  l=fixture();l.execute(r'''
local P=loadfile('/home/bec_v2/lib/preparation.lua')();local map={a='raw.a'};local base={a=100};local secured={['raw.a']=288}
assert(P.balance(base,secured,map,{a=100},{['raw.a']=288},{a=100}))
assert(P.balance(base,secured,map,{a=100},{['raw.a']=144},{a=388}))
assert(P.balance(base,secured,map,{a=388},{},{a=388}))
assert(not P.balance(base,secured,map,{a=100},{['raw.a']=289},{a=100}))
assert(not P.balance(base,secured,map,{a=388},{['raw.a']=1},{a=388}))
assert(not P.balance(base,secured,map,{a=100},{['raw.a']=144},{a=200}))
assert(not P.balance(base,secured,map,{a=99},{['raw.a']=288},{a=100}))
assert(not pcall(P.balance,base,secured,map,{a=100},{['other.raw']=1},{a=100}))
''')

 def test_conversion_starts_during_hive_io_and_continues_while_next_fluid_is_pending(self):
  l=world(delayed=True,io_delay=8);l.execute(r'''
advanceUntil(function()return world.stock.entangled_chromaticglass==288 and requestCount==1 end)
assert(world.main['molten.transcendentmetal']==0 and world.workAllowed==false and world.outputSignal==15)
assert(world.gen.gen1 and not E.tasks[1].fault and E.fluidOwner==1 and E.groupOwner[1]==1)
advanceUntil(function()return #world.outputs>=1 and not E.groupOwner[1]end)
assert(not E.tasks[1].fault,table.concat(E.logs,' / '))
local r=C.read(C.path('state/node-1/production.journal'))
assert(r.stage=='stopped'and r.preparation and r.preparation.earlyConversion)
assert(requestCount==1 and #r.transfers==2 and not r.pending)
assert(next(world.sub)==nil and world.rs.load==0 and world.rs.ret==0)
''')

 def test_stock_hit_never_starts_a_generator_or_moves_raw(self):
  l=world();l.execute(r'''
world.stock={entangled_chromaticglass=288,entangled_transcendentmetal=288}
advanceUntil(function()return #world.outputs>=1 and not E.groupOwner[1]end)
assert(not E.tasks[1].fault,table.concat(E.logs,' / '))
assert((world.calls.transferFluid or 0)==0 and not world.conversionAt)
local r=C.read(C.path('state/node-1/production.journal'));assert(r.preparation and not r.preparation.earlyConversion)
''')

 def test_unknown_transfer_stops_io_and_keeps_pending_without_replay(self):
  l=world(delayed=True,io_delay=20);l.execute(r'''
local c=require('component');local invoke=c.invoke;local moves=0
c.invoke=function(a,m,...)if m=='transferFluid'then moves=moves+1;local ok,n=invoke(a,m,...);if moves==2 then return false,n end;return ok,n end;return invoke(a,m,...)end
advanceUntil(function()return E.tasks[1].fault and not E.tasks[1].co end)
assert(moves==2 and #world.outputs==0 and not world.gen.gen1 and not world.gen.gen2)
assert(world.rs.load==0 and world.rs.ret==0 and world.outputSignal==15 and world.workAllowed==false)
local r=C.read(C.path('state/node-1/production.journal'));assert(r.pending and requestCount==1)
for i=1,100 do E.step();world.advance(.05)end;assert(moves==2 and requestCount==1)
''')

 def test_bad_gate_never_starts_conversion_and_cleans_hive_io(self):
  l=world(io_delay=20);l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if a=='gate'and m=='getCondensateFilters'then return{}end;return invoke(a,m,...)end
advanceUntil(function()return E.tasks[1].fault and not E.tasks[1].co end)
assert(world.rs.load==0 and world.rs.ret==0 and not world.gen.gen1 and not world.gen.gen2 and #world.outputs==0)
assert((world.calls.transferFluid or 0)==0)
''')

 def test_normal_pause_during_preparation_closes_io_and_keeps_ledger(self):
  l=world(delayed=True,io_delay=20);l.execute(r'''
advanceUntil(function()return world.gen.gen1==true end);E.pauseAll()
advanceUntil(function()return not E.tasks[1].co end)
assert(world.rs.load==0 and world.rs.ret==0 and not world.gen.gen1 and not world.gen.gen2)
assert(world.outputSignal==15 and not world.workAllowed and #world.outputs==0)
local r=C.read(C.path('state/node-1/production.journal'));assert(r.supplyLedger and r.configOwned==false)
''')

 def test_confirmed_conversion_checkpoint_resumes_with_credit_and_no_transfer_replay(self):
  l=world();l.execute(r'''
advanceUntil(function()local j=C.read(C.path('state/group-1/nanites-cell.journal'));return world.gen.gen1==true and j and j.stage=='done' end);E.pauseAll()
advanceUntil(function()return not E.tasks[1].co end)
local r=C.read(C.path('state/node-1/production.journal'));assert(r.supplyLedger and not r.pending)
local moved=world.calls.transferFluid;E.resumeNode(1)
advanceUntil(function()return #world.outputs>=1 and not E.groupOwner[1]end)
assert(not E.tasks[1].fault,table.concat(E.logs,' / '))
assert(world.calls.transferFluid==moved and requestCount==0)
''')

 def test_identical_model_reduces_first_release_wait(self):
  results=[]
  for enabled in (False,True):
   l=world(enabled,delayed=True,io_delay=8);l.execute("advanceUntil(function()return world.started end);assert(not E.tasks[1].fault,table.concat(E.logs,' / '))")
   results.append(l.eval('s.now'))
  self.assertLess(results[1],results[0]*.8)
  print('same-model first release, serial vs overlapped:',results)

if __name__=='__main__':unittest.main()
