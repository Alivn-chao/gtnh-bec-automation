# 蜂群缓存刷新补丁（2026-10-24）

此目录保存从实际 OC 导出的实体总线版本及本次补丁，不能用仓库较旧的 `reinstall_v2/files` 直接覆盖它。当前实机配置为 cell-io、hiveSource=transposer、hatchSide=4。

修复：实体有蜂群而节点/观测阵列缓存数量或类型不一致时，禁止走“无需换蜂”的返回路径；保持整组暂停，通过原有带 journal 的 IO 回收、重新装入。允许使用回收后得到的同种蜂群，不要求备用箱另有一整份。缺空盘、未完成日志或不确定搬运仍停止。

装入完成后检查同组所有节点的原生 getAvailableNanites/getProvidedTier；数量按30720封顶比较，类型必须一致。最多等待30秒，仍不识别则保留 verifying-array 日志并暂停，不循环重试、不放行生产。正常识别不额外搬盘。这里只刷新库存变化，不修改模组缓存或伪造节点读数。

本次仅将 `files/lib/bridge.lua` 与 `files/runtime/nanites_cell.lua` 部署至实际 OC，写入前比较实际旧文件，使用 MCP 版本校验并保留备份，写后逐字回读。`hive_transposer.lua` 为兼容版本快照，实际未替换。

验证：`python fixes/hive_refresh/test_refresh.py`。包含实际桥接模块接线模拟和拒绝重复搬运场景；需要 `work/lua_runtime` 的 Lua5.2 Lupa。不能将模拟成功称为真实缓存故障复现。
