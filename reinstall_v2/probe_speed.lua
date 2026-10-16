-- BEC V2 speed probe. Read-only, one pass; never writes files or machine outputs.
local c=require('component')
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local cfg=C.load();C.validate(cfg,false)
print('BEC V2 SPEED PROBE - READ ONLY / ONE PASS')
print('Estimate = recipe ticks advanced per server tick; excludes waiting and TPS loss.')
local names={'getState','getRequiredTier','getProvidedTier','getAvailableNanites','getParallelRecipesInProgress','getSlowdowns','getManualSlowdown'}
local function tier(v)return type(v)=='table'and v.tier or v end
local function valid(v)return type(v)=='number'and v==v and v>=0 and v<math.huge end
for i,n in ipairs(cfg.nodes)do
 print(('--- Node %d / %s ---'):format(i,n.name or n.address))
 local ok,methods=pcall(c.methods,n.address)
 local values={}
 for _,method in ipairs(names)do
  if ok and type(methods)=='table'and methods[method]~=nil then
   local readable,value=pcall(c.invoke,n.address,method)
   if readable then values[method]=value else print(method..': unavailable / '..tostring(value))end
  else print(method..': method unavailable')end
 end
 local state,need,provided=values.getState,tier(values.getRequiredTier),tier(values.getProvidedTier)
 local count,p,dirty,manual=values.getAvailableNanites,values.getParallelRecipesInProgress,values.getSlowdowns,values.getManualSlowdown
 print('State: '..tostring(state))
 print(('Nanites: %s / required T%s / provided T%s'):format(tostring(count),tostring(need),tostring(provided)))
 print(('Parallel: %s / contaminants: %s / manual slowdown: %s'):format(tostring(p),tostring(dirty),tostring(manual)))
 if valid(need)and valid(provided)and provided<need then
  print('BLOCKED: nanite tier too low; more nanites of this tier cannot fix it.')
 elseif state=='idle'then
  print('IDLE: no active recipe speed estimate.')
 elseif valid(need)and valid(provided)and valid(count)and valid(p)and p>=1 and valid(dirty)and valid(manual)and manual>=1 then
  local gap=provided-need
  local penalty=2^gap;local slowdown=math.max(dirty+1,manual)
  local rate=count/p/penalty/slowdown
  print(('Estimated active speed: %.4f recipe ticks / server tick'):format(rate))
  print(('Divisors: parallel %s x tier %.0f x slowdown %s'):format(p,penalty,slowdown))
  if gap>0 then print('TIER PENALTY: compare counts as well as tier; higher is not automatically faster.')end
  if dirty>0 then print('CONTAMINATION: review Maxwell gate filtering / reachable unrelated condensates.')end
  if dirty>3 then print('BLOCKED: more than 3 contaminants triggers clogged shutdown in this GTNH version.')end
  if manual>1 then print('MANUAL SLOWDOWN: inspect the node speed divisor before changing it.')end
  if state~='crafting'then print('NOTE: currently paused/blocked; estimate applies only while actually crafting.')end
 else print('No estimate: missing/invalid active recipe readings; do not assume zero slowdown.')end
end
print('Done. No polling, outputs, transfers, settings or files changed.')
