-- BEC_V1_CACHE_FAST_V2
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
