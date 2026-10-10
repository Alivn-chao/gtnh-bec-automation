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
