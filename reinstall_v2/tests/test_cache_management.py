"""V1 cache protocol under actual V2 leases and the clocked hardware model."""
import unittest
from test_read_optimization import fixture
from simulate_two_recipes import WORLD

SETUP=r'''
world.finished=true;world.current=2;world.readyAt=math.huge;world.workAllowed=false
C.write(C.path('config.dat'),cfg)
B=loadfile('/home/bec_v2/lib/ochd_bindings.lua')()
local fs=require('filesystem');local original=fs.list
fs.list=function(path)
 if path==cfg.recipeDirectory then local rows={'a.dat','b.dat'};local i=0;return function()i=i+1;return rows[i]end end
 return original(path)
end
factoryCache=loadfile('/home/bec_v2/lib/cache.lua')()
disk={status=function()return {known=true,ok=not diskLow}end}
K=factoryCache(C,B,cfg,disk)
function change(mode,name,value) return K.action({mode=mode,name=name,value=value,revision=K.snapshot(1).revision})end
function steps(count)
 for i=1,count do K.step(E,true);assert(not K.blocked,K.message);world.advance(.05)end
end
'''

def setup():
 l=fixture();l.execute("cfg.recipeDirectory='/home/bec_v2/recipes';BANK_SIZE=27")
 l.execute(WORLD+SETUP)
 return l

AE=r'''
world.main['molten.chromaticglass']=0;cpuBusy=true;requests=0
local c=require('component');local original=c.invoke
c.invoke=function(a,m,...)
 local filter=...
 if a=='main'and m=='getCpus'then return {{busy=cpuBusy,storage=1000000,cpu={activeItems=function()return {}end,pendingItems=function()return {}end}}}end
 if a=='main'and m=='getCraftables'then
  if filter.name~='molten.chromaticglass'then return {}end
  return {{getStack=function()return {name=filter.name,amount=1,size=1,isCraftable=true,hasTag=false}end,
   request=function(amount)
    requests=requests+1;local at=s.now+1;local delivered=false
    return {isComputing=function()return false end,hasFailed=function()return false end,isCanceled=function()return false end,
     isDone=function()if s.now<at then return false end;if not delivered then world.main[filter.name]=(world.main[filter.name]or 0)+amount;delivered=true end;return true end}
   end}}
 end
 return original(a,m,...)
end
change('save','default','1000');change('save','entangled_infinity','0');change('save','entangled_transcendentmetal','0');change('enable')
'''

class CacheManagementTests(unittest.TestCase):
 def test_only_old_fully_confirmed_cache_archives_are_pruned(self):
  l=setup();l.execute('''
local dir=C.path('state/group-1');local fs=require('filesystem');local exists,list=fs.exists,fs.list
fs.exists=function(p)return p==dir or exists(p)end
fs.lastModified=function()return 0 end
fs.remove=function(p)s.files[p]=nil;return true end
fs.list=function(p)
 if p~=dir then return list(p)end
 local rows={};for file in pairs(s.files)do if file:sub(1,#p+1)==p..'/'then rows[#rows+1]=file:sub(#p+2)end end;table.sort(rows)
 local i=0;return function()i=i+1;return rows[i]end
end
for i=1,6 do C.write(dir..'/cache.journal.stopped-'..i,{kind='cache',stage='stopped',configOwned=false,requests={{state='done'}},transfers={{ok=true}}})end
C.write(dir..'/cache.journal.stopped-7',{kind='cache',stage='stopped',configOwned=false,requests={{state='submitted'}}})
C.write(dir..'/cache.journal.stopped-8',{kind='cache',stage='stopped',configOwned=false,plan={}})
s.files[dir..'/cache.journal.stopped-9']='unknown-keep'
change('enable');K.step(E,true)
for i=1,4 do assert(s.files[dir..'/cache.journal.stopped-'..i]==nil)end
for i=5,9 do assert(s.files[dir..'/cache.journal.stopped-'..i]~=nil)end
''')

 def test_web_events_save_enable_and_run_real_cache_worker(self):
  from test_web_session import SETUP as WEB
  l=setup();l.execute(WEB+'''
local revision=H.snapshot().cache.revision
H.handle('cache',{mode='save',name='default',value='1000',revision=revision},301)
assert(H.snapshot().cache.target==1000 and world.calls.transferFluid==nil)
H.handle('cache',{mode='enable',revision=H.snapshot().cache.revision},302)
H.handle('start',{revision=H.snapshot().revision},303)
for i=1,1200 do H.step();world.advance(.05)end
assert(H.snapshot().cache.enabled)
assert(world.stock.entangled_chromaticglass==1008)
H.handle('cache',{mode='disable',revision=H.snapshot().cache.revision},304)
assert(not H.snapshot().cache.enabled)
H.handle('pause',{},305)
''')

 def test_closing_with_submitted_request_keeps_journal_and_blocks_restart(self):
  l=setup();l.execute(AE+'''cpuBusy=false
for i=1,100 do K.step(E,true);world.advance(.05);if requests==1 then break end end
K.close();K=factoryCache(C,B,cfg,disk)
''')
  with self.assertRaisesRegex(Exception,'未确认缓存'):l.execute('K.assertReady()')
  self.assertEqual(l.eval('requests'),1)
 def test_busy_cpu_wait_then_one_confirmed_request_and_no_replay(self):
  l=setup();l.execute(AE+'steps(150)')
  self.assertEqual(l.eval('requests'),0)
  self.assertTrue(l.eval('K.busy'))
  self.assertIn('CPU',l.eval('K.message'))
  l.execute('cpuBusy=false;steps(450)')
  self.assertEqual(l.eval('requests'),1)
  self.assertEqual(l.eval('world.stock.entangled_chromaticglass'),1008)
  self.assertFalse(l.eval('K.busy'))

 def test_arriving_production_waits_for_request_and_confirmed_conversion(self):
  l=setup();l.execute(AE+'''cpuBusy=false
for i=1,100 do K.step(E,true);world.advance(.05);if requests==1 then break end end
assert(requests==1 and K.busy and E.fluidOwner=='cache-1'and world.workAllowed==false)
world.finished=false
steps(200)
''')
  self.assertFalse(l.eval('K.busy'))
  self.assertEqual(l.eval('E.groupOwner[1]'),None)
  self.assertEqual(l.eval('E.fluidOwner'),None)
  self.assertEqual(l.eval('requests'),1)
  self.assertEqual(l.eval('next(world.sub)'),None)

 def test_unfinished_production_journal_blocks_cache_without_writes(self):
  l=setup();l.execute("change('enable');C.write(C.path('state/node-1/production.journal'),{stage='craft-request-pending',pending={},configOwned=false});steps(100)")
  self.assertFalse(l.eval('K.busy'))
  self.assertEqual(l.eval('world.calls.transferFluid'),None)
 def test_v1_default_per_fluid_zero_and_rounding_use_real_transfers(self):
  l=setup();l.execute("change('save','default','1000');change('save','entangled_infinity','0');change('save','entangled_transcendentmetal','2000');change('enable');steps(800)")
  self.assertEqual(l.eval('world.stock.entangled_chromaticglass'),1008)
  self.assertEqual(l.eval('world.stock.entangled_transcendentmetal'),2016)
  self.assertEqual(l.eval('world.stock.entangled_infinity or 0'),0)
  self.assertEqual(l.eval('next(world.sub)'),None)
  self.assertFalse(l.eval('K.busy'))
  self.assertEqual(l.eval('E.fluidOwner'),None)

 def test_configuration_is_durable_read_only_and_conflict_checked(self):
  l=setup();l.execute("change('save','default','5000');change('save','entangled_infinity','0');K=factoryCache(C,B,cfg,disk)")
  self.assertEqual(l.eval('K.snapshot(1).target'),5000)
  self.assertEqual(l.eval('C.read(C.path("cache.config")).overrides.entangled_infinity'),0)
  self.assertEqual(l.eval('#world.events'),1)
  with self.assertRaisesRegex(Exception,'已变化'):l.execute("K.action({mode='save',name='default',value='1',revision='stale'})")
  for name,value in [('default','0'),('default','-1'),('default','2147483648'),('unknown','1')]:
   with self.assertRaises(Exception):l.execute("change('save',"+repr(name)+','+repr(value)+')')
  l.execute("change('save','entangled_infinity','');assert(C.read(C.path('cache.config')).overrides.entangled_infinity==nil)")

 def test_existing_stock_credit_and_finished_cycles_do_not_repeat_transfers(self):
  l=setup();l.execute("world.stock={entangled_chromaticglass=900,entangled_transcendentmetal=2000,entangled_infinity=2000};change('save','default','1000');change('enable');steps(400)")
  self.assertEqual(l.eval('world.stock.entangled_chromaticglass'),1044)
  l.execute("beforeMoves=world.calls.transferFluid or 0;steps(300)")
  self.assertEqual(l.eval('world.calls.transferFluid'),l.eval('beforeMoves'))

 def test_pending_production_and_other_fluid_owner_block_cache_start(self):
  for condition in ["world.finished=false","E.fluidOwner=2","E.groupOwner[1]=2"]:
   l=setup();l.execute("change('enable');"+condition+";steps(20)")
   self.assertFalse(l.eval('K.busy'))
   self.assertEqual(l.eval('world.calls.transferFluid'),None)

 def test_disable_drains_confirmed_raw_then_releases_production_leases(self):
  l=setup();l.execute("change('save','default','1000');change('enable');for i=1,100 do K.step(E,true);world.advance(.05);if world.conversionAt then break end end;assert(K.busy and E.fluidOwner=='cache-1');change('disable');steps(150)")
  self.assertFalse(l.eval('K.busy'))
  self.assertEqual(l.eval('E.groupOwner[1]'),None)
  self.assertEqual(l.eval('next(world.sub)'),None)
  self.assertFalse(l.eval('world.gen.gen1'))
  self.assertFalse(l.eval('world.gen.gen2'))

 def test_restart_with_uncertain_cache_requests_never_replays_or_starts_production(self):
  l=setup();l.execute("C.write(C.path('state/group-1/cache.journal'),{kind='cache',stage='craft-paused',configOwned=false,requests={{state='submitted',amount=1000}}})")
  with self.assertRaisesRegex(Exception,'未确认缓存'):l.execute("change('enable')")
  self.assertEqual(l.eval('world.calls.transferFluid'),None)

 def test_binding_change_during_io_fails_and_preserves_record(self):
  l=setup();l.execute("change('save','default','1000');change('enable');for i=1,100 do K.step(E,true);world.advance(.05);if world.conversionAt then break end end;s.files[C.path('config.dat')]='changed';for i=1,150 do K.step(E,true);world.advance(.05);if K.blocked then break end end")
  self.assertTrue(l.eval('K.blocked')is not None)
  self.assertIsNotNone(l.eval("s.files[C.path('state/group-1/cache.journal')]"))
  self.assertFalse(l.eval('world.gen.gen1'))

if __name__=='__main__':unittest.main()
