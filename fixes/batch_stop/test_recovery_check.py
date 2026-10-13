import unittest
from pathlib import Path
from lupa.lua52 import LuaRuntime
SOURCE=(Path(__file__).parent/'recovery_check.lua').read_text(encoding='utf-8')
MOCK=r'''
logs={};closed=false
function print(s)logs[#logs+1]=s end
io={open=function(path,mode)assert(path=='/home/bec_auto.journal' and mode=='r');return {read=function()return 'old' end,close=function()closed=true end}end}
local values={getState='idle',getParallelRecipesInProgress=0,getConsumedCondensate={glass=100},getStoredCondensate={glass=29},getFluidsInNetwork={{name='raw.glass',amount=5}}}
local c={invoke=function(a,m,...)
 if m=='getRequiredCondensate'then return active and {other=144} or nil end
 if m=='getState' and active then return 'crafting' end
 if m=='getOutput'then return 15 end
 assert(values[m]~=nil,'unexpected mutation/call '..m);return values[m]
end}
old={stage='pipeline-producing',required={glass=112},pipeline={base={glass=134},initial={},delivered={},recipe={glass=14},startConsumed={}},plan={{name='glass',raw='raw.glass'}},requests={{raw='raw.glass',amount=134,state='done'}}}
require=function(n)if n=='component'then return c end;assert(n=='serialization');return {serialize=function(v)if type(v)=='table'then return 'table' end;return tostring(v)end,unserialize=function(s)assert(s=='old');return old end}end
'''
class CheckTests(unittest.TestCase):
 def test_idle_retained_consumption_and_active_next_recipe_read_only(self):
  for active in (False,True):
   r=LuaRuntime(unpack_returned_tuples=True);r.execute(MOCK);r.globals().active=active;r.execute(SOURCE)
   logs='\n'.join(r.globals().logs.values())
   self.assertIn('ACTIVE:' if active else 'IDLE:',logs)
   self.assertTrue(r.globals().closed);self.assertEqual(r.globals().old.stage,'pipeline-producing')
if __name__=='__main__':unittest.main()
