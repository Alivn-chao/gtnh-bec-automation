local ROOT='/home/bec_v2'
local function module(name)return assert(loadfile(ROOT..'/lib/'..name..'.lua'))()end
local C=module('config')
local mode,option=...
mode=mode or 'monitor'
if mode=='scan'then module('scan')();return end
if mode=='setup'then module('setup')(C);return end
if mode=='add-nodes'then module('setup')(C,true);return end
if mode=='patterns'then module('patterns')(C,option or 'preview');return end
assert(mode=='monitor'or mode=='run','用法：setup / monitor / run')
local cfg=C.load();C.validate(cfg,true)
local E=module('engine')(cfg,C,module('bridge'),mode=='monitor')
local c=require('component');local event=require('event')
if mode=='run'then
 for _,g in ipairs(cfg.groups)do for _,a in ipairs(g.generators)do
  assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'先停止稳定版和所有纠缠器，再启动V2')
 end end
 for _,n in ipairs(cfg.nodes)do
  local state=c.invoke(n.address,'getState')
  assert(state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low','先暂停全部节点，再启动V2；当前 '..tostring(state))
  assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'先提供暂停信号15，再启动V2')
 end
end
local UI=module('ui')(cfg,E,C)
local ok,err=xpcall(function()
 local running=true;local nextPaint=0
 while running do
  E.step()
  local now=require('computer').uptime()
  if now>=nextPaint then UI.draw();nextPaint=now+0.5 end
  local signal,_,character,code=event.pull(0.05,'key_down')
  if signal=='key_down'then
   if character==113 or character==81 then running=false
   else local success,reason=pcall(UI.key,character,code);if not success then E.log(UI.selected(),tostring(reason))end end
  end
 end
end,debug.traceback)
local errors=E.shutdown();UI.close()
if not ok then print('V2已停止：'..tostring(err))end
for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
print(mode=='monitor'and '只读监控已退出'or 'V2已暂停所有组并关闭纠缠器；现场和日志保留')
