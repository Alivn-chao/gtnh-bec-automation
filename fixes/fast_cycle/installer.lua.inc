local fs=require('filesystem');local c=require('component');local ser=require('serialization')
local auto='/home/bec_auto.lua';local bees='/home/bec_nanites.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original,module=read(auto),read(bees)
local fastModule=[==[MODULE_BODY]==]
if original:find('BEC_V1_FAST_CYCLE_V1:',1,true)and module==fastModule then print('快速切换补丁已安装');return end
assert(not original:find('BEC_V1_FAST_CYCLE_V1:',1,true),'已有不同版本快速补丁，保留原文件')
assert(original:find('BEC_V1_NANITES_STAGE_V2:',1,true) and original:find('BEC_V1_BATCH_STOP_V1:',1,true),'需要被动阶段换蜂V2和逐批关机补丁')
local modified=original
local function replace(old,new)
 local a,b=modified:find(old,1,true);assert(a and not modified:find(old,b+1,true),'加速入口缺失或不唯一: '..old)
 modified=modified:sub(1,a-1)..new..modified:sub(b+1)
end
replace('-- BEC_V1_NANITES_STAGE_V2:','-- BEC_V1_FAST_CYCLE_V1: batch IO reads and single-pass stage decisions.\n-- BEC_V1_NANITES_STAGE_V2:')
replace('if not stageWorker.needsSwitch() then return end',
 'if not stageWorker.fastStages then error("蜂群模块版本不匹配") end\n local current=call(NODE,"getProvidedTier");local count=call(NODE,"getAvailableNanites")\n if type(current)=="table" and current.name==required.name and current.tier==required.tier and type(count)=="number" and count>=64 then return end')
replace('checked()\n  record.naniteStage={required=required,stage="switching"};save(record.stage)\n  print("阶段换蜂：优先对应库存；等级不足由节点自动停顿")',
 'local announced=false\n  local function announce()\n   checked();record.naniteStage={required=required,stage="switching"};save(record.stage)\n   print("阶段换蜂：优先对应库存；等级不足由节点自动停顿");announced=true\n  end')
replace('stageWorker.ensure({passive=true,check=checked,','stageWorker.ensure({passive=true,stage=true,beforeAction=announce,check=checked,')
replace('record.naniteStage=nil;save(record.stage)','if announced then record.naniteStage=nil;save(record.stage) end')
local count
modified,count=modified:gsub('stageCheckAt=computer.uptime%(%)%+2','stageCheckAt=computer.uptime()+0.5')
assert(count==2,'阶段复查入口数量变化')
-- Keep the five-second settling deadline, but sample every game tick.
modified,count=modified:gsub('for i=1,20 do(%s+)tick%(0%.25%);unchanged%(%)','for i=1,100 do%1tick(0.05);unchanged()')
assert(count==1,'接单稳定检查入口缺失或不唯一')
-- Raw fallback still verifies every sample; reduce its fixed wait from 5s to 1s.
modified,count=modified:gsub('(for i=1,20 do unchanged%(%)%;assert%(same%(network%(SUB%),expected%),"原液不稳定"%);)os.sleep%(0%.25%)','%1os.sleep(0.05)')
assert(count==1,'原液稳定检查入口缺失或不唯一')
replace('local batchControl\n','local batchControl\nlocal batchControlVerified=false\n')
replace('batchControl=batchControl or batchControlAddress(c)', 'batchControl=batchControl or batchControlAddress(c)\n if batchControlVerified and call(batchControl,"isWorkAllowed")==enabled then return end')
replace('if call(batchControl,"isWorkAllowed")~=enabled then','batchControlVerified=true\n if call(batchControl,"isWorkAllowed")~=enabled then')
assert(load(modified,'@'..auto,'t',_ENV),'控制器语法检查失败')
local worker=assert(load(fastModule,'@'..bees,'t',_ENV))()
assert(type(worker)=='table' and worker.fastStages,'蜂群模块格式错误')
local function stopped()
 assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'等本次换蜂完成后按Q退出')
 assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
  and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'等纠缠装置停稳')
 local p='/home/bec_nanites_io.journal'
 if fs.exists(p)then local r=ser.unserialize(read(p));assert(type(r)=='table' and r.stage=='done','本次换蜂尚未完成，保留盘和日志，暂不安装')end
end
stopped();worker.preview();assert(read(auto)==original and read(bees)==module,'检查期间文件变化')
local index=1
while fs.exists(auto..'.before-fast-cycle-'..index)or fs.exists(bees..'.before-fast-cycle-'..index)
 or fs.exists(auto..'.fast-cycle-new-'..index)or fs.exists(bees..'.fast-cycle-new-'..index)
 or fs.exists(auto..'.fast-cycle-failed-'..index)or fs.exists(bees..'.fast-cycle-failed-'..index)do index=index+1 end
local paths={auto,bees};local sources={modified,fastModule};local originals={original,module}
local function backup(p)return p..'.before-fast-cycle-'..index end
local function temp(p)return p..'.fast-cycle-new-'..index end
for i,p in ipairs(paths)do
 local f=assert(io.open(temp(p),'w'));assert(f:write(sources[i]));assert(f:flush());f:close();assert(read(temp(p))==sources[i],'临时文件回读失败')
end
stopped();assert(read(auto)==original and read(bees)==module,'写入期间文件变化')
local retired={};local installed={}
local ok,reason=pcall(function()
 for i,p in ipairs(paths)do
  assert(fs.rename(p,backup(p)),'备份失败: '..p);retired[i]=true
  assert(fs.rename(temp(p),p),'替换失败: '..p);installed[i]=true
  assert(read(p)==sources[i] and read(backup(p))==originals[i],'安装回读失败')
 end
end)
if not ok then
 for i=#paths,1,-1 do local p=paths[i]
  if installed[i]then assert(fs.rename(p,p..'.fast-cycle-failed-'..index),'保存失败版本失败')end
  if retired[i]then assert(fs.rename(backup(p),p),'还原失败: '..p);assert(read(p)==originals[i],'还原回读失败')end
 end
 error('安装失败，已还原两文件: '..tostring(reason))
end
print('快速切换补丁已安装；控制器与蜂群模块均已备份。配置、订单和日志保留。')
print('继续: lua /home/bec_ui.lua resume')
