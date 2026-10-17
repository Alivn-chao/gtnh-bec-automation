"""Display-only sampling must not delay durable action completion or control guards."""
import unittest
from test_read_optimization import fixture
from test_web_session import SETUP
from test_web_transport import SETUP as TRANSPORT
from test_cache_management import setup as cache_setup

class WebLatencyTests(unittest.TestCase):
 def make(self):
  l=fixture();l.execute('cfg.nodes={};nodes={};outputs={};configure(16)'+SETUP)
  return l
 def test_fast_snapshot_and_saved_reply_do_not_read_any_machine(self):
  l=self.make();l.execute(r'''
local c=require('component');local invoke=c.invoke;calls=0
c.invoke=function(...)calls=calls+1;s.now=s.now+.2;return invoke(...)end
local before=s.now;local snap=H.snapshot(true)
assert(#snap.nodes==16 and calls==0 and s.now==before)
H.handle('cache',{mode='save',name='default',value='4000000',revision=snap.cache.revision},201)
local saved=H.snapshot(true);assert(saved.cache.target==4000000 and calls==0 and s.now==before)
assert(C.read(C.path('cache.config')).target==4000000)
''')
 def test_display_reads_are_bounded_and_expire_without_becoming_control_inputs(self):
  l=self.make();l.execute(r'''
local c=require('component');local invoke=c.invoke;calls=0
c.invoke=function(...)calls=calls+1;s.now=s.now+.2;return invoke(...)end
for i=1,45 do local before=calls;H.displayStep();assert(calls-before<=1);s.now=s.now+.05 end
local snapshot=H.snapshot(true);assert(#snapshot.nodes==16 and snapshot.nodes[16].state~='offline')
local before=calls;for i=1,10 do H.snapshot(true)end;assert(calls==before)
s.now=s.now+11;assert(H.snapshot(true).nodes[16].state=='offline')
outputs['rs1-']=0
local ok=pcall(H.handle,'start',{revision=H.snapshot(true).revision},202);assert(not ok and not H.running)
''')
 def test_heartbeat_publishes_current_software_state_without_bulk_reads(self):
  l=self.make();l.execute(TRANSPORT+r'''
T.snapshot=function()return H.snapshot(true)end
local c=require('component');local invoke=c.invoke;calls=0
c.invoke=function(...)calls=calls+1;s.now=s.now+.2;return invoke(...)end
H.notice='phase changed inside worker';s.now=s.now+.7;T.pulse()
assert(T.last.notice=='phase changed inside worker'and calls==0)
local snap=H.snapshot(true)
H.handle('cache',{mode='save',name='default',value='4000000',revision=snap.cache.revision},203)
T.publish(H.snapshot(true),{token='save-fast',ok=true,message='saved'})
s.now=s.now+.7;T.pulse();assert(publications[#publications].token=='save-fast'and T.last.cache.target==4000000 and calls==0)
H.notice='next stage';s.now=s.now+.7;T.pulse();assert(T.last.notice=='next stage'and T.last.reply.token=='save-fast')
''')
 def test_single_target_saves_reuse_catalogue_and_refresh_or_invalidation_rescan(self):
  l=cache_setup();l.execute(r'''
local fs=require('filesystem');local listing=fs.list;scans=0
fs.list=function(p)if p==cfg.recipeDirectory then scans=scans+1 end;return listing(p)end
K.snapshot(1);assert(scans==1)
for i=1,5 do change('save','entangled_chromaticglass',tostring(1000+i))end
assert(scans==1)
K.action({mode='refresh'});assert(scans==2)
K.invalidateCatalogue();K.catalogueStep();assert(scans==3)
change('save','entangled_chromaticglass','4000');assert(scans==3)
''')
 def test_config_flush_failure_is_never_successful_early_reply(self):
  l=self.make();l.execute(r'''
local revision=H.snapshot(true).cache.revision
local open=io.open
io.open=function(path,mode)local f=open(path,mode);if f and path==C.path('cache.config')and mode=='w'then f.flush=function()return nil,'disk failure'end end;return f end
local ok=pcall(H.handle,'cache',{mode='save',name='default',value='4000000',revision=revision},204)
assert(not ok and H.snapshot(true).cache.revision==revision)
''')
 def test_control_reads_update_display_passively_and_display_reads_are_skipped(self):
  l=self.make();l.execute(TRANSPORT+r'''
T.snapshot=function()return H.snapshot(true)end;T.observe=H.observe
local c=C.component(require('component'));local state=c.invoke('node16','getState')
assert(H.snapshot(true).nodes[16].state==state)
local state,allowed=H.snapshot(true).nodes[16].state,c.invoke('node16','isWorkAllowed')
assert(H.snapshot(true).nodes[16].workAllowed==allowed)
local result={c.invoke('node1','setWorkAllowed',false)};assert(result[1]==true)
assert(H.snapshot(true).nodes[1].workAllowed==false)
-- A stale display value cannot replace a fresh hardware result in a guard.
outputs['rs16-']=0;assert(c.invoke('node16','getState')=='crafting')
assert(H.snapshot(true).nodes[16].state=='crafting')
''')
if __name__=='__main__':unittest.main()
