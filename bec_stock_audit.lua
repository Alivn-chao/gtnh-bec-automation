-- Read-only audit: no request, transfer, configuration, or machine mutations.
local c=require("component")
local ser=require("serialization")
local MAIN="3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local SUB="86311657-33d1-41b5-a0d9-0aee7b5c2c50"
local TRANS="66fb280f-080d-4623-8d54-0dffd5cd5aad"
local raw="molten.chromaticglass"
local function show(label,value) print(label..": "..ser.serialize(value,false)) end
local function read(a,m,...)
  if c.methods(a)[m]==nil then return "method missing: "..m end
  local ok,v,reason=pcall(c.invoke,a,m,...)
  if not ok then return "error: "..tostring(v) end
  if v==nil then return "nil: "..tostring(reason) end
  return v
end
for sample=1,3 do
  print("=== 库存快照 "..sample.." ===")
  for _,network in ipairs({{MAIN,"主网"},{SUB,"子网"}}) do
    local rows=read(network[1],"getFluidsInNetwork")
    if type(rows)=="table" then
      local total,count=0,0
      for _,f in pairs(rows) do
        if type(f)=="table" and f.name==raw then
          count=count+1;show(network[2].." 列表条目 "..count,f)
          total=total+(tonumber(f.amount or f.size) or 0)
        end
      end
      print(network[2].." 列表合计 "..total.." mB / "..count.." 条")
    else show(network[2].." 列表",rows) end
    show(network[2].." 单项读取",read(network[1],"getFluidInNetwork",raw))
  end
  if sample<3 then os.sleep(2) end
end
print("=== 接口与实际缓存 ===")
for slot=0,5 do
  local cfg=read(MAIN,"getFluidInterfaceConfiguration",slot)
  if type(cfg)=="table" then show("主网配置槽 "..slot,cfg) end
end
for _,side in ipairs({4,5}) do
  local count=read(TRANS,"getTankCount",side)
  if type(count)=="number" then
    for slot=1,count do
      local f=read(TRANS,"getFluidInTank",side,slot)
      if type(f)=="table" and ((tonumber(f.amount) or 0)>0 or type(f[1])=="table") then
        show("缓存侧 "..side.." 槽 "..slot,f)
      end
    end
  end
end
print("=== AE 运行任务 ===")
local cpus=read(MAIN,"getCpus")
if type(cpus)=="table" then
  for index,row in pairs(cpus) do
    if row.busy==true then
      print("CPU "..index.." "..tostring(row.name))
      if row.cpu then
        for _,getter in ipairs({"finalOutput","activeItems","pendingItems","storedItems"}) do
          local ok,v,reason=pcall(function() return row.cpu[getter]() end)
          if ok and type(v)=="table" then
            if v.name then show(getter,v) else
              for _,item in pairs(v) do
                if type(item)=="table" and (item.name==raw
                  or (item.name=="gregtech:gt.metaitem.03" and tonumber(item.damage)==32307)) then
                  show(getter,item)
                end
              end
            end
          elseif getter=="finalOutput" then print(getter..": "..tostring(v).." "..tostring(reason)) end
        end
      end
    end
  end
else show("CPU",cpus) end
local file=io.open("/home/bec_auto.journal","r")
if file then
  local record=ser.unserialize(file:read("*a"));file:close()
  if type(record)=="table" then
    show("日志阶段",record.stage);show("申请记录",record.requests)
  end
end
print("只读检查结束；没有申请或搬运流体。")
