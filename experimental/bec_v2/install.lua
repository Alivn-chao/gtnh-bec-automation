-- Install only V2 scripts. No configuration, recipe, machine or journal changes.
local fs=require('filesystem')
local shell=require('shell')
local ROOT='/home/bec_v2'
local BASE='https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/bec-v2-preview-2026-10-09/experimental/bec_v2/'
local files={'main.lua','lib/config.lua','lib/bridge.lua','lib/engine.lua','lib/setup.lua','lib/ui.lua','lib/scan.lua','lib/patterns.lua',
 'runtime/controller.lua','runtime/nanites.lua','runtime/patterns.lua'}
for _,dir in ipairs({ROOT,ROOT..'/lib',ROOT..'/runtime',ROOT..'/download'})do
 assert(fs.exists(dir)or fs.makeDirectory(dir),'不能建立 '..dir)
end
print('安装BEC V2测试版；升级前须先退出正在运行的V2服务。')
print('下载完整并通过语法检查后替换程序；配置、配方和日志保留。')
for i,path in ipairs(files)do
 local temp=ROOT..'/download/'..i..'.lua'
 assert(shell.execute('wget -f '..BASE..path..' '..temp),'下载失败：'..path..'；现有程序尚未替换')
 assert(loadfile(temp),'下载内容不是有效Lua程序：'..path)
end
for i,path in ipairs(files)do
 local dest=ROOT..'/'..path
 if fs.exists(dest)then
  local backup=dest..'.before-install';local n=1
  while fs.exists(backup)do backup=dest..'.before-install-'..n;n=n+1 end
  assert(fs.rename(dest,backup),'备份失败：'..path)
 end
 assert(fs.rename(ROOT..'/download/'..i..'.lua',dest),'安装失败：'..path)
end
print('安装完成。先扫描并运行配置向导：')
print('lua /home/bec_v2/main.lua scan')
print('lua /home/bec_v2/main.lua setup')
print('新用户需先登记配方；详见仓库 docs/GETTING_STARTED.md。')
