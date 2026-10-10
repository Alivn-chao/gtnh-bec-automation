# 通过 OC 互联网卡上传实际诊断文件

用于把游戏 OC 电脑的真实 V1 文件和组件读数传到分析者的电脑，避免只依赖截图或旧副本。上传一次后退出，不接收远程指令。兼容 OpenOS / Lua 5.2，不需要安装 V2。

## 游戏端怎么用

1. OC 电脑装互联网卡，服务器允许 HTTP/HTTPS。若原先能用 `wget` 下载 GitHub 文件，已有基础网络能力。
2. 分析者启动下文的接收端后，把生成的两条命令发给你。
3. 在 OC 的 `/home #` 命令行运行，例子中的完整地址必须换成分析者实际提供的地址：

```sh
wget -f https://临时域名/访问令牌/bootstrap.lua /home/bec_upload.lua
lua /home/bec_upload.lua
```

显示“上传完成”和会话编号后，分析者就能读取本地快照。以后再次运行第二条命令会生成一个新快照。临时隧道重启会换域名，需要重新下载上传脚本。

默认运行现在采用 `recent`：当前程序、配置、当前日志、上一份日志和每种日志最近两份编号备份；按文件修改时间选择，不上传原程序备份或配方目录。显式 `full` 才上传完整历史。V1 process_reset 补丁也会直接升级现有游戏上传器，保留私有端点和旧程序备份。

已经上传完整程序后，只更新当前组件、CPU、库存读数和缓存配置可运行 `lua /home/bec_upload.lua status`。这种方式不再传全部历史脚本和日志；分析者应将状态会话与先前完整会话结合读取。

蜂群改用 ME IO 端口搬存储盘时，重新下载最新 bootstrap 后运行 `lua /home/bec_upload.lua ioport`。该模式读取新转运器 `13070035-3a3f-4468-b896-1c084288fdc9` 的底0（硬盘盒）、北2（网络→硬盘）、南3（硬盘→网络）库存名称、槽数、每槽物品（每面最多128槽）；读取组件地址/方法、红石输出、机器状态和可用的存储元件工作台只读方法。另上传实际 `bec_nanites.lua`、`bec_nanites_io_test.lua`、蜂群 journal 及备份和蜂群配置，不上传全部配方、其他程序或主网 CPU/流体清单。若驱动提供 `storedItemCount` 和 `getAvailableItems` 可读盘内物品，否则仅槽位读数不能代表盘内数量；组件列表也不能自动确定红石端口的物理输出面。此模式不会移动硬盘或设置红石。

如果生产界面还在运行，先用它原本的 Q 正常退出到命令行；保持约束场开启，保留订单与日志。不需要重下单、手动开启节点或清空库存。上传程序本身不会启停机器，也不会修复生产状态。

## 具体会读什么

- `/home/bec_*.lua` 及带 `.lua` 的备份，排除上传工具自己。
- `/home/bec_*.journal*`，包括 `previous`、`before-resume`、`stopped` 等历史备份。
- `/home/bec_*.cfg`、`/home/bec_*.config`、`/home/bec_*.dat`。
- `/home/bec/recipes/*.dat`。
- OC 可见组件地址、方法清单；BEC 节点需求/消耗/并行/蜂群状态、约束场库存、闸门过滤、机器运行状态/传感器信息/坐标、转运器各面流体、红石输出、ME 网络流体和主网 CPU 任务。二合一接口的 OC 类型为 `fluid_interface`，同样读取。
- 两个现有蜂群子网的 ME 物品清单。这两个地址在 `upload.lua` 有明确注释；他人的配置需改成对应的蜂群子网地址。其余组件动态扫描。

只调用代码中列出的读取方法，方法标记为 false 仍视为存在。不调用机器启停、接口配置、流体/物品搬运或 AE 合成申请；不改写上述源文件。所有采样按顺序执行，机器运行中读数可能变化，不把它当同一瞬间的原子快照。单文件最多 512 KiB，最多 300 个文件，跳过的文件会写入上传报告。

## Windows 接收端怎么准备

需要 Python 3.9 以上和官方 `cloudflared.exe`。工具使用 Python 标准库，无额外 Python 包。优先下载 [Cloudflare 官方版本](https://github.com/cloudflare/cloudflared/releases)，并按发布页摘要核验文件。

在仓库根目录运行，按实际安装路径填写参数；**运行目录放在仓库外**：

```powershell
.\diagnostics\start.ps1 `
  -Python 'C:\路径\python.exe' `
  -Cloudflared 'D:\bec_diagnostics\runtime\cloudflared.exe' `
  -RuntimeDir 'D:\bec_diagnostics\runtime'
```

脚本后台启动仅监听 `127.0.0.1:8765` 的接收服务和 Cloudflare 临时 HTTPS 隧道，生成随机访问令牌，然后输出游戏端的两条命令。不需要在路由器做端口映射。检查公网地址的 `/health` 返回 `BEC diagnostic receiver ready` 后再交付命令。

快照保存在运行目录上一级的 `snapshots/<会话编号>/`。`manifest.json` 包含文件大小、SHA256 和是否完成；`snapshots/latest.json` 指向最近完成的会话。上传一半断开时，已有文件仍保留，完整性以 manifest 为准。上传的 Lua 和记录只是数据，接收端不会执行或反序列化它们，也不提供公网文件下载。

`runtime/receiver.json`、`bootstrap_url.txt` 和下载后的 `/home/bec_upload.lua` 含当前访问令牌。仅把通用源代码放进公开仓库；诊断快照和这些运行配置留在本机。接收服务设有文件大小、数量和会话上限。

关闭接收端，保留快照：

```powershell
.\diagnostics\stop.ps1 -RuntimeDir 'D:\bec_diagnostics\runtime'
```

电脑和这两个后台进程需保持运行。[Cloudflare 临时隧道说明](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)明确其域名在重启时改变，停止进程后链接失效；首次诊断适合此方式，长期固定入口可另配正式隧道。

## 故障处理

- 下载失败：确认接收电脑没有关机，重新检查 `/health` 和 `runtime/tunnel.stderr.log`；服务器网络可能无法访问该域名，需要换可达的接收地址。
- 显示“需要互联网卡”或“服务器禁用了…HTTP”：先处理 OC 硬件或服务器设置。
- HTTP 403/404：确认用了接收端最新输出的完整链接，而非 GitHub 上没有绑定地址的 `upload.lua`。
- 中断后重新运行会创建新会话，不会重放生产或搬运操作。分析者可读取未完成会话中已经收到的文件。

互联网卡以主动 HTTP 请求上传。[OpenComputers 互联网卡 API](https://ocdoc.cil.li/component:internet) 提供请求、连接状态、响应码、读取和关闭接口。

## 本地验证

```powershell
cd diagnostics
python -m unittest -v test_receiver.py
```

检查鉴权、禁止文件路径逃逸、大小限制、摘要和幂等确认、动态脚本绑定，以及 Lua 5.2 模拟中的只读调用和 HTTP 错误处理。Lua 模拟需要仓库既有 `work/lua_runtime` 下的 `lupa.lua52`，缺少时明确跳过该项。它们不代表游戏硬件已验证；以真实 OC 上传结果为准。
