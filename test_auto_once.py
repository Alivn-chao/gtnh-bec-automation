"""Lua 5.2 behavioral mocks. These are not Minecraft hardware validation."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

SOURCE = Path(__file__).with_name('bec_auto_once.lua').read_text(encoding='utf-8')
MOCK = r'''
local glass='entangled_chromaticglass'
local metal='entangled_transcendentmetal'
local rg='molten.chromaticglass'
local rm='molten.transcendentmetal'
s={now=0,output=15,enabled=false,moves=0,sets=0,mutations=0,writes=0,
 sub={},stock={},consumed={},files={},logs={},required={[glass]=288,[metal]=288}}
local rs='266f65b5-20be-4543-8f2f-bfd2d0816611'
local gen='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local function clone(t)
 if type(t)~='table' then return t end
 local n={} for k,v in pairs(t) do n[k]=clone(v) end return n
end
local serials={}; local serialCounter=0
local ser={}
function ser.serialize(t,pretty)
 assert(pretty==false,'persistent serialization must be compact')
 serialCounter=serialCounter+1; local text='record-'..serialCounter
 serials[text]=clone(t); return text
end
function ser.unserialize(text) return clone(serials[text]) end
local function state()
 if s.released then
  if s.finishReads and s.finishReads>=2 then return 'idle' end
  if s.now-s.released>=1 then return 'idle' end
  if s.delayRelease and s.now-s.released<0.5 then return 'paused-immediate' end
  return 'crafting'
 end
 if s.forceIdle or s.now<0.5 then return 'idle' end
 if s.offline and s.now<1.5 then return 'assembler-offline' end
 if s.unpowered and s.now<1.5 then return 'unpowered' end
 if s.badCrafting and s.now>=0.5 then return 'crafting' end
 if s.canceled and s.moves>=1 then return 'idle' end
 return 'paused-immediate'
end
local c={}
function c.list()
 local rows={{rs,'redstone'},{gen,'gt_machine'}}
 local i=0; return function() i=i+1; if rows[i] then return table.unpack(rows[i]) end end
end
function c.methods() return setmetatable({}, {__index=function() return false end}) end
function c.invoke(a,m,...)
 local args={...}
 if m=='getName' then return 'multi.bec.generator'
 elseif m=='getOutput' then return s.output
 elseif m=='setOutput' then
  assert(args[1]==1); s.mutations=s.mutations+1; s.output=args[2]
  if args[2]==0 then
   s.released=s.now
   assert(s.stock[glass]>=s.required[glass] and s.stock[metal]>=s.required[metal], 'released too early')
   s.stock={}; s.consumed=clone(s.required)
  end
 elseif m=='isWorkAllowed' then if a==gen then return s.enabled end return true
 elseif m=='setWorkAllowed' then assert(a==gen); s.mutations=s.mutations+1; s.enabled=args[1]
 elseif m=='isMachineActive' then return false
 elseif m=='getMinParallel' or m=='getMaxParallel' then return 1
 elseif m=='getState' then
  s.stateReads=(s.stateReads or 0)+1
  -- Hardware can change between two calls even without os.sleep.
  if s.race and s.now>=0.25 and not s.raceFired then
   s.raceFired=true; s.now=0.5; return 'idle'
  end
  if s.finishRace and s.released and s.now-s.released>=0.5 then
   s.finishReads=(s.finishReads or 0)+1
   return s.finishReads==1 and 'crafting' or 'idle'
  end
  return state()
 elseif m=='getParallelRecipesInProgress' then return state()=='idle' and 0 or 1
 elseif m=='getRequiredCondensate' then return clone(s.required)
 elseif m=='getConsumedCondensate' then return clone(s.consumed)
 elseif m=='getStoredCondensate' then return clone(s.stock)
 elseif m=='getFluidsInNetwork' then
  local inventory = a:sub(1,2)=='3a' and {[rg]=s.shortage and 0 or 16000,[rm]=16000} or s.sub
  local rows={} for name,n in pairs(inventory) do rows[#rows+1]={name=name,amount=n} end return rows
 elseif m=='getTankCount' then return 6
 elseif m=='getFluidInTank' then
  assert(args[2]>=1 and args[2]<=6)
  if args[1]==4 and args[2]==1 and s.cfg and not s.timeout then return {name=s.cfg.name,amount=16000} end
  return {amount=0}
 elseif m=='getFluidInterfaceConfiguration' then assert(args[1]>=0 and args[1]<=5); return args[1]==0 and s.cfg or nil
 elseif m=='setFluidInterfaceConfiguration' then
  assert(args[1]==0); s.mutations=s.mutations+1; s.sets=s.sets+1; s.cfg=args[2]
  return true
 elseif m=='transferFluid' then
  assert(args[1]==4 and args[2]==5)
  local journal=ser.unserialize(s.files['/home/bec_auto_once.journal'])
  assert(journal.stage=='transfer-pending' and journal.pending.amount==args[3],'missing durable intent')
  s.moves=s.moves+1
  local moved=s.partial and 144 or args[3]
  s.sub[s.cfg.name]=(s.sub[s.cfg.name] or 0)+moved
  if s.uncertain then error('uncertain transfer return') end
  return true,moved
 end
end
local function tick(n)
 s.now=s.now+n
 if s.enabled and not s.noConvert then
  for name,amount in pairs(s.sub) do
   local target=name==rg and glass or metal
   s.stock[target]=(s.stock[target] or 0)+amount
  end
  s.sub={}
 end
end
function require(name)
 return ({component=c,serialization=ser,computer={uptime=function() return s.now end},
  filesystem={exists=function(path) return s.files[path]~=nil end,
   rename=function(src,dst) s.files[dst]=s.files[src];s.files[src]=nil;return true end},sides={top=1}})[name]
end
os={sleep=tick}
io={open=function(path,mode)
 local buffer=mode=='w' and '' or s.files[path]
 if mode=='r' and buffer==nil then return nil end
 return {
  write=function(self,text) buffer=buffer..text; return self end,
  flush=function() s.writes=s.writes+1; s.files[path]=buffer; return true end,
  close=function() end,
  read=function() return s.corrupt and 'corrupted' or buffer end
 }
end}
function print(...)
 local args={...}; for i,v in ipairs(args) do args[i]=tostring(v) end
 s.logs[#s.logs+1]=table.concat(args,' ')
end
'''

def run(label, setup='', mode='run', expected_moves=0, success=False):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute(setup)
    program = lua.eval('function(...) ' + SOURCE + '\nend')
    program(mode)
    s = lua.globals().s
    logs = list(s.logs.values())
    assert s.moves == expected_moves, (label, s.moves, logs)
    assert s.output == 15 and s.enabled is False, (label, logs)
    assert s.cfg is None, (label, logs)
    completed = any('单次运行结束' in line for line in logs)
    assert completed == success, (label, logs)
    if mode == 'preview':
        assert s.mutations == 0 and s.writes == 0, (label, logs)
        assert any('预览结束' in line for line in logs), (label, logs)
    else:
        # A second run must never repeat transfers, including after partial/uncertain results.
        before = s.moves
        program('run')
        assert s.moves == before, (label, 'repeated transfer')
    print(label + ': PASS')

run('preview is read only', mode='preview')
run('full single order', expected_moves=2, success=True)
run('release state updates after tick', 's.delayRelease=true', expected_moves=2, success=True)
run('existing subnet credit', "s.sub['molten.chromaticglass']=144", expected_moves=2, success=True)
run('existing field credit', "s.stock['entangled_chromaticglass']=288", expected_moves=1, success=True)
run('main shortage stops before transfer', 's.shortage=true')
run('foreign subnet fluid stops', "s.sub['water']=144")
run('nonbatch subnet stops', "s.sub['molten.chromaticglass']=1")
run('partial transfer once', 's.partial=true', expected_moves=1)
run('uncertain transfer once', 's.uncertain=true', expected_moves=1)
run('source cache timeout', 's.timeout=true')
run('conversion timeout', 's.noConvert=true', expected_moves=2)
run('canceled paused order', 's.canceled=true', expected_moves=1)
run('journal readback failure blocks mutations', 's.corrupt=true')
run('no order timeout', 's.forceIdle=true')
run('assembler offline during startup waits', 's.offline=true', expected_moves=2, success=True)
run('power startup waits', 's.unpowered=true', expected_moves=2, success=True)
run('unexpected crafting stops without feeding', 's.badCrafting=true')
run('completion changes between polls', 's.finishRace=true', expected_moves=2, success=True)

# Regression: an idle condition and a paused guard used to disagree when the
# real node changed state between two consecutive getState calls.
lua=LuaRuntime(unpack_returned_tuples=True)
lua.execute(MOCK)
lua.execute('s.race=true')
program=lua.eval('function(...) '+SOURCE+'\nend')
program('run')
logs=list(lua.globals().s.logs.values())
assert not any('节点未按预期暂停' in x for x in logs), logs
assert any('单次运行结束' in x for x in logs), logs
print('state polling race does not falsely reject paused: PASS')

for stage, expected in [('starting',2), ('transfer-pending',0), ('done',0)]:
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    lua.execute("s.files['/home/bec_auto_once.journal']=require('serialization').serialize({version=1,stage='"+stage+"',transfers={}},false)")
    program=lua.eval('function(...) '+SOURCE+'\nend')
    program('resume')
    s=lua.globals().s
    logs=list(s.logs.values())
    assert s.moves==expected, (stage,logs)
    if stage=='starting':
        assert s.files['/home/bec_auto_once.journal.before-resume-1'] is not None
        assert any('单次运行结束' in x for x in logs), logs
    else:
        assert s.mutations==0, (stage,logs)
    print('resume '+stage+': PASS')
