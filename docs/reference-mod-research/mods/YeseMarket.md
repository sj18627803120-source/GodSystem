# YeseMarket 研究报告

## 身份与版本

- 名称：YeseMarket [SP/MP]
- MOD ID：`YeseMarket`
- 作者：Dusk
- 本地代码树：`42`
- `mod.info` 未声明准确 B42 小版本
- 证据强度：`旧 B42 参考`

## 功能地图

- `media/lua/shared/YeseMarketProtocol.lua`：统一 C2S/S2C 命令常量。
- `client/YeseMarket/YeseMarketCore.lua`：客户端状态、文本、商品判断和命令入口。
- `YeseMarketSinglePlayer.lua`：SP 加载服务端模块并本地分发同一 handler。
- `server/YeseMarketServer/YeseMarketServerEvents.lua`：MP 命令映射、异常隔离和事件注册。
- `YeseMarketServerCore.lua`：ModData、玩家 key、库存同步、状态回包和批量 transmit。
- `YeseMarketServerTrades.lua`：寄售、求购、快照、回滚和待领取物品。
- 其他 server 模块：经济、抽奖、刮刮乐、车辆、动物、燃油和额外生命。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `shared/YeseMarketProtocol.lua` | 所有请求和回包名称集中定义，客户端和服务端不各写一份字符串。 |
| `代码确认` | `client/YeseMarketCore.lua`，`SendMarketCommand()` | SP 调用本地 dispatcher，MP 调用 `sendClientCommand()`，UI 使用同一命令入口。 |
| `代码确认` | `YeseMarketSinglePlayer.lua` | SP 通过 `pcall(require)` 加载服务端核心、交易、车辆等模块，并构造与 MP 一致的 handler 表。 |
| `代码确认` | `server/YeseMarketServerEvents.lua` | MP 每次命令在 `pcall` 内运行；handler 未主动发 state 时，分发器补发一次完整状态。 |
| `代码确认` | `YeseMarketServerCore.lua` | 服务器库存增删封装显式 `sendAddItemToContainer()` 和 `sendRemoveItemFromContainer()`；ModData 变化可批量 transmit。 |
| `代码确认` | `YeseMarketServerTrades.lua`，寄售流程 | 服务端从真实物品生成快照；删除中途失败会按已保存快照恢复已删除物品并退还费用。 |
| `代码确认` | 同文件，`BuyTrade()` | 先服务端扣买家余额，再按快照发货；发货失败会删除已发物品并退款，成功后才减少库存并给卖家入账。 |
| `代码确认` | 同文件，取消寄售/求购 | 卖家离线时将物品加入待领取队列；取消求购按剩余数量返还预付款。 |

## 单人与多人数据流

- SP 与 MP 共用服务端业务模块：区别只在命令传输和状态回包适配层。
- MP 服务端维护经济、玩家、市场和统计 ModData；客户端维护显示快照。
- 每个命令执行前滚动经济/抽奖状态，执行后保证 state 回包，并使用 transmit batch 减少重复同步。
- 玩家市场由服务端捕获实例快照；客户端只提供 item ID、数量和期望操作。
- 离线卖家取消寄售或求购成交后，通过 pending deliveries 延迟发放真实物品。

## 可采用机制

- 用共享协议表作为命令唯一来源，静态测试可检查 C2S 与 handler 完整对应。
- SP 本地加载同一服务端业务层，避免两套奖励、价格和回滚逻辑长期漂移。
- handler 统一异常隔离，并保证成功或失败后都有状态回包。
- 实例寄售由服务端生成快照；删除或重建失败时按快照回滚。
- 将跨玩家离线物品转为待领取队列，而不是要求卖家在线。
- 多个 ModData 更新在命令结束时批量 transmit，减少同一操作重复广播。

## 风险与限制

- 没有发现所有付费操作统一使用的持久化 operation ID；断线超时后的同请求重放仍需额外幂等层。
- `合理推断`：实例快照字段越多，兼容第三方自定义物品越好，但市场数据体积和恢复失败面也会扩大。
- SP 为击杀奖励注册 `OnPlayerUpdate` 并读取击杀差值；虽然有增量限制，仍应评估是否可换低频事件。
- 大型单体 UI 文件和大量服务端功能模块共享全局命名空间，继续扩展时需要防止加载顺序和状态耦合。
- 未声明准确 B42 小版本，网络签名和车辆接口必须用 B42.19 原版复核。

## 对 GodSystem 的应用

- GodSystem 可以逐步把稳定 SP/MP 业务抽成共享 backend，但不应为追求统一而一次重写全部稳定 SP 逻辑。
- 新协议继续集中维护，并由静态测试检查客户端命令、服务端 handler 和回包 code。
- 玩家市场或复杂物品交付应采用服务端快照、回滚和 pending delivery。
- GodSystem 仍需保留比 YeseMarket 更强的 operation ID、请求指纹和原资金来源退款记录。
- 状态同步可按 shared/player/trade 分片，避免每个操作都下发全部系统数据。

## 待验证内容

- `待实机验证`：B42.19 中 SP require 服务端目录模块的加载顺序和事件重复注册风险。
- `待实机验证`：高延迟下寄售购买超时重试是否可能重复扣款或发货。
- `待实机验证`：大量快照、求购和待领取物品长期累积时的 ModData 大小。

## 联网检索信息

- 搜索词：`Project Zomboid YeseMarket Dusk SP MP`
- 建议核对：作者发布页、目标 B42 小版本、多人市场并发测试记录。
