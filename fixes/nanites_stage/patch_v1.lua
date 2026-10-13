-- Patch the installed V1; never overwrite it with the historical root controller.
local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original=read(path)
if original:find('BEC_V1_NANITES_STAGE_V1',1,true)then print('阶段优选换蜂补丁已安装');return end
assert(original:find('BEC_V1_PRODUCTION_OVERLAP_V3',1,true),'先安装最新生产并行 V3 补丁')
assert(original:find('/home/bec_nanites.lua',1,true),'须使用已接入自动换蜂的V1控制器，不能替换历史基准文件')
local worker=assert(loadfile('/home/bec_nanites.lua','t',_ENV))()
assert(type(worker)=='table' and type(worker.needsSwitch)=='function','先安装新版阶段优选蜂群模块')
local function insert(s,marker,body)
 local a,b=s:find(marker,1,true);assert(a and not s:find(marker,b+1,true),'入口缺失或不唯一: '..marker)
 return s:sub(1,a-1)..body..s:sub(a)
end
local modified=insert(original,'-- BEC_V1_PRODUCTION_OVERLAP_V3:','local serviceNaniteStage\n')
modified=insert(modified,'local function serve()',[==[-- BEC_V1_NANITES_STAGE_V1: prefer exact-stage bees, retain compatible fallback.
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
 if not same(normalized,expected) then return end -- The recipe/filter controller owns new recipes.
 local required=call(NODE,"getRequiredTier")
 if type(required)~="table" or type(required.tier)~="number" then return end
 local signature=tostring(required.name)..":"..required.tier
 if signature==stageSignature and computer.uptime()<(stageCheckAt or 0) then return end
 if not stageWorker then
  local loader=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")
  stageWorker=loader()
  assert(type(stageWorker)=="table" and type(stageWorker.needsSwitch)=="function","请先安装新版阶段优选蜂群模块")
 end
 stageSignature=signature;stageCheckAt=computer.uptime()+2
 if not stageWorker.needsSwitch() then return end
 stageBusy=true
 local ok,reason=xpcall(function()
  local output=call(RS,"getOutput",sides.top)
  assert(output==0 or output==15,"换蜂前暂停输出异常")
  local converting=call(GEN,"isWorkAllowed")
  pause(15);generator(false)
  local limit=computer.uptime()+190
  local function stoppedCheck()
   if record.gateIntent then verifyGate(record.gateIntent.filters) end
   assert(same(call(NODE,"getRequiredCondensate"),req)
    and call(NODE,"getParallelRecipesInProgress")==parallel,"换蜂等待时配方发生变化，保持暂停")
   local value=call(NODE,"getRequiredTier")
   assert(type(value)=="table" and value.tier==required.tier and value.name==required.name,"换蜂等待时阶段发生变化，保持暂停")
  end
  while true do
   stoppedCheck()
   if stopping then return end
   local s=call(NODE,"getState")
   if (s=="paused-immediate" or s=="nanite-tier-too-low") and call(GEN,"isMachineActive")==false then break end
   assert(computer.uptime()<limit,"阶段换蜂停机超时，保持暂停")
   originalStageTick(0.1)
  end
  local used=call(NODE,"getConsumedCondensate")
  assert(type(used)=="table","换蜂前消耗记录不可读")
  local function checked()
   stoppedCheck()
   assert(same(call(NODE,"getConsumedCondensate"),used),"暂停换蜂期间消耗发生变化，保留现场")
  end
  record.naniteStage={required=required,consumed=used,stage="switching"};save(record.stage)
  print("阶段换蜂：需求 "..tostring(required.name).." / T"..required.tier.."，优先对应库存")
  stageWorker.ensure({check=checked,tick=originalStageTick,stopping=function()return stopping end})
  checked()
  local p=call(NODE,"getProvidedTier")
  assert(type(p)=="table" and p.tier>=required.tier and call(NODE,"getAvailableNanites")>=64,"阶段换蜂后等级或数量不足")
  record.naniteStage=nil;save(record.stage)
  if not stopping then
   if converting then generator(true) end
   pause(output) -- Restore only our previous output; the production guard still checks funding.
  end
 end,debug.traceback)
 stageBusy=false
 if not ok then pcall(pause,15);pcall(generator,false);error(reason) end
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
