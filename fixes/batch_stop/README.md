# V1 每个实际并行批次完成后关机

按用户要求，防止快速配方在 OC 两次检查之间自动接着执行下一批：

1. 节点已接单且暂停时，关闭节点的 `setWorkAllowed(false)`。
2. 当前批次备齐凝聚物才放行；仍可并行供液、纠缠和按阶段换蜂。
3. 当前批次完成后，机器不再自动调用下一次 `checkRecipe()`。
4. 服务进入下一轮，先确认暂停输出 15，再开机接单；读取新需求，再关机备料和放行。

“一批”是节点当前实际并行批次，例如 64 并行一起完成；不修改最大并行，不取消 AE 队列。暂停中接单不会消耗凝聚物。换蜂仍为被动模式，不因蜂群等级不足主动暂停或关闭纠缠装置。

## 版本依据与限制

核对 GT5-Unofficial **5.09.54.133（Beta 3）**：

- [MTEBECIONode](https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/tectech/thing/metaTileEntity/multi/bec/MTEBECIONode.java) 覆盖 `notAllowedToWork_stopMachine_EM()` 为空；关闭允许工作不清除正在进行的配方。
- [TTMultiblockBase](https://github.com/GTNewHorizons/GT5-Unofficial/blob/5.09.54.133/src/main/java/tectech/thing/metaTileEntity/multi/base/TTMultiblockBase.java) 活跃配方继续增加进度，结束后只有允许工作才调用下一次 `checkRecipe()`。

需要唯一能够同时读取 BEC 状态/需求/并行并调用 `setWorkAllowed`、`isWorkAllowed` 的组件。普通 `bec_io_node` 驱动可能没有启停方法；先运行 `check.lua`，找不到时需确认节点的可启停适配器组件。脚本不会猜测机器地址或误关装配机。多个节点时拒绝自动绑定。每次写之前比较控制组件与既有节点的状态、并行和需求，写后回读。

## 安装

先按 Q 正常退出，等待纠缠装置停稳。下载并运行 `check.lua`，通过后运行 `patch_v1.lua`。安装器只原位修补已安装生产并行 V3 的 `/home/bec_auto.lua`，保留阶段换蜂、UI、过滤、配置、AE 订单和日志。自动备份 `.before-batch-stop-N`；写入 flush/回读，失败恢复，重复安装不写。

已经因缺凝聚物停机的旧配方不能由补丁恢复。原有故障日志不删除，不伪造消耗，不重新提交未知订单；`resume` 仍按原守恒检查决定能否恢复。若旧节点空闲且凝聚物只部分消耗，应先核对 AE 任务与实际输出。

8 个 Lua 5.2 模拟测试覆盖快速批次不得连跑、暂停接下一批、兼容/低阶蜂群无主动暂停、缺失/重复控制组件、错误机器/启停回读失败、未暂停禁止接单、完整现有补丁链安装/语法/备份/日志保留/幂等、替换失败回滚。源码和模拟未代替游戏实测。
