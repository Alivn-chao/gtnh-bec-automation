import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests')]
from test_cache_management import setup,AE
COUNT=r'''
recipeReads,bulkScans,craftReads=0,0,0
local open=io.open;io.open=function(p,m)if m=='r'and p:find(cfg.recipeDirectory..'/',1,true)==1 then recipeReads=recipeReads+1 end;return open(p,m)end
local c=require('component');local list,invoke=c.list,c.invoke
c.list=function(kind,...)if kind=='transposer'then bulkScans=bulkScans+1 end;return list(kind,...)end
c.invoke=function(a,m,...)if m=='getCraftables'then craftReads=craftReads+1 end;return invoke(a,m,...)end
change('save','default','1000');change('enable');steps(400)
assert(not K.busy and not K.blocked,K.message)
'''
class DiscoveryTests(unittest.TestCase):
 def warm(self):
  l=setup();l.execute(COUNT);return l
 def test_multiple_cycles_reuse_catalogue_ports_and_raw_names(self):
  l=self.warm();l.execute('''
assert(recipeReads==2 and bulkScans==1);local crafts=craftReads
for i=1,3 do world.stock.entangled_chromaticglass=0;steps(400);assert(not K.busy and not K.blocked,K.message)end
assert(recipeReads==2 and bulkScans==1);assert(craftReads==crafts)
assert(world.stock.entangled_chromaticglass==1008)
''')
 def test_registered_recipe_invalidates_catalogue_but_keeps_known_ports(self):
  from test_read_optimization import fixture
  from simulate_two_recipes import WORLD
  from test_cache_management import SETUP
  l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27");l.execute(WORLD.replace("entangled_infinity='molten.infinity'}","entangled_infinity='molten.infinity',entangled_neutronium='molten.neutronium'}")+SETUP);l.execute(COUNT);l.execute('''
C.write(cfg.recipeDirectory..'/c.dat',{state='converted',condensates={{name='entangled_neutronium',amount=144}},outputs={}})
local fs=require('filesystem');local list=fs.list
fs.list=function(p)if p~=cfg.recipeDirectory then return list(p)end;local a={'a.dat','b.dat','c.dat'};local i=0;return function()i=i+1;return a[i]end end
local before=recipeReads;K.invalidateCatalogue();K.catalogueStep();assert(recipeReads==before+3)
steps(400);assert(recipeReads==before+3 and bulkScans==1)
assert(world.stock.entangled_neutronium>=1000)
''')
 def test_changed_route_is_rediscovered_before_transfer(self):
  l=self.warm();l.execute('''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)local args={...};if a=='bulk1'and (m=='getTankCount'or m=='getTankCapacity'or m=='getFluidInTank'or m=='transferFluid')then args[1]=args[1]==0 and 4 or args[1]==4 and 0 or args[1]end;return invoke(a,m,table.unpack(args))end
world.stock.entangled_chromaticglass=0;steps(400);assert(bulkScans==2)
local j=C.read(C.path('state/group-1/cache.journal'));assert(j.stage=='stopped'and j.transfers[1].from==0)
''')
 def test_empty_known_source_keeps_binding_and_never_transfers_wrong_fluid(self):
  l=self.warm();l.execute('''
world.main['molten.chromaticglass']=0;world.stock.entangled_chromaticglass=0
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)local side=...;if a=='bulk1'and m=='getFluidInTank'and side==4 and world.main['molten.chromaticglass']==0 then return {amount=0}end;return invoke(a,m,...)end
'''+AE+'''cpuBusy=false;steps(400);assert(requests==1);assert(bulkScans==1);assert(world.stock.entangled_chromaticglass>=1000)''')
 def test_manual_refresh_rebuilds_discovery(self):
  l=self.warm();l.execute("K.action({mode='refresh'});world.stock.entangled_chromaticglass=0;steps(400);assert(recipeReads==4 and bulkScans==2)")
 def test_restart_reuses_saved_routes_but_reads_recipe_catalogue_once(self):
  l=self.warm();l.execute("K=factoryCache(C,B,cfg,disk);world.stock.entangled_chromaticglass=0;steps(400);assert(recipeReads==4 and bulkScans==1);assert(world.stock.entangled_chromaticglass==1008)")
 def test_wrong_binding_or_unbound_address_discards_saved_discovery(self):
  for mutation in ["v.binding='other-config'","v.ports['molten.chromaticglass'].address='unbound'"]:
   l=self.warm();l.execute("local p=C.path('state/group-1/cache-discovery.dat');local v=C.read(p);"+mutation+";C.write(p,v);K=factoryCache(C,B,cfg,disk);world.stock.entangled_chromaticglass=0;steps(400);assert(bulkScans==2);assert(world.stock.entangled_chromaticglass==1008)")
 def test_saved_alias_cannot_redirect_recipe_to_unrelated_fluid(self):
  l=self.warm();l.execute("local p=C.path('state/group-1/cache-discovery.dat');local v=C.read(p);v.rawNames.entangled_chromaticglass='molten.infinity';C.write(p,v);K=factoryCache(C,B,cfg,disk);world.stock.entangled_chromaticglass=0;steps(400);local j=C.read(C.path('state/group-1/cache.journal'));assert(j.transfers[1].raw=='molten.chromaticglass');assert(world.stock.entangled_chromaticglass==1008)")
if __name__=='__main__':unittest.main()
