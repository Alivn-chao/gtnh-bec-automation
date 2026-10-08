"""Inventory-backed cache worker mocks; not Minecraft validation."""
import ast
import sys
from pathlib import Path
sys.path.insert(0,str(Path('work/lua_runtime').resolve()))
from lupa.lua52 import LuaRuntime
def literal(file,name):
    return next(n.value.value for n in ast.parse(Path(file).read_text(encoding='utf-8')).body
                if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
base=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
base=base.replace('/home/bec_auto_once.journal','/home/bec_cache.journal').replace('/home/bec_auto.journal','/home/bec_cache.journal')
EXTRA=r'''
local c=require('component');local previous=c.invoke;local fs=require('filesystem')
local previousRequire=require
function require(name) if name=='filesystem' then return fs end return previousRequire(name) end
local exists=fs.exists
fs.exists=function(path) return path=='/home/bec/recipes' or exists(path) end
fs.list=function(path)
 local rows={} for file in pairs(s.files) do if file:sub(1,#path+1)==path..'/' then rows[#rows+1]=file:sub(#path+2) end end
 table.sort(rows);local i=0;return function() i=i+1;return rows[i] end
end
local serial=require('serialization')
local function add(name,fluids)
 s.files['/home/bec/recipes/'..name..'.dat']=serial.serialize({state='converted',condensates=fluids,outputs={{name='gregtech:gt.metaitem.03',damage=name=='shielding' and 32307 or 32316,size=1}}},false)
end
add('shielding',{{name='entangled_chromaticglass',amount=288},{name='entangled_transcendentmetal',amount=288}})
add('waveguide',{{name='entangled_chromaticglass',amount=576}})
function c.invoke(a,m,...)
 local args={...}
 if m=='getState' then return s.newOrderAt and s.now>=s.newOrderAt and 'paused-immediate' or 'idle' end
 if m=='setWorkAllowed' then s.cacheEnabled=args[1];s.mutations=s.mutations+1;return end
 if m=='isWorkAllowed' and a:sub(1,8)=='c1ae3f7c' then return s.cacheEnabled or false end
 if m=='getStoredCondensate' and s.cacheEnabled and not s.noConvert then
  local names={['molten.chromaticglass']='entangled_chromaticglass',
   ['molten.transcendentmetal']='entangled_transcendentmetal',['molten.infinity']='entangled_infinity',dimensionallyshiftedsuperfluid='entangled_dimshiftedsuperfluid',
   ['molten.spacetime']='entangled_spacetime',['molten.spatialfluid']='entangled_space',spatialfluid='entangled_space',
   ['molten.neutronium']='entangled_neutronium',boundlesscosmicsolder='entangled_cosmicsolder'}
  for raw,n in pairs(s.sub) do local name=assert(names[raw]);s.stock[name]=(s.stock[name] or 0)+n end
  s.sub={}
 end
 if m=='getCraftables' then
  local known={['molten.chromaticglass']=true,['molten.transcendentmetal']=true,['molten.infinity']=true,
   dimensionallyshiftedsuperfluid=true,['molten.spacetime']=true,['molten.spatialfluid']=true,
   ['molten.neutronium']=true,boundlesscosmicsolder=true}
  if not (s.availableCrafts or known)[args[1].name] then return {} end
 end
 return previous(a,m,...)
end
function addRecipe(name,fluids) add(name,fluids) end
'''
SOURCE=Path('bec_cache.lua').read_text(encoding='utf-8')
passed=0
def run(label,setup='',mode='run',copies=1,success=True):
    global passed
    lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(base+EXTRA);lua.execute(setup)
    program=lua.eval('function(...) '+SOURCE+'\nend');program(mode,copies)
    s=lua.globals().s;logs=list(s.logs.values())
    if mode in ('preview','preview-stock'): assert s.mutations==0 and s.moves==0 and s.writes==0,(label,logs)
    else:
        assert any('预缓存完成' in x for x in logs)==success,(label,logs)
        assert not s.cacheEnabled and s.cfg is None,(label,logs)
        if not success:
            moves,requests=s.moves,s.requests;program('run',copies)
            assert s.moves==moves and s.requests==requests,(label,'unsafe retry')
    passed+=1;print(label+': PASS');return lua,program

run('registry preview is read-only',mode='preview')
lua,_=run('shared fluids maximum rather than sum')
assert lua.globals().s.stock.entangled_chromaticglass==576 and lua.globals().s.stock.entangled_transcendentmetal==288
run('configurable ten copies',copies=10)
lua,_=run('existing field credit','s.stock={entangled_chromaticglass=288,entangled_transcendentmetal=288}')
assert lua.globals().s.moves==1
run('cached unrelated known fluid preserved','s.stock.entangled_dimshiftedsuperfluid=1000')
lua,_=run('AE shortage streamed into protected subnet','s.mainStock={}',copies=10)
assert lua.globals().s.requests==2 and lua.globals().s.midJobMoves>0
dss="addRecipe('valve',{{name='entangled_chromaticglass',amount=576},{name='entangled_dimshiftedsuperfluid',amount=1000}});s.mainStock.dimensionallyshiftedsuperfluid=20000;"
lua,_=run('1000 mB DSS unit is not rounded to 144',dss,copies=3)
assert lua.globals().s.stock.entangled_dimshiftedsuperfluid==3000
lua,program=run('completed cache can run again without duplicate transfer')
s=lua.globals().s;moves=s.moves;program('run',1);assert s.moves==moves
run('unknown source mapping refuses before mutations',"addRecipe('unknown',{{name='entangled_unknown',amount=144}})",success=False)
run('incomplete registry refuses before mutations',"s.files['/home/bec/recipes/bad.dat']=require('serialization').serialize({state='prepared'},false)",success=False)
run('producer non-normal journal blocks competing controller',"s.files['/home/bec_auto.journal']=require('serialization').serialize({stage='waiting'},false)",success=False)
run('new order during cache preparation stops',"s.mainStock={};s.newOrderAt=0.5",success=False)
run('partial transfer blocks retry','s.partial=true',success=False)
run('uncertain AE request blocks retry','s.mainStock={};s.uncertainCraft=true',success=False)
infinity="addRecipe('rough',{{name='entangled_chromaticglass',amount=576},{name='entangled_infinity',amount=576}});s.mainStock['molten.infinity']=20000;"
lua,_=run('registered Rough recipe infinity cache',infinity,copies=10)
assert lua.globals().s.stock.entangled_infinity==5760
lua,_=run('existing infinity cache credited',infinity+"s.stock.entangled_infinity=5760",copies=10)
assert lua.globals().s.stock.entangled_infinity==5760
run('infinity registry preview is read-only',infinity,mode='preview',copies=10)
lua,_=run('uniform stock mode with four registered types',infinity+dss,mode='run-stock',copies=144000)
for name in ('chromaticglass','transcendentmetal','infinity','dimshiftedsuperfluid'):
    assert lua.globals().s.stock['entangled_'+name]==144000
run('uniform stock preview is read-only',infinity+dss,mode='preview-stock',copies=144000)
lua,_=run('uniform target credits existing surplus',"s.stock={entangled_chromaticglass=5760,entangled_transcendentmetal=2880}",mode='run-stock',copies=2880)
assert lua.globals().s.moves==0 and lua.globals().s.stock.entangled_chromaticglass==5760
lua,program=run('uniform nonbatch target rounds only needed deficit',dss,mode='run-stock',copies=1000)
assert lua.globals().s.stock.entangled_chromaticglass==1008
moves=lua.globals().s.moves;program('run-stock',1000);assert lua.globals().s.moves==moves
coal="addRecipe('coal_umv',{{name='entangled_space',amount=3456},{name='entangled_spacetime',amount=1728},{name='entangled_dimshiftedsuperfluid',amount=10000}})"
lua,_=run('UMV assembly line new fluids streamed and converted',coal+";s.mainStock={}",mode='run-stock',copies=18000)
for name in ('space','spacetime','dimshiftedsuperfluid'):
    assert lua.globals().s.stock['entangled_'+name]==18000
lua,_=run('existing extended caches survive next cache task',"s.stock.entangled_neutronium=18000")
assert lua.globals().s.stock.entangled_neutronium==18000
lua,_=run('1000 mB cosmic solder uses its correct unit',"addRecipe('uxv',{{name='entangled_cosmicsolder',amount=5000}});s.mainStock.boundlesscosmicsolder=30000",copies=2)
assert lua.globals().s.stock.entangled_cosmicsolder==10000
run('new fluid missing raw and recipe stops before mutations',coal+";s.availableCrafts={['molten.chromaticglass']=true,['molten.transcendentmetal']=true}",success=False)
run('ambiguous source candidates refuse before mutations',coal+";s.availableCrafts={['molten.chromaticglass']=true,['molten.transcendentmetal']=true,['molten.spacetime']=true,['molten.spatialfluid']=true,spatialfluid=true,dimensionallyshiftedsuperfluid=true}",success=False)
print(f'{passed} cache scenarios passed (mock only).')
