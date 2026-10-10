"""V1 bee module: cap, same-item top-up, journal safety; mocks only."""
import ast
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
tree=ast.parse((ROOT/'work/test_nanites_switch.py').read_text(encoding='utf-8'))
mock=next(n.value.value for n in tree.body if isinstance(n,ast.Assign)
    and any(isinstance(t,ast.Name) and t.id=='MOCK' for t in n.targets))
# Match the uploaded hardware layout; the old generic mock incorrectly made
# every transposer face look like an ME interface, including the west hatch.
mock += r'''
local c=require('component');local old=c.invoke
function c.invoke(a,m,...)
 local args={...}
 if a=='4bebfefd-f3c6-40ac-81d6-35b331415b0f' then
  if m=='getInventoryName' then
   if args[1]==4 then return 'gt.blockmachines' end
   if args[1]==2 or args[1]==3 then return s.inventoryName end
   return nil,'no inventory'
  end
  if m=='getInventorySize' then return args[1]==4 and 3 or (s.interfaceSlots or 9) end
  if m=='getStackInSlot' or m=='transferItem' then
   assert(args[1]==2 or args[1]==3,'attempted to read or move through hatch display slots')
   if m=='transferItem' then assert(args[2]==2 or args[2]==3,'wrong transfer destination') end
  end
 end
 return old(a,m,...)
end
'''
source=(Path(__file__).parent/'bec_nanites.lua').read_text(encoding='utf-8')
def run(label,setup='',success=True):
    lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(mock+setup)
    before=lua.eval('total()');lua.globals().worker=lua.execute(source)
    result=lua.eval('function()return pcall(worker.ensure,ctx)end')()
    ok=result[0] if isinstance(result,tuple) else result
    assert ok==success,(label,result)
    assert lua.eval('total()')==before,label
    print(label+': PASS');return lua
lua=run('adds new matching bees without evacuating current hatch','s.required=4;s.reserve.trans=9180')
assert lua.eval('s.hatch==19612 and s.reserve.trans==0 and s.provided==4')
assert lua.eval("require('serialization').unserialize(s.files['/home/bec_nanites.journal']).action=='topup'")
lua=run('same item top-up stops at 30720','s.required=4;s.reserve.trans=40000')
assert lua.eval('s.hatch==30720 and s.reserve.trans+s.buffers.supply==19712')
lua=run('full hatch has no transfers','s.required=4;s.hatch=30720;s.reserve.trans=9180')
assert lua.eval('s.moves==0')
lua=run('no matching extra bees leaves existing hatch alone','s.required=4;s.reserve.trans=0')
assert lua.eval('s.moves==0 and s.hatch==10432')
lua=run('same grade different item is not mixed','s.required=2;s.provided=2;s.hatchKey="silver";s.hatch=64;s.reserve.silver=0')
assert lua.eval('s.moves==0 and s.hatch==64')
lua=run('type switch loads all available selected bees up to cap','s.reserve.silver=40000')
assert lua.eval('s.hatch==30720 and s.provided==2 and s.reserve.silver+s.buffers.supply==9280 and s.reserve.trans==10840')
lua=run('adequate higher-grade fallback also tops up identical bees','s.required=3;s.reserve.silver=0')
assert lua.eval('s.hatch==10840 and s.provided==4')
lua=run('fewer than 64 existing bees may top up to usable count','s.required=4;s.hatch=32;s.reserve.trans=32')
assert lua.eval('s.hatch==64')
run('running node cannot top up','s.required=4;s.state="crafting"',False)
run('no pause signal cannot top up','s.required=4;s.output=0',False)
lua=run('wrong physical interface is rejected before any writes or moves','s.inventoryName="tile.fluid_interface"',False)
assert lua.eval('s.moves==0 and next(s.files)==nil')
lua=run('wrong interface size is rejected before any writes or moves','s.interfaceSlots=3',False)
assert lua.eval('s.moves==0 and next(s.files)==nil')
lua=run('uncertain transfer preserves pending intent','s.required=4;s.throwMove=true',False)
lua.execute('s.throwMove=false');before=lua.eval('s.moves');result=lua.eval('pcall(worker.ensure,ctx)')
assert result[0] is False and lua.eval('s.moves')==before
lua=run('interrupt after confirmed moves preserves totals','s.required=4;ctx.stopping=function()return s.moves>=3 end',False)
lua.execute('ctx.stopping=nil');lua.globals().worker.ensure(lua.globals().ctx)
assert lua.eval('s.hatch==10840 and s.reserve.trans==0')
print('confirmed interrupted top-up resumes: PASS')
lua=run('destination blocked preserves all bees','s.required=4;s.blockMove=true',False)
LuaRuntime().execute('assert(load(...))',source)
print('Module syntax: PASS; simulation only')
