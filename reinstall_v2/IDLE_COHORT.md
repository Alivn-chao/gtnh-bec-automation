# 重启后读取配方一直等待 idle

用户截图：读取配方4分34秒，工作器日志持续等idle，而N04已经有订单、蜂群等级不足。模拟复现出一条相同死等路径：旧批次节点在重启前已完成，旧cohort仍working；恢复工作器只监控旧成员，物理节点全idle后沿用V1常驻等待，设备组占用一直不释放，新节点订单进不来。

V2的工作器是有限批次，应该在旧成员完成后结束。现在看到全idle，会重新读取全部成员的需求和消耗证明；全部完整才结束旧批次，由调度器处理新订单。缺少证明、配方/状态变化、未确认AE申请仍保持暂停，不猜测完成、不清日志。

## 已有V2更新

OC按Q退出旧网页并暂停，然后执行：

```sh
wget -f https://cdn.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-idle-cohort-2026-10-17/reinstall_v2/update_cohort.lua /home/bec_cohort_update.lua
lua /home/bec_cohort_update.lua
lua /home/bec_v2/main.lua web
```

下载约59KB，只替换bridge和controller两个程序文件，保留蜂群检查优化、地址、草稿、缓存配置、配方和所有当前/未知日志。仅支持已知V2蜂群阶段、缓存、heartbeat或蜂群检查版本；备份 `.before-cohort-fix-N`，四处rename故障逐点回滚，不调用机器组件，不依赖collectgarbage。安装不启动生产。

打开网页后点启动自动化，由程序核对日志。核对通过会输出“本批节点已完成，消耗核对通过；结束旧批次并交回设备组调度”。缺少完整消耗证明则保护暂停并明确报告，不会盲目放行。

模拟验证：旧代码复现idle死等；新版从原working cohort和watching journal恢复，结束旧批次并运行另一个节点新任务；无新任务时重新开放空闲节点接单；缺少消耗证明与未确认AE申请保持关闭，原申请日志不改。尚未在Minecraft机器上验证。
