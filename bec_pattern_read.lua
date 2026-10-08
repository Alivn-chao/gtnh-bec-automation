-- Read-only. Put the copied pattern in pattern slot 1.
local c = require("component")
local s = require("serialization")
local choices = {}
for a, kind in c.list() do
  local ok, m = pcall(c.methods, a)
  if ok and m.getInterfacePattern ~= nil then
    choices[#choices + 1] = {address = a, kind = kind, methods = m}
  end
end
if #choices == 0 then print("No pattern interface found."); return end
local n = 1
if #choices > 1 then
  for i, v in ipairs(choices) do print(i, v.kind, v.address) end
  io.write("Workshop interface number: ")
  n = tonumber(io.read())
  if not n or not choices[n] then print("Invalid number."); return end
end
local v = choices[n]
print("INTERFACE: " .. v.address)
print("Can edit input: " .. tostring(v.methods.setInterfacePatternInput ~= nil))
print("Can request AE: " .. tostring(v.methods.getCraftables ~= nil))
local ok, p = pcall(c.invoke, v.address, "getInterfacePattern", 1)
if not ok then print("READ ERROR: " .. tostring(p)); return end
if p == nil then print("Pattern slot 1 is empty."); return end
local f, err = io.open("/home/bec_pattern_report.txt", "w")
if not f then print("SAVE ERROR: " .. tostring(err)); return end
f:write("Interface: " .. v.address .. "\n" .. s.serialize(p, true))
f:close()
print("isCraftable: " .. tostring(p.isCraftable))
for _, group in ipairs({"inputs", "outputs"}) do
  print(string.upper(group))
  local entries = p[group]
  if type(entries) ~= "table" then
    print("No decoded entries; see report.")
  else
    for index, entry in pairs(entries) do
      print("ENTRY " .. tostring(index))
      if type(entry) == "table" then
        for _, key in ipairs({"name", "damage", "size", "amount", "type", "fluid", "fluidName"}) do
          local value = entry[key]
          if value ~= nil then
            if type(value) == "table" then value = "[table; see report]" end
            print("  " .. key .. " = " .. tostring(value))
          end
        end
      else
        print(tostring(entry))
      end
      io.write("Press Enter for next entry...")
      io.read()
    end
  end
end
print("DONE: /home/bec_pattern_report.txt")
