# 参考 MOD 研究笔记

本文件是 GodSystem 的参考研究入口，不再重复保存第三方源码摘要或依赖某台电脑的绝对路径。完整的 11 份自包含报告位于：

- [研究库说明](../reference-mod-research/README.md)
- [来源与版本目录](../reference-mod-research/catalog.md)

## 使用原则

1. 当前目标游戏版本是 B42.19；同版本原版文件和官方示例优先级最高。
2. 社区来源按 `B42.19 同版本证据`、`旧 B42 参考`、`B41 弱参考` 分级。
3. 结论必须标明 `代码确认`、`作者声明`、`合理推断` 或 `待实机验证`。
4. 不上传第三方源码、贴图、模型、音效和完整配置，只保留机制、符号、风险和检索词。
5. 理论风险不能写成已发生故障。例如客户端直接转移电池属于潜在事务风险，但没有复现就不能称为 MP 不同步。
6. 报告能帮助定位接口，不能替代目标版本原版文件和实机验证。

## 按任务选报告

### 多人、经济和交易

- [Server Shop](../reference-mod-research/mods/Server-Shop.md)：B42.19 服务端定价、库存预留、发货、退款、离线队列和审计。
- [YeseMarket](../reference-mod-research/mods/YeseMarket.md)：共享协议、SP 本地后端、MP handler、物品快照和失败回滚。
- [CaiGou's Shop](../reference-mod-research/mods/CaiGou-Shop.md)：玩家上架与真实物品 ID，同时包含客户端价格/快照信任反例。
- [RuinBazaar](../reference-mod-research/mods/RuinBazaar.md)：SP 数据、UI 和交易 manager 分层；不作为 MP 权威依据。

### 容器、重量和物品脚本

- [Cultivation Storage Artifacts](../reference-mod-research/mods/CultivationStorageArtifacts.md)：五个独立容量 50 容器、递归实例减重、服务端同步和全局脚本污染风险。
- [More Traits](../reference-mod-research/mods/MoreTraits.md)：通过 Unified Carry Weight Framework 组合负重 modifier。
- [that DAMN Library](../reference-mod-research/mods/damnlib.md)：缺失 ItemType fallback 和全局 `ScriptItem:DoParam()` 的适用边界。
- [Extended Categories](../reference-mod-research/mods/CAExtendedCategories.md)：启动期分类、隐藏/废弃/内部物品过滤和临时实例缓存。

### 特质、XP 和能力

- [More Traits](../reference-mod-research/mods/MoreTraits.md)：B42 命名空间注册、创建期奖励、动态特质与事件节流。
- [Traits Purchase System](../reference-mod-research/mods/TraitsPurchaseSystem.md)：标准特质枚举、XP 点数、购买副作用和服务端校验缺口。
- [Psionic Awakening](../reference-mod-research/mods/PsionicAwakening.md)：B42.19 ModData 技能树、现实秒冷却、分批扫描、临时渲染和直接击杀限制。

### 车辆、调试和 UI

- [DebugMenu](../reference-mod-research/mods/DebugMenu.md)：原版 `vehicle/repair` 命令、调试物品生成和 hidden/obsolete 过滤。
- [Traits Purchase System](../reference-mod-research/mods/TraitsPurchaseSystem.md)：双列表交互及全局覆盖原版侧栏的冲突面。
- [Psionic Awakening](../reference-mod-research/mods/PsionicAwakening.md)：临时全屏 overlay 和事件注销。

## 已应用到 GodSystem 的稳定结论

- 系统币脚本已经显式使用 `ItemType = base:normal` 和 `WorldStaticModel = Money`；GodSystem 不依赖也不打包 damnlib。
- 商城、回收、任务交物和付费升级在 MP 由服务端重新解析价格、余额、真实物品 ID 和归属；UI 是否可点不构成权限。
- 付费/消耗操作使用稳定 operation ID、规范化请求指纹和持久结果缓存；超时重试只复用相同请求的 ID。
- 服务端发放或删除真实物品后显式调用容器同步；离线投递同时保留 `OnCreatePlayer + hello` 入口。
- 抽奖、商城和回收候选池优先过滤 `hidden`、`obsolete`、内部 ItemType/BodyLocation；名称黑名单只是兜底。
- 大型静态分类适合初始化或配置变更时预处理，不进入 UI draw、搜索和分页热路径。
- 单个 B42.19 `ItemContainer` 不设计超过 50；GodSystem 当前空间终端上限 49。
- 每实例重量、耐久和状态不能通过全局 `ScriptItem:DoParam()` 实现。全局脚本修改会影响同 fullType 的其他实例和后续生成物品。
- 运行时添加特质不会自动重放 `OnNewGame`/`OnCreatePlayer` 里的物品、伤病、配方或自定义 ModData；复杂特质需要专用适配器。
- 标准 MOD 技能只在暴露 `PerkFactory` 注册对象和有效 XP 曲线时进入属性页；MP 由服务端重新报价、加 XP 并 `SyncXp()`。
- 单人同伴伤害进入 `setAttackedBy(player)` 与 `Kill(player)` 路径，不能只 `setHealth(0)` 后手工增加击杀数。

## 当前原版检索入口

在安装了目标版本游戏的设备上，先用 `rg` 搜索命中，再读取少量上下文：

- `media/lua/server/ClientCommands.lua`：`OnClientCommand`、服务端物品增删同步。
- `media/lua/client/ServerCommands.lua`：`OnServerCommand` 客户端入口。
- `media/lua/shared/Util/LuaNet.lua`：网络命令调用形态。
- `media/lua/client/ISUI`：原版 UI、对话框、列表和车辆界面。
- `media/luaexamples` 与 `mods/examplemod`：官方示例。
- `media/scripts`：物品、容器、车辆、配方、模型和音效字段。

不要把不同设备的游戏绝对路径写回仓库。找不到本地原版文件时，先使用研究报告里的联网检索词，结论仍需标注证据等级。

## 维护方式

- 新增来源时先写独立报告，再更新研究库 README、catalog 和仓库内 `pz-mod-dev` 技能。
- 跨来源稳定规则写入 `tools/codex/skills/pz-mod-dev/references/pz-b42-patterns.md`，并保留来源报告链接。
- 运行 `tools/tests/Test-ReferenceModResearch.ps1` 检查来源覆盖、标题、证据标签、绝对路径和非 Markdown 资产。
- 研究库只记录静态证据；实机结论应同时更新对应版本实现文档和测试记录。
