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
 local n=1;while fs.exists(path..'.before-cache-fast-'..n) or fs.exists(path..'.cache-fast-new-'..n) or fs.exists(path..'.cache-fast-new-'..n..'.failed')do n=n+1 end
 plans[#plans+1]={path=path,original=original,modified=modified,backup=path..'.before-cache-fast-'..n,temp=path..'.cache-fast-new-'..n}
end
plan('/home/bec_cache.lua','BEC_V1_CACHE_FAST_V2',function(t)
 assert(t:find('BEC_V1_CACHE_PRIORITY_V1',1,true),'请先安装配方优先补丁，再升级快速补库')
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
return t end)
plan('/home/bec_auto.lua','BEC_V1_IDLE_CACHE_FAST_V2',function(t)return replace(t,[=[if state~="idle" and not incomplete then return end]=],[=[-- BEC_V1_IDLE_CACHE_FAST_V2
if state~="idle" and not incomplete then
 local safe={['assembler-offline']=true,unpowered=true,['nanite-tier-too-low']=true,['paused-immediate']=true}
 if not safe[state] then return end
 local req=call(NODE,"getRequiredCondensate")
 if type(req)=="table" and next(req)~=nil then return end
end]=])end)
plan('/home/bec_cache_ui.lua','BEC_V1_CACHE_STATUS_FAST_V2',function(t)
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
print('快速补库升级完成：取消16桶限制；只为已确认配方让位；修正完成状态。')
for _,p in ipairs(plans)do print('备份: '..p.backup)end
print('订单/日志保留，未启停机器。继续: lua /home/bec_ui.lua run')
