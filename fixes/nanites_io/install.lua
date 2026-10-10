-- V1 cell-IO installer: preview, verified backup, replace only the bee module.
local c=require('component')
local fs=require('filesystem')
local internet=require('internet')
local target='/home/bec_nanites.lua'
local url='https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/nanites_io/bec_nanites.lua'
local node='b04787f9-5423-4b03-8549-c786d4ef38d0'
local rs='266f65b5-20be-4543-8f2f-bfd2d0816611'
local LENGTH,CHECKSUM=14283,550471779
local function paused()
 assert(c.invoke(rs,'getOutput',1)==15,'先停止生产UI，保持节点暂停红石15')
 assert(c.invoke(node,'isWorkAllowed')==false,'节点仍允许工作，取消安装')
 local s=c.invoke(node,'getState')
 assert(s=='paused-immediate' or s=='nanite-tier-too-low' or s=='idle','节点状态不适合安装：'..tostring(s))
end
local function read(path)
 local f=assert(io.open(path,'r'));local v=f:read('*a');f:close();return assert(v)
end
local function write(path,text)
 assert(not fs.exists(path),'不会覆盖已有文件：'..path)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(path)==text,'文件回读不一致：'..path)
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
local original=read(target);assert(#original>0,'旧模块为空，取消安装')
local chunks,size={},0
for chunk in internet.request(url) do
 size=size+#chunk;assert(size<=LENGTH,'下载内容过长，旧文件未改动')
 chunks[#chunks+1]=chunk
end
local source=table.concat(chunks)
assert(#source==LENGTH and checksum(source)==CHECKSUM,'下载校验失败，旧文件未改动')
local worker=assert(load(source,'@bec_nanites.cellio','t',_ENV))()
assert(type(worker)=='table' and type(worker.preview)=='function' and type(worker.ensure)=='function','模块格式错误')
worker.preview() -- Reads the verified cell layout; never calls ensure here.
paused();assert(read(target)==original,'检查期间旧模块变化，取消安装')
if source==original then print('已经是蜂群IO版，无需替换');return end
local backup=unique(target..'.before_cellio-');write(backup,original)
local pending=unique(target..'.cellio-pending-');write(pending,source)
paused();assert(read(target)==original,'写入期间旧模块变化，取消安装')
local retired=unique(target..'.cellio-retired-')
assert(fs.rename(target,retired),'无法移开旧模块，取消安装')
local success,moved,reason=pcall(fs.rename,pending,target)
if not success or not moved then
 assert(fs.rename(retired,target),'安装与回退均失败；备份：'..backup)
 assert(read(target)==original,'回退回读失败；备份：'..backup)
 error('安装失败，已恢复旧模块：'..tostring(success and reason or moved))
end
assert(read(target)==source,'新模块回读失败；备份：'..backup)
print('V1蜂群IO模块已安装；旧模块备份：'..backup)
print('整盘搬运，数量由放盘控制；旧蜂群/生产/缓存日志均保留。')
print('未搬盘、未启动生产。独立测试：lua /home/bec_nanites.lua test')
