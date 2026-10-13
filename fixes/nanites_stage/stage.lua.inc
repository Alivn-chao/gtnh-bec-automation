-- BEC_V1_NANITES_STAGE_V2: let the node stall itself; exchange bees live.
local stageBusy=false
local stageSignature,stageCheckAt
local stageWorker
local originalStageTick=tick
serviceNaniteStage=function()
 if stageBusy or stopping or not record then return end
 local overlapping=record.pipeline and record.pipeline.overlap
 if record.stage~="watching" and not overlapping then return end
 local state=call(NODE,"getState")
 if state~="crafting" and state~="paused-immediate" and state~="nanite-tier-too-low" then return end
 local req=call(NODE,"getRequiredCondensate")
 local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)~="table" or type(parallel)~="number" or parallel<1 then return end
 local normalized={};for name,n in pairs(req)do normalized[name]=integer(n)/parallel end
 local expected=overlapping and record.pipeline.recipe or perRecipe
 if not same(normalized,expected) then return end
 local required=call(NODE,"getRequiredTier")
 if type(required)~="table" or type(required.tier)~="number" then return end
 local signature=tostring(required.name)..":"..required.tier
 if signature==stageSignature and computer.uptime()<(stageCheckAt or 0) then return end
 if not stageWorker then
  local loader=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")
  stageWorker=loader()
  assert(type(stageWorker)=="table" and type(stageWorker.needsSwitch)=="function" and stageWorker.passiveStages,
   "请先安装新版自动停顿换蜂模块")
 end
 stageSignature=signature;stageCheckAt=computer.uptime()+2
 if not stageWorker.needsSwitch() then return end
 stageBusy=true
 local ok,reason=xpcall(function()
  -- Stage and consumption may advance while compatible bees keep working.
  -- Do not freeze those hints or drive node/GEN outputs to exchange bees.
  local function checked()
   if record.gateIntent then verifyGate(record.gateIntent.filters) end
  end
  checked()
  record.naniteStage={required=required,stage="switching"};save(record.stage)
  print("阶段换蜂：优先对应库存；等级不足由节点自动停顿")
  stageWorker.ensure({passive=true,check=checked,tick=originalStageTick,stopping=function()return stopping end})
  checked()
  record.naniteStage=nil;save(record.stage)
  local latest=call(NODE,"getRequiredTier")
  if type(latest)=="table" and latest.tier==required.tier and latest.name==required.name then
   stageSignature=signature;stageCheckAt=computer.uptime()+2
  else stageSignature=nil;stageCheckAt=0 end
 end,debug.traceback)
 stageBusy=false
 if not ok then error(reason) end
end
tick=function(seconds)
 originalStageTick(seconds)
 if not stopping then serviceNaniteStage() end
end
