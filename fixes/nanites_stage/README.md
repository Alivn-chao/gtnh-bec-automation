# V1 运行中按阶段优选蜂群

需求阶段变化时，优先使用硬盘盒里对应类型、对应等级且合计至少64个的蜂群；没有对应类型时，选择同等级兼容类型，再选择更高等级。现有蜂群比备用选择更合适时保留现有蜂群。比如仓内T4、需求T1碳，盒里有碳盘时换碳；随后需求T2银，有银盘时换银；银盘没有而T4仍兼容时继续使用T4。数量仍由放盘决定，不强制30720搬运限制。

`fixes/nanites_io/bec_nanites.lua` 新增只读 `needsSwitch()`，选择时优先精确类型。同等级兼容蜂群没有等级惩罚；优选仍按用户要求选择对应类型。库存不足64个不会优先选中。已有蜂群兼容而没有更合适库存时不搬盘、不回收。同一阶段每2秒检查库存；阶段等级或类型变化时立即检查。此处“立即”指控制器下一次轮询，不能保证无延迟切换，也不预切换 `Next Nanite`。

阶段协调器同时接入顺序生产 watcher 的 tick 和 overlap 的 productionGuard，后者先换蜂再判断等级是否覆盖。换蜂时保持节点暂停15、关闭纠缠装置并等待停稳，核对归一化配方、实际需求、消耗记录、阶段类型和已有门过滤。整盘回收/装入仍使用已有南3/北2/底0布局和独立IO日志。完成后恢复本脚本此前的暂停输出及纠缠装置允许工作状态；材料是否够由原生产守卫继续判断。不同配方交回原配方/门控制，不使用旧过滤放行新配方。

AE订单和已确认供液申请不取消、不重下，生产进度不重置。换蜂部分成功或结果不明时保留盘、蜂群IO日志及生产日志中的 `naniteStage`，保持暂停，不自动重放。未确认的阶段换蜂记录阻止自动恢复，必须先核对现场。Q在停机等待中会退出并保持暂停，Q在IO搬运中遵循原模块的保留现场规则。

## 安装

只适用于已接入自动蜂群模块、已安装生产并行V3的游戏 `/home/bec_auto.lua`。仓库根部历史控制器不代表游戏里的完整版本，不要用它覆盖游戏文件。本补丁不适用于实验版16节点V2。

先在面板按Q正常退出，等纠缠装置停稳。依次安装新版蜂群模块及控制器阶段补丁：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/nanites_io/install.lua /home/bec_install_io.lua
lua /home/bec_install_io.lua
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/nanites_stage/patch_v1.lua /home/bec_patch_nanite_stage.lua
lua /home/bec_patch_nanite_stage.lua
lua /home/bec_ui.lua resume
```

raw无法连接时可替换URL前缀为 `https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@main/`。模块安装器内部仍请求raw并核对固定长度/校验值。不能用未经校验的下载替换游戏模块。

两份安装器各自备份原文件，控制器备份名 `.before-nanite-stage-N`。配置和原订单日志保留。重复安装阶段补丁不重复写。先升级蜂群模块；缺少 `needsSwitch()` 或 V3 时控制器补丁拒绝安装。

## 验证

Lua5.2模拟直接执行实际蜂群模块和阶段协调器，覆盖T4→碳T1→银T2、同等级对应类型优先、兼容回退、少于64个的候选、运行中新库存、配方变化、GEN停稳等待、部分搬运不重放、恢复原暂停输出、Q等待退出，以及安装/编译/备份/幂等。

模拟不等于游戏验收。先在盒里放碳、银和至少一张可接收新类型的空盘，确认运行日志出现阶段换蜂、旧蜂群完整回盘、当前数量/类型正确、节点进度继续；再验证缺对应盘时兼容回退。
