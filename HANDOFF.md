# 在家里的 Codex 接着做

## 用户意图与当前成果

用户要 GTNH BEC 的样板转换、凝聚物精确补料、缺料自动合成下单、自动切换纳米蜂群。避免 ProjectRed；中文、一步一步指导，有接线图更好。

已实际完成 Primitive Shielding（原始屏蔽层）×1，从 AE 下发到 BEC 合成、成品回主网。两种原液通过 OC 转运器精确加入独立子网，进阶存储输入仓自动拉取，纠缠装置转换后约束场读到两种凝聚物各 288。随后 AE 下单、节点合成完成，无线终端已找到成品。

最新状态（evidence_final_status.png）：

```text
storage: 237a9cac-118a-4b74-8755-0d0b0ad216c0
getStoredCondensate: {}
getFieldStrength: 2000000000
node: b04787f9-5423-4b03-8549-c786d4ef38d0
getState: idle
getParallelRecipesInProgress: 0
getMinParallel / getMaxParallel: 1 / 1
getProvidedTier: {name="Transcendent",tier=4}
getAvailableNanites: 64
getRequiredTier: nil
getRequiredCondensate: nil
getConsumedCondensate: {entangled_transcendentmetal=288,entangled_chromaticglass=288}
main/sub interface caches: empty
```

getConsumedCondensate 在空闲时仍保留上一单的消耗记录，不能当新单需求。接口缓存为空不等于子网存储元件为空，自动补料应读取子网网络总库存。

## 已转换的配方记录

游戏电脑路径 `/home/bec/recipes/gregtech_gt_metaitem_03_32307_1.dat`。这份游戏文件未导出到本地，仓库不包含真实 .dat。

原始样板有 7 项输入，转换后保留 5 项普通物品，移除第 6、7 项凝聚物流体：

- `entangled_chromaticglass` 288
- `entangled_transcendentmetal` 288
- 成品 `gregtech:gt.metaitem.03`，damage=32307，size=1。

转换工坊接口槽 1 的样板副本已转换。转换后的样板已放最终生产样板接口。不要再转换或执行修复以取得状态。

真实记录此前被 `serialization.serialize(record,true)` 截断，OpenOS 的 pretty 输出默认限制行数，生成不可反序列化的文件。修复脚本已改 false，用户修复成功，之后备料和生产成功。

修复后记录大致包含 version=1、state="converted"、interface、slot=1、ordinaryInputs、outputs、convertedPattern、recovered=true、condensates。修复版不保证包含 original，后续程序不要强制依赖 original。

## 接下来先做什么

停止点：上一轮建议给传送节点安装 **IONode 控制仓**，设 **立即暂停（PAUSE_INSTANT）**，先用拉杆验证，再接 OC 红石控制。用户尚未确认安装或测试，不能写成已完成。

原因：查到的 Beta 参考节点源码会在启动普通物品配方后设置 requiredCondensate。它不会自动因缺凝聚物而等待，会继续进度，直到结束检查缺料并失败。已有阻挡卡不能替代 OC 的凝聚物库存等待逻辑。

建议验证顺序：

1. 确认游戏版本控制仓的立即暂停模式及接线。先暂停，再让 AE 下发一单，检查节点返回 paused-immediate 和需求；不得让缺凝聚物的单子无保护运行。
2. 确认 OC 能驱动控制仓红石信号（用户未证明已有 redstone 组件）。控制仓不同于关闭整个机器，优先使用已有暂停 API/红石机制。
3. 导出游戏里现有 `bec_prepare.lua` 和有效 .dat，或据已验证规则重建并测试。见 bec_prepare_MISSING.md。
4. 自动读节点当前需求、已消耗、约束场现存、子网原液，精确补差额。样例只支持两个映射；不要猜其它凝聚物转换比例。
5. 等约束场凝聚物达到尚需量后解除暂停。完成后恢复待机暂停，处理连续单、取消、重启、部分搬运。
6. 再加入主网缺料 AE 合成请求，先验证流体 request 的单位、craftable 对象调用方式和完成状态，不要把 request(1) 未经验证解释成 1 mB 或 1 桶。
7. 最后扩展配方、蜂群切换和多并行。

如果现有顶部物品缓冲已经有适合 OC 的放行方式，也可在核对部件/API后选用；不要为假定的方案拆除已成功结构。

## 曾踩过的坑

- 流体接口配置是 0 起，转运器槽是 1 起；错误索引导致 index out of bounds。
- 错认生产接口为供液接口，曾等缓存超时；当前正确地址在 HARDWARE.md。
- 主网缓存可能一次拉入 16000，而非指定 144；转运器的实际精确搬运和子网数量才决定转换总量。
- 主网原液有多少不可控，不允许进阶输入仓直接读主网或存储总线桥接。
- 方法表值 false 是非 direct 方法存在，不能当方法缺失。
- 写文件不要断言 close() 必须 true；OpenOS 可返回 nil。显式 flush、回读一致性、可反序列化、保留备份。
- 两个 gt_machine 名称都不是机器专有名称，自动开关地址还没确认。
- `bec_prepare.lua` 本地零字节；游戏里曾成功运行，二者不是同一份文件。

## 证据与源码适用范围

真实游戏截图优先于当前 master 文档。参考 GT5 源码快照 commit `081055b6c8a7bb5896fec8784daa524daa51b06d`，不等于已经确认每个文件都是用户 Beta 3 对应版本。

- [BEC 节点源码](https://github.com/GTNewHorizons/GT5-Unofficial/blob/081055b6c8a7bb5896fec8784daa524daa51b06d/src/main/java/tectech/thing/metaTileEntity/multi/bec/MTEBECIONode.java)
- [凝聚物定义](https://github.com/GTNewHorizons/GT5-Unofficial/blob/081055b6c8a7bb5896fec8784daa524daa51b06d/src/main/java/gregtech/api/enums/CondensateType.java)
- [AE2FC 流体接口实现](https://github.com/GTNewHorizons/AE2FluidCraft-Rework/blob/master/src/main/java/com/glodblock/github/util/DualityFluidInterface.java)
- [OpenOS 序列化说明](https://ocdoc.cil.li/api:serialization)
- [转运器 API](https://ocdoc.cil.li/component:transposer)
- [用户参考磁物质自动化教程](https://gtnh.huijiwiki.com/wiki/磁物质自动化)：此前完整网页被安全验证阻挡，只有索引代码片段读到，不能声称通读。

## 给家里 Codex 的启动提示

> 请先读 AGENTS.md、HANDOFF.md、HARDWARE.md 和 bec_prepare_MISSING.md，接续我的 GTNH BEC 自动化。独立子网精确补液和一份原始屏蔽层合成回主网已经成功；先核对传送节点控制仓立即暂停，随后接自动补料、缺料 AE 下单和蜂群切换。不要重复转换、修复或拆掉已有成功接线。用户会手动操作游戏并发截图。
