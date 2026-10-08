# GTNH BEC 自动化

2026-10-08 项目接续快照。环境为 GTNH 2.9.0 Beta 3、OpenComputers/OpenOS；游戏终端显示 Lua 5.3，代码使用 Lua 5.2 兼容语法。

**已完成一份原始屏蔽层（Primitive Shielding）的真实合成及成品回主网。尚未实现完整无人值守循环、缺料自动下单和蜂群自动切换。**

在另一台电脑的 Codex 中打开此仓库，先读 [HANDOFF.md](HANDOFF.md) 和 [HARDWARE.md](HARDWARE.md)。不要重新执行转换或修复；本次配方记录在游戏电脑中已经修复。

## 已验证

- OC 配置主网流体接口缓存，转运器精确搬运原液到独立子网；不使用外部储罐。
- 纠缠装置的进阶存储输入仓读取子网，原液转换为凝聚物后进入约束场。
- 传送节点的进阶存储输入总线读取子网物品，ME 输出总线将成品回收到主网。
- 最终生产样板接口已放转换后的样板；用户安装高级阻挡卡并启用智能阻挡模式。
- 一次 Primitive Shielding ×1 合成成功，两种凝聚物各消耗 288。

## 文件

| 文件 | 用途与状态 |
| --- | --- |
| `bec_live_status.lua` | 最新只读状态检查，用户已成功执行；无翻页 |
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

继续实现：按当前单子计算凝聚物缺口、主网缺料时请求 AE 合成、暂停等待库存后放行、不同配方自动切换蜂群、重复单及恢复处理。用户希望中文说明、分步实施、接线图，避免 ProjectRed。
