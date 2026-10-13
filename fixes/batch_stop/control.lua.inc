local function batchControlAddress(component)
 local candidates={}
 for address in component.list() do
  local methods=component.methods(address)
  if methods.getRequiredCondensate~=nil and methods.getParallelRecipesInProgress~=nil
   and methods.getState~=nil and methods.setWorkAllowed~=nil and methods.isWorkAllowed~=nil then
   candidates[#candidates+1]=address
  end
 end
 assert(#candidates==1,"需要唯一可启停的传送节点组件；请用适配器连接节点并提供 gt_machine（当前找到 "..#candidates.." 个）")
 return candidates[1]
end
