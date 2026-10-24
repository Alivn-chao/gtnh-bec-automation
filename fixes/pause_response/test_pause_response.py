import sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests'),str(ROOT/'reinstall_v3/tests')]
from test_cache_management import setup as cache_setup
from test_web_session import SETUP as SESSION
from test_web_transport import SETUP as TRANSPORT
from test_cache_response import WIRE
class PauseTests(unittest.TestCase):
 def test_pause_received_during_catalogue_read_releases_pattern_editor(self):
  l=cache_setup();l.execute("cfg.workshopInterface='workshop';"+SESSION)
  l.execute("H.snapshot();H.handle('cache',{mode='enable',revision=H.snapshot(true).cache.revision},1);H.handle('start',{revision=H.snapshot(true).revision},2)")
  l.execute(TRANSPORT+WIRE+r'''
local c=require('component');local invoke=c.invoke;local injected=false
c.invoke=function(a,m,...)
 if m=='getTankCount'and not injected then
  injected=true;queued[#queued+1]={'hd_panel_web','panel','pause','player',500,{_token='pause-read'}}
 end
 return invoke(a,m,...)
end
for i=1,50 do H.step();if injected and not H.snapshot(true).cache.busy then break end;world.advance(.05)end
assert(injected and serviced==1 and T.reply.ok and T.reply.name=='pause')
assert(not H.running and not H.snapshot(true).cache.busy and not H.snapshot(true).cache.blocked)
assert(not E.groupOwner[1]and not E.fluidOwner)
assert((world.calls.transferFluid or 0)==0)
H.handle('patterns',{mode='preview',revision=H.snapshot(true).revision},501)
assert(H.snapshot(true).patterns.status=='running')
''')
 def test_pause_does_not_wait_for_cache_sleep_deadline(self):
  l=cache_setup();l.execute("s.files[C.path('runtime/cache.lua')]='os.sleep(100)\\n'..s.files[C.path('runtime/cache.lua')];change('save','default','1000');change('enable');K.step(E,true);K.step(E,true);assert(K.busy);local before=s.now;K.requestStop();for i=1,10 do K.step(E,false);if not K.busy then break end end;assert(s.now==before);assert(not K.busy and not K.blocked,K.message);assert(not E.groupOwner[1]and not E.fluidOwner)")
 def test_pause_handler_is_not_nested_and_does_not_overwrite_pending_reply(self):
  from test_cache_response import CacheResponseTests
  l=CacheResponseTests().make();l.execute("T.handling=true;queued={{'hd_panel_web','panel','pause','player',600,{_token='pause'}}};T.pulse();assert(serviced==nil and #T.queue==1);T.handling=false;T.pending={mode='binding'};T.pulse();assert(serviced==nil);s.now=s.now+.7;T.pulse();T.pulse();assert(serviced==1 and T.reply.name=='pause')")
if __name__=='__main__':unittest.main()
