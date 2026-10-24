-- Physical GT containment-bus display; size is capped, never a total.
return function(c,n)
 local side=n.hatchSide
 assert(type(side)=='number'and side%1==0 and side>=0 and side<=5,'实体蜂群总线方向无效')
 assert(side~=n.bankSide and side~=n.loadSide and side~=n.returnSide,'实体蜂群总线方向与盘库/IO重复')
 local kinds={Carbon={1,'Carbon'},Glowstone={1,'Glowstone'},Silver={2,'Silver'},Neutronium={2,'Neutronium'},
  Gold={3,'Gold'},TranscendentMetal={4,'Transcendent'},SixPhasedCopper={5,'SixPhasedCopper'},
  WhiteDwarfMatter={6,'WhiteDwarf'},BlackDwarfMatter={7,'BlackDwarf'},Universium={8,'Universium'},
  Eternity={9,'Eternity'},MagMatter={10,'MagMatter'}}
 local function read()
  assert(c.invoke(n.transposer,'getInventoryName',side)=='gt.blockmachines'and c.invoke(n.transposer,'getInventorySize',side)==3,'实体蜂群收容总线缺失或布局变化')
  local item=c.invoke(n.transposer,'getStackInSlot',side,3)
  if not item then return 0,nil end
  assert(type(item.size)=='number'and item.size%1==0 and item.size>=0 and item.size<=64,'实体蜂群展示数量无效')
  if item.size==0 then return 0,nil end
  local p
  for _,ore in pairs(item.oreNames or {})do
   local k=type(ore)=='string'and ore:sub(1,6)=='nanite'and kinds[ore:sub(7)]
   if k then
    assert(not p or p.tier==k[1]and p.name==k[2],'实体蜂群展示类型不唯一')
    p={tier=k[1],name=k[2]}
   end
  end
  assert(p,'实体总线展示槽不是已知蜂群，保持暂停')
  return item.size,p
 end
 return {read=read,displayCap=64,source='transposer'}
end
