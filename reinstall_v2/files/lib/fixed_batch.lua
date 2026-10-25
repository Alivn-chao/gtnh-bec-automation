-- The batch identity and exact quotas were checked before release. Poll only
-- live state/tier and consumption not already proven. Full validation remains
-- at swaps and completion. Immediate pause holds observed phase leaders.
return function(c,cfg,members,entries,task,full)
 local phase
 local function identity(t)return type(t)=='table'and tostring(t.tier)..':'..tostring(t.name)or ''end
 return function()
  assert(not task.cancel,'用户暂停生产组')
  if not task.released then return full()end
  if not phase then local v=full();phase={tier=v.requiredTier,name=v.requiredFamily};return v end
  local out={required={},consumed={},parallel=0,requiredTier=phase.tier,requiredFamily=phase.name,allIdle=true,allPaused=true}
  local rows={};local oldPresent=false;local newPhase,mixed
  for _,i in ipairs(members)do
   local n,e=cfg.nodes[i],entries[i];local state=c.invoke(n.address,'getState')
   assert(not e.finished or state=='idle','已完成节点接到新订单')
   assert(state=='idle'or state=='crafting'or state=='paused-immediate'or state=='nanite-tier-too-low','节点运行异常：'..tostring(state))
   if not e.consumedProven then
    local used=c.invoke(n.address,'getConsumedCondensate');assert(type(used)=='table','节点消耗不可读');e.consumed=e.consumed or {}
    e.consumedProven=true
    for k,need in pairs(e.required)do
     local v=used[k]or 0;assert(type(v)=='number'and v>=0 and v<=need,'节点消耗数量异常')
     e.consumed[k]=math.max(e.consumed[k]or 0,v);if e.consumed[k]<need then e.consumedProven=false end
    end
   end
   if state=='idle'then
    assert(c.invoke(n.address,'isWorkAllowed')==false and e.consumedProven,'节点空闲但本批消耗/接单许可未确认')
    if not e.finished then c.invoke(n.redstone,'setOutput',n.pauseSide,15);e.finished=true end
   else
    out.allIdle=false
    local tier=c.invoke(n.address,'getRequiredTier')
    if type(tier)~='table'or type(tier.tier)~='number'then return full()end
    rows[#rows+1]={node=n,entry=e,tier=tier,state=state}
    if identity(tier)==identity(phase)then oldPresent=true
    elseif not newPhase then newPhase=tier
    elseif identity(newPhase)~=identity(tier)then mixed=true end
    if state=='crafting'then out.allPaused=false end
   end
   out.parallel=out.parallel+e.parallel
   for k,v in pairs(e.required)do out.required[k]=(out.required[k]or 0)+v;out.consumed[k]=(out.consumed[k]or 0)+(e.consumed[k]or 0)end
  end
  if newPhase then
   if oldPresent then
    -- Keep the current nanites until every remaining member leaves this phase.
    for _,r in ipairs(rows)do if identity(r.tier)~=identity(phase)and not r.entry.phaseHeld then
     c.invoke(r.node.redstone,'setOutput',r.node.pauseSide,15)
     assert(c.invoke(r.node.redstone,'getOutput',r.node.pauseSide)==15,'阶段等待暂停回读失败');r.entry.phaseHeld=true
    end end
    out.allPaused=false
   elseif mixed then
    -- A very short recipe can cross several steps between OC callbacks.
    -- Fall back to the original live group policy rather than guess a phase.
    for _,r in ipairs(rows)do if r.entry.phaseHeld then
     assert(c.invoke(r.node.address,'isWorkAllowed')==false,'阶段恢复前接单必须关闭')
     c.invoke(r.node.redstone,'setOutput',r.node.pauseSide,0);r.entry.phaseHeld=nil
    end end
    local v=full();phase={tier=v.requiredTier,name=v.requiredFamily};return v
   else
    out.requiredTier=newPhase.tier;out.requiredFamily=newPhase.name
    phase={tier=newPhase.tier,name=newPhase.name}
    for _,r in ipairs(rows)do r.entry.phaseHeld=nil end
   end
  end
  out.state=out.allIdle and 'idle'or out.allPaused and 'paused-immediate'or 'crafting'
  return out
 end
end
