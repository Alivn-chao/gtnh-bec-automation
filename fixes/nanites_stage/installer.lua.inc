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
modified=insert(modified,'local function serve()',[==[STAGE_BODY]==]..'\n')
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
