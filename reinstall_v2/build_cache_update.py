"""Five-file V1 cache integration update; preserves configuration and journals."""
from pathlib import Path
import subprocess,zlib
from build import literal
HERE=Path(__file__).resolve().parent
NAMES=['lib/cache.lua','runtime/cache.lua','web.lua','lib/web_session.lua','lib/web_page.html']
rows=[]
for name in NAMES:
 signatures=[]
 for ref in ['334125a','81b7724','f60f785','933750b','180bf41','bccf281','438f625','dae5e0e','d26100c']:
  result=subprocess.run(['git','show',ref+':reinstall_v2/files/'+name],cwd=HERE.parent,capture_output=True)
  if result.returncode:continue
  data=result.stdout
  signatures.append('['+repr(str(len(data))+':'+str(zlib.adler32(data)&0xffffffff))+']=true')
 rows.append('{name='+repr(name)+',added='+('true'if name in ['lib/cache.lua','runtime/cache.lua']else 'false')+',source='+literal((HERE/'files'/name).read_text(encoding='utf-8'))+',supported={'+','.join(signatures)+'}}')
body=r'''
local fs=require('filesystem');local root='/home/bec_v2/'
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function normal(s)return s and s:gsub('\r\n','\n')end
local function signature(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local old,identical,bytes={},true,0
for i,row in ipairs(rows)do
 local target=root..row.name;old[i]=read(target);assert(old[i]or row.added,'缺少V2程序: '..target)
 local text=normal(old[i]);assert(row.added and text==nil or text==row.source or text and row.supported[signature(text)],'未知本地程序，保留未覆盖: '..target)
 if text~=row.source then identical=false end
 if row.name:sub(-4)=='.lua'then assert(load(row.source,'@'..target,'t',_ENV),'新程序语法无效')end
 bytes=bytes+#row.source
end
-- Release only this exact, already-loaded temporary download. The program
-- backups and every state/configuration file are retained.
local self='/home/bec_cache_update.lua'
if debug.getinfo(1,'S').source=='@'..self then
 local downloaded=read(self)
 local payload=downloaded and downloaded:match('^%-%- BEC_V2_CACHE_UPDATE_1\nlocal SELF_SIGNATURE=[^\n]*\n(.*)$')
 if payload and signature(payload)==SELF_SIGNATURE then
  assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')
 end
 downloaded=nil;payload=nil;collectgarbage('collect')
end
if identical then print('缓存管理功能已安装，无需重复更新。');return end
local disk=assert(fs.get(root));assert(disk.spaceTotal()-disk.spaceUsed()>=bytes+524288,'磁盘空间不足：更新后需保留512KiB')
local n=1
while true do
 local conflict=false;for _,row in ipairs(rows)do for _,suffix in ipairs({'.before-cache-','.cache-new-','.cache-failed-'})do if fs.exists(root..row.name..suffix..n)then conflict=true end end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(rows)do
 local temp=root..row.name..'.cache-new-'..n;local f=assert(io.open(temp,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(temp)==row.source,'临时文件回读失败，旧程序未改')
end
for i,row in ipairs(rows)do assert(read(root..row.name)==old[i],'更新期间程序改变，未替换')end
local backed,installed={},{}
local ok,reason=pcall(function()
 for i,row in ipairs(rows)do local target=root..row.name
  if old[i]then assert(fs.rename(target,target..'.before-cache-'..n),'备份失败');backed[i]=true end
  assert(fs.rename(target..'.cache-new-'..n,target),'替换失败');installed[i]=true
  assert(read(target)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#rows,1,-1 do local target=root..rows[i].name
  if installed[i]then assert(fs.rename(target,target..'.cache-failed-'..n),'移出失败程序失败，保留备份')end
  if backed[i]then assert(fs.rename(target..'.before-cache-'..n,target),'恢复失败，保留备份')end
 end
 error('更新失败，旧程序已恢复：'..tostring(reason))
end
print('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。')
print('已有地址、草稿、配置、配方和运行记录保留；未控制机器。')
print('重新打开：lua /home/bec_v2/main.lua web')
'''
payload="print('BEC web cache update; Q to exit the old UI first')\nlocal rows={"+','.join(rows)+'}\n'+body
data=payload.encode('utf-8');signature=str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)
(HERE/'update_cache.lua').write_text('-- BEC_V2_CACHE_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature)+'\n'+payload,encoding='utf-8',newline='\n')
print('Built update_cache.lua:',len(rows),'files')
