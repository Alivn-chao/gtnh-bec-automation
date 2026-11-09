-- Reset only an idle admission checkpoint with a known physical outcome.
return function(C,cfg,group)
 local native=require('component');local c=C.component and C.component(native)or native;local clock=require('computer')
 local g=assert(cfg.groups[group]);local f=g.cellFeed
 if not(f and f.enabled)then return false end
 local function path(file)return C.path('state/group-'..group..'/'..file)end
 local jp=path('cell-feed.journal');local j=C.read(jp)
 if not j or j.stage=='stopped'then return false end
 assert(j.kind=='cell-feed'and j.version==1 and not j.pending and
  (j.stage=='waiting-nodes'or j.stage=='waiting-node'or j.stage=='nodes-closed'),
  '仅可重置等待接单且无未确认操作的批次')
 for _,name in ipairs({'cohort.dat','cache.journal'})do
  local r=C.read(path(name));assert(not r or r.stage=='stopped'and not r.pending,'生产或补库记录尚未结清')
 end
 local hive=C.read(path('nanites-cell.journal'))
 assert(not hive or hive.stage=='done'and not hive.pending,'换蜂记录尚未结清')
 for i,n in ipairs(cfg.nodes)do if n.group==group then
  local p=C.read(C.path('state/node-'..i..'/production.journal'))
  assert(not p or p.stage=='stopped'and not p.pending and p.configOwned==false,'节点生产记录尚未结清：'..i)
  assert(c.invoke(n.address,'isWorkAllowed')==false and c.invoke(n.address,'getState')=='idle'
   and c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'节点仍在接单或生产：'..i)
 end end
 for _,a in ipairs(g.generators)do
  assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'纠缠器尚未停止')
 end
 local binding={f.transposer,f.sourceSide,f.productionSide,f.sourceSlot,f.productionSlot}
 for i,v in ipairs(binding)do assert(j.binding[i]==v,'原料盘绑定变化')end
 local function stack(side,slot)return c.invoke(f.transposer,'getStackInSlot',side,slot)end
 local describe=assert(loadfile(C.path('lib/cell_feed.lua')))().describe
 local src,dst=stack(f.sourceSide,f.sourceSlot),stack(f.productionSide,f.productionSlot)
 local function intact(d)
  assert(d and d.name==j.cell,'原料盘类型不符')
  local items=describe(d)
  for k,v in pairs(j.items)do assert(items[k]==v,'原料已部分消耗或变化，保留记录')end
  for k in pairs(items)do assert(j.items[k],'原料盘混入其他物品，保留记录')end
 end
 if dst then assert(not src,'进料槽被占用');intact(dst)
 else
  assert(src and src.name==j.cell,'无法确认原料盘位置')
  local _,total=describe(src);if total>0 then intact(src)end
 end
 local plan={}
 for _,i in ipairs(j.members)do
  local n=assert(cfg.nodes[i]);assert(n.group==group)
  local v=assert(j.limits[i]);local q=assert(j.quota[i])
  local lo,hi=c.invoke(n.address,'getMinParallel'),c.invoke(n.address,'getMaxParallel')
  assert((lo==q and hi==q)or(lo==v.min and hi==v.max),'节点配额已被外部修改：'..i)
  plan[#plan+1]={node=n,lo=lo,hi=hi,wanted=v}
 end
 local archive=C.path('diagnostics/feed-reset-'..group..'-'..math.floor(clock.uptime()*1000)..'.dat')
 C.write(archive,j)
 j.pending={kind='manual-reset',archive=archive};C.write(jp,j)
 if dst then
  assert(c.invoke(f.transposer,'transferItem',f.productionSide,f.sourceSide,1,f.productionSlot,f.sourceSlot)==1,'回盘回执未确认，不重试')
  assert(not stack(f.productionSide,f.productionSlot),'回盘后生产槽非空');intact(stack(f.sourceSide,f.sourceSlot))
 end
 for _,p in ipairs(plan)do
  local a,v,lo,hi=p.node.address,p.wanted,p.lo,p.hi
  if lo>v.max then c.invoke(a,'setMinParallel',v.min);lo=v.min end
  if hi<v.min then c.invoke(a,'setMaxParallel',v.max);hi=v.max end
  if lo~=v.min then c.invoke(a,'setMinParallel',v.min)end
  if hi~=v.max then c.invoke(a,'setMaxParallel',v.max)end
  assert(c.invoke(a,'getMinParallel')==v.min and c.invoke(a,'getMaxParallel')==v.max,'恢复配额回读失败')
 end
 j.stage='stopped';j.pending=nil;j.resetArchive=archive;C.write(jp,j)
 return true
end
