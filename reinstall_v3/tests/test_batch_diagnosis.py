from pathlib import Path
import unittest
from test_read_optimization import fixture

SCRIPT=(Path(__file__).resolve().parents[1]/'diagnose_batch.lua').read_text(encoding='utf-8')

class BatchDiagnosisTests(unittest.TestCase):
 def run_script(self,values):
  l=fixture();l.execute("C.write(C.path('config.dat'),cfg);"+values+r'''
printed={};print=function(...)local out={...};for i,v in ipairs(out)do out[i]=tostring(v)end;printed[#printed+1]=table.concat(out,' ')end
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)assert(m:sub(1,3)=='get','diagnosis must not mutate machines');return invoke(a,m,...)end
local open=io.open;io.open=function(p,mode)assert(mode=='r','diagnosis must not write');return open(p,mode)end
''');l.execute(SCRIPT)
  return '\n'.join(l.globals().printed.values())
 def test_multi_node_sum_exceeds_limit_without_changing_anything(self):
  out=self.run_script("for _,n in pairs(nodes)do n.required={entangled_infinity=1500000000};n.consumed={}end")
  self.assertIn('OVER LIMIT entangled_infinity = 3000000000',out)
  self.assertNotIn('NODE OVER LIMIT',out)
 def test_single_node_limit_and_consumption_credit(self):
  out=self.run_script("nodes.node1.required={entangled_infinity=3000000000};nodes.node1.consumed={entangled_infinity=100000000};nodes.node2.done=true")
  self.assertIn('NODE OVER LIMIT entangled_infinity = 2900000000',out)
 def test_unknown_consumption_does_not_invent_remaining(self):
  out=self.run_script("nodes.node1.required={entangled_infinity=2};nodes.node1.consumed={entangled_infinity=3};nodes.node2.done=true")
  self.assertIn('inconsistent getters',out)
  self.assertNotIn('OVER LIMIT entangled_infinity',out)

if __name__=='__main__':unittest.main()
