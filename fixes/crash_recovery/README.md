# 崩溃后、备料和装盘前的受限恢复

文件安装到 OC 的 `/home/bec_recover.lua`。此工具只支持当前单设备组、实体蜂群总线已绑定、旧批次 interrupted、蜂群日志 loading 且尚未开始装盘的情况；其它情况拒绝恢复。

1. 在运行 BEC 的 OC 终端按 Q 正常退出。
2. 只读预览：`lua /home/bec_recover.lua preview`。
3. 检查通过后执行：`lua /home/bec_recover.lua apply`。
4. `lua /home/bec_v2/main.lua web`，在网页点击启动自动化。

脚本核对全部节点已暂停且关闭接单、当前未完成配方没有消耗、配方与旧批次一致、纠缠器已停、子网原液为空、双 IO 端口和实体蜂群总线为空、T4 蜂群数量与装盘前日志一致。未确认请求、部分搬运、活动配置或其它未完成生产日志均阻止恢复。

成功时在 `/home/bec_v2/diagnostics/crash-recovery-*.{proof,cohort,cell,production}.dat` 保存现场和旧记录，回读验证后解除旧批次阻塞。不会标记旧订单已完成，不重放搬运、不补下 AE 订单、不还原崩溃丢失的物品。检查失败请保留完整错误，不删除 journal 强行运行。

测试：`python fixes/crash_recovery/test_recovery.py`，需要仓库 `work/lua_runtime` 下的 Lua 5.2 Lupa。
