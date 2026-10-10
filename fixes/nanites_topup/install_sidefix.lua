-- One-shot V1 installer. Run from the OpenOS prompt after stopping the UI.
-- Checks/preview are read-only; no production, configuration, or journal writes.
local c=require('component')
local fs=require('filesystem')
local internet=require('internet')
local sides=require('sides')
local target='/home/bec_nanites.lua'
local url='https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/a2c8c9a/fixes/nanites_topup/bec_nanites.lua'
local node='b04787f9-5423-4b03-8549-c786d4ef38d0'
local rs='266f65b5-20be-4543-8f2f-bfd2d0816611'
local function paused()
 assert(c.invoke(rs,'getOutput',sides.top)==15,'请先停止生产UI，保持向上红石输出15')
 assert(c.invoke(node,'isWorkAllowed')==false,'节点尚未暂停，取消安装')
 local s=c.invoke(node,'getState')
 assert(s=='paused-immediate' or s=='nanite-tier-too-low' or s=='idle','节点状态不适合安装: '..tostring(s))
end
local function read(path)
 local f=assert(io.open(path,'r'));local text=f:read('*a');f:close();return assert(text)
end
local function write(path,text)
 assert(not fs.exists(path),'不会覆盖已有文件: '..path)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(path)==text,'文件回读不一致: '..path)
end
local function unique(prefix)
 local n=1;while fs.exists(prefix..n) do n=n+1 end;return prefix..n
end
local function checksum(text)
 local a,b=1,0
 for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end
 return b*65536+a
end
paused()
local original=read(target);assert(#original>0,'旧模块是空文件，取消安装')
print('下载已固定版本的蜂群方向修正，先校验并只读预览。')
local parts,size={},0
for chunk in internet.request(url) do
 size=size+#chunk;assert(size<=11148,'下载内容长度错误，旧文件未改动')
 parts[#parts+1]=chunk
end
local source=table.concat(parts)
assert(#source==11148 and checksum(source)==43059260,'下载校验失败，旧文件未改动')
local worker=assert(load(source,'@bec_nanites.sidefix','t',_ENV))()
assert(type(worker)=='table' and type(worker.preview)=='function','模块格式错误')
worker.preview() -- Verifies actual north/south interfaces without moving bees.
paused()
assert(read(target)==original,'旧模块在检查期间发生变化，取消安装')
if original==source then print('已经是方向修正版，无需替换。');return end
local backup=unique(target..'.before_sidefix-')
write(backup,original)
local pending=unique(target..'.sidefix-pending-')
write(pending,source)
paused()
assert(read(target)==original,'旧模块在写入期间发生变化，取消替换')
-- OC filesystems may reject renaming onto an existing file. Retain the old
-- target separately, then install the verified file; restore on rename failure.
local retired=unique(target..'.sidefix-retired-')
local ok,reason=fs.rename(target,retired)
assert(ok,'无法移开旧文件，取消替换: '..tostring(reason))
local attempt,moved,why=pcall(fs.rename,pending,target)
if not attempt or not moved then
 local restored,restoreReason=fs.rename(retired,target)
 assert(restored,'替换及回退失败；备份: '..backup..'；原因: '..tostring(restoreReason))
 assert(read(target)==original,'回退校验失败；备份: '..backup)
 error('替换失败，已恢复旧模块: '..tostring(attempt and why or moved))
end
assert(read(target)==source,'安装回读不一致；旧模块备份: '..backup)
print('已安装：备用北2，收容南3，西4蜂群仓；上限30720。')
print('旧模块备份: '..backup)
print('未启动生产、未搬运蜂群，所有journal保留。')
