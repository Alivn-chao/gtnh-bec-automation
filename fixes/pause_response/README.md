# 暂停与样板处理响应

暂停请求现在可在组件回调之间通过原有FIFO处理通道执行，仍不嵌套处理器、不覆盖未送达的回复。暂停会立即通知缓存上下文停止，取消休眠截止时间的等待；缓存扫描在只读检查点退出，已有请求或搬运仍按原日志收尾。

本轮对实际OC的lib/web_session.lua、lib/cache.lua、runtime/cache.lua做了精确片段修改、条件写入、备份和回读。旧网页会话在journal全部停止且没有待确认请求/搬盘时停止；机箱和MCP代理没有关机。更新后的网页保持暂停，不自动启动生产，便于处理样板。

验证：`python fixes/pause_response/test_pause_response.py`。覆盖扫描中暂停后释放样板入口、只读等待可取消、处理器不嵌套和旧回复保留。完整入口为 `python reinstall_v3/run_tests.py`。
