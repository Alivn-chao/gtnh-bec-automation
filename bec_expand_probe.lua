-- Read-only setup report for patterns, nanite inventory routing and pre-cache.
local c=require("component")
local ser=require("serialization")
local fs=require("filesystem")
local report,rows={},{}
local function get(a,m,...)
 local ok,value=pcall(c.invoke,a,m,...)
 if ok then return value end
end
local function say(text) rows[#rows+1]=text;print(text) end
local function contains(text)
 text=tostring(text):lower()
 return text:find("nanite",1,true) or text:find("纳米",1,true) or text:find("蜂群",1,true)
end
print("BEC 扩展接线检查（只读，不换蜂群、不改样板、不搬料）")
for a,kind in c.list() do
 if kind=="transposer" or kind=="inventory_controller" then
  local entry={address=a,type=kind,sides={}}
  report[#report+1]=entry
  say(kind.." "..a)
  for side=0,5 do
   local size=get(a,"getInventorySize",side)
   if type(size)=="number" and size>0 then
    local inv={side=side,size=size,name=get(a,"getInventoryName",side),items={}}
    entry.sides[#entry.sides+1]=inv
    say("  side "..side.." 槽数 "..size.." 名称 "..tostring(inv.name))
    for slot=1,math.min(size,512) do
     local f=get(a,"getStackInSlot",side,slot)
     if type(f)=="table" and (tonumber(f.size) or 0)>0 then
      inv.items[#inv.items+1]={slot=slot,stack=f}
      if contains(f.name) or contains(f.label) then
       say("    蜂群候选 slot "..slot.." "..tostring(f.label or f.name).." x"..f.size.." damage="..tostring(f.damage))
      end
     end
    end
   end
  end
 end
end
for _,a in ipairs({"72994a02-7bff-41cb-bfc7-8a541036d7ad","32db4b55-68cc-4ccf-88a7-ed0848d0f960"}) do
 local entry={address=a,type="pattern_interface",methods={},patterns={}}
 report[#report+1]=entry
 local ok,methods=pcall(c.methods,a)
 if ok then for m in pairs(methods) do
  if m:lower():find("pattern",1,true) then
   local readable,doc=pcall(c.doc,a,m)
   entry.methods[m]=readable and tostring(doc) or "available"
  end
 end end
 for slot=1,9 do
  local p=get(a,"getInterfacePattern",slot)
  if type(p)=="table" then
   entry.patterns[#entry.patterns+1]={slot=slot,pattern=p}
   local output=type(p.outputs)=="table" and p.outputs[1]
   say("样板 "..a:sub(1,8).." slot "..slot.." "..tostring(output and (output.label or output.name) or "无解码产物"))
  end
 end
end
local node="b04787f9-5423-4b03-8549-c786d4ef38d0"
local status={type="node",state=get(node,"getState"),provided=get(node,"getProvidedTier"),
 required=get(node,"getRequiredTier"),nanites=get(node,"getAvailableNanites")}
report[#report+1]=status
say("节点 "..tostring(status.state).." 蜂群 "..ser.serialize(status.provided,false).." 数量 "..tostring(status.nanites))
local dir="/home/bec/recipes"
local recipes={type="registry",records={}}
report[#report+1]=recipes
if fs.exists(dir) then
 for name in fs.list(dir) do if name:sub(-4)==".dat" then
  local f=io.open(dir.."/"..name,"r")
  if f then
   local text=f:read("*a");f:close()
   local ok,value=pcall(ser.unserialize,text)
   if ok and type(value)=="table" then recipes.records[#recipes.records+1]={file=name,record=value} end
  end
 end end
end
say("已登记配方 "..#recipes.records)
local path="/home/bec_expand_report.dat"
local f=assert(io.open(path,"w"));assert(f:write(ser.serialize(report,false)));assert(f:flush());f:close()
say("完整接线与样板报告："..path)
