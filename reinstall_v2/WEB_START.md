# 网页应用与启动反馈

旧网页在正式配置尚未生成时禁用启动按钮；应用失败只显示在页面底部，容易看不到。新网页把状态与错误放到顶部，并在应用前列出当前设备组缺少或格式不正确的字段，点击条目跳转到模块输入框。此清单只检查填写内容，仍由 OC 校验在线设备、方法、方向和实际机器状态；其它设备组由 OC 校验。

必填：主网供液 ME 接口；每组约束场、原液子网 ME 接口、供液转运器、至少一台纠缠器，并分配节点。节点组件与暂停红石须成对填写，每个节点需要独立韦门或组公共韦门。自动换蜂三项地址要一起填写，或者全部留空。空节点自动跳过；额外纠缠器、高速供液口、样板工坊接口可留空。

先在 OC 按 Q 退出旧网页，再逐行执行：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/bec-v2-web-start-2026-10-17/reinstall_v2/update_web.lua /home/bec_web_update.lua
lua /home/bec_web_update.lua
lua /home/bec_v2/main.lua web
```

只更新网页，备份旧文件；不改地址、草稿、配方或运行记录，不启动机器。需要已安装十口绑定模块；若提示先运行 update_bulk10.lua，用本标签下同名更新器，随后重新打开网页。

124 项 Python/Lua 回归与原核心 20 场景、16 项 JS 场景及实际 CEF 原生点击、缺项清单跳转、失败提示和重试验证通过；尚未 Minecraft 现场验证。
