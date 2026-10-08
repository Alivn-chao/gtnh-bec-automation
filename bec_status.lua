-- Read-only BEC commissioning. Never moves items or changes machines.
local component = require("component")
local rows = {"BEC STATUS CHECK - READ ONLY", ""}
local function add(s) rows[#rows+1] = tostring(s) end
local function ascii(v)
  return tostring(v):gsub("[\128-\255]", function(c)
    return string.format("\\x%02X", string.byte(c))
  end)
end
local function show(value, prefix, depth)
  prefix = prefix or "  "
  depth = depth or 0
  if type(value) ~= "table" then add(prefix..ascii(value)); return end
  if depth >= 5 then add(prefix.."[nested table]"); return end
  local keys = {}
  for k in pairs(value) do keys[#keys+1] = k end
  table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
  if #keys == 0 then add(prefix.."[empty]") end
  for _,k in ipairs(keys) do
    if type(value[k]) == "table" then
      add(prefix..ascii(k)..":")
      show(value[k],prefix.."  ",depth+1)
    else add(prefix..ascii(k).." = "..ascii(value[k])) end
  end
end
local function call(address, methods, name, ...)
  add(name..":")
  if methods[name] == nil then add("  NOT AVAILABLE"); return end
  local ok,value = pcall(component.invoke,address,name,...)
  if ok then show(value) else add("  ERROR: "..ascii(value)) end
end
local selected = {
  bec_io_node=true,bec_storage=true,gt_machine=true,
  fluid_interface=true,me_interface=true,me_controller=true,transposer=true
}
local ok,err = xpcall(function()
  for address,kind in component.list() do
    if selected[kind] then
      add("COMPONENT: "..kind); add(address)
      local got,methods = pcall(component.methods,address)
      if not got then add("METHOD ERROR: "..ascii(methods))
      else
        if kind=="bec_storage" then
          call(address,methods,"getFieldStrength")
          call(address,methods,"getStoredCondensate")
        elseif kind=="bec_io_node" then
          for _,name in ipairs({"getState","getRequiredTier","getProvidedTier",
            "getAvailableNanites","getMinParallel","getMaxParallel",
            "getParallelRecipesInProgress","getRequiredCondensate",
            "getConsumedCondensate","getRecipeSteps"}) do
            call(address,methods,name)
          end
        elseif kind=="transposer" then
          for side=0,5 do
            add("SIDE "..side)
            call(address,methods,"getInventorySize",side)
            if methods.getInventorySize ~= nil then
              local gotSize,size=pcall(component.invoke,address,"getInventorySize",side)
              if gotSize and type(size)=="number" and size>0 then
                for slot=1,math.min(size,4) do
                  local gotStack,stack=pcall(component.invoke,address,"getStackInSlot",side,slot)
                  if gotStack and stack then
                    add("  SLOT "..slot.." ITEM "..ascii(stack.name)..
                      " DAMAGE "..ascii(stack.damage).." COUNT "..ascii(stack.size))
                  elseif not gotStack then add("  SLOT ERROR: "..ascii(stack)) end
                end
              end
            end
          end
        end
        add("AVAILABLE METHODS:")
        local names={}
        for name in pairs(methods) do names[#names+1]=name end
        table.sort(names)
        for _,name in ipairs(names) do add("  "..name) end
      end
      add("")
    end
  end
end,debug.traceback)
if not ok then add("CHECK ERROR: "..ascii(err)) end
local f,writeErr=io.open("/home/bec_status_report.txt","w")
if f then f:write(table.concat(rows,"\n")); f:close()
else add("SAVE ERROR: "..ascii(writeErr)) end
for i,line in ipairs(rows) do
  print(line)
  if i%12==0 and i<#rows then
    io.write("Press Enter to continue..."); io.read()
  end
end
print("DONE: /home/bec_status_report.txt")
