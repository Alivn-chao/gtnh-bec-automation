import sys
from pathlib import Path
sys.path.insert(0, str(Path('work/lua_runtime').resolve()))
from lupa.lua52 import LuaRuntime

source = Path('bec_convert.lua').read_text(encoding='utf-8')
setup = r'''
function clone(t)
  if type(t)~='table' then return t end
  local r={} for k,v in pairs(t) do r[k]=clone(v) end return r
end
pattern={isCraftable=false,inputs={},outputs={{name='gregtech:gt.metaitem.03',damage=32307,size=1,hasTag=false}}}
for i=1,5 do pattern.inputs[i]={name='item_'..i,damage=i,size=i,hasTag=i==1,tag=i==1 and {test='keep'} or nil} end
pattern.inputs[6]={name='entangled_chromaticglass',size=288,amount=288}
pattern.inputs[7]={name='entangled_transcendentmetal',size=288,amount=288}
original=clone(pattern)
files={} records={} logs={} deletions={} writeCount=0 readCount=0
choice='c' failClear=false corruptRead=false failFlush=false failClose=false
package.preload.component=function()
  return {
    methods=function() return {getInterfacePattern=false,clearInterfacePatternInput=false,setInterfacePatternInput=false} end,
    invoke=function(a,m,slot,index,detail,tp)
      if m=='getInterfacePattern' then
        readCount=readCount+1
        local r=clone(pattern)
        if corruptRead and readCount==3 then r.outputs[1].size=99 end
        return r
      elseif m=='clearInterfacePatternInput' then
        if failClear and index==6 then error('simulated driver failure') end
        deletions[#deletions+1]=index
        table.remove(pattern.inputs,index)
        return true
      elseif m=='setInterfacePatternInput' then
        assert(tp=='fluid')
        pattern.inputs[index]=clone(detail)
        return true
      end
      error(m)
    end
  }
end
package.preload.filesystem=function()
  return {
    exists=function(p) return files[p]~=nil end,
    makeDirectory=function() return true end,
    remove=function(p) files[p]=nil return true end,
    rename=function(a,b)
      if not files[a] then return nil,'missing source' end
      if files[b] then return nil,'destination exists' end
      files[b]=files[a] files[a]=nil return true
    end
  }
end
package.preload.serialization=function()
  return {serialize=function(value)
    writeCount=writeCount+1
    local key='record_'..writeCount
    records[key]=clone(value)
    return key
  end}
end
package.preload.term=function() return {clear=function() end} end
print=function(...) local r={} for i=1,select('#',...) do r[i]=tostring(select(i,...)) end logs[#logs+1]=table.concat(r,' ') end
io.write=function() end
io.read=function() return choice end
io.open=function(path)
  local f={}
  function f:write(s) files[path]=s return self end
  function f:read() return files[path] end
  function f:flush() if failFlush then return nil,'simulated full disk' end return self end
  function f:close() if failClose then return nil,'simulated close failure' end end
  return f
end
function same(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~='table' then return a==b end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
function saved()
  for path,data in pairs(files) do if path:sub(-4)=='.dat' then return records[data] end end
end
'''

cases = [
    ('convert and preserve tagged ordinary input', '', "assert(#pattern.inputs==5); assert(deletions[1]==7 and deletions[2]==6); for i=1,5 do assert(same(pattern.inputs[i],original.inputs[i])) end; assert(same(pattern.outputs,original.outputs)); assert(saved().state=='converted'); assert(saved().condensates[1].amount==288); assert(#saved().condensates==2)"),
    ('cancel leaves copy untouched', "choice='q'", "assert(same(pattern,original)); assert(writeCount==0); assert(#deletions==0)"),
    ('driver failure restores fluid tail', "failClear=true", "assert(same(pattern,original)); assert(saved().state=='restored')"),
    ('failed readback verification restores copy', "corruptRead=true", "assert(same(pattern,original)); assert(saved().state=='restored')"),
    ('existing record is preserved', "files['/home/bec/recipes/gregtech_gt_metaitem_03_32307_1.dat']='existing'", "assert(same(pattern,original)); assert(writeCount==0); assert(#deletions==0)"),
    ('already converted copy is not modified', "table.remove(pattern.inputs,7); table.remove(pattern.inputs,6); original=clone(pattern)", "assert(same(pattern,original)); assert(writeCount==0); assert(#deletions==0)"),
    ('flush failure stops before pattern mutation', "failFlush=true", "assert(same(pattern,original)); assert(#deletions==0); assert(saved()==nil)"),
    ('close error stops before pattern mutation', "failClose=true", "assert(same(pattern,original)); assert(#deletions==0); assert(saved()==nil)"),
]
for name, scenario, assertions in cases:
    lua = LuaRuntime()
    lua.execute(setup)
    lua.execute(scenario)
    lua.execute(source)
    lua.execute(assertions)
    print('PASS:', name)
