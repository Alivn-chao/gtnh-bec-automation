"""Read-only base detection; physical 1..6 mapping never retries configuration writes."""
import unittest
from test_read_optimization import fixture

SETUP=r'''
local c=require('component');local invoke=c.invoke
physicalReads={};physicalWrites={};configValues={}
c.invoke=function(a,m,...)
 if a=='new-interface'or a=='old-interface'then
  local slot,detail=...
  if m=='getFluidInterfaceConfiguration'then
   physicalReads[#physicalReads+1]={a=a,slot=slot}
   if failRead then error('network unavailable')end
   local base=a=='new-interface'and 1 or 0
   if slot<base or slot>base+5 then error('index out of bounds')end
   return configValues[slot]
  elseif m=='setFluidInterfaceConfiguration'then
   physicalWrites[#physicalWrites+1]={a=a,slot=slot,detail=detail}
   if failWrite then error('unknown write receipt')end
   configValues[slot]=detail;return not falseWrite
  end
 end
 return invoke(a,m,...)
end
first=C.component(c);second=C.component(c)
'''

class FluidSlotTests(unittest.TestCase):
 def world(self):
  l=fixture();l.execute(SETUP);return l

 def test_new_api_maps_both_boundaries_and_checks_sixth_slot(self):
  l=self.world();l.execute(r'''
configValues[6]={name='unexpected',amount=5}
assert(first.invoke('new-interface','getFluidInterfaceConfiguration',0)==nil)
assert(first.invoke('new-interface','getFluidInterfaceConfiguration',5).amount==5)
assert(physicalReads[#physicalReads].slot==6 and #physicalWrites==0)
local n=#physicalReads;second.invoke('new-interface','getFluidInterfaceConfiguration',0)
assert(#physicalReads==n+1,'base discovery must be shared and cached')
''')

 def test_old_api_preserved_and_base_is_per_address(self):
  l=self.world();l.execute(r'''
first.invoke('old-interface','setFluidInterfaceConfiguration',0,{name='old',amount=1})
assert(physicalWrites[1].slot==0)
first.invoke('new-interface','setFluidInterfaceConfiguration',0,{name='new',amount=2})
assert(physicalWrites[2].slot==1)
second.invoke('old-interface','getFluidInterfaceConfiguration',5)
assert(physicalReads[#physicalReads].slot==5)
''')

 def test_first_setter_discovers_only_by_reads_and_clear_uses_same_slot(self):
  l=self.world();l.execute(r'''
first.invoke('new-interface','setFluidInterfaceConfiguration',0,{name='raw',amount=100})
assert(#physicalWrites==1 and physicalWrites[1].slot==1 and configValues[1].amount==100)
second.invoke('new-interface','setFluidInterfaceConfiguration',0)
assert(#physicalWrites==2 and physicalWrites[2].slot==1 and configValues[1]==nil)
''')

 def test_read_failure_and_invalid_slot_never_write(self):
  l=self.world();l.execute(r'''
failRead=true;local ok,err=pcall(first.invoke,'new-interface','setFluidInterfaceConfiguration',0,{})
assert(not ok and tostring(err):find('network unavailable',1,true)and #physicalWrites==0)
failRead=false
for _,slot in ipairs({-1,6,1.5})do assert(not pcall(first.invoke,'new-interface','setFluidInterfaceConfiguration',slot,{}))end
assert(#physicalWrites==0)
''')

 def test_lost_or_false_write_is_never_reissued(self):
  for flag in ['failWrite','falseWrite']:
   l=self.world();l.execute(flag+r'''=true
local ok,result=pcall(first.invoke,'new-interface','setFluidInterfaceConfiguration',0,{})
assert(#physicalWrites==1 and physicalWrites[1].slot==1)
assert(not ok or result==false)
''')

 def test_actual_controller_checks_one_based_interface_and_keeps_last_slot_guard(self):
  for dirty in [False,True]:
   l=fixture();l.globals().dirtyLast=dirty;l.execute(r'''
local c=require('component');local invoke=c.invoke;lastSlotRead=false
c.invoke=function(a,m,...)
 if a=='main'and(m=='getFluidInterfaceConfiguration'or m=='setFluidInterfaceConfiguration')then
  local args=table.pack(...);local slot=args[1]
  if slot<1 or slot>6 then error('index out of bounds')end
  if slot==6 then lastSlotRead=true;if dirtyLast then return{name='unexpected',amount=1}end end
  args[1]=slot-1;return invoke(a,m,table.unpack(args,1,args.n))
 end
 return invoke(a,m,...)
end
E=factory(cfg,C,Bridge,false)
for tick=1,300 do E.step();s.now=s.now+.1 end
assert(lastSlotRead)
if dirtyLast then assert(E.tasks[1].fault and releaseCount==0)
else assert(not E.tasks[1].fault and releaseCount==2,table.concat(E.logs,' / '))end
''')

if __name__=='__main__':unittest.main()
