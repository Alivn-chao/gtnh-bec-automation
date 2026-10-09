# GTNH BEC 自动化

通过 OpenComputers 控制 BEC：同配方物理并行、自动补液、按配方切换纳米蜂群，以及多台纠缠器一起工作。中文配置向导按扫描结果绑定设备，支持 **1～16台传送节点**。

**第一次使用：[从零安装、下载文件、接线、查地址与扩容](docs/GETTING_STARTED.md)。**

**正在使用V1：[独立缓存脚本修正与替换说明](fixes/cache_bulk/README.md)** · [下载V1 bec_cache.lua](https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/cache_bulk/bec_cache.lua)。只更新缓存脚本，沿用现有界面和配置，无需安装V2。

## 下载与安装

对外安装版本为 **V2独立测试版**，目标环境是 GTNH 2.9.0 Beta 3 + OpenComputers/OpenOS。程序安装在 `/home/bec_v2/`，与旧单节点版本分开。

- [下载V2安装包](https://github.com/Alivn-chao/gtnh-bec-automation/releases/download/bec-v2-preview-2026-10-09.1/bec_v2_multinode.zip)
- [浏览V2源码与配置示例](https://github.com/Alivn-chao/gtnh-bec-automation/tree/bec-v2-preview-2026-10-09.1/experimental/bec_v2)
- [查看V2后续开发分支](https://github.com/Alivn-chao/gtnh-bec-automation/tree/codex/bec-v2-multinode/experimental/bec_v2)

游戏里的OC电脑有互联网卡与wget时，可直接安装：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/bec-v2-preview-2026-10-09.1/experimental/bec_v2/install.lua /home/bec_v2_install.lua
lua /home/bec_v2_install.lua
lua /home/bec_v2/main.lua scan
lua /home/bec_v2/main.lua setup
lua /home/bec_v2/main.lua pause
```

新用户还需登记原加工样板副本、配置自己的AE/BEC网络，再启动生产。完整步骤见 [入门指南](docs/GETTING_STARTED.md#5-配置登记配方和启动)。不必逐个修改源码中的地址。

## 当前功能

| 功能 | V2行为 |
| --- | --- |
| 多传送节点 | 同组接到相同配方的节点同时运行，汇总实际需求 |
| 共享纳米蜂群 | 切配方时暂停整组、切换一次，所有节点共用 |
| 多纠缠器 | 每组可配置多台，逐台启停和回读 |
| 自动补液 | 读取已登记配方、抵扣库存，缺原液时申请AE合成 |
| 凝聚物过滤 | 放行前配置麦克斯韦门并核对过滤 |
| 样板登记 | 专用工坊接口处理原加工样板副本并保存凝聚物需求 |
| 黑色仪表盘 | 节点状态、并行、蜂群、纠缠器与库存条；支持VRAM缓冲 |
| 新增节点 | `add-nodes`只追加新节点，保留原有设备绑定 |

V2已有模拟测试，仍需游戏逐步验收。建议先1台，再2台同配方，最后扩到16台。库存条目标在V2是参考线；固定目标后台预缓存、可编辑缓存页等旧版功能尚未全部迁入V2。

## 常用命令

```sh
lua /home/bec_v2/main.lua scan
lua /home/bec_v2/main.lua setup
lua /home/bec_v2/main.lua patterns preview
lua /home/bec_v2/main.lua patterns run
lua /home/bec_v2/main.lua monitor
lua /home/bec_v2/main.lua pause
lua /home/bec_v2/main.lua run
lua /home/bec_v2/main.lua add-nodes
```

`scan`与`monitor`只读；`setup`与`add-nodes`写配置；`patterns run`修改工坊样板并登记需求；`pause`初始化所有已绑定节点的暂停输出并关闭纠缠器；`run`控制机器、申请原液和搬料。生产界面Q暂停全部并退出。约束场保持开启，异常时保留日志与现场。

## 仓库目录

| 位置 | 用途 |
| --- | --- |
| `docs/GETTING_STARTED.md` | 新用户安装、接线、角色与地址、扩容、故障检查 |
| `experimental/bec_v2/`（V2分支或版本标签） | 独立测试版源码、配置示例、紧凑粘贴文件、测试 |
| 根目录旧Lua、旧说明与历史ZIP | 早期单节点接续快照，含作者历史地址；新用户使用V2安装包 |
| `evidence_*.png`、`HARDWARE.md` | 早期实际布局及运行记录，地址不适用于其他存档 |
| `HANDOFF.md`、`NEXT_SESSION.md`、`AGENTS.md` | 开发接续材料，不是新用户安装入口 |

历史程序曾真实跑通生产；不能据此把新多节点V2的模拟测试称为实机验收。不同整合包版本请以实际组件方法和设备行为为准。
