from pathlib import Path
folder=Path(__file__).parent
changes=[
('local fault,stopRequested=false,false','local fault,stopRequested=false,false -- BEC_V1_UI_PAUSE_V1\nlocal pauseReason,retryRequested=nil,false'),
('fault and "程序已退出"','fault and "暂停：待处理"'),
('"EVENTS / "..(stages[record.stage] or record.stage or "等待订单")','"EVENTS / "..(fault and "已暂停 / 待处理" or stages[record.stage] or record.stage or "等待订单")'),
('end gpu.setBackground(bg);gpu.setForeground(accent)', '''end
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
end gpu.setBackground(bg);gpu.setForeground(accent)'''),
('gpu.set(2,h-2,fit("[ S 样板处理 ]  [ N 缓存翻页 ]",w-3))','gpu.set(2,h-2,fit("[ S 样板处理 ]  [ N 缓存翻页 ]",w-3))\nif fault then text(60,h-2,"[ T 重试 / 继续 ]",w-61,0xffffff,0xb00020) end'),
('if text:find("程序停止",1,true) then fault=true end','''if text:find("程序停止",1,true) then
 fault=true;pauseReason=text:match("([^\\n]+)") or text
 pauseReason=pauseReason:gsub("^程序停止：%s*",""):gsub("^程序停止:%s*",""):gsub("^/home/[^:]+:%d+:%s*","")
end'''.replace(')\n"',')\\n"')),
('local function handle(e) if showCache then','''local function handle(e)
if fault and mode~="monitor" and ((e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=60)
 or (e[1]=="key_down" and (e[3]==116 or e[3]==84))) then
 retryRequested=true;return {}
end
if showCache then'''),
('assert(ok,n);deadline=', '''if not ok then capture("程序停止: "..tostring(n));deadline=math.huge;filter=nil;return end
deadline='''),
('advance() while coroutine.status(service)~="dead" do','while true do\nadvance() while coroutine.status(service)~="dead" do'),
('draw(true) if fault then repeat handle({pullUI(0.1)});if not stopRequested then draw(false) end until stopRequested end', '''draw(true)
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
end'''),
]
head=(folder/'patch_v1.lua').read_text(encoding='utf-8').split("local original=read(path)",1)[0]
tail=(folder/'patch_v1.lua').read_text(encoding='utf-8').split("assert(load(modified",1)[1]
tail='assert(load(modified'+tail
tail=tail.replace('ui-speed','ui-pause').replace('UI调度与耗时记录补丁已安装','暂停原因与继续按钮已安装')
code=head+'''local original=read(path)
if original:find('BEC_V1_UI_PAUSE_V1',1,true)then print('暂停面板已安装');return end
assert(original:find('BEC_V1_UI_SPEED_V2',1,true),'请先安装UI调度V2补丁')
local modified=original:gsub('\\r\\n','\\n')
'''
for before,after in changes:code+='modified=replace(modified,[=['+before+']=],[=['+after+']=])\n'
(folder/'patch_pause.lua').write_text(code+tail,encoding='utf-8')
