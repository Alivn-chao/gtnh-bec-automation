-- Read-only live BEC status. No inventory transfers or configuration changes.
local c = require("component")
local s = require("serialization")
local rows = {"BEC 当前状态（只读，无翻页）"}
local function add(v) rows[#rows + 1] = tostring(v) end
local function get(a, name, ...)
  local ok, value = pcall(c.invoke, a, name, ...)
  if not ok then return "读取失败: " .. tostring(value) end
  if type(value) == "table" then return s.serialize(value, false) end
  return tostring(value)
end
local foundStorage, foundNode = false, false
for a, kind in c.list() do
  if kind == "bec_storage" then
    foundStorage = true
    add("约束场 " .. a)
    add("  库存: " .. get(a, "getStoredCondensate"))
    add("  场强: " .. get(a, "getFieldStrength"))
  elseif kind == "bec_io_node" then
    foundNode = true
    add("传送节点 " .. a)
    add("  状态: " .. get(a, "getState"))
    add("  当前并行: " .. get(a, "getParallelRecipesInProgress") ..
      "  设置: " .. get(a, "getMinParallel") .. " / " .. get(a, "getMaxParallel"))
    add("  蜂群: " .. get(a, "getProvidedTier") .. "  数量: " .. get(a, "getAvailableNanites"))
    add("  需要蜂群: " .. get(a, "getRequiredTier"))
    add("  凝聚物需求: " .. get(a, "getRequiredCondensate"))
    add("  已消耗: " .. get(a, "getConsumedCondensate"))
  elseif kind == "gt_machine" then
    add("机器 " .. a .. " " .. get(a, "getName"))
    add("  启用: " .. get(a, "isWorkAllowed") .. "  运行: " .. get(a, "isMachineActive") ..
      "  进度: " .. get(a, "getWorkProgress") .. " / " .. get(a, "getWorkMaxProgress"))
  end
end
if not foundStorage then add("未找到 bec_storage：检查约束场的 OC 适配器连接。") end
if not foundNode then add("未找到 bec_io_node：检查传送节点的 OC 适配器连接。") end
local transposer = "66fb280f-080d-4623-8d54-0dffd5cd5aad"
for _, side in ipairs({4, 5}) do
  local label = side == 4 and "主网接口缓存" or "子网接收接口缓存"
  local ok, tanks = pcall(c.invoke, transposer, "getFluidInTank", side)
  if not ok then
    add(label .. ": 读取失败 " .. tostring(tanks))
  elseif type(tanks) ~= "table" then
    add(label .. ": 未读到储槽")
  else
    local fluids = {}
    for _, tank in pairs(tanks) do
      if type(tank) == "table" and tonumber(tank.amount) and tank.amount > 0 then
        fluids[#fluids + 1] = tostring(tank.name or tank.label or "未知流体") .. "=" .. tank.amount .. " mB"
      end
    end
    add(label .. ": " .. (#fluids == 0 and "空" or table.concat(fluids, ", ")))
  end
end
add("注意：接口缓存为空，不代表子网存储元件中的原液为空。")
local path = "/home/bec_live_status_report.txt"
local f, err = io.open(path, "w")
if f then
  local written, writeErr = f:write(table.concat(rows, "\n") .. "\n")
  local flushed, flushErr = f:flush()
  f:close()
  if written and flushed then add("报告: " .. path)
  else add("报告保存失败: " .. tostring(writeErr or flushErr)) end
else add("报告保存失败: " .. tostring(err)) end
for _, line in ipairs(rows) do print(line) end
