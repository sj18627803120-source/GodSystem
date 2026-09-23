# GodSystem 工程文档

更新时间：2026-09-23。目标游戏：Project Zomboid B42.20.4，Lua 5.1/Kahlua。开发树版本：`42.20_3.18.1`。最近已实机验收并备份：`42.20_3.16`；3.17–3.18.1 为测试版，结论见最新交接。此文描述当前代码组织，不替代逐项实机验收。

## 项目身份与目录

- 源码仓库：`C:\APPS\Pzmodproject\GodSystem-main`；游戏测试副本：`C:\Users\wan20\Zomboid\Workshop\GodSystem-main`。后者是部署产物，不作为编辑源。
- 滚动备份：`C:\APPS\Pzmodproject\GodSystem-main.zip`，仍是用户通过的 3.16；`C:\APPS\Pzmodproject\历史资料` 存放旧 UI 测试树、候选归档和笔记。
- Workshop ID `3773949382`，Mod ID `GodSystem_CN`，存档键 `GodSystem_CN_Data`。文档整理不改变这些身份。
- 上传结构：`workshop.txt`、`preview.png` 和 `Contents/mods/GodSystem/{mod.info,42/mod.info,42/media}`。`docs`、`tools`、`.git`、`.test-runtime` 与历史资料不属于游戏运行包。

## 分层与入口

| 层 | 入口/关键文件 | 职责 |
|---|---|---|
| `shared` | `GodSystem_Config.lua`、`GodSystem_Protocol.lua`、`GodSystem_EconomyPolicy.lua`、`GodSystem_Equipment*.lua`、`GodSystem_UtilityGenerator.lua` | 配置、协议、双方一致的规则和物品/世界对象业务原语 |
| `client` | `GodSystem_Core.lua`、`GodSystem_Network.lua`、`GodSystem_UI.lua`、`GodSystem_Terminal*.lua` | UI、选择/展示缓存、SP 适配与 MP 请求；不把显示缓存当权威价格 |
| `server` | `GodSystem_Server.lua`、`GodSystem_ServerRuntime_*.lua`、`GodSystem_TransactionOps.lua` | MP 命令分发、真实物品/玩家/世界对象复核、结算、回执和同步 |
| 资源 | `media/scripts/GodSystem_Items.txt`、`media/sandbox-options.txt`、`media/lua/shared/Translate` | 物品、沙盒选项及生成的 CN/CH/EN 文本 |

当前包有 135 个 Lua 文件；精确数量以后以测试输出为准。ServerRuntime 以 installer 注册并由 `GodSystem_Server.lua` 装配；新增命令应先核对 `GodSystem_Protocol.lua`，再核对服务端路由与客户端回执。SP 与 MP 尽量复用 shared 业务规则，由适配器决定真实玩家、存档和同步路径。

## 核心状态与交易

- 玩家货币、任务、升级、银行及 UI 偏好由已有玩家数据承载；服务端投影 `GodSystem_StateProjection.lua` 只发客户端展示所需状态。不要把客户端副本作为权限或余额来源。
- 商城目录使用稳定商品身份、分块同步及本地目录快照；购买服务端复核真实上架状态和逐件报价。动态涨价按账号及商品记录在线游戏时间层数；交易成功与原操作回执一起提交。
- 商品购买参考价顺序为管理员覆盖、`GodSystem_Prices.lua` 精确价、分类默认价；回收价再按管理员覆盖、未知模组保守价、比例/倍率及物品状态计算。转换关系静态基础表与管理员覆盖层共同形成安全最低价。详见 3.13–3.16 交接。
- 付费/发货操作使用 `opId`、指纹和有界回执；服务端重新定位物品、价格、余额及配置。重试同一操作返回原结果，不能重复扣费、发货或叠加效果。超过 2000 件回收使用有界摘要，仍须避免大批量删除造成单帧压力。
- 装备绑定以稳定身份及服务所需的原生信息为边界，等级档案由权威存储管理。近战冻结、冲击和溅射共用挥击事件；溅射致死统计与多人同步仍待实机验证。
- 水电一体机 `GodSystem.UtilityGenerator` 使用原生 `IsoGenerator` 和流体接口；余额按设备 ID 存储，所有玩家可操作。当前原生对象同步、固定设施供水和服务器重启恢复仍待实机验收。完整边界见交接 112。

## 修改入口与约束

1. 先读根 `AGENTS.md`、交接 `00_继续开发入口.md` 和目标功能的最近一篇交接，再追踪现有调用链。
2. 不猜 Java/Kahlua 签名：同补丁原版代码、反编译或最小实机探针优先；历史 B42.19 资料只作线索。
3. 功能版本升级须同步两处 `mod.info`、`GodSystem_Config.Version`/经济策略版本、`workshop.txt` 首行以及 `00`/`07` 和新交接；纯文档整理不升运行包版本。
4. 玩家文本修改 UTF-8 YAML 源，运行 `tools/localization/generate_godsystem_v11645_localization.py`，生成 CN/CH/EN、ItemName、Tooltip、Sandbox 和 Lua fallback；检查 U+FFFD。
5. 保留原始存档身份、Mod ID/Workshop ID、未发布修订及用户撰写的 Workshop 正文。参考 MOD 报告仅提供事实、路径和接口线索，不复制代码或素材。

## 验证与发布边界

在仓库根运行：

```powershell
python tools/tests/run_lua_tests.py
python tools/tests/run_kahlua_tests.py --game "D:\SteamLibrary\steamapps\common\ProjectZomboid"
pwsh tools/Test-GodSystem.ps1
git diff --check
```

第一项用 Lua 5.1 VM 编译打包 Lua 并执行行为规格；第二项在目标游戏 Kahlua 环境运行回归；第三项检查包结构、版本、本地化和脚本/协议等静态条件。模拟测试不证明 Java 重载、真实 UI 绘制、世界对象生命周期、反作弊或多人同步。

源码修改后如需部署，先确认测试目录与 Robocopy 进程，用绝对路径镜像 `Contents`、Workshop 元数据及仓库测试所需文件，再逐文件核对 SHA-256 并在目标目录运行静态检查。GitHub 开发分支同步、更新 `main`、覆盖滚动 ZIP 和 Steam Workshop 发布是不同动作。3.17–3.18.1 的实机项目见 [交接 110–112](../GodSystem_DevHandoff_CN/112_v42.20_3.18.1_水电一体机.md)。
