-- Run after quitting the BEC program with Q. Changes source only.
local fs=require('filesystem')
local path='/home/bec_v2/runtime/nanites_cell.lua'
local function read(p)
 local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return s
end
local function patchRuntime(old)
if not old:find('local DISPLAY_CAP,MIN=',1,true) then
 assert(old:find('的可用蜂群',1,true) and not old:find('%f[%w_]MIN%f[^%w_]'),'未知模块版本，未修改')
 return old
end
local new,n=old:gsub('local DISPLAY_CAP,MIN=([^\r\n]-),64 %-%-','local DISPLAY_CAP=%1 --')
assert(n==1,'未知数量门槛，未修改')
new,n=new:gsub(' and h%+sameFamily>=MIN','');assert(n==1)
new,n=new:gsub('n>=MIN','n>0');assert(n==2)
new,n=new:gsub('h>=MIN','h>0');assert(n<=1)
new,n=new:gsub('的至少64个蜂群','的可用蜂群');assert(n==1)
new=new:gsub(' local sameFamily=0\r?\n if p then for _,disk in ipairs%(cells%) do if disk%.item and disk%.item%.family==p%.name then sameFamily=sameFamily%+disk%.count end end end\r?\n','')
assert(not new:find('%f[%w_]MIN%f[^%w_]'),'发现未知数量门槛，未修改')
assert(load(new,'@'..path,'t'))
return new
end
local function install(path,old,new)
 if new==old then return end
 assert(load(new,'@'..path,'t'))
local tmp,backup=path..'.small-hive.tmp',path..'.before-small-hive'
assert(not fs.exists(tmp) and not fs.exists(backup),'已有临时文件或备份，未覆盖')
local f=assert(io.open(tmp,'w'));assert(f:write(new));assert(f:flush());f:close()
assert(read(tmp)==new and read(path)==old,'文件回读失败或原文件已改变')
assert(fs.rename(path,backup),'备份失败')
if not fs.rename(tmp,path) then
 assert(fs.rename(backup,path),'替换失败，原文件保存在 '..backup)
 error('替换失败，已恢复原文件')
end
assert(read(path)==new,'安装回读失败，原文件保存在 '..backup)
end

local old=read(path);local new=patchRuntime(old)
local bp='/home/bec_v2/lib/bridge.lua'
local bo=read(bp);local bn,n=bo:gsub('or count<64 or total and count~=math%.min%(total,30720%)','or count<=0 or total and count~=math.min(total,30720)')
assert(n<=1 and (n==1 or not bo:find('arrayHiveReady=function',1,true) or bo:find('or count<=0 or total and count~=math.min(total,30720)',1,true)),'未知阵列数量校验，未修改')
install(bp,bo,bn)
install(path,old,new)
print('已取消蜂群盘和阵列校验的64个门槛；等级、实际数量与搬运校验仍有效。')
