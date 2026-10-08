-- Read-only recovery diagnosis. Does not request, transfer or change machines.
local c=require("component")
local s=require("serialization")
local node="b04787f9-5423-4b03-8549-c786d4ef38d0"
local main="3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local sub="86311657-33d1-41b5-a0d9-0aee7b5c2c50"
local storage="237a9cac-118a-4b74-8755-0d0b0ad216c0"
local function get(a,m,...) return c.invoke(a,m,...) end
local function show(k,v) print(k..": "..s.serialize(v,false)) end
print("恢复检查：只读，不补料、不放行")
show("状态",get(node,"getState"))
local parallel=get(node,"getParallelRecipesInProgress")
local required=get(node,"getRequiredCondensate")
local consumed=get(node,"getConsumedCondensate")
show("实际并行",parallel);show("当前需求",required);show("节点已消耗",consumed)
local queued=0
for i,cpu in pairs(get(main,"getCpus")) do if cpu.busy==true then
 assert(cpu.cpu,"CPU没有任务对象")
 for _,m in ipairs({"activeItems","pendingItems"}) do
  for _,item in pairs(cpu.cpu[m]()) do
   if item.name=="gregtech:gt.metaitem.03" and tonumber(item.damage)==32307 then
    local n=assert(tonumber(item.size or item.amount))
    print("CPU "..i.." "..m.." 原始屏蔽层="..n);queued=queued+n
   end
  end
 end
end end
show("AE剩余份数合计",queued)
local raw={}
for _,f in pairs(get(sub,"getFluidsInNetwork")) do if (tonumber(f.amount or f.size) or 0)>0 then
 raw[f.name]=(raw[f.name] or 0)+(tonumber(f.amount or f.size) or 0)
end end
local stock=get(storage,"getStoredCondensate")
show("子网原液",raw);show("约束场凝聚物",stock)
if type(required)=="table" and type(consumed)=="table" then
 for _,names in ipairs({{"entangled_chromaticglass","molten.chromaticglass"},{"entangled_transcendentmetal","molten.transcendentmetal"}}) do
  local name,fluid=names[1],names[2]
  local need=(required[name] or 0)-(consumed[name] or 0)+288*math.max(0,queued-parallel)
  print(fluid.." 恢复尚需="..need.."，子网="..(raw[fluid] or 0).."，凝聚物="..(stock[name] or 0))
 end
end
local f=io.open("/home/bec_auto.journal","r")
if f then
 local record=s.unserialize(f:read("*a"));f:close()
 show("旧阶段",record.stage);show("旧批量",record.batchCount)
 show("旧需求",record.required);show("旧尚需",record.remaining);show("旧整批目标",record.target)
end
