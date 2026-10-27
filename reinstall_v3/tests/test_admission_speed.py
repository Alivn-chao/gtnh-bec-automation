"""Frozen identity reuse and durable parallel transactions; no game timing claim."""
from pathlib import Path
import unittest
import subprocess
from test_read_optimization import fixture
from test_batch_overhead import feed_world

ROOT=Path(__file__).resolve().parents[2]
SOURCE=(ROOT/'reinstall_v2/files/runtime/controller.lua').read_text(encoding='utf-8')
INDEX=SOURCE[SOURCE.index('local recipeIndex'):SOURCE.index('local matchedOutputs')]

def recipe_world():
 l=fixture();l.execute(r'''
fs=require('filesystem')
catalogueReads=0
fs.exists=function(p)return p=='/home/bec/recipes'end
fs.list=function()catalogueReads=catalogueReads+1;return function()end end
function integer(n)assert(type(n)=='number'and n>=0 and n%1==0);return n end
function same(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;for k in pairs(b)do if not a[k]then return false end end;return true end
print=function()end
BEC_V3_FROZEN_RECIPE={recipe='frozen.dat',condensates={{name='cond',amount=288}},outputs={{name='actual-output',size=4}}}
''');return l

class AdmissionSpeedTests(unittest.TestCase):
 def test_startup_reuses_frozen_identity_and_bound_capabilities(self):
  results=[]
  for old in (True,False):
   l=fixture()
   if old:
    for name in ('lib/bridge.lua','runtime/controller.lua'):
     l.globals().s.files['/home/bec_v2/'+name]=subprocess.check_output(['git','show','eb46d5f:reinstall_v2/files/'+name],cwd=ROOT).decode()
    l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()")
   l.execute(r'''
configure(16);cfg.groups[1].cellFeed={enabled=false,representativeChecks=true}
local recipe={state='converted',condensates={{name='entangled_chromaticglass',amount=288},{name='entangled_transcendentmetal',amount=288}},outputs={{name='exact-product',size=1}}}
for i=1,36 do C.write(cfg.recipeDirectory..'/'..i..'.dat',recipe)end
local fs=require('filesystem');local exists=fs.exists;local list=fs.list
fs.exists=function(p)return p==cfg.recipeDirectory or exists(p)end
fs.list=function(p)if p~=cfg.recipeDirectory then return list(p)end;local i=0;return function()i=i+1;if i<=36 then return i..'.dat'end end end
local env=Bridge.environment
Bridge.environment=function(config,index,engine)
 engine.tasks[index].fixedBatch={count=16,recipe='1.dat',condensates=recipe.condensates,outputs=recipe.outputs}
 return env(config,index,engine)
end
reads,methodReads,componentLists,recipeReads=0,0,0,0
local c=require('component');local invoke,methods,components=c.invoke,c.methods,c.list;local open=io.open
c.invoke=function(...)reads=reads+1;return invoke(...)end
c.methods=function(...)methodReads=methodReads+1;return methods(...)end
c.list=function(...)componentLists=componentLists+1;return components(...)end
io.open=function(p,mode)if mode=='r'and p:sub(1,#cfg.recipeDirectory+1)==cfg.recipeDirectory..'/'then recipeReads=recipeReads+1 end;return open(p,mode)end
E=factory(cfg,C,Bridge,false);local phase=E.phase
E.phase=function(i,stage)if stage=='nanites'and not measured then measured={calls=reads,methods=methodReads,lists=componentLists,recipes=recipeReads}end;return phase(i,stage)end
for tick=1,50 do E.step();s.now=s.now+.1;if measured then break end end
assert(measured and not E.tasks[1].fault,table.concat(E.logs,' / '))
''')
   results.append(dict(l.globals().measured.items()))
  self.assertEqual(results[0]['recipes'],36);self.assertEqual(results[1]['recipes'],0)
  self.assertEqual(results[0]['lists'],3);self.assertEqual(results[1]['lists'],0)
  self.assertLess(results[1]['calls'],results[0]['calls'])
  self.assertLess(results[1]['methods'],results[0]['methods'])
  print('16-node first preparation startup callbacks, before/after:',results)

 def test_exact_frozen_recipe_never_rescans_or_selects_other_outputs(self):
  l=recipe_world();f=l.execute(INDEX+'\nreturn indexedRecipes')
  for _ in range(5):
   result=f(l.table_from({'cond':288}));self.assertEqual(result[1].name,'actual-output');self.assertEqual(result[1].size,4)
  self.assertEqual(l.globals().catalogueReads,0)

 def test_frozen_mismatch_and_bad_outputs_do_not_fall_back_to_catalogue(self):
  for change,needs in (("",{'cond':144}),("",{'cond':288,'other':1}),("BEC_V3_FROZEN_RECIPE.outputs={}",{'cond':288})):
   l=recipe_world();l.execute(change);f=l.execute(INDEX+'\nreturn indexedRecipes')
   with self.assertRaises(Exception):f(l.table_from(needs))
   self.assertEqual(l.globals().catalogueReads,0)

 def test_without_frozen_identity_catalogue_fallback_is_retained(self):
  l=recipe_world();l.execute('BEC_V3_FROZEN_RECIPE=nil');f=l.execute(INDEX+'\nreturn indexedRecipes')
  f(l.table_from({'cond':288}));f(l.table_from({'cond':288}));self.assertEqual(l.globals().catalogueReads,1)

 def test_batch_configuration_and_restore_use_two_checkpoints_each(self):
  l=feed_world(1000);l.execute(r'''
local write=C.write;stages={};C.write=function(path,r)
 if path:find('cell-feed.journal',1,true)then stages[r.stage]=(stages[r.stage]or 0)+1 end
 write(path,r)
end
admit();assert(stages.configuring==1 and stages.configured==1)
complete();assert(stages.restoring==1 and stages.restored==1)
assert(setters==64 and noops==0)
''')

 def test_partial_parallel_configuration_retains_whole_intent_and_no_replay(self):
  l=feed_world(1000);l.execute(r'''
local c=require('component');local invoke=c.invoke;attempts=0
c.invoke=function(a,m,...)local v=invoke(a,m,...);if m=='setMaxParallel'then attempts=attempts+1;if attempts==3 then error('lost callback')end end;return v end
F.step();s.now=10;assert(not pcall(F.step));assert(attempts==3 and admitted==0)
local r=C.read(C.path('state/group-1/cell-feed.journal'));assert(r.pending.kind=='set-parallel'and #r.pending.nodes==16)
assert(not pcall(F.step)and attempts==3);assert(not pcall(M.new,cfg,1,C,E))
for _,n in pairs(nodes)do assert(not n.workAllowed)end
''')

 def test_pause_at_configuration_intent_opens_no_node(self):
  l=feed_world(1000);l.execute(r'''
local write=C.write;C.write=function(path,r)write(path,r);if r.stage=='configuring'then E.tasks[1].disabled=true end end
F.step();s.now=10;assert(not pcall(F.step));assert(setters==0 and admitted==0)
assert(C.read(C.path('state/group-1/cell-feed.journal')).pending.kind=='set-parallel')
''')

 def test_unknown_restore_result_retains_pending_and_refuses_restart(self):
  l=feed_world(1000);l.execute(r'''
admit();local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)local v=invoke(a,m,...);if m=='setMaxParallel'then error('restore reply lost')end;return v end
assert(not pcall(complete));assert(C.read(C.path('state/group-1/cell-feed.journal')).pending.kind=='restore-parallel')
assert(not pcall(M.new,cfg,1,C,E))
''')

 def test_real_worker_uses_frozen_recipe_with_no_catalogue_scan(self):
  l=fixture();l.execute(r'''
cfg.groups[1].cellFeed={enabled=false,representativeChecks=true}
local env=Bridge.environment;local fs=require('filesystem');local list=fs.list;catalogueReads=0
fs.list=function(path)if path==cfg.recipeDirectory then catalogueReads=catalogueReads+1;error('unexpected recipe rescan')end;return list(path)end
Bridge.environment=function(config,index,engine)
 engine.tasks[index].fixedBatch={count=2,recipe='exact.dat',condensates={{name='entangled_chromaticglass',amount=288},{name='entangled_transcendentmetal',amount=288}},outputs={{name='exact-product',size=4}}}
 return env(config,index,engine)
end
E=factory(cfg,C,Bridge,false)
for tick=1,300 do E.step();s.now=s.now+.1;if releaseCount==2 and not E.groupOwner[1]then break end end
assert(releaseCount==2 and not E.tasks[1].fault,table.concat(E.logs,' / '));assert(catalogueReads==0)
''')

if __name__=='__main__':unittest.main()
