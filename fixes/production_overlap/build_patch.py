from pathlib import Path
folder = Path(__file__).parent
root = folder.parent
prepare = (root/'pipeline/prepare.lua.inc').read_text(encoding='utf-8')
prepare = prepare.replace('BEC_V1_PIPELINE_V1:', 'BEC_V1_PRODUCTION_OVERLAP_V3:')
prepare = prepare.replace('record.pipeline={base=base,initial=held,delivered={}}', '''record.pipeline={base=base,initial=held,delivered={}}
 local recipe={};checkRecipe(record.required)
 for name,n in pairs(perRecipe) do recipe[name]=n end
 record.pipeline.recipe=recipe;record.pipeline.startConsumed={}
 for name,n in pairs(record.required) do record.pipeline.startConsumed[name]=n-record.remaining[name] end
 local halted,released=false,false
 local releasedAt;local lastFeedback;local feedbackAt=0
 local lastRequired=record.required
 local tierMethod=c.methods(NODE).getRequiredTier~=nil
 local function tierValue()local t=call(NODE,"getRequiredTier");return type(t)=="table" and t.tier or t end
 local neededTier=tierMethod and tierValue()
 local function productionGuard()
  if record.gateIntent then verifyGate(record.gateIntent.filters) end
  local state=call(NODE,"getState")
  local req=call(NODE,"getRequiredCondensate")
  local parallel=call(NODE,"getParallelRecipesInProgress")
  local normalized={}
  if type(req)=="table" and type(parallel)=="number" and parallel>0 then
   for name,n in pairs(req) do normalized[name]=integer(n)/parallel end
  end
  local changed=not same(normalized,recipe)
  local reason=changed and "配方需求变化，等待旧窗口收尾" or nil
  local tierCovered=false
  if not changed and tierMethod then
   local nextTier=tierValue()
   if nextTier~=neededTier or state=="nanite-tier-too-low" then
    local provided=call(NODE,"getProvidedTier")
    local count=call(NODE,"getAvailableNanites")
    tierCovered=type(nextTier)=="number" and type(provided)=="table" and type(provided.tier)=="number"
     and provided.tier>=nextTier and type(count)=="number" and count>=64
    if tierCovered then
     neededTier=nextTier
    else changed=true;reason="蜂群不足以运行当前阶段，等待旧窗口收尾" end
   end
  end
  if state~="crafting" and state~="paused-immediate" and not(state=="nanite-tier-too-low" and tierCovered) then
   changed=true;reason=reason or ("节点状态: "..tostring(state))
  end
  if released and releasedAt and computer.uptime()-releasedAt>=3 then
   local output=call(RS,"getOutput",sides.top)
   local feedback
   if output~=0 then
    feedback="本脚本已放行，但暂停输出被改为 "..tostring(output).."；检查其他运行脚本或红石控制"
   elseif state=="paused-immediate" then
    feedback="本脚本暂停输出=0，节点仍立即暂停；检查其他控制仓收到的红石信号"
   end
   if feedback and (feedback~=lastFeedback or computer.uptime()>=feedbackAt) then
    print("放行核对: "..feedback)
    record.pipeline.feedback={reason=feedback,output=output,state=state,at=computer.uptime()}
    save(record.stage);lastFeedback=feedback;feedbackAt=computer.uptime()+15
   elseif not feedback then lastFeedback=nil;record.pipeline.feedback=nil end
  end
  if changed then
   if not halted then print("生产暂停: "..reason.."；已提交的供液申请继续核对，不重复下单。") end
   pause(15);released=false;halted=true
   if state=="idle" and record.pipeline.overlap then
    local used=call(NODE,"getConsumedCondensate");assert(type(used)=="table","节点空闲后消耗记录不可读")
    for name,n in pairs(lastRequired)do assert(integer(used[name] or 0)>=n,"节点进入空闲但凝聚物未消耗完: "..name)end
   end
  else
   lastRequired=req
  end
  return req
 end''')
prepare = prepare.replace('unchanged();jobsAndRequests();if stopping then break end', 'productionGuard();jobsAndRequests();if stopping then break end')
prepare = prepare.replace('verifyBulk(route,item.raw);unchanged()', 'verifyBulk(route,item.raw);productionGuard()')
prepare = prepare.replace('local amount=math.floor(math.min(remaining,network(MAIN)[item.raw] or 0,2147483647)/item.batch)*item.batch', 'local amount=remaining>0 and math.floor(math.min(remaining,network(MAIN)[item.raw] or 0,2147483647)/item.batch)*item.batch or 0')
prepare = prepare.replace('for name,n in pairs(base) do assert((stock[name] or 0)>=n,"暂停备料时已有凝聚物减少") end', 'for name,n in pairs(base) do if not recipe[name] then assert((stock[name] or 0)==n,"无关凝聚物库存变化") end end')
prepare = prepare.replace('condensate>=(base[item.name] or 0) and liquid+condensate<=', 'liquid+condensate<=')
prepare = prepare.replace('supplied<item.amount or condensate<target[item.name] or liquid>0', 'supplied<item.amount or liquid>0')
prepare = prepare.replace('  if ready and (not converting or call(GEN,"isMachineActive")==false) then', '''  local req=productionGuard()
  local funded=not halted
  local shortages={}
  if funded then
   local consumed=call(NODE,"getConsumedCondensate")
   assert(type(consumed)=="table","当前消耗记录不可读")
   for name,n in pairs(req) do
    local used=integer(consumed[name] or 0);assert(used<=n,"节点消耗超过当前需求")
    if (stock[name] or 0)<n-used then
     funded=false;shortages[#shortages+1]=name.." 缺 "..(n-used-(stock[name] or 0)).." mB"
    end
   end
  end
  if funded and not released then
   checkRecipe(req)
   record.pipeline.overlap=true;save("pipeline-production-release-pending")
   local releaseReq=productionGuard()
   if not halted and same(releaseReq,req) then pause(0);released=true;releasedAt=computer.uptime();save("pipeline-producing")
    print("当前配方材料已够，暂停输出已设0；节点运行状态持续核对，其余供液纠缠继续。") end
  elseif not funded and released then
   pause(15);released=false;save("pipeline-waiting-material")
   if #shortages>0 then print("生产等料: "..table.concat(shortages,"；").."；供液纠缠继续。") end
  end
  if ready and (halted or not funded) and (not converting or call(GEN,"isMachineActive")==false) then
   pause(15)''')
prepare = prepare.replace('record.pipelineComplete=true;', 'record.productionOverlapHandled=true;')
prepare = prepare.replace('unchanged();save("pipeline-converting")', 'productionGuard();save("pipeline-converting")')
prepare = prepare.replace('原液已到货，边收料边纠缠；装配端保持暂停。', '原液已到货，边收料边纠缠；当前配方够料即生产。')
(folder/'prepare.lua.inc').write_text(prepare, encoding='utf-8')
template = (folder/'installer.lua.inc').read_text(encoding='utf-8')
(folder/'patch_v1.lua').write_text(template.replace('PREPARE_BODY',prepare).replace('RECOVER_BODY',(folder/'recover.lua.inc').read_text(encoding='utf-8')), encoding='utf-8')
