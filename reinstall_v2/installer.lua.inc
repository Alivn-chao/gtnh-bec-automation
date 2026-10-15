-- Clean install only. OpenOS must already be installed on the disk.
local fs=require('filesystem')
local ROOT='/home/bec_v2'
assert(not fs.exists(ROOT),'已有 /home/bec_v2；这是全新安装器，不覆盖配置/日志。请保留原目录并使用升级流程。')
local stage='/home/.bec-v2-new-1'
local sequence=1
while fs.exists(stage)do sequence=sequence+1;stage='/home/.bec-v2-new-'..sequence end
assert(fs.makeDirectory(stage),'无法建立安装临时目录')
local written={}
local function read(path)
 local f=assert(io.open(path,'r'));local s=f:read('*a');f:close();return s
end
local function clean()
 for i=#written,1,-1 do pcall(fs.remove,stage..'/'..written[i])end
 for _,d in ipairs({'runtime','lib','recipes'})do pcall(fs.remove,stage..'/'..d)end
 pcall(fs.remove,stage)
end
local ok,reason=pcall(function()
 for _,dir in ipairs({'lib','runtime','recipes'})do assert(fs.makeDirectory(stage..'/'..dir),'建立目录失败')end
 for _,entry in ipairs(FILES)do
  local name,source=entry[1],entry[2]
  if name:sub(-4)=='.lua'then assert(load(source,'@'..ROOT..'/'..name,'t',_ENV),'Lua语法检查失败：'..name)end
  local path=stage..'/'..name
  written[#written+1]=name
  local f=assert(io.open(path,'w'),'磁盘空间不足或无法写入：'..name)
  assert(f:write(source),'写入失败：'..name);assert(f:flush(),'刷新失败：'..name)
  local closed,err=f:close();assert(closed~=false and err==nil,'关闭文件失败：'..name)
  assert(read(path)==source,'回读不符：'..name)
 end
 assert(not fs.exists(ROOT),'安装期间目标目录发生变化，保留现场')
 assert(fs.rename(stage,ROOT),'发布安装目录失败')
end)
if not ok then clean();error('安装未完成，未启动机器：'..tostring(reason))end
print('BEC V2 完整安装完成：/home/bec_v2')
print('普通屏配置：lua /home/bec_v2/main.lua setup')
print('OCHD配置：lua /home/bec_v2/main.lua setup-hd')
print('入门说明：edit /home/bec_v2/START_HERE.txt')
print('尚未绑定、搬料、下单或启动生产。')
