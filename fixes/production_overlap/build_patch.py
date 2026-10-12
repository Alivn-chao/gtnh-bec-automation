from pathlib import Path
folder = Path(__file__).parent
root = folder.parent
prepare = (root/'pipeline/prepare.lua.inc').read_text(encoding='utf-8')
prepare = prepare.replace('BEC_V1_PIPELINE_V1:', 'BEC_V1_PRODUCTION_OVERLAP_V1:')
prepare = prepare.replace('record.pipeline={base=base,initial=held,delivered={}}', '''record.pipeline={base=base,initial=held,delivered={}}
 local recipe={};checkRecipe(record.required)
 for name,n in pairs(perRecipe) do recipe[name]=n end
 record.pipeline.recipe=recipe;record.pipeline.startConsumed={}
 for name,n in pairs(record.required) do record.pipeline.startConsumed[name]=n-record.remaining[name] end
 local halted,released=false,false
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
  if not changed and tierMethod then changed=tierValue()~=neededTier end
  if state~="crafting" and state~="paused-immediate" then changed=true end
  if changed then
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
  if funded then
   local consumed=call(NODE,"getConsumedCondensate")
   assert(type(consumed)=="table","当前消耗记录不可读")
   for name,n in pairs(req) do
    local used=integer(consumed[name] or 0);assert(used<=n,"节点消耗超过当前需求")
    if (stock[name] or 0)<n-used then funded=false end
   end
  end
  if funded and not released then
   checkRecipe(req)
   record.pipeline.overlap=true;save("pipeline-production-release-pending")
   local releaseReq=productionGuard()
   if not halted and same(releaseReq,req) then pause(0);released=true;save("pipeline-producing")
    print("当前配方材料已够，开始生产；其余收液、下单和纠缠继续。") end
  elseif not funded and released then
   pause(15);released=false;save("pipeline-waiting-material")
  end
  if ready and (halted or not funded) and (not converting or call(GEN,"isMachineActive")==false) then
   pause(15)''')
prepare = prepare.replace('record.pipelineComplete=true;', 'record.productionOverlapHandled=true;')
prepare = prepare.replace('unchanged();save("pipeline-converting")', 'productionGuard();save("pipeline-converting")')
prepare = prepare.replace('原液已到货，边收料边纠缠；装配端保持暂停。', '原液已到货，边收料边纠缠；当前配方够料即生产。')
(folder/'prepare.lua.inc').write_text(prepare, encoding='utf-8')
template = (folder/'installer.lua.inc').read_text(encoding='utf-8')
(folder/'patch_v1.lua').write_text(template.replace('PREPARE_BODY',prepare).replace('RECOVER_BODY',(folder/'recover.lua.inc').read_text(encoding='utf-8')), encoding='utf-8')
