"""Behavioral Lua 5.2 simulation; not Minecraft hardware validation."""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
V2 = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

tree = ast.parse((ROOT / 'test_auto_once.py').read_text(encoding='utf-8'))
BASE = next(n.value.value for n in tree.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'MOCK' for t in n.targets))
MOCK = r'''
local c=require('component');local oldRequire=require
local fs=require('filesystem')
fs.path=function(path)return path:match('^(.*)/')end
fs.makeDirectory=function()return true end
fs.list=function()return function()end end
function require(name)
 if name=='filesystem'then return fs end
 if name=='event'then return {pull=function()end}end
 return oldRequire(name)
end
function loadfile(path,mode,env)return assert(load(assert(s.files[path],path),path,mode or 't',env or _G))end
nodes={};outputs={};generators={};filters={};releaseTimes={};releaseCount=0
cfg={version=2,mainInterface='main',recipeDirectory='/home/test-recipes',cacheTarget=144000,nodes={},groups={}}
local function copy(t)local r={};for k,v in pairs(t)do r[k]=v end;return r end
function configure(count)
 cfg.groups={{name='G1',storage='field',gate='gate',subInterface='sub',transposer='fluid',mainSide=4,subSide=5,
  generators={'gen1','gen2'},bulkTransposers={},nanites={enabled=false}}}
 for i=1,count do
  cfg.nodes[i]={name='N'..i,address='node'..i,group=1,redstone='rs'..i..'-',pauseSide=1,gate='gate'}
  nodes['node'..i]={required={entangled_chromaticglass=288,entangled_transcendentmetal=288},parallel=1,tier=4,consumed={},duration=i==1 and 0.5 or 1}
  outputs['rs'..i..'-']=15
 end
 s.stock={entangled_chromaticglass=288*count,entangled_transcendentmetal=288*count}
end
function c.list()
 local rows={{'gen1','gt_machine'},{'gen2','gt_machine'},{'gate','bec_diode'}}
 for i,n in ipairs(cfg.nodes)do rows[#rows+1]={n.redstone,'redstone'};rows[#rows+1]={n.address,'bec_io_node'}end
 local index=0;return function()index=index+1;if rows[index]then return table.unpack(rows[index])end end
end
function c.invoke(a,m,...)
 local args={...};local node=nodes[a]
 if node then
  if m=='getState'then
   if node.started and s.now-node.started>=node.duration then node.done=true end
   if node.done then return 'idle'end
   local rs='rs'..a:match('%d+')..'-'
   return outputs[rs]==15 and 'paused-immediate'or 'crafting'
  end
  if m=='getRequiredCondensate'then return not node.done and copy(node.required)or nil end
  if m=='getConsumedCondensate'then return copy(node.consumed)end
  if m=='getParallelRecipesInProgress'then return node.done and 0 or node.parallel end
  if m=='getRequiredTier'then return node.done and nil or {tier=node.tier}end
  if m=='getProvidedTier'then return {tier=4}end
  if m=='getAvailableNanites'then return 10432 end
  if m=='getMinParallel'or m=='getMaxParallel'then return 1 end
 end
 if a:sub(1,2)=='rs'then
  if m=='getOutput'then return outputs[a]end
  if m=='setOutput'then
   outputs[a]=args[2]
   if args[2]==0 then
    local n=nodes['node'..a:match('%d+')]
    assert(not n.done,'finished node was released again')
    if not n.started then
     n.started=s.now;releaseTimes[#releaseTimes+1]=s.now;releaseCount=releaseCount+1
     for key,value in pairs(n.required)do assert(s.stock[key]>=value);s.stock[key]=s.stock[key]-value;n.consumed[key]=value end
    end
   end;return true
  end
 end
 if a:sub(1,3)=='gen'then
  if m=='getName'then return 'multi.bec.generator'end
  if m=='setWorkAllowed'then
   if s.failGenerator and a=='gen2'and args[1]then error('generator fault')end
   generators[a]=args[1];return true
  end
  if m=='isWorkAllowed'then return generators[a]==true end
  if m=='isMachineActive'then return false end
 end
 if a=='gate'then
  if m=='getCondensateFilterCount'then return 9 end
  if m=='getCondensateFilters'then return copy(filters)end
  if m=='setCondensateFilters'then filters=copy(args[1]);return true end
  if m=='isMachineActive'or m=='isWorkAllowed'then return true end
 end
 if m=='getStoredCondensate'then return copy(s.stock)end
 if m=='isWorkAllowed'then return true end
 if m=='getFluidsInNetwork'or m=='getCpus'or m=='getCraftables'then return {}end
 if m=='getFluidInterfaceConfiguration'then return nil end
 if m=='setFluidInterfaceConfiguration'then return true end
 if m=='getTankCount'then return 1 end
 if m=='getFluidInTank'then return {amount=0}end
 error('unimplemented '..a..' '..m)
end
configure(2)
'''

def fixture():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(BASE)
    lua.execute(MOCK)
    for path in [V2 / 'main.lua', *sorted((V2 / 'lib').glob('*.lua')), *sorted((V2 / 'runtime').glob('*.lua'))]:
        source = path.read_text(encoding='utf-8')
        lua.eval('function(s) assert(load(s)) end')(source)
        lua.globals().s.files['/home/bec_v2/' + path.relative_to(V2).as_posix()] = source
    lua.execute("C=loadfile('/home/bec_v2/lib/config.lua')();Bridge=loadfile('/home/bec_v2/lib/bridge.lua')();factory=loadfile('/home/bec_v2/lib/engine.lua')()")
    return lua

def check(label, script):
    lua = fixture()
    lua.execute(script)
    print(label + ': PASS')

check('1 and 16 nodes accepted; 0 and 17 rejected', '''
configure(1);assert(C.validate(cfg,false));cfg.nodes={};assert(not pcall(C.validate,cfg,false))
configure(16);assert(C.validate(cfg,false));configure(17);assert(not pcall(C.validate,cfg,false))
''')
check('duplicate output and cross-group gate rejected', '''
cfg.nodes[2].redstone=cfg.nodes[1].redstone;assert(not pcall(C.validate,cfg,false))
configure(2);cfg.groups[2]={storage='field2',subInterface='sub2',transposer='fluid2',mainSide=4,subSide=5,generators={'gen3'},nanites={enabled=false}};cfg.nodes[2].group=2
assert(not pcall(C.validate,cfg,false))
''')
check('component methods returning false are present', "assert(C.validate(cfg,true))")
check('full controller: two physical nodes release together and finish independently', '''
E=factory(cfg,C,Bridge,false)
for tick=1,300 do E.step();s.now=s.now+0.1 end
assert(releaseCount==2,table.concat(E.logs,' / '));assert(releaseTimes[1]==releaseTimes[2])
assert(nodes.node1.done and nodes.node2.done);assert(outputs['rs1-']==15 and outputs['rs2-']==15)
assert(not generators.gen1 and not generators.gen2);assert(not E.tasks[1].fault,table.concat(E.logs,' / '))
assert(C.read(C.path('state/group-1/cohort.dat')).stage=='stopped')
assert(s.stock.entangled_chromaticglass==0 and s.stock.entangled_transcendentmetal==0)
''')
check('16 physical nodes run same cohort', '''
configure(16);E=factory(cfg,C,Bridge,false)
for tick=1,300 do E.step();s.now=s.now+0.1 end
assert(releaseCount==16,table.concat(E.logs,' / '));for _,time in ipairs(releaseTimes)do assert(time==releaseTimes[1])end
''')
check('different recipes are held out of current cohort', '''
nodes.node2.required={entangled_chromaticglass=144};E=factory(cfg,C,Bridge,false);E.step()
assert(#E.tasks[1].members==1 and E.tasks[1].members[1]==1);assert(outputs['rs2-']==15)
''')
check('aggregate demand and shared hive count', '''
E=factory(cfg,C,Bridge,false);E.step()
assert(#E.tasks[1].members==2)
local captured;local original=load
load=function(text,path,mode,env)
 if path:find('runtime/controller.lua',1,true)then captured=env;return function()coroutine.yield('wait',1000)end end
 return original(text,path,mode,env)
end
Bridge.environment(cfg,1,E)
local c=captured.require('component');assert(c.invoke('node1','getRequiredCondensate').entangled_chromaticglass==576)
assert(c.invoke('node1','getAvailableNanites')==10432)
''')
check('pause applies to entire shared group', '''
E=factory(cfg,C,Bridge,false);E.step();E.pauseNode(2)
assert(E.tasks[1].cancel and E.tasks[2].cancel and outputs['rs1-']==15 and outputs['rs2-']==15)
for tick=1,3 do E.step();s.now=s.now+1 end
assert(not E.groupOwner[1]);assert(C.read(C.path('state/group-1/cohort.dat')).stage=='interrupted')
''')
check('generator failure never releases nodes', '''
s.failGenerator=true;E=factory(cfg,C,Bridge,false)
for tick=1,300 do E.step();s.now=s.now+0.1 end
assert(releaseCount==0);assert(E.tasks[1].fault);assert(outputs['rs1-']==15 and outputs['rs2-']==15)
assert(not generators.gen1 and not generators.gen2)
''')
check('restart does not replay an unfinished cohort', '''
E=factory(cfg,C,Bridge,false);E.step();E.pauseNode(1);E.step()
local old=C.read(C.path('state/group-1/cohort.dat'));assert(old.stage=='interrupted')
E=factory(cfg,C,Bridge,false);E.step();assert(not E.groupOwner[1] and E.tasks[1].disabled)
assert(releaseCount==0)
''')
check('monitor is read only', '''
E=factory(cfg,C,Bridge,true);local writes=s.writes;E.step();assert(s.writes==writes)
assert(not pcall(E.pauseNode,1));assert(not pcall(E.resumeNode,1));E.shutdown();assert(s.writes==writes)
''')
check('shared fluid interface is exclusively owned', '''
E=factory(cfg,C,Bridge,false);E.acquire(1)
local acquired=false;local other=coroutine.create(function()E.acquire(2);acquired=true end)
local ok,kind=coroutine.resume(other);assert(ok and kind=='lock'and not acquired)
E.release(1);assert(coroutine.resume(other));assert(acquired and E.fluidOwner==2)
''')
check('changed recipe in a cohort stops before release', '''
E=factory(cfg,C,Bridge,false);E.step();nodes.node2.required.entangled_chromaticglass=144
for tick=1,300 do E.step();s.now=s.now+0.1 end
assert(releaseCount==0);assert(E.tasks[1].fault);assert(outputs['rs1-']==15 and outputs['rs2-']==15)
''')
check('hive mutations require every group node and generator paused', '''
cfg.groups[1].nanites={enabled=true,transposer='bee',supplyInterface='supply',hatchInterface='hold',supplySide=2,hatchSide=4}
local captured;local original=load
load=function(text,path,mode,env)
 if path:find('runtime/controller.lua',1,true)then captured=env;return function()coroutine.yield('wait',1000)end end
 return original(text,path,mode,env)
end
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if a=='bee'then s.moves=s.moves+1;return 1 end;return invoke(a,m,...)end
E=factory(cfg,C,Bridge,false);E.step();local proxy=captured.require('component')
outputs['rs2-']=0;assert(not pcall(proxy.invoke,'bee','transferItem',2,4,1,1));assert(s.moves==0)
outputs['rs2-']=15;generators.gen2=true;assert(not pcall(proxy.invoke,'bee','transferItem',2,4,1,1));assert(s.moves==0)
generators.gen2=false;assert(proxy.invoke('bee','transferItem',2,4,1,1)==1 and s.moves==1)
''')
check('one failed redstone does not prevent pausing other nodes', '''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)if a=='rs1-'and m=='setOutput'then error('offline')end;return invoke(a,m,...)end
outputs['rs2-']=0;E=factory(cfg,C,Bridge,false);assert(not pcall(E.pauseNode,1));assert(outputs['rs2-']==15)
''')
check('dashboard renders offscreen and restores GPU', '''
local c=require('component');local native=require;local active=0;local frames=0;local freed=false
require=function(name)if name=='unicode'then return {wlen=function(s)return #s end,sub=string.sub}end;return native(name)end
c.gpu={getResolution=function()return 80,25 end,maxResolution=function()return 120,40 end,setResolution=function()end,
 getActiveBuffer=function()return active end,setActiveBuffer=function(v)active=v end,allocateBuffer=function()return 1 end,
 setForeground=function()end,setBackground=function()end,fill=function()assert(active==1)end,set=function()assert(active==1)end,
 bitblt=function(to,x,y,w,h,from)assert(to==0 and from==1);frames=frames+1 end,freeBuffer=function()freed=true end}
E=factory(cfg,C,Bridge,true);local UI=loadfile('/home/bec_v2/lib/ui.lua')()(cfg,E,C)
UI.draw();assert(frames==1);UI.close();assert(freed and active==0)
''')
print('V2 behavioral simulation passed; no hardware claim.')
