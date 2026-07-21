# More Traits 研究报告

## 身份与版本

- 主 MOD：More Traits，MOD ID 为 `1299328280/ToadTraits`。
- 动态子模块：More Traits - Dynamic Traits，MOD ID 为 `1299328280/ToadTraitsDynamic`。
- 本次主证据树：`42.17`；两份 `mod.info` 都声明 `versionMin=42.17`。
- 主 MOD 依赖 `UnifiedCarryWeightFramework`；动态子模块依赖主 MOD 与 KillCount。
- 证据强度：`旧 B42 参考`。注册方式接近 B42.19，但接口采用前仍应核对当前原版。

## 功能地图

- `media/registries.lua`：用 `CharacterTrait.register()` 注册命名空间特质资源。
- `media/lua/shared/NPCs/MoreTraitsMainCreationMethods.lua`：在 `OnGameBoot` 中建立特质定义、XP 加成、免费配方和互斥关系。
- `media/lua/shared/MoreTraits .lua`：特质运行效果、角色创建物品、初始伤病/等级和高频事件。
- `media/lua/server/MoreTraits_UCWF.lua`：向统一负重框架注册 Pack Mule/Pack Mouse 等负重修正。
- 动态子模块的 `media/lua/shared/MoreTraits - Dynamic.lua`：按等级、击杀、伤病、体重和时间条件增删特质。
- 动态子模块的 `media/lua/server/MoreTraitsDCC.lua`：接收增删特质和 XP boost 命令，并周期复查部分条件。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `media/registries.lua`，`CharacterTrait.register()` | B42.17 先注册 `ToadTraits:*` 命名空间资源，并按已启用 MOD 条件跳过冲突特质。 |
| `代码确认` | `MoreTraitsMainCreationMethods.lua`，`initToadTraits()` | `TraitFactory.addTrait()` 建立显示、点数、XP boost、免费配方和互斥定义；该函数只挂在 `OnGameBoot`。 |
| `代码确认` | `MoreTraits .lua`，`initToadTraitsItems()`/`initToadTraitsPerks()` | 准备类物品、初始伤病、直接等级和部分配方学习发生在 `OnCreatePlayer` 初始化链，不是 `traits:add()` 的自动副作用。 |
| `代码确认` | `MoreTraits_UCWF.lua` | 客户端跳过该文件；SP/服务端通过统一负重框架，根据力量和 Pack Mule/Pack Mouse 特质返回基础负重加值。 |
| `代码确认` | 动态 `MoreTraits - Dynamic.lua`，`MTDTraitsGainsByLevel()` | 动态模块按具体条件调用 `traits:add()`/`traits:remove()`；只有代码明确调用 `MTDapplyXPBoost()` 的分支才补 XP boost。 |
| `代码确认` | 同文件，`MTDRegisterLogic()` | 每分钟、每十分钟、每小时、技能升级、命中和僵尸死亡分别处理不同条件，不依赖每帧全量重算。 |
| `代码确认` | 同文件，`MTDPlayerCreation()` | 初始动态复查临时使用 `OnPlayerUpdate`，约 200 次更新后执行一次并立即移除事件。 |
| `代码确认` | 动态 `MoreTraitsDCC.lua` | 服务端接受 `addTrait/removeTrait/setXpBoosts`，并在 `EveryTenMinutes` 与力量/体格升级时执行同步复查。 |

## 单人与多人数据流

- SP 中动态判断直接修改角色的 `CharacterTraits` 和 XP boost，计数保存在玩家 ModData。
- MP 客户端达到条件后发送 `MoreTraitsDynamic` 命令；服务端按注册表 key 增删真实特质。
- 服务端另外每十分钟遍历在线玩家，尝试调用完整条件函数；函数不可用时只复核 Pack Mouse、Pack Mule 和 Hardy 三项。
- `作者声明`：动态文件保留了 `TODO MP Support` 注释；虽然存在服务端命令和周期复查，不能据此宣称全部动态规则已严格服务端权威化。
- 客户端命令只携带特质 key 或 perk/boost，没有携带一次性请求 ID，也没有结果回包或失败恢复。

## 可采用机制

- B42 特质先注册稳定的命名空间资源，再建立显示、点数、互斥和 XP 定义。
- 将“持续运行效果”“动态获得条件”“创建角色一次性奖励”拆开；运行时购买只执行明确列出的补发动作。
- 动态条件按事件频率分组：等级变化即时复查，伤病十分钟复查，体重每小时复查，避免每帧遍历全部规则。
- 特质改变由服务端落地，客户端只负责 UI 和低风险候选检测；服务端仍要重新计算资格。
- 负重增益通过统一框架注册 modifier，避免多个 MOD 反复覆盖同一个最大负重值。

## 风险与限制

- `代码确认`：动态服务端命令只校验 key 能否解析，没有按请求重新验证该特质的等级、击杀、伤病或时间门槛；不适合作为付费购买的权威模板。
- `代码确认`：动态事件在 `OnCreatePlayer` 内注册全局事件。重生、分屏或重复创建角色时是否重复注册，需要实机确认。
- `代码确认`：动态获得特质时通常只增删特质并选择性修改 XP boost，不会调用主 MOD 的角色创建物品和初始伤病逻辑。
- `合理推断`：仅调用 `player:getCharacterTraits():add()` 购买第三方特质，能激活以后通过 `hasTrait()` 检查的持续效果，但不能保证补发它在 `OnNewGame`、`OnCreatePlayer` 或专用初始化函数中的奖励。
- 主 MOD 体量很大并注册多个高频事件；研究某一特质时应追踪该特质的专属调用链，不应把定义表当作完整行为说明。

## 对 GodSystem 的应用

- 属性页继续购买标准 Perk XP，不把“购买任意特质”与技能经验混成同一接口。
- 若未来开放特质购买，服务端必须解析真实 `CharacterTraitDefinition`、重算价格、互斥和前置条件，并为一次性副作用建立明确适配表。
- 未建立适配表的第三方特质只可标注为“添加特质标记”，不能承诺初始等级、物品、配方或自定义 ModData 已补齐。
- 多个负重来源应走组合式 modifier 或集中结算，不直接覆盖其他 MOD 已计算的容量。
- 动态规则应按分钟/小时/事件分层，并避免从 `OnPlayerUpdate` 重复注册长期事件。

## 待验证内容

- `待实机验证`：B42.19 中 `CharacterTrait.register()` 与 `TraitFactory.addTrait()` 的最终资源映射和加载顺序。
- `待实机验证`：专用服务器、分屏和死亡重生后动态事件是否重复注册或重复提示。
- `待实机验证`：动态 XP boost 在 MP 的即时同步、重连保存及超过框架上限时的行为。
- `待实机验证`：与其他动态特质 MOD 同时修改同一特质时的冲突顺序。

## 联网检索信息

- 搜索词：`Project Zomboid More Traits 1299328280 ToadTraits B42.17 Dynamic Traits`
- 建议核对：Workshop 更新记录、Unified Carry Weight Framework 文档、B42.19 `CharacterTrait` 注册变更和 Dynamic Traits 兼容说明。
