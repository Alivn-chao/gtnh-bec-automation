# 配方运行期间的阶段换蜂修复

2026-10-17。对应旧版错误：`lib/bridge.lua:54: 组内配方蜂群等级变化，保持整组暂停`。

V2 的 controller 原本就有运行中调用 `switchNanites()` 的分支，但 bridge 在读取节点状态时将当前阶段等级与 cohort 开工时的 `entry.tier` 比较，导致正常阶段变化先被拒绝。

对照 V1 `reinstall/files/bec_auto.lua` 的 `serviceNaniteStage`、`reinstall/files/bec_nanites.lua` 的 `requiredFamily`、`choose`、`keeping`：阶段需求需要实时读取；同等级库存优先选择对应种类；有合适的低等级库存时可以在后续阶段换回。V1 最新实现还支持单节点不施加暂停红石的被动换蜂，本次没有将该策略直接用于 V2 共用蜂群仓的多节点组。

修复内容：

- 同配方的蜂群需求等级允许随进度变化，仍核对标准化流体需求、批量、完成状态和下一单接单权限。
- 共用蜂群仓采用未完成成员的最大实时等级；只有最高等级成员的种类需求一致时才传递对应种类偏好。开工快照不改写，因此旧暂停记录可继续核对恢复。
- 沿用 V1 对应种类优先的硬盘选择规则，并检测同等级阶段种类变化。
- 仍暂停整组节点、等待纠缠器停机后换盘。换盘过程中等级和明确的种类需求必须保持稳定；保留整盘数量守恒、IO 清空确认和未确认记录禁止重放。

## 更新已有 V2

按 Q 退出旧程序后，在 OpenOS shell 执行：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/bec-v2-stage-nanites-2026-10-17/reinstall_v2/update_dynamic_nanites.lua /home/bec_dynamic_update.lua
lua /home/bec_dynamic_update.lua
lua /home/bec_v2/main.lua web
```

点击“启动自动化”恢复。这次等级检查报错不需要清空总线或归档生产日志。更新器只替换 bridge/controller/nanites_cell 三个程序，先逐文件备份并读回验证，失败回滚；不调用机器，不更改绑定、配方、草稿或任何运行记录。若另外存在未完成的搬盘记录或未确认 AE 请求，仍会暂停核对。

## 验证

149 项 Python/Lua 测试（另包含 20 个原有核心模拟检查）、24 个网页 JS 场景通过。新增回归使用实际 V2 engine/bridge/controller/cell-IO 程序，旧 bridge 可重现报错；替换后不清空 journal，从同一暂停现场恢复，完成金 T3 → 超时空 T4 → 碳 T1 的同配方生产，归还 39,392 金蜂群和 19,612 超时空蜂群，两个 IO 清空；另检查同等级种类优先、错配方/批量和无效等级拒绝、更新器六处 rename 失败回滚及原记录保留。这是组件模拟，尚待真实游戏验证。
