# 在家里的 Codex 接着做

2026-10-11 IO诊断已收到完整f7e76e91149b45f7b42b976e8ae7b938，5文件/56173字节、SHA256全对、runtime无截断。新转运器南北两台IO各12槽空，底CompressedChest243槽前128采样，1..8空数字奇点、9有19612个T4 gregtech:gt.metaitem.03:4581；stack有storedItemCount/getAvailableItems，可直接读盘内数量。节点nanite-tier-too-low/需求T1/蜂群0/isWorkAllowed=false，暂停输出top15；两只新增RS各面0，北候选唯一另一个4bfbed4a-5d62-4311-9d34-5761103e76ce。用户确认两只IO控制RS都贴上方向下0。实际旧bee日志stage=filling,moved576,goal19612,owned41c9711c，无当前pending；previous含未确认64意图，均保留，不重放。新增独立bec_nanites_io_test.lua只支持本盘T4，preview只读/load默认9/return仅回收本脚本上次成功load同槽同数量，搬整盘2次，独立journal、未完成拒重放、上限拒超量、错误关闭两端IO红石、节点不启停。12Lua5.2模拟通过，IO镜像/接收端8模拟通过；游戏装入尚未执行。新增固定公开/nanites-io/test.lua供下载新文件，不替换旧bee模块。上传器ioport扩展收集新测试源码/journal。先南口装入验证，随后北口回收验证，再做完整自动换蜂；不恢复生产或宣称吞料已修。

2026-10-11 最新：用户已实际运行 sidefix 安装器，显示旧蜂群仓 T4/10432、备用同类9180，方向北2/南3/西4；试跑 ensure 显示目标19612/30720，但尚无完成证据。因64个一搬太慢，用户现改为数字奇点存储盘+两台ME IO端口，新转运器13070035-3a3f-4468-b896-1c084288fdc9，南3硬盘→收容网、北2收容网→硬盘、底0蜂群硬盘盒；南红石I/O4e31083a-e153-40e4-bf3f-e5ada363819d，北地址/两端输出面未知。图一“工序完成后移动至输出口”对应AE2 FullnessMode.HALF，数字盘不宜等装满，但输出槽不证明数量完整；源码为当前master非用户Beta3硬件验收。新增upload.lua ioport只读模式，读取新转运器0/2/3每槽、红石、组件方法和可用工作台读取方法，上传蜂群模块/journal备份/配置以确认旧试跑是否pending。新搬盘模块尚未实现，不运行旧接口模块，不重放未确认蜂群搬运，不恢复生产。保持30720上限；需确认盘内数量或限制策略，不能用高速轮询兜底超量。新版bootstrap由已有接收端动态提供，实际上传待用户执行。

2026-10-11 用户执行安装器wget时raw.githubusercontent.com连接超时，尚未执行安装。已在现有诊断接收端加入两个固定公开脚本入口/sidefix/install.lua与/sidefix/bec_nanites.lua，模块固定SHA256为a2c8c9a内容，安装器内部下载URL替换为同一临时公网地址，保持原暂停/校验/备份流程。7接收端测试通过，实际临时HTTPS下载安装器3583字节、模块11148字节均200且校验通过。仅重启自己启动的receiver，原cloudflared通道保留，runtime/state.json更新PID；没有触碰游戏或执行安装。用户已接管游戏操作，下一步用临时地址下载并运行安装器后看输出。

2026-10-10 用户授权离开期间操作游戏。已根据真实上传的转运器读数修正V1蜂群模块：北2备用ME接口、南3收容ME接口、西4是gt.blockmachines/3槽蜂群仓；检查、计数、搬运和预览统一2/3，30720上限不变。模块及16模拟场景已提交a2c8c9a到main。新增install_sidefix.lua固定该版本、校验下载、只读预览接口/库存、核对暂停状态后备份替换；9安装模拟场景通过，含错误下载/接口、备份失败、改名失败回退、重复安装。未调用蜂群ensure或生产恢复，未改journal。通过computer-use的sky能操作游戏菜单，但场景右键/移动输入未生效，退出原OC界面后无法重新打开屏幕，因此游戏里的模块尚未安装，不能声称硬件验收。临时F8交互绑定已恢复鼠标按键2，F11已恢复窗口模式，停留原地面对OC屏幕；需要重新打开OC命令行才能安装。当前实时错误仍是西面应为收容接口，节点暂停3/64且需求T1，UI缓存目标显示111000，与23:31上传144000不同，不能用旧配置覆盖。吞料根因、实际接口配置写入API及放行前新过滤校验仍待核对。

2026-10-10 23:31 快速状态上传完成：会话fc98f0999a6542468dc41345b2575def，3文件/175142字节，含bec_cache.config version1/target144000，runtime无截断。子网流体为空，主网molten.cosmicneutronium146464096，field cosmic144000。节点isWorkAllowed=false、idle、progress0/max0，仍保留hypogen1728/cosmic0消耗。field/generator/diode传感器都显示BEC Network20；同网络号不证明装配侧能穿过单向闸门取得所有流体，装配机尚无OC可见地址。门现过滤celestialtungsten/hypogen/phononmedium为事后状态，不能当故障时证据。主网22CPU中2个busy，上传器原先用type(getter)==function判断跳过了Java可调用对象的任务详情；已改直接pcall包装调用，只对busyCPU读取，增加可调用table模拟测试，后续重新下载版本会补详情。没有启停/搬料，也没有修改生产控制器。当前任务只读通道已实机验证，吞料根因仍未确认。

2026-10-10 23:20 实际诊断接收成功：会话901265679f0a4dda8c4c48beaf2f0808在 D:/workmain/bec_diagnostics/snapshots/，259文件/22配方/1047452字节，所有SHA256正确，未遗漏超大读数。真实当前node idle,isWorkAllowed=false,parallel0,consumed cosmic=0/hypogen=1728,T4/10432；field12种各144000、门过滤celestialtungsten/hypogen/phononmedium。before-resume-26保留旧required cosmic13824/hypogen1728，remaining cosmic13824/hypogen0，gateIntent cosmic/hypogen，stage cache-working。实际控制器watcher有“蜂群需求变化→暂停换蜂→验证旧filters→pause(0)→才校验新req”顺序风险，且连续放行靠0.1秒轮询不能保证在下一短配方开始前换门；两次吞料根因仍未证实，现库存/门过滤不是故障时的读数。暂未修改生产控制器。发现诊断第一版遗漏fluid_interface的网络/CPU及.config，已修正上传器、补sensor/coords/progress只读采样，并增加status模式快速补读；新下载后status即可，无需重传全部备份。数据留本地，不提交实际游戏文件。

2026-10-10 互联网卡诊断准备：新增 diagnostics/receiver.py、upload.lua、Windows 启停脚本及说明，6项本地测试（含Lua5.2只读模拟）通过，Cloudflare临时公网下载及POST上传/保存/完成确认通过。接收端和隧道后台运行，私有配置、最新下载地址及PID记录位于 D:/workmain/bec_diagnostics/runtime/；诊断快照在同级 snapshots/。此路径在仓库外，不提交令牌、实际游戏文件或上传数据。只收集V1真实Lua/日志所有备份/登记配方与组件读数，不远程启停或搬料。尚未收到游戏OC上传；现有self-test会话明确标记无游戏数据，不能当实机验收。下一步用户运行提供的wget和lua后，读取最新真实会话，优先检查实际bec_auto.lua及before-resume/stopped日志，再定位吞料原因。约束场保持开启，保留订单和日志。

用户提醒网络超过3种未请求凝聚物会立即失败。已加放行前同场field库存多余种类检查，>3保持暂停并显示类型，1..3日志提示减速。这只是保守防护，尚未实现实际BEC网络过滤/自动切过滤；需用户提供实际过滤部件界面/OC接入，不能把原液接口过滤当BEC过滤，也不能声称凝聚物多类型预缓存可无损全配方生产。参考节点getSlowdowns和BECFactoryNetwork路由判断，但已取快照的pipe/hatch未见过滤OC方法；不要猜API。当前单field检查不能覆盖别的约束场，更不能验证已配置路由过滤。下一步确认物理过滤机制。

2026-10-09 最新：后台缓存已在游戏填到玻璃/金属各144000，新订单实际并行5触发旧checkRecipe“未验证的配方需求”，保持暂停未搬本单。生产改按真实登记.dat的凝聚物需求/并行精确匹配，AE ACTIVE/PENDING按匹配产物及输出份量计数；相同需求多个候选产物保守合计。蜂群读取节点requiredTier校验，不自动切换。144/1000转换批量及超时通用化，保留无登记原始屏蔽层兼容；未知需求仍停止。53原生产、26缓存、7全服务、2登记需求/队列模拟通过，225行紧凑控制交付，仅需替换/home/bec_auto.lua后UI resume，保留订单/日志。新登记配方完整实机生产尚待验收；不声称已确认失败截图里的具体产物。

## 用户意图与当前成果

用户要 GTNH BEC 的样板转换、凝聚物精确补料、缺料自动合成下单、自动切换纳米蜂群。避免 ProjectRed；中文、一步一步指导，有接线图更好。

已实际完成 Primitive Shielding（原始屏蔽层）×1，从 AE 下发到 BEC 合成、成品回主网。两种原液通过 OC 转运器精确加入独立子网，进阶存储输入仓自动拉取，纠缠装置转换后约束场读到两种凝聚物各 288。随后 AE 下单、节点合成完成，无线终端已找到成品。

最新状态（evidence_final_status.png）：

```text
storage: 237a9cac-118a-4b74-8755-0d0b0ad216c0
getStoredCondensate: {}
getFieldStrength: 2000000000
node: b04787f9-5423-4b03-8549-c786d4ef38d0
getState: idle
getParallelRecipesInProgress: 0
getMinParallel / getMaxParallel: 1 / 1
getProvidedTier: {name="Transcendent",tier=4}
getAvailableNanites: 64
getRequiredTier: nil
getRequiredCondensate: nil
getConsumedCondensate: {entangled_transcendentmetal=288,entangled_chromaticglass=288}
main/sub interface caches: empty
```

getConsumedCondensate 在空闲时仍保留上一单的消耗记录，不能当新单需求。接口缓存为空不等于子网存储元件为空，自动补料应读取子网网络总库存。

## 已转换的配方记录

游戏电脑路径 `/home/bec/recipes/gregtech_gt_metaitem_03_32307_1.dat`。这份游戏文件未导出到本地，仓库不包含真实 .dat。

原始样板有 7 项输入，转换后保留 5 项普通物品，移除第 6、7 项凝聚物流体：

- `entangled_chromaticglass` 288
- `entangled_transcendentmetal` 288
- 成品 `gregtech:gt.metaitem.03`，damage=32307，size=1。

转换工坊接口槽 1 的样板副本已转换。转换后的样板已放最终生产样板接口。不要再转换或执行修复以取得状态。

真实记录此前被 `serialization.serialize(record,true)` 截断，OpenOS 的 pretty 输出默认限制行数，生成不可反序列化的文件。修复脚本已改 false，用户修复成功，之后备料和生产成功。

修复后记录大致包含 version=1、state="converted"、interface、slot=1、ordinaryInputs、outputs、convertedPattern、recovered=true、condensates。修复版不保证包含 original，后续程序不要强制依赖 original。

## 接下来先做什么

最新：用户已确认并行恢复可用，随后新40份订单被识别、每种需11520，主网glass原有864，AE申请10656报done后库存不足30秒停止（line298），未搬本轮料，日志craft-done。截图不能确定去向，不断言单位错误/材料丢失。新版申请记beforeStock/needed/observedStock；done且库存净增加后最多补两次实测差额，无增长停止详细数值；resume接收craft-done且无搬运/plan/pending/config、申请全部done、暂停停机、原订单req/remaining未变的日志，归档后按当前库存恢复。38模拟通过。本次补差额游戏尚未验收，交付新版替换后resume，不重下成品。

最新覆盖：整批版游戏已读取剩余10份、搬入两种各2592、放行。用户运行中把最大并行改为1000后，实际6并行、各1728需求，旧checkRecipe固定288触发异常（line59），截图显示已立即暂停。新版bec_auto.lua接受需求288×实际并行，批量目标改为 remaining + 288×(AE剩余份数-实际并行)，监控同样扣当前consumed，取消并行1/1硬编码。resume支持watching阶段完整搬运/申请全部done、无pending/config、接口空、红石15且纠缠装置停机后归档恢复；读取当前库存抵扣不重复搬运。34模拟通过，多并行2/6/1000、已消耗6份后恢复零搬运。用户应替换脚本后resume，保持当前订单和约束场，不删除日志；本次游戏恢复未验收。

最新覆盖：用户不接受逐份加备用补料（太慢），要求按订单所有流体整批准备。游戏截图已确认 AE 原液申请144到账并继续补料。bec_auto.lua 已改 getCpus cpu.activeItems + pendingItems 读取所有剩余原始屏蔽层数量，整批 req*N - 当前consumed，已有库存抵扣。两种整批搬入，15984 mB 分段，上限随数量扩大，然后一次转换并连续放行；追加订单补整批差额。30 个模拟场景通过（15一次备齐、运行中追加10、100分段），真实 CPU userdata 批量清单待游戏验收。用户旧版仍运行，应先 Q 正常退出，替换后 run，保留订单和日志，不用 resume。用户提供维基要求参考后续GUI，已读取页面及 Mainform.png，见 UI_REFERENCE.md；未要求立即制作GUI。仍保留原拓扑，不执行参考页面脚本。

2026-10-08 最新覆盖：用户要求缺原液自动向主网 AE 下单，并明确不用每步让他验证，相关实现和本地检查一次完成后交付。主网 getCraftables / getCraftable、两种原液唯一匹配、getStack 的流体字段已游戏确认。bec_auto.lua 已接入按缺口 mB 请求、空闲 CPU 等待、顺序请求、状态跟踪、库存到账后继续补料；请求前持久化，失败/不确定/Q 在途保留日志禁止重复下单。26 个模拟场景通过，真实 request 尚未验收。最新游戏失败是主网 molten.chromaticglass 不足，尚未搬料；替换脚本后用 resume 保留旧日志恢复，AE 成品订单保留，不重新下单。resume 仅无配置/搬运/申请的 starting/waiting/waiting-stock。详见 AUTO.md。不要重做配方转换或已验证硬件探查。

最新澄清覆盖固定批量方案：用户要任意下单数量适用，常驻自动处理，不要启动前填写总数。已创建 bec_auto.lua / AUTO.md，14 个 Lua 5.2 模拟场景通过；下一步游戏复制新文件，preview，再 run，无数量参数。限制为原始屏蔽层已验证需求、tier 4 / 64、并行 1 / 1。按实时尚需量加一份备用（两种各 288）维持场内库存，初次空库存补各 576；备用不足则暂停补差额，不依赖捕捉 idle 数单。按 Q 正常停止并保留备用；日志独立，正常停止日志归档后可再运行，部分搬运或异常退出阻止盲目重跑。尚未游戏验收，不要把常驻版写成已成功。

此前为 ×5、×10 合计 15 创建了 bec_auto_batch.lua / AUTO_BATCH.md，15 个批量模拟场景通过，但用户不接受预先填写总量。此固定总量方案已被常驻方案替代，保留文件作参考，不引导用户继续用 batch15 验收。

2026-10-08 本轮真实游戏验证完成：控制仓设为立即暂停，先用拉杆验证，再通过 OC P2P 接远端红石 I/O。远端地址前缀 `266f65b5`，位于控制仓正下方，向上输出 15 暂停、0 放行。必须指定远端组件，不能使用默认 component.redstone；另一个 `152e823e` 前缀组件不是本次目标。

用户起初忘记连接 OC P2P，远端组件不可见，误控制另一个组件后有一单因缺凝聚物失败。连通 P2P 后，游戏里的备料程序真实搬运两种原液各 288，稳定检查通过；用户开启纠缠装置后约束场两种库存各 288。新单呈 paused-immediate、并行 1、需求各 288、消耗为空；远端输出改 0 后呈 crafting，两种各消耗 288；输出恢复 15，最终 idle、并行 0、需求 nil、库存空，用户明确确认成品到账。

当前停止点：远端向上输出 15，节点空闲，约束场保持开启。纠缠装置 `c1ae3f7c` 物理对应和 OC setWorkAllowed(true/false) 已真实验证，当前关闭。bec_auto_once.lua 默认只读 preview，显式 run 后等待并处理一单，通过当前节点需求计算补液，停止纠缠装置搬液、开启转换、库存齐备放行、完成恢复暂停。23 个 Lua 5.2 模拟场景通过，修正版现已在游戏中自动完成原始屏蔽层 ×1，用户确认“下单完成了”，终端截图 evidence_auto_once.png。

首次自动运行在等待阶段遇到 assembler-offline，未搬液，日志 {stage="starting",version=1,transfers={}}；修正状态等待后用 resume 保留旧日志到 .before-resume-1，等待观测阵列恢复再成功完成。最新游戏日志预计 stage=done（尚未导出），不能直接 run/resume 再次运行，也不要直接删除日志。下一步扩展已完成日志的安全归档、连续单循环，再接 AE 缺料下单。连续自动循环、AE 缺料下单和蜂群切换仍未实现。

原因：查到的 Beta 参考节点源码会在启动普通物品配方后设置 requiredCondensate。它不会自动因缺凝聚物而等待，会继续进度，直到结束检查缺料并失败。已有阻挡卡不能替代 OC 的凝聚物库存等待逻辑。

建议验证顺序：

1. 已完成控制仓立即暂停及远端 OC 暂停/放行验证，不必重复损耗材料验收。
2. 已验证纠缠装置新地址 c1ae3f7c 及 setWorkAllowed 启停；不要继续使用旧 gt_machine 地址。
3. 导出游戏里现有 `bec_prepare.lua` 和有效 .dat，或据已验证规则重建并测试。见 bec_prepare_MISSING.md。
4. 已真实验证自动读节点需求、库存并精确补差额。当前只支持两个映射；不要猜其它凝聚物转换比例。
5. 已真实验证库存齐备解除暂停、完成恢复待机暂停。接下来处理成功日志归档、连续单、取消、重启、部分搬运；不要把单次成功当作这些场景均已硬件验证。
6. 再加入主网缺料 AE 合成请求，先验证流体 request 的单位、craftable 对象调用方式和完成状态，不要把 request(1) 未经验证解释成 1 mB 或 1 桶。
7. 最后扩展配方、蜂群切换和多并行。

如果现有顶部物品缓冲已经有适合 OC 的放行方式，也可在核对部件/API后选用；不要为假定的方案拆除已成功结构。

## 曾踩过的坑

- 流体接口配置是 0 起，转运器槽是 1 起；错误索引导致 index out of bounds。
- 错认生产接口为供液接口，曾等缓存超时；当前正确地址在 HARDWARE.md。
- 主网缓存可能一次拉入 16000，而非指定 144；转运器的实际精确搬运和子网数量才决定转换总量。
- 主网原液有多少不可控，不允许进阶输入仓直接读主网或存储总线桥接。
- 方法表值 false 是非 direct 方法存在，不能当方法缺失。
- 写文件不要断言 close() 必须 true；OpenOS 可返回 nil。显式 flush、回读一致性、可反序列化、保留备份。
- 两个 gt_machine 名称都不是机器专有名称，自动开关地址还没确认。
- `bec_prepare.lua` 本地零字节；游戏里曾成功运行，二者不是同一份文件。

## 证据与源码适用范围

真实游戏截图优先于当前 master 文档。参考 GT5 源码快照 commit `081055b6c8a7bb5896fec8784daa524daa51b06d`，不等于已经确认每个文件都是用户 Beta 3 对应版本。

- [BEC 节点源码](https://github.com/GTNewHorizons/GT5-Unofficial/blob/081055b6c8a7bb5896fec8784daa524daa51b06d/src/main/java/tectech/thing/metaTileEntity/multi/bec/MTEBECIONode.java)
- [凝聚物定义](https://github.com/GTNewHorizons/GT5-Unofficial/blob/081055b6c8a7bb5896fec8784daa524daa51b06d/src/main/java/gregtech/api/enums/CondensateType.java)
- [AE2FC 流体接口实现](https://github.com/GTNewHorizons/AE2FluidCraft-Rework/blob/master/src/main/java/com/glodblock/github/util/DualityFluidInterface.java)
- [OpenOS 序列化说明](https://ocdoc.cil.li/api:serialization)
- [转运器 API](https://ocdoc.cil.li/component:transposer)
- [用户参考磁物质自动化教程](https://gtnh.huijiwiki.com/wiki/磁物质自动化)：此前完整网页被安全验证阻挡，只有索引代码片段读到，不能声称通读。

## 给家里 Codex 的启动提示

> 请先读 AGENTS.md、HANDOFF.md、HARDWARE.md 和 bec_prepare_MISSING.md，接续我的 GTNH BEC 自动化。独立子网精确补液、控制仓立即暂停、OC P2P 远端红石 I/O 向上 15 暂停/0 放行以及成品到账已真实验证。下一步核对纠缠装置 OC 控制后实现自动补料，再加缺料 AE 下单和蜂群切换。不要重复转换、修复或拆掉已有成功接线。用户会手动操作游戏并发截图。

## 2026-10-08 合成中收料更新

样板实测7槽watch成功（Primitive Waveguide/Energy Conduit/Electrogravitic Valve、Rough Sensor Array/Field Manipulator/Wave Focuser/Resonance Chamber），去重扫描成功并退出，用户确认可以再答“好的”授权下一步。已做一次性登记配方预缓存bec_cache.lua（紧凑bec_cache_paste.lua121行），build_cache.py复用主控制收料函数，cache_main.lua.inc为尾部入口。默认份数1，可指定10/任意正整数；同种流体按配方最大需求缓存，不累计所有配方。读真实游戏.dat，未知映射停止，3支持类型玻璃144/金属144/DSS1000，DSS原液从2候选名主网真实库存/可合成对象唯一解析，尚待游戏确认。生产与缓存互斥，需要原生产正常Q停机。缓存独立journal，无错误自动恢复，先preview10再run10，完成回UIrun。正常控制器更新保留已知额外场内凝聚物，并将收料批量通用化；bec_auto_paste197行、UI无需换。14缓存、51生产、9UI模拟通过。当前7新登记配方需求未从游戏导出，本机没有真实.dat；preview将实际读取并显示，不声称已确认每个目标。

最新用户截图restock正常完成39并行生产，UIidle当前并行0，蜂群423；每种凝聚物剩288，子网原液0，消耗记录保留11232而当前需求nil，这属于旧消耗记录，不可在idle抵扣下一轮。用户“正常了，下一个环节”。先做样板自动处理，新增bec_patterns.lua和PATTERNS.md：已验证工作接口9槽，自动保存需求/去除尾部entangled输入，run一次、watch监听新副本、preview只读；重复跳过或复用已登记原副本，冲突/未完成记录不覆盖，持久化备份、失败仅还原未被编辑的原输入前缀。不改生产接口，不声称通用生产已完成。16个模式模拟通过，待游戏多槽验收。用户蜂群备用库/回收/输入的OC接线尚未搭建，自动换料暂缓；预缓存尚未开始。

收到bec_resume_check真实输出：39并行、req每种11232、consumed={}，CPU26activeItems屏蔽层40，queued40，sub/field={}，尚需各11520；oldstageconverting,batch40,oldreq/remaining288each,target11520each。不能声称已消耗或AE已完成，也未查明流体丢失原因。新增显式restock而非继续放宽resume：旧操作全部已确认/请求done、暂停停机/interfacesempty后可接受physical<currenttarget，归档旧日志后按当前实际缺口重新备料。主网玻璃4752->申请6768，金属3301448足够只搬11520，无重复未确认操作。50个控制器和9个UI模拟通过。交付bec_auto_paste.lua195行、bec_ui.lua159行，替换两文件后lua /home/bec_ui.lua restock，保留AE订单。UI新增当前节点消耗/需求显示。用户其他三项功能和硬件接线仍暂缓。

最新截图恢复仍失败：已显示“实际并行/消耗已变化”，之后inventory mismatch molten.transcendentmetal 子网0+凝聚物0，目标被GUI截断。不能继续猜测已消耗，尚未取得getConsumedCondensate与AE ACTIVE/PENDING的真实数值。新增bec_resume_check.lua只读一次输出并行、需求/消耗、各CPU原始屏蔽层条目、queued合计、raw/field及旧journal目标。用户先Q退出错误界面，再新建运行此小脚本并提供输出；不要再改恢复策略或补料，直到看清需求/消耗/队列差异。

最新UI已实际显示错误且保留屏幕：日志阶段converting/40份，当前39并行、tier4蜂群214，主网玻璃4752、子网原液0、凝聚物0，报转换中订单已变化。当前消耗记录未在截图显示，不能断言已消耗；新恢复分支将以实际getConsumedCondensate及AE剩余队列扣除消耗核对physical==liveTarget，仅目标未增加、旧batchCount齐全才允许。46个模拟通过。交付只替换bec_auto.lua（bec_auto_paste.lua194行），保留UI和日志，Q退出错误界面后备份脚本、编辑粘贴、lua /home/bec_ui.lua resume。若仍有库存不符则需真实状态核对，不盲目申请。

最新用户：样板自动处理、切配方蜂群切换、已登记流体预缓存均为后续需求；实物蜂群输入/备用/回收都没接，明确“这个先等会，你先看图片上的问题”。当前重点仅UI启动run拒绝非正常日志。已加waiting带已确认历史记录的resume，UI loadfile显式_ENV保证打印捕获；43个控制器、8个UI模拟通过。交付两个更新文件（bec_auto_paste.lua 192行、bec_ui.lua 157行），替换后lua /home/bec_ui.lua resume。不要要求用户现在跑扩展probe，不开始自动预缓存。

最新用户截图确认resume成功：每种凝聚物11520、40份整批放行、最终idle等待下一单。用户表示能正常运行并进入下一步。已按此前可视化参考制作bec_ui.lua（不到257行），以loadfile调用原/home/bec_auto.lua，拦截print和事件刷新显示，不独立控制机器；Q/左下触摸交原控制器停机，R刷新，monitor只读。6个界面模拟通过，尚待游戏视觉/触摸验收。安装先Q正常停止当前服务，新增/home/bec_ui.lua后lua /home/bec_ui.lua run，保留稳定控制器和日志。详见UI.md。

后续截图：暂停、纠缠装置关闭，场内玻璃576/金属9792；resume报不支持恢复阶段。新增converting恢复：严格检查订单未变、无未确认操作、停机、每种sub原液+场内凝聚物=old.target。精确守恒才归档并抵扣继续转换，无请求/搬运重复。42个模拟通过，紧凑版重新生成仍不足200行；实际旧日志阶段未经cat确认，预期converting，否则仍安全拒绝并需读取日志。

最新截图：两种原液各11520已搬入子网，用户增加蜂群导致旧tier4/恰64检查在转换前退出，日志应为stream-prepared。已放开同级tier4数量>=64，增加prepared恢复检查并抵扣已有库存。38个模拟通过。用户粘贴限制257行，bec_auto_paste.lua为不足200行的完整等价副本，build_paste.py生成它及250行分段。下一步用户复制紧凑版到/home/bec_auto.lua并resume，不删日志或重复AE订单。

随后游戏 resume 在 assembler-offline 时于 current() 立即暂停检查退出，尚未归档旧日志或搬料。已修正：仅恢复订单核对允许红石15下的离线/缺电/蜂群等级不足状态，仍核对旧需求；serve继续等待机器就绪，实际备料仍要求 paused-immediate。新增3个恢复等待模拟，当前33个通过，尚待游戏复测。

用户确认彩色玻璃输出被主网其他设备消耗，拒绝外部专用输出缓存，授权合成进程中搬入独立子网。bec_auto.lua 已改为保持供液配置、每0.1秒尝试收料，达到整批目标立即清配置；两种原液收齐才转换和放行。旧craft-done恢复不再要求主网库存净增，仍须申请全部done且订单未变。30个库存驱动模拟通过，包含分批到货时提前收料；新版尚待游戏测试。test_auto.py 为当前测试入口，test_stream.py 实现模拟。保留现有40份AE订单及日志，替换全文后resume；不要另下40份。主网竞争没有绝对排他保证，持续收料减少暴露时间。

2026-10-09：用户缓存preview10报entangled_infinity未登记；尚无搬料。补齐无尽molten.infinity/144，并更新两份生成脚本。提供bec_fix_infinity.lua小补丁自动校验、逐份备份、写入回读两游戏文件，不碰journal。17缓存/52生产模拟通过，小补丁在两紧凑旧版上执行及重复执行通过。无尽真实转换仍待游戏确认。

2026-10-09：用户真实截图preview及run10完成，8登记配方四种流体含无尽、DSS均跑通。用户要求统一库存数值，并明确在可视化UI可编辑配置。新增bec_cache_ui.lua：E数字编辑/Enter保存、Esc取消、P预览/B一轮补缓存，/home/bec_cache.config备份回读；默认144000可改。生产UI新增C/底部触摸入口，正常Q停生产后切缓存UI。缓存新增preview-stock/run-stock N固定mB目标（原份数模式保持），只补已登记涉及类型，按批向上取整，余库存保留。交付缓存脚本125行/缓存UI约150行/生产UI约170行，主控制不需再换。21缓存、6缓存UI、10生产UI模拟通过；后台自动维持尚未接入。

2026-10-09：用户点击缓存设置切屏后闪回。定位缓存UI底栏整行误映射Q，切屏入口坐标再次touch立即退出；新增入口坐标重复touch后仍能E保存/预览及右侧刷新不退出模拟，旧版复现失败。修正仅左侧2..25为Q、右侧刷新、中央忽略。8缓存UI场景通过。仅替换bec_cache_ui.lua（136行），游戏真实复测待用户；其他脚本不需要换。

2026-10-09：用户授权UI按键处理样板。更新bec_ui.lua新增S/触摸h-2按钮，同步调用现有/home/bec_patterns.lua run扫描9槽，仅工作接口，不切屏不退出原控制器；结果捕获日志，失败留日志/不终止生产；1秒去重，monitor拒绝修改。12UI/16样板模拟通过。仅替换生产UI，新文件约190行，既有bec_patterns.lua不需换。实际游戏按键验收待用户。

2026-10-09：新样板新流体需求用户举例UMV部件装配线。读取BECRecipes/MaterialsInit源码（work忽略快照）：Space/SpaceTime/DSS，空间材料名spatialFluid非space。支持19已知映射和1000批量四类型，缓存唯一解析真实主网候选名，无主网库存/样板且场不足时精确报告，不盲下单。动态缓存UI5秒读取.dat+场已有列表，8行/页N翻页；C/S既有生产入口保留。高级流体转换等待修正为总批数*180秒上界。交付主控制200行/缓存132左右/缓存UI168左右，更新这3文件，其他不换。26缓存/10缓存UI/53生产/12生产UI模拟通过；本次只扩展登记缓存，通用UMV生产及蜂群切换未完成。

2026-10-09：用户明确常规UI自动补缓存、配置UI按Q仅返回常规UI不中断补库。实现生产serve idleCache读取配置/默认144000；工作段按最低库存选择一种最多16000mB，当前段完成后优先订单。cacheworker新增background-stock允许生产cache-working持久阶段和节点红石阻塞；单协程互斥，正常Q留下已确认raw段可再完成，未确认AE请求/transfer拒绝盲重复。UI改为工作协程+前台事件循环，C内嵌配置而非停机切文件；配置Q消耗并回主UI，主UIQ真正停。E/Enter保存/B启用默认，P只读；独立cacheUI启动默认转统一service并打开缓存视图，standalone用于旧模拟。7全链条紧凑交付源/53生产/26缓存/12UI/10缓存UI模拟通过。交付四文件均小于257行，启动run。后台游戏验收待用户；未放宽通用UMV生产或蜂群切换。
