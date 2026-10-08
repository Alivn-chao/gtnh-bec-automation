import sys
from pathlib import Path
sys.path.insert(0, str(Path('work/lua_runtime').resolve()))
from lupa.lua52 import LuaRuntime
source = Path('bec_feed_test.lua').read_text(encoding='utf-8')
mock = r'''
state={now=0,sub=0,source=5,moves=0,sets=0,cfg=false,logs={}}
local FLUID='molten.chromaticglass'
local c={}
function c.methods(a) return {setFluidInterfaceConfiguration=false,getFluidInterfaceConfiguration=false,getFluidsInNetwork=false,transferFluid=false} end
function c.doc(a,m) return 'function([slot:number][, detail:table]):boolean' end
function c.invoke(a,m,...)
 local args={...}
 if m=='getFluidsInNetwork' then
  if a:sub(1,2)=='3a' then return {{name=FLUID,amount=1296}} end
  return {{name=FLUID,amount=state.sub}}
 elseif m=='getFluidInterfaceConfiguration' then
  assert(args[1]>=0 and args[1]<=5,'interface index out of bounds')
  if state.occupied and args[1]==0 then return {name=FLUID,amount=8000} end
  if state.cfg and args[1]==0 then return {name=FLUID,amount=8000} end
  return nil
 elseif m=='getTankCount' then return 6
 elseif m=='getFluidInTank' then
  assert(args[2]>=1 and args[2]<=6,'transposer tank index out of bounds')
  if state.cfg and not state.timeout and args[1]==state.source and args[2]==1 then return {name=FLUID,amount=144,capacity=8000} end
  return {amount=0,capacity=8000}
 elseif m=='setFluidInterfaceConfiguration' then
  assert(args[1]==0,'must use interface slot 0')
  if args[2] then
   assert(args[2].name==FLUID and args[2].size==144 and args[2].amount==144)
   state.sets=state.sets+1;state.cfg=true
  else state.cfg=false end
  return true
 elseif m=='transferFluid' then
  assert(args[1]==state.source and args[2]~=state.source and args[3]==144)
  state.moves=state.moves+1
  local moved=state.partial and 72 or 144
  state.sub=state.sub+moved
  return true,moved
 end
 error('unexpected method '..m)
end
local computer={uptime=function() return state.now end}
local term={clear=function() end}
function c.list(kind,exact)
 local used=false
 return function() if not used then used=true;return '66fb280f-080d-4623-8d54-0dffd5cd5aad' end end
end
local ser={serialize=function(v) if type(v)=='table' then return '{name='..tostring(v.name)..',amount='..tostring(v.amount)..'}' end return tostring(v) end}
function require(name) return ({component=c,computer=computer,term=term,serialization=ser})[name] end
function print(...) local xs={...};for i,v in ipairs(xs) do xs[i]=tostring(v) end;state.logs[#state.logs+1]=table.concat(xs,' ') end
io={read=function() return state.cancel and 'N' or 'T' end,open=function() return nil end}
os={sleep=function(n) state.now=state.now+n end}
'''
cases=[('east', {}, 1,144),('west', {'source':4},1,144),('cancel',{'cancel':True},0,0),('nonempty',{'sub':144},0,144),('occupied',{'occupied':True},0,0),('partial',{'partial':True},1,72),('timeout',{'timeout':True},0,0)]
for label, opts, calls, quantity in cases:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(mock)
    state=lua.globals().state
    for k,v in opts.items(): state[k]=v
    lua.execute(source)
    assert state.moves==calls, label
    assert state.sub==quantity, label
    assert state.cfg is False, label
    if label in ('east','west'):
        assert any('验收通过' in v for _,v in state.logs.items()),label
    print(label+': PASS')
