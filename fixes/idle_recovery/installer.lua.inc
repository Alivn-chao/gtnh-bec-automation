local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original=read(path)
if original:find('BEC_V1_IDLE_RECOVERY_V1:',1,true)then print('空闲末批恢复补丁已安装');return end
assert(original:find('BEC_V1_PRODUCTION_OVERLAP_V3:',1,true),'需要生产并行V3')
assert(original:find('BEC_V1_BATCH_STOP_V1:',1,true),'先安装逐批关机补丁，避免恢复后继续跨批缺料')
local start='if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then'
local a,b=original:find(start,1,true);assert(a and not original:find(start,b+1,true),'流水恢复入口缺失或不唯一')
local finish=assert(original:find('local streaming=',b+1,true),'流水恢复结束入口缺失')
local modified=original:sub(1,a-1)..[==[RECOVER_BODY]==]..'\n'..original:sub(finish)
assert(load(modified,'@'..path,'t',_ENV),'恢复补丁语法检查失败')
local function stopped()
 assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先按Q正常退出UI')
 assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
  and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'先等纠缠装置停稳')
end
stopped();assert(read(path)==original,'检查期间控制器变化')
local n=1;while fs.exists(path..'.before-idle-recovery-'..n)or fs.exists(path..'.idle-recovery-new-'..n)do n=n+1 end
local backup,temp=path..'.before-idle-recovery-'..n,path..'.idle-recovery-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified,'临时文件回读失败')
stopped();assert(read(path)==original,'写入期间控制器变化')
assert(fs.rename(path,backup),'控制器备份失败')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'备份还原失败');error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'安装回读失败')
print('空闲末批恢复补丁已安装；备份: '..backup)
print('原日志未修改。恢复时保存末批消耗审计并归档旧流水；继续: lua /home/bec_ui.lua resume')
