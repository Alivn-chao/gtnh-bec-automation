-- Read a copied processing pattern from interface pattern slot 1.
-- Read-only: this version does not edit patterns or request crafting.
local component=require("component")
local serialization=require("serialization")
local choices={}
for address,kind in component.list() do
  local ok,methods=pcall(component.methods,address)
  if ok and methods.getInterfacePattern~=nil then
    choices[#choices+1]={address=address,kind=kind,methods=methods}
  end
end
table.sort(choices,function(a,b) return a.address<b.address end)
if #choices==0 then print("No pattern-readable interface. Connect an adapter to a full ME interface block."); return end
local choice=1
if #choices>1 then
  print("Choose the pattern workshop interface:")
  for i,v in ipairs(choices) do print(i,v.kind,v.address) end
  io.write("Number: ")
  choice=tonumber(io.read())
  if not choice or choice%1~=0 or not choices[choice] then print("Invalid selection."); return end
end
local v=choices[choice]
print("INTERFACE: "..v.address)
for _,name in ipairs({"getInterfacePattern","setInterfacePatternInput",
  "setInterfacePatternOutput","clearInterfacePatternInput",
  "getCraftables","getItemsInNetwork","getFluidsInNetwork"}) do
  print(name..": "..(v.methods[name]~=nil and "YES" or "NO"))
end
local ok,p=pcall(component.invoke,v.address,"getInterfacePattern",1)
if not ok then print("READ ERROR: "..tostring(p)); return end
if p==nil then print("Pattern slot 1 is empty. Put an encoded processing pattern there."); return end
local f,err=io.open("/home/bec_pattern_report.txt","w")
if f then
  f:write("Interface: "..v.address.."\n"..serialization.serialize(p,true))
  f:close()
else print("SAVE ERROR: "..tostring(err)) end
print("isCraftable: "..tostring(p.isCraftable))
local function ascii(s)
  return tostring(s):gsub("[\128-\255]",function(c)
    return string.format("\\x%02X",string.byte(c))
  end)
end
local function dump(t,indent,depth)
  if type(t)~="table" then print(indent..ascii(t)); return end
  if depth>5 then print(indent.."[nested data; see report]"); return end
  local keys={}
  for k in pairs(t) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  for _,k in ipairs(keys) do
    if k~="label" and k~="tag" and k~="nbt" then
      if type(t[k])=="table" then
        print(indent..ascii(k)..":"); dump(t[k],indent.."  ",depth+1)
      else print(indent..ascii(k).." = "..ascii(t[k])) end
    end
  end
end
for _,group in ipairs({"inputs","outputs"}) do
  print("\n"..string.upper(group))
  local entries=p[group]
  if type(entries)~="table" then print("No decoded entries. See report.")
  else
    local keys={}
    for k in pairs(entries) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do
      print("ENTRY "..tostring(k)); dump(entries[k],"  ",0)
      io.write("Press Enter for next entry..."); io.read()
    end
  end
end
print("DONE: /home/bec_pattern_report.txt")
