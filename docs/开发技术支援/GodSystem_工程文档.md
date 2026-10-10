# GodSystem 工程文档

更新时间：2026-10-10。目标游戏：Project Zomboid B42.21，Lua 5.1/Kahlua。源码及唯一滚动备份：`42.21_3.21.4`；用户确认当前测试通过，授权同步GitHub main，验收/归档见交接130。尸体本体开关、地面回收核对/备用拾取及配置优化分别见交接129、128、125。此前未逐项确认的多人及原生接口场景保留原状态。开发期诊断工具由 `python tools/analysis/setup.py` 安装，随后运行 `pwsh tools/Test-GodSystem.ps1`；工具不进入运行包。此文描述当前代码组织，不替代逐项实机验收。

## 项目身份与目录

- 源码仓库：`C:\APPS\Pzmodproject\GodSystem-main`；游戏测试副本：`C:\Users\wan20\Zomboid\Workshop\GodSystem-main`。后者是部署产物，不作为编辑源。
- 滚动备份：`C:\APPS\Pzmodproject\GodSystem-main.zip`，对应当前已验收的 3.21.4；`C:\APPS\Pzmodproject\历史资料` 存放旧 UI 测试树、候选归档和笔记。
- Workshop ID `3773949382`，Mod ID `GodSystem_CN`，存档键 `GodSystem_CN_Data`。文档整理不改变这些身份。
- 上传结构：`workshop.txt`、`preview.png` 和 `Contents/mods/GodSystem/{mod.info,42/mod.info,42/media}`。`docs`、`tools`、`.git`、`.test-runtime` 与历史资料不属于游戏运行包。

## 分层与入口

| 层 | 入口/关键文件 | 职责 |
|---|---|---|
| `shared` | `GodSystem_Config.lua`、`GodSystem_Protocol.lua`、`GodSystem_EconomyPolicy.lua`、`GodSystem_Equipment*.lua`、`GodSystem_UtilityGenerator.lua` | 配置、协议、双方一致的规则和物品/世界对象业务原语 |
| `client` | `GodSystem_Core.lua`、`GodSystem_Network.lua`、`GodSystem_UI.lua`、`GodSystem_Terminal*.lua` | UI、选择/展示缓存、SP 适配与 MP 请求；不把显示缓存当权威价格 |
| `server` | `GodSystem_Server.lua`、`GodSystem_ServerRuntime_*.lua`、`GodSystem_TransactionOps.lua` | MP 命令分发、真实物品/玩家/世界对象复核、结算、回执和同步 |
| 资源 | `media/scripts/GodSystem_Items.txt`、`media/sandbox-options.txt`、`media/lua/shared/Translate` | 物品、沙盒选项及生成的 CN/CH/EN 文本 |

当前包有 142 个 Lua 文件；精确数量以后以测试输出为准。ServerRuntime 以 installer 注册并由 `GodSystem_Server.lua` 装配；新增命令应先核对 `GodSystem_Protocol.lua`，再核对服务端路由与客户端回执。SP 与 MP 尽量复用 shared 业务规则，由适配器决定真实玩家、存档和同步路径。

## 核心状态与交易

- 玩家货币、任务、升级、银行及 UI 偏好由已有玩家数据承载；服务端投影 `GodSystem_StateProjection.lua` 只发客户端展示所需状态。不要把客户端副本作为权限或余额来源。
- 商城目录使用稳定商品身份、分块同步及本地目录快照；购买服务端复核真实上架状态和逐件报价。动态涨价按账号及商品记录在线游戏时间层数；交易成功与原操作回执一起提交。
- 商品购买参考价顺序为管理员覆盖、`GodSystem_Prices.lua` 精确价、分类默认价；回收价再按管理员覆盖、未知模组保守价、比例/倍率及物品状态计算。转换关系静态基础表与管理员覆盖层共同形成安全最低价。详见 3.13–3.16 交接。
- 付费/发货操作使用 `opId`、指纹和有界回执；服务端重新定位物品、价格、余额及配置。重试同一操作返回原结果，不能重复扣费、发货或叠加效果。超过 2000 件回收使用有界摘要，仍须避免大批量删除造成单帧压力。
- 装备绑定以稳定身份及服务所需的原生信息为边界，等级档案由权威存储管理。近战冻结、冲击和溅射共用挥击事件；溅射致死统计与多人同步仍待实机验证。
- 水电一体机 `GodSystem.UtilityGenerator` 使用原生 `IsoGenerator` 供电；供水对带原版管道标志的固定设施使用原生流体接口，或经原生水量回读验证的 `waterAmount` / `waterMaxAmount` 储水字段。水、电账户按设备 ID 分开保存并扣费，旧共享余额惰性迁入水账户；所有玩家可操作。当前固定水龙头供水、多人同步和服务器重启恢复仍待实机验收。完整边界见交接 112 与水电修复交接。

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

### 3.21 补充

当前集中更新见[交接125](../GodSystem_DevHandoff_CN/125_v42.21_3.21_配置一致性与批量回收优化交接.md)。配置核查见[沙盒生效矩阵](沙盒配置生效矩阵.md)，调用量与模拟耗时见[性能评估](3.21_回收性能评估.md)。准备任务比较业务令牌与会话代次；回收同步使用请求内分组，原生删除和恢复验证保留。超时不是失败结算；提交后仅通知失败保留原回执。原生MP收包与世界效果仍待集中实机验收。

## 3.21.1 隐藏管理修复

多人隐藏管理和上架预检通过Runtime.getShopListingRows读取现有ShopListingStore，保留ready和家具变体；最后一块消费完补一次展示刷新。服务端仍独立核验，不改变商品存档或收费规则。详见[交接126](../GodSystem_DevHandoff_CN/126_v42.21_3.21.1_多人隐藏商品管理修复.md)。

## 最新验收状态（2026-10-10）

用户确认42.21_3.21.4当前测试通过，唯一滚动ZIP更新为此版；源码和技术资料集成至GitHub main。验收/归档见[交接130](../GodSystem_DevHandoff_CN/130_v42.21_3.21.4_验收备份与源码同步.md)。多人尚不方便实测，未逐项确认的专项仍保留原状态。可复用的原生返回语义、删除生命周期与真实动作栏验证经验见[开发经验03](../GodSystem_DevHandoff_CN/03_开发经验与踩坑.md)。

## 3.21.2 多人预设状态

当前价格保存在服务器当前世界ModData，共用文件仅保存可复用模板。模板缺失不重置价格或选中标记；MP首次加载和重连等待权威状态，不先选中默认。正常重启及单项修改保持已有存储规则。代码与模拟证据、待实测边界见[交接127](../GodSystem_DevHandoff_CN/127_v42.21_3.21.2_多人价格预设重启显示修复.md)。

## 3.21.3 地面回收

原生世界移除成功后不重复执行生命周期；异常或暂时核验失败后进行一次有界状态复查，确认身份、两个地块列表及世界引用全部清除才结算。失败诊断带步骤和异常摘要。全部恢复并确认失败的地面回收可自动原版拾取后按背包回收一次；多人需匹配操作回执，等待原生物品与背包同步，不对超时/未知结果启动备用。用户已确认回收正常，详见[交接128](../GodSystem_DevHandoff_CN/128_v42.21_3.21.3_地面回收核对与备用拾取.md)。

## 3.21.4 范围回收动作栏与规则

populateList动作栏显式列出fourth按钮，复用既有toggleCorpses意图及个人偏好。共享RangeRecycleDomain在includeCorpses=false时仅跳过corpses，corpseItems继续按原筛选处理。没有新增扫描或网络消息；真实UI及Domain回归覆盖显示与规则独立性，详见交接129。
