# V1 后台缓存完成后的恢复补丁

生产日志停在 `cache-working`，而缓存日志已经 `stopped` 且 `incomplete=false` 时，旧 V1 的 `resume` 会报“该阶段存在未确认操作，不能自动恢复”。这个补丁补上该阶段的核对，不替换整份控制器，也不修改、删除两个 journal。

先退出 UI，确保没有其他控制程序运行。在游戏 OC 电脑执行：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/cache_resume/patch_v1.lua /home/bec_patch_cache_resume.lua
lua /home/bec_patch_cache_resume.lua
lua /home/bec_ui.lua resume
```

安装时要求控制器有可识别的 V1 恢复入口，先做语法检查，再保留原脚本为 `/home/bec_auto.lua.before-cache-resume-1`（已有备份时递增编号）。已安装最初的恢复补丁时会原位升级，已是新版时跳过。文件替换失败会尝试还原。

恢复要求无待处理生产计划、pending或供液配置，生产与缓存申请全部完成、两边搬液数量完全确认、后台缓存已完成、真实库存达到缓存日志的本轮目标、实际子网无原液，并且节点暂停、纠缠装置已停机。实际节点允许空闲、立即暂停、蜂群等级不足、装配机离线或未供电；正在合成等状态仍拒绝恢复。旧 `lastState` 是历史显示记录，`expected/secured` 也可能保留上一轮生产数据，不把这些历史字段当作当前设备状态：已有新订单但确实暂停时，可归档旧生产日志，再让原服务按当前订单和真实库存检查、切蜂群及备料。不重放旧申请和搬液，实际子网还有原液或操作未完整确认时仍保留日志人工核对。

`test_resume.py` 使用 Lua 5.2 验证缓存完成恢复、已暂停新订单和蜂群不足的恢复、历史原液记录与实际库存的区别，以及未确认申请/搬液等拒绝情况；检查安装备份、失败还原、前两版补丁升级、幂等与日志不变。另运行实际 V1 控制器的模拟恢复和生产流程，确认新订单完成且没有重放历史申请/搬液。模拟验证不代表实际游戏硬件已验收。这个补丁只用于 V1，不改变 V2。
