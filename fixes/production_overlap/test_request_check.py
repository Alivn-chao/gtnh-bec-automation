"""Read-only request check: stale journals, live tasks, and unreadable task lists."""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
SOURCE=(Path(__file__).parent/'check_requests.lua').read_text(encoding='utf-8')
MOCK=r'''
logs={};reads=0
old={stage='craft-paused',configOwned=false,requests={{raw='raw.a',state='submitted',amount=1000}},
 plan={{raw='raw.a',name='a',amount=1000}},pipeline={initial={},delivered={['raw.a']=500}}}
cpus={{busy=true,name='raw task',cpu={activeItems=function()return {{name='raw.a',size=500}}end,pendingItems=function()return {}end}},
 {busy=true,name='assembly',cpu={activeItems=function()return {{name='finished-product',size=1}}end,pendingItems=function()return {}end}}}
c={invoke=function(address,method)
 reads=reads+1
 if method=='getCpus'then return cpus end
 if method=='getStoredCondensate'then return {a=500}end
 if method=='getFluidsInNetwork'then return {{name='raw.a',amount=144},{name='unrelated',amount=999}}end
 error('Forbidden mutation/method: '..method)
end}
ser={unserialize=function(s)assert(s=='original journal');return old end,
 serialize=function(v,pretty)assert(pretty==false);return tostring(v)end}
io={open=function(path,mode)assert(path=='/home/bec_auto.journal' and mode=='r');return {read=function()return 'original journal'end,close=function()end}end}
require=function(n)if n=='component'then return c elseif n=='serialization'then return ser end;error(n)end
print=function(text)logs[#logs+1]=text end
'''
for setup,expected in [('',(2,1,0)),("cpus={{busy=false}}",(0,0,0)),("cpus={{busy=true,cpu={}}}",(1,0,1))]:
    r=LuaRuntime(unpack_returned_tuples=True);r.execute(MOCK+setup)
    r.execute('captured={};ser.serialize=function(v,pretty)assert(pretty==false);captured[#captured+1]=v;return tostring(v)end')
    r.execute(SOURCE)
    rows=list(r.globals().captured.values());summary=rows[-1]
    assert (summary.busy,summary.matchingRaw,summary.unreadable)==expected
    assert r.globals().old.requests[1].state=='submitted'
    assert any(isinstance(x,str) and 'No requests' in x for x in r.globals().logs.values())
print('Live raw task, stale submitted journal, unreadable CPU, no mutations: PASS')
