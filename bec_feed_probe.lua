-- Read-only: discover actual interface API and transposer sides.
local c = require("component")
local term = require("term")
local rows = {}
local line = 0
local direction = {[0]="下",[1]="上",[2]="北",[3]="南",[4]="西",[5]="东"}
local function out(value)
  value = tostring(value)
  rows[#rows+1] = value
  print(value)
  line = line + 1
  if line >= 11 then
    print("按回车继续……")
    io.read()
    term.clear()
    line = 0
  end
end
term.clear()
out("BEC 调料接口检查（只读取）")
for address, kind in c.list() do
  if kind == "fluid_interface" or kind == "me_interface" then
    out("----------------------------")
    out(kind)
    out(address)
    local methods = c.methods(address)
    if methods.setFluidInterfaceConfiguration ~= nil then
      local ok, doc = pcall(c.doc, address, "setFluidInterfaceConfiguration")
      out("设置方法说明：")
      out(ok and tostring(doc) or "说明无法读取")
    end
    if methods.getFluidInterfaceConfiguration ~= nil then
      local ok = pcall(c.invoke, address, "getFluidInterfaceConfiguration", 0)
      out("读取第 0 槽：" .. (ok and "调用成功" or "调用失败"))
    end
    if methods.getFluidsInNetwork ~= nil then
      local ok, fluids = pcall(c.invoke, address, "getFluidsInNetwork")
      if ok and type(fluids) == "table" then
        local types = 0
        for _, fluid in pairs(fluids) do
          if type(fluid) == "table" then
            types = types + 1
            local name = tostring(fluid.name or "")
            if name:find("chromatic",1,true) or name:find("chronomatic",1,true) or name:find("transcendent",1,true) then
              out("原液候选：" .. name)
              out("数量：" .. tostring(fluid.amount or fluid.size or "未知"))
            end
          end
        end
        out("网络可见流体种类：" .. types)
      else
        out("网络流体读取失败")
      end
    end
  end
end
for address in c.list("transposer",true) do
  out("----------------------------")
  out("转运器：")
  out(address)
  for side = 0,5 do
    local ok, count = pcall(c.invoke,address,"getTankCount",side)
    if ok and type(count) == "number" and count > 0 then
      out("方向 " .. side .. "（" .. direction[side] .. "）：" .. count .. " 个流体槽")
      local readOK, tank = pcall(c.invoke,address,"getFluidInTank",side,1)
      if readOK and type(tank) == "table" then
        if type(tank[1]) == "table" then tank = tank[1] end
        out("首槽：" .. tostring(tank.name or "空") .. " / " .. tostring(tank.amount or 0) .. " mB")
      end
    end
  end
end
local path = "/home/bec_feed_probe_report.txt"
local f, err = io.open(path,"w")
if f then
  local written, writeErr = f:write(table.concat(rows,"\n") .. "\n")
  local flushed, flushErr = f:flush()
  local closed, closeErr = f:close()
  if written and flushed and closed ~= false and closeErr == nil then
    print("报告：" .. path)
  else
    print("报告保存失败：" .. tostring(writeErr or flushErr or closeErr))
  end
else
  print("报告无法写入：" .. tostring(err))
end
print("结束。本程序没有配置接口或转移流体。")
