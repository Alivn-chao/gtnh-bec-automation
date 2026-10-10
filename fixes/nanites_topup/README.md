# V1：相同蜂群补充，最多30720个

仅替换现有 V1 `/home/bec_nanites.lua`，沿用原控制器和蜂群子网地址。实际转运器**北2连接备用网物品ME接口，南3连接收容网物品ME接口，西4是蜂群仓本体**；收容网存储总线连接蜂群仓，控制网只暴露该仓，仓输出显示槽保持锁定。程序通过两侧ME接口搬运，不直接读写蜂群仓显示槽。

若旧版报“西面应为收容网物品接口”，下载此修正版即可，无需挪动接口。检查、库存计数、装入和退回蜂群均使用同一组已核对的方向。

- 节点暂停、配方需要蜂群时，读取两边的库存。
- 仓内类型满足需求，且没有需要优先切换的更低合适等级时，按物品ID和damage补充完全相同的蜂群，不先退出原蜂群。
- 同类型补充量是 `min(同类型备用数量, 30720 - 当前仓内数量)`。
- 需要换类型时，先退回旧蜂群，选用原有等级选择逻辑，再装入新类型全部可用数量，最多30720。
- 新加蜂群在下次暂停准备配方时补入；不在合成中搬运。满仓不搬，多余的保留在备用子网。
- 持久化搬运意图、暂停校验、需求等级校验、节点数量回读及两网总量核对保留。未确认的搬运不重试。

推荐在退出生产UI、保持节点暂停后运行带校验的安装器：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/nanites_topup/install_sidefix.lua /home/bec_install_sidefix.lua
lua /home/bec_install_sidefix.lua
```

安装器固定下载 `a2c8c9a` 的模块，校验长度、内容校验值及 Lua 语法，只读预览实际北2/南3接口与库存。全部通过才自动生成不覆盖旧文件的 `bec_nanites.lua.before_sidefix-N` 备份，写入并回读新文件，最后替换模块；替换失败尝试恢复旧文件。不会调用 `ensure`、搬蜂群、改配置、启动生产或写 journal。重复运行已安装的同版模块不新增备份。若 OC 在两次改名之间断电，先用打印的备份恢复 `/home/bec_nanites.lua`。9 个安装模拟场景通过，尚待游戏验收。

确认安装成功后，另行运行 `lua /home/bec_ui.lua resume`。凝聚物不足故障与门过滤放行时序仍需独立核对，方向修正不代表吞料问题已解决。

若游戏服务器连接 GitHub 超时，已启动的诊断接收端还提供 `<临时公网地址>/sidefix/install.lua` 和 `/sidefix/bec_nanites.lua` 两个固定脚本下载入口。该入口返回的安装器会从同一通道下载模块，保持同版内容校验、暂停检查及备份流程。临时地址以本地 `public_url.txt` 为准；隧道停止后失效。接收端只镜像这两个公开脚本，不提供诊断快照下载或远程执行。

手动安装方式（备份名已存在时更换名称）：

```sh
cp /home/bec_nanites.lua /home/bec_nanites.before_topup.lua
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/nanites_topup/bec_nanites.lua /home/bec_nanites.lua
lua /home/bec_ui.lua resume
```

保留蜂群、生产及缓存journal。`test_topup.py` 的模拟覆盖同类型补充、封顶、满仓、类型切换、不同物品不混入、中断继续、未确认操作拒绝重试等。不是游戏硬件验收。

## 凝聚物不足排查

节点显示 `Insufficient condensate ... Cosmic Neutronium ... 13824` 且当前空闲时，显示的是上次停机原因，不能据此推算下一单需求。需比较失败时的库存、消耗记录及门过滤；储存侧有料与装配端能取到料是两个检查。

只读检查，不修改配置或重试失败订单：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/main/fixes/nanites_topup/check_condensate.lua /home/bec_check_condensate.lua
lua /home/bec_check_condensate.lua
```

把输出与门两侧BEC仓的实际接线一并核对。原程序只查询指定约束场库存并回读门过滤，没有能验证完整装配端可达路径的已确认API。若过滤正确而储存有料，下一步检查门的单向连接、装配端所接网络、其他过滤设备及现场运行状态，不能直接靠再补13824或重下订单当作修复。
