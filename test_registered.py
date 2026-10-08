"""Registered recipe demand and AE batch matching; mock only."""
import ast,sys
from pathlib import Path
sys.path.insert(0,str(Path('work/lua_runtime').resolve()))
from lupa.lua52 import LuaRuntime
def literal(file,name):
 return next(n.value.value for n in ast.parse(Path(file).read_text(encoding='utf-8')).body
  if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
prefix=Path('bec_auto.lua').read_text(encoding='utf-8').split('local function unchanged()')[0]
for label,fluids,parallel,amount,stock in [
 ('waveguide single fluid',"{entangled_chromaticglass=576}",5,10,144000),
 ('UMV three fluids',"{entangled_space=3456,entangled_spacetime=1728,entangled_dimshiftedsuperfluid=10000}",2,7,0)]:
 lua=LuaRuntime(unpack_returned_tuples=True)
 lua.execute(literal('test_auto_once.py','MOCK'))
 lua.execute('''
 local c=require('component');local fs=require('filesystem');local previous=require
 function require(n) if n=='filesystem' then return fs end return previous(n) end
 fs.exists=function(p) return p=='/home/bec/recipes' or s.files[p]~=nil end
 fs.list=function() local done=false;return function() if not done then done=true;return 'new.dat' end end end
 s.unit='''+fluids+''';s.parallel='''+str(parallel)+''';s.queue='''+str(amount)+'''
 local condensates={} for name,n in pairs(s.unit) do condensates[#condensates+1]={name=name,amount=n} end
 s.files['/home/bec/recipes/new.dat']=require('serialization').serialize({state='converted',condensates=condensates,outputs={{name='test:part',damage=0,size=2}}},false)
 local old=c.invoke
 function c.invoke(a,m,...)
  if m=='getParallelRecipesInProgress' then return s.parallel end
  if m=='getRequiredTier' then return {tier=4} end
  if m=='getProvidedTier' then return {tier=4} end
  if m=='getAvailableNanites' then return 2048 end
  if m=='getCpus' then return {{busy=true,cpu={activeItems=function() return {{name='test:part',damage=0,size=s.parallel*2}} end,pendingItems=function() return {{name='test:part',damage=0,size=(s.queue-s.parallel)*2},{name='gregtech:gt.metaitem.03',damage=32307,size=999}} end}}} end
  return old(a,m,...)
 end
 ''')
 lua.execute(prefix+'''
 local req={} for name,n in pairs(s.unit) do req[name]=n*s.parallel end
 local target,count=batchTarget(req,req)
 assert(count==s.queue)
 for name,n in pairs(s.unit) do assert(target[name]==n*s.queue) end
 assert(s.mutations==0 and s.writes==0)
 ''')
 print(label+': PASS')
