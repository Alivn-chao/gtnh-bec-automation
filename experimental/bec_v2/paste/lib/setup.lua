local c=require('component')
local term=require('term')
return function(C)
 local function ask(label,default)
  io.write(label..(default~=nil and ' ['..tostring(default)..']' or '')..': ')
  local answer=assert(io.read(),'配置输入已取消')
  return answer=='' and default or answer
 end
 local function number(label,default,lo,hi)
  while true do local n=tonumber(ask(label,default));if n and n==math.floor(n) and n>=lo and n<=hi then return n end;print('请输入 '..lo..' 到 '..hi..' 的整数') end
 end
 local function pick(label,kind,method)
  local rows={}
  for a,t in c.list() do if (not kind or t==kind) and (not method or c.methods(a)[method]~=nil) then rows[#rows+1]={a,t} end end
  table.sort(rows,function(a,b)return a[1]<b[1]end)
  print('\n'..label)
  for i,r in ipairs(rows) do print(i..'  '..r[2]..'  '..r[1]) end
  assert(#rows>0,'找不到 '..label..'；请接入OC网络')
  while true do
   local value=ask('输入序号或地址前缀')
   local index=tonumber(value)
   if index and rows[index] then return rows[index][1] end
   local selected,count=nil,0
   for _,r in ipairs(rows) do if r[1]:sub(1,#value)==value then selected=r[1];count=count+1 end end
   if count==1 then return selected end
   print('选择不唯一或不存在')
  end
 end
 term.clear();print('BEC V2 / 独立测试版配置向导')
 print('方向：0下 1上 2北 3南 4西 5东；配置时只读取设备')
 local previous=C.read(C.path('config.dat'))
 if previous then
  for group in ipairs(previous.groups)do
   local old=C.read(C.path('state/group-'..group..'/cohort.dat'))
   assert(not old or old.stage=='stopped','本组旧进度尚未结束；先按原配置核对恢复，禁止更换设备绑定')
  end
  print('已有配置。重新配置会备份旧配置，不修改稳定版。')
 end
 local count=number('传送节点数量',previous and #previous.nodes or 1,1,16)
 local groupCount=number('观测阵列/设备组数量',1,1,count)
 local cfg={version=2,nodes={},groups={},cacheTarget=144000}
 cfg.mainInterface=pick('主网供液接口','me_interface','getFluidsInNetwork')
 cfg.recipeDirectory=ask('已转换配方记录目录','/home/bec/recipes')
 for i=1,groupCount do
  print('\n=== 设备组 '..i..' ===')
  local g={name=ask('设备组名称','观测阵列'..i),generators={},bulkTransposers={}}
  g.storage=pick('此组约束场','bec_storage','getStoredCondensate')
  g.gate=pick('此组韦门','bec_diode','setCondensateFilters')
  g.subInterface=pick('此组原液子网接口','me_interface','getFluidsInNetwork')
  g.transposer=pick('主网到此子网的供液转运器','transposer')
  g.mainSide=number('转运器主网方向',4,0,5);g.subSide=number('转运器子网方向',5,0,5)
  local generators=number('此组纠缠器数量',1,1,64)
  for j=1,generators do g.generators[j]=pick('纠缠器 '..j,'gt_machine','setWorkAllowed') end
  local bulk=number('此组额外高速供液转运器数量（没有填0）',0,0,64)
  for j=1,bulk do g.bulkTransposers[j]=pick('高速供液转运器 '..j,'transposer') end
  local enabled=ask('启用此组自动换蜂群？y/n','n')=='y'
  g.nanites={enabled=enabled}
  if enabled then
   local n=g.nanites
   n.transposer=pick('蜂群转运器','transposer')
   n.supplyInterface=pick('备用蜂群子网接口','me_interface','getItemsInNetwork')
   n.hatchInterface=pick('收容总线子网接口','me_interface','getItemsInNetwork')
   n.supplySide=number('备用网接口方向',2,0,5);n.hatchSide=number('收容网接口方向',4,0,5)
  end
  cfg.groups[i]=g
 end
 for i=1,count do
  print('\n=== 传送节点 '..i..' ===')
  local group=number('归属设备组',1,1,groupCount)
  cfg.nodes[i]={name=ask('节点名称','节点'..i),group=group,
   address=pick('传送节点','bec_io_node','getState'),
   redstone=pick('暂停控制红石I/O','redstone','setOutput'),
   pauseSide=number('红石输出方向',1,0,5),
   gate=cfg.groups[group].gate}
 end
 C.validate(cfg,true)
 C.write(C.path('config.dat'),cfg)
 print('\n配置已保存。运行 lua /home/bec_v2/main.lua monitor 先看仪表盘。')
end
