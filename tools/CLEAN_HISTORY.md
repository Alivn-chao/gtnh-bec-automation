# 清理游戏电脑的 BEC 运行历史

2026-10-14 用户截图 T3 4 MB 硬盘已用 4193927/4194304 字节，仅余 377 字节；蜂群模块写日志报 not enough space，目录有数百份 cache.stopped、auto.before-resume、nanites_io.before-run 历史。磁盘满与 ME IO 设置问题不同，当前换蜂记录或 `.previous` 可能是恢复证据，不能用删除当前 journal 的方式腾空间。

先 Q 退出 UI。截图中明确存在 `/home/bec_auto.lua.before-overlap-2`，它是旧程序回滚副本，可先精确删除这一份，为下载清理脚本腾空间：

```sh
rm /home/bec_auto.lua.before-overlap-2
```

`clean_history.lua` 下载到 `/home/bec_clean.lua` 后运行 `lua /home/bec_clean.lua`。默认清理，`lua /home/bec_clean.lua check` 只显示将释放的文件数/字节。

脚本要求控制器已停（节点暂停输出15、GEN不允许工作），不操作机器，只扫描 `/home` 顶层四类精确带数字后缀的运行历史，每类保留最近三份：

- `bec_cache.journal.stopped-N`
- `bec_auto.journal.stopped-N`
- `bec_auto.journal.before-resume-N`
- `bec_nanites_io.journal.before-run-N`

按 `filesystem.lastModified` 降序保留，支持旧程序删除后重用较小编号的情况；时间相同时按编号降序。无修改时间的旧文件按编号保留。不会删除目录或递归清理。

当前程序、所有当前 journal 及 `.previous`、配置、配方、初始化诊断、pending 搬运证据、reset/initialize/restart 专用备份均不参与清理。其它程序版本、旧补丁或未知命名文件也不猜测删除。脚本本身不写文件或备份，因此在释放空间前无需额外日志存储。

清理后显示删除文件数、释放字节与实际剩余空间；当前 IO 写入失败是否损坏记录，需要再看 `/home/bec_nanites_io.journal`，不能仅凭空间恢复就宣布换蜂已恢复。先保留现场和 `.previous`。

六个 Lua 5.2 模拟测试覆盖精确白名单、当前与恢复证据保留、四组各200份只留3、重用低编号按时间保留、只读、不在运行中清理、不递归/不删除相似文件名、重复清理不再删除。尚未用户游戏实测。
