# 当前单节点 V1：新硬盘完整安装

此入口用于本次已验证接线的单节点电脑，固定组件地址与 HARDWARE.md 一致，包含当前所有已交付 V1 修复。不会把这台机器改装成 V2，也不需要在新盘逐个运行旧补丁。

安装版本标签：`bec-v1-full-2026-10-14.1`。单文件包含全部程序，只需下载一次，安装过程不再逐文件联网。

## 换盘与安装

1. 旧 UI 按 Q 退出，保持约束场开启。两侧蜂群 ME IO 的设置恢复正确，端口内存储盘取回底部普通箱子前10格。
2. 换新盘并先装 OpenOS，保留互联网卡。旧盘先作为资料盘保留；不要先格式化，里面有已登记配方和自定义缓存目标。软件重装不能从机器状态猜回所有已登记样板。
3. 在新盘运行：

```sh
wget -f https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/bec-v1-full-2026-10-14.1/reinstall/install.lua /home/bec_install.lua
lua /home/bec_install.lua
```

安装器会检测其它已挂载硬盘中唯一的旧 BEC `/home`，复制 `bec/recipes/*.dat`、`bec_cache.config`、`bec_hd.config`。有多个来源时列出目录，按需要显式指定：

```sh
lua /home/bec_install.lua /mnt/旧盘地址/home
```

旧盘当时没接上也可以先安装程序，之后挂载旧盘再迁移数据：

```sh
lua /home/bec_install.lua import /mnt/旧盘地址/home
```

后补迁移会备份要覆盖的配置/配方，不覆盖新程序，不复制旧运行日志。若没有旧盘数据，需要通过样板处理重新登记配方。

## 首次启动

```sh
lua /home/bec_start.lua monitor
```

有高清屏幕组件时使用 OCHD BEC 适配器，否则使用普通 OC 面板；monitor 只读。确认配方已经迁移、两端 ME IO 无留盘且设置正确后退出只读界面，再运行：

```sh
lua /home/bec_start.lua initialize
```

此命令先设置暂停信号并按实际存量处理现有原液、创建新的供液会话，再重建换蜂状态，最后启动一个控制器。它不依赖电脑重启后仍保留旧红石输出。保持旧约束场库存；不从旧日志重放搬料或 AE 订单。机器里已经存在的外部 AE 任务需要按实物继续核对，不能因换盘假定它们消失。

之后常用：

```sh
lua /home/bec_start.lua run
lua /home/bec_start.lua resume
lua /home/bec_start.lua bee-restart
```

run 用于无日志或正常停止状态，resume 用于未完成状态。默认不带参数为 monitor。保留普通 OC 屏幕与显卡，高清控制模式仍复用原 UI 调度。

## 包含的功能

17 个文件，208326 字节（不含 OpenOS 和迁入的配方）：生产控制器、麦克斯韦门过滤、大订单分窗、高速并行供液/边纠缠边生产、顺序供液、CPU 持续等待与明确失败手动补料、单项缓存与鼠标设置、暂停原因/初始化、逐批关机、被动阶段换蜂、普通箱前10格及 ME IO 1/7、样板登记、蜂群重开、历史清理、OCHD BEC 适配器及通用模拟演示。

新盘默认缓存为每种 5000000 mB；迁入旧配置时保留真实默认值和每种流体的覆盖值。`bec_hd.config` 默认使用本次机器的节点和约束场地址，不适用于其它存档。

正常生产/缓存/换蜂的四类自动运行历史，每次归档前只留两份旧记录，加本次形成最多三份。当前 journal、`.previous`、初始化/重置/人工恢复证据与程序回滚副本不被该保留策略删除。

## OCHD 项目

- [项目源码](https://github.com/Alivn-chao/oc-hd-panel)
- [已发布 alpha3 完整测试包](https://github.com/Alivn-chao/oc-hd-panel/releases/download/v0.3.0-alpha3/oc-hd-panel-alpha3-test-package.zip)
- [alpha3 模组 jar](https://github.com/Alivn-chao/oc-hd-panel/releases/download/v0.3.0-alpha3/oc-hd-panel-0.3.0-alpha3.jar)

模组 jar 放在客户端和服务器的 `mods`，不是放入 OC 电脑硬盘；两端使用一致版本。若游戏已经装好合适版本，不必因为换 OC 硬盘重装模组。这里随新盘安装的 `bec_hd.lua`、`automation_demo.lua` 来自项目已发布 `v0.3.0-alpha3`（commit `d5d56dc012257cab4854f6789b9b0a790cc786d6`），保持其接口，不修改另一个项目本地尚未提交的 alpha4 开发内容。

## 下载与验证

完整安装器内嵌全部文件，逐个校验长度、Adler32 和 Lua 5.2 语法/配置格式，全部验证完成后才安装程序。部分改名失败可再次执行安装器，复用本次已验证内容；不覆盖被外部更改的部分安装程序。不在已有 BEC 程序/运行状态的旧盘直接覆盖，不格式化磁盘，不自动启动生产。另有较小的 `install_network.lua` 可逐文件从 raw/CDN 下载，支持下载失败后继续；一般使用上述单文件完整入口。

`build_bundle.py` 从 `seeds/` 中的实际 V1 快照依序应用仓库已交付补丁，在隔离的虚拟文件系统中组装；安装包只带最终程序，不带模拟器、安装历史或旧补丁。OCHD 种子来自上述公开标签。`files/` 与 manifest 是生成交付内容，修改构建输入后应重新生成。

`test_bundle.py` 的14个 Lua 5.2 模拟覆盖单文件零额外下载完整安装、旧盘仅迁移有效配方/配置、坏数据拒绝、磁盘满提前拒绝、网络版下载/校验失败不暴露半套程序、下载继续、部分改名重试、后补迁移、历史保留界限、实际完整生产控制器完成一批并保留过滤/换蜂入口、初始化只启动一个高清控制器。所有脚本语法校验通过；新盘实机整体安装仍待用户验收。
