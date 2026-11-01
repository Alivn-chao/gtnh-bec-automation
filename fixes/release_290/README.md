# GTNH 2.9.0 正式版兼容

核对本地正式包：GregTech 5.09.54.265、OpenComputers 1.12.68-GTNH、
Computronics 1.9.13-GTNH、AE2 rv3-beta-1095-GTNH、AE2FC 1.5.116-gtnh。
以这些实际 JAR 和对应标签源码为准，没有用 master 推断旧版本行为。

## 适配内容

- OC 的节点并行参数、韦门过滤，以及 Computronics 的机器启停改为服务器线程
  排队执行，调用返回时可能尚未生效。组件包装器记录已返回写操作的预期值，
  首次回读若尚未符合才每0.05秒等待；符合即返回，普通读取不增加扫描或等待。
- 只发送一次写操作。最多等待5个游戏秒/100次等待；仍不符则保留原持久意图，
  不重新发送。未知回执仍直接报错；搬盘、搬液和AE申请不套用此处理，不自动重放。
- pending在同一配置实例的组件包装器之间共享，网页暂停可覆盖旧目标，回读不会
  再等待已经取消的开放目标。等待使用网页原事件接收器，保留暂停请求和Q退出。
- 固定配额接单先提交整组许可，再统一回读，避免等待回读又变成逐台开放。
  开放后再检查一次取消状态，防止最后一条指令与网页暂停相遇时留下接单许可。

这里的5秒只限制参数写入确认，配方运行仍没有超时；原10秒攒料、代表节点检测、
换蜂/门/备料重叠、阶段追赶与最终消耗证明保留。同步生效的旧版也可用。

## 蜂群总线

正式版移除了旧奇点蜂群收容总线。现场旧总线升级后消失，用户重新装上总线后，
MCP已确认原转运器第4面为 `gt.blockmachines`、3槽，原绑定和展示槽3可继续使用。
正式版装配机的有效蜂群读数仍封顶30720，仓内实际数量可更大；脚本不把展示槽
的64或装配机的30720当实际搬运总量。蜂群种类、配方阶段及搬液回执协议保持兼容。

## 现有固定配额V3升级

本机已由MCP安装。下面仅供其他安装了 `ff5da13` 固定配额版本的电脑更新；
旧三文件性能包/缓存响应包不能完整安装这次兼容补丁。

1. 等生产和缓存完整结束，在OC按Q退出网页。
2. 在OpenOS命令行执行：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/codex/bec-v3-performance/reinstall_v3/update_290.lua /home/bec_290_update.lua
lua /home/bec_290_update.lua
lua /home/bec_v2/main.lua web
```

更新器只替换 `lib/config.lua`、`lib/cell_feed.lua`、`web.lua`，保留地址、配方、
缓存目标、运行记录。拒绝未知本地版本、活动网页、未完成生产/IO/AE请求、未空闲
节点或不足512KiB保留空间。三文件均flush/回读、备份并替换；失败成套回滚。
备份后缀 `.before-release290-N`。更新器只读硬件，不启停机器或搬物品。

## 验证

311项回归及20项核心场景通过，含延迟写入、范围顺序和还原、整组先开放后回读、
丢回执不重发、未生效保护、暂停覆盖、网页请求保留、零搬液不重放，以及更新事务
的六个重命名故障回滚和运行中拒绝更新。

实际OC上已验证原生语法、绑定、16台idle/关闭/RS15，以及新总线3槽；在关闭接单
的空闲节点上将最小并行1→2→1，0.10秒确认首次变更并恢复原范围。没有为测试新下
AE任务或搬原料/蜂群；新配方完整生产和性能仍待下一批实际订单验证。

对照源码：[OC节点驱动](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/scala/li/cil/oc/integration/gregtech/DriverBECIONode.java)、
[OC韦门驱动](https://github.com/GTNewHorizons/OpenComputers/blob/1.12.68-GTNH/src/main/scala/li/cil/oc/integration/gregtech/DriverBECDiode.java)、
[正式版装配机](https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.265/src/main/java/tectech/thing/metaTileEntity/multi/bec/MTEBECAssembler.java)。
