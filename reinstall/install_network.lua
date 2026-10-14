print('BEC INSTALL 2026-10-14.2 - starting')
local installArgs=table.pack(...)
local function install(...)
-- Complete V1 install for a NEW OpenOS disk. Does not start machinery.
local first,second=...
local importOnly=first=='import'
local oldHome=first;if importOnly then oldHome=second end
local fs=require('filesystem');local ser=require('serialization');local internet
local TAG='bec-v1-full-2026-10-14.2'
local manifest={
{name="automation_demo.lua",size=2464,checksum=3590512264},
{name="bec_auto.lua",size=73181,checksum=1633258873},
{name="bec_bee_restart.lua",size=6673,checksum=1727298972},
{name="bec_cache.config",size=40,checksum=594873840},
{name="bec_cache.lua",size=28870,checksum=4226225003},
{name="bec_cache_ui.lua",size=12560,checksum=4040312061},
{name="bec_check.lua",size=910,checksum=3679727260},
{name="bec_clean.lua",size=2019,checksum=1165012568},
{name="bec_hd.config",size=101,checksum=3219594098},
{name="bec_hd.lua",size=11765,checksum=3202616409},
{name="bec_history.lua",size=1098,checksum=3287645135},
{name="bec_initialize.lua",size=8119,checksum=4171324930},
{name="bec_nanites.lua",size=17713,checksum=3876160642},
{name="bec_pattern.lua",size=2977,checksum=2540891175},
{name="bec_patterns.lua",size=7499,checksum=1281814973},
{name="bec_start.lua",size=1122,checksum=1162067},
{name="bec_ui.lua",size=31215,checksum=4183191812}
}
local bundled={}
local stage='/home/bec_install_stage'
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'写入回读失败: '..p)end
local function checksum(text)local a,b=1,0;for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end;return b*65536+a end
local function validate(entry,text)
 assert(#text==entry.size and checksum(text)==entry.checksum,'下载校验失败')
 if entry.name:match('%.lua$')then assert(load(text,'@'..entry.name,'t',_ENV),'Lua语法错误')
 else assert(type(ser.unserialize(text))=='table','默认配置无效')end
 return text
end
local function fetch(entry)
 if bundled[entry.name]then return validate(entry,bundled[entry.name])end
 internet=internet or require('internet')
 local roots={'https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/'..TAG..'/reinstall/files/',
 'https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@'..TAG..'/reinstall/files/'}
 local errors={}
 for _,root in ipairs(roots)do
  local ok,result=pcall(function()
   local pieces,n={},0;for chunk in internet.request(root..entry.name)do
    assert(type(chunk)=='string');n=n+#chunk;assert(n<=entry.size,'下载内容超出预期');pieces[#pieces+1]=chunk
   end
   return validate(entry,table.concat(pieces))
  end)
  if ok then return result end;errors[#errors+1]=tostring(result)
 end
 error(entry.name..' 下载失败：'..table.concat(errors,'; '))
end
local pending=read(stage..'/release.txt')
local resuming=pending and pending:match('^([^\n]+)')==TAG
if fs.exists(stage)then assert(resuming,'安装临时目录不是本版，请核对 '..stage)end
if resuming and not oldHome then local saved=pending:match('\n(.+)$');if saved then oldHome=saved end end
for _,entry in ipairs(manifest)do
 assert(entry.name:match('^[%w_%.]+$')and not entry.name:find('..',1,true),'安装包路径无效')
 if not importOnly and not resuming then assert(not fs.exists('/home/'..entry.name),'这是新盘完整安装包；当前文件已存在: '..entry.name)end
end
assert(not fs.exists('/home/bec_auto.journal')and not fs.exists('/home/bec_nanites_io.journal'),'当前盘有运行状态，请使用新盘OpenOS安装')
if not oldHome then
 local candidates,seen={},{}
 local current=fs.get('/home')
 for proxy,path in fs.mounts()do
  if proxy.address~=current.address then for _,suffix in ipairs({'home/',''})do
   local candidate=path:gsub('/+$','')..'/'..suffix
   candidate=candidate:gsub('/+$','')
   if not seen[candidate]and fs.exists(candidate..'/bec/recipes')and fs.exists(candidate..'/bec_auto.lua')then
    candidates[#candidates+1]=candidate;seen[candidate]=true
   end
  end end
 end
 if #candidates==1 then oldHome=candidates[1]
 elseif #candidates>1 then
  for _,p in ipairs(candidates)do print('旧盘候选：'..p)end
  error('找到多个旧程序目录；请重新运行安装器并在命令后指定旧home目录')
 end
end
local imports={};local recipes=0
if importOnly then assert(oldHome,'未找到旧盘；命令格式：lua /home/bec_install.lua import /mnt/旧盘地址/home')end
if oldHome then
 oldHome=oldHome:gsub('/+$','')
 assert(fs.isDirectory(oldHome),'旧盘目录不存在: '..oldHome)
 for _,name in ipairs({'bec_cache.config','bec_hd.config'})do
  local text=read(oldHome..'/'..name)
  if text then
   local ok,t=pcall(ser.unserialize,text);assert(ok and type(t)=='table'and t.version==1,'旧配置不可读: '..name)
   if name=='bec_cache.config'then
    assert(type(t.target)=='number'and t.target>=1 and t.target<=2147483647 and t.target%1==0,'旧缓存目标无效')
    assert(t.overrides==nil or type(t.overrides)=='table','旧单项缓存配置无效')
    for k,v in pairs(t.overrides or {})do assert(type(k)=='string'and type(v)=='number'and v>=0 and v<=2147483647 and v%1==0,'旧单项缓存目标无效')end
   else
    for _,k in ipairs({'node','field'})do assert(type(t[k])=='string'and t[k]:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'旧高清配置地址无效')end
   end
   imports[name]=text
  end
 end
 local dir=oldHome..'/bec/recipes'
 if fs.isDirectory(dir)then for name in fs.list(dir)do
  if name:match('^[%w_%-%.]+%.dat$')and not fs.isDirectory(dir..'/'..name)then
   local text=assert(read(dir..'/'..name));local ok,t=pcall(ser.unserialize,text)
   assert(ok and type(t)=='table'and t.state=='converted'and type(t.condensates)=='table','旧配方未完成或不可读: '..name)
   imports['bec/recipes/'..name]=text;recipes=recipes+1
  end
 end end
 print('只迁移配方与配置，来源：'..oldHome)
end
if importOnly then
 if not fs.exists('/home/bec/recipes')then assert(fs.makeDirectory('/home/bec/recipes'))end
 for name,text in pairs(imports)do
  local target='/home/'..name;local previous=read(target)
  if previous~=text then
   if previous then local n=1;while fs.exists(target..'.before-import-'..n)do n=n+1 end;write(target..'.before-import-'..n,previous)end
   write(target,text)
  end
 end
 print('旧盘配方与配置迁移完成：'..recipes..' 个配方；未复制运行日志。');return
end
local disk=fs.get('/home');local needed=65536
for _,entry in ipairs(manifest)do needed=needed+entry.size end
for _,text in pairs(imports)do needed=needed+#text end
assert(disk.spaceTotal()-disk.spaceUsed()>needed,'新盘空间不足；至少需要 '..needed..' 字节')
-- Stage and validate every download before exposing a partial program installation.
if not fs.exists(stage)then assert(fs.makeDirectory(stage));write(stage..'/release.txt',TAG..'\n'..(oldHome or ''))end
for i,entry in ipairs(manifest)do
 print('下载 '..i..'/'..#manifest..' '..entry.name)
 local expected=imports[entry.name]
 local installed=read('/home/'..entry.name)
 if installed then
  assert(installed==expected or (not expected and #installed==entry.size and checksum(installed)==entry.checksum),'部分安装的目标已变化: '..entry.name)
 else
  local cached=read(stage..'/'..entry.name)
  local valid=cached and (cached==expected or (not expected and #cached==entry.size and checksum(cached)==entry.checksum))
  if not valid then write(stage..'/'..entry.name,expected or fetch(entry))end
 end
 imports[entry.name]=nil
end
if not fs.exists('/home/bec/recipes')then assert(fs.makeDirectory('/home/bec/recipes'))end
for name,text in pairs(imports)do
 local target='/home/'..name;local previous=read(target)
 assert(not previous or previous==text,'目标数据已变化: '..target)
 if not previous then write(target,text)end
end
for _,entry in ipairs(manifest)do if not fs.exists('/home/'..entry.name)then assert(fs.rename(stage..'/'..entry.name,'/home/'..entry.name),'安装改名失败: '..entry.name)end end
assert(fs.remove(stage..'/release.txt'))
assert(fs.remove(stage),'清除安装临时目录失败')
print('完整安装完成：V1控制器、单项缓存、整盘换蜂、初始化与OCHD适配器。')
print('已迁移登记配方 '..recipes..' 个；没有复制历史日志，也没有启动机器。')
print('只读查看：lua /home/bec_start.lua monitor')
print('盘归位且ME IO设置正确后，从现场初始化并运行：lua /home/bec_start.lua initialize')
if recipes==0 then print('尚未迁移配方：保留旧盘，用安装器 import /mnt/旧盘地址/home 迁移，或用 bec_patterns.lua 登记样板。')end
end
local ok,reason=xpcall(function()return install(table.unpack(installArgs,1,installArgs.n))end,debug.traceback)
if not ok then
 print('BEC INSTALL FAILED: '..tostring(reason))
 error(reason,0)
end
