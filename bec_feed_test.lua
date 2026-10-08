-- BEC one-shot feed test v4: live interface config slots are zero-based.
local c = require("component")
local computer = require("computer")
local term = require("term")
local ser = require("serialization")
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50"
local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad"
local FLUID = "molten.chromaticglass"
local AMOUNT = 144
local SLOT = 0 -- Interface configuration: 0..5. Transposer tanks: 1..6.
local touched = false
local transferred
local rows = {}
local function say(value)
  local s = tostring(value)
  print(s)
  rows[#rows+1] = s
end
local function invoke(address, method, ...)
  return c.invoke(address, method, ...)
end
local function requireMethod(address, method)
  assert(c.methods(address)[method] ~= nil, "地址或方法不可用：" .. address .. " / " .. method)
end
local function network(address)
  local fluids = invoke(address, "getFluidsInNetwork")
  assert(type(fluids) == "table", "无法读取 AE 网络库存")
  local amounts, total = {}, 0
  for _, fluid in pairs(fluids) do
    if type(fluid) == "table" then
      local n = tonumber(fluid.amount or fluid.size or 0)
      assert(n and n >= 0, "网络返回了无效流体数量")
      if n > 0 then
        assert(type(fluid.name) == "string", "流体缺少标识")
        amounts[fluid.name] = (amounts[fluid.name] or 0) + n
        total = total + n
      end
    end
  end
  return amounts, total
end
local function tanks(side)
  local count = invoke(TRANS, "getTankCount", side)
  assert(type(count) == "number" and count > 0, "方向没有可读流体槽：" .. side)
  local result = {}
  for index = 1,count do
    local tank = invoke(TRANS, "getFluidInTank", side, index)
    assert(type(tank) == "table", "无法读取相邻接口的流体槽")
    if type(tank[1]) == "table" then tank = tank[index] or tank[1] end
    result[#result+1] = tank
  end
  return result
end
local function cached(side)
  local n = 0
  for _, tank in ipairs(tanks(side)) do
    if tank.name == FLUID then n = n + (tonumber(tank.amount) or 0) end
  end
  return n
end
local function trace()
  say("主网配置回读：" .. ser.serialize(invoke(MAIN,"getFluidInterfaceConfiguration",SLOT)))
  for _, side in ipairs({4,5}) do
    say("方向 " .. side .. " 的储槽：")
    for index,tank in ipairs(tanks(side)) do
      if index == 1 or (tonumber(tank.amount) or 0) > 0 then
        say("槽 " .. index .. "：" .. ser.serialize(tank))
      end
    end
  end
end
local function main()
  term.clear()
  say("BEC 单次调料验收 v4（接口配置槽 0～5）")
  say("主网：" .. MAIN)
  say("子网：" .. SUB)
  say("只搬 144 mB 彩色玻璃原液，不启动机器。")
  say("请先停纠缠装置，约束场储存保持开启。")
  for _,method in ipairs({"setFluidInterfaceConfiguration","getFluidInterfaceConfiguration","getFluidsInNetwork"}) do
    requireMethod(MAIN,method)
  end
  requireMethod(SUB,"getFluidsInNetwork")
  requireMethod(TRANS,"transferFluid")
  local doc = c.doc(MAIN,"setFluidInterfaceConfiguration")
  assert(type(doc)=="string" and doc:find("detail:table",1,true),"驱动参数格式不符合已核对版本")
  for slot = 0,5 do
    assert(invoke(MAIN,"getFluidInterfaceConfiguration",slot)==nil,"供料接口已有流体配置，请先清空")
  end
  local _, beforeTotal = network(SUB)
  assert(beforeTotal==0,"子网已有原液，停止；不要重复加料")
  local stock = network(MAIN)
  assert((stock[FLUID] or 0)>=AMOUNT,"主网原液不足 144 mB；本次验收不自动下单")
  for _,side in ipairs({4,5}) do
    for _,tank in ipairs(tanks(side)) do
      assert((tonumber(tank.amount) or 0)==0,"转运器旁边的接口还有原液缓存，停止")
    end
  end
  say("检查通过：子网为空，主网原液充足。")
  say("输入 T 执行一次搬运，其他输入退出：")
  if string.upper(io.read() or "")~="T" then
    say("已退出，没有修改配置或搬运流体。")
    return
  end
  touched = true
  assert(invoke(MAIN,"setFluidInterfaceConfiguration",SLOT,
    {name=FLUID,size=AMOUNT,amount=AMOUNT})==true,"配置主网接口失败")
  local value = invoke(MAIN,"getFluidInterfaceConfiguration",SLOT)
  assert(value~=nil,"设置返回成功，但配置仍为空；没有搬运")
  local deadline, source = computer.uptime()+20, nil
  repeat
    local west,east = cached(4),cached(5)
    assert(not(west>0 and east>0),"两侧都有原液，无法确定主网方向")
    if west>=AMOUNT then source=4 end
    if east>=AMOUNT then source=5 end
    if not source then os.sleep(0.25) end
  until source or computer.uptime()>=deadline
  if not source then
    trace()
    error("供料接口缓存超时，没有执行搬运")
  end
  local target = source==4 and 5 or 4
  local _, stillEmpty = network(SUB)
  assert(stillEmpty==0,"备料期间子网库存变化，停止")
  say("主网方向：" .. source .. (source==4 and "（西）" or "（东）"))
  say("子网方向：" .. target .. (target==4 and "（西）" or "（东）"))
  -- One transfer call only, including partial-transfer and uncertain-return cases.
  local ok,moved = invoke(TRANS,"transferFluid",source,target,AMOUNT)
  transferred = moved
  say("搬运返回：" .. tostring(ok) .. "，数量：" .. tostring(moved))
  assert(ok==true and type(moved)=="number" and moved==AMOUNT,
    "未确认完整搬运 144 mB，停止；先检查子网，不能直接重跑")
  assert(invoke(MAIN,"setFluidInterfaceConfiguration",SLOT)==true,"无法清除本次主网配置")
  touched = false
  os.sleep(1)
  local after,total = network(SUB)
  assert(total==AMOUNT and after[FLUID]==AMOUNT,
    "子网数量不符；检查纠缠装置是否停机、流体存储元件和网络隔离")
  say("子网库存：彩色玻璃原液 144 mB。")
  say("等待 5 秒检查是否自行增加……")
  os.sleep(5)
  local stable,stableTotal = network(SUB)
  assert(stableTotal==AMOUNT and stable[FLUID]==AMOUNT,"子网库存自行变化，验收未通过")
  say("验收通过：只调入 144 mB，库存保持不变。")
  say("原液留在子网，后续补料会计入已有库存。")
end
local ok,err = xpcall(main,debug.traceback)
if touched then
  local cleaned,result = pcall(invoke,MAIN,"setFluidInterfaceConfiguration",SLOT)
  if cleaned and result==true then
    say("已清除本次供料接口配置。")
  else
    say("请手动清除主网供料接口本次添加的流体配置。")
  end
end
if not ok then
  say("验收停止：" .. tostring(err))
  if transferred~=nil then say("搬运返回数量：" .. tostring(transferred)) end
end
local path = "/home/bec_feed_test_report.txt"
local f = io.open(path,"w")
if f then
  local written = f:write(table.concat(rows,"\n") .. "\n")
  local flushed = f:flush()
  local closed,closeErr = f:close()
  if written and flushed and closed~=false and closeErr==nil then
    print("报告：" .. path)
  else print("报告保存失败，请保留屏幕结果。") end
end
