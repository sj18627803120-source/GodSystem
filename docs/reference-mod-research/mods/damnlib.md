# that DAMN Library 研究报告

## 身份与版本

- 名称：that DAMN Library
- MOD ID：`damnlib`
- 作者：KI5 / bikinihorst
- 本地主要代码树：`42.17`
- MOD 版本：`0.9862b`
- Workshop ID：`3171167894`（来自源码许可头）
- 证据强度：`旧 B42 参考`
- 许可边界：源码头明确禁止重新分发、重打包和修改，因此本仓库只保留接口研究摘要。

## 功能地图

- `media/lua/shared/DAMN_Shared.lua`、`DAMN_Helpers.lua`：框架命名空间和通用帮助函数。
- `media/lua/client/DAMN_Client.lua`、`media/lua/server/DAMN_Server.lua`：客户端/服务端命令总线。
- `media/lua/server/Commands/`：车辆部件、装甲、ModData 和物品发放 handler。
- `media/lua/shared/Kludges/ItemTypeAndRecipeFallback.lua`：B42.13 物品脚本兼容修补。
- `media/lua/server/DAMN_Spawns.lua`：持久化车辆生成点和格子加载处理。
- `media/lua/server/DAMN_ContainerAccess.lua`：车辆储物部件的门、座位和区域访问规则。
- `media/lua/client/Hooks/`：车辆径向菜单、机械提示、拖车兼容和进出车辆动画扩展。
- `media/lua/server/Crafting/DAMN_damnCraft.lua`：轮胎、车体部件拆解和修理回调。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `shared/Kludges/ItemTypeAndRecipeFallback.lua`，`Events.OnGameBoot` | 遍历 `getAllItems()`；缺少 `ItemType` 时通过 `Item:DoParam()` 写入 `base:normal` 或 `base:literature`，并为特定杂志补配方和标签。 |
| `代码确认` | `client/DAMN_Client.lua`，`DAMN:sendClientCommand()` | 请求可附加 `_vehicleId=vehicle:getId()`，然后使用 `sendClientCommand(getPlayer(), module, method, args)`。 |
| `代码确认` | `server/DAMN_Server.lua`，`Events.OnClientCommand` | 服务端按模块和 `DAMN.ServerHandlers[command]` 分发，并通过 `getVehicleById()`还原车辆对象。 |
| `代码确认` | `server/Commands/DAMN_Items.lua`，`DAMN:spawnAndSendItem()` | 服务端 `instanceItem()` 后加入真实玩家库存，并调用 `sendAddItemToContainer()`；同时写物品生成日志。 |
| `代码确认` | `server/Commands/DAMN_Armor.lua`、`DAMN_Parts.lua` | 修改车辆部件后分别调用 `transmitPartCondition()`、`transmitPartItem()` 或 `transmitPartModData()`。 |
| `代码确认` | `server/DAMN_Spawns.lua` | 使用全局 ModData 记忆生成点，并在 `LoadGridsquare` 时检查；变化后调用 `ModData.transmit()`。 |
| `代码确认` | `client/DAMN_Client.lua` | 只在玩家进入相关车辆后注册 `OnPlayerUpdate`，离车时移除，避免无条件常驻车辆扫描。 |
| `作者声明` | 各 Lua 文件许可头 | 作者将该 MOD 标为不可重打包、不可修改的受限作品。 |

## 单人与多人数据流

- 客户端将普通参数和稳定车辆 ID 发送到统一命令模块；服务端重新解析车辆，再调用对应 handler。
- 服务端物品发放、车辆部件状态和持久化生成点都有显式同步调用，不依赖 UI 自行刷新。
- 客户端只接收 `that_damn_lib` 模块下已注册的 `DAMN.ClientHandlers` 回包。
- `ItemTypeAndRecipeFallback` 位于 shared 且在 `OnGameBoot` 执行，意味着两端都可能修改脚本定义；它不是一次服务器状态回包。

## 可采用机制

- 用 handler 表统一分发客户端命令，避免巨型 `if/elseif` 命令文件。
- 网络参数发送对象 ID，服务端重新获取真实车辆或物品，不传递 Lua/Java 对象本身。
- 服务端改变库存或车辆状态后调用对应的显式同步 API。
- 高频事件按状态动态注册和移除；只有玩家处于相关车辆中才运行更新逻辑。
- 持久化世界生成点使用全局 ModData，并在格子加载事件中增量处理。
- 车辆容器访问将座位、区域、门状态和部件是否存在拆成清晰的纯判断函数。

## 风险与限制

- `合理推断`：启动时为所有缺字段物品执行 `DoParam()` 能掩盖其他 MOD 的脚本错误。GodSystem 应修正自己的 `ItemType`，不能把 damnlib 当作必要依赖。
- `代码确认`：多个 Hook 会覆盖或扩展原版全局函数，例如拖车查找和车辆菜单；大型框架之间存在补丁顺序冲突的可能。
- `代码确认`：fallback 和脚本 tweaker 修改的是全局 ScriptItem，而不是单个物品实例，不适合实现临时重量、临时伤害等实例能力。
- `旧 B42 参考`：42.17 的车辆事件、部件同步和 crafting 回调在 B42.19 使用前仍需对照原版。
- 许可明确禁止复制实现和资源，只能借鉴架构。

## 对 GodSystem 的应用

- 系统币已显式声明 `ItemType = base:normal`，不再依赖 fallback 修补。
- MP 发物品、车辆修复和车辆部件同步继续使用服务端真实对象加显式同步。
- 新的高频能力应采用“需要时注册、结束时移除”或低频节流，而不是永久 `OnPlayerUpdate` 扫描。
- 不应使用 `ScriptItem:DoParam()` 实现某个玩家、某个容器或某件物品的临时数值变化。

## 待验证内容

- `待实机验证`：B42.19 对 42.17 DAMN 自定义进出车辆动画和拖车 Hook 的兼容性。
- `待实机验证`：服务端 handler 抛错时是否存在统一异常隔离和客户端失败回包。
- `待实机验证`：大量 KI5 车辆同时存在时，格子加载生成检查和车辆部件更新的实际服务器开销。

## 联网检索信息

- 搜索词：`Project Zomboid that DAMN Library 3171167894 KI5 0.9862b`
- 建议核对：作者 Workshop 说明、B42.19 更新记录、TIS Mod Permissions 页面。
