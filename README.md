# GTNH BEC 自动化

2026-10-09 项目接续快照。环境为 GTNH 2.9.0 Beta 3、OpenComputers/OpenOS；游戏终端显示 Lua 5.3，代码使用 Lua 5.2 兼容语法。

**最新接续入口：[NEXT_SESSION.md](NEXT_SESSION.md)。** 当前已实现常驻生产 UI、主网缺液 AE 下单并在合成中收料、样板登记、可编辑缓存配置与空闲自动补缓存。已登记配方生产匹配的最新修正通过模拟，等待游戏验收；BEC 凝聚物网络自动过滤和蜂群切换尚未完成。历史说明以下面的最新接续入口为准。

**已完成一份原始屏蔽层（Primitive Shielding）的真实合成及成品回主网。常驻补料和主网缺原液自动申请已实现并通过本地模拟，待完整游戏验收；蜂群自动切换尚未实现。**

在另一台电脑的 Codex 中打开此仓库，先读 [HANDOFF.md](HANDOFF.md) 和 [HARDWARE.md](HARDWARE.md)。不要重新执行转换或修复；本次配方记录在游戏电脑中已经修复。

## 已验证

- OC 配置主网流体接口缓存，转运器精确搬运原液到独立子网；不使用外部储罐。
- 纠缠装置的进阶存储输入仓读取子网，原液转换为凝聚物后进入约束场。
- 传送节点的进阶存储输入总线读取子网物品，ME 输出总线将成品回收到主网。
- 最终生产样板接口已放转换后的样板；用户安装高级阻挡卡并启用智能阻挡模式。
- 一次 Primitive Shielding ×1 合成成功，两种凝聚物各消耗 288。
- 新 bec_auto_once.lua 已真实完成一单自动补液、转换、放行及恢复待机暂停；连续循环、缺料 AE 下单与蜂群切换尚未实现。

## 文件

| 文件 | 用途与状态 |
| --- | --- |
| `bec_live_status.lua` | 最新只读状态检查，用户已成功执行；无翻页 |
| `bec_auto_once.lua` / `AUTO_ONCE.md` | 单次自动补液/转换/放行程序；默认只读预览，23 个模拟场景通过，修正版已真实自动完成原始屏蔽层 ×1 |
| `bec_auto_batch.lua` / `AUTO_BATCH.md` | 同配方多任务按合计份数备料、连续放行；本次 5+10 共 15，模拟通过，待游戏预览及整批验收 |
| `bec_auto.lua` / `AUTO.md` | 常驻整批版；自动读取 AE 剩余数量与实际并行，一次备齐流体，缺原液申请与已完成后的实测差额处理，38 个模拟场景通过 |
| `bec_convert.lua` | 工坊样板转换；会修改样板，保存凝聚物需求记录 |
| `bec_repair_recipe.lua` | 仅恢复这份已知 Primitive Shielding 记录；已执行完成，不应例行重跑 |
| `bec_feed_test.lua` | 精确搬运 144 mB 彩色玻璃原液的单次测试；会搬料，不是守护程序 |
| `bec_feed_probe.lua` | 只读接口与转运器诊断 |
| `bec_pattern.lua` / `bec_pattern_read.lua` | 样板读取诊断 |
| `bec_check.lua` / `bec_probe.lua` | 早期组件诊断 |
| `bec_status.lua` | 旧全量诊断，会列举大量方法并翻页；日常改用 live 版本 |
| `bec_fluid_check.lua` | 早期储罐方案诊断，留档；不适用于当前接法 |
| `bec_prepare_MISSING.md` | 本地备料脚本空文件问题和恢复要求；没有可运行的本地 prepare 副本 |
| `bec_batch_subnet.png` | 独立流体子网方案示意；物品实际接法以 HARDWARE 和截图为准 |
| `evidence_*.png` | 本次实际游戏运行和最终状态截图 |
| `test_bec_convert.py` / `test_feed_test.py` | 可复跑的 Lua 模拟验证，不代表真实硬件验收 |

游戏电脑上的典型执行命令：

```sh
lua /home/bec_live_status.lua
```

复制新脚本时可用 `edit /home/文件名.lua`，粘贴全文后 Ctrl+S 保存、Ctrl+W 退出。不要自动覆盖用户游戏电脑的需求记录。

## 本地测试

需要 Python 和 `lupa`，从仓库根目录执行：

```sh
python -m pip install -r requirements-dev.txt
python test_bec_convert.py
python test_feed_test.py
```

打包时 11 个非空 Lua 文件通过 Lua 5.2 语法解析；转换和搬液模拟测试分别 8、7 个场景通过。实际游戏验收证据见截图和 HANDOFF。缺失的备料文件不在这个结论中。

## 项目目标

下一步验收常驻补料和主网 AE 原液申请，再实现不同配方自动切换蜂群及更多恢复处理。用户希望中文说明、完整修改后统一交付，避免 ProjectRed。
