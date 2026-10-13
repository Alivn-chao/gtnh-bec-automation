-- BEC_V1_NANITES_STAGE_V1: prefer exact-stage bees, retain compatible fallback.
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
 if not same(normalized,expected) then return end -- The recipe/filter controller owns new recipes.
 local required=call(NODE,"getRequiredTier")
 if type(required)~="table" or type(required.tier)~="number" then return end
 local signature=tostring(required.name)..":"..required.tier
 if signature==stageSignature and computer.uptime()<(stageCheckAt or 0) then return end
 if not stageWorker then
  local loader=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")
  stageWorker=loader()
  assert(type(stageWorker)=="table" and type(stageWorker.needsSwitch)=="function","请先安装新版阶段优选蜂群模块")
 end
 stageSignature=signature;stageCheckAt=computer.uptime()+2
 if not stageWorker.needsSwitch() then return end
 stageBusy=true
 local ok,reason=xpcall(function()
  local output=call(RS,"getOutput",sides.top)
  assert(output==0 or output==15,"换蜂前暂停输出异常")
  local converting=call(GEN,"isWorkAllowed")
  pause(15);generator(false)
  local limit=computer.uptime()+190
  local function stoppedCheck()
   if record.gateIntent then verifyGate(record.gateIntent.filters) end
   assert(same(call(NODE,"getRequiredCondensate"),req)
    and call(NODE,"getParallelRecipesInProgress")==parallel,"换蜂等待时配方发生变化，保持暂停")
   local value=call(NODE,"getRequiredTier")
   assert(type(value)=="table" and value.tier==required.tier and value.name==required.name,"换蜂等待时阶段发生变化，保持暂停")
  end
  while true do
   stoppedCheck()
   if stopping then return end
   local s=call(NODE,"getState")
   if (s=="paused-immediate" or s=="nanite-tier-too-low") and call(GEN,"isMachineActive")==false then break end
   assert(computer.uptime()<limit,"阶段换蜂停机超时，保持暂停")
   originalStageTick(0.1)
  end
  local used=call(NODE,"getConsumedCondensate")
  assert(type(used)=="table","换蜂前消耗记录不可读")
  local function checked()
   stoppedCheck()
   assert(same(call(NODE,"getConsumedCondensate"),used),"暂停换蜂期间消耗发生变化，保留现场")
  end
  record.naniteStage={required=required,consumed=used,stage="switching"};save(record.stage)
  print("阶段换蜂：需求 "..tostring(required.name).." / T"..required.tier.."，优先对应库存")
  stageWorker.ensure({check=checked,tick=originalStageTick,stopping=function()return stopping end})
  checked()
  local p=call(NODE,"getProvidedTier")
  assert(type(p)=="table" and p.tier>=required.tier and call(NODE,"getAvailableNanites")>=64,"阶段换蜂后等级或数量不足")
  record.naniteStage=nil;save(record.stage)
  if not stopping then
   if converting then generator(true) end
   pause(output) -- Restore only our previous output; the production guard still checks funding.
  end
 end,debug.traceback)
 stageBusy=false
 if not ok then pcall(pause,15);pcall(generator,false);error(reason) end
end
tick=function(seconds)
 originalStageTick(seconds)
 if not stopping then serviceNaniteStage() end
end
