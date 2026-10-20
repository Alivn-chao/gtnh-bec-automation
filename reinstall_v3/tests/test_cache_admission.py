"""Real cache worker, synthetic callback admission race; not hardware timing."""
import subprocess
import unittest
from pathlib import Path
from test_cache_management import setup

ROOT=Path(__file__).resolve().parents[2]

RACE=r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local args={...}
 if a=='node1'and m=='setWorkAllowed'and args[1]then
  admitted=true;world.finished=false
 end
 if admitted and a=='node1'and m=='getState'then return 'crafting'end
 return invoke(a,m,...)
end
change('save','default','1000');change('enable')
for i=1,800 do K.step(E,true);world.advance(.05);if K.blocked then break end end
'''

class CacheAdmissionTests(unittest.TestCase):
 def test_previous_code_reproduces_screenshot_guard(self):
  l=setup()
  source=subprocess.check_output(['git','show','499d433:reinstall_v2/files/lib/cache.lua'],cwd=ROOT).decode()
  l.globals().oldCache=source
  l.execute("factoryCache=assert(load(oldCache))();K=factoryCache(C,B,cfg,disk)"+RACE)
  self.assertIn('缓存期间节点状态异常',l.eval('K.blocked'))
  self.assertEqual(l.eval('world.calls.transferFluid'),None)

 def test_cache_never_opens_admission_while_holding_group(self):
  l=setup();l.execute(RACE)
  self.assertIsNone(l.eval('K.blocked'))
  self.assertIsNone(l.eval('admitted'))
  self.assertFalse(l.eval('world.workAllowed'))
  self.assertGreater(l.eval('world.stock.entangled_chromaticglass'),0)

 def test_order_admitted_during_final_close_yields_without_cache_writes(self):
  l=setup();l.execute(r'''
local nodeWork=E.nodeWork
E.nodeWork=function(i,enabled)
 nodeWork(i,enabled)
 world.finished=false -- order crossed the final idle read / close boundary
end
change('enable');K.step(E,true);assert(K.busy)
K.step(E,true)
assert(not K.busy and not K.blocked)
assert(E.groupOwner[1]==nil and E.fluidOwner==nil)
assert(world.calls.transferFluid==nil)
assert(C.read(C.path('state/group-1/cache.journal'))==nil)
assert(K.message:find('缓存尚未搬液/下单',1,true))
''')

 def test_external_reopening_during_cache_still_blocks_and_retains_journal(self):
  l=setup();l.execute(r'''
change('save','default','1000');change('enable')
for i=1,150 do K.step(E,true);world.advance(.05);if world.conversionAt then break end end
assert(K.busy and world.conversionAt)
world.workAllowed=true
for i=1,150 do K.step(E,true);world.advance(.05);if K.blocked then break end end
assert(K.blocked and K.blocked:find('接单许可被重新开启',1,true))
assert(C.read(C.path('state/group-1/cache.journal')))
assert(not world.gen.gen1 and not world.gen.gen2)
''')

if __name__=='__main__':unittest.main()
