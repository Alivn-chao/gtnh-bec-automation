local c=require('component')
local unicode=require('unicode')
return function(cfg,E,C)
 local gpu=c.gpu;assert(gpu,'需要GPU和屏幕')
 local oldW,oldH=gpu.getResolution();local maxW,maxH=gpu.maxResolution()
 local w,h=math.min(120,maxW),math.min(40,maxH)
 assert(w>=80 and h>=25,'屏幕至少需要80×25字符')
 gpu.setResolution(w,h)
 local oldBuffer=gpu.getActiveBuffer and gpu.getActiveBuffer()or 0
 local buffer
 if gpu.allocateBuffer then local ok,value=pcall(gpu.allocateBuffer,w,h);if ok then buffer=value end end
 local selected=1;local page=1;local cachePage=1
 local UI={}
 local bg,panel,white,dim,cyan,green,amber,red=0x080D14,0x111B28,0xDCE7F5,0x73869C,0x35C9EC,0x45D9A1,0xE6B35A,0xF07888
 local function text(x,y,s,color)
  gpu.setForeground(color or white);s=tostring(s)
  while unicode.wlen(s)>w-x do s=unicode.sub(s,1,-2)end
  gpu.set(x,y,s)
 end
 local function read(a,m,...)
  local ok,result=pcall(c.invoke,a,m,...);return ok and result or nil
 end
 local function bar(x,y,width,value,target)
  local ratio=math.max(0,math.min(1,(value or 0)/math.max(1,target or 1)))
  gpu.setBackground(0x213246);gpu.fill(x,y,width,1,' ')
  gpu.setBackground(cyan);local fill=math.floor(width*ratio);if fill>0 then gpu.fill(x,y,fill,1,' ')end
  gpu.setBackground(panel)
 end
 function UI.selected()return selected end
 function UI.key(character,code)
  if code==200 then selected=(selected-2)%#cfg.nodes+1 elseif code==208 then selected=selected%#cfg.nodes+1 end
  if character==110 then cachePage=cachePage+1 end
  if E.monitor then return end
  if character==112 then E.pauseNode(selected)elseif character==114 then E.resumeNode(selected)elseif character==97 then E.pauseAll()end
 end
 function UI.draw()
  if buffer then gpu.setActiveBuffer(buffer)end
  gpu.setBackground(bg);gpu.fill(1,1,w,h,' ')
  text(3,2,'BEC / PARALLEL CONTROL',cyan)
  text(w-28,2,E.monitor and '只读监控 / V2' or '独立测试版 / V2',amber)
  local active,parallel,failed=0,0,0
  for i,n in ipairs(cfg.nodes)do
   local state=read(n.address,'getState');if state=='crafting'then active=active+1 end
   parallel=parallel+(tonumber(read(n.address,'getParallelRecipesInProgress'))or 0)
   if E.tasks[i].fault then failed=failed+1 end
  end
  text(3,4,'节点 '..active..' / '..#cfg.nodes..' 运行    合计并行 '..parallel..'    设备组 '..#cfg.groups..'    故障 '..failed,white)
  local rows=math.min(16,h-22);page=math.floor((selected-1)/rows)+1
  gpu.setBackground(panel);gpu.fill(2,6,w-2,rows+2,' ')
  text(3,6,'节点      设备组   当前状态                  并行 / 蜂群等级 / 蜂群数量',dim)
  for row=1,rows do local i=(page-1)*rows+row;local n=cfg.nodes[i];if n then
   local state=read(n.address,'getState')or '离线'
   local tier=read(n.address,'getProvidedTier');tier=type(tier)=='table'and tier.tier or '?'
   text(3,6+row,(i==selected and '> 'or '  ')..string.format('%02d',i)..' '..n.name,i==selected and cyan or white)
   text(20,6+row,'G'..n.group,dim)
   text(27,6+row,state,state=='crafting'and green or state=='idle'and dim or amber)
   text(54,6+row,tostring(read(n.address,'getParallelRecipesInProgress')or '?')..' / T'..tier..' / '..tostring(read(n.address,'getAvailableNanites')or '?'),white)
  end end
  local g=cfg.groups[cfg.nodes[selected].group];local y=rows+9
  local generators=0;for _,a in ipairs(g.generators)do if read(a,'isMachineActive')then generators=generators+1 end end
  text(3,y,g.name..'   纠缠器 '..generators..' / '..#g.generators..' 运行',cyan)
  text(3,y+1,'调度：'..E.tasks[selected].status..'   '..(g.nanites and g.nanites.enabled and '自动蜂群开启'or '手动蜂群'),dim)
  local stock=read(g.storage,'getStoredCondensate')or {};local keys={}
  for key in pairs(stock)do keys[#keys+1]=key end;table.sort(keys)
  local pages=math.max(1,math.ceil(#keys/3));cachePage=(cachePage-1)%pages+1
  text(3,y+3,'凝聚物库存 / 参考目标 '..(cfg.cacheTarget or 144000)..' mB   '..cachePage..' / '..pages,white)
  for row=1,3 do local key=keys[(cachePage-1)*3+row];if key then
   local yy=y+3+row;local value=stock[key]
   text(3,yy,key:gsub('entangled_','')..'  '..value,dim)
   bar(math.floor(w*0.6),yy,math.floor(w*0.35),value,cfg.cacheTarget)
  end end
  gpu.setBackground(bg)
  text(3,h-4,E.logs[#E.logs]or '同组节点：同配方物理并行，共用蜂群；新批次等整组完成',dim)
  text(3,h-2,E.monitor and '↑↓ 选节点   N 库存翻页   Q 退出监控'or '↑↓ 选节点  P 暂停整组  R 核对后恢复整组  A 暂停全部  Q 安全退出',cyan)
  if buffer then gpu.setActiveBuffer(0);gpu.bitblt(0,1,1,w,h,buffer,1,1)end
 end
 function UI.close()
  if buffer then gpu.setActiveBuffer(oldBuffer);gpu.freeBuffer(buffer)end
  gpu.setResolution(oldW,oldH);gpu.setBackground(0x000000);gpu.setForeground(0xFFFFFF)
 end
 return UI
end
