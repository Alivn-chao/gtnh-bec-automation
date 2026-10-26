"""Pre-recipe input checks; call counts are not Minecraft timings."""
from pathlib import Path
import subprocess
import unittest
import test_cell_feed as feed_tests
ROOT=Path(__file__).resolve().parents[2]
BULK=r"""
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if a=='items'and m=='getAllStacks'then
  local side=...;return {count=function()return 10 end,getAll=setmetatable({},{__call=function()
   local rows={};for slot=0,9 do rows[slot]={}end
   rows[0]=disk[side]or{};if extraSide==side then rows[8]={name='foreign',size=1}end
   if brokenBulk then rows[6]=nil end
   return rows
  end})}
 end
 if a=='items'and m=='getStackInSlot'and extraSide==select(1,...)and select(2,...)==9 then return {name='foreign',size=1}end
 return invoke(a,m,...)
end
"""

class FeedDetectionTests(unittest.TestCase):
 def world(self):
  l=feed_tests.CellFeedTests().world();l.execute(BULK);return l

 def test_ten_second_collection_and_one_consistent_preflight(self):
  results=[]
  for old in [True,False]:
   l=self.world()
   if old:
    l.globals().s.files['/home/bec_v2/lib/cell_feed.lua']=subprocess.check_output(['git','show','20eb39a:reinstall_v2/files/lib/cell_feed.lua'],cwd=ROOT).decode()
    l.execute("M=loadfile('/home/bec_v2/lib/cell_feed.lua')();F=M.new(cfg,1,C,E)")
   l.execute(r"""
local c=require('component');local invoke=c.invoke;calls,reads,writes=0,0,0
c.invoke=function(a,m,...)calls=calls+1;if m=='setOutput'or m=='setWorkAllowed'then writes=writes+1 else reads=reads+1 end;return invoke(a,m,...)end
-- Match the real engine's idempotent admission permission setter.
E.nodeWork=function(i,on)local n=cfg.nodes[i];if c.invoke(n.address,'isWorkAllowed')~=on then c.invoke(n.address,'setWorkAllowed',on);assert(c.invoke(n.address,'isWorkAllowed')==on)end end
F.step();s.now=9.99;F.step();assert(moves==0)
local match=M.match;M.match=function(...)atMatch={calls=calls,reads=reads,writes=writes};return match(...)end
calls,reads,writes=0,0,0;s.now=10;F.step();assert(atMatch and moves==1 and admitted==1)
""")
   results.append({k:int(v)for k,v in l.globals().atMatch.items()})
  self.assertLess(results[1]['calls'],results[0]['calls'])
  print('before recipe match, 16 nodes, old/new callback counts:',results)

 def test_bulk_snapshot_includes_all_ten_slots_and_failure_falls_back(self):
  for broken in [True,False]:
   for side in [4,5]:
    l=self.world();l.globals().brokenBulk=broken;l.globals().extraSide=side
    l.execute('F.step();s.now=10;assert(not pcall(F.step));assert(moves==0 and admitted==0)')

 def test_unavailable_bulk_method_uses_normal_per_slot_checks(self):
  l=self.world();l.execute(r"""
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if m=='getAllStacks'then error('not supported')end;return invoke(a,m,...)end
F.step();s.now=10;F.step();assert(moves==1 and admitted==1)
""")

 def test_closing_admission_race_is_observed_before_moving_disk(self):
  l=self.world();l.execute(r"""
nodes.node1.workAllowed=true
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local result=invoke(a,m,...)
 if a=='node1'and m=='setWorkAllowed'and select(1,...)==false then nodes.node1.done=false end
 return result
end
F.step();s.now=10;assert(not F.step());assert(moves==0 and admitted==0)
""")

 def test_pause_write_failure_still_stops_before_capture(self):
  l=self.world();l.execute(r"""
outputs['rs1-']=0;local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if a=='rs1-'and m=='setOutput'then return true end;return invoke(a,m,...)end
F.step();s.now=10;assert(not pcall(F.step));assert(moves==0 and admitted==0)
""")

 def test_admission_does_not_poll_the_absent_source_disk(self):
  l=self.world();l.execute(r"""
F.step();s.now=10;F.step();assert(moves==1)
local c=require('component');local invoke=c.invoke;sourceReads=0
c.invoke=function(a,m,...)if a=='items'and m=='getStackInSlot'and select(1,...)==4 then sourceReads=sourceReads+1 end;return invoke(a,m,...)end
for i=1,8 do s.now=s.now+1;F.observe();assert(F.pending())end
assert(sourceReads==0)
""")

 def test_engine_reuses_confirmed_quota_identity_after_admission(self):
  l=self.world();l.execute(r"""
local c=require('component');local invoke=c.invoke;local needs,tiers={},{}
c.invoke=function(a,m,...)
 if m=='getRequiredCondensate'then needs[a]=(needs[a]or 0)+1 end
 if m=='getRequiredTier'then tiers[a]=(tiers[a]or 0)+1 end
 return invoke(a,m,...)
end
local reached=false
local bridge={environment=function(config,index,engine)return function()
 reached=true;assert(#engine.tasks[index].members==16)
 for i=1,16 do
  assert(needs['node'..i]==(i==index and 2 or 1),'accepted recipe was re-read')
  assert((tiers['node'..i]or 0)==(i==index and 1 or 0))
  local e=engine.tasks[index].entries[i];assert(e.parallel==nodes['node'..i].parallel and e.required.entangled_chromaticglass==288*e.parallel)
  nodes['node'..i].done=true;nodes['node'..i].consumed=e.required
 end
end end}
E=factory(cfg,C,bridge,false)
for tick=1,100 do E.step();s.now=s.now+.2+10;if reached then break end end
assert(reached and moves==2 and admitted==16)
""")

 def test_pause_during_capture_checkpoint_preserves_unmoved_source_and_clean_stop(self):
  l=self.world();l.execute(r"""
local write=C.write
C.write=function(path,r)write(path,r);if path:find('cell-feed.journal',1,true)and r.stage=='capturing'then E.tasks[1].disabled=true end end
F.step();s.now=10;assert(not pcall(F.step));assert(moves==0 and admitted==0 and disk[4]and not disk[5])
assert(C.read(C.path('state/group-1/cell-feed.journal')).stage=='stopped')
assert(C.read(C.path('state/group-1/cell-feed.journal.previous')).stage=='capturing')
""")

 def test_input_behind_sleeping_cache_wakes_cleanup_without_waiting(self):
  import test_cache_management as cache_tests
  l=cache_tests.setup();l.execute(r"""
change('enable');K.step(E,true);assert(K.busy)
local clock=require('computer');clock.uptime=function()return s.now end
-- Park the real cache coroutine far in the future at a harmless read.
local nativeRequire=require
require=function(name)if name=='event'then return {pull=function()coroutine.yield(s.now+100)end}end;return nativeRequire(name)end
local c=require('component');local invoke=c.invoke;local once=true
c.invoke=function(a,m,...)
 if once and m=='getTankCount'then once=false;coroutine.yield(s.now+100)end
 return invoke(a,m,...)
end
K.step(E,true);assert(K.busy)
E.hasPendingFeed=function()return true end
for i=1,10 do K.step(E,true);if not K.busy then break end end
assert(not K.busy and not K.blocked and not world.calls.transferFluid,K.message)
""")

if __name__=='__main__':unittest.main()
