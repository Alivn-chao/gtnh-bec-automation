"""Simulate slow OC callbacks and the real five-second panel lease."""
import unittest
from test_read_optimization import fixture

SETUP=r'''
queued={};acks={};publications={};lastPublish=-100
local ev={pull=function(seconds)
 if #queued>0 then return table.unpack(table.remove(queued,1))end
 s.now=s.now+(seconds or 0)
end}
local panel={ack=function(id,ok,message)acks[#acks+1]={id=id,ok=ok,message=message,at=s.now}end,
 publish=function(data)
  if s.now-lastPublish<.5 then return false end
  if lastPublish>=0 then assert(s.now-lastPublish<5,'panel expired')end
  lastPublish=s.now
  publications[#publications+1]={at=s.now,busy=data.transportBusy,token=data.reply and data.reply.token}
  return true
 end}
T=loadfile('/home/bec_v2/lib/web_transport.lua')()(panel,ev,{decode=function(value)return value end},'panel')
C.pulse=T.pulse
function enqueue(token)queued[#queued+1]={'hd_panel_web','panel','cache','player',#acks+1,{_token=token}}end
T.pulse(true)
'''

class TransportTests(unittest.TestCase):
 def make(self):
  l=fixture();l.execute(SETUP);return l

 def test_slow_calls_keep_panel_alive_and_ack_without_reentrant_handler(self):
  l=self.make();l.execute(r'''
local calls=0
local proxy=C.component({invoke=function()calls=calls+1;s.now=s.now+.2;return nil,false,'reason'end})
enqueue('enable-1')
for i=1,180 do local a,b,c=proxy.invoke();assert(a==nil and b==false and c=='reason')end
assert(calls==180 and #publications>40)
assert(#acks==1 and acks[1].ok and acks[1].at<1 and acks[1].message=='BEC_REQUEST_ACCEPTED')
assert(T.take().token=='enable-1'and T.take()==nil)
''')

 def test_rate_limited_result_is_retained_before_next_request(self):
  l=self.make();l.execute(r'''
enqueue('one');T.pulse();assert(T.take().token=='one')
T.publish({mode='running',values={}},{token='one',ok=true,message='enabled'})
enqueue('two');T.pulse();assert(T.take()==nil and T.pending)
s.now=s.now+.7;T.pulse()
assert(publications[#publications].token=='one'and not publications[#publications].busy)
assert(T.take().token=='two')
s.now=s.now+.7;T.pulse();assert(publications[#publications].token=='one'and publications[#publications].busy)
''')

 def test_oversize_queue_invalid_source_and_q(self):
  l=self.make();l.execute(r'''
for i=1,18 do enqueue('request-'..i)end
for i=1,3 do T.pulse()end
assert(#T.queue==16 and #acks==18 and not acks[18].ok)
queued={{'hd_panel_web','different','start','p',30,{_token='ignored'}},{'key_down','keyboard',113,16}}
T.pulse();assert(T.stopping and #acks==18)
''')

 def test_actual_sixteen_node_snapshot_keeps_lease_during_read(self):
  from test_web_session import SETUP as SESSION
  l=fixture();l.execute('cfg.nodes={};nodes={};outputs={};configure(16)'+SESSION+SETUP)
  l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(...)s.now=s.now+.2;return invoke(...)end
local before=s.now;local snap=H.snapshot()
assert(#snap.nodes==16 and s.now-before>5)
assert(#publications>5 and s.now-lastPublish<1)
''')

if __name__=='__main__':unittest.main()
