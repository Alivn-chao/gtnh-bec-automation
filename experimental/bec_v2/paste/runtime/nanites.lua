local c=require('component')
local ser=require('serialization')
local fs=require('filesystem')
local clock=require('computer')
local sides=require('sides')
local T='4bebfefd-f3c6-40ac-81d6-35b331415b0f'
local SUPPLY='41c9711c-cb6c-4fb5-8690-9a4ff709d18b'
local HOLD='5009c70f-9607-48b1-8831-488b599942cd'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local PATH='/home/bec_nanites.journal'
local ports,record={},nil
local function call(a,m,...) return c.invoke(a,m,...) end
local function loadRecord()
 local f=io.open(PATH,'r');if not f then return end
 local text=f:read('*a');f:close()
 local r=ser.unserialize(text);assert(type(r)=='table' and r.version==1,'蜂群日志损坏')
 return r
end
local function write(path,text)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 f=assert(io.open(path,'r'));local actual=f:read('*a');f:close();assert(actual==text,'蜂群日志回读失败')
end
local function save(stage)
 record.stage=stage
 local f=io.open(PATH,'r');if f then local old=f:read('*a');f:close();write(PATH..'.previous',old) end
 write(PATH,ser.serialize(record,false))
end
local function id(item) return item.name..':'..tostring(item.damage or 0) end
local labels={{'transcendent',4},{'six phased',5},{'six-phased',5},{'white dwarf',6},{'black dwarf',7},
 {'universium',8},{'eternity',9},{'magmatter',10},{'mag matter',10},{'carbon',1},{'glowstone',1},{'silver',2},{'neutronium',2},{'gold',3}}
local function tier(item)
 if item.name=='gregtech:gt.metaitem.03' and item.damage==451 then return 4 end
 local label=tostring(item.label or ''):lower()
 if not label:find('nanite',1,true) then return end
 for _,entry in ipairs(labels) do if label:find(entry[1],1,true) then return entry[2] end end
 error('未知蜂群类型，请保留物品编号: '..ser.serialize(item,false))
end
local function add(result,item)
 if type(item)~='table' then return end
 local n=item.size or item.amount or 0;if n<=0 then return end
 local grade=tier(item);assert(grade,'蜂群子网里有其他物品: '..tostring(item.label or item.name))
 assert(not item.hasTag,'不支持带NBT蜂群')
 local key=id(item)
 local row=result[key] or {name=item.name,damage=item.damage or 0,tier=grade,label=item.label,size=0}
 row.size=row.size+n;result[key]=row
end
local function stock(address,side)
 local result={};local items=call(address,'getItemsInNetwork');assert(type(items)=='table','蜂群子网库存不可读')
 for _,item in pairs(items) do add(result,item) end
 for slot=1,9 do add(result,call(T,'getStackInSlot',side,slot)) end
 return result
end
local function count(rows) local n=0;for _,item in pairs(rows) do n=n+item.size end;return n end
local function requiredTier()
 local value=call(NODE,'getRequiredTier');return type(value)=='table' and value.tier or value
end
local function discover()
 assert(call(T,'getInventoryName',2)=='tile.appliedenergistics2.BlockInterface','北面应为备用网物品接口')
 assert(call(T,'getInventoryName',4)=='tile.appliedenergistics2.BlockInterface','西面应为收容网物品接口')
 ports[SUPPLY]=2;ports[HOLD]=4
 for _,a in ipairs({SUPPLY,HOLD}) do
  assert(c.type(a)=='me_interface','蜂群接口组件缺失')
  for _,m in ipairs({'getItemsInNetwork','getInterfaceConfiguration','setInterfaceConfiguration'}) do assert(c.methods(a)[m]~=nil,'蜂群接口缺少 '..m) end
 end
end
local function clear(address)
 assert(call(address,'setInterfaceConfiguration',1)==true,'无法清除蜂群接口配置')
 assert(call(address,'getInterfaceConfiguration',1)==nil,'蜂群配置未清除')
 record.owned=nil;save(record.stage)
end
local function configure(address,item)
 record.owned=address;record.config={name=item.name,damage=item.damage,size=64};save(record.stage)
 assert(call(address,'setInterfaceConfiguration',1,record.config)==true,'蜂群接口配置失败；此版本可能需要数据库组件')
 local value=call(address,'getInterfaceConfiguration',1)
 assert(type(value)=='table' and id(value)==id(item),'蜂群配置回读不一致')
end
local function guard(ctx)
 assert(call(RS,'getOutput',sides.top)==15,'换蜂群必须保持暂停')
 local state=call(NODE,'getState')
 assert(state=='paused-immediate' or state=='nanite-tier-too-low','换蜂群时节点状态变化: '..tostring(state))
 assert(requiredTier()==record.requiredTier,'换蜂群时需求等级变化')
 if ctx and ctx.check then ctx.check() end
end
local function tick(ctx)
 if ctx and ctx.tick then ctx.tick(0.1) else os.sleep(0.1) end
 if ctx and ctx.stopping and ctx.stopping() then error('蜂群切换已暂停，保留进度') end
end
local function move(from,to,slot,limit)
 local item=call(T,'getStackInSlot',ports[from],slot)
 if type(item)~='table' or (item.size or 0)<=0 then return 0 end
 assert(tier(item),'接口出现无关物品')
 local n=math.min(limit,item.size)
 record.pending={from=from,to=to,slot=slot,name=item.name,damage=item.damage,requested=n};save(record.stage)
 local moved=call(T,'transferItem',ports[from],ports[to],n,slot)
 assert(type(moved)=='number' and moved>=0 and moved<=n and moved==math.floor(moved),'蜂群搬运返回值不明确')
 record.pending=nil;record.moved=(record.moved or 0)+moved;save(record.stage)
 return moved
end
local function emptyConfigs()
 for _,a in ipairs({SUPPLY,HOLD}) do for slot=1,9 do
  assert(call(a,'getInterfaceConfiguration',slot)==nil,'蜂群专用接口已有配置，请清空配置栏')
 end end
end
local M={}
function M.preview()
 discover()
 print('蜂群转运器: '..T..'；备用北2，收容西4')
 print('收容网: '..ser.serialize(stock(HOLD,4),false))
 print('备用网: '..ser.serialize(stock(SUPPLY,2),false))
 print('所需等级: '..tostring(requiredTier())..'；节点蜂群 '..tostring(call(NODE,'getAvailableNanites')))
end
function M.ensure(ctx)
 local need=requiredTier();if type(need)~='number' then return false end
 discover();record=loadRecord()
 assert(not record or not record.pending,'蜂群搬运存在未确认操作，不能自动重试')
 local provided=call(NODE,'getProvidedTier')
 local have=type(provided)=='table' and provided.tier or 0
 local available=call(NODE,'getAvailableNanites')
 local interrupted=record and record.stage~='done'
 if not interrupted and have==need and available>=64 then return false end
 if interrupted then
  assert(record.requiredTier==need,'旧蜂群切换需求变化，保留日志核对')
  guard(ctx)
  if record.owned then clear(record.owned);tick(ctx) end
 else
  emptyConfigs()
  local reserve=stock(SUPPLY,2)
  local hold=stock(HOLD,4)
  assert(count(hold)==available,'收容子网与节点蜂群数量不符；输出槽请锁定，控制网仅连接这一蜂群仓')
  local choice
  for _,item in pairs(reserve) do
   if item.tier>=need and item.size>=64 and (not choice or item.tier<choice.tier or item.tier==choice.tier and item.size>choice.size) then choice=item end
  end
  if have>=need and available>=64 and (not choice or choice.tier>=have) then return false end
  assert(choice,'备用子网缺少 T'..need..' 或更高等级蜂群，至少需要64个')
  local baseline={}
  for key,item in pairs(reserve) do baseline[key]=item.size end
  for key,item in pairs(hold) do baseline[key]=(baseline[key] or 0)+item.size end
  record={version=1,requiredTier=need,choice=choice,goal=math.min(choice.size,math.max(64,available)),stage='draining',moved=0,baseline=baseline}
  guard(ctx);save('draining')
  print('蜂群切换: T'..have..' -> T'..choice.tier..'，目标 '..record.goal..' 个')
 end
 local deadline=clock.uptime()+300
 if record.stage=='draining' then
  while true do
   guard(ctx);assert(clock.uptime()<deadline,'退回蜂群超时，检查存储总线允许提取及备用网空间')
   local rows=stock(HOLD,4)
   if count(rows)==0 then if record.owned then clear(record.owned) end;save('filling');break end
   local old;for _,item in pairs(rows) do old=item;break end
   if record.owned then clear(record.owned);tick(ctx) end
   configure(HOLD,old)
   while true do
    guard(ctx);assert(clock.uptime()<deadline,'退回蜂群超时')
    for slot=1,9 do move(HOLD,SUPPLY,slot,64) end
    tick(ctx)
    local fresh=stock(HOLD,4);if not fresh[id(old)] then break end
   end
   clear(HOLD);tick(ctx)
  end
 end
 if record.stage=='filling' then
  configure(SUPPLY,record.choice)
  while true do
   guard(ctx);assert(clock.uptime()<deadline,'装入蜂群超时，检查存储总线允许插入')
   local rows=stock(HOLD,4);local held=rows[id(record.choice)]
   local n=held and held.size or 0
   assert(count(rows)==n and n<=record.goal,'收容子网混入其他蜂群或超额，保持暂停')
   if n==record.goal then break end
   for slot=1,9 do
    local item=call(T,'getStackInSlot',2,slot)
    if item and (item.size or 0)>0 then assert(id(item)==id(record.choice),'供货口蜂群类型变化');n=n+move(SUPPLY,HOLD,slot,record.goal-n) end
    if n==record.goal then break end
   end
   tick(ctx)
  end
  clear(SUPPLY);save('verifying')
 end
 local verified=false
 for i=1,50 do
  guard(ctx);local p=call(NODE,'getProvidedTier');local n=call(NODE,'getAvailableNanites')
  if type(p)=='table' and p.tier==record.choice.tier and n==record.goal then verified=true;break end
  tick(ctx)
 end
 assert(verified,'蜂群仓回读未达到目标，检查控制网是否仅存储在蜂群仓')
 local actual={}
 for key,item in pairs(stock(SUPPLY,2)) do actual[key]=item.size end
 for key,item in pairs(stock(HOLD,4)) do actual[key]=(actual[key] or 0)+item.size end
 for key,n in pairs(record.baseline) do assert(actual[key]==n,'蜂群总量核对不符，保留日志: '..key) end
 for key,n in pairs(actual) do assert(record.baseline[key]==n,'蜂群库存类型变化，保留日志: '..key) end
 save('done');print('蜂群切换完成: T'..record.choice.tier..' / '..record.goal..' 个')
 return true
end
return M
