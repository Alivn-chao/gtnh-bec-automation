-- 阅读用示例。实际配置由 main.lua setup 写入 config.dat。
-- 所有地址均选自己设备；不复制作者的地址。
-- 同一个装配机/BEC网络的节点放在同一组：同配方并行、共用蜂群。
return {
 version=2,
 mainInterface='这里填主网供液ME接口地址',
 recipeDirectory='/home/bec_v2/recipes', -- 新用户在此登记；旧用户可用/home/bec/recipes
 workshopInterface='这里填专用样板工坊ME接口地址', -- 不选择生产接口
 cacheTarget=144000, -- 仪表盘库存参考线；本测试版按正在运行的批次补液
 groups={
  {
   name='观测阵列1',
   storage='这里填本组约束场适配器地址',
   gate='这里填本组麦克斯韦门适配器地址',
   subInterface='这里填本组原液子网ME接口地址',
   transposer='这里填主网到本组原液子网的转运器地址',
   mainSide=4,subSide=5, -- 0下 1上 2北 3南 4西 5东
   generators={
    '这里填第一台纠缠器的适配器地址',
    -- '这里填第二台纠缠器地址', -- 需要几台就增加几项
   },
   bulkTransposers={}, -- 额外高速供液转运器，没有则留空
   nanites={
    enabled=true,
    transposer='这里填蜂群转运器地址',
    supplyInterface='这里填备用蜂群子网ME接口地址',
    hatchInterface='这里填收容总线子网ME接口地址',
    supplySide=2,hatchSide=4,
   },
  },
 },
 nodes={
  {name='节点1',group=1,
   address='这里填传送节点1的适配器地址',
   redstone='这里填控制节点1暂停的红石I/O地址',pauseSide=1,
   gate='这里填本组韦门地址'},
  -- 节点2至16同样增加条目，group=1表示共用上面整组设备。
  -- 一个红石I/O能控制多节点：地址可重复，输出方向必须不同。
 },
}
