-- Read-only: inspect main-network fluid crafting API; never request a job.
local c = require("component")
local ser = require("serialization")
local a = assert(c.get("3afdc4cf"), "主网接口未连接")
local methods = c.methods(a)
print("主网接口: " .. a)
for _, m in ipairs({"getCraftable", "getCraftables", "getCpus"}) do
  print(m .. ": " .. tostring(methods[m] ~= nil))
  if methods[m] ~= nil then print(c.doc(a, m)) end
end
if methods.getCraftables ~= nil then
  for _, name in ipairs({"molten.chromaticglass", "molten.transcendentmetal"}) do
    print("检查原液: " .. name)
    local ok, rows = pcall(c.invoke, a, "getCraftables", {name=name})
    if not ok then
      print("读取失败: " .. tostring(rows))
    elseif type(rows) ~= "table" then
      print("返回类型: " .. type(rows))
    else
      local count = 0
      for _, craft in pairs(rows) do
        count = count + 1
        print("合成对象类型: " .. type(craft))
        for _, getter in ipairs({"getStack", "getItemStack"}) do
          local worked, stack = pcall(function() return craft[getter]() end)
          if worked then print(getter .. ": " .. ser.serialize(stack, false)) end
        end
      end
      print("匹配数量: " .. count)
    end
  end
end
print("检查结束：没有下单、搬液、修改配置或启停机器。")
