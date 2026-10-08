-- Recover only the known Primitive Shielding recipe. Does not alter patterns or fluids.
local c=require("component")
local fs=require("filesystem")
local ser=require("serialization")
local term=require("term")
local PATH="/home/bec/recipes/gregtech_gt_metaitem_03_32307_1.dat"
local WORKSHOP="72994a02-7bff-41cb-bfc7-8a541036d7ad"
local function read(path)
  local f,err=io.open(path,"r")
  assert(f,err)
  local value,readErr=f:read("*a")
  f:close()
  assert(type(value)=="string",readErr or "读取失败")
  return value
end
local function run()
  term.clear()
  print("BEC 已确认配方需求记录修复")
  local damaged=read(PATH)
  local old,parseErr=ser.unserialize(damaged)
  if type(old)=="table" and old.state=="converted" then
    print("需求记录已可读取，无需修复。")
    return
  end
  assert(old==nil,"文件可解析但状态不同，停止，避免覆盖其他记录")
  print("原文件无法解析：" .. tostring(parseErr))
  -- The provided screenshot confirms these two quantities in the intact header.
  local header=damaged:sub(1,600)
  assert(header:find("entangled_chromaticglass",1,true)
    and header:find("entangled_transcendentmetal",1,true),"损坏文件前部没有两种已确认凝聚物，停止")
  local _,count=header:gsub("amount%s*=%s*288[^%d]","")
  assert(count>=2,"损坏文件前部没有两项 288 数量，停止")
  assert(c.methods(WORKSHOP).getInterfacePattern~=nil,"无法读取转换工作台")
  local p=c.invoke(WORKSHOP,"getInterfacePattern",1)
  assert(type(p)=="table","转换工作台第一个样板槽为空，请放入已转换样板")
  assert(p.isCraftable==false,"需要加工样板")
  assert(type(p.outputs)=="table" and #p.outputs==1,"样板产物数量不符")
  local output=p.outputs[1]
  assert(output.name=="gregtech:gt.metaitem.03" and output.damage==32307 and output.size==1,
    "工作台里的样板不是 Primitive Shielding ×1")
  assert(type(p.inputs)=="table" and #p.inputs==5,"需要已经去掉两种凝聚物的五项普通输入样板")
  for _,input in ipairs(p.inputs) do
    assert(type(input.name)=="string" and not input.name:find("entangled_",1,true),"样板仍包含纠缠凝聚物")
  end
  local record={version=1,state="converted",interface=WORKSHOP,slot=1,
    ordinaryInputs=p.inputs,outputs=p.outputs,convertedPattern=p,
    recovered=true,condensates={
      {name="entangled_chromaticglass",amount=288,index=6},
      {name="entangled_transcendentmetal",amount=288,index=7}
    }}
  print("已核对：Primitive Shielding ×1，五项普通输入。")
  print("恢复需求：彩色玻璃凝聚物 288，超时空金属凝聚物 288。")
  print("原损坏文件会保留备份，不修改样板或搬运流体。")
  print("输入 R 修复，其他输入退出：")
  if string.upper(io.read() or "")~="R" then print("已退出。") return end
  local payload=ser.serialize(record,false)
  local temporary=PATH..".repair.tmp"
  local file,openErr=io.open(temporary,"w")
  assert(file,openErr)
  local written,writeErr=file:write(payload)
  local flushed,flushErr=file:flush()
  local closed,closeErr=file:close()
  assert(written,writeErr or "写入失败")
  assert(flushed,flushErr or "刷新失败；请检查磁盘空间")
  assert(closed~=false and closeErr==nil,closeErr or "关闭失败")
  local reread=read(temporary)
  assert(reread==payload,"新记录写入不完整；原文件未替换，请检查磁盘空间")
  local verified,verifyErr=ser.unserialize(reread)
  assert(type(verified)=="table" and verified.state=="converted",verifyErr or "新记录无法解析")
  local number=1
  while fs.exists(PATH..".broken"..number) do number=number+1 end
  local backup=PATH..".broken"..number
  assert(fs.rename(PATH,backup),"无法备份原记录")
  local moved,moveErr=fs.rename(temporary,PATH)
  if not moved then
    local restored,restoreErr=fs.rename(backup,PATH)
    error("新记录替换失败：" .. tostring(moveErr) .. "; 原文件还原：" .. tostring(restored) .. " " .. tostring(restoreErr))
  end
  assert(read(PATH)==payload,"替换后读回不一致；原文件保留在 " .. backup)
  print("修复成功：新记录已完整写入并读回核对。")
  print("损坏文件备份：" .. backup)
  print("可以重新运行：lua /home/bec_prepare.lua")
end
local ok,err=xpcall(run,debug.traceback)
if not ok then print("修复停止：" .. tostring(err)) end
