-- BEC_V1_ORDER_WINDOW_V1
local function batchTarget(required,remaining,queueHint)
  local parallel=checkRecipe(required)
  local queued=math.max(parallel,queueHint or queuedRecipes())
  local count=queued
  -- Bound the prepared window, not the AE order. Align the raw-fluid ceiling.
  for name in pairs(required) do
    local unit=units[name] or 144
    local limit=math.floor(2147483647/unit)*unit
    local now=integer(remaining[name])
    assert(now<=limit,'当前实际并行单轮需求超过单次供液上限: '..name..' / '..now..' mB；请降低机器最大并行')
    local per=perRecipe[name]
    assert(type(per)=='number' and per>0,'单配方需求不可读: '..name)
    count=math.min(count,parallel+math.floor((limit-now)/per))
  end
  local target={}
  for name in pairs(required) do
    target[name]=remaining[name]+perRecipe[name]*(count-parallel)
  end
  return target,count,queued
end
local function needsRefill(required,consumed,stock,queueHint)
  local remaining={}
  for name,amount in pairs(required) do
    local used=integer(consumed[name] or 0)
    assert(used<=amount,'当前消耗超过本轮需求: '..name)
    remaining[name]=amount-used
  end
  local window,count=batchTarget(required,remaining,queueHint)
  local parallel=checkRecipe(required)
  local ahead=math.min(parallel,math.max(0,count-parallel))
  for name in pairs(required) do
    -- Keep one following physical batch ready. Do not pause to refill the
    -- entire large queue after every completed recipe or small stock change.
    local low=math.min(window[name],remaining[name]+perRecipe[name]*ahead)
    if (stock[name] or 0)<low then return true end
  end
  return false
end
