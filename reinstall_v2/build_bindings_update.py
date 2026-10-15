from pathlib import Path
from build import literal
HERE=Path(__file__).resolve().parent
rows=[]
for name in ['lib/ochd_bindings.lua','setup_hd.lua']:
    rows.append('{path="/home/bec_v2/'+name+'",source='+literal((HERE/'files'/name).read_text(encoding='utf-8'))+'}')
body=r'''
local fs=require('filesystem')
assert(fs.exists('/home/bec_v2/main.lua')and fs.exists('/home/bec_v2/lib/config.lua'),'请先安装V2；本文件只更新绑定页面')
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local originals={};local identical=true
for i,row in ipairs(files)do
 assert(load(row.source,'@'..row.path,'t',_ENV),'Lua语法检查失败')
 originals[i]=read(row.path)or false
 if originals[i]~=row.source then identical=false end
end
if identical then print('绑定页已经是最新版');return end
local n=1
while fs.exists(files[1].path..'.before-drafts-'..n)or fs.exists(files[1].path..'.drafts-new-'..n)do n=n+1 end
for _,row in ipairs(files)do
 assert(not fs.exists(row.path..'.before-drafts-'..n)and not fs.exists(row.path..'.drafts-new-'..n),'备份路径冲突')
 local p=row.path..'.drafts-new-'..n;local f=assert(io.open(p,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(p)==row.source,'回读失败')
end
for i,row in ipairs(files)do assert((read(row.path)or false)==originals[i],'程序在更新期间变化')end
local retired,installed={},{}
local ok,err=pcall(function()
 for i,row in ipairs(files)do
  if originals[i]then assert(fs.rename(row.path,row.path..'.before-drafts-'..n));retired[i]=true end
  assert(fs.rename(row.path..'.drafts-new-'..n,row.path));installed[i]=true
  assert(read(row.path)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#files,1,-1 do local p=files[i].path
  if installed[i]then assert(fs.rename(p,p..'.drafts-failed-'..n))end
  if retired[i]then assert(fs.rename(p..'.before-drafts-'..n,p))end
 end
 error('更新失败，旧程序已恢复：'..tostring(err))
end
print('绑定页已更新；原配置、配方和生产日志保留。')
print('需要客户端和服务器同时安装 OCHD 0.3.2-alpha4-drafts。')
print('lua /home/bec_v2/main.lua setup-hd')
'''
(HERE/'update_bindings.lua').write_text('local files={'+','.join(rows)+'}\n'+body,encoding='utf-8',newline='\n')
