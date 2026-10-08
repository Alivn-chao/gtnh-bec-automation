-- BEC pattern converter v1. Converts a copied pattern in workshop slot 1.
-- Ordinary inputs and outputs are left untouched. Only trailing entangled fluids are removed.
local c = require("component")
local fs = require("filesystem")
local ser = require("serialization")
local term = require("term")
local ADDRESS = "72994a02-7bff-41cb-bfc7-8a541036d7ad"
local SLOT = 1
local DIR = "/home/bec/recipes"
local names = {
  entangled_chromaticglass = "纠缠彩色玻璃凝聚物",
  entangled_transcendentmetal = "纠缠超时空金属凝聚物"
}
local function equal(a,b)
  if type(a)~=type(b) then return false end
  if type(a)~="table" then return a==b end
  for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function save(path,value)
  local payload=ser.serialize(value,false)
  local f,err=io.open(path..".tmp","w")
  assert(f,err)
  local ok,writeErr=f:write(payload)
  local flushed,flushErr=f:flush()
  local closed,closeErr=f:close()
  assert(ok,writeErr or "写入需求记录失败。")
  assert(flushed,flushErr or "刷新需求记录失败，请检查磁盘空间。")
  assert(closed~=false and closeErr==nil,closeErr or "关闭需求记录失败。")
  local check,checkErr=io.open(path..".tmp","r")
  assert(check,checkErr)
  local reread=check:read("*a")
  check:close()
  assert(reread==payload,"需求记录写入不完整，原记录未替换。")
  local previous=path..".prev"
  local hadPrevious=fs.exists(path)
  if hadPrevious then
    if fs.exists(previous) then assert(fs.remove(previous),"无法清理旧的临时记录。") end
    local kept,keepErr=fs.rename(path,previous)
    assert(kept,keepErr)
  end
  local moved,moveErr=fs.rename(path..".tmp",path)
  if not moved then
    if hadPrevious then fs.rename(previous,path) end
    error(moveErr or "无法保存需求记录。")
  end
  if hadPrevious then fs.remove(previous) end
end
local function read()
  local p=c.invoke(ADDRESS,"getInterfacePattern",SLOT)
  assert(type(p)=="table","第一个样板槽没有可读取的编码样板。")
  assert(p.isCraftable==false,"请使用加工样板。")
  assert(type(p.inputs)=="table" and type(p.outputs)=="table","样板没有解码输入/输出。")
  return p
end
local function run()
  term.clear()
  print("BEC 样板转换器 v1")
  print("读取右侧转换接口的第一个样板槽。")
  local methods=c.methods(ADDRESS)
  for _,m in ipairs({"getInterfacePattern","clearInterfacePatternInput","setInterfacePatternInput"}) do
    assert(methods[m]~=nil,"接口缺少方法："..m)
  end
  local p=read()
  assert(#p.outputs==1,"本版先支持单产物样板。")
  local output=p.outputs[1]
  assert(type(output.name)=="string","无法识别产物。")
  assert(not output.hasTag,"本版暂不转换带 NBT 的产物。")
  local ordinary,fluids,remove={},{},{}
  local reachedFluid=false
  for i,input in ipairs(p.inputs) do
    assert(type(input)=="table" and type(input.name)=="string","输入条目无有效标识。")
    if input.name:sub(1,10)=="entangled_" then
      reachedFluid=true
      local quantity=tonumber(input.size or input.amount)
      assert(quantity and quantity>0 and quantity%1==0,"凝聚物数量无效。")
      if input.size and input.amount then
        assert(input.size==input.amount,"流体的 size 和 amount 不一致。")
      end
      fluids[#fluids+1]={name=input.name,amount=quantity,index=i}
      remove[#remove+1]=i
    else
      assert(not reachedFluid,"特殊流体后还有普通材料，本版不改这种排列。")
      ordinary[#ordinary+1]=input
    end
  end
  if #fluids==0 then
    print("没有纠缠凝聚物输入：样板可能已经转换；未做修改。")
    print("OC 需求数据保存在："..DIR)
    return
  end
  assert(#ordinary>0,"不能生成没有普通输入的加工样板。")
  local key=output.name:gsub("[^%w_]","_").."_"..tostring(output.damage or 0).."_"..tostring(output.size or 1)
  local path=DIR.."/"..key..".dat"
  fs.makeDirectory(DIR)
  assert(not fs.exists(path),"此产物已有需求记录。先保留它，避免覆盖之前的数据："..path)
  print("产物："..tostring(output.label or output.name).." × "..tostring(output.size or 1))
  print("保留普通输入："..#ordinary.." 项")
  print("交给 OC 补充：")
  for _,f in ipairs(fluids) do
    print("  "..(names[f.name] or f.name).."："..f.amount.." mB")
  end
  print("请确认这里放的是原样板的副本。")
  io.write("输入 C 转换；其他输入退出：")
  if tostring(io.read()):lower()~="c" then print("已退出，未修改。"); return end
  assert(equal(read(),p),"样板在预览后发生变化，未转换。")
  local record={version=1,state="prepared",interface=ADDRESS,slot=SLOT,
    original=p,ordinaryInputs=ordinary,outputs=p.outputs,condensates=fluids}
  save(path,record)
  local changed=false
  local ok,err=xpcall(function()
    for i=#remove,1,-1 do
      changed=true
      local result=c.invoke(ADDRESS,"clearInterfacePatternInput",SLOT,remove[i])
      assert(result~=false,"清除输入失败。")
    end
    local after=read()
    assert(equal(after.inputs,ordinary),"转换后的普通输入与原样板不一致。")
    assert(equal(after.outputs,p.outputs),"转换后的产物与原样板不一致。")
    record.state="converted"
    save(path,record)
  end,debug.traceback)
  if not ok then
    print("转换未完成："..tostring(err))
    if changed then
      local restored,restoreErr=pcall(function()
        for _,f in ipairs(fluids) do
          c.invoke(ADDRESS,"setInterfacePatternInput",SLOT,f.index,
            {name=f.name,size=f.amount,amount=f.amount},"fluid")
        end
        assert(equal(read(),p),"还原核对失败。")
      end)
      record.state=restored and "restored" or "needs_manual_restore"
      record.error=tostring(err)
      record.restoreError=not restored and tostring(restoreErr) or nil
      pcall(save,path,record)
      if restored then print("原样板内容已还原。")
      else print("请取出这张副本，用保留的原样板重新复制。") end
    end
    print("保留需求记录用于排查："..path)
    return
  end
  print("")
  print("转换成功：普通材料与产物核对通过。")
  print("凝聚物需求已保存："..path)
  print("保留这张转换样板；暂时留在工作台，不要接生产。")
end
local ok,err=xpcall(run,debug.traceback)
if not ok then print("转换器停止："..tostring(err)) end
