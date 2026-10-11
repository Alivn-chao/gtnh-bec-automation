# 通用后台缓存重置键

V2支持 `transfer-pending` 的实物核对：GEN已停、AE全idle/节点pause15、MAIN无供液配置时，
仅对有已确认同raw/地址/from/to历史记录的独立高速口（源0或1→接收5）操作，读取old.secured
完整子网快照；对应raw实际只能等于快照（未搬）或快照+pending.amount（整笔已搬），
其他raw不变，再读取一次子网验证稳定。不重新执行transfer；部分/超额/无历史路线仍拒绝，
显示未搬、整搬、实测数量。核对结果单独保存于reset进度reconciliation，原pending日志完整备份。
这依赖原接法的独立子网，不用于有其他流体自动化并行写入子网的系统。
安装器兼容已装重置V1，原位替换内嵌worker；编译/备份后升级，不重置机器或日志。

`patch_reset_button.lua` 为已安装 UI_SPEED_V2/UI_PAUSE_V1 的真实上传面板增加 Z 放弃缓存/重置。
安装器仅修改 UI（内嵌 `reset_cache.lua`），定位全部修改后编译，临时文件 flush 回读、唯一备份、失败还原。
生产控制器/配置/journal/硬件在安装时不变，保留单项目标与暂停提示补丁。

Q 退出暂停面板后安装，再 `lua /home/bec_ui.lua resume`，故障页点击左下 Z 或按 Z。
按钮只在控制器已经停止的故障状态生效，不另起并行服务；T仍是正常恢复核对。
重置成功自动进入既有 resume，恢复核对不通过仍留面板显示红底原因。

重置的是后台缓存目标，不删除生产订单，不清凝聚物，不重新下 AE 单，不搬新原液。
读取旧目标确定涉及类型，所有登记流体均支持，空间/时间允许真实 raw 别名。
要求节点暂停15/安全状态、GEN停inactive、场开启、主网全部CPU非空明确idle、接口配置全nil，
生产cache-working且无plan/pending、历史生产申请搬料确认、缓存无pending/configOwned，
缓存申请只接受submitted/done、搬料已确认。AE尚忙时须ME中完成或取消，再按Z；不会猜CPU或自动取消。

对剩余原液核对归属于本轮目标、整转换批次和old.secured确认上限，读取现场场存量，
先写原cache/config唯一备份与bec_cache.reset进度，再仅启GEN转换held。
最终需子网空、GENinactive、各类型field+raw与起始field+raw守恒且无无关库存变化；
超时600秒或Q关闭GEN并留进度，下次Z按实际剩余接续。无剩余原液则不启GEN。
可连续处理以后的独立失败，已done进度独立备份后新建；不能让旧done阻塞新一轮。

处理后旧submitted完整留备份，新cache结束记录标abandoned/resetRecord/originalJournal，
目标改为本次处理后的实有库存，requests/transfers为空（主动放弃，不冒充旧订单已done）。
生产journal不改，交原resume核对。涉及缓存类型overrides设0，防止立即重下旧大额目标；
其他类型、默认目标不改。C里设合适目标即可重新启用，生产按实际配方备料继续。

这不是任何生产故障都能“强制清日志”的按钮：不确定搬料/提交、非缓存阶段、守恒不符仍拒绝并说明原因。
当前Java流体转换采用和原cacheworker相同的原液/凝聚物1:1数量目标；转换单位144或1000。
`test_reset_button.py <实际bec_ui.lua>` 在Lua5.2模拟多流体/转换单位/库存保留/后续新重置/
AE忙或未知搬料拒绝/超时和部分转换接续/守恒不符拒绝/实际V2暂停目标UI安装回滚重试/
鼠标Z处理后resume一次。模拟通过，游戏实机待用户验证。
