"""Large total counts retain physical parallel; only API calls are segmented."""
from pathlib import Path
import subprocess
import unittest
from test_read_optimization import fixture
from simulate_two_recipes import WORLD
ROOT=Path(__file__).resolve().parents[2]

COHORT=r'''
cfg.nodes={};nodes={};outputs={};configure(16)
local selected={6,7,8,9,10,11,13,14,16};local enabled={};for _,i in ipairs(selected)do enabled[i]=true end
per={entangled_bedrockium=2359296,entangled_celestialtungsten=294912,entangled_hypogen=576,entangled_neutronium=294912}
s.stock={}
local entries={}
for i=1,16 do local n=nodes['node'..i];n.workAllowed=false
 if enabled[i]then
  n.parallel=i==6 and 182 or 256;n.required={};n.consumed={};n.duration=.5
  for kind,v in pairs(per)do n.required[kind]=v*n.parallel;s.stock[kind]=(s.stock[kind]or 0)+v*n.parallel end
  entries[i]={required=n.required,consumed={},parallel=n.parallel,tier=4}
 else n.done=true end
end
local fs=require('filesystem');local exists,list=fs.exists,fs.list
fs.exists=function(p)return p==cfg.recipeDirectory or exists(p)end
fs.list=function(p)if p==cfg.recipeDirectory then local once=false;return function()if not once then once=true;return 'large.dat'end end end;return list(p)end
local fluids={};for kind,v in pairs(per)do fluids[#fluids+1]={name=kind,amount=v}end
C.write(cfg.recipeDirectory..'/large.dat',{state='converted',condensates=fluids,outputs={{name='test:large',size=1}}})
original={version=2,stage='interrupted',leader=6,members=selected,entries=entries,normalized=per}
function runAll()
 for tick=1,400 do E.step();s.now=s.now+.1;if E.tasks[6].fault or releaseCount==9 and not E.groupOwner[1]then break end end
end
'''
SUPPLY=r'''
world.recipes[1].required={entangled_chromaticglass=5261230080,entangled_transcendentmetal=144}
world.main['molten.chromaticglass']=0
local r={state='converted',condensates={{name='entangled_chromaticglass',amount=5261230080},{name='entangled_transcendentmetal',amount=144}},outputs={{name='test:large',size=1}}}
C.write(cfg.recipeDirectory..'/a.dat',r)
requests={};transfers={};local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local args={...}
 if m=='getFieldStrength'or m=='setFieldStrength'then error('operator handles field strength')end
 if a=='main'and m=='getCpus'then return {{busy=false}}end
 if a=='main'and m=='getCraftables'and args[1].name=='molten.chromaticglass'then
  return {{getStack=function()return {name='molten.chromaticglass',amount=1,size=1,isCraftable=true,hasTag=false}end,
   request=function(amount)
    assert(amount<=2147483647 and amount%144==0);requests[#requests+1]=amount
    local delivered=false;local at=s.now+.5
    return {isCanceled=function()return false end,isDone=function()
     if s.now<at then return false end
     if not delivered then world.main['molten.chromaticglass']=world.main['molten.chromaticglass']+amount;delivered=true end
     return true
    end}
   end}}
 end
 if m=='transferFluid'then assert(args[3]<=2147483647);transfers[#transfers+1]=args[3]end
 return invoke(a,m,...)
end
'''

CONVERTING=r'''
local total={};for _,i in ipairs(original.members)do
 for name,n in pairs(nodes['node'..i].required)do total[name]=(total[name]or 0)+n end
end
C.write(C.path('state/group-1/cohort.dat'),original)
path=C.path('state/node-6/production.journal')
saved={version=1,kind='continuous',stage='converting',required=total,remaining=total,target=total,
 batchCount=2230,expected={},transfers={},requests={},configOwned=false}
s.stock.entangled_hypogen=4163184
'''

class LargeBatchTests(unittest.TestCase):
 def cohort(self,old=False):
  l=fixture()
  if old:l.globals().s.files['/home/bec_v2/runtime/controller.lua']=subprocess.check_output(['git','show','bf1ae6f:reinstall_v2/files/runtime/controller.lua'],cwd=ROOT).decode()
  l.execute(COHORT);return l
 def test_old_controller_reproduces_exact_5261230080_limit(self):
  l=self.cohort(True);l.execute("E=factory(cfg,C,Bridge,false);runAll();assert(E.tasks[6].fault and releaseCount==0);assert(table.concat(E.logs,' / '):find('整批需求过大',1,true))")
 def test_all_nine_nodes_release_together_with_original_parallel(self):
  l=self.cohort();l.execute("E=factory(cfg,C,Bridge,false);runAll();assert(releaseCount==9,table.concat(E.logs,' / '));assert(not E.tasks[6].fault);assert(#E.tasks[6].members==9);for _,at in ipairs(releaseTimes)do assert(at==releaseTimes[1])end;assert(nodes.node6.parallel==182 and nodes.node7.parallel==256)")
 def test_existing_interrupted_cohort_resumes_without_repartition(self):
  l=self.cohort();l.execute("C.write(C.path('state/group-1/cohort.dat'),original);C.write(C.path('state/node-6/production.journal'),{version=1,kind='continuous',stage='starting',transfers={},requests={},configOwned=false});E=factory(cfg,C,Bridge,false);E.resumeNode(6);runAll();assert(releaseCount==9 and not E.tasks[6].fault);assert(#C.read(C.path('state/group-1/cohort.dat')).members==9)")
 def test_large_raw_request_and_transfer_chunks_sum_exactly(self):
  l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27;"+WORLD+SUPPLY+r'''
for tick=1,3000 do E.step();world.advance(.05);if E.tasks[1].fault or #world.outputs>0 then break end end
assert(not E.tasks[1].fault,table.concat(E.logs,' / '));assert(#world.outputs==1)
assert(#requests==3 and requests[1]==2147483520 and requests[2]==2147483520 and requests[3]==966263040)
local total=0;for _,n in ipairs(requests)do total=total+n end;assert(total==5261230080)
assert(next(world.sub)==nil and world.stock.entangled_chromaticglass==0)
''')
 def test_unconfirmed_prior_request_remains_blocked_without_replay(self):
  l=self.cohort();l.execute("C.write(C.path('state/group-1/cohort.dat'),original);C.write(C.path('state/node-6/production.journal'),{version=1,kind='continuous',stage='starting',transfers={},requests={{state='submitted',raw='molten.bedrockium',amount=100}},configOwned=false});local before=s.files[C.path('state/node-6/production.journal')];E=factory(cfg,C,Bridge,false);E.resumeNode(6);runAll();assert(E.tasks[6].fault and releaseCount==0);assert(before==s.files[C.path('state/node-6/production.journal')])")
 def test_unknown_second_chunk_receipt_is_not_reissued_on_resume(self):
  l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27;"+WORLD+SUPPLY+r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if not(a=='main'and m=='getCraftables')then return invoke(a,m,...)end
 local result=invoke(a,m,...)
 if result[1]then
  local request=result[1].request
  result[1].request=function(amount)
   if #requests==1 then requests[#requests+1]=amount;return nil,'unconfirmed response'end
   return request(amount)
  end
 end
 return result
end
for tick=1,2000 do E.step();world.advance(.05);if E.tasks[1].fault then break end end
assert(E.tasks[1].fault and #requests==2)
local path=C.path('state/node-1/production.journal');local before=s.files[path]
local r=C.read(path);assert(r.requests[#r.requests].state=='pending')
E=factory(cfg,C,Bridge,false);E.resumeNode(1)
for tick=1,50 do E.step();world.advance(.05);if E.tasks[1].fault then break end end
assert(E.tasks[1].fault and #requests==2 and s.files[path]==before)
''')
 def test_quantities_above_lua_exact_integer_limit_are_rejected(self):
  l=self.cohort();l.execute("s.stock.entangled_bedrockium=9007199254740992;E=factory(cfg,C,Bridge,false);runAll();assert(E.tasks[6].fault and releaseCount==0);assert(table.concat(E.logs,' / '):find('精确整数范围',1,true))")

 def test_old_recovery_rejects_real_hypogen_surplus(self):
  l=self.cohort();l.globals().s.files['/home/bec_v2/runtime/controller.lua']=subprocess.check_output(['git','show','3ed7e69:reinstall_v2/files/runtime/controller.lua'],cwd=ROOT).decode()
  l.execute(CONVERTING+"C.write(path,saved);E=factory(cfg,C,Bridge,false);E.resumeNode(6);runAll();assert(E.tasks[6].fault and releaseCount==0);assert(table.concat(E.logs,' / '):find('转换恢复库存不符: molten.hypogen',1,true))")

 def test_converted_surplus_resumes_nine_nodes_without_supply(self):
  l=self.cohort();l.execute(CONVERTING+"C.write(path,saved);E=factory(cfg,C,Bridge,false);E.resumeNode(6);runAll();assert(not E.tasks[6].fault,table.concat(E.logs,' / '));assert(releaseCount==9);local r=C.read(path);assert(#r.transfers==0 and #r.requests==0);assert(table.concat(E.logs,' / '):find('保留多余库存 2878704',1,true))")

 def test_surplus_does_not_bypass_unconfirmed_requests_or_moves(self):
  for change in ["saved.pending={raw='molten.hypogen',amount=144}","saved.requests={{raw='molten.hypogen',amount=144,state='submitted'}}","saved.transfers={{raw='molten.hypogen',amount=144,ok=false}}"]:
   l=self.cohort();l.execute(CONVERTING+change+";C.write(path,saved);local before=s.files[path];E=factory(cfg,C,Bridge,false);E.resumeNode(6);runAll();assert(E.tasks[6].fault and releaseCount==0);assert(s.files[path]==before)")

 def test_recovery_shortage_and_misaligned_surplus_remain_blocked(self):
  for amount in [1284336,4163185]:
   l=self.cohort();l.execute(CONVERTING+"s.stock.entangled_hypogen="+str(amount)+";C.write(path,saved);local before=s.files[path];E=factory(cfg,C,Bridge,false);E.resumeNode(6);runAll();assert(E.tasks[6].fault and releaseCount==0);assert(s.files[path]==before)")

 def test_surplus_with_residual_raw_fluid_still_blocks(self):
  l=self.cohort();l.execute(CONVERTING+r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if a=='sub'and m=='getFluidsInNetwork'then return {{name='molten.hypogen',amount=144}}end
 return invoke(a,m,...)
end
C.write(path,saved);local before=s.files[path];E=factory(cfg,C,Bridge,false);E.resumeNode(6);runAll()
assert(E.tasks[6].fault and releaseCount==0);assert(s.files[path]==before)
''')

if __name__=='__main__':unittest.main()
