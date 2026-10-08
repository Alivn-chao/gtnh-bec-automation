-- Read-only commissioning check. Never transfers fluids or changes machine state.
local c = require("component")
local term = require("term")
local report = {}
local lines = 0
local directions = {[0]="下", [1]="上", [2]="北", [3]="南", [4]="西", [5]="东"}
local function out(s)
  s = tostring(s)
  report[#report + 1] = s
  print(s)
  lines = lines + 1
  if lines >= 11 then
    print("按回车继续查看……")
    io.read()
    term.clear()
    lines = 0
  end
end
local function call(address, method, ...)
  local methods = c.methods(address)
  if methods[method] == nil then return false, "无此方法" end
  return pcall(c.invoke, address, method, ...)
end
local addresses = {}
for address in c.list("transposer", true) do
  addresses[#addresses + 1] = address
end
table.sort(addresses)
term.clear()
out("BEC 补料接线检查：只读取")
out("转运器数量：" .. #addresses)
for n, address in ipairs(addresses) do
  out("------------------------------")
  out("转运器 " .. n)
  out(address)
  for side = 0, 5 do
    local ok, count = call(address, "getTankCount", side)
    if not ok or type(count) ~= "number" then
      out("方向 " .. side .. "（" .. directions[side] .. "）：读取失败")
    elseif count == 0 then
      out("方向 " .. side .. "（" .. directions[side] .. "）：无储罐")
    else
      out("方向 " .. side .. "（" .. directions[side] .. "）：" .. count .. " 个槽")
      for tank = 1, count do
        local readOK, fluid = call(address, "getFluidInTank", side, tank)
        if readOK and type(fluid) == "table" then
          -- Some drivers return a list even when a tank index is supplied.
          if fluid.amount == nil and fluid.capacity == nil and type(fluid[1]) == "table" then
            fluid = fluid[tank] or fluid[1]
          end
          out("  槽 " .. tank .. "：" .. tostring(fluid.label or fluid.name or "空"))
          out("  标识：" .. tostring(fluid.name or "空"))
          out("  数量/容量：" .. tostring(fluid.amount or 0) .. "/" .. tostring(fluid.capacity or "未知"))
        else
          out("  槽 " .. tank .. "：无法读取流体详情")
        end
      end
    end
  end
end
out("------------------------------")
out("已连接的 GT 控制器名称：")
for address in c.list("gt_machine", true) do
  local ok, name = call(address, "getName")
  out(address)
  out(ok and tostring(name) or "名称读取失败")
end
local path = "/home/bec_fluid_check_report.txt"
local file, err = io.open(path, "w")
if file then
  local written, writeErr = file:write(table.concat(report, "\n") .. "\n")
  local flushed, flushErr = file:flush()
  local closed, closeErr = file:close()
  if written and flushed and closed ~= false and closeErr == nil then
    print("报告已保存：" .. path)
  else
    print("报告保存失败：" .. tostring(writeErr or flushErr or closeErr))
  end
else
  print("报告无法写入：" .. tostring(err))
end
print("检查结束，本程序没有转移流体。")
