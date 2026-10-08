-- BEC 接线诊断：只读取，不下单、不搬运、不修改机器。
local component = require("component")
local event = require("event")
local term = require("term")
local serialization = require("serialization")
local gpu = component.gpu
local labels = {
  bec_io_node="BEC 传送节点", bec_storage="BEC 约束场",
  bec_diode="BEC 麦克斯韦门", gt_machine="格雷机器",
  transposer="转运器", me_interface="ME 物品接口",
  fluid_interface="ME 流体接口", me_controller="ME 控制器",
  database="数据库"
}
local states = {
  idle="空闲", unpowered="供电不足",
  ["assembler-offline"]="装配主体离线",
  ["nanite-tier-too-low"]="蜂群等级不足",
  ["paused-step"]="阶段暂停", ["paused-immediate"]="立即暂停",
  crafting="制作中", ["internal-error"]="内部错误"
}
local sides = {[0]="下",[1]="上",[2]="北",[3]="南",[4]="西",[5]="东"}
local function read(p, name)
  if not p[name] then return "接口不存在" end
  local ok, value = pcall(p[name])
  if not ok then return "读取失败："..tostring(value) end
  if value == nil then return "无 / 空闲" end
  if type(value)=="table" then return serialization.serialize(value) end
  return states[value] or tostring(value)
end
local function collect()
  local rows={"BEC 中文接线诊断（只读）", ""}
  local function add(s) rows[#rows+1]=s end
  for address, kind in component.list() do
    if labels[kind] then
      local p=component.proxy(address)
      add("["..(labels[kind] or kind).."] "..kind)
      add("地址："..address)
      if kind=="bec_io_node" then
        for _, v in ipairs({{"状态","getState"},{"需要蜂群","getRequiredTier"},
          {"现有蜂群","getProvidedTier"},{"蜂群数量","getAvailableNanites"},
          {"当前并行","getParallelRecipesInProgress"},{"配方阶段","getRecipeSteps"},
          {"需要凝聚物","getRequiredCondensate"},{"已消耗凝聚物","getConsumedCondensate"}}) do
          add(v[1].."："..read(p,v[2]))
        end
      elseif kind=="bec_storage" then
        add("场强："..read(p,"getFieldStrength"))
        add("凝聚物库存："..read(p,"getStoredCondensate"))
      elseif kind=="transposer" then
        for side=0,5 do
          local ok,size=pcall(p.getInventorySize,side)
          if ok and size then
            add("方向 "..side.."（"..sides[side].."）："..size.." 个槽位")
            for slot=1,math.min(size,4) do
              local got,s=pcall(p.getStackInSlot,side,slot)
              if got and s then
                add("  槽 "..slot.."："..tostring(s.label).." ×"..tostring(s.size))
                add("  标识："..tostring(s.name).." / "..tostring(s.damage))
              end
            end
          end
        end
      end
      local methods={}
      for name in pairs(component.methods(address)) do methods[#methods+1]=name end
      table.sort(methods)
      add("方法："..table.concat(methods,", "))
      add("")
    end
  end
  local f,err=io.open("/home/bec_probe_report.txt","w")
  if f then f:write(table.concat(rows,"\n")); f:close()
  else add("报告保存失败："..tostring(err)) end
  return rows
end
local rows=collect()
local top=1
local function draw()
  term.clear()
  local w,h=gpu.getResolution()
  gpu.set(1,1,"BEC 接线诊断 | 上下翻页 | R 刷新 | Q 退出")
  local y=3
  for i=top,math.min(#rows,top+h-5) do
    gpu.set(1,y,require("unicode").wtrunc(rows[i],w)); y=y+1
  end
  gpu.set(1,h,"报告：/home/bec_probe_report.txt")
end
while true do
  draw()
  local _,_,char,code=event.pull("key_down")
  if char==113 or char==81 then break end
  if char==114 or char==82 then rows=collect(); top=1 end
  local _,h=gpu.getResolution()
  if code==200 or code==201 then top=math.max(1,top-(h-5)) end
  if code==208 or code==209 then top=math.min(math.max(1,#rows-h+5),top+h-5) end
end
term.clear()
print("诊断结束。报告已保存到 /home/bec_probe_report.txt")
