local c=require('component')
return function(C,mode,options)
 options=options or {}
 assert(mode=='preview'or mode=='run'or mode=='watch'or mode=='replace','用法：patterns preview / run / watch / replace')
 local cfg=C.load();local address=assert(cfg.workshopInterface,'先setup绑定专用工坊ME接口')
 assert(address~=cfg.mainInterface,'工坊接口不能用主网供液接口')
 local function guard()
 if mode=='replace'then
  local function stopped(path)
   local r=C.read(C.path(path));assert(not r or r.stage=='stopped'and not r.pending and not r.plan and not r.incomplete,'仍有未完成批次或未确认操作，不能覆盖登记：'..path)
   for _,j in pairs(r and r.requests or{})do assert(j.state=='done'or j.state=='rejected'and j.preSubmissionFailed,'AE申请尚未确认，不能覆盖登记')end
  end
  for group in ipairs(cfg.groups)do
   stopped('state/group-'..group..'/cell-feed.journal');stopped('state/group-'..group..'/cohort.dat');stopped('state/group-'..group..'/cache.journal')
  end
  for i,n in ipairs(cfg.nodes)do
   stopped('state/node-'..i..'/production.journal')
   assert(c.invoke(n.address,'getState')=='idle'and c.invoke(n.address,'getParallelRecipesInProgress')==0 and c.invoke(n.address,'isWorkAllowed')==false,'先结束批次并关闭节点接单，再覆盖登记')
  end
 end
 for group,g in ipairs(cfg.groups)do
  assert(address~=g.subInterface,'工坊接口不能用原液子网接口')
  for _,n in ipairs(cfg.nodes)do if n.group==group then
   local state=c.invoke(n.address,'getState')
   assert(mode=='preview'or (state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low'),'先暂停生产再处理样板')
  end end
  for _,a in ipairs(g.generators)do
   assert(mode=='preview'or (c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false),'先关闭纠缠器再处理样板')
  end
 end
 end
 guard()
 local f=assert(io.open(C.path('runtime/patterns.lua'),'r'));local text=f:read('*a');f:close()
 text=text:gsub('local ADDRESS="[^"]+"',function()return 'local ADDRESS='..string.format('%q',address)end,1)
 text=text:gsub('local DIR="[^"]+"',function()return 'local DIR='..string.format('%q',cfg.recipeDirectory)end,1)
 local env=options.print and setmetatable({print=options.print},{__index=_ENV})or _ENV
 local hooks=options.hooks
 if hooks then local before=hooks.beforeSlot;hooks.beforeSlot=function(slot)guard();if before then before(slot)end end end
 assert(load(text,'V2样板处理','t',env))(mode,hooks)
end
