local c=require('component')
return function(C,mode)
 assert(mode=='preview'or mode=='run'or mode=='watch','用法：patterns preview / run / watch')
 local cfg=C.load();local address=assert(cfg.workshopInterface,'先setup绑定专用工坊ME接口')
 assert(address~=cfg.mainInterface,'工坊接口不能用主网供液接口')
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
 local f=assert(io.open(C.path('runtime/patterns.lua'),'r'));local text=f:read('*a');f:close()
 text=text:gsub('local ADDRESS="[^"]+"',function()return 'local ADDRESS='..string.format('%q',address)end,1)
 text=text:gsub('local DIR="[^"]+"',function()return 'local DIR='..string.format('%q',cfg.recipeDirectory)end,1)
 assert(load(text,'V2样板处理','t',_ENV))(mode)
end
