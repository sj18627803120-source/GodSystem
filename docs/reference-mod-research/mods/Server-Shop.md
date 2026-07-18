# Server Shop 研究报告

## 身份与版本

- 名称：Server Shop
- MOD ID：`ServerShop`
- 本地主要代码树：`42.19`
- `mod.info` 描述：B42.19 compatibility patch
- 证据强度：`B42.19 同版本证据`

## 功能地图

- `media/lua/server/ServerShopServer.lua`：余额、商品、库存、购买、车辆/动物、兑换券、管理员和离线队列。
- `ServerShopStatsServer.lua`：玩家收入、支出和击杀统计。
- `ServerShopKillPoints.lua`：击杀计数同步和奖励。
- `ServerShopAudit.lua`：按玩家、余额和兑换行为写服务器日志。
- `ServerShopZombieVoucherDrops.lua`：僵尸兑换券掉落。
- `media/lua/client/ServerShopUI.lua`：商城 UI 和购买请求。
- `ServerShopRedeemContext.lua`：兑换券右键入口和回包提示。
- `ServerShopOfflineDeliveryClient.lua`：上线 hello 握手。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `ServerShopServer.lua`，`getBalance()`/`setBalance()` | 余额优先存服务器全局 ModData，按 username/OnlineID key 持久化，并同步角色 ModData 作为兼容副本。 |
| `代码确认` | 同文件，`Commands.buy()` | 服务端用 listing ID 查真实条目和价格，先预留有限库存，再扣余额和发货。 |
| `代码确认` | 同文件，购买失败路径 | XP 无效、车辆/动物生成失败和未知类型会恢复库存并以 `reason="refund"` 退款。 |
| `代码确认` | 同文件，`grantItems()` | 服务端 `AddItem()` 后调用 `sendAddItemToContainer()`；地面发货先同步移除再投放世界。 |
| `代码确认` | 同文件，`Commands.redeem()` | 服务端递归查真实兑换券，限制并发兑换，校验所有者，先写 `SS_redeemed` 再删除并同步，最后加余额。 |
| `代码确认` | 同文件，离线兑换券队列 | 同时通过 `OnCreatePlayer` 和客户端 `hello` 尝试投递，降低登录时序漏发。 |
| `代码确认` | `ServerShopAudit.lua` | 购买、退款、余额、管理员和兑换异常可写独立审计日志。 |
| `代码确认` | `ServerShopKillPoints.lua` | 击杀奖励使用客户端累计击杀差值上报并限制单次增量，不是严格服务器击杀归属证明。 |

## 单人与多人数据流

- 客户端只提交商品 ID、兑换数量和管理请求；服务端查商品、价格、余额和真实物品。
- 商品列表、有限库存、余额和离线队列均由服务端保存或生成。
- 库存增删、车辆/动物生成和兑换券 ModData 变化有显式同步。
- 关键结果通过 `sendServerCommand()` 回到 UI；客户端可显示余额和错误，但不是可信状态来源。
- 该来源以 MP 服务器商店为中心，不提供 YeseMarket 式完整 SP 本地后端复用。

## 可采用机制

- 购买顺序：查条目与余额、预留库存、扣款、发货、失败恢复库存和退款、记录审计。
- 退款使用明确原因，避免被统计成新收入。
- 兑换类消耗品在删除前写一次性标记，并增加玩家级处理中锁。
- 上线事件与客户端 hello 双重触发离线投递，处理服务器玩家对象未就绪的时序问题。
- 余额主存储与角色兼容副本分离，死亡后仍可保留账户资产。
- 管理员 UI 是否可见不构成权限，服务端再次检查 access level。

## 风险与限制

- 没有通用于所有付费命令的持久化 operation ID 和结果缓存；兑换锁仅覆盖当前在线进程内并发。
- `代码确认`：普通 ITEM 分支调用 `grantItems()` 后直接报告成功，没有逐件复查实际发放数量；目录预验证降低风险但不等于事务验证。
- `合理推断`：以 username 为主 key 时，服务器改名、大小写策略或账户迁移需要额外规则。
- 击杀奖励信任客户端累计击杀差值，只做增量上限保护，不适合作为强反作弊依据。
- 部分服务端错误仍直接发送完整字符串；GodSystem 应继续使用结构化 code/args 本地化。

## 对 GodSystem 的应用

- GodSystem MP 经济继续以服务端重算余额、价格、库存和物品归属为准。
- 付费/消耗命令比 Server Shop 更进一步：使用 operation ID、请求指纹和持久化结果缓存处理超时重试。
- 离线奖励、待领取物品和登录恢复应采用 `OnCreatePlayer + hello` 的双入口。
- 交易失败必须保留原银行/现金扣款拆分并原路退款，退款不计消费和收入统计。
- 关键经济操作应写审计事件，至少包含玩家 key、动作、金额、物品和结果 code。

## 待验证内容

- `待实机验证`：B42.19 高延迟下有限库存购买的同时请求行为。
- `待实机验证`：服务器重启发生在扣款与发货之间时的恢复能力。
- `待实机验证`：大量离线兑换券和轮换商品状态的 ModData 体积与启动时间。

## 联网检索信息

- 搜索词：`Project Zomboid Server Shop zPoints B42.19 compatibility patch`
- 建议核对：Workshop B42.19 更新说明、专用服务器安装要求和已知兑换券问题。
