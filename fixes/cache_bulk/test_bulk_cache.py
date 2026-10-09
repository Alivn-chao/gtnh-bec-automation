"""Actual cache worker in Lua 5.2 mocks. No hardware claim."""
import ast, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
def literal(file,name):
 tree=ast.parse((ROOT/file).read_text(encoding='utf-8'))
 return next(n.value.value for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id==name for t in n.targets))
base=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
base=base.replace('/home/bec_auto_once.journal','/home/bec_cache.journal').replace('/home/bec_auto.journal','/home/bec_cache.journal')
base+=literal('test_cache.py','EXTRA')
extra=r'''
local c=require('component');local invoke,list=c.invoke,c.list
local B='bulk-transposer'
s.mainStock={['molten.chromaticglass']=200000};s.stock.entangled_chromaticglass=15984;s.stock.entangled_transcendentmetal=144000
function c.list(kind)
 local iter=list(kind);local added=false
 return function()local a,t=iter();if a then return a,t end;if not added and not s.noPort then added=true;return B,'transposer'end end
end
function c.invoke(a,m,...)
 local args={...}
 if a==B then
  if m=='getTankCount'then return args[1]==1 and 1 or args[1]==5 and 6 or 0 end
  if m=='getTankCapacity'then return args[1]==1 and 2147483647 or 16000 end
  if m=='getFluidInTank'then return args[1]==1 and {name='molten.chromaticglass',amount=s.mainStock['molten.chromaticglass']or 0}or {amount=0}end
  if m=='transferFluid'then
   assert(args[1]==1 and args[2]==5 and not s.cacheEnabled and s.output==15)
   local journal=require('serialization').unserialize(s.files['/home/bec_cache.journal'])
   assert(journal.stage=='transfer-pending'and journal.pending.amount==args[3])
   local raw='molten.chromaticglass';local n=math.min(args[3],s.mainStock[raw]or 0)
   if s.partial then n=n-144 end
   s.mainStock[raw]=s.mainStock[raw]-n;s.sub[raw]=(s.sub[raw]or 0)+n;s.moves=s.moves+1
   if s.uncertain then error('uncertain bulk transfer')end
   return true,n
  end
 end
 if m=='transferFluid'then error('ordinary fluid route must never run')end
 return invoke(a,m,...)
end
'''
source=(Path(__file__).parent/'bec_cache.lua').read_text(encoding='utf-8')
def run(label,setup='',mode='background-stock',success=True):
 lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(base+extra);lua.execute(setup)
 worker=lua.eval('function(...) '+source+'\nend');ok,error=worker(mode,144000)
 assert bool(ok)==success,(label,error,list(lua.globals().s.logs.values()))
 print(label+': PASS');return lua,worker

lua,_=run('high-speed background fills remaining 128016 mB in one round')
s=lua.globals().s;assert s.stock.entangled_chromaticglass==144000 and s.moves==1
lua,_=run('AE shortage orders the whole missing quantity and streams',"s.mainStock={}")
s=lua.globals().s;assert s.stock.entangled_chromaticglass==144000
assert s.requestTotals['molten.chromaticglass']==128016 and s.requests==1
lua,_=run('route remains discoverable when source is empty and no AE recipe exists',"s.mainStock={};s.availableCrafts={}",success=False)
logs=list(lua.globals().s.logs.values());assert any('AE补货配方' in x for x in logs),logs
lua,_=run('existing stock is moved without requesting a craft',"s.availableCrafts={}")
assert lua.globals().s.requests==0
lua,_=run('missing high-speed route never falls back',"s.noPort=true",success=False)
assert lua.globals().s.moves==0 and lua.globals().s.writes==0
lua,_=run('already dispatched production skips a new cache batch',"s.newOrderAt=0")
assert lua.globals().s.moves==0 and lua.globals().s.writes==0
lua,_=run('existing stopped small batch resumes without inflating its target',"""
s.files['/home/bec_cache.journal']=require('serialization').serialize({kind='cache',stage='stopped',background=true,incomplete=true,pending=nil,configOwned=false,requests={},transfers={},target={entangled_chromaticglass=31968}},false)
""")
assert lua.globals().s.stock.entangled_chromaticglass==31968
for failure in ['partial','uncertain']:
 lua,worker=run(failure+' bulk transfer refuses replay','s.'+failure+'=true',success=False)
 before=lua.globals().s.moves;worker('background-stock',144000);assert lua.globals().s.moves==before
lua,_=run('preview stays read only',mode='preview-stock')
assert lua.globals().s.moves==0 and lua.globals().s.writes==0
print('10 bulk-only cache scenarios passed (mock only).')
