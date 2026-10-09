local mode=(...) or "preview"
local c=require("component")
local fs=require("filesystem")
local ser=require("serialization")
local event=require("event")
local ADDRESS="72994a02-7bff-41cb-bfc7-8a541036d7ad"
local DIR="/home/bec/recipes"
local announced={}
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function read(slot) return c.invoke(ADDRESS,"getInterfacePattern",slot) end
local function load(path)
 local f=assert(io.open(path,"r"));local text=f:read("*a");f:close()
 local value=ser.unserialize(text);assert(type(value)=="table","配方记录损坏，保留原文件")
 return value
end
local function save(path,record)
 local text=ser.serialize(record,false)
 local f=assert(io.open(path..".tmp","w"))
 assert(f:write(text),"配方记录写入失败");assert(f:flush(),"配方记录刷新失败")
 local closed,reason=f:close();assert(closed~=false and reason==nil,"配方记录关闭失败")
 local check=assert(io.open(path..".tmp","r"));local copy=check:read("*a");check:close()
 assert(copy==text and type(ser.unserialize(copy))=="table","配方记录回读失败")
 local backup
 if fs.exists(path) then
  local n=1;while fs.exists(path..".backup-"..n) do n=n+1 end
  backup=path..".backup-"..n;assert(fs.rename(path,backup),"旧配方记录归档失败")
 end
 local ok,err=fs.rename(path..".tmp",path)
 if not ok then if backup then fs.rename(backup,path) end;error(err or "配方记录保存失败") end
end
local function inspect(p)
 assert(p.isCraftable==false,"仅处理加工样板")
 assert(type(p.inputs)=="table" and type(p.outputs)=="table" and #p.outputs==1,"仅处理单产物加工样板")
 local out=p.outputs[1]
 assert(type(out.name)=="string" and not out.hasTag,"产物标识无效或带NBT，暂不登记")
 local ordinary,fluids={},{}
 local tail=false
 for index,input in ipairs(p.inputs) do
  assert(type(input)=="table" and type(input.name)=="string","输入标识无效")
  if input.name:sub(1,10)=="entangled_" then
   tail=true
   local n=tonumber(input.amount or input.size)
   assert(n and n>0 and n==math.floor(n),"凝聚物数量无效")
   assert(not (input.size and input.amount) or input.size==input.amount,"凝聚物数量字段不一致")
   fluids[#fluids+1]={name=input.name,amount=n,index=index}
  else
   assert(not tail,"凝聚物后还有普通输入，保留样板不处理")
   ordinary[#ordinary+1]=input
  end
 end
 local key=out.name:gsub("[^%w_]","_").."_"..tostring(out.damage or 0).."_"..tostring(out.size or 1)
 return DIR.."/"..key..".dat",ordinary,fluids
end
local function notify(slot,text)
 if announced[slot]~=text then print("槽 "..slot.."："..text);announced[slot]=text end
end
local function process(slot)
 local p=read(slot)
 if p==nil then announced[slot]=nil;return end
 assert(type(p)=="table","样板不可读")
 local path,ordinary,fluids=inspect(p)
 local existing=fs.exists(path) and load(path)
 if #fluids==0 then
  if existing then
   assert(existing.state=="converted" and equal(p.inputs,existing.ordinaryInputs)
    and equal(p.outputs,existing.outputs),"现有样板与登记记录不符，请保留并核对")
   notify(slot,"已转换并登记，无需重复处理")
  else notify(slot,"没有凝聚物输入，也无原始需求记录；不猜测配方") end
  return
 end
 assert(#ordinary>0,"不能移除全部样板输入")
 if existing then
  assert(existing.state=="converted" and equal(existing.original,p),"同产物记录冲突或有未完成转换，保留记录")
  assert(equal(existing.ordinaryInputs,ordinary) and equal(existing.condensates,fluids),"登记需求不一致")
 end
 local name=tostring(p.outputs[1].label or p.outputs[1].name)
 if mode=="preview" then
  print("槽 "..slot.."："..name.."，普通输入 "..#ordinary.." 项，凝聚物 "..#fluids.." 项")
  for _,f in ipairs(fluids) do print("  "..f.name.." "..f.amount.." mB") end
  return
 end
 assert(equal(read(slot),p),"登记前样板已变化")
 local record=existing or {version=1,state="prepared",interface=ADDRESS,slot=slot,
  original=p,ordinaryInputs=ordinary,outputs=p.outputs,condensates=fluids}
 if not existing then assert(fs.makeDirectory(DIR)~=false,"创建配方目录失败");save(path,record) end
 local changed=false
 local ok,err=xpcall(function()
  for i=#fluids,1,-1 do
   local before=read(slot)
   local expected={};for index=1,fluids[i].index do expected[index]=p.inputs[index] end
   assert(type(before)=="table" and before.isCraftable==p.isCraftable and equal(before.inputs,expected)
    and equal(before.outputs,p.outputs),"转换途中样板变化")
   changed=true
   assert(c.invoke(ADDRESS,"clearInterfacePatternInput",slot,fluids[i].index)~=false,"清除凝聚物输入失败")
  end
  local after=read(slot)
  assert(type(after)=="table" and after.isCraftable==p.isCraftable and equal(after.inputs,ordinary) and equal(after.outputs,p.outputs),"转换结果不符")
  if not existing then record.state="converted";save(path,record) end
 end,debug.traceback)
 if not ok then
  if changed then
   local restored,restoreErr=pcall(function()
    local after=read(slot)
    assert(type(after)=="table" and after.isCraftable==p.isCraftable and equal(after.outputs,p.outputs),"样板已被替换，不能自动还原")
    assert(type(after.inputs)=="table" and #after.inputs>=#ordinary and #after.inputs<=#p.inputs,"输入数量变化")
    for i,input in ipairs(after.inputs) do assert(equal(input,p.inputs[i]),"输入内容变化，不能自动还原") end
    for index=#after.inputs+1,#p.inputs do
     local input=p.inputs[index]
     assert(c.invoke(ADDRESS,"setInterfacePatternInput",slot,index,
      {name=input.name,size=input.size or input.amount,amount=input.amount or input.size},"fluid")~=false,"还原失败")
    end
    assert(equal(read(slot),p),"还原核对失败")
   end)
   if not existing then
    record.state=restored and "restored" or "needs_manual_restore"
    record.error=tostring(err);record.restoreError=not restored and tostring(restoreErr) or nil
    pcall(save,path,record)
   end
   error(tostring(err)..(restored and "；原样板已还原" or "；请保留此槽和记录，人工核对"))
  end
  error(err)
 end
 notify(slot,"转换完成并登记："..name)
end
local function main()
 assert(mode=="preview" or mode=="run" or mode=="watch","用法: preview / run / watch")
 local methods=c.methods(ADDRESS)
 for _,m in ipairs({"getInterfacePattern","clearInterfacePatternInput","setInterfacePatternInput"}) do
  assert(methods[m]~=nil,"工作接口缺少方法："..m)
 end
 print("BEC 样板自动处理：工作接口 "..ADDRESS)
 print(mode=="preview" and "只读预览，不修改样板或记录" or "放入原加工样板的副本，自动去除凝聚物输入并保存需求")
 repeat
  for slot=1,9 do
   local ok,err=pcall(process,slot)
   if not ok then notify(slot,"暂停处理："..tostring(err));return end
  end
  if mode~="watch" then break end
  local _,_,char=event.pull(1,"key_down")
  if char==113 or char==81 then break end
 until false
 print("样板处理已结束；转换样板仍在工作接口，需求记录在 "..DIR)
end
local ok,err=xpcall(main,debug.traceback)
if not ok then print("样板服务停止："..tostring(err)) end
