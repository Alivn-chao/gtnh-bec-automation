-- Patch only V1's batch sizing and low-stock trigger; preserve other fixes.
local fs=require('filesystem')
local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return text end
local original=read(path)
if original:find('BEC_V1_ORDER_WINDOW_V1',1,true)then print('大订单分批补丁已安装');return end
local function section(text,first,last,new)
 local a=assert(text:find(first,1,true),'找不到定位: '..first)
 assert(not text:find(first,a+#first,true),'定位不唯一: '..first)
 local b=assert(text:find(last,a+#first,true),'找不到结束定位: '..last)
 return text:sub(1,a-1)..new..text:sub(b)
end
local modified=section(original,'local function batchTarget(required,remaining)','local function unchanged()',[==[-- BEC_V1_ORDER_WINDOW_V1
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
]==])
modified=section(modified,'local refill=false','if refill then break end',[==[local refill=false
if req~=nil then
 if computer.uptime()>=nextQueueCheck then windowQueue=queuedRecipes();nextQueueCheck=computer.uptime()+1 end
 local consumed=call(NODE,"getConsumedCondensate")
 assert(type(consumed)=="table","当前消耗记录不可读")
 refill=needsRefill(req,consumed,stock,windowQueue)
 if refill then
  windowQueue=queuedRecipes()
  refill=needsRefill(req,consumed,stock,windowQueue)
 end
end
]==])
modified=section(modified,'local nextQueueCheck=0','while not stopping do','local nextQueueCheck=0 local windowQueue\n')
modified=modified:gsub('record%.batchCount=count','record.batchCount=count;record.windowed=true')
local from='type(old.batchCount)=="number" and count<=old.batchCount'
local a,b=modified:find(from,1,true)
assert(a and not modified:find(from,b+1,true),'旧转换恢复批量检查入口缺失或不唯一，原程序未修改')
modified=modified:sub(1,a-1)..'type(old.batchCount)=="number" and (old.windowed==true or count<=old.batchCount)'..modified:sub(b+1)
modified=modified:gsub('按主网 CPU 剩余任务量，一次准备整批原液；追加订单自动补差额。','按主网剩余任务分批备料，整个AE订单保留；库存不足自动接续。')
modified=modified:gsub('主网剩余配方 ','本轮备料配方 ')
modified=modified:gsub('一次准备整批所需流体。','按安全批量备料，大订单自动接续。')
modified=modified:gsub('整批流体齐备，已连续放行；追加订单自动补整批差额。','本轮备料齐备，已连续放行；库存不足时自动准备下一批。')
assert(load(modified,'@'..path,'t',_ENV),'分批补丁语法检查失败')
assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先正常Q退出服务，保持节点暂停15')
assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'纠缠装置须停机')
local n=1;while fs.exists(path..'.before-window-'..n)or fs.exists(path..'.window-new-'..n)do n=n+1 end
local backup,temp=path..'.before-window-'..n,path..'.window-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close()
assert(read(temp)==modified,'分批临时文件回读失败')
assert(fs.rename(path,backup),'备份失败，原程序保留')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'还原失败，备份: '..backup);error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'分批补丁或备份回读失败')
print('大订单分批已安装；备份: '..backup)
print('没有取消AE订单、搬料或修改日志。继续运行: lua /home/bec_ui.lua resume')
