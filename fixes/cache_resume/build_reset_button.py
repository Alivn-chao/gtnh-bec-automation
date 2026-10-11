from pathlib import Path
import subprocess
folder=Path(__file__).parent
base=(folder.parent/'ui_speed/patch_v1.lua').read_text(encoding='utf-8')
worker=(folder/'reset_cache.lua').read_text(encoding='utf-8')
changes=[
('local pauseReason,retryRequested=nil,false','local pauseReason,retryRequested=nil,false -- BEC_V1_UI_CACHE_RESET_V2\nlocal resetRequested=false'),
('if fault then text(60,h-2,"[ T 重试 / 继续 ]",w-61,0xffffff,0xb00020) end',
 'if fault then text(2,h-2,"[ Z 放弃缓存 / 重置 ]",28,0xffffff,0xb00020);text(60,h-2,"[ T 重试 / 继续 ]",w-61,0xffffff,0xb00020) end'),
('local function handle(e)\nif fault', '''local function handle(e)
if fault and mode~="monitor" and ((e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=2 and e[3]<=28)
 or (e[1]=="key_down" and (e[3]==122 or e[3]==90))) then
 resetRequested=true;retryRequested=true;return {}
end
if fault'''),
('retryRequested=false;fault=false;pauseReason=nil;clearDisplayCache()',
 'local doReset=resetRequested;resetRequested=false;retryRequested=false;fault=false;pauseReason=nil;clearDisplayCache()'),
('service=coroutine.create(function() controller(retryMode) end);activeService=service', '''service=coroutine.create(function()
 if doReset then
  local ok,err=cacheResetWorker();assert(ok,err)
  cacheView=nil;showCache=false;clearDisplayCache()
 end
 controller(retryMode)
end);activeService=service'''),
('end local function mainUI()', 'end local function cacheResetWorker()\n'+worker+'\nend\nlocal function mainUI()'),
]
head=base.split('local original=read(path)',1)[0]
tail='assert(load(modified'+base.split('assert(load(modified',1)[1]
tail=tail.replace('ui-speed','ui-reset').replace('UI调度与耗时记录补丁已安装','通用缓存重置按键已安装')
code=head+'''local original=read(path)
if original:find('BEC_V1_UI_CACHE_RESET_V2',1,true)then print('缓存重置按键V2已安装');return end
assert(original:find('BEC_V1_UI_PAUSE_V1',1,true),'请先安装暂停原因面板补丁')
local modified=original:gsub('\\r\\n','\\n')
'''
oldWorker=subprocess.check_output(['git','show','f439a94:fixes/cache_resume/reset_cache.lua'],cwd=folder).decode('utf-8').replace('\r\n','\n')
code+="if original:find('BEC_V1_UI_CACHE_RESET_V1',1,true)then\nmodified=replace(modified,'BEC_V1_UI_CACHE_RESET_V1','BEC_V1_UI_CACHE_RESET_V2')\n"
code+='modified=replace(modified,[=['+oldWorker+']=],[=['+worker+']=])\nelse\n'
for before,after in changes:code+='modified=replace(modified,[=['+before+']=],[=['+after+']=])\n'
code+='end\n'
tail=tail.replace('正常Q停止后继续: lua /home/bec_ui.lua run','启动故障面板: lua /home/bec_ui.lua resume；按Z放弃本轮缓存并重置')
(folder/'patch_reset_button.lua').write_text(code+tail,encoding='utf-8')
