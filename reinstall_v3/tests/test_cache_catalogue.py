"""Persistent requirements and idle preflight. Call counts are not game timings."""
import json
import subprocess
import unittest
from pathlib import Path
import test_cache_management as cache_tests
ROOT=Path(__file__).resolve().parents[2]
META=r"""
local fs=require('filesystem');mtime={};recipeReads=0
fs.size=function(p)return #(s.files[p]or'')end
fs.lastModified=function(p)return mtime[p]or 1 end
disk.status=function()return{known=true,ok=true,free=2000000,reserve=524288}end
local open=io.open
io.open=function(p,m)if m=='r'and p:find(cfg.recipeDirectory..'/',1,true)==1 then recipeReads=recipeReads+1 end;return open(p,m)end
"""

def durable():
 l=cache_tests.setup();l.execute(META);return l

COUNT=r"""
local c=require('component');local invoke=c.invoke
for i=2,16 do cfg.nodes[i]={name='N'..i,address='node'..i,redstone='rs'..i..'-',pauseSide=1,group=1,gate='gate'};E.tasks[i]={}end
E.nodeWork=function(i,on)c.invoke(cfg.nodes[i].address,'setWorkAllowed',on)end
nodeCalls=0
c.invoke=function(a,m,...)
 if a:match('^node%d+$')then nodeCalls=nodeCalls+1;a='node1'end
 if a:match('^rs%d+%-')then a='rs1-'end
 return invoke(a,m,...)
end
change('save','default','1000');change('enable')
world.stock={entangled_chromaticglass=1000,entangled_transcendentmetal=1000,entangled_infinity=1000}
nodeCalls=0;world.calls={}
steps(400)
"""

class CatalogueTests(unittest.TestCase):
 def test_restart_reads_no_unchanged_recipe_and_does_not_rewrite_index(self):
  l=durable();l.execute(r"""
K.catalogueStep();assert(recipeReads==2 and K.catalogueStats.persisted)
local index=C.path('state/cache-catalogue.dat');assert(s.files[index]and #s.files[index]<65536)
local before=s.writes;K=factoryCache(C,B,cfg,disk);K.catalogueStep()
assert(recipeReads==2 and K.catalogueStats.reused==2 and s.writes==before)
assert(K.snapshot(1,true).total==3)
""")

 def test_only_changed_recipe_is_parsed_and_deleted_recipe_is_removed(self):
  l=durable();l.execute(r"""
K.catalogueStep();local p=cfg.recipeDirectory..'/a.dat';local r=C.read(p)
r.condensates[1].amount=999;C.write(p,r);mtime[p]=2
local before=recipeReads;K.invalidateCatalogue();K.catalogueStep()
assert(recipeReads==before+1 and K.catalogueStats.reused==1)
local fs=require('filesystem');local list=fs.list
fs.list=function(p)if p==cfg.recipeDirectory then local done=false;return function()if not done then done=true;return'b.dat'end end end;return list(p)end
before=recipeReads;K.invalidateCatalogue();K.catalogueStep();assert(recipeReads==before)
local saved=C.read(C.path('state/cache-catalogue.dat'));assert(not saved.entries['a.dat'])
""")

 def test_manual_refresh_forces_recheck_of_same_metadata(self):
  l=durable();l.execute("K.catalogueStep();K.action({mode='refresh'});assert(recipeReads==4 and K.catalogueStats.read==2)")

 def test_corrupt_index_or_different_directory_falls_back_to_recipe_library(self):
  for mutation in ["s.files[p]='broken'","local v=C.read(p);v.directory='other';C.write(p,v)","local v=C.read(p);v.entries['a.dat'].totals={bad=-1};C.write(p,v)"]:
   with self.subTest(mutation=mutation):
    l=durable();l.execute("K.catalogueStep();local p=C.path('state/cache-catalogue.dat');"+mutation+";K=factoryCache(C,B,cfg,disk);K.catalogueStep();assert(recipeReads==4 and K.snapshot(1,true).total==3)")

 def test_index_is_optional_at_low_disk_and_has_fixed_bounded_paths(self):
  l=durable();l.execute(r"""
disk.status=function()return{known=true,ok=true,free=524300,reserve=524288}end
K.catalogueStep();assert(recipeReads==2 and not K.catalogueStats.persisted)
assert(not s.files[C.path('state/cache-catalogue.dat')])
K.catalogueStep();assert(recipeReads==2,'same session still reuses requirements')
""")

 def test_full_stock_skips_workers_nodes_journals_and_generator_writes(self):
  rows=[]
  for baseline in [True,False]:
   l=cache_tests.setup()
   if baseline:
    l.globals().s.files['/home/bec_v2/lib/cache.lua']=subprocess.check_output(['git','show','b9cb993:reinstall_v2/files/lib/cache.lua'],cwd=ROOT).decode()
    l.execute("factoryCache=loadfile('/home/bec_v2/lib/cache.lua')();K=factoryCache(C,B,cfg,disk)")
   l.execute(COUNT)
   rows.append(dict(baseline=baseline,node_calls=int(l.globals().nodeCalls),component_calls=sum(l.globals().world.calls.values()),generator_writes=int(l.globals().world.calls['setWorkAllowed']or 0)))
   if not baseline:l.execute("assert(nodeCalls==0 and not K.busy and not world.calls.setWorkAllowed and not world.calls.transferFluid)")
  self.assertGreater(rows[0]['node_calls'],0)
  print('full stock, 16 nodes, 20-second simulation:',json.dumps(rows))

 def test_busy_group_is_skipped_and_new_deficit_still_starts_real_transfer(self):
  l=cache_tests.setup();l.execute(COUNT+r"""
world.stock.entangled_chromaticglass=0;E.groupOwner[1]=7;nodeCalls=0;steps(200)
assert(nodeCalls==0 and not K.busy)
E.groupOwner[1]=nil;steps(500);assert(world.stock.entangled_chromaticglass>=1000 and not K.blocked)
""")

 def test_pattern_preview_does_not_invalidate_known_cache_requirements(self):
  from test_web_patterns import WebPatternsTests
  l=WebPatternsTests().setup();l.execute(r"""
local fs=require('filesystem');local list=fs.list;local scans=0
fs.list=function(p)if p==cfg.recipeDirectory then scans=scans+1 end;return list(p)end
H.snapshot();local before=scans
H.handle('patterns',{mode='preview',revision=H.snapshot().revision},221)
for i=1,11 do H.step()end
H.snapshot();assert(scans==before and patternWrites==0)
""")

 def test_unreadable_stock_starts_no_request_or_transfer(self):
  l=cache_tests.setup();l.execute(r"""
change('enable');local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if m=='getStoredCondensate'then error('offline')end;return invoke(a,m,...)end
steps(100);assert(not K.busy and not world.calls.transferFluid)
""")

if __name__=='__main__':unittest.main()
