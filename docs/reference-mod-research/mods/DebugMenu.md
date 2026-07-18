# DebugMenu 研究报告

## 身份与版本

- 名称：调试菜单 (DebugMenu) B42
- MOD ID：`QNWDebugMenuB42`
- 本地代码树：`42`
- 最低版本声明：`42.13`
- 证据强度：`旧 B42 参考`

## 功能地图

- `media/lua/client/DebugMenuCore.lua`：延迟初始化、库存和世界右键入口。
- `DebugMenuVehicle.lua`：车辆钥匙、热接线、部件、锈蚀、整车修复和删除入口。
- `DebugMenuInventory.lua`：物品生成、修复和库存操作。
- `DebugMenuStatus.lua`、`DebugMenuMode.lua`：角色状态和持续调试模式。
- `client/IS/`：物品、车辆、地图和笔刷类调试 UI。
- `server/DebugMenuServerCommand.lua`：天气、时间、僵尸生成和车辆部件安装/拆卸的管理员 handler。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `client/DebugMenuVehicle.lua`，`QNW_DMVehicle.repairAll()` | 整车修复没有自建修复算法，而是发送原版模块命令 `sendClientCommand(player, "vehicle", "repair", {vehicle=id})`。 |
| `代码确认` | 同文件，`repair()`、`condition()` | 单部件修复使用 `vehicle/repairPart`；直接条件修改使用 `vehicle/setPartCondition`。 |
| `代码确认` | `server/DebugMenuServerCommand.lua` | 自定义服务端命令先检查管理员权限，再通过 `getVehicleById()` 获取真实车辆。 |
| `代码确认` | 同文件，`installPart`/`uninstallPart` | 修改车辆部件后调用 `VehicleUtils.callLua()` 完成回调、`transmitPartItem()` 和 `mechanicActionDone` 对象变化。 |
| `代码确认` | `client/IS/ISItemGenerateUI.lua` | 枚举 `getScriptManager():getAllItems()`，创建预览实例前过滤 `getObsolete()` 和 `isHidden()`。 |
| `代码确认` | `client/IS/ISItemGenerateTable.lua` | MP 发物品走服务器 `/additem` 命令；非客户端环境才直接 `instanceItem()` 后加入库存。 |
| `代码确认` | `client/DebugMenuCore.lua` | 使用 `OnTick` 完成延迟安装后移除初始化函数，再注册库存和世界右键事件。 |

## 单人与多人数据流

- 整车修复、热接线、取钥匙和车辆状态变化复用游戏已有 `vehicle` 命令模块。
- DebugMenu 自己的天气、时间和安装/拆卸命令由服务端检查管理员权限。
- 物品生成在 MP 中发送服务器控制台命令，在 SP 中才直接创建实例。
- 该 MOD 的权限模型面向管理员调试，不包含普通玩家付费、消耗品或事务退款。

## 可采用机制

- 优先复用原版服务器命令，不重新实现已经存在的车辆修复和部件流程。
- 车辆请求只发送 ID，服务端获取真实对象并执行修改。
- 部件安装/拆卸不仅设置 `InventoryItem`，还执行车辆脚本的 `complete` 回调和同步。
- 枚举可生成物品时使用 `obsolete/hidden` 结构化过滤。
- 一次性初始化任务完成后从 `OnTick` 移除，避免永久空转。

## 风险与限制

- Debug 接口默认假设管理员权限和主动操作，不能直接暴露给普通玩家。
- `代码确认`：部分 SP 路径直接修改客户端对象；GodSystem 的付费功能不能把这些路径当作 MP 权威实现。
- `合理推断`：管理员命令通常不处理扣除消耗品、失败退款和重复请求，复制到经济系统会缺失事务边界。
- `旧 B42 参考`：该版本最低为 42.13，原版 `vehicle` 命令名称和参数仍应以 B42.19 本体为最终证据。

## 对 GodSystem 的应用

- 系统车辆修复模块最终采用原版 `vehicle/repair` 命令路径，而不是客户端直接调用 `vehicle:repair()`。
- 付费模块仍需在 GodSystem 服务端先验证物品和距离，再调用原版命令或同版本修复入口；DebugMenu 只能证明修复接口，不证明收费事务。
- 商城和抽奖的脚本物品枚举继续排除 `hidden` 与 `obsolete`。
- 需要扩展车辆部件时，必须考虑 `VehicleUtils.callLua()`、部件 Item/Condition/ModData 同步，而不是只设置 condition 数值。

## 待验证内容

- `待实机验证`：B42.19 专用服务器中普通 MOD 是否可以直接调用原版 `vehicle/repair` 命令，或必须由客户端以已认证玩家发送。
- `待实机验证`：第三方车辆重写修复表或部件脚本时，原版整车修复是否能恢复缺失部件。
- `待实机验证`：管理员 DebugMenu 与 Vehicle Repair Overhaul 同时启用时的命令覆盖顺序。

## 联网检索信息

- 搜索词：`Project Zomboid QNWDebugMenuB42 vehicle repair DebugMenu`
- 建议核对：B42.19 原版 `ClientCommands` 的 `vehicle` 模块、Workshop 更新说明。
