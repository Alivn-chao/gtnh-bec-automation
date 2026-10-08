"""Workshop multi-slot automation mocks; no Minecraft hardware claim."""
import ast
import sys
from pathlib import Path
sys.path.insert(0,str(Path('work/lua_runtime').resolve()))
from lupa.lua52 import LuaRuntime
tree=ast.parse(Path('test_bec_convert.py').read_text(encoding='utf-8'))
base=next(n.value.value for n in tree.body if isinstance(n,ast.Assign)
          and any(isinstance(t,ast.Name) and t.id=='setup' for t in n.targets))
extra=r'''
local c=require('component');local old=c.invoke
patterns={[1]=pattern};clears=0;ticks=0
function c.invoke(a,m,slot,...)
 if m=='getInterfacePattern' then return patterns[slot] and clone(patterns[slot]) end
 if m=='clearInterfacePatternInput' then clears=clears+1 end
 local savedPattern=pattern;pattern=patterns[slot]
 local result={pcall(old,a,m,slot,...)};patterns[slot]=pattern;pattern=savedPattern
 if not result[1] then error(result[2]) end
 return table.unpack(result,2)
end
require('serialization').unserialize=function(text) return clone(records[text]) end
package.preload.event=function() return {pull=function()
 ticks=ticks+1
 if addLater and ticks==1 then patterns[9]=clone(original);patterns[9].outputs[1].damage=999 end
 if ticks>=3 then return 'key_down','keyboard',113 end
end} end
'''
source=Path('bec_patterns.lua').read_text(encoding='utf-8')
passed=0
def run(label,scenario='',assertions='',mode='run'):
    global passed
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(base+extra);lua.execute(scenario)
    program=lua.eval('function(...) '+source+'\nend');program(mode)
    lua.execute(assertions);passed+=1;print(label+': PASS')
    return lua,program

run('preview does not write or edit',assertions='assert(writeCount==0 and clears==0 and same(patterns[1],original))',mode='preview')
run('single copied pattern preserves ordinary inputs and outputs',assertions="assert(#patterns[1].inputs==5 and clears==2 and saved().state=='converted');assert(same(patterns[1].outputs,original.outputs));for i=1,5 do assert(same(patterns[1].inputs[i],original.inputs[i])) end")
run('nine slots scanned and registered',"for i=2,9 do patterns[i]=clone(original);patterns[i].outputs[1].damage=32307+i end","assert(clears==18);for i=1,9 do assert(#patterns[i].inputs==5) end")
lua,program=run('already converted pattern not processed twice',assertions='assert(clears==2)')
before=lua.globals().writeCount;program('run')
assert lua.globals().clears==2 and lua.globals().writeCount==before
run('second original copy reuses verified registration',"patterns[2]=clone(original)","assert(clears==4);assert(#patterns[2].inputs==5);assert(writeCount==2)")
run('conflicting same product does not overwrite record',"patterns[2]=clone(original);patterns[2].inputs[6].amount=576;patterns[2].inputs[6].size=576","assert(clears==2);assert(saved().condensates[1].amount==288);assert(#patterns[2].inputs==7)")
run('watch discovers new copied pattern',"addLater=true","assert(clears==4 and ticks==3 and #patterns[9].inputs==5)",mode='watch')
run('fluid removal error restores original',"failClear=true","assert(same(patterns[1],original));assert(saved().state=='restored')")
run('flush failure before editing',"failFlush=true","assert(clears==0 and same(patterns[1],original))")
run('existing incomplete record blocks retry',"local v={state='prepared',original=original};records['incomplete']=v;files['/home/bec/recipes/gregtech_gt_metaitem_03_32307_1.dat']='incomplete'","assert(clears==0 and writeCount==0)")
run('unregistered stripped pattern does not invent demand',"table.remove(patterns[1].inputs,7);table.remove(patterns[1].inputs,6)","assert(clears==0 and writeCount==0)")
run('NBT product stays untouched',"patterns[1].outputs[1].hasTag=true","assert(clears==0 and writeCount==0)")
run('interleaved condensate stays untouched',"patterns[1].inputs[8]={name='other',size=1}","assert(clears==0 and writeCount==0)")
run('new entangled type demand is registered',"patterns[1].inputs[6].name='entangled_new_type'","assert(saved().condensates[1].name=='entangled_new_type' and clears==2)")
uncertain="""
local c=require('component');local previous=c.invoke;local fired=false
c.invoke=function(a,m,...)
 local result={previous(a,m,...)}
 if m=='clearInterfacePatternInput' and not fired then fired=true;error('uncertain clear return') end
 return table.unpack(result)
end
"""
run('uncertain clear restores from actual prefix without retry',uncertain,"assert(clears==1 and same(patterns[1],original) and saved().state=='restored')")
race="""
local c=require('component');local previous=c.invoke;local reads=0
c.invoke=function(a,m,slot,...)
 if m=='getInterfacePattern' then
  reads=reads+1;if reads==4 then patterns[slot].inputs[1].name='edited_by_user' end
 end
 return previous(a,m,slot,...)
end
"""
run('concurrent edit stops and is not overwritten',race,"assert(clears==1 and patterns[1].inputs[1].name=='edited_by_user' and saved().state=='needs_manual_restore')")
print(f'{passed} pattern scenarios passed (mock only).')
