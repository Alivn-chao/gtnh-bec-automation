"""2.9.0 server-thread writes: delayed callbacks, not version-name guessing."""
import unittest
from test_read_optimization import fixture
from test_batch_overhead import feed_world


ASYNC=r'''
local c=require('component');local invoke=c.invoke
server={};writes={};waits=0
local setters={setMinParallel=true,setMaxParallel=true,setWorkAllowed=true,setCondensateFilters=true}
c.invoke=function(a,m,...)
 if setters[m]then
  local args=table.pack(...);writes[m]=(writes[m]or 0)+1
  if drop then return end
  server[#server+1]=function()invoke(a,m,table.unpack(args,1,args.n))end
  if lostReply then error('reply lost after queue')end
  return
 end
 return invoke(a,m,...)
end
C.wait=function(seconds)
 waits=waits+1;s.now=s.now+seconds
 if waits>=3 then local queued=server;server={};for _,run in ipairs(queued)do run()end end
end
'''


class Release290Tests(unittest.TestCase):
 def test_delayed_min_max_range_order_and_original_limit_restore(self):
  for minimum,maximum in ((1,256),(8,16),(1,1)):
   l=feed_world(16);l.globals().lo=minimum;l.globals().hi=maximum;l.execute(r'''
for _,n in pairs(nodes)do n.min=lo;n.max=hi end
'''+ASYNC+r'''
admit();assert(F.ready and waits>=3 and admitted==16)
for _,n in pairs(nodes)do assert(n.min==1 and n.max==1 and not n.workAllowed)end
complete();C.wait(.05);for _,n in pairs(nodes)do assert(n.min==lo and n.max==hi)end
assert(noops==0 and #server==0)
''')

 def test_delayed_wave_submits_all_permissions_before_first_readback_wait(self):
  l=feed_world(16);l.execute(ASYNC+r'''
local wait=C.wait;local openingWait
C.wait=function(seconds)
 local record=F.plan()
 if record and record.stage=='opening-nodes'and not openingWait then
  openingWait=true;assert(#server==16 and writes.setWorkAllowed==16 and admitted==0)
 end
 wait(seconds)
end
admit();assert(openingWait and admitted==16 and writes.setWorkAllowed==32 and #server==0)
''')

 def test_lost_setter_reply_keeps_pending_without_repeating_write(self):
  l=feed_world(16);l.execute(ASYNC+r'''
F.step();s.now=10;lostReply=true
assert(not pcall(F.step));local count=writes.setMaxParallel
assert(count==1 and #server==1 and admitted==0)
assert(F.plan().pending.kind=='set-parallel')
assert(not pcall(F.step)and writes.setMaxParallel==count)
assert(not pcall(M.new,cfg,1,C,E))
''')

 def test_write_that_never_commits_stops_and_is_not_resent(self):
  l=feed_world(16);l.execute(ASYNC+r'''
drop=true;F.step();s.now=10
assert(not pcall(F.step)and writes.setMaxParallel==1 and waits<=100 and admitted==0)
assert(F.plan().pending.kind=='set-parallel')
assert(not pcall(F.step)and writes.setMaxParallel==1)
''')

 def test_engine_pause_waits_for_deferred_disable_before_confirming(self):
  l=fixture();l.execute(ASYNC+r'''
E=factory(cfg,C,{},false);E.pauseAll()
for i=1,#cfg.nodes do assert(not nodes['node'..i].workAllowed)end
assert(writes.setWorkAllowed==#cfg.nodes and #server==0)
for i=1,#cfg.nodes do assert(C.read(C.path('state/node-'..i..'/batch-stop.dat')).stage=='confirmed')end
''')

 def test_shared_pending_is_seen_by_other_component_wrappers(self):
  l=fixture();l.execute(ASYNC+r'''
local c=require('component');local first=C.component(c);local second=C.component(c)
first.invoke('node1','setWorkAllowed',false)
assert(nodes.node1.workAllowed~=false)
assert(second.invoke('node1','isWorkAllowed')==false and writes.setWorkAllowed==1 and waits==3)
''')

 def test_nested_pause_supersedes_old_open_without_waiting_for_it_again(self):
  l=fixture();l.execute(ASYNC+r'''
local c=require('component');local first=C.component(c);local second=C.component(c)
nodes.node1.workAllowed=false
first.invoke('node1','setWorkAllowed',true)
local armed=true
C.pulse=function()
 if armed then
  armed=false
  assert(second.invoke('node1','isWorkAllowed')==true)
  second.invoke('node1','setWorkAllowed',false)
  assert(second.invoke('node1','isWorkAllowed')==false)
 end
end
assert(first.invoke('node1','isWorkAllowed')==false)
assert(writes.setWorkAllowed==2 and #server==0 and not nodes.node1.workAllowed)
''')

 def test_delayed_gate_filter_confirms_exact_slots_without_resending(self):
  l=fixture();l.execute(ASYNC+r'''
local c=C.component(require('component'))
local wanted={'entangled_chromaticglass','entangled_transcendentmetal'}
c.invoke('gate','setCondensateFilters',wanted)
local actual=c.invoke('gate','getCondensateFilters')
assert(actual[1]==wanted[1]and actual[2]==wanted[2]and writes.setCondensateFilters==1 and waits==3)
local now=s.now;c.invoke('gate','getCondensateFilters');assert(s.now==now)
''')

 def test_unchanged_sync_writes_add_no_sleep_or_getter(self):
  l=fixture();l.execute(r'''
local gets=0;local raw={invoke=function(a,m,...)if m=='isWorkAllowed'then gets=gets+1;return false,nil,'reason'end end}
C.wait=function()error('synchronous callback must not wait')end
local p=C.component(raw);p.invoke('a','setWorkAllowed',false)
local a,b,c=p.invoke('a','isWorkAllowed');assert(a==false and b==nil and c=='reason'and gets==1)
p.invoke('a','isWorkAllowed');assert(gets==2)
''')

 def test_transfer_callbacks_are_not_waited_repeated_or_reinterpreted(self):
  l=fixture();l.execute(r'''
local count=0;local raw={invoke=function(a,m,...)assert(m=='transferFluid');count=count+1;return false,0 end}
C.wait=function()error('transfers must not be settled/replayed')end
local ok,n=C.component(raw).invoke('a','transferFluid',4,5,144);assert(ok==false and n==0 and count==1)
''')

 def test_pending_confirmation_preserves_web_requests(self):
  from test_web_transport import SETUP
  l=fixture();l.execute(SETUP+ASYNC+r'''
local wait=C.wait
C.wait=function(seconds)T.poll(seconds);wait(seconds)end
enqueue('during-server-write')
local p=C.component(require('component'));p.invoke('node1','setWorkAllowed',false)
assert(p.invoke('node1','isWorkAllowed')==false)
assert(#acks==1 and T.take().token=='during-server-write')
''')


if __name__=='__main__':unittest.main()
