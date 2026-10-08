"""Same-recipe queued batches, Lua 5.2 mocks; not hardware acceptance."""
import ast
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

SOURCE=Path('bec_auto_batch.lua').read_text(encoding='utf-8')
tree=ast.parse(Path('test_auto_once.py').read_text(encoding='utf-8'))
MOCK=next(node.value.value for node in tree.body if isinstance(node,ast.Assign)
          and any(isinstance(t,ast.Name) and t.id=='MOCK' for t in node.targets))
MOCK=MOCK.replace('/home/bec_auto_once.journal','/home/bec_auto_batch.journal')
EXTRA=r'''
local c=require('component')
local invoke=c.invoke
s.quantity=15; s.outputs=0; s.baseline=7; s.started=0; s.completed=0
local glass='entangled_chromaticglass';local metal='entangled_transcendentmetal'
local function state()
 if s.released then
  if s.completed==s.quantity then return 'idle' end
  if s.completed==5 and s.now-s.released<10 then return 'idle' end
  if s.noGap then return 'crafting' end
  if s.completed==s.started then return 'idle' end
  return 'crafting'
 end
 if s.now<0.5 then return 'idle' end
 return 'paused-immediate'
end
function c.invoke(a,m,...)
 local args={...}
 if m=='getItemsInNetwork' then
  assert(args[1].name=='gregtech:gt.metaitem.03' and args[1].damage==32307)
  if s.unreadable then return nil end
  local output=s.outputs
  if s.deferred then output=s.completed>=s.quantity and s.quantity or (s.completed>=5 and 5 or 0) end
  if s.takeAway and s.completed>0 then output=output-1 end
  return {{name='gregtech:gt.metaitem.03',damage=32307,size=s.baseline+output},
    {name='gregtech:gt.metaitem.03',damage=32308,size=10000}}
 elseif m=='setOutput' and args[2]==0 then
  assert(s.stock[glass]>=s.quantity*288 and s.stock[metal]>=s.quantity*288,'released before whole queue stock')
  s.released=s.now;s.output=0;s.mutations=s.mutations+1;return 15
 elseif m=='getState' then return state()
 elseif m=='getParallelRecipesInProgress' then return state()=='idle' and 0 or 1
 elseif m=='getRequiredCondensate' then
  if s.mixed and s.started>=2 then return {entangled_chromaticglass=144} end
  if s.released and state()=='idle' then return nil end
  return s.required
 elseif m=='getFluidsInNetwork' and a:sub(1,2)=='3a' then
  return {{name='molten.chromaticglass',amount=s.shortage and 0 or 16000},
    {name='molten.transcendentmetal',amount=16000}}
 end
 return invoke(a,m,...)
end
local sleep=os.sleep
function os.sleep(n)
 sleep(n)
 if s.released and s.output==0 and not s.cancel then
  local target=math.min(s.quantity,math.floor(s.now-s.released))
  -- Two AE tasks: first five, second ten arrives later.
  if s.now-s.released<10 then target=math.min(target,5) end
  while s.completed<target do
   s.started=s.started+1
   assert(s.stock[glass]>=288 and s.stock[metal]>=288,'queue ran out of condensate')
   s.stock[glass]=s.stock[glass]-288;s.stock[metal]=s.stock[metal]-288
   s.completed=s.completed+1;s.outputs=s.outputs+1
   s.consumed={[glass]=288,[metal]=288}
  end
 end
end
'''

def run(label,setup='',mode='run',qty=15,moves=2,done=True):
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK+EXTRA)
    lua.execute(setup)
    program=lua.eval('function(...) '+SOURCE+'\nend')
    program(mode,str(qty))
    s=lua.globals().s
    logs=list(s.logs.values())
    assert s.moves==moves,(label,s.moves,logs)
    assert s.output==15 and s.enabled is False,(label,logs)
    assert s.cfg is None,(label,logs)
    assert any('批量运行完成' in x for x in logs)==done,(label,logs)
    if done:
        assert s.outputs==qty,(label,logs)
    if mode=='preview':
        assert s.mutations==0 and s.writes==0,(label,logs)
        assert any('预览结束' in x for x in logs),(label,logs)
    else:
        # Do not automatically retry ambiguous or incomplete runs.
        if not done:
            before=s.moves
            program('run',str(qty))
            assert s.moves==before,(label,'repeated uncertain transfer')
    print(label+': PASS')
    return lua,program

run('preview fifteen read only',mode='preview',moves=0,done=False)
run('two queued tasks five plus ten')
run('no idle gap between recipes','s.noGap=true')
run('AE CPU holds task outputs until task done','s.deferred=true')
run('existing condensate credit',"s.stock.entangled_chromaticglass=1440")
run('existing subnet credit',"s.sub['molten.chromaticglass']=144")
run('main shortage', 's.shortage=true', moves=0,done=False)
run('partial transfer is not repeated','s.partial=true',moves=1,done=False)
run('uncertain transfer is not repeated','s.uncertain=true',moves=1,done=False)
run('mixed recipe aborts and pauses','s.mixed=true',done=False)
run('missing inventory API data','s.unreadable=true',moves=0,done=False)
run('cancelled queue times out paused','s.cancel=true',done=False)
run('invalid batch count','',qty=17,moves=0,done=False)

lua,program=run('first completed queue')
lua.execute("s.baseline=s.baseline+s.outputs;s.outputs=0;s.started=0;s.completed=0;s.now=0;s.released=nil;s.stock={};s.consumed={};s.sub={};s.quantity=15")
program('run','15')
s=lua.globals().s
assert s.outputs==15 and s.moves==4 and s.output==15
assert s.files['/home/bec_auto_batch.journal.done-1'] is not None
assert list(s.logs.values()).count('批量运行完成：主网原始屏蔽层增加 15，已恢复暂停 15，纠缠装置关闭。')==2
print('completed journal retained and next queue starts: PASS')
