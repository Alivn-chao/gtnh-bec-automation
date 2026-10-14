-- New-disk launcher: monitor first, or explicitly initialize existing machinery.
local mode,panel=...
mode=mode or 'monitor'
local fs=require('filesystem');local c=require('component')
local function run(path,...)return assert(loadfile(path,'t',_ENV))(...)end
if mode=='bee-restart'then return run('/home/bec_bee_restart.lua')end
if mode=='initialize'then
 assert(fs.exists('/home/bec/recipes'),'没有配方目录，请从旧硬盘导入登记配方或用样板处理登记')
 local count=0;for name in fs.list('/home/bec/recipes')do if name:match('%.dat$')then count=count+1 end end
 assert(count>0,'还没有登记配方；请先迁移旧盘配方或运行 bec_patterns.lua')
 local ok,why=run('/home/bec_bee_restart.lua','reset');assert(ok,why)
 ok,why=run('/home/bec_initialize.lua');assert(ok,why)
 mode='resume'
end
assert(mode=='monitor'or mode=='run'or mode=='resume'or mode=='restock','用法：monitor / initialize / run / resume / bee-restart')
local count=0;for _ in c.list('hd_panel',true)do count=count+1 end
if count>0 then return run('/home/bec_hd.lua',mode,panel)end
return run('/home/bec_ui.lua',mode)
