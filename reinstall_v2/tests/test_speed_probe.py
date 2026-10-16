"""Read-only speed diagnosis against deterministic component samples."""
from pathlib import Path
import unittest
from lupa.lua52 import LuaRuntime
SCRIPT=(Path(__file__).resolve().parents[1]/'probe_speed.lua').read_text(encoding='utf-8-sig')
SETUP=r'''
logs={};calls={};sample={getState='crafting',getRequiredTier={tier=4},getProvidedTier={tier=4},getAvailableNanites=1024,getParallelRecipesInProgress=64,getSlowdowns=0,getManualSlowdown=1}
local cfg={nodes={{name='N1',address='node'}}}
function loadfile(p)assert(p=='/home/bec_v2/lib/config.lua');return function()return{load=function()return cfg end,validate=function()end}end end
local c={methods=function(a)local m={};for k in pairs(sample)do m[k]=false end;return m end,invoke=function(a,m)calls[#calls+1]=m;assert(m:match('^get'),'must not mutate hardware');return sample[m]end}
function require(name)assert(name=='component');return c end
function print(s)logs[#logs+1]=tostring(s)end
io.open=function()error('probe must not open files directly')end
'''
class SpeedProbeTests(unittest.TestCase):
 def run_probe(self,change=''):
  l=LuaRuntime(unpack_returned_tuples=True);l.execute(SETUP);l.execute(change);l.execute(SCRIPT)
  return l,'\n'.join(l.globals().logs.values())
 def test_matching_tier_and_false_method_flags(self):
  l,out=self.run_probe();self.assertIn('16.0000 recipe ticks',out);self.assertEqual(len(l.globals().calls),7)
 def test_tier_penalty(self):
  _,out=self.run_probe('sample.getProvidedTier.tier=5');self.assertIn('8.0000 recipe ticks',out);self.assertIn('TIER PENALTY',out)
 def test_contamination_and_manual_use_maximum(self):
  _,out=self.run_probe('sample.getSlowdowns=2;sample.getManualSlowdown=4');self.assertIn('4.0000 recipe ticks',out);self.assertIn('CONTAMINATION',out)
 def test_low_tier_blocks_instead_of_estimating_speed(self):
  _,out=self.run_probe('sample.getProvidedTier.tier=3');self.assertIn('BLOCKED: nanite tier too low',out);self.assertNotIn('Estimated active speed:',out)
 def test_unknown_reading_is_not_assumed_zero(self):
  _,out=self.run_probe('sample.getSlowdowns=nil');self.assertIn('No estimate:',out)
 def test_idle_and_paused_are_not_actual_crafting(self):
  _,out=self.run_probe("sample.getState='idle'");self.assertIn('IDLE:',out)
  _,out=self.run_probe("sample.getState='paused-immediate'");self.assertIn('currently paused/blocked',out)
if __name__=='__main__':unittest.main()
