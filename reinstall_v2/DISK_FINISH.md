# 磁盘清理与配方完成时暂停超时

标签：`bec-v2-disk-finish-2026-10-18`。

用户现场：浏览补丁因“更新后需保留512KiB”未安装；根目录还有旧hive/display/cohort/cache_partial更新器。随后只读输出为`stage watching / pending false`、16节点全部idle。模拟重现旧控制器在换蜂暂停边界配方恰好完成后，只等待paused-immediate或nanite-tier-too-low，最终通用等待超时。

## 先释放空间

在Lua解释器按Ctrl+D回到`/home #`，网页运行时先按Q退出：

```sh
wget -f https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-disk-finish-2026-10-18/reinstall_v2/files/disk_cleanup.lua /home/bec_disk_cleanup.lua
lua /home/bec_disk_cleanup.lua run
```

约9KB的工具先检查程序和备份的完整内容签名，只清理与已发布程序完全对应的多余`.before-*-N`副本，每个已识别当前程序保留一份已验证回滚副本；还可清理白名单中已知完整内容的旧更新器。`bec_browse_update.lua`及本工具保留。未知修改、`.new/.failed`、当前程序、整个state/recipes、配置、报告和未知stage目录不清理。逐文件删除前重新核对内容及当前/保留备份，变化时停止；删除失败保留并报告。无collectgarbage依赖、不加载组件、不控制机器。默认不带run是只读预览。

## 安装完成边界修复

```sh
wget -f https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-disk-finish-2026-10-18/reinstall_v2/update_finish.lua /home/bec_finish_update.lua
lua /home/bec_finish_update.lua
```

约42KB，仅替换controller.lua；保留所有数据。两个暂停等待都能识别idle，但必须由既有`BEC_V2_COHORT_IDLE`读取整组并核对每个成员的完整消耗证明，才正常结束旧批次；缺证明、未完成AE请求等仍暂停。已完成时不再换蜂，不重新申请旧订单或搬料。新的暂停超时消息包含等待用途和最后状态。该修复不会直接改写用户的watching记录；重新启动时走原恢复核对和归档流程。

如果此前浏览更新还没装上，接着执行保留的下载包：

```sh
lua /home/bec_browse_update.lua
lua /home/bec_v2/main.lua web
```

每一步成功后再继续。清理完成后若空间依然不足，保留工具打印的剩余空间和失败原因；不要删除未确认记录腾空间。

测试：原发布版超时复现、新版完成后停止且交回调度、消耗缺证明仍保护；清理预览无删除/只删已知副本/保留一份/保留用户文件/未知版本及删除失败；更新签名、低空间、缺完成核对桥接和每次rename失败。模拟结果不等于Minecraft现场验收。
