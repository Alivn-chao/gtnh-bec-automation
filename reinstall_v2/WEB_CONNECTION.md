# 网页连接、缓存滚动与换蜂恢复修复

2026-10-17，基于 `bec-v2-cache-manager-2026-10-17`。

OCHD 在五秒无 publish 时将 OC 标记离线。16节点读取、绑定校验和缓存检查可能超过这个时间，导致连接闪烁以及已执行操作显示未确认。现在各次组件读取之间持续发布心跳，长读取明确显示上次机器快照；请求即时确认收到，实际结果通过独立 token 回传。离线不重放操作，恢复后可显示迟到的实际结果。

缓存页改为有明确高度的独立滚动区域，底部翻页固定可见。结构数据中重复空白行共享存储，模型和贴图逐值保持相同，页面包减至约231KiB。

换蜂后重新放行现在重置暂停过渡计时。V2多节点读取给予最多30秒状态恢复窗口，超过仍保护暂停；保留整组暂停、IO守恒、订单一致性与禁止重放未确认搬运的检查。

## 已安装缓存版的更新

先在 OC 按 Q 退出旧网页并暂停。删除以前下载的两个临时更新包，保留程序和记录：

```sh
rm /home/bec_cache_update.lua
rm /home/bec_dynamic_update.lua
wget -f https://cdn.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-web-heartbeat-2026-10-17/reinstall_v2/update_connection.lua /home/bec_connection_update.lua
lua /home/bec_connection_update.lua
lua /home/bec_v2/main.lua web
```

不存在的临时包会提示找不到文件，可继续下一条。更新器只接受已知缓存版或完全相同的新程序，替换9个程序文件，备份 `.before-connection-N`，失败回滚。完整校验自己的已加载临时下载包后释放它以腾空间；保留512KiB余量。不调用机器组件，不改配置、草稿、配方和当前或未知日志。不需要换客户端 JAR。

恢复生产使用网页启动按钮，由程序核对当前机器和原日志；不要清空收容网或删除 journal。缓存配置保留。

## 验证

- Lua 5.2 模拟实际16节点快照、36秒慢组件读取、五秒面板租约、接收回执、限流结果保留、队列边界和退出。
- 旧版复现运行中换蜂后 `paused-immediate` 错误；新版继续完成，持续异常超过窗口仍保护停止。
- 更新器17处 rename 故障逐点回滚；未知程序、磁盘不足和 flush 失败不覆盖配置与日志。
- 实际 CEF 原生滚轮、底部第8项输入和保存、翻页、请求接收与实际结果分离；未做 Minecraft 机器硬件验证。

构建先安装 `requirements-build.txt`，然后运行各 `build*.py`。依赖 `rjsmin==1.2.5`，离线构建也可预装至 `work/build_tools`。
