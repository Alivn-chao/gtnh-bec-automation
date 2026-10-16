# 网页输入与滚轮修复（2026-10-17）

本次有两个独立更新：客户端CEF运行时负责删除/光标焦点和页面滚轮；OC网页负责可见选择列表、清空按钮与模型缩放。不需要重装OC或重新填地址。

## 客户端（已安装OCHD alpha8 Chromium）

退出Minecraft，备份游戏目录下 `ochd-web-runtime/cef-host.jar`，下载并解压 [客户端输入补丁](https://github.com/Alivn-chao/oc-hd-panel/releases/download/v0.4.0-alpha8-input-fix1/ochd-input-fix1-client.zip) 到游戏目录，覆盖这一文件，然后重启。服务器和mod JAR不变。

若仍为alpha7 WebKit，本补丁不能直接用于该运行时；先按 [alpha8说明](https://github.com/Alivn-chao/oc-hd-panel/releases/tag/v0.4.0-alpha8-chromium) 升级匹配的客户端/服务器JAR和完整客户端运行时。不要同时留下两个OCHD JAR。

## OC网页（支持未完成地址绑定的草稿）

在OC按Q退出旧网页，然后执行：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/bec-v2-web-input-2026-10-17/reinstall_v2/update_web.lua /home/bec_web_update.lua
lua /home/bec_web_update.lua
lua /home/bec_v2/main.lua web
```

这个更新器只替换 `lib/web_page.html`，精确识别334125a与81b7724网页，备份/flush/回读/失败回滚；配置、半截地址草稿、配方和所有运行日志保持原样，不扫描或控制机器。未知自定义网页拒绝覆盖。空间不足也不会覆盖原网页。

## 操作

- 地址输入支持退格、Delete、Ctrl+A后删除；每个地址另有“清空”。点击输入框显示蓝色焦点和输入光标，选中文字有高亮。
- 所属组等选择框用网页内列表，可鼠标选择、上下方向键、Enter确认、Esc关闭。列表渲染在屏幕纹理中，不再依赖不可见的系统弹窗。
- 滚轮向下页面向下，向上页面向上，每格明显增大（实际CEF测试约150 CSS像素）。模型滚轮向上放大、向下缩小，一格约26%距离变化；Ctrl+滚轮仍由OCHD控制整页比例。
- 模型范围仍有限制，文本编辑和配置保存不会启动机器。

验证：116项Python/Lua模拟与8项JS队列/模型测试；实际CEF运行时验证删除、全选、光标焦点、清空、鼠标/键盘选择、上下滚动和缩放。游戏内视觉/硬件验收仍待用户确认。
