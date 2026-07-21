# Cultivation Storage Artifacts 研究报告

## 身份与版本

- 名称：Cultivation Storage Artifacts。
- MOD ID：`CultivationStorageArtifacts`，作者字段为 Tofu。
- 本次主要代码树：`42.15`，`modversion=0.1.10`、`versionMin=42.15`。
- `mod.info` 说明文本声明适配 B42.17；根目录较旧清单是 `0.1.8`，不作为主要证据。
- 证据强度：`旧 B42 参考`。

## 功能地图

- `media/registries.lua` 与 `media/lua/shared/NPCs/CSABodyLocations.lua`：注册五个命名空间穿戴位置并加入 Human BodyLocationGroup。
- `media/scripts/generated/items/csa_item.txt`：五件容量 50 的穿戴容器和一个容量 5 的 EnergyHub 嵌套容器。
- `media/lua/server/CSAWeightServer.lua`：服务端耗电、递归压缩/恢复重量、附近世界物品恢复和同步。
- `media/lua/client/CSAClientTick.lua`：低频请求服务端处理，并按物品 ID 应用回传重量。
- `media/lua/client/CSABarrierClient.lua`：电池装卸、EnergyHub 自定义槽位预算和法宝交互。
- 其余 Barrier/Nourish 文件实现护盾、滋养和电池消耗，不是大容量本身的来源。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `csa_item.txt`，五个法宝 item | SpatialRing、SoulChain、BeltofMoonlitBridges、QiankunBag、BraceletofBoundlessHeart 各自都是独立 `Capacity=50`、`WeightReduction=100` 容器。 |
| `代码确认` | `registries.lua`/`CSABodyLocations.lua` | 五个容器使用五个不同的 `CSA:*` 穿戴位置，可同时出现在角色的容器栏；没有单个容器容量大于 50。 |
| `代码确认` | `csa_item.txt`，`EnergyHub` | EnergyHub 是容量 5 的子容器，用于装电池；它不是把五件法宝合并成一个库存界面的总仓库。 |
| `代码确认` | `CSAWeightServer.lua`，`GetContainerStatus()` | 四类法宝的递归重量倍率分别为 `0.5/0.1/0.01/0.001`；QiankunBag 不新增压缩倍率。 |
| `代码确认` | 同文件，`ScanDeep()` | 服务端递归遍历嵌套容器；有电法宝使用自身倍率，断电时保持当前重量，普通装备容器可触发恢复路径。 |
| `代码确认` | 同文件，`ProcessWeightAutoritative()` | 原始基准保存在每个物品的 `CSA_BaseWeight`，实例通过 `setActualWeight()` 和 `setCustomWeight()` 修改。 |
| `代码确认` | 同函数的脚本同步段 | 除实例外还调用 `scriptItem:setActualWeight()` 与 `DoParam("Weight = ...")`，会修改该 fullType 的全局脚本原型。 |
| `代码确认` | `CSAClientTick.lua` | 客户端每游戏分钟请求 `SyncContext`；服务端 `syncItemFields()` 后按 item ID 回传，客户端递归查找真实实例并更新重量。 |
| `代码确认` | `CSABarrierClient.lua`，`CSABatteryAction:perform()` | 电池在客户端 timed action 中直接从源容器 `Remove()` 再向目标 `AddItem()`，没有对应的专用服务端转移命令。 |

## 单人与多人数据流

- SP 和 MP 都由客户端低频触发 `CSA_FABAO/SyncContext`；非客户端环境的服务端 handler 扫描玩家真实库存。
- 服务端保存每个实例的基准重量，修改实例和脚本重量，调用 `syncItemFields()`，再发送 `UpdateWeight{id,w,o}`。
- MP 客户端只按回包中的真实 ID 搜索角色递归库存或附近两格世界物品，不按 fullType 随机选择实例。
- 服务端扫描范围包括角色根库存中的容器，以及玩家附近两格的世界物品；世界物品走恢复基准重量路径。
- `作者声明`：源码注释将上述路径标为“联机同步”；代码确有 C2S、服务端处理、`syncItemFields()` 和 S2C 更新，但没有事务 ID 或完整结果确认。
- EnergyHub 电池装卸没有复用这条服务端命令链；其成功与同步依赖原版容器行为和当前运行环境。

## 可采用机制

- 用多个独立标准容量容器扩展总携带空间，而不是尝试突破单个 `ItemContainer` 的硬上限。
- 自定义穿戴位置同时完成资源注册、Human group 建立、`BodyLocation` 和 `CanBeEquipped` 四处一致声明。
- 递归遍历时携带当前压缩上下文，并为每个实例保存原始基准，便于离开特殊容器后恢复。
- MP 由服务端按真实物品 ID 修改，客户端只应用结构化结果；嵌套容器必须递归定位。
- 大范围恢复不需要全场扫描，可限制到玩家库存、明确转移动作和附近世界格。
- 同步前避开正在拖拽或选择物品的 UI 时段，可减少刷新与玩家操作冲突。

## 风险与限制

- `代码确认`：表面上的“超大空间”实际是五个容器栏，每件仍为 50；游戏里看起来仍是多个背包/容器标签，而不是一个合并仓库。
- `代码确认`：`ScriptItem` 是同 fullType 共用的脚本定义。对单个实例压缩时调用 `DoParam()` 会改变全局默认重量，不符合“每实例状态”边界。
- `合理推断`：同类型物品处于不同法宝倍率、后来新生成物品或多玩家同时处理时，全局脚本重量可能互相覆盖；这是结构风险，不等于已经复现联机错误。
- `代码确认`：`SyncContext` 顶层只递归进入根库存里的容器；根库存中的散装物品不经过恢复函数。压缩物品直接拿到主库存后的恢复时机需要实测。
- `代码确认`：断电分支明确保持断电前重量，不立即恢复；这是当前玩法规则，不是同步失败。
- `合理推断`：客户端直接 `Remove/AddItem` 的电池动作缺少服务端原子校验，在丢包、并发或容器归属变化时存在潜在事务风险；目前没有玩家报告或复现证据证明它必然不同步。
- 自定义穿戴槽在该 B42.17 参考中成立，不能证明 B42.19 所有物品定义和第三方服装 MOD 都兼容。

## 对 GodSystem 的应用

- 不再追求单个系统空间终端超过 49；若要扩总空间，应明确设计成多个独立容器或虚拟服务器仓库，并向玩家说明 UI 形态。
- 仅为需要减重的实例保存 `baseWeight` 和自定义倍率，避免调用全局 `ScriptItem:DoParam()`。
- MP 减重应由服务端按 ID 验证物品归属和容器链，修改实例后显式同步；客户端不得提交最终重量。
- 物品离开特殊容器时应在同一次受控转移后恢复，不能依赖附近扫描最终补救。
- 电池、能源或嵌套容器转移应复用原版 transfer action 与服务端容器同步，必要时增加 operation ID 和失败恢复。
- 若实现虚拟仓库，数据应保存 item snapshot 或服务器真实库存，而不是伪装成一个超上限 `ItemContainer`。

## 待验证内容

- `待实机验证`：B42.19 中五个自定义穿戴位置同时装备、重进和多人观察的稳定性。
- `待实机验证`：压缩物品从法宝直接移动到主库存、普通背包、地面和另一玩家后何时恢复。
- `待实机验证`：两个相同 fullType 实例处于不同压缩倍率时，全局 `ScriptItem` 修改造成的显示和重量结果。
- `待实机验证`：高延迟 MP 下 EnergyHub 电池批量装卸是否重复、丢失或回滚。
- `待实机验证`：深层嵌套和大量物品时每分钟服务端递归扫描的耗时。

## 联网检索信息

- 搜索词：`Project Zomboid Cultivation Storage Artifacts Tofu 0.1.10 B42.17 multiplayer weight`
- 建议核对：Workshop 联机说明、作者对减重同步的解释、B42.19 `InventoryItem.setActualWeight`/`setCustomWeight` 行为和自定义 BodyLocation 变更。
