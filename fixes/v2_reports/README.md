# V2 GitHub 故障报告与本地历史保留

原位安装到已发布的 `bec-v2-cell-io-preview-2026-10-12`，不更换控制器、绑定、配方或运行日志。`patch_v1.lua` 内嵌报告模块和一次性凭据向导，备份并更新 engine/main，安装失败回滚四个文件。先正常退出V2，所有节点暂停15、全部纠缠器关闭并停止活动后安装。

```sh
lua /home/bec_patch_v2_reports.lua
lua /home/bec_v2/report_setup.lua
```

第二步在 OC 本地掩码输入 GitHub fine-grained token：只选 `Alivn-chao/gtnh-bec-automation`，Contents 为 Read and write。凭据只存 `/home/bec_v2/github-upload.dat`，不写入公开程序、配置导出或报告；不要把 token 发进聊天。已有凭据的再次更新会保留 `.previous`，若该备份已存在会要求本地核对，避免静默覆盖旧凭据。互联网卡或有效凭据缺失时，只排队不声称上传成功。

之后正常 `lua /home/bec_v2/main.lua run`。故障工作器退出并完成原暂停处理后，报告自动排队；顶层异常先执行原shutdown，再保存报告，下一次启动继续上传。报告包含错误、最近事件、同组节点最后已知任务/批次信息、相关生产/蜂群/cohort/generator记录；不是故障后的实时硬件全量扫描。只读取白名单，不读取凭据、完整config、配方或任意磁盘文件。文本长度有上限并遮蔽已配置token及常见GitHub token格式。

报告发送到本仓库 `diagnostics/v2/<电脑地址前缀>-<序号>-<时间>.txt`。先GET核对：不存在才PUT创建；201之后再GET回读完全一致才记uploaded。上传响应丢失/重启后先核对同一路径，不盲目重复创建、不覆盖不同内容。网络每次step只推进一小步，无sleep/event.pull，也不操作机器；超时或403等失败保留报告并60秒后重试。界面最近事件显示排队/失败/成功链接。网络适配器和Lua5.2模拟通过不等于实际游戏HTTPS验收。

容量策略：

- 本地已上传报告只留最近3份；GitHub上的报告不删除。
- 待上传完整报告最多5份，队列满时保留已有5份，新事件只累计次数和最近512字符摘要，明确提示队列满。每报告不超过48KiB，不无限堆积。
- 每个生产节点的 `production.journal.stopped-N`、`before-resume-N`，以及每组 `nanites-cell.journal.before-run-N`，仅清理内容明确为stopped/done且没有pending/plan、搬运全确认、申请全done的旧记录；每种前缀保留最新3份。
- 当前journal、`.previous`、未确认记录、损坏记录、人工恢复证据、配方、配置和程序备份不删除。不能为了容量把未确认操作当完成。
- 清理逐文件让出调度；删除前再次核对mtime，避免清理扫描期间被替换的记录。

本次不包含之前讨论的韦门/节点快照提速，也不迁移V1被动换蜂逻辑；这些是独立修改。

断电恢复：写报告前持久化writing.dat；报告文件已完整写入而index尚未更新时，重启会核对并收编，半写报告保留为incomplete并计入待上传上限。历史清理另外拒绝configOwned、naniteStage和pipeline尚在使用的记录。11项Lua5.2模拟通过。

OCHD本地地址绑定另见 https://github.com/Alivn-chao/oc-hd-panel/releases/tag/v0.3.1-alpha4-bindings ，基于用户提供的1080p alpha4，客户端/服务端均需更新。绑定与本报告安装器独立。
