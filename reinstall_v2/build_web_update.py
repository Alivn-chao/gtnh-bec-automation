"""HTML-only update; works before a complete machine binding is available."""
from pathlib import Path
import subprocess
import zlib
from build import literal
HERE=Path(__file__).resolve().parent
source=(HERE/'files/lib/web_page.html').read_text(encoding='utf-8')
signatures=[]
for ref in ['334125a','81b7724','f60f785','933750b','180bf41','bccf281','438f625']:
 data=subprocess.check_output(['git','show',ref+':reinstall_v2/files/lib/web_page.html'],cwd=HERE.parent)
 signatures.append('['+repr(str(len(data))+':'+str(zlib.adler32(data)&0xffffffff))+']=true')
body=r'''
local fs=require('filesystem')
local target='/home/bec_v2/lib/web_page.html'
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function normal(s)return s and s:gsub('\r\n','\n')end
local function signature(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local binding=read('/home/bec_v2/lib/ochd_bindings.lua')
assert(binding and binding:find('BEC_BULK_SLOTS_10',1,true),'十口网页需要同步升级绑定模块，请运行 update_bulk10.lua；未修改原网页')
local session=read('/home/bec_v2/lib/web_session.lua');local entry=read('/home/bec_v2/web.lua')
assert(session and session:find('BEC_COMPONENT_PICKER_1',1,true)and entry and entry:find('scan_components',1,true),'当前网页需要组件识别后端，请先运行 update_discovery.lua；原网页未改')
assert(session and session:find('BEC_WEB_PATTERNS_1',1,true)and entry:find("'patterns'",1,true),'当前网页需要样板处理后端，请先运行 update_patterns.lua；原网页未改')
assert(session:find('BEC_WEB_CACHE_1',1,true)and entry:find("'cache'",1,true),'请先运行 update_cache.lua 安装缓存管理后端；原网页未改')
local previous=assert(read(target),'需要已安装V2网页；不要用于V1')
if normal(previous)==SOURCE then print('网页启动反馈修复已安装。');return end
assert(SUPPORTED[signature(normal(previous))],'网页有未知本地修改，保留原文件，不覆盖')
local disk=assert(fs.get('/home/bec_v2'));assert(disk.spaceTotal()-disk.spaceUsed()>=#SOURCE+524288,'磁盘空间不足：安装后需保留512KiB')
local n=1;while fs.exists(target..'.before-input-'..n)or fs.exists(target..'.input-new-'..n)or fs.exists(target..'.input-failed-'..n)do n=n+1 end
local temp=target..'.input-new-'..n;local backup=target..'.before-input-'..n
local f=assert(io.open(temp,'w'));assert(f:write(SOURCE));assert(f:flush());f:close();assert(read(temp)==SOURCE,'临时网页回读失败，原网页未改')
assert(read(target)==previous,'网页在更新期间变化，未替换')
assert(fs.rename(target,backup),'备份失败，原网页未改')
local installed=false
local ok,reason=pcall(function()assert(fs.rename(temp,target),'替换失败');installed=true;assert(read(target)==SOURCE,'网页回读失败')end)
if not ok then
 if installed then assert(fs.rename(target,target..'.input-failed-'..n),'保留失败网页失败，请核对备份')end
 assert(fs.rename(backup,target),'原网页恢复失败，请核对 '..backup)
 error('更新失败，原网页已恢复：'..tostring(reason))
end
print('网页更新完成：顶部显示启动条件、应用/启动失败原因，修正节点韦门地址回填。')
print('配置、草稿、配方和运行日志未修改；没有控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
'''
(HERE/'update_web.lua').write_text("print('BEC web input update - Q to exit the old page before updating')\nlocal SOURCE="+literal(source)+'\nlocal SUPPORTED={'+','.join(signatures)+'}\n'+body,encoding='utf-8',newline='\n')
print('Built HTML-only updater:',len(source.encode()),'HTML bytes')
