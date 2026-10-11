-- UI-only patch. Display caching never supplies data to the controller.
local fs=require('filesystem')
local path='/home/bec_ui.lua'
local function read(p)
 local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return assert(text)
end
local function replace(text,from,to)
 local a,b=text:find(from,1,true)
 assert(a and not text:find(from,b+1,true),'UI版本入口缺失或不唯一，原文件未改')
 return text:sub(1,a-1)..to..text:sub(b+1)
end
local original=read(path)
if original:find('BEC_V1_UI_TARGETS_V1',1,true)then print('单项目标显示已安装');return end
local modified=original:gsub('\r\n','\n')
modified=replace(modified,[=[if cacheView.handle(e)=="back" then showCache=false;returnedAt=]=],[=[if cacheView.handle(e)=="back" then if clearDisplayCache then clearDisplayCache() end showCache=false;returnedAt=]=])
modified=replace(modified,[=[local config=journal("/home/bec_cache.config") local goal=tonumber(config.target) or 144000]=],[=[local config=journal("/home/bec_cache.config") local goal=tonumber(config.target) or 144000
-- BEC_V1_UI_TARGETS_V1: same per-fluid targets as the cache worker/settings view.
local function cacheGoal(name)
 local v=type(config.overrides)=="table" and config.overrides[name] or nil
 if type(v)=="number" and v>=0 and v==math.floor(v) and v<=2147483647 then return v end
 return goal
end]=])
modified=replace(modified,[=[if stock and (stock[name] or 0)>=goal then]=],[=[if stock and (stock[name] or 0)>=cacheGoal(name) then]=])
modified=replace(modified,[=[local n=stock and (stock[name] or 0) or nil text(rx+1,y,]=],[=[local desired=cacheGoal(name);local n=stock and (stock[name] or 0) or nil text(rx+1,y,]=])
modified=replace(modified,[=[text(rx+rw-21,y,number(n).." / "..number(goal).." mB",20,n and n>=goal and good or accent) bar(rx+1,y+1,rw-2,n,goal,n and n>=goal and good or purple)]=],[=[text(rx+rw-21,y,number(n).." / "..(desired==0 and "停补" or number(desired).." mB"),20,n and n>=desired and good or accent) bar(rx+1,y+1,rw-2,n,math.max(1,desired),n and n>=desired and good or purple)]=])
assert(load(modified,'@'..path,'t',_ENV),'补丁后语法检查失败')
local n=1;while fs.exists(path..'.before-ui-targets-'..n) or fs.exists(path..'.ui-targets-new-'..n) do n=n+1 end
local backup,temp=path..'.before-ui-targets-'..n,path..'.ui-targets-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close()
assert(read(temp)==modified,'临时文件回读失败')
assert(fs.rename(path,backup),'备份失败，原文件保留')
if not fs.rename(temp,path) then assert(fs.rename(backup,path),'还原失败，原文件在 '..backup);error('替换失败，已还原') end
assert(read(path)==modified and read(backup)==original,'替换或备份回读失败')
print('生产主页单项缓存目标显示已修正；备份: '..backup)
print('生产控制器、订单和日志均未修改。正常Q停止后继续: lua /home/bec_ui.lua run')
