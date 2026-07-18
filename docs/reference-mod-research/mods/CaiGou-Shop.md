# CaiGou's Shop V2 研究报告

## 身份与版本

- 名称：CaiGou's ShopV2
- MOD ID：`CaiGou's ShopV2`
- 本地代码树：`42`
- `mod.info` 未声明准确 B42 小版本
- 证据强度：`旧 B42 参考`

## 功能地图

- `media/lua/shared/CGShopCatalogue.lua`：系统商品、回收和车辆目录。
- `shared/CGShopUtil.lua`：物品属性快照、恢复、描述和回收估价。
- `server/CGShopServer.lua`：MP 余额、商城、车辆、动物、玩家交易所、安全屋和留言板。
- `server/serverLog.lua`：按玩家和日期写交易日志。
- `client/CGShopSP.lua`：单人余额和击杀奖励。
- `client/CGShopClient.lua`：接收整份服务端状态和提示。
- `client/UI/CGTradingPostUI.lua`、`CGShopTextBoxTrading.lua`：真实物品寄售界面和请求组装。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `server/CGShopServer.lua`，`ModData.getOrCreate("CGShopServerData")` | MP 余额、商城目录、玩家市场和留言板集中存于服务器全局 ModData。 |
| `代码确认` | 同文件，`buyItem` | 服务端检查余额并负责发物品及同步，但商品单价直接使用客户端传入的 `args.price`，没有按服务端目录重新查价。 |
| `代码确认` | 同文件，`sellItem` 与 `specialSell` | 普通出售使用客户端单价；`specialSell` 则按真实物品 ID 收集整批物品，并由服务端 `calculateRecyclePrice()` 重算。 |
| `代码确认` | 同文件，`tradingPostList` | 限制单包最多 30 件，按客户端 item ID 找真实物品后删除并同步；寄售快照本身来自客户端请求。 |
| `代码确认` | 同文件，`tradingPostBuy`/`tradingPostBuyAll` | 通过包 UUID 和物品 UUID 定位快照，服务端重建物品、同步买家库存、给卖家入账并移除市场条目。 |
| `代码确认` | `shared/CGShopUtil.lua`，`getItemAttributes()` | 快照记录 full type、名称、类别、耐久、锋利度、食物状态、Drainable 余量、媒体索引和 ModData 等字段。 |
| `代码确认` | 同文件，`restoreItemAttr()` | 尝试恢复多种实例属性；`modData = attr.itemModdata` 只重绑局部变量，没有把键写回目标物品的 ModData。 |
| `代码确认` | `server/CGShopServer.lua`，`serverSendData()` | 操作后向客户端发送完整 `CGShopServerData`，不是只发送当前玩家和当前分页数据。 |
| `代码确认` | `client/CGShopSP.lua` | SP 采用角色 ModData 中的独立余额和本地击杀奖励，不复用 MP 服务端交易 handler。 |

## 单人与多人数据流

- SP 和 MP 是两套业务路径：SP 主要写玩家 ModData，MP 使用服务器全局 ModData。
- MP 客户端组织 UI 和寄售快照；服务端验证真实物品 ID并负责删除、发放、余额和日志。
- 服务端库存变动显式调用 `sendAddItemToContainer()`、`sendRemoveItemFromContainer()` 或批量删除同步。
- 市场列表使用 UUID 标识寄售包和包内单件物品，但没有持久化请求 operation ID 或完成结果缓存。

## 可采用机制

- 玩家市场需要保存物品实例快照，而不是只保存 full type。
- 服务端按真实 item ID 核对并删除寄售物品，不能相信客户端声称的数量。
- 包 UUID 和单件 UUID 分离，支持同一寄售包内部分成交。
- 寄售数量设置硬上限，防止服务器 ModData 无限增长。
- 商城、回收和玩家交易日志分类型记录，便于追查经济异常。
- 批量回收先收集并验证全部真实物品，再统一删除和结算。

## 风险与限制

- `代码确认`：普通购买、普通出售和部分玩家市场金额信任客户端传入价格；严肃经济应由服务端目录重新计算。
- `代码确认`：寄售手续费在验证所有 item ID 之前扣除，后续发现物品缺失时当前分支没有退款。
- `代码确认`：客户端提交的属性快照没有按服务端真实物品重建，存在伪造个体属性的可能。
- `代码确认`：`restoreItemAttr()` 的 ModData 赋值不会修改目标物品表，不能保证自定义 MOD 状态被恢复。
- `合理推断`：完整下发全局商城状态会随玩家、市场条目和留言增长而放大网络及客户端解析开销。
- 没有持久化幂等 transaction ID；断线重试和服务器重启后的重复请求需要额外设计。

## 对 GodSystem 的应用

- GodSystem 普通“回收并上架”仍只解锁 full type，不保存实例快照，数据量远低于真实寄售。
- 未来若做玩家市场，应由服务端从真实物品生成快照，客户端只发送 item ID、期望价格和请求 ID。
- 上架流程应先验证物品和费用，再扣款；删除失败必须按原资金来源退款。
- 市场状态应分页或按变更增量发送，不能频繁下发所有玩家和全部条目。
- GodSystem 现有批量精确回收可以继续采用“先整批验证、后统一删除”的两阶段结构。

## 待验证内容

- `待实机验证`：该版本在 B42.19 专用服务器中的真实寄售、断线和并发购买表现。
- `待实机验证`：快照字段是否足以恢复当前 B42.19 枪械部件、液体和第三方自定义耐久。
- `待实机验证`：全量 `CGShopServerData` 在大型服务器中的包大小和刷新频率。

## 联网检索信息

- 搜索词：`Project Zomboid CaiGou ShopV2 trading post CGShop`
- 建议核对：作者 Workshop 说明、寄售数量限制和 B42.19 更新记录。
