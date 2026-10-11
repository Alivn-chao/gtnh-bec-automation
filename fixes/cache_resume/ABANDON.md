# 放弃本次空间缓存

用户明确授权“肯定放弃重置”。`abandon_space.lua` 是一次性实物核对脚本，针对本次截图
空间凝聚物144000、子网spatialfluid576、旧cache stage stream-crafting、单目标500万、
单申请spatialfluid submitted、已确认搬料576。不是通用重置器。

Q正常退出生产UI，Ctrl+D退出Lua解释器后，在shell下载并执行。脚本要求已安装单项缓存
模块，主网CPU列表非空且全部明确idle（有无关任务同样等待/手动取消），暂停输出15、
节点安全状态、GEN停且inactive、场开启、主接口全部无配置、生产日志cache-working且无plan/pending。
现场数量或记录不符先拒绝，不重复申请或搬料，不自动取消AE任务。

先复制原cache/config唯一备份并写显式flush回读重置记录 `/home/bec_cache.abandon`，
仅启GEN处理现有576，最终子网空/场空间144576/GENinactive，关GEN。其他场库存必须不变。
180秒超时或Q停止关闭GEN，保留原cache和独立重置记录，可重新运行同脚本核对守恒后接续。
本次限定空间原液1:1守恒，不适用于其他纠缠配方。

随后配置entangled_space单项0（其他单项和默认目标保留），旧cache完整留备份，包括submitted
申请；新cache结束记录标明 abandoned/originalJournal，requests/transfers为空，本轮目标改为
本次已守恒转换的实际存量。这表示主动放弃旧目标，不把旧AE订单冒充done。
生产journal不改，使用现有 `lua /home/bec_ui.lua resume` 完整核对后恢复。
实机仍待用户运行；Lua5.2模拟验证归档原记录/只转换576/配置0/重复无动作/AE忙与现场变化
拒绝/超时停止GEN与重试接续。
