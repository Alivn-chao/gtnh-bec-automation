-- Locate all changes before replacing any file. No machine or journal actions.
local fs=require('filesystem');local plans={}
local function read(p)local f=assert(io.open(p,'r'));local t=f:read('*a');f:close();return assert(t)end
local function replace(t,a,b)
 local x,y=t:find(a,1,true);assert(x and not t:find(a,y+1,true),'快速补库入口缺失或不唯一，原文件未改')
 return t:sub(1,x-1)..b..t:sub(y+1)
end
local function plan(path,marker,transform)
 local original=read(path);if original:find(marker,1,true)then return end
 local modified=transform(original:gsub('\r\n','\n'));assert(load(modified,'@'..path,'t',_ENV),'语法检查失败: '..path)
 local n=1;while fs.exists(path..'.before-cache-custom-'..n) or fs.exists(path..'.cache-custom-new-'..n) or fs.exists(path..'.cache-custom-new-'..n..'.failed')do n=n+1 end
 plans[#plans+1]={path=path,original=original,modified=modified,backup=path..'.before-cache-custom-'..n,temp=path..'.cache-custom-new-'..n}
end
plan('/home/bec_cache.lua','BEC_V1_CACHE_CUSTOM_V1',function(t)
if not t:find('BEC_V1_CACHE_FAST_V2',1,true)then
t=replace(t,[=[-- BEC_V1_CACHE_PRIORITY_V1
local productionOutputs,priorityAt,priorityQueued={},-math.huge,false
local function productionWaiting()
 if not background then return false end
 if call(NODE,"getState")~="idle" then return true end
 if computer.uptime()<priorityAt then return priorityQueued end
 priorityAt=computer.uptime()+1;priorityQueued=false
 local cpus=call(MAIN,"getCpus");assert(type(cpus)=="table","主网 CPU 状态不可读")
 for _,cpu in pairs(cpus) do if cpu.busy==true then
  for _,getter in ipairs({"activeItems","pendingItems"}) do
   local ok,rows=pcall(function()return cpu.cpu[getter]()end)
   if not ok or type(rows)~="table" then priorityQueued=true
   else for _,item in pairs(rows) do
    local key=tostring(item.name)..":"..tostring(tonumber(item.damage or 0))
    if productionOutputs[key] and (item.size or item.amount or 0)>0 then priorityQueued=true end
   end end
  end
 end end
 return priorityQueued
end
]=],[=[-- BEC_V1_CACHE_FAST_V2
local productionOutputs,priorityAt,priorityQueued={},-math.huge,false
local unknownReported=false
local function productionWaiting()
 if not background then return false end
 local state=call(NODE,"getState")
 if state~="idle" then
  local req=call(NODE,"getRequiredCondensate")
  if (type(req)=="table" and next(req)~=nil) or state=="crafting" or state=="paused-step" then
   print("后台缓存让位：节点有配方，优先生产。")
   return true
  end
 end
 if computer.uptime()<priorityAt then return priorityQueued end
 priorityAt=computer.uptime()+1;priorityQueued=false
 local cpus=call(MAIN,"getCpus");assert(type(cpus)=="table","主网 CPU 状态不可读")
 for _,cpu in pairs(cpus) do if cpu.busy==true then
  for _,getter in ipairs({"activeItems","pendingItems"}) do
   local ok,rows=pcall(function()return cpu.cpu[getter]()end)
   if not ok or type(rows)~="table" then
    if not unknownReported then print("AE CPU任务列表不可读；未确认为配方，空闲补库继续。") end
    unknownReported=true
   else for _,item in pairs(rows) do
    local key=tostring(item.name)..":"..tostring(tonumber(item.damage or 0))
    if productionOutputs[key] and (item.size or item.amount or 0)>0 then priorityQueued=true end
   end end
  end
 end end
 if priorityQueued then print("后台缓存让位：AE队列有登记配方，优先生产。") end
 return priorityQueued
end
]=])
t=replace(t,[=[selectedBackground=selected;totals={[selected]=math.min(fixedStock,(stock[selected] or 0)+math.floor(16000/(units[selected] or 144))*(units[selected] or 144))}]=],[=[selectedBackground=selected;totals={[selected]=fixedStock}]=])
t=replace(t,[=[print("后台补缓存按最多16桶分段；有配方优先交回生产，本段目标 "..totals[selectedBackground].." mB。")]=],[=[print("空闲高速补库：直接补本种完整缺口到 "..fixedStock.." mB；有配方优先让位。")]=])
t=replace(t,[=[unchanged();save("converting");generator(true) local deadline=]=],[=[unchanged();save("converting");generator(true);if background then print("后台缓存纠缠转换中；本轮目标已更新。") end local deadline=]=])
end
t=replace(t,[=[local fixedStock]=],[=[local fixedStock -- BEC_V1_CACHE_CUSTOM_V1
local overrides={}]=])
t=replace(t,[=[assert(count>0,"没有可缓存的已登记配方") if fixedStock then for name in pairs(totals) do totals[name]=fixedStock end]=],[=[assert(count>0,"没有可缓存的已登记配方") if fixedStock then
local input=io.open("/home/bec_cache.config","r")
if input then local cfg=ser.unserialize(input:read("*a"));input:close()
 assert(type(cfg)=="table" and cfg.version==1 and (cfg.overrides==nil or type(cfg.overrides)=="table"),"单项缓存配置无效")
 overrides=cfg.overrides or {};for name,n in pairs(overrides) do assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"单项缓存目标无效") end
end
for name in pairs(totals) do totals[name]=overrides[name]~=nil and overrides[name] or fixedStock end]=])
t=replace(t,[=[selectedBackground=selected;totals={[selected]=fixedStock}]=],[=[selectedBackground=selected;totals={[selected]=totals[selected]}]=])
t=replace(t,[=["..fixedStock.." mB；有配方优先让位。"]=],[=["..totals[selectedBackground].." mB；有配方优先让位。"]=])
t=replace(t,[=[每种凝聚物统一目标 "..fixedStock.." mB，只补差额。]=],[=[默认目标 "..fixedStock.." mB，单项设置优先，0停补；只补差额。]=])
return t end)
plan('/home/bec_auto.lua','BEC_V1_IDLE_CACHE_FAST_V2',function(t)return replace(t,[=[if state~="idle" and not incomplete then return end]=],[=[-- BEC_V1_IDLE_CACHE_FAST_V2
if state~="idle" and not incomplete then
 local safe={['assembler-offline']=true,unpowered=true,['nanite-tier-too-low']=true,['paused-immediate']=true}
 if not safe[state] then return end
 local req=call(NODE,"getRequiredCondensate")
 if type(req)=="table" and next(req)~=nil then return end
end]=])end)
plan('/home/bec_cache_ui.lua','BEC_V1_CACHE_CUSTOM_UI_V1',function(t)
if not t:find('BEC_V1_CACHE_STATUS_FAST_V2',1,true)then
t=replace(t,[=[elseif text:find("预缓存完成",1,true) then status="预缓存完成"]=],[=[elseif text:find("后台缓存让位",1,true) then status=text
elseif text:find("等待高速口",1,true) or text:find("等待原液",1,true) then status=text
elseif text:find("高速供液",1,true) or text:find("已入子网",1,true) then status="高速缓存收液中"
elseif text:find("后台缓存纠缠转换中",1,true) then status="纠缠转换中"
elseif text:find("预缓存完成",1,true) then status=embedded and "本轮完成；继续维护库存" or "预缓存完成"]=])
t=replace(t,[=[line(8,"登记/已有流体 "]=],[=[-- BEC_V1_CACHE_STATUS_FAST_V2
if embedded and stock and (status=="预缓存完成" or status=="本轮完成；继续维护库存") then
 local missing=0;for _,row in ipairs(names) do if (stock[row[2]] or 0)<target then missing=missing+1 end end
 line(4,missing>0 and ("状态："..missing.." 种未达标，等待下一轮补库") or "状态：当前显示库存已达标",0x42d9ed)
end
line(8,"登记/已有流体 "]=])
t=replace(t,[=[local names,page,registryAt={},1,-math.huge]=],[=[local names,page,registryAt={},1,-math.huge;local displayStock,displayStockAt=nil,-math.huge]=])
t=replace(t,[=[local ok,stock=pcall(c.invoke,"237a9cac-118a-4b74-8755-0d0b0ad216c0","getStoredCondensate")]=],[=[local ok,stock=true,displayStock;if computer.uptime()-displayStockAt>=2 then ok,stock=pcall(c.invoke,"237a9cac-118a-4b74-8755-0d0b0ad216c0","getStoredCondensate");displayStock=ok and stock or nil;displayStockAt=computer.uptime() end]=])
t=replace(t,[=[if force or computer.uptime()-registryAt>=5 then]=],[=[if #names==0 or computer.uptime()-registryAt>=60 then]=])
t=replace(t,[=[if not editing and (ch==110 or ch==78) then]=],[=[if not editing and (ch==114 or ch==82) then registryAt=-math.huge;displayStockAt=-math.huge end if not editing and (ch==110 or ch==78) then]=])
end
t=replace(t,[=[if e[1]=="touch" and e[5]==0 then]=],[=[if e[1]=="touch" and (e[5]==0 or e[5]==1) then]=])
t=replace(t,[=[local target=144000]=],[=[local target=144000 -- BEC_V1_CACHE_CUSTOM_UI_V1
local overrides,selectedName,restoreDefault={},nil,false]=])
t=replace(t,[=[target=value.target]=],[=[target=value.target
assert(value.overrides==nil or type(value.overrides)=="table","单项缓存配置损坏")
overrides=value.overrides or {};for name,n in pairs(overrides) do assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"单项缓存目标无效") end]=])
t=replace(t,[=["每种凝聚物目标："..(editing and buffer.."_" or tostring(target))]=],[=[(selectedName and ((labels[selectedName] or selectedName).." 单项目标：") or "默认缓存目标：")..(editing and buffer.."_" or tostring(target))]=])
t=replace(t,[=[editing and "输入数字；Enter 保存，Esc 取消，Backspace 删除" or "[ E 修改目标 ]   [ B 补缓存 ]   [ P 预览 ]"]=],[=[editing and "[ 保存 ]       [ 取消 ]       [ 恢复统一 ]  输入数字，0停补" or "[ E 默认目标 ]   [ B 补缓存 ]   [ P 预览 ]  点击流体设置；右键恢复默认"]=])
t=replace(t,[=[if (stock[row[2]] or 0)<target then]=],[=[if (stock[row[2]] or 0)<(overrides[row[2]]~=nil and overrides[row[2]] or target) then]=])
t=replace(t,[=[local value=row and stock and (stock[row[2]] or 0) or nil]=],[=[local desired=row and (overrides[row[2]]~=nil and overrides[row[2]] or target) or target
local value=row and stock and (stock[row[2]] or 0) or nil]=])
t=replace(t,[=[(value or 0)/target]=],[=[(value or 0)/math.max(1,desired)]=])
t=replace(t,[=[value>=target]=],[=[value>=desired]=])
t=replace(t,[=[tostring(value or "?").." / "..target]=],[=[tostring(value or "?").." / "..(desired==0 and "停补" or desired)]=])
t=replace(t,[=[local n=tonumber(buffer);assert(valid(n),"请输入有效正整数mB")]=],[=[local n=tonumber(buffer)
assert(valid(n) or (selectedName~=nil and n==0),"默认目标需正整数；单项允许0停补")
local nextOverrides={};for name,value in pairs(overrides) do nextOverrides[name]=value end
local nextTarget=target
if selectedName then if restoreDefault then nextOverrides[selectedName]=nil else nextOverrides[selectedName]=n end else nextTarget=n end]=])
t=replace(t,[=[out:flush();out:close()]=],[=[assert(out:flush());out:close()]=])
t=replace(t,[=[write(CONFIG,ser.serialize({version=1,target=n},false))
target=n;editing=false;status="配置已保存，下次启动仍使用此目标"]=],[=[write(CONFIG,ser.serialize({version=1,target=nextTarget,overrides=nextOverrides},false))
target=nextTarget;overrides=nextOverrides;editing=false;selectedName=nil;restoreDefault=false;status="缓存设置已保存，下次补库按单项目标执行"]=])
t=replace(t,[=[editing=false;buffer=tostring(target);return "back"]=],[=[editing=false;selectedName=nil;restoreDefault=false;buffer=tostring(target);return "back"]=])
t=replace(t,[=[if e[4]==6 then]=],[=[if e[4]>=9 and e[4]<=16 then
 local row=names[(page-1)*8+e[4]-8]
 if row then selectedName=row[2];restoreDefault=false;editing=true;buffer="";status="设置 "..row[1].."；输入新目标，0停止自动补这一种"
  if e[5]==1 then e={"key_down","ui",100} else e={} end
 end
elseif editing and e[4]==7 then
 e={"key_down","ui",e[3]<16 and 13 or e[3]<32 and 0 or 100,e[3]>=16 and e[3]<32 and 1 or 0}
elseif e[4]==6 then]=])
t=replace(t,[=[if editing then if code==1 then editing=false]=],[=[if editing then if code==1 then editing=false;selectedName=nil;restoreDefault=false
elseif ch==100 and selectedName then restoreDefault=true;buffer=tostring(target);local ok,err=pcall(save);if not ok then status=tostring(err) end]=])
t=replace(t,[=[elseif ch==101 or ch==69 then editing=true;buffer="";status="修改统一库存目标"]=],[=[elseif ch==101 or ch==69 then selectedName=nil;restoreDefault=false;editing=true;buffer="";status="修改默认目标，已设单项目标保持"]=])
t=replace(t,[=[if embedded then buffer=tostring(target);local ok,err=pcall(save);]=],[=[if embedded then selectedName=nil;restoreDefault=false;buffer=tostring(target);local ok,err=pcall(save);]=])
return t end)
for _,p in ipairs(plans)do local f=assert(io.open(p.temp,'w'));assert(f:write(p.modified));assert(f:flush());f:close();assert(read(p.temp)==p.modified,'临时回读失败')end
local installed={}
local ok,err=pcall(function()
 for _,p in ipairs(plans)do
  assert(fs.rename(p.path,p.backup),'备份失败: '..p.path);installed[#installed+1]=p
  assert(fs.rename(p.temp,p.path),'替换失败: '..p.path)
  assert(read(p.path)==p.modified and read(p.backup)==p.original,'替换回读不符')
 end
end)
if not ok then
 for i=#installed,1,-1 do local p=installed[i]
  if fs.exists(p.path)then assert(fs.rename(p.path,p.temp..'.failed'),'失败文件保留失败')end
  assert(fs.rename(p.backup,p.path),'恢复失败，原文件在 '..p.backup)
 end
 error('安装失败，已还原: '..tostring(err))
end
print('单项缓存设置已安装：鼠标点击流体，0停补，右键恢复默认。')
for _,p in ipairs(plans)do print('备份: '..p.backup)end
print('订单/日志保留，未启停机器。继续: lua /home/bec_ui.lua run')
