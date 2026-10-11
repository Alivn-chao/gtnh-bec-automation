from pathlib import Path
folder=Path(__file__).parent
base=(folder/'patch_v1.lua').read_text(encoding='utf-8')
head=base.split('local original=read(path)',1)[0]
tail='assert(load(modified'+base.split('assert(load(modified',1)[1]
tail=tail.replace('ui-speed','ui-targets').replace('UI调度与耗时记录补丁已安装','生产主页单项缓存目标显示已修正')
changes=[
('if cacheView.handle(e)=="back" then showCache=false;returnedAt=', 'if cacheView.handle(e)=="back" then if clearDisplayCache then clearDisplayCache() end showCache=false;returnedAt='),
('local config=journal("/home/bec_cache.config") local goal=tonumber(config.target) or 144000', '''local config=journal("/home/bec_cache.config") local goal=tonumber(config.target) or 144000
-- BEC_V1_UI_TARGETS_V1: same per-fluid targets as the cache worker/settings view.
local function cacheGoal(name)
 local v=type(config.overrides)=="table" and config.overrides[name] or nil
 if type(v)=="number" and v>=0 and v==math.floor(v) and v<=2147483647 then return v end
 return goal
end'''),
('if stock and (stock[name] or 0)>=goal then','if stock and (stock[name] or 0)>=cacheGoal(name) then'),
('local n=stock and (stock[name] or 0) or nil text(rx+1,y,','local desired=cacheGoal(name);local n=stock and (stock[name] or 0) or nil text(rx+1,y,'),
('text(rx+rw-21,y,number(n).." / "..number(goal).." mB",20,n and n>=goal and good or accent) bar(rx+1,y+1,rw-2,n,goal,n and n>=goal and good or purple)',
 'text(rx+rw-21,y,number(n).." / "..(desired==0 and "停补" or number(desired).." mB"),20,n and n>=desired and good or accent) bar(rx+1,y+1,rw-2,n,math.max(1,desired),n and n>=desired and good or purple)'),
]
code=head+'''local original=read(path)
if original:find('BEC_V1_UI_TARGETS_V1',1,true)then print('单项目标显示已安装');return end
local modified=original:gsub('\\r\\n','\\n')
'''
for before,after in changes:code+='modified=replace(modified,[=['+before+']=],[=['+after+']=])\n'
(folder/'patch_targets.lua').write_text(code+tail,encoding='utf-8')
