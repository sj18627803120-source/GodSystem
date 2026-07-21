# Traits Purchase System 研究报告

## 身份与版本

- 名称：Traits Purchase System。
- MOD ID：`TraitsPurchaseSystem`。
- `mod.info`：`modversion=2`、`versionMin=42.0`，说明文本声明可用于单人和多人。
- 本地主要代码树：`42`，没有声明精确 B42 小版本。
- 证据强度：`旧 B42 参考`。

## 功能地图

- `media/perks.txt`：注册 `Traits1/Traits2/Traits3` 三条十级技能，用等级总和表示可消费特质点。
- `media/lua/client/TraitsPurchaseSystem/ISTraitsPurchasePanel.lua`：枚举特质、过滤互斥、确认购买或移除。
- `media/lua/server/TraitsPurchaseSystem/Server.lua`：奖励特质点 XP、消费点数、增删特质并 `SyncXp()`。
- `media/lua/client/TraitsPurchaseSystem/Client.lua`：上报击杀和技能升级，接收成功音效。
- `media/lua/client/TraitsPurchaseSystem/ISEquippedItem.lua`：全局补丁原版侧栏，增加特质购买入口。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `media/perks.txt` | 三条自定义 Perk 各有十级 XP 曲线；当前可用点数为三条技能等级之和。 |
| `代码确认` | `Client.lua`/`Server.lua`，`purchaseTrait()` | 消费时从第三段、第二段、第一段依次降级，再用 `setXPToLevel()` 和剩余段内 XP 重建进度。 |
| `代码确认` | `Server.lua`，`OnClientCommand()` | 服务端按 `CharacterTraitDefinition.getTraits()` 重新解析真实特质，而不是直接执行客户端传来的对象。 |
| `代码确认` | 同函数，`TPSAddTrait` | 服务端增加特质后显式遍历 XP boosts 来升级 Perk，并学习 `getGrantedRecipes()` 返回的配方。 |
| `代码确认` | 同函数，参数校验 | 服务端直接使用客户端提交的 `TPScost` 检查和扣点，没有按真实 trait cost 重算，也没有重查 UI 的黑名单、互斥或职业前置。 |
| `代码确认` | `Client.lua`，击杀/升级事件 | 客户端从 `OnPlayerUpdate` 发现击杀变化并上报，从 `LevelPerk` 上报普通技能升级；服务端据此增加特质点 XP。 |
| `代码确认` | `Server.lua`，本地事件 | 非客户端环境还注册 `OnPlayerUpdate` 与 `LevelPerk`，直接增加同样的 XP；具体联机事件触发组合需要实测。 |
| `代码确认` | `ISEquippedItem.lua` | 保存并覆盖 `ISEquippedItem:prerender()` 与 `initialise()`，在原版健康按钮附近插入悬浮入口。 |

## 单人与多人数据流

- SP 由购买面板直接消费自定义 Perk 等级、增删特质、补 XP 等级和配方。
- MP 客户端发送 trait resource 字符串和客户端计算的点数费用；服务端解析角色与特质后执行真实 XP/特质修改，并调用 `SyncXp(player)`。
- 击杀和技能升级奖励采用客户端信号触发；服务端没有根据击杀差值或真实 LevelPerk 记录验证每次上报。
- 服务端回包只用于播放增删成功音效，没有回传完整特质点和特质状态快照。
- `作者声明`：`mod.info` 声明 SP/MP 支持；代码确有服务端 handler，但不等于价格、资格和奖励信号都是服务端权威。

## 可采用机制

- 使用标准 Perk XP 曲线承载可消费点数，使状态自然进入角色 XP 存档和同步系统。
- 枚举 `CharacterTraitDefinition.getTraits()`，可发现按标准方式注册的 MOD 特质。
- 购买后显式处理 trait 的 XP boosts 和 granted recipes，说明运行时添加特质需要补做部分创建期效果。
- MP 中服务端重新解析枚举对象并调用 `SyncXp()`，客户端不传 Java 对象。
- UI 先过滤已拥有、正点数、互斥和黑名单，并在确认时重新检查本地状态。

## 风险与限制

- `代码确认`：客户端可提交任意较低的 `TPScost`；服务端没有用真实 cost 覆盖，属于明确的联机信任边界，不可复用于 GodSystem 付费能力。
- `代码确认`：服务端未重查互斥、职业映射、黑名单和可购买性；UI 隐藏不是权限验证。
- `代码确认`：`TPSZombieKill` 和 `TPSPerkLevelup` 可直接触发 XP 奖励，服务端没有 operation ID、速率限制或事实重算。
- `合理推断`：标准注册的 MOD 特质会出现在枚举中，但其自定义初始化、事件注册、物品发放和 ModData 不会因通用 `add()` 自动执行。
- `代码确认`：全局 monkey patch 原版 `ISEquippedItem`，与其他侧栏 MOD 的覆盖顺序和 UI 缩放存在冲突面。
- 移除特质只删除特质标记并消费点数，不回滚购买时补发的技能等级和配方。

## 对 GodSystem 的应用

- 可借鉴“标准注册表枚举”，但 GodSystem 服务端必须按 perk/trait 的真实定义重算价格、上限、互斥和余额。
- 属性 XP 购买继续以 `Perks.getMaxIndex()`、`Perks.fromIndex()` 和注册 XP 曲线为准，并按实际 XP 增量结算。
- 若实现特质商店，应建立允许列表或适配器，区分纯标记特质、XP/配方特质和带一次性初始化的复杂特质。
- 不采用全局覆盖原版侧栏的入口方式；继续走 GodSystem 自身导航和模块注册。
- 付费和 XP 变更应有结构化结果、状态回包和去重机制，不能仅依赖成功音效。

## 待验证内容

- `待实机验证`：B42.19 专用服务器是否同时触发服务端本地奖励事件与客户端奖励命令，从而发生重复 XP。
- `待实机验证`：三段 Perk 降级和段内 XP 重分配在边界等级、非整数 XP 下是否精确守恒。
- `待实机验证`：大量 MOD 特质、命名空间资源和职业特质同时加载时的枚举完整性。
- `待实机验证`：与其他修改 `ISEquippedItem` 的 UI MOD 的加载顺序兼容性。

## 联网检索信息

- 搜索词：`Project Zomboid Traits Purchase System hakcenter modversion 2 B42`
- 建议核对：Workshop 的 MP 已知问题、B42.19 CharacterTraitDefinition API、`SyncXp` 行为和服务器事件触发说明。
