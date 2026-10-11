-- UI-only patch. Display caching never supplies data to the controller.
local fs=require('filesystem')
local path='/home/bec_ui.lua'
local function read(p)
 local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return assert(text)
end
local function replace(text,from,to)
 local a,b=text:find(from,1,true)
 assert(a and not text:find(from,b+1,true),'UI版本入口缺失或不唯一，原文件未改')
 return text:sub(1,a-1)..to..text:sub(b+1)
end
local original=read(path)
if original:find('BEC_V1_UI_PAUSE_V1',1,true)then print('暂停面板已安装');return end
assert(original:find('BEC_V1_UI_SPEED_V2',1,true),'请先安装UI调度V2补丁')
local modified=original:gsub('\r\n','\n')
modified=replace(modified,[=[local fault,stopRequested=false,false]=],[=[local fault,stopRequested=false,false -- BEC_V1_UI_PAUSE_V1
local pauseReason,retryRequested=nil,false]=])
modified=replace(modified,[=[fault and "程序已退出"]=],[=[fault and "暂停：待处理"]=])
modified=replace(modified,[=["EVENTS / "..(stages[record.stage] or record.stage or "等待订单")]=],[=["EVENTS / "..(fault and "已暂停 / 待处理" or stages[record.stage] or record.stage or "等待订单")]=])
modified=replace(modified,[=[end gpu.setBackground(bg);gpu.setForeground(accent)]=],[=[end
local reason=pauseReason
if not fault then
 if state=="unpowered" then reason="供电不足：检查机器供电"
 elseif state=="assembler-offline" then reason="观测阵列未就绪：检查连接与运行状态"
 elseif state=="nanite-tier-too-low" then reason="蜂群等级不足：检查所需蜂群"
 end
end
if reason then
 text(3,22,"暂停原因："..reason,w-5,0xffffff,0xb00020)
 if h>25 then text(3,23,fault and "处理后点击下方继续；恢复时重新核对记录" or "等待条件满足后，常驻服务继续检查",w-5,0xffffff,0xb00020) end
end gpu.setBackground(bg);gpu.setForeground(accent)]=])
modified=replace(modified,[=[gpu.set(2,h-2,fit("[ S 样板处理 ]  [ N 缓存翻页 ]",w-3))]=],[=[gpu.set(2,h-2,fit("[ S 样板处理 ]  [ N 缓存翻页 ]",w-3))
if fault then text(60,h-2,"[ T 重试 / 继续 ]",w-61,0xffffff,0xb00020) end]=])
modified=replace(modified,[=[if text:find("程序停止",1,true) then fault=true end]=],[=[if text:find("程序停止",1,true) then
 fault=true;pauseReason=text:match("([^\n]+)") or text
 pauseReason=pauseReason:gsub("^程序停止：%s*",""):gsub("^程序停止:%s*",""):gsub("^/home/[^:]+:%d+:%s*","")
end]=])
modified=replace(modified,[=[local function handle(e) if showCache then]=],[=[local function handle(e)
if fault and mode~="monitor" and ((e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=60)
 or (e[1]=="key_down" and (e[3]==116 or e[3]==84))) then
 retryRequested=true;return {}
end
if showCache then]=])
modified=replace(modified,[=[assert(ok,n);deadline=]=],[=[if not ok then capture("程序停止: "..tostring(n));deadline=math.huge;filter=nil;return end
deadline=]=])
modified=replace(modified,[=[advance() while coroutine.status(service)~="dead" do]=],[=[while true do
advance() while coroutine.status(service)~="dead" do]=])
modified=replace(modified,[=[draw(true) if fault then repeat handle({pullUI(0.1)});if not stopRequested then draw(false) end until stopRequested end]=],[=[draw(true)
if fault and not stopRequested then
 repeat handle({pullUI(0.1)});if not stopRequested then draw(false) end until stopRequested or retryRequested
 if stopRequested then break end
 retryRequested=false;fault=false;pauseReason=nil;clearDisplayCache()
 -- Only the existing validated recovery entry point may restart a controller.
 -- Never erase, rewrite or silently mark unconfirmed operations as done here.
 local f=io.open("/home/bec_auto.journal","r");local retryMode=f and "resume" or "run";if f then f:close() end
 service=coroutine.create(function() controller(retryMode) end);activeService=service
 deadline=nil;filter=nil;started=computer.uptime()
else break end
end]=])
assert(load(modified,'@'..path,'t',_ENV),'补丁后语法检查失败')
local n=1;while fs.exists(path..'.before-ui-pause-'..n) or fs.exists(path..'.ui-pause-new-'..n) do n=n+1 end
local backup,temp=path..'.before-ui-pause-'..n,path..'.ui-pause-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close()
assert(read(temp)==modified,'临时文件回读失败')
assert(fs.rename(path,backup),'备份失败，原文件保留')
if not fs.rename(temp,path) then assert(fs.rename(backup,path),'还原失败，原文件在 '..backup);error('替换失败，已还原') end
assert(read(path)==modified and read(backup)==original,'替换或备份回读失败')
print('暂停原因与继续按钮已安装；备份: '..backup)
print('生产控制器、订单和日志均未修改。正常Q停止后继续: lua /home/bec_ui.lua run')
