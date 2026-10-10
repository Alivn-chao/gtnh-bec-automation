-- Hardware reads only. No configuration, transfer, crafting or journal writes.
local c=require('component')
local ser=require('serialization')
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local GATE='cf2a0c4a-ab8d-4958-b1df-253094d6690c'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0'
local function read(address,method)
  local ok,methods=pcall(c.methods,address)
  if not ok or methods[method]==nil then
    print(address..' '..method..': 方法不可用');return
  end
  local success,value=pcall(c.invoke,address,method)
  print(address..' '..method..': '..(type(value)=='table' and ser.serialize(value,false) or tostring(value)))
  if not success then print('读取失败，未修改设备。') end
end
print('BEC 凝聚物只读检查；不启动或重试失败订单。')
for _,method in ipairs({'getState','getParallelRecipesInProgress','getRequiredCondensate',
  'getConsumedCondensate','getSlowdowns','getProvidedTier','getAvailableNanites'}) do read(NODE,method) end
for _,method in ipairs({'isWorkAllowed','isMachineActive','getCondensateFilters'}) do read(GATE,method) end
read(FIELD,'isWorkAllowed');read(FIELD,'getStoredCondensate')
for address,kind in c.list() do
  if address~=FIELD and (kind=='bec_storage' or kind=='gt_machine') then
    local ok,methods=pcall(c.methods,address)
    if ok and methods.getStoredCondensate~=nil then read(address,'getStoredCondensate') end
  end
end
print('检查结束。门过滤正确及储存有料，仍不能单独证明装配端可达；需核对门的两个BEC仓接线。')
