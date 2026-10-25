-- Frozen storage-cell batches. Never replay an uncertain move or admission.
local component=require('component')
local clock=require('computer')
local fs=require('filesystem')
local M={}
local function whole(n)return type(n)=='number'and n>=0 and n%1==0 and n<=9007199254740991 end
local function key(v)
 assert(type(v)=='table'and type(v.name)=='string','物品标识不可读')
 assert(not v.hasTag,'原料含NBT，尚不支持自动配方匹配')
 return v.name..':'..tostring(v.damage or 0)
end
local function itemMap(list)
 local result={}
 for _,v in pairs(list)do local n=v.size or v.amount;assert(whole(n)and n>0,'原料数量无效或含非消耗输入');local k=key(v);result[k]=(result[k]or 0)+n end
 return result
end
function M.describe(cell)
 assert(type(cell)=='table'and cell.size==1 and whole(cell.storedItemCount)and type(cell.getAvailableItems)=='table','存储盘内容不可读')
 local items=itemMap(cell.getAvailableItems);local total=0;for _,n in pairs(items)do total=total+n end
 assert(total==cell.storedItemCount,'盘内总数与清单不符');return items,total
end
function M.match(items,recipes)
 local found,count
 for _,r in ipairs(recipes)do
  local n,ok=nil,true
  for k,unit in pairs(r.items)do local v=items[k];if not v or v%unit~=0 then ok=false;break end;local q=v/unit;if n and n~=q then ok=false;break end;n=q end
  for k in pairs(items)do if not r.items[k]then ok=false end end
  if ok and n and n>=1 then assert(not found,'相同原料对应多份登记，不能猜测配方');found=r;count=n end
 end
 assert(found,'盘内原料未匹配到唯一完整登记配方，保持暂停');return found,count
end
function M.allocate(total,limits)
 assert(whole(total)and total>0,'批次份数无效')
 local quota={};local left=total
 for _,n in ipairs(limits)do assert(whole(n.max)and n.max>0);quota[n.index]=0 end
 while left>0 do
  local available={};for _,n in ipairs(limits)do if quota[n.index]<n.max then available[#available+1]=n end end
  assert(#available>0,'本批超过16台单轮并行容量，保留原料盘；请拆小批次')
  for pos,n in ipairs(available)do local portion=math.ceil(left/(#available-pos+1));local add=math.min(portion,n.max-quota[n.index],left);quota[n.index]=quota[n.index]+add;left=left-add end
 end
 return quota
end
function M.new(cfg,group,C,E,resumeAdmission)
 local settings=cfg.groups[group].cellFeed
 if not(settings and settings.enabled)then return end
 local c=C.component and C.component(component)or component
 local F={ready=false,message='等待缓存盘进料',nextPoll=0}
 local path=C.path('state/group-'..group..'/cell-feed.journal')
 local old=C.read(path)
 assert(not old or old.stage=='stopped'or resumeAdmission==true and old.stage=='waiting-node'and not old.pending,'原料盘有未完成批次，请保留记录核对，禁止自动重放')
 local cohort=C.read(C.path('state/group-'..group..'/cohort.dat'))
 assert(not cohort or cohort.stage=='stopped','整组有旧生产记录，禁止搬入新原料盘')
 for i,n in ipairs(cfg.nodes)do if n.group==group then
  local j=C.read(C.path('state/node-'..i..'/production.journal'))
  assert(not j or j.stage=='stopped'and not j.pending and j.configOwned==false,'节点存在未完成生产记录，禁止新批次')
  for _,job in ipairs(j and j.requests or {})do assert(job.state=='done','节点旧AE请求未确认')end
 end end
 local recipes={}
 for file in fs.list(cfg.recipeDirectory)do if file:match('%.dat$')then
  local r=C.read(cfg.recipeDirectory..'/'..file)
  if r and r.state=='converted'and type(r.ordinaryInputs)=='table'and #r.ordinaryInputs>0 then
   local ok,items=pcall(itemMap,r.ordinaryInputs)
   if ok then recipes[#recipes+1]={file=file,items=items,condensates=r.condensates,outputs=r.outputs}end
  end
 end end
 local function call(m,...)return c.invoke(settings.transposer,m,...)end
 local function stack(side,slot)return call('getStackInSlot',side,slot)end
 local record
 local function save(stage)record.stage=stage;C.write(path,record)end
 local function members()
  local result={};for i,n in ipairs(cfg.nodes)do if n.group==group then result[#result+1]=i end end;return result
 end
 local ids=members()
 local function enabled()
  for _,i in ipairs(ids)do assert(not E.tasks[i].disabled and not E.tasks[i].fault,'原料批次已暂停，保留记录')end
 end
 local function closeAll()
  for _,i in ipairs(ids)do
   local n=cfg.nodes[i];c.invoke(n.redstone,'setOutput',n.pauseSide,15)
   assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'暂停输出回读失败');E.nodeWork(i,false)
  end
 end
 local function idleClosed()
  for _,i in ipairs(ids)do local n=cfg.nodes[i]
   assert(c.invoke(n.address,'getState')=='idle'and c.invoke(n.address,'isWorkAllowed')==false,'整组未空闲关闭接单，禁止搬盘')
  end
 end
 local function drives()
  for _,side in ipairs({settings.sourceSide,settings.productionSide})do
   assert(call('getInventoryName',side)=='tile.appliedenergistics2.BlockDrive'and call('getInventorySize',side)==10,'原料两侧必须是10槽ME驱动器')
  end
 end
 local function move(from,to,sourceSlot,destSlot,stage)
  enabled();assert(not stack(to,destSlot),'搬盘目标槽被占用')
  local before=stack(from,sourceSlot);assert(before and before.size==1 and before.name==record.cell,'原料盘已变化')
  record.pending={kind='move',from=from,to=to,sourceSlot=sourceSlot,destSlot=destSlot};save(stage)
  enabled();assert(call('transferItem',from,to,1,sourceSlot,destSlot)==1,'搬盘回执不确定，不重复搬运')
  local after=stack(to,destSlot)
  assert(not stack(from,sourceSlot)and after and after.name==record.cell and after.size==1,'搬盘后槽位不符，不重复搬运')
  record.pending=nil;save(stage..'-confirmed');return after
 end
 local function parallel(i,from,wanted)
  local n=cfg.nodes[i];local lo,hi=from.min,from.max
  if lo>wanted.max then c.invoke(n.address,'setMinParallel',wanted.min);lo=wanted.min end
  if hi<wanted.min then c.invoke(n.address,'setMaxParallel',wanted.max);hi=wanted.max end
  if lo~=wanted.min then c.invoke(n.address,'setMinParallel',wanted.min)end
  if hi~=wanted.max then c.invoke(n.address,'setMaxParallel',wanted.max)end
  assert(c.invoke(n.address,'getMinParallel')==wanted.min and c.invoke(n.address,'getMaxParallel')==wanted.max,'并行参数回读失败')
 end
 local function restore()
  for _,i in ipairs(record.members)do local v=record.limits[i];local q=record.quota[i]
   record.pending={kind='restore-parallel',node=i};save('restoring')
   parallel(i,{min=q,max=q},v)
   record.pending=nil;save('restored')
  end
 end
 if resumeAdmission then
  -- Explicit repair entry, never selected by the normal engine constructor.
  -- Only confirmed pre-production admission can resume; no move is replayed.
  assert(old and old.stage=='waiting-node'and not old.pending and type(old.members)=='table'and type(old.quota)=='table'and type(old.limits)=='table','不支持恢复此原料批次')
  assert(old.openNode==old.members[old.cursor]and old.cell and old.recipe,'接单检查点无效')
  local binding={settings.transposer,settings.sourceSide,settings.productionSide,settings.sourceSlot,settings.productionSlot}
  assert(type(old.binding)=='table'and #old.binding==#binding)
  for i,v in ipairs(binding)do assert(old.binding[i]==v,'原料盘接线已变化')end
  drives();local recipe
  for _,r in ipairs(recipes)do if r.file==old.recipe then recipe=r end end;assert(recipe,'恢复时配方登记缺失')
  local total,accepted=0,0
  for _,i in ipairs(ids)do
   local n=cfg.nodes[i];local q=old.quota[i];assert(whole(q)and old.limits[i]);total=total+q
   assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15 and c.invoke(n.address,'isWorkAllowed')==false,'恢复前整组必须暂停并关闭接单')
   local state=c.invoke(n.address,'getState');local p=c.invoke(n.address,'getParallelRecipesInProgress')
   if state~='idle'then
    assert(state=='paused-immediate'or state=='nanite-tier-too-low','恢复时节点状态异常')
    assert(p==q and q>0,'恢复接单配额不符');local req=c.invoke(n.address,'getRequiredCondensate');local used=c.invoke(n.address,'getConsumedCondensate')
    assert(type(req)=='table'and type(used)=='table')
    local expected={};for _,v in ipairs(recipe.condensates)do expected[v.name]=(expected[v.name]or 0)+v.amount*q end
    for k,v in pairs(expected)do assert(req[k]==v and(used[k]or 0)==0,'生产已消耗或接到了其他配方')end
    for k,v in pairs(used)do assert(v==0,'生产已消耗凝聚物')end
    for k in pairs(req)do assert(expected[k],'恢复时需求含未知流体')end
    local position;for pos,j in ipairs(old.members)do if j==i then position=pos end end
    assert(position and position<=old.cursor,'后续节点提前接单');accepted=accepted+q
   else
    assert(p==0,'空闲节点并行不为零')
    for pos,j in ipairs(old.members)do assert(j~=i or pos>=old.cursor,'先前确认节点变为空闲')end
   end
   if q>0 then assert(c.invoke(n.address,'getMinParallel')==q and c.invoke(n.address,'getMaxParallel')==q,'恢复时节点配额设置变化')end
  end
  assert(total==old.count,'原始批次数量不符')
  for _,side in ipairs({settings.sourceSide,settings.productionSide})do for slot=1,10 do
   if side~=settings.productionSide or slot~=settings.productionSlot then assert(not stack(side,slot),'恢复时原料盘位置变化')end
  end end
  local disk=stack(settings.productionSide,settings.productionSlot);assert(disk and disk.name==old.cell)
  local items=M.describe(disk)
  for k,unit in pairs(recipe.items)do assert(old.items[k]==unit*old.count and(items[k]or 0)==unit*(old.count-accepted),'余料与已接单数量不符')end
  for k in pairs(items)do assert(recipe.items[k],'恢复时混入其他原料')end
  record=old
 end
 function F.observe()
  if clock.uptime()<F.nextPoll then return end;F.nextPoll=clock.uptime()+1
  local v=stack(settings.sourceSide,settings.sourceSlot)
  if v and whole(v.storedItemCount)and v.storedItemCount>0 then F.since=F.since or clock.uptime()else F.since=nil end
 end
 function F.pending()F.observe();return record~=nil or F.since~=nil end
 function F.step()
  enabled();if F.ready then return true end
  assert(not record or not record.pending,'原料盘有未确认操作，禁止自动重放')
  F.observe()
  if not record then
   if not F.since or clock.uptime()-F.since<(settings.collectSeconds or 10)then
    F.message=F.since and '同配方攒料10秒' or '等待缓存盘进料';return false
   end
   for _,i in ipairs(ids)do if c.invoke(cfg.nodes[i].address,'getState')~='idle'then F.message='等待全部节点空闲';return false end end
   drives();closeAll();idleClosed()
   for _,side in ipairs({settings.sourceSide,settings.productionSide})do for slot=1,10 do
    if side==settings.productionSide or slot~=settings.sourceSlot then assert(not stack(side,slot),'原料驱动器存在其他盘，禁止混批')end
   end end
   local v=assert(stack(settings.sourceSide,settings.sourceSlot),'原料盘不见了')
   record={version=1,kind='cell-feed',binding={settings.transposer,settings.sourceSide,settings.productionSide,settings.sourceSlot,settings.productionSlot},cell=v.name,limits={},quota={},members={}}
   save('capturing')
   local captured=move(settings.sourceSide,settings.productionSide,settings.sourceSlot,settings.productionSlot,'moving-to-production')
   local items=M.describe(captured);local recipe,count=M.match(items,recipes)
   record.items=items;record.recipe=recipe.file;record.count=count;record.condensates=recipe.condensates;record.outputs=recipe.outputs
   local limits={}
   for _,i in ipairs(ids)do local n=cfg.nodes[i];local lo=c.invoke(n.address,'getMinParallel');local hi=c.invoke(n.address,'getMaxParallel')
    assert(whole(lo)and lo>=1 and whole(hi)and hi>=lo,'节点并行参数无效')
    record.limits[i]={min=lo,max=hi};limits[#limits+1]={index=i,max=settings.maxParallelPerNode or hi}
   end
   record.quota=M.allocate(count,limits);save('planned')
   for _,i in ipairs(ids)do local q=record.quota[i];if q>0 then
    local n=cfg.nodes[i];record.pending={kind='set-parallel',node=i,quota=q};save('configuring')
    enabled();parallel(i,record.limits[i],{min=q,max=q})
    record.pending=nil;record.members[#record.members+1]=i;save('configured')
   end end
   record.cursor=1;save('admitting')
   F.message='原料盘已冻结：'..count..'份 / '..#record.members..'台'
   E.log(ids[1],F.message)
  end
  local i=record.members[record.cursor]
  if i then
   local n=cfg.nodes[i];local state=c.invoke(n.address,'getState')
   if not record.openNode then
    assert(state=='idle','节点接单前不空闲');record.openNode=i;record.pending={kind='admission',node=i};save('opening-node')
    enabled();E.nodeWork(i,true);record.pending=nil;save('waiting-node');return false
   end
   if state=='idle'then return false end
   E.nodeWork(i,false)
   if state=='crafting'then
    assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'接单后暂停信号缺失')
    F.message='等待节点'..i..'进入暂停状态';return false
   end
   assert(state=='paused-immediate'or state=='nanite-tier-too-low','接单状态异常：'..tostring(state))
   assert(c.invoke(n.address,'getParallelRecipesInProgress')==record.quota[i],'实际接单数量与配额不符')
   local req=c.invoke(n.address,'getRequiredCondensate');local expected={}
   for _,v in ipairs(record.condensates)do expected[v.name]=(expected[v.name]or 0)+v.amount*record.quota[i]end
   assert(type(req)=='table','凝聚物需求不可读')
   for k,v in pairs(expected)do assert(req[k]==v,'接到的配方与原料盘不符')end
   for k in pairs(req)do assert(expected[k],'节点接到无关配方')end
   record.openNode=nil;record.cursor=record.cursor+1;save('node-admitted');return false
  end
  closeAll()
  local disk=stack(settings.productionSide,settings.productionSlot);local _,remaining=M.describe(disk)
  assert(remaining==0,'接单后原料盘有余料，保持整组暂停')
  move(settings.productionSide,settings.sourceSide,settings.productionSlot,settings.sourceSlot,'returning-empty-cell')
  save('ready');F.ready=true;F.since=nil;return true
 end
 function F.finish()
  assert(record and F.ready,'原料批次未就绪');closeAll();idleClosed();restore();save('stopped')
  record=nil;F.ready=false;F.message='等待下一批原料';F.observe()
 end
 function F.plan()return record end
 return F
end
return M
