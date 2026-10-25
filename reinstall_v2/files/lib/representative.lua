-- Exact quotas are frozen by cell_feed. Demand is read from the largest
-- parallel member; ties choose the last member released. Other members retain
-- state/fault, pause and completion checks, not repeated recipe/tier scans.
return function(c,cfg,members,entries,task,fallback)
 local M={};local total,required=0,{}
 for _,i in ipairs(members)do local e=assert(entries[i]);total=total+e.parallel
  for k,v in pairs(e.required)do required[k]=(required[k]or 0)+v end
 end
 local function copy(v)local out={};for k,n in pairs(v)do out[k]=n end;return out end
 function M.parallel()return total end
 function M.required()return copy(required)end
 local lastReference,phase,pending,steps
 local function id(v)return tostring(v.tier)..':'..tostring(v.name)end
 local function used(i,state)
  local n,e=cfg.nodes[i],entries[i]
  if not e.consumedProven and(task.released or state=='idle')then
   local actual=c.invoke(n.address,'getConsumedCondensate');assert(type(actual)=='table','消耗记录不可读')
   e.consumed=e.consumed or {};e.consumedProven=true
   for k,need in pairs(e.required)do local value=actual[k]or 0
    assert(type(value)=='number'and value>=0 and value<=need,'节点消耗超出固定批次')
    e.consumed[k]=math.max(e.consumed[k]or 0,value)
    if e.consumed[k]<need then e.consumedProven=false end
   end
   for k,value in pairs(actual)do assert(value==0 or e.required[k],'节点有无关凝聚物消耗')end
  end
  return e.consumed or {}
 end
 function M.snapshot(paused,retry)
  assert(not task.cancel,'用户暂停生产组')
  local out={required=copy(required),consumed={},parallel=total,requiredTier=0,allIdle=true,allPaused=true,states={}}
  local ref
  for _,i in ipairs(members)do local n,e=cfg.nodes[i],entries[i];local state=c.invoke(n.address,'getState');out.states[i]=state
   assert(not e.finished or state=='idle','已完成节点提前接到新订单')
   assert(state=='idle'or state=='crafting'or state=='paused-immediate'or state=='nanite-tier-too-low','节点运行异常：'..tostring(state))
   if paused or not task.released then
    assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15 and state~='crafting','备料/换蜂期间整组必须暂停')
   end
   local consumption=used(i,state)
   for k,v in pairs(e.required)do out.consumed[k]=(out.consumed[k]or 0)+(consumption[k]or 0)end
   if state=='idle'then
    assert(c.invoke(n.address,'isWorkAllowed')==false and e.consumedProven,'空闲节点缺少完整消耗证明或仍允许接单')
    if not e.finished then c.invoke(n.redstone,'setOutput',n.pauseSide,15);e.finished=true end
   else
    out.allIdle=false
    if state=='crafting'then out.allPaused=false end
    if not ref or e.parallel>=entries[ref].parallel then ref=i end
   end
  end
  if ref then
   local n,e=cfg.nodes[ref],entries[ref]
   local p=c.invoke(n.address,'getParallelRecipesInProgress')
   local req=c.invoke(n.address,'getRequiredCondensate')
   local demand=c.invoke(n.address,'getRequiredTier')
   if type(p)~='number'or type(req)~='table'or type(demand)~='table'then
    if c.invoke(n.address,'getState')=='idle'then
     if(retry or 0)<1 then return M.snapshot(paused,(retry or 0)+1)end
     return fallback(paused)
    end
    error('代表节点需求不可读')
   end
   assert(p==e.parallel,'代表节点并行与已确认配额不符')
   for k,v in pairs(e.required)do assert(req[k]==v,'代表节点配方变化')end
   for k in pairs(req)do assert(e.required[k],'代表节点出现无关流体需求')end
   assert(type(demand.tier)=='number'and demand.tier>=1 and demand.tier%1==0,'代表节点蜂群等级无效')
   out.requiredTier=demand.tier;out.requiredFamily=demand.name;out.reference=ref;lastReference=ref
  else lastReference=nil end
  out.state=out.allIdle and 'idle'or out.allPaused and 'paused-immediate'or 'crafting'
  return out
 end
 function M.demand()
  local s=M.snapshot();return s.requiredTier>0 and{tier=s.requiredTier,name=s.requiredFamily}or nil
 end
 local function hold(i)
  assert(not task.cancel,'用户暂停生产组')
  local n,e=cfg.nodes[i],entries[i]
  if not e.phaseHeld then
   c.invoke(n.redstone,'setOutput',n.pauseSide,15)
   assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'阶段等待暂停回读失败');e.phaseHeld=true
  end
 end
 local function boundary(ref)
  steps=steps or c.invoke(cfg.nodes[ref].address,'getRecipeSteps')
  assert(type(steps)=='table','代表节点阶段表不可读')
  local progress=c.invoke(cfg.nodes[ref].address,'getWorkProgress')
  assert(type(progress)=='number'and progress>=0,'代表节点进度不可读')
  for _,step in ipairs(steps)do
   assert(type(step.start)=='number'and type(step['end'])=='number','阶段边界不可读')
   if progress>=step.start and progress<step['end']then return step.start end
  end
 end
 function M.production()
  local out=M.snapshot()
  if not task.released or out.allIdle then return out end
  local demand={tier=out.requiredTier,name=out.requiredFamily}
  if not phase then phase=demand;return out end
  if not pending and id(demand)~=id(phase)then
   hold(out.reference)
   local start=boundary(out.reference)
   if not start then return M.snapshot()end
   pending={tier=demand.tier,name=demand.name,start=start}
  end
  if pending then
   local ready=true
   for _,i in ipairs(members)do if out.states[i]~='idle'then
    local progress=c.invoke(cfg.nodes[i].address,'getWorkProgress')
    assert(type(progress)=='number'and progress>=0,'阶段同步进度不可读')
    if progress>=pending.start then hold(i)else
     ready=false
     if entries[i].phaseHeld then
      assert(c.invoke(cfg.nodes[i].address,'isWorkAllowed')==false,'阶段追赶前接单必须关闭')
      c.invoke(cfg.nodes[i].redstone,'setOutput',cfg.nodes[i].pauseSide,0);entries[i].phaseHeld=nil
     end
    end
   end end
   if ready then
    phase={tier=pending.tier,name=pending.name};pending=nil
    out.requiredTier=phase.tier;out.requiredFamily=phase.name
    for _,i in ipairs(members)do entries[i].phaseHeld=nil end
    out.allPaused=true;out.state='paused-immediate'
   else
    out.requiredTier=phase.tier;out.requiredFamily=phase.name;out.allPaused=false;out.state='crafting'
   end
  end
  return out
 end
 return M
end
