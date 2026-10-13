-- BEC_V1_BATCH_STOP_V1: latch work off before releasing each physical batch.
CONTROL_BODY
local batchControl
local function batchWork(enabled)
 batchControl=batchControl or batchControlAddress(c)
 -- The generic gt_machine and bec_io_node must refer to the same physical node.
 assert(call(batchControl,"getState")==call(NODE,"getState"),"启停组件与传送节点状态不一致")
 assert(call(batchControl,"getParallelRecipesInProgress")==call(NODE,"getParallelRecipesInProgress"),"启停组件与节点并行不一致")
 local a,b=call(batchControl,"getRequiredCondensate"),call(NODE,"getRequiredCondensate")
 assert((a==nil and b==nil) or (type(a)=="table" and type(b)=="table" and same(a,b)),"启停组件与节点配方不一致")
 if call(batchControl,"isWorkAllowed")~=enabled then
  record.batchStop={control=batchControl,enabled=enabled,phase="pending"};save(record.stage)
  call(batchControl,"setWorkAllowed",enabled)
  assert(call(batchControl,"isWorkAllowed")==enabled,"传送节点启停回读不符")
  record.batchStop.phase="confirmed";save(record.stage)
 end
end
local function batchBetween()
 -- Immediate pause is set before allowing an idle node to accept the next recipe.
 assert(call(RS,"getOutput",sides.top)==15,"接收下一批前必须立即暂停")
 batchWork(call(NODE,"getState")=="idle")
end
local continuousBatchPrepare=prepareStreaming
prepareStreaming=function(target)
 -- Beta 3 finishes the active batch with workAllowed=false but skips checkRecipe.
 batchWork(false)
 return continuousBatchPrepare(target)
end
local continuousBatchPause=pause
pause=function(value)
 if value==0 then batchWork(false) end
 return continuousBatchPause(value)
end
