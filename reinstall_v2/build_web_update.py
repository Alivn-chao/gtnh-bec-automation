"""HTML-only update; works before a complete machine binding is available."""
from pathlib import Path
import subprocess
import zlib
from build import literal
HERE=Path(__file__).resolve().parent
source=(HERE/'files/lib/web_page.html').read_text(encoding='utf-8')
signatures=[]
for ref in ['334125a','81b7724']:
 data=subprocess.check_output(['git','show',ref+':reinstall_v2/files/lib/web_page.html'],cwd=HERE.parent)
 signatures.append('['+repr(str(len(data))+':'+str(zlib.adler32(data)&0xffffffff))+']=true')
body=r'''
local fs=require('filesystem')
local target='/home/bec_v2/lib/web_page.html'
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function normal(s)return s and s:gsub('\r\n','\n')end
local function signature(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local previous=assert(read(target),'需要已安装V2网页；不要用于V1')
if normal(previous)==SOURCE then print('网页交互修复已安装。');return end
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
print('网页更新完成：清空地址、输入焦点、可见下拉列表和更快模型缩放。')
print('配置、草稿、配方和运行日志未修改；没有控制机器。')
print('退格/Delete修复还需客户端替换OCHD cef-host.jar；详见WEB_INPUT.md。')
print('重新打开：lua /home/bec_v2/main.lua web')
'''
(HERE/'update_web.lua').write_text("print('BEC web input update - Q to exit the old page before updating')\nlocal SOURCE="+literal(source)+'\nlocal SUPPORTED={'+','.join(signatures)+'}\n'+body,encoding='utf-8',newline='\n')
print('Built HTML-only updater:',len(source.encode()),'HTML bytes')
