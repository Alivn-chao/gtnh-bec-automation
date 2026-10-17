缓存提交时翻页和输入保留：已读取页面可立即浏览，保存与分页独立；见 [CACHE_BROWSE.md](CACHE_BROWSE.md)。

缓存设置提交慢、屏幕信息滞后：保存回执与机器读取解耦，分批刷新并复用控制器实际读数，小更新见 [DISPLAY_LATENCY.md](DISPLAY_LATENCY.md)。

缓存部分搬运返回引发保护暂停：实际回执记账修复，以及本次空间流体补96收尾工具，见 [CACHE_PARTIAL.md](CACHE_PARTIAL.md)。保留原日志，不重下AE申请。

重启后读取配方一直等idle：已修复旧批次占用设备组不退出的路径，小更新见 [IDLE_COHORT.md](IDLE_COHORT.md)。

蜂群检查优化：16节点同一轮组件读取292→100，保留整组核对；小更新见 [HIVE_INSPECTION.md](HIVE_INSPECTION.md)。

网页连接闪烁、缓存页无法滚动、换蜂后误暂停修复：见 [WEB_CONNECTION.md](WEB_CONNECTION.md)。已有缓存版使用 `update_connection.lua`，保留绑定与日志。

网页新增第三个页签「缓存管理」：默认库存目标、每种流体自定义、0停补与真实后台补库，沿用V1缓存工作器。安装及操作见 [CACHE_MANAGEMENT.md](CACHE_MANAGEMENT.md)。

网页顶部新增「样板处理」：只读预览、处理一次、停止与逐槽结果，操作及更新见 [WEB_PATTERNS.md](WEB_PATTERNS.md)。

无需手抄 UUID：地址框旁新增「从 OC 识别 / 选择」，同类设备可对比断开/接回分支后的新增组件。更新及操作见 [COMPONENT_PICKER.md](COMPONENT_PICKER.md)。

网页应用/启动反馈修复：见 [WEB_START.md](WEB_START.md)。应用前会显示当前设备组缺项清单，点击可跳转；OC 校验失败会显示在顶部。

2026-10-17 高速供液口已扩容至每组10个，模型/绑定/状态一致。已有网页版使用 [BULK10.md](BULK10.md) 的 `update_bulk10.lua` 一次升级，原地址和草稿保留。最新标签 `bec-v2-bulk10-2026-10-17`。

2026-10-17 网页交互修复：删除键和上下滚动需要客户端输入补丁；选择列表、地址清空与模型缩放用OC网页更新。保留已填草稿，不需要重装。完整步骤见 [WEB_INPUT.md](WEB_INPUT.md)。新标签 `bec-v2-web-input-2026-10-17`，已有V2优先只运行 `update_web.lua`。

# V2 OCHD 一体化预览 preview 5

本分支接续10月16日未完成检查点，已修正阶段计时、草稿保存并发和配方完成时的跨读取误暂停。支持从结构模型绑定、保存草稿、校验应用、启动/暂停及查看当前批次流程。代码和模拟通过，**GTNH实机验收仍待进行**；完整边界见 [OCHD_PROGRESS.md](OCHD_PROGRESS.md)。

需要 [OCHD alpha7](https://github.com/Alivn-chao/oc-hd-panel/releases/tag/v0.4.0-alpha7-html)：客户端同时使用匹配的JAR与网页运行时，服务器使用匹配JAR。此项目只安装OC脚本，不替换模组。多组先通过普通 setup 创建，网页切组编辑；未绑定的节点空位会跳过。

已有V2：先在原控制器按Q退出，待纠缠器停稳、两端ME IO无留盘，再运行（不覆盖配置、配方或运行日志）：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/bec-v2-ochd-preview-2026-10-16.1/reinstall_v2/update_reads.lua /home/bec_v2_update.lua
lua /home/bec_v2_update.lua
lua /home/bec_v2/main.lua web
```

空盘OpenOS完整安装用同一标签的 `reinstall_v2/install.lua`；已有 `/home/bec_v2` 时完整安装器拒绝覆盖。网页不会自动创建登记配方，仍需迁入有效V2配方记录或从原样板登记。V1不能运行V2更新器。

以下10月15日说明保留为稳定旧版的安装历史；其固定标签不会自动升级到本预览。预览已包含前10格/IO1与7、读取优化、批次接单关闭、HTML流程和容量保护；V2后台固定库存预缓存仍未迁入。

---

> 2026-10-16：已同步 V1 批次接单启停，见 [BATCH_STOP.md](BATCH_STOP.md)。

# BEC V2 从零安装与分享包

适用 GTNH 2.9.0 Beta 3、OpenComputers + OpenOS。这里的“空硬盘”指已安装 OpenOS、没有 V1/V2 文件的硬盘；完全未格式化的盘须先用 OpenOS 安装盘执行 `install`，重启取出安装盘。准备联网卡、`wget`、普通 OC 屏幕/键盘、足够内存和磁盘、组件容量。

本包包含 V2 主程序、1–16 节点分组、ME-IO自动换蜂配置、样板处理、普通屏幕仪表盘、OCHD 本地地址配置、可选 GitHub 故障报告和受限旧历史清理。无需 V1，也不需要再安装此前的绑定/报告补丁。发布页提供 `bec-v2-clean-install.zip`；离线把其中 `install.lua` 复制到游戏电脑执行，或把 `files` 内全部内容放到 `/home/bec_v2/`（不要多套一层files）。

## 1. 安装

在游戏OC终端执行：

```sh
wget -f https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-clean-2026-10-15.1/reinstall_v2/install.lua /home/bec_v2_install.lua
lua /home/bec_v2_install.lua
```

安装器自带所有程序，后续不逐文件下载。全部语法检查、写入、flush、回读成功后才把临时目录发布为 `/home/bec_v2`；写入/回读失败不发布。已有该目录时直接拒绝，避免误覆盖配置和运行现场。安装不扫描或控制机器、不搬料、不下单、不启动生产。旧 V1 文件不用删除，但同一设备的 V1 服务必须正常退出后才能使用 V2。

包内没有作者或其他玩家的配置、配方需求记录、运行日志和凭据；runtime 中历史默认地址由 bridge/样板包装入口使用配置替换，不应直接执行runtime文件。

## 2. 接线和首次绑定

每组是一个实际共享 BEC 网络：约束场、韦门、原液子网、纠缠器及蜂群共享；同组可有1–16节点，多台纠缠器。独立BEC网络分不同组。同组投相同配方，生产接口使用高级阻挡卡的智能阻挡模式。约束场始终开启。

- 原液：主网供液ME接口 → OC转运器 → 独立子网接收ME接口/流体存储 → 纠缠器进阶存储输入仓 → 约束场。不要用存储总线把主网全部原液直接暴露给子网。
- 每个节点：OC适配器读状态；红石I/O接立即暂停控制仓，15暂停、0放行。红石I/O不能代替状态适配器。同一红石地址+输出方向不能重复绑定。
- 普通物品：主网生产ME接口 → 物品子网缓冲 → 节点ME输入总线；成品经ME输出总线回主网。
- 样板：独立工坊ME接口，用于转换原加工样板副本，与生产接口分开。
- 存储盘换蜂：普通箱子/硬盘盒、OC转运器、两只12槽ME IO端口、各自红石I/O；常见方向下0箱子、南3装入、北2回收、两红石向下0。装入硬盘→收容网，回收收容网→硬盘，两端选工序完成后移到输出口。本包沿用已发布V2的全槽读取和输出7–12确认，尚未迁入V1后来“只扫前10/端口1与7”的性能补丁。
- 运行核心兼容旧双ME接口配置；新版OCHD配置页统一ME-IO，不需要换蜂时整套蜂群设备留空并手动放蜂。

先在机器已闲置/暂停、所有纠缠器已关闭且不活动时配置。方向统一0下、1上、2北、3南、4西、5东。

普通OC屏幕入口，不需要OCHD：

```sh
lua /home/bec_v2/main.lua scan
lua /home/bec_v2/main.lua setup
```

向导依次选择节点数量、设备组数量和各设备，支持设备序号或唯一地址前缀；新用户配方目录用默认 `/home/bec_v2/recipes`。不要使用说明截图里的其他存档地址。

OCHD可选入口：[下载1080p alpha4绑定版](https://github.com/Alivn-chao/oc-hd-panel/releases/tag/v0.3.2-alpha4-drafts)，客户端/服务器都替换旧JAR并重启。在OC接入一个OCHD主组件后：

```sh
lua /home/bec_v2/main.lua setup-hd
```

右键OCHD → 设置 → 设备地址绑定，支持Ctrl+V、Ctrl+A；“暂存草稿”允许空项、半截地址并保存到OC硬盘；“应用绑定”才完整校验。返回设置/关闭界面会尝试自动暂存，建议等待明确暂存回执再去查地址。方向直接选择上/下/南/北/东/西。绑定嵌在原有白色卡片、蓝色导航的OCHD页面中。保存等待成功回执，在OC键盘按Q退出配置服务。空配置默认一组，可填1–16节点；多个独立组先用普通setup创建，再用OCHD编辑。OCHD目前提供地址配置，生产仍使用普通OC仪表盘；保存不启动生产。

## 3. 登记配方和启动

```sh
lua /home/bec_v2/main.lua pause
lua /home/bec_v2/main.lua patterns preview
lua /home/bec_v2/main.lua patterns run
```

`pause`会操作已绑定机器：给节点暂停15、关闭纠缠器，约束场保持开启。等待纠缠器实际停止。将原加工样板副本放到工坊接口9个样板槽，再preview只读检查、run转换登记。转换后样板仍在工坊，手动移到生产接口。空硬盘没有旧配方需求记录，不能直接使用已去掉凝聚物流体、又没有记录的加工样板；请用原样板副本登记。不要把不明旧记录当作新数据。

```sh
lua /home/bec_v2/main.lua monitor
```

只读核对后按Q退出。确认全部节点暂停、纠缠器关闭且不活动，再启动：

```sh
lua /home/bec_v2/main.lua run
```

先测1节点/小订单，再测2台同配方并行，最后扩至16。↑↓选节点、P暂停整组、R核对恢复、A暂停全部、N库存翻页、Q暂停全部并退出。新增节点先完成批次并Q退出，再 `lua /home/bec_v2/main.lua add-nodes`。

## 4. 可选日志上传和磁盘容量

不配置GitHub也能生产，报告仅在本地排队且有容量上限。需要自动上传时：

```sh
lua /home/bec_v2/main.lua reports
```

填写自己可写、已初始化且有main分支的 `owner/repository`，再在OC本地掩码输入仅授权该仓库、Contents读写的fine-grained token。其他玩家应使用自己的仓库/token；不要共享凭据，也不要向无写权限的作者仓库配置。保存后正常启动V2，故障报告异步上传至 `diagnostics/v2/`，上传后回读一致才确认。已排队且绑定了目标的报告不会随凭据更换悄悄改投其他仓库。

本地已上传报告留最近3份、待上传完整报告最多5份；单报告最多48KiB，队列满保留计数及摘要。明确stopped/done且无未确认操作的自动历史每前缀留3份；当前/未完成/损坏记录、人工证据与配置配方备份不删除。GitHub端不删历史。凭据只在 `github-upload.dat`，不进入诊断和分发包。

## 版本与边界

生产核心固定来自V2 cell-io `e1f381885ed446d20fdfb21e310a176e36f19d7d`；报告来自 `274b79d` 并增加分享包自选仓库；OCHD配置来自 `67ac4cec`，改为V2目录内加载。仅新增setup-hd/reports入口，不迁入V1近期切蜂、快配方、预缓存或韦门提速修改；不能把本包当作那些提速已完成。V2后台固定库存预缓存尚未迁入。模拟、语法、安装失败和回读测试不等于GTNH实机验收。

## 已装10月15日完整V2包：仅更新绑定页

先Q退出配置服务；客户端/服务器替换OCHD 0.3.2-alpha4-drafts并重启。无需重装V2，也不删除已有数据：

```sh
wget -f https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@bec-v2-clean-2026-10-15.1/reinstall_v2/update_bindings.lua /home/bec_v2_update_bindings.lua
lua /home/bec_v2_update_bindings.lua
lua /home/bec_v2/main.lua setup-hd
```

此更新器仅备份替换绑定模块和配置页面，不写生产配置、配方或现场日志。草稿保存在 `/home/bec_v2/bindings.draft.dat`，与生效配置分开。

## 读取优化预览（2026-10-16）

当前本地源码包含减少整组重复读取的 preview 1，详见 [READ_OPTIMIZATION.md](READ_OPTIMIZATION.md)。原有 GitHub 发布标签保持原样；本次尚未游戏验收。已有 V2 可使用独立 `update_reads.lua`，不需要从空盘重装。

## 阶段切换提速 preview 2

针对换蜂前检查和下一配方韦门确认的延迟，已收窄硬盘箱到前10格、IO等待到1/7格，避免同轮重复换蜂检查，并精简三轮韦门确认中的重复组数据读取。仍全槽检查IO留盘，保留三轮过滤回读和供液前完整配方检查。更新器现为4文件并兼容preview1。使用和模拟数据见 [STAGE_LATENCY.md](STAGE_LATENCY.md)。尚未游戏验收。
