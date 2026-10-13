local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original=read(path)
if original:find('BEC_V1_BATCH_STOP_V1:',1,true)then print('逐批关机补丁已安装');return end
assert(original:find('BEC_V1_PRODUCTION_OVERLAP_V3:',1,true),'需要已安装生产并行 V3 的控制器')
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

local control=batchControlAddress(c)
print('节点启停组件: '..control..'；安装过程不启停机器')
local first,last=original:find('local function serve()',1,true)
assert(first and not original:find('local function serve()',last+1,true),'服务入口缺失或不唯一')
local modified=original:sub(1,first-1)..[==[-- BEC_V1_BATCH_STOP_V1: latch work off before releasing each physical batch.
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
]==]..'\n'..original:sub(first)
local count
modified,count=modified:gsub('(while not stopping do%s+pause%(15%);%s*generator%(false%)%s+)(local state=call%(NODE,%s*"getState"%))','%1batchBetween()\n    %2')
assert(count==1,'逐批接单入口缺失或不唯一，未改原文件')
modified,count=modified:gsub('(pause%(15%);%s*generator%(false%);%s*)(record.configOwned=false)','%1batchWork(false);%2')
assert(count==1,'退出入口缺失或不唯一，未改原文件')
assert(load(modified,'@'..path,'t',_ENV),'逐批关机补丁语法检查失败')
local function stopped()
 assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先按Q退出UI')
 assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
  and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'先等纠缠装置停稳')
end
stopped();assert(read(path)==original,'控制器已变化，取消安装')
local n=1;while fs.exists(path..'.before-batch-stop-'..n)or fs.exists(path..'.batch-stop-new-'..n)do n=n+1 end
local backup,temp=path..'.before-batch-stop-'..n,path..'.batch-stop-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified,'临时文件回读失败')
stopped();assert(read(path)==original,'写入期间控制器变化，取消安装')
assert(fs.rename(path,backup),'备份失败')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'备份还原失败');error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'文件回读失败')
print('逐批关机补丁已安装；备份: '..backup)
print('订单/日志不改；缺料停机的旧记录仍须核对，补丁不会伪造完成或重新下单。')
