"""Request completion inside slow worker reads, without reentrant machine actions."""
from pathlib import Path
import subprocess
import json
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests')]
from test_read_optimization import fixture
from test_web_session import SETUP as SESSION
from test_web_transport import SETUP as TRANSPORT
from test_cache_management import setup as cache_setup

WIRE=r'''
H.snapshot();T.snapshot=function()return H.snapshot(true)end
T.canServe=H.canServeFast
T.serve=function(request)
 serviced=(serviced or 0)+1
 local ok,message=pcall(H.handle,request.name,request.args,request.request)
 T.publish(H.snapshot(true),{token=request.token,name=request.name,ok=ok,message=tostring(message)})
end
function saveRequest(token,value,revision)
 queued[#queued+1]={'hd_panel_web','panel','cache','player',101,{_token=token,mode='save',name='default',value=value or '4000000',revision=revision or H.snapshot(true).cache.revision,group=1}}
end
'''

class CacheResponseTests(unittest.TestCase):
    def make(self,baseline=False):
        l=fixture();l.execute(SESSION)
        if baseline:
            l.globals().s.files['/home/bec_v2/lib/web_transport.lua']=subprocess.check_output(['git','show','0e3926a:reinstall_v2/files/lib/web_transport.lua'],cwd=ROOT).decode()
        l.execute(TRANSPORT+WIRE);return l

    def test_old_transport_reproduces_save_waiting_for_entire_slow_scan(self):
        l=self.make(True)
        l.execute("saveRequest('old');local proxy=C.component({invoke=function()s.now=s.now+.2 end});for i=1,180 do proxy.invoke()end;assert(#acks==1 and #T.queue==1);assert(H.snapshot(true).cache.target~=4000000)")
        self.assertIsNone(l.eval('serviced'))

    def test_save_is_durable_before_slow_scan_completes_and_receipt_is_distinct(self):
        l=self.make()
        l.execute(r'''
saveRequest('new')
local proxy=C.component({invoke=function()s.now=s.now+.2 end})
proxy.invoke();assert(serviced==1 and C.read(C.path('cache.config')).target==4000000)
assert(T.pending and T.reply.token=='new'and T.reply.ok)
for i=1,180 do proxy.invoke()end
assert(serviced==1 and #T.queue==0 and T.last.reply.token=='new')
assert(acks[1].message=='BEC_REQUEST_ACCEPTED')
assert(publications[2].token=='new'and publications[2].at<1)
''')

    def test_flush_failure_or_stale_revision_is_returned_as_failure(self):
        for mutation in ["saveRequest('bad','123','stale')",r"local open=io.open;io.open=function(p,m)local f=open(p,m);if f and p==C.path('cache.config')and m=='w'then f.flush=function()return nil end end;return f end;saveRequest('bad')"]:
            l=self.make();l.execute(mutation+";T.pulse();assert(serviced==1 and T.reply.ok==false);assert(H.snapshot(true).cache.target~=4000000)")

    def test_never_nests_handlers_or_skips_a_machine_action_in_fifo(self):
        l=self.make()
        l.execute("T.handling=true;saveRequest('wait');T.pulse();assert(serviced==nil and #T.queue==1);T.handling=false;T.pulse();assert(serviced==1)")
        l=self.make()
        l.execute("queued={{'hd_panel_web','panel','pause','player',99,{_token='pause'}}};saveRequest('after');T.pulse();assert(serviced==nil and #T.queue==2);assert(T.take().name=='pause');T.pulse();assert(serviced==1)")

    def test_pending_completion_is_not_overwritten_by_another_save(self):
        l=self.make()
        l.execute("saveRequest('one');T.pulse();assert(T.pending);saveRequest('two','2000000');T.pulse();assert(serviced==1 and T.reply.token=='one');s.now=s.now+.7;T.pulse();assert(T.last.reply.token=='one');T.pulse();assert(serviced==2 and T.reply.token=='two')")

    def test_inline_whitelist_excludes_controls_and_stale_groups(self):
        l=self.make()
        l.execute("for _,mode in ipairs({'enable','disable','refresh'})do assert(not H.canServeFast({name='cache',args={mode=mode}}))end;assert(not H.canServeFast({name='start',args={}}));saveRequest('group');queued[1][6].group=2;T.pulse();assert(serviced==1 and not T.reply.ok)")

    def test_full_catalogue_includes_inherited_zero_and_override_without_reads(self):
        l=cache_setup()
        l.execute(r'''
K.snapshot(1);change('save','entangled_infinity','0');change('save','entangled_transcendentmetal','123')
local c=require('component');c.invoke=function()error('display must be memory-only')end
local s=K.snapshot(1,true);assert(#s.catalogue==3)
local rows={};for _,r in ipairs(s.catalogue)do rows[r[1]]=r end
assert(rows.entangled_chromaticglass[4]==false and #rows.entangled_chromaticglass==4)
assert(rows.entangled_infinity[4]==0 and rows.entangled_transcendentmetal[4]==123)
''')

    def test_actual_cache_worker_services_save_at_recipe_log_boundary(self):
        l=cache_setup();l.execute(SESSION)
        l.execute("H.snapshot();H.handle('cache',{mode='enable',revision=H.snapshot(true).cache.revision},1);H.handle('start',{revision=H.snapshot(true).revision},2)")
        l.execute(TRANSPORT+WIRE+r'''
local open=io.open;local injected=false
io.open=function(p,m)
 local f=open(p,m)
 if m=='r'and p==cfg.recipeDirectory..'/b.dat'and not injected then
  injected=true;saveRequest('during-recipe','123456')
 end
 return f
end
for i=1,50 do H.step();if serviced then break end;world.advance(.05)end
assert(injected and serviced==1 and T.reply.ok)
assert(C.read(C.path('cache.config')).target==123456)
assert(H.snapshot(true).cache.busy and not H.snapshot(true).cache.blocked)
''')

    def test_catalogue_respects_panel_budget_with_sixteen_nodes(self):
        for total in [19,64]:
            l=fixture();l.execute('cfg.nodes={};nodes={};outputs={};configure(16)'+SESSION)
            l.globals().total=total
            l.execute(r'''
local r={state='converted',condensates={}}
for i=1,total do r.condensates[i]={name='entangled_item_'..i}end
C.write(cfg.recipeDirectory..'/limit.dat',r)
local fs=require('filesystem');local exists,list=fs.exists,fs.list
fs.exists=function(p)return p==cfg.recipeDirectory or exists(p)end
fs.list=function(p)
 if p~=cfg.recipeDirectory then return list(p)end
 local done=false;return function()if not done then done=true;return 'limit.dat'end end
end
''')
            def convert(v):return {str(k):convert(x)for k,x in v.items()}if hasattr(v,'items')else v
            data=convert(l.eval('H.snapshot()'))
            self.assertEqual(data['cache']['total'],total)
            self.assertEqual('catalogue'in data['cache'],total==19)
            data.update(reply={'token':'t'*64,'name':'cache','ok':True,'message':'中'*400},transportBusy=False,transportAt=123,transportProtocol=1)
            def count(v):return 1+sum(count(x)for x in v.values())if isinstance(v,dict)else 1
            self.assertLessEqual(count(data),512)
            self.assertLess(len(json.dumps(data,ensure_ascii=False).encode()),16384)

if __name__=='__main__':unittest.main()
