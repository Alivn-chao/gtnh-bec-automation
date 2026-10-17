# 蜂群检查耗时优化

用户实测 V1 换蜂平均约10秒；V2的16节点同组检查阶段曾达到2分50秒，内部检查与换盘函数记录124.35秒。截图不足以拆分物理搬运和读取耗时。

V2原先每次 `getState`、`getRequiredTier` 都展开完整组快照；蜂群guard分别读取状态、等级和种类，会重复读取三次配方、并行和消耗记录。改为每轮一个新鲜的完整快照，同时检查成员暂停红石、组内其余节点和全部纠缠器。16节点的同一轮组件调用由292降至100（减少65.8%）。IO等待的tick返回后直接进入下一轮guard，删去两者间紧挨的重复检查。

不跨等待或搬盘缓存快照。每次搬盘前后、IO开始与等待、最终完成仍核对；配方、并行、需求等级、暂停信号、机器停机、完成证明及未确认日志检查保留。不能把调用次数减少直接换算成实机秒数。

## 从已安装的蜂群阶段版、缓存版或heartbeat版更新

OC按Q退出旧网页并暂停。旧临时连接更新包可以删除腾空间（不存在则继续）。不要清空总线或删日志。

```sh
rm /home/bec_connection_update.lua
wget -f https://cdn.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-hive-check-2026-10-17/reinstall_v2/update_hive.lua /home/bec_hive_update.lua
lua /home/bec_hive_update.lua
lua /home/bec_v2/main.lua web
```

仅替换 `lib/bridge.lua` 和 `runtime/nanites_cell.lua`，约37KB下载。精确版本签名、备份回读与失败回滚；不调用机器组件、不改配置/配方/当前与未知日志。不依赖collectgarbage，临时包删不掉也可在空间足够时继续。仍需保留512KiB运行余量。

验证包含16节点调用计数、每轮新鲜读取、配方/批量/暂停变化、非当前批次成员和纠缠器状态、用户取消、现有换蜂动态阶段与硬盘守恒、更新器四处rename故障回滚。全部是模拟验证；实机耗时待用户比较。
