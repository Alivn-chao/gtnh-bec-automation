"""Confirmed partial IO is accounted once; unknown outcomes remain quarantined."""
import unittest
from test_cache_management import setup
OPTIONS="change('save','default','1000');change('save','entangled_infinity','0');change('save','entangled_transcendentmetal','0');change('enable')"
class CachePartialTests(unittest.TestCase):
 def test_partial_nonbatch_returns_accumulate_to_exact_rounded_target(self):
  l=setup();l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if m=='transferFluid'then local from,to,n=...;return invoke(a,m,from,to,math.min(n,333))end
 return invoke(a,m,...)
end
'''+OPTIONS+';steps(500)')
  self.assertEqual(l.eval('world.stock.entangled_chromaticglass'),1008)
  self.assertIsNone(l.eval('next(world.sub)'))
  l.execute("local r=C.read(C.path('state/group-1/cache.journal'));assert(r.stage=='stopped'and not r.pending);local sum=0;for _,t in ipairs(r.transfers)do sum=sum+t.amount end;assert(sum==1008 and #r.transfers==4)")
 def test_confirmed_zero_waits_without_inventing_stock(self):
  l=setup();l.execute(r'''
local c=require('component');local invoke=c.invoke;local attempts=0
c.invoke=function(a,m,...)
 if m=='transferFluid'then attempts=attempts+1;if attempts<=3 then return true,0 end end
 return invoke(a,m,...)
end
'''+OPTIONS+';steps(500)')
  self.assertEqual(l.eval('world.stock.entangled_chromaticglass'),1008)
  l.execute("local r=C.read(C.path('state/group-1/cache.journal'));assert(r.zeroTransfers==3 and #r.transfers==1)")
 def test_stop_after_partial_finishes_only_one_batch_before_handoff(self):
  l=setup();l.execute(r'''
local c=require('component');local invoke=c.invoke;calls=0
c.invoke=function(a,m,...)
 if m=='transferFluid'then calls=calls+1;local from,to,n=...;local a,b=invoke(a,m,from,to,math.min(n,333));if calls==1 then world.finished=false end;return a,b end
 return invoke(a,m,...)
end
'''+OPTIONS+';steps(500)')
  self.assertEqual(l.eval('world.stock.entangled_chromaticglass'),432)
  self.assertIsNone(l.eval('next(world.sub)'))
  self.assertIsNone(l.eval('E.groupOwner[1]'))
 def test_unknown_invalid_or_mismatched_receipt_never_replays(self):
  for result in ['return false,333','return true,nil','return true,-1','return true,n+1',"error('lost receipt')",'return true,332']:
   l=setup();l.execute(r'''
local c=require('component');local invoke=c.invoke;calls=0
c.invoke=function(a,m,...)
 if m=='transferFluid'then calls=calls+1;local from,to,n=...;invoke(a,m,from,to,333);'''+result+r''' end
 return invoke(a,m,...)
end
'''+OPTIONS+";for i=1,500 do K.step(E,true);world.advance(.05);if K.blocked then break end end")
   self.assertIsNotNone(l.eval('K.blocked'),result)
   self.assertEqual(l.eval('calls'),1,result)
   l.execute("local r=C.read(C.path('state/group-1/cache.journal'));assert(r.pending);assert(not world.gen.gen1 and not world.gen.gen2)")
if __name__=='__main__':unittest.main()
