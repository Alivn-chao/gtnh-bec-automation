-- Patch the installed V1; never overwrite it with the historical root controller.
local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original=read(path)
if original:find('BEC_V1_NANITES_STAGE_V2',1,true)then print('阶段停稳换蜂补丁已安装');return end
assert(original:find('BEC_V1_PRODUCTION_OVERLAP_V3',1,true),'先安装最新生产并行 V3 补丁')
assert(original:find('/home/bec_nanites.lua',1,true),'须使用已接入自动换蜂的V1控制器，不能替换历史基准文件')
local worker=assert(loadfile('/home/bec_nanites.lua','t',_ENV))()
assert(type(worker)=='table' and type(worker.needsSwitch)=='function' and worker.passiveStages,'先安装新版自动停顿换蜂模块')
local function insert(s,marker,body)
 local a,b=s:find(marker,1,true);assert(a and not s:find(marker,b+1,true),'入口缺失或不唯一: '..marker)
 return s:sub(1,a-1)..body..s:sub(a)
end
local modified
local legacy='-- BEC_V1_NANITES_STAGE_V1:'
local first,last=original:find(legacy,1,true)
if first then
 assert(not original:find(legacy,last+1,true),'旧阶段换蜂入口不唯一')
 local finish=assert(original:find('local function serve()',last+1,true),'旧阶段换蜂结束入口缺失')
 modified=original:sub(1,first-1)..[==[-- BEC_V1_NANITES_STAGE_V2: let the node stall itself; exchange bees live.
local stageBusy=false
local stageSignature,stageCheckAt
local stageWorker
local originalStageTick=tick
serviceNaniteStage=function()
 if stageBusy or stopping or not record then return end
 local overlapping=record.pipeline and record.pipeline.overlap
 if record.stage~="watching" and not overlapping then return end
 local state=call(NODE,"getState")
 if state~="crafting" and state~="paused-immediate" and state~="nanite-tier-too-low" then return end
 local req=call(NODE,"getRequiredCondensate")
 local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)~="table" or type(parallel)~="number" or parallel<1 then return end
 local normalized={};for name,n in pairs(req)do normalized[name]=integer(n)/parallel end
 local expected=overlapping and record.pipeline.recipe or perRecipe
 if not same(normalized,expected) then return end
 local required=call(NODE,"getRequiredTier")
 if type(required)~="table" or type(required.tier)~="number" then return end
 local signature=tostring(required.name)..":"..required.tier
 if signature==stageSignature and computer.uptime()<(stageCheckAt or 0) then return end
 if not stageWorker then
  local loader=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")
  stageWorker=loader()
  assert(type(stageWorker)=="table" and type(stageWorker.needsSwitch)=="function" and stageWorker.passiveStages,
   "请先安装新版自动停顿换蜂模块")
 end
 stageSignature=signature;stageCheckAt=computer.uptime()+2
 if not stageWorker.needsSwitch() then return end
 stageBusy=true
 local ok,reason=xpcall(function()
  -- Stage and consumption may advance while compatible bees keep working.
  -- Do not freeze those hints or drive node/GEN outputs to exchange bees.
  local function checked()
   if record.gateIntent then verifyGate(record.gateIntent.filters) end
  end
  checked()
  record.naniteStage={required=required,stage="switching"};save(record.stage)
  print("阶段换蜂：优先对应库存；等级不足由节点自动停顿")
  stageWorker.ensure({passive=true,check=checked,tick=originalStageTick,stopping=function()return stopping end})
  checked()
  record.naniteStage=nil;save(record.stage)
  local latest=call(NODE,"getRequiredTier")
  if type(latest)=="table" and latest.tier==required.tier and latest.name==required.name then
   stageSignature=signature;stageCheckAt=computer.uptime()+2
  else stageSignature=nil;stageCheckAt=0 end
 end,debug.traceback)
 stageBusy=false
 if not ok then error(reason) end
end
tick=function(seconds)
 originalStageTick(seconds)
 if not stopping then serviceNaniteStage() end
end
]==]..'\n'..original:sub(finish)
else
modified=insert(original,'-- BEC_V1_PRODUCTION_OVERLAP_V3:','local serviceNaniteStage\n')
modified=insert(modified,'local function serve()',[==[-- BEC_V1_NANITES_STAGE_V2: let the node stall itself; exchange bees live.
local stageBusy=false
local stageSignature,stageCheckAt
local stageWorker
local originalStageTick=tick
serviceNaniteStage=function()
 if stageBusy or stopping or not record then return end
 local overlapping=record.pipeline and record.pipeline.overlap
 if record.stage~="watching" and not overlapping then return end
 local state=call(NODE,"getState")
 if state~="crafting" and state~="paused-immediate" and state~="nanite-tier-too-low" then return end
 local req=call(NODE,"getRequiredCondensate")
 local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)~="table" or type(parallel)~="number" or parallel<1 then return end
 local normalized={};for name,n in pairs(req)do normalized[name]=integer(n)/parallel end
 local expected=overlapping and record.pipeline.recipe or perRecipe
 if not same(normalized,expected) then return end
 local required=call(NODE,"getRequiredTier")
 if type(required)~="table" or type(required.tier)~="number" then return end
 local signature=tostring(required.name)..":"..required.tier
 if signature==stageSignature and computer.uptime()<(stageCheckAt or 0) then return end
 if not stageWorker then
  local loader=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")
  stageWorker=loader()
  assert(type(stageWorker)=="table" and type(stageWorker.needsSwitch)=="function" and stageWorker.passiveStages,
   "请先安装新版自动停顿换蜂模块")
 end
 stageSignature=signature;stageCheckAt=computer.uptime()+2
 if not stageWorker.needsSwitch() then return end
 stageBusy=true
 local ok,reason=xpcall(function()
  -- Stage and consumption may advance while compatible bees keep working.
  -- Do not freeze those hints or drive node/GEN outputs to exchange bees.
  local function checked()
   if record.gateIntent then verifyGate(record.gateIntent.filters) end
  end
  checked()
  record.naniteStage={required=required,stage="switching"};save(record.stage)
  print("阶段换蜂：优先对应库存；等级不足由节点自动停顿")
  stageWorker.ensure({passive=true,check=checked,tick=originalStageTick,stopping=function()return stopping end})
  checked()
  record.naniteStage=nil;save(record.stage)
  local latest=call(NODE,"getRequiredTier")
  if type(latest)=="table" and latest.tier==required.tier and latest.name==required.name then
   stageSignature=signature;stageCheckAt=computer.uptime()+2
  else stageSignature=nil;stageCheckAt=0 end
 end,debug.traceback)
 stageBusy=false
 if not ok then error(reason) end
end
tick=function(seconds)
 originalStageTick(seconds)
 if not stopping then serviceNaniteStage() end
end
]==]..'\n')
local marker='local function productionGuard()'
local a,b=modified:find(marker,1,true);assert(a and not modified:find(marker,b+1,true),'阶段检查入口不唯一')
modified=modified:sub(1,b)..'\n  serviceNaniteStage()\n'..modified:sub(b+1)
local recovery='local old=ser.unserialize(contents)'
local x,y=modified:find(recovery,1,true);assert(x and not modified:find(recovery,y+1,true),'恢复入口缺失或不唯一')
modified=modified:sub(1,y)..'; assert(not(type(old)=="table" and old.naniteStage),"旧阶段换蜂未确认完成，保留蜂群与生产日志，禁止重放") '..modified:sub(y+1)
end
local insufficient='else changed=true;reason="蜂群不足以运行当前阶段，等待旧窗口收尾" end'
local p,q=modified:find(insufficient,1,true);assert(p and not modified:find(insufficient,q+1,true),'蜂群不足处理入口缺失或不唯一')
modified=modified:sub(1,p-1)..'else neededTier=nextTier;tierCovered=true end'..modified:sub(q+1)
assert(load(modified,'@'..path,'t',_ENV),'阶段换蜂补丁语法检查失败')
local function paused()
 assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先按Q正常退出生产UI')
 assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
  and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'先等纠缠装置停稳')
end
paused();assert(read(path)==original,'检查期间控制器变化，取消安装')
local n=1;while fs.exists(path..'.before-nanite-stage-'..n)or fs.exists(path..'.nanite-stage-new-'..n)do n=n+1 end
local backup,temp=path..'.before-nanite-stage-'..n,path..'.nanite-stage-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified,'临时文件回读失败')
paused();assert(read(path)==original,'写入期间控制器变化，取消安装')
assert(fs.rename(path,backup),'备份失败')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'备份还原失败');error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'文件回读失败')
print('阶段优选换蜂已安装；备份: '..backup)
print('配置、订单和日志保留。继续: lua /home/bec_ui.lua resume')
