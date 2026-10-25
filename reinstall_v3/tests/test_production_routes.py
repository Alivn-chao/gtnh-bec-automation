import unittest
from pathlib import Path
from test_read_optimization import fixture
from simulate_two_recipes import WORLD
from test_cache_management import AE

ROOT=Path(__file__).resolve().parents[2]
SOURCE=(ROOT/'reinstall_v2/files/runtime/controller.lua').read_text(encoding='utf-8')
HELPERS=SOURCE[SOURCE.index('local discovery,saveDiscovery'):SOURCE.index('local function prepareStreaming')]

def world():
 l=fixture();l.execute(r'''
cfg.groups[1].bulkTransposers={};mapping={};from={};empty={};fluid={};scans,calls=0,0
for i=1,10 do local a='port'..i;cfg.groups[1].bulkTransposers[i]=a;mapping['cond'..i]='raw'..i;from[a]=0 end
C.write(C.path('config.dat'),cfg);TRANS='normal'
function integer(v)assert(type(v)=='number'and v>=0 and v%1==0);return v end
c={list=function()scans=scans+1;local i=0;return function()i=i+1;if i<=10 then return 'port'..i,'transposer'end end end}
function call(a,m,side,slot)
 calls=calls+1;assert(from[a]~=nil,'unbound route invoked')
 if m=='getTankCount'then return side==from[a]and 1 or side==1 and 6 or 0 end
 if m=='getTankCapacity'then return side==from[a]and 2147483647 or 16000 end
 if m=='getFluidInTank'then
  if side~=from[a]or empty[a]then return{amount=0}end
  return{name=fluid[a]or 'raw'..a:match('%d+'),amount=1000}
 end;error(m)
end
BEC_V3_PRODUCTION_DISCOVERY=function()return loadfile(C.path('lib/fluid_discovery.lua'))()(C,cfg,1)end
''');return l

def helpers(l):return l.execute(HELPERS+'\nreturn {ports=bulkPorts,verify=verifyBulk}')
def wanted(l):return l.table_from({'cond1':True})

class ProductionRouteTests(unittest.TestCase):
 def test_restart_uses_background_compatible_routes_and_probes_only_needed_port(self):
  l=world();r=helpers(l);r.ports(wanted(l));self.assertEqual(l.globals().calls,90)
  l.execute('calls=0;from.port2=4');r=helpers(l);routes=r.ports(wanted(l))
  self.assertEqual(l.globals().scans,1);self.assertEqual(l.globals().calls,5)
  self.assertEqual(routes.raw1.address,'port1')

 def test_wrong_binding_or_unbound_saved_route_forces_discovery(self):
  for mutation in ("v.binding='other'","v.ports.raw1.address='unbound'"):
   l=world();helpers(l).ports(wanted(l));l.execute("local p=C.path('state/group-1/cache-discovery.dat');local v=C.read(p);"+mutation+";C.write(p,v)")
   routes=helpers(l).ports(wanted(l));self.assertEqual(l.globals().scans,2);self.assertEqual(routes.raw1.address,'port1')

 def test_changed_side_is_rediscovered(self):
  l=world();helpers(l).ports(wanted(l));l.execute('from.port1=4')
  routes=helpers(l).ports(wanted(l));self.assertEqual(l.globals().scans,2);self.assertEqual(routes.raw1['from'],4)

 def test_empty_known_source_keeps_route_but_cannot_transfer_as_full(self):
  l=world();helpers(l).ports(wanted(l));l.execute('empty.port1=true;calls=0')
  r=helpers(l);route=r.ports(wanted(l)).raw1
  self.assertEqual(l.globals().scans,1);self.assertEqual(l.globals().calls,5)
  r.verify(route,'raw1',True)
  with self.assertRaises(Exception):r.verify(route,'raw1')

 def test_wrong_fluid_is_not_used_as_the_cached_source(self):
  l=world();helpers(l).ports(wanted(l));l.execute("fluid.port1='unrelated'")
  routes=helpers(l).ports(wanted(l));self.assertIsNone(routes.raw1);self.assertEqual(l.globals().scans,2)

 def test_saved_alias_cannot_redirect_to_unrelated_fluid(self):
  l=world();helpers(l).ports(wanted(l));l.execute("local p=C.path('state/group-1/cache-discovery.dat');local v=C.read(p);v.rawNames.cond1='raw2';C.write(p,v)")
  routes=helpers(l).ports(wanted(l));self.assertEqual(routes.raw1.address,'port1');self.assertEqual(l.globals().mapping.cond1,'raw1')

 def test_actual_two_recipe_production_reuses_routes_across_workers(self):
  for missing in (False,True):
   l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27;BULK_COUNT=10");l.execute(WORLD)
   l.execute("C.write(C.path('config.dat'),cfg)")
   if missing:l.execute("s.files[C.path('lib/fluid_discovery.lua')]=nil")
   l.execute(r'''
local c=require('component');local list=c.list;scans=0
c.list=function(kind,...)if kind=='transposer'then scans=scans+1 end;return list(kind,...)end
for i=1,2000 do E.step();world.advance(.05);assert(not E.tasks[1].fault,table.concat(E.logs,' / '));if #world.outputs==2 then break end end
assert(#world.outputs==2 and world.outputs[1].item~=world.outputs[2].item,table.concat(E.logs,' / '))
''')
   self.assertEqual(l.globals().scans,2 if missing else 1)

 def test_known_empty_production_route_can_request_then_transfer_exact_fluid(self):
  l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27;BULK_COUNT=10");l.execute(WORLD)
  l.execute(r'''
C.write(C.path('config.dat'),cfg)
C.write(C.path('state/group-1/cache-discovery.dat'),{version=1,binding=s.files[C.path('config.dat')],ports={
 ['molten.chromaticglass']={address='bulk1',from=4,to=5},['molten.transcendentmetal']={address='bulk2',from=4,to=5}},
 rawNames={entangled_chromaticglass='molten.chromaticglass',entangled_transcendentmetal='molten.transcendentmetal'}})
'''+AE.split("change('save'",1)[0]+r'''
cpuBusy=false;bulkMoves=0
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local side=...
 if a=='bulk1'and m=='getFluidInTank'and side==4 and world.main['molten.chromaticglass']==0 then return{amount=0}end
 if a=='bulk1'and m=='transferFluid'then bulkMoves=bulkMoves+1 end
 return invoke(a,m,...)
end
for i=1,2000 do E.step();world.advance(.05);assert(not E.tasks[1].fault,table.concat(E.logs,' / '));if #world.outputs>=1 then break end end
assert(#world.outputs>=1 and requests==1 and bulkMoves==1,table.concat(E.logs,' / '))
''')

if __name__=='__main__':unittest.main()
