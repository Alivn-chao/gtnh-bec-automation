"""Read amplification regression and call-count comparison; Lua mocks, not game timings."""
import ast
import json
from pathlib import Path
import subprocess
import unittest

HERE=Path(__file__).resolve().parent
HELPER=HERE/'test_v2.py'
module=ast.parse(HELPER.read_text(encoding='utf-8'))
ns={'__file__':str(HELPER)}
exec(compile(ast.Module(body=[n for n in module.body if not isinstance(n,ast.Expr)],type_ignores=[]),str(HELPER),'exec'),ns)
fixture=ns['fixture']
ROOT=HERE.parents[1]
BASE='549df6e'
FILES=['lib/engine.lua','lib/bridge.lua','runtime/controller.lua']
COUNTER=r'''
reads={};nodeReads=0
local c=require('component');local original=c.invoke
function c.invoke(a,m,...)
 if nodes[a]then reads[m]=(reads[m]or 0)+1;nodeReads=nodeReads+1 end
 return original(a,m,...)
end
'''
CAPTURE=r'''
E=factory(cfg,C,Bridge,false)
local t=E.tasks[1];t.members={};t.entries={};t.normalized={entangled_chromaticglass=288,entangled_transcendentmetal=288}
for i=1,#cfg.nodes do t.members[i]=i;t.entries[i]={required=nodes['node'..i].required,consumed={},parallel=1,tier=4}end
local original=load
load=function(text,path,mode,env)
 if path:find('runtime/controller.lua',1,true)then captured=env;return function()end end
 return original(text,path,mode,env)
end
Bridge.environment(cfg,1,E);load=original
'''

def measure(count,baseline=False):
    lua=fixture()
    if baseline:
        for name in FILES:
            raw=subprocess.check_output(['git','show',BASE+':reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')
            lua.globals().s.files['/home/bec_v2/'+name]=raw
        lua.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')();factory=loadfile('/home/bec_v2/lib/engine.lua')()")
    lua.execute(f'cfg.nodes={{}};nodes={{}};outputs={{}};configure({count})'+COUNTER)
    lua.execute(r'''
E=factory(cfg,C,Bridge,false)
for tick=1,300 do
 E.step()
 local done=true;for _,n in pairs(nodes)do if not n.done then done=false end end
 if done and not E.groupOwner[1]then break end
 s.now=s.now+0.1
end
assert(releaseCount==#cfg.nodes,table.concat(E.logs,' / '))
assert(not E.tasks[1].fault,table.concat(E.logs,' / '))
assert(C.read(C.path('state/group-1/cohort.dat')).stage=='stopped')
''')
    return {'node_getter_calls':int(lua.globals().nodeReads),'simulated_seconds':round(float(lua.globals().s.now),2),'releases':int(lua.globals().releaseCount)}

class ReadOptimizationTests(unittest.TestCase):
    def test_cross_getter_completion_still_requires_consumption_and_closed_admission(self):
        for closed,consumed,accepted in [(True,True,True),(True,False,False),(False,True,False)]:
            with self.subTest(closed=closed,consumed=consumed):
                lua=fixture();lua.execute('configure(1);'+CAPTURE)
                lua.globals().closed=closed;lua.globals().completeConsumption=consumed
                lua.execute(r'''
E.tasks[1].released=true
local c=require('component');local invoke=c.invoke;local reads=0
c.invoke=function(a,m,...)
 if a=='node1'then
  if m=='getState'then reads=reads+1;return reads==1 and 'crafting'or 'idle'end
  if m=='getRequiredTier'then return nil end
  if m=='isWorkAllowed'then return not closed end
  if m=='getConsumedCondensate'then return completeConsumption and nodes.node1.required or {}end
 end
 return invoke(a,m,...)
end
accepted=pcall(captured.BEC_V2_NODE_SNAPSHOT)
''')
                self.assertEqual(lua.globals().accepted,accepted)
    def test_idle_scan_does_not_read_old_recipe_fields(self):
        lua=fixture();lua.execute('configure(16);for _,n in pairs(nodes)do n.done=true end;'+COUNTER+'E=factory(cfg,C,Bridge,false);E.step()')
        self.assertEqual(lua.globals().reads['getState'],32)
        self.assertEqual(lua.globals().reads['isWorkAllowed'],16)
        self.assertIsNone(lua.globals().reads['getRequiredCondensate'])
        self.assertEqual(lua.globals().releaseCount,0)

    def test_one_explicit_sample_replaces_four_full_scans(self):
        lua=fixture();lua.execute('configure(16);'+CAPTURE+COUNTER)
        lua.execute("snapshot=captured.BEC_V2_NODE_SNAPSHOT();assert(snapshot.parallel==16 and snapshot.required.entangled_chromaticglass==4608)")
        self.assertEqual(lua.globals().nodeReads,80)
        lua.execute("nodeReads=0;local c=captured.require('component');c.invoke('node1','getState');c.invoke('node1','getParallelRecipesInProgress');c.invoke('node1','getRequiredCondensate');c.invoke('node1','getConsumedCondensate')")
        self.assertEqual(lua.globals().nodeReads,320)

    def test_sample_is_fresh_and_checks_every_member(self):
        lua=fixture();lua.execute('configure(16);'+CAPTURE)
        lua.execute("local a=captured.BEC_V2_NODE_SNAPSHOT();a.required.entangled_chromaticglass=0;local b=captured.BEC_V2_NODE_SNAPSHOT();assert(b.required.entangled_chromaticglass==4608);nodes.node16.required.entangled_chromaticglass=144")
        with self.assertRaisesRegex(Exception,'不同配方'):
            lua.execute('captured.BEC_V2_NODE_SNAPSHOT()')
        self.assertEqual(lua.globals().releaseCount,0)

    def test_unavailable_member_is_not_hidden(self):
        lua=fixture();lua.execute('configure(2);'+CAPTURE)
        lua.execute("local c=require('component');local old=c.invoke;c.invoke=function(a,m,...)if a=='node2'and m=='getState'then return 'unpowered'end;return old(a,m,...)end")
        with self.assertRaisesRegex(Exception,'节点不可用'):
            lua.execute('captured.BEC_V2_NODE_SNAPSHOT()')

    def test_full_worker_without_helper_keeps_getter_fallback(self):
        lua=fixture()
        lua.execute("s.files['/home/bec_v2/lib/bridge.lua']=s.files['/home/bec_v2/lib/bridge.lua']:gsub('env.BEC_V2_NODE_SNAPSHOT=nodeSnapshot','');Bridge=loadfile('/home/bec_v2/lib/bridge.lua')();E=factory(cfg,C,Bridge,false);for tick=1,300 do E.step();s.now=s.now+0.1 end;assert(releaseCount==2 and not E.tasks[1].fault,table.concat(E.logs,' / '))")

    def test_full_workers_reduce_calls_with_same_outcome(self):
        rows=[]
        for count in (1,2,16):
            before,after=measure(count,True),measure(count)
            self.assertLess(after['node_getter_calls'],before['node_getter_calls'])
            self.assertEqual(before['releases'],after['releases'])
            rows.append({'nodes':count,'baseline':before,'optimized':after,'getter_reduction_percent':round(100*(1-after['node_getter_calls']/before['node_getter_calls']),1)})
        output=ROOT/'outputs/v2_read_optimization';output.mkdir(parents=True,exist_ok=True)
        (output/'call-counts.json').write_text(json.dumps({'baseline_commit':BASE,'kind':'Lua 5.2 simulation; invocation counts, not real latency','rows':rows},indent=2),encoding='utf-8')
        print(json.dumps(rows,ensure_ascii=False),flush=True)

if __name__=='__main__':unittest.main()
