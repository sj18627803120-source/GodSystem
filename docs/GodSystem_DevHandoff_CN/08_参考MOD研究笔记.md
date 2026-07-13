# 参考 MOD 研究笔记

本文件用于沉淀后续开发必须优先参考的本地 MOD 代码、接口和踩坑结论。每次研究出新结论，都要追加到这里。

参考 MOD 根目录：
`C:\Users\Admin\Desktop\PJ\File`

当前已知参考 MOD：

- `damnlib`
- `RuinBazaar`
- `DebugMenu`
- `TraitsPurchaseSystem`
- `Server Shop`
- `CAExtendedCategories`

## 使用原则

- 开发新功能前，先确认 Project Zomboid 版本。当前目标是 B42.19。
- 参考优先级按版本一致性决定，同版本资料优先于不同版本资料。
- 如果官方有当前开发版本的开发手册或官方示例，它是第一优先级。
- 同版本官方资料之后，再找同版本参考 MOD 里是否已有同类功能。
- 用户目前提供的参考 MOD 默认视为同版本参考，除非后续检查发现版本不一致。
- 参考 MOD 重点看目录结构、PZ 事件接口、物品脚本字段、容器/背包操作 API、UI 控件用法。
- 不直接复制大段代码或素材；只抽象思路后写到 GodSystem 自己的代码里。
- 如果参考 MOD 与 GodSystem 当前稳定逻辑冲突，优先保持 GodSystem 稳定，再小步迁移。

## 参考优先级

1. 当前目标版本的官方开发手册 / 官方示例 / 当前版本原版脚本。
2. 用户提供的同版本参考 MOD。
3. 其他同版本社区 MOD。
4. 不同版本官方资料。
5. 不同版本 MOD 或旧教程。

原则：谁和当前开发版本一致，谁优先级更高；版本一致时官方最高。

## that DAMN Library / damnlib

路径：
`C:\Users\Admin\Desktop\PJ\File\damnlib`

关键文件：
`C:\Users\Admin\Desktop\PJ\File\damnlib\42.17\media\lua\shared\Kludges\ItemTypeAndRecipeFallback.lua`

已确认作用：

- 它会遍历 `getAllItems()`，对缺少 `ItemType` 的物品脚本执行类似 `DoParam("ItemType = base:normal")` 的 fallback。
- 这解释了为什么启用 `damnlib` 后 GodSystem 系统币红字消失。
- 它不是 GodSystem 的必要依赖，只是掩盖了 GodSystem 自己物品脚本不符合 B42.19 的问题。

GodSystem 已采用的结论：

- `GodSystem_Items.txt` 中 `SystemCoin1/10/100` 已改为 `ItemType = base:normal`。
- 已补 `WorldStaticModel = Money`。
- 稳定包不包含 `damnlib`。

注意：

- 不要把 `damnlib` 打包进 GodSystem。
- 它的 Workshop 描述明确限制 repack/修改/再分发。

## RuinBazaar

路径：
`C:\Users\Admin\Desktop\PJ\File\RuinBazaar`

重点文件：

- `42\media\lua\client\RuinBazaar_Main\RuinBazaar_Main.lua`
- `42\media\lua\client\RuinBazaar_Main\RuinBazaar_Data.lua`
- `42\media\lua\client\RuinBazaar_Main\RuinBazaar_Shop.lua`
- `42\media\lua\client\RuinBazaar_Main\RuinBazaar_VendingManager.lua`
- `42\media\lua\client\RuinBazaar_Main\RuinBazaar_Recycle.lua`
- `42\media\scripts\items\RuinBazaar_test-物品.txt`
- `42\media\scripts\weapon_scripts-武器.txt`

已确认结构：

- `RuinBazaar_Data.lua` 集中放商店分类、商品、价格。
- `RuinBazaar_Shop.lua` 负责商城 UI。
- `RuinBazaar_Recycle.lua` 负责回收 UI。
- `RuinBazaar_VendingManager.lua` 统一处理容器、扣钱、发物品、回收。
- `RuinBazaar_Main.lua` 注册右键售货机入口，并打开主菜单。

可借鉴点：

- 数据表与交易管理器分离，减少 UI 里直接写交易逻辑。
- 所有扣除/发放物品集中到一个 manager，便于统一修 bug。
- 删除容器内物品时反向遍历，避免索引错乱。
- 可将交易限定在指定容器中，而不是递归扫玩家全背包。
- 商店分类、回收、抽奖、贷款等功能拆成独立 Lua 文件。
- 2026-06-14 腰包自动回收采用相同方向：限定系统腰包容器第一层，不递归扫玩家全背包。

不宜照搬点：

- UI 尺寸硬编码较多。
- 文本文件存在编码乱码。
- 部分脚本仍写 `ItemType = Normal`，对 B42.19 不是最稳写法；GodSystem 普通物品优先用 `ItemType = base:normal`。
- 不复制其贴图、模型、音效、代码资产。

对 GodSystem 的后续建议：

- 若继续扩展商城/回收，可考虑把 GodSystem 的交易容器、扣币、发物品、回收逻辑进一步整理成独立 manager 风格。
- 新增复杂功能前，先在 RuinBazaar 对应模块找事件注册和 UI 模式，再设计 GodSystem 自己版本。

## DebugMenu

路径：
`C:\Users\Admin\Desktop\PJ\File\DebugMenu`

用途：

- 适合参考调试菜单如何发物品、调用 PZ 调试/物品生成接口。
- 曾用于对比 `AddItem(fullType)` 与对象添加路径。

注意：

- 只参考接口，不把调试功能直接暴露给正式版本玩家。

## TraitsPurchaseSystem

路径：
`C:\Users\Admin\Desktop\PJ\File\TraitsPurchaseSystem`

用途：

- 后续继续打磨天赋购买/移除时优先参考。
- 重点查天赋枚举、购买校验、冲突处理、UI 提示和存档处理。

注意：

- GodSystem 当前天赋仍属高风险功能，不能承诺所有原版天赋效果立即完全生效。

## Server Shop

路径：
`C:\Users\Admin\Desktop\PJ\File\Server Shop\42.19`

用途：

- 作为 B42.19 同版本服务器商店 / 多人模式适配参考。
- 重点参考它的客户端/服务端分层、服务端权威交易、余额同步、离线发货、管理员操作和审计日志。
- 只参考接口和架构，不复制代码、图片、贴图或完整实现。

已确认版本信息：

- `mod.info` 写明 `id=ServerShop`，`versionMin=42.19`。
- `sandbox-options.txt` 提供服务器选项：货币名称、在线发点频率、每次发点数、发货方式、兑换券绑定用户、离线兑换券、击杀奖励、丧尸掉券等。
- `ServerShop_items.txt` 里的兑换券物品使用 `ItemType = base:normal`，符合当前 B42.19 稳定写法。

关键文件：

- `media\lua\server\ServerShopServer.lua`：服务端核心，处理余额、商品加载、购买、退款、发物品/车/动物、管理员发点/发券、离线队列、事件注册。
- `media\lua\server\ServerShopStatsServer.lua`：服务端统计存储和同步。
- `media\lua\server\ServerShopKillPoints.lua`：击杀奖励，服务端按客户端 kill 计数差值发点并做上限保护。
- `media\lua\server\ServerShopAudit.lua`：服务端审计日志，写入 `Zomboid/Lua/Shop_Server/...`。
- `media\lua\server\ServerShopZombieVoucherDrops.lua`：服务端丧尸掉兑换券。
- `media\lua\client\ServerShopUI.lua`：客户端商店 UI，只请求加载、余额、购买，并接收服务端返回。
- `media\lua\client\ServerShopRedeemContext.lua`：客户端右键兑换入口，实际发点和删券由服务端做。
- `media\lua\client\ServerShopOfflineDeliveryClient.lua`：登录后发送 `hello` 握手，防止离线发货因为玩家对象/网络未就绪漏发。
- `media\lua\client\ServerShopAdminPanel.lua`：管理员 UI，客户端只发送管理命令，权限仍由服务端判定。
- `media\lua\shared\ServerShopVehicleStorageCatalog.lua`：共享车辆储物展示数据。

多人模式架构结论：

- 客户端文件用 `if not isClient() then return end` 兜底，服务端文件用 `if not isServer() then return end` 兜底。
- 核心通信模块名是 `ServerShop`。客户端用 `sendClientCommand(getPlayer(), "ServerShop", command, args)` 请求，服务端用 `Events.OnClientCommand.Add(...)` 统一分发到 `Commands[command]`。
- 服务端回包用 `sendServerCommand(player, "ServerShop", command, args)`，客户端用 `Events.OnServerCommand` 接收。
- UI 打开时会先 `Events.OnServerCommand.Remove(...)` 再 `Add(...)`，避免窗口反复打开导致事件监听叠加。
- 客户端 UI 可以显示余额、按钮可用状态和提示，但不作为可信判断；购买、扣钱、发货、退款全部由服务端重新校验。
- 余额优先存服务端全局 `ModData.getOrCreate("ServerShopBalance")`，按用户名/OnlineID 作为 key，另同步一份到 `player:getModData()["zPoints_Balance"]` 兼容旧逻辑。
- 服务端余额变动统一走 `getBalance/setBalance/addBalance/sendBalance`；增加余额时通知统计模块，退款 `reason="refund"` 不计入总收入。
- 有限库存、商品轮换等服务器状态也存服务端 ModData，并在变更后 `ModData.transmit(...)`。
- 商品购买流程是：服务端查商品 id -> 查库存 -> 查余额 -> 先预留库存 -> 扣余额 -> 尝试发货 -> 成功回包；发车/动物失败时恢复库存并退款。
- 服务端发物品时，在服务端 `inventory:AddItem(fullType)` 后调用 `sendAddItemToContainer(inv, item)`；删除物品时调用 `container:Remove(item)` 后调用 `sendRemoveItemFromContainer(container, item)`。
- 兑换券兑换不是信任客户端选中的物品，而是服务端递归扫描玩家携带容器，确认券类型、价值、归属、是否已兑换，再先标记 `SS_redeemed` 后删除并发点，防止重复兑换。
- 离线发券存服务端队列 `ServerShop.OfflineVoucherQueue`，玩家上线时 `OnCreatePlayer` 和客户端 `hello` 握手都会尝试投递，降低 MP 登录时序问题。
- 管理员命令在服务端使用 `player:isAccessLevel("Admin")` / `Moderator` 判断；客户端是否显示管理员 UI 只影响入口，不影响权限。
- 审计日志按日期和用户写入服务端 Lua 文件夹，购买、退款、管理员调整、兑换异常都可以记录，适合服务器排查经济异常。

## CAExtendedCategories

路径：
`C:\Users\Admin\Desktop\PJ\File\CAExtendedCategories`

用途：

- 作为 B42 同版本物品分类、标签识别、BodyLocation 过滤参考。
- 当前重点用于修正 GodSystem 抽奖奖池和经济候选池里混入隐藏/调试/内部物品的问题。
- 只参考它的判定依据，不直接复制整套分类系统。

关键文件：

- `common\media\lua\shared\CAExtendedCategories\CAEC.lua`
- `common\media\lua\shared\CAExtendedCategories\CAEC_Utils.lua`
- `common\media\lua\shared\CAExtendedCategories\Categorizers\CAEC_Apparel.lua`

已确认机制：

- `CAEC.CategorizeAllItems()` 遍历 `getAllItems()`，逐个调用 `CAEC.CategorizeItem(item)`。
- `CAEC.CategorizeItem()` 会读取静态覆盖、缓存、实例专用分类，再走分类器。
- `Utils.HasAnyTag(item, tags)` 使用 `item:getTags()` 和 `item:hasTag(tag)`，适合作为 GodSystem 后续分类优化参考。
- `Utils.CreateInstanceIfNeeded()` 会调用 `instanceItem(item)` 生成临时物品实例并缓存。这个方案分类能力强，但对 GodSystem 抽奖奖池来说可能过重，暂不建议默认照搬。
- `CAEC_Apparel.lua` 的服装验证排除 `ItemBodyLocation.WOUND`、`ItemBodyLocation.ZED_DMG`、`ItemBodyLocation.BANDAGE`，证明这些 body location 不应进入普通服装/装备分类。

对 GodSystem 的结论：

- 抽奖、商店、回收这类经济池不能只用 `FindItem(fullType)` 判断物品存在。
- 官方同版本脚本已经使用 `not item:getObsolete()` 和 `not item:isHidden()` 过滤玩家可见物品；GodSystem 应优先采用同样的基础过滤。
- `Base.ZedDmg_*` 在官方脚本中是 `DisplayCategory = ZedDmg`、`BodyLocation = base:zeddmg`、`WorldRender = false`、`hidden = true` 的内部物品，必须从抽奖奖池排除。
- 名称黑名单只能作为兜底，优先级低于官方 `hidden/obsolete` 字段，避免误伤第三方 MOD 的真实物品。

对 GodSystem 多人模式的直接启发：

- GodSystem 当前 Lua 主要在 `media\lua\client` 和 `media\lua\shared`，没有服务端核心模块；多人适配不能只加 UI，需要新增 `media\lua\server\GodSystem_Server.lua`。
- GodSystem 当前经济是实体系统币，不应直接照搬 `zPoints` 虚拟余额；第一阶段更稳的做法是保留实体币设计，但把扣币、发币、发物品、回收删除、任务交付等操作改成服务端权威。
- 所有会改变经济或世界状态的动作都要改成客户端发请求、服务端校验后执行：商城购买、回收、腰包自动回收、任务领取/结算、家园传送扣费、临时点购买、天赋修改。
- 客户端仍可做列表、预览、确认弹窗和本地提示，但服务端必须重新检查余额、物品是否存在、容器归属、数量、商品是否有效、目标坐标是否安全。
- MP 适配时要建立统一命令模块，例如 `GodSystem` / `GodSystemMP`，并为每个命令定义输入、服务端校验、成功回包、失败回包。
- 服务器适配后需要新增审计日志，至少记录系统币变化、商城购买、回收收入、任务奖励/惩罚、管理员修正、传送扣费和失败退款。

不宜照搬点：

- Server Shop 是虚拟点数商店，GodSystem 稳定版是实体系统币经济；迁移时不能直接改掉玩家当前系统币资产模型。
- Server Shop 商店 UI 体量很大，布局和素材不应复制。
- 击杀奖励通过客户端 kill 计数同步，作者也注明不是严格反作弊；GodSystem 如果做服务器严肃经济，需要更保守地对待客户端上报数据。

## YeseMarket

路径：`C:\Users\Admin\Desktop\PJ\File\YeseMarket`

版本/入口结论：
- `42\mod.info` 是单入口：`name=YeseMarket[SP/MP]`、`id=YeseMarket`。
- 该参考 MOD 证明“一个 Workshop/MOD 条目同时支持 SP/MP”是可行方向，不必拆成两个可选子 MOD。

关键文件：
- `42\media\lua\shared\YeseMarketProtocol.lua`：统一定义 `Module`、C2S、S2C 命令名。
- `42\media\lua\client\YeseMarket\YeseMarketCore.lua`：`SendMarketCommand(command,args)` 统一发送命令；SP 走本地 dispatcher，MP 走 `sendClientCommand`。
- `42\media\lua\client\YeseMarket\YeseMarketSinglePlayer.lua`：单人模式本地加载 server 模块，复用服务端业务层；`SendToPlayer` 被重定向到客户端状态处理器。
- `42\media\lua\server\YeseMarketServer\YeseMarketServerEvents.lua`：服务端 `Events.OnClientCommand` 分发到 handlers 表。
- `42\media\lua\server\YeseMarketServer\YeseMarketServerCore.lua`：服务端 ModData、玩家 key、`sendServerCommand`、库存同步、DirtyUI 等通用工具。
- `42\media\lua\client\YeseMarket\YeseMarketEvents.lua`：客户端接收服务器状态并刷新 UI。

架构结论：
- YeseMarket 的理想结构是“同一套服务端业务层同时服务 SP/MP”：MP 用网络命令，SP 本地加载 server 模块并直调 handler。
- GodSystem 当前采用更保守的第一阶段方案：SP 维持 v1.15.6 稳定本地逻辑，MP 额外启用网络桥和服务端权威结算。原因是 GodSystem 原核心全部在 client 文件，完整改成 YeseMarket 式统一后端会大幅重构，风险高。
- 未来如果要继续提高一致性，可逐步把 GodSystem 的经济/任务/传送逻辑抽成 shared/backend，再让 SP 与 MP 共享同一套 handler。

接口结论：
- B42.19 参考里同时存在 `sendClientCommand(player, module, command, args)` 与 `sendClientCommand(module, command, args)` 写法；GodSystem 网络桥目前先尝试带 player 的写法，失败后 fallback 到不带 player 写法。
- 服务端发物品后调用 `sendAddItemToContainer(inv, item)`；删物品后调用 `sendRemoveItemFromContainer(container, item)`；同时可用 `sendServerCommand(player, "ui", "DirtyUI", {})` 和 `container:setDrawDirty(true)` 辅助刷新。
- 客户端 UI 可以预览和显示，但所有会改变经济/库存/角色/位置的动作必须在服务端重验。

对 v1.16.1 的直接影响：
- 采用 `YeseMarket` 的单入口思路，但暂不采用其“单机本地加载服务端业务层”的完整重构。
- 采用 `YeseMarket` 的 command handler 表和异常隔离思路：服务端分发必须包 `pcall`，并在 handler 后保证 state 能回包。
- 采用 `Server Shop 42.19` 的带 player `sendClientCommand` 写法作为第一尝试，同时保留 `YeseMarket` 的三参数写法 fallback。
- 多人握手必须可重试，不能只依赖一次 `OnGameStart`；这点与 Server Shop 离线发货 hello 机制、YeseMarket 状态请求机制一致。

## 当前游戏本体文件索引 / B42 unstable

本地安装路径：
`C:\APP\Steam\steamapps\common\ProjectZomboid`

当前 Steam manifest 结论：

- `appmanifest_108600.acf` 显示 `BetaKey=unstable`。
- `buildid=23504596`。
- `SVNRevision.txt` 为 `964`。
- 当前本体包含 `projectzomboid.jar`、`media\lua`、`media\scripts`、`media\luaexamples`、`mods\examplemod`。

本体文件参考优先级：

- 当前版本本体 `media\lua` / `media\scripts` / `mods\examplemod` 可视为同版本官方/准官方参考，优先级高于社区 MOD。
- 旧教程和不同版本 MOD 只作为弱参考；遇到冲突时按当前本体文件为准。
- 为节省 token，后续不要全文读取本体大目录。先用 `rg` 查目标 API，再只读命中的几十行上下文。

重要目录：

- `media\lua\client`：原版客户端 UI、上下文菜单、车辆 UI、角色界面等。
- `media\lua\server`：原版服务端命令处理、物品发放/删除同步、车辆/农业/钓鱼/觅食等服务端系统。
- `media\lua\shared`：客户端和服务端都可能加载的通用工具、移动物体、日志系统、LuaNet、配方/物品相关通用逻辑。
- `media\scripts`：原版物品、配方、车辆、模型、声音等脚本定义。当前约 1004 个 `.txt`，新增 GodSystem 物品字段应优先对照这里。
- `media\luaexamples`：官方 Lua 示例，包含 UI 示例和 timed action 示例。
- `mods\examplemod`：官方示例 MOD 结构，可用于确认 `mod.info`、资源路径、Lua/音乐/UI 素材放置方式。

当前本体 Lua 粗略规模：

- `media\lua\shared` 约 1034 个文件。
- `media\lua\client` 约 735 个文件。
- `media\lua\server` 约 268 个文件。

常用事件索引：

- 本体中出现较多的事件包括 `OnGameStart`、`OnTick`、`OnGameBoot`、`OnCreatePlayer`、`OnPlayerUpdate`、`OnZombieDead`、`EveryHours`、`EveryTenMinutes`、`OnClientCommand`、`OnServerCommand`。
- GodSystem 后续新增计时/后台同步优先考虑低频事件或自身节流，不要在 `OnTick` 做重扫描。
- UI 初始化/重绘相关可查 `OnGameStart`、`OnResolutionChange`、`OnPreUIDraw`、原版 `ISUI` 文件。

多人通信官方本体索引：

- 服务端总入口：`media\lua\server\ClientCommands.lua`。
  - 其中有 `ClientCommands.OnClientCommand = function(module, command, player, args)`。
  - 文件末尾使用 `Events.OnClientCommand.Add(ClientCommands.OnClientCommand)`。
  - 这是 GodSystem 服务端命令分发签名的重要同版本依据。
- 客户端总入口：`media\lua\client\ServerCommands.lua`。
  - 其中有 `ServerCommands.OnServerCommand = function(module, command, args)`。
  - 文件末尾使用 `Events.OnServerCommand.Add(ServerCommands.OnServerCommand)`。
- 通用网络辅助：`media\lua\shared\Util\LuaNet.lua`。
  - 同时展示了 `sendServerCommand(player, module, command, args)`、`sendServerCommand(module, command, args)`、`sendClientCommand(module, command, args)` 等多种调用形态。
  - GodSystem 目前保留带 player 与不带 player fallback 是合理的。

库存/物品同步官方本体索引：

- `media\lua\server\ClientCommands.lua` 有多个同版本样例：
  - 服务端删除物品：`container:Remove(item)` 后调用 `sendRemoveItemFromContainer(container, item)`。
  - 服务端发物品：`inventory:AddItem(fullType)` 后调用 `sendAddItemToContainer(inventory, item)`。
  - 多件物品可参考农业系统中的 `sendAddItemsToContainer(player:getInventory(), items)`。
- `media\lua\server\Farming\SFarmingSystem.lua` 展示 `AddItems(...)` 后 `sendAddItemsToContainer(...)`。
- GodSystem 购买、回收、任务提交、测试发币、腰包操作等 MP 实物变动应继续按这个模式做同步。

物品脚本字段参考：

- B42 普通自定义物品继续优先使用 `ItemType = base:normal`。
- 新物品字段不要凭旧 B41 记忆写，优先在 `media\scripts` 查同类原版物品，再查同版本参考 MOD。
- 若 `inventory:AddItem(fullType)` 得到 nil 或触发 Java NPE，第一优先检查脚本模块名、fullType、`ItemType`、图标/模型字段和 `getScriptManager():FindItem(fullType)`。

UI 官方索引：

- 传统 ISUI 控件主要在 `media\lua\client\ISUI` 及各功能目录的 `ISUI` 子目录。
- 新 UI 示例在 `media\luaexamples\ui`，包括 `ui.lua`、`uiHelpers.lua`、`hotkeyBar.lua`、`actionUIElement.lua`。
- GodSystem 当前仍采用传统 ISUI 风格；若以后要大改 UI，可先研究 `media\luaexamples\ui`，但不要在稳定功能上贸然混用新旧 UI 框架。
