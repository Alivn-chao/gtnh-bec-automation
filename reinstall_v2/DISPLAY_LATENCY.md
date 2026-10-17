# 网页保存和显示提速

标签：`bec-v2-display-latency-2026-10-18`。约50KB小更新，保留绑定、配方、缓存目标与所有运行/恢复记录，不安装新客户端。

先在OC按Q退出旧网页，再执行：

```sh
wget -f https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-display-latency-2026-10-18/reinstall_v2/update_display.lua /home/bec_display_update.lua
lua /home/bec_display_update.lua
lua /home/bec_v2/main.lua web
```

保存目标仍要完成配置备份、flush和读回验证，完成后即构造内存快照返回带token的操作结果，不再先扫整组机器。请求送达与保存成功仍是两件事；断线不重发操作。缓存流体清单复用，样板处理完成后失效，手动刷新也会重扫；外部手动改配方文件后请刷新。

心跳约每0.6秒从内存重建流程阶段和日志，替代长操作期间重复发送旧页面。显示硬件读数每循环最多读取一个getter，逐项更新；已有控制器实际读取结果通过pulse只旁观更新显示，1秒内相同显示getter跳过重复读取，10秒以上旧读数显示不可读。仅显示缓存，不供生产控制判断。缓存库存跟随控制器实读或显示轮询刷新，仍不是全部设备的同一时刻快照。

未取消生产/换蜂/搬液/放行前的实时核对，没有把显示缓存拿去通过安全检查。OC长回调、磁盘和低TPS仍可能造成等待，本改动不承诺游戏中固定秒数。

模拟验证覆盖16节点保存后完成快照0机器回调、单步显示最多1回调、硬件读数过期、忙时软件阶段持续更新、AE/控制返回值原样保留、缓存目录复用与失效、flush失败不报成功、更新10处rename失败恢复原文件。Minecraft实机效果待用户确认。
