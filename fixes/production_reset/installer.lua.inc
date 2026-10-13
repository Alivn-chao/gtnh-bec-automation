local fs=require('filesystem')
local path='/home/bec_ui.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local function replace(s,from,to)
 local a,b=s:find(from,1,true);assert(a and not s:find(from,b+1,true),'入口缺失或不唯一: '..from)
 return s:sub(1,a-1)..to..s:sub(b+1)
end
local original=read(path)
if original:find('BEC_V1_UI_PRODUCTION_RESET_V1:',1,true)then print('生产未下成重置按键已安装');return end
assert(original:find('BEC_V1_UI_CACHE_RESET_V3',1,true),'需要上一版缓存重置V3')
local modified=original:gsub('\r\n','\n')
modified=replace(modified,'local function cacheResetWorker()',
 '-- BEC_V1_UI_PRODUCTION_RESET_V1: Z explicitly confirms raw requests did not start.\n'
 ..'local function productionResetWorker(...)\n'..[==[RESET_BODY]==]..'\nend\n'
 ..'local function cacheResetWorker()\n'
 ..'local saved=journal();if type(saved.pipeline)=="table" and type(saved.plan)=="table" then return productionResetWorker("confirmed-not-submitted") end\n')
modified=replace(modified,'[ Z 放弃缓存 / 重置 ]','[ Z 确认未下单 / 重置 ]')
local chunk,why=load(modified,'@'..path,'t',_ENV);assert(chunk,'UI语法检查失败: '..tostring(why))
local n=1;while fs.exists(path..'.before-production-reset-'..n)or fs.exists(path..'.production-reset-new-'..n)do n=n+1 end
local backup,temp=path..'.before-production-reset-'..n,path..'.production-reset-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified)
assert(read(path)==original,'安装期间UI变化')
assert(fs.rename(path,backup),'UI备份失败')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'UI还原失败');error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'安装回读失败')
print('生产未下成重置按键已安装；备份: '..backup)
print('启动 lua /home/bec_ui.lua resume；Z表示你确认本轮未完成的原液申请没有成功。')
print('完整备份旧记录、保留物料后重新计算；申请若实际已启动，请用T等待核对，不按Z。')
