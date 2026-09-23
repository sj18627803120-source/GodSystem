# OrangeCommunityEconomy (橙子社区经济) 架构参考

> Workshop ID: 3777900792 | 作者: 溜达橙 | 规模: 240 Lua / 415 文件
> 分析版本: 2026-09-23 | 目标: 提取可借鉴模式，辅助 GodSystem 后续迭代

---

## 1. 整体架构

OCE 采用 **扁平 namespace + 服务注册** 模式，与 GodSystem 的 Runtime Installer 隔离环境形成对比：

| 维度 | GodSystem | OCE |
|------|-----------|-----|
| 命名空间 | `GodSystemServerRuntimeEnv` (setmetatable 沙箱) | `OrangeTradingModServer` (全局表) |
| 模块隔离 | `setfenv(1, runtimeEnvironment)` | 无隔离，所有服务挂载到同一表 |
| 加载控制 | Runtime Installer 幂等守卫 | `require` + `XLoaded` 标志 |
| 协议定义 | `GodSystemProtocol.C2S/S2C` 枚举 | `Protocol.C2S/S2C` 字符串常量 (~340 C2S / ~85 S2C) |
| 数据层 | 直接 ModData 读写 | AuthoritativeBuckets 内存缓存 + 批量持久化 |

**可借鉴**: OCE 的 AuthoritativeBuckets 模式——启动时全量加载到内存，写入走 `PersistBucket` + revision tracking，适合高频读写场景。GodSystem 当前每次操作直接读写 ModData，在 MP 高频交易下可能有性能瓶颈。

---

## 2. 数据层模式

### 2.1 AuthoritativeBuckets (runtime_core.lua)

```lua
-- 启动时全量加载
server.AuthoritativeBuckets[key] = deepCopy(engineBucket(key))

-- 写入时先改内存，再持久化
function server.PersistBucket(key)
    overwrite(engineBucket(key), server.AuthoritativeBuckets[key])
    bumpBucketRevision(key)
end

-- 批量去重：同一命令内的多次写入只持久化一次
server.BeginTransmitBatch()
-- ... 多次 DataBucket 写入 ...
server.EndTransmitBatch()  -- 统一 FlushPendingTransmitKeys
```

**核心价值**: 减少 ModData I/O 次数，revision tracking 支持增量同步判断。

### 2.2 输入验证工具链

```lua
server.SafeNumber(value, fallback, min, max)    -- NaN/Inf 防御
server.SafeInt(value, fallback, min, max)        -- 整数钳制
server.SafeString(value, maxLength)              -- 长度限制
server.SafeTrimmedString(value, maxLength)       -- 去首尾空白
server.SteamIdString(value)                      -- 17位数字 Steam ID 验证
server.ClampCoins(value)                         -- 货币范围钳制 [0, MAX_BALANCE]
server.ExactCoinAmount(value, min, max)          -- 精确金额验证（拒绝浮点误差）
```

**可借鉴**: GodSystem 的输入验证分散在各模块，可考虑抽取统一的 `Safe*` 工具链到 shared 层。

### 2.3 玩家记录归一化 (normalizePlayerRecord)

OCE 在每次读取玩家数据时执行全字段归一化，修复缺失/错误类型字段：

```lua
local function normalizePlayerRecord(data)
    data.coins = server.NormalizeAccountBalance(data.coins)
    data.flowDay = server.SafeInt(data.flowDay, 0)
    data.flowEvents = type(data.flowEvents) == "table" and data.flowEvents or {}
    -- ... 50+ 字段归一化 ...
    return data
end

-- 弱表缓存避免重复归一化
local normalizedPlayerRecords = setmetatable({}, { __mode = "k" })
```

**可借鉴**: "读时修复" 模式比 "写时保证" 更适合 MOD 场景——数据可能来自旧版本、手动编辑或损坏的 ModData。GodSystem 的状态归一化主要在写入时做，读时假设数据正确。

---

## 3. 网络层模式

### 3.1 域订阅 (state_sync.lua, 1083 行)

OCE 的状态同步采用 **域订阅** 模式，而非 GodSystem 的全量推送：

```lua
-- 玩家只订阅关心的域
SubscribeStateDomain(player, "trade")
SubscribeStateDomain(player, "auction")

-- 广播只发给订阅者
function QueueDomainBroadcast(domain)
    -- hash-based stagger delay: 500 + hash(domain) % 1001 ms
    -- 分散到不同 tick 执行，避免 burst
end

-- revision-gated: 同 revision 5分钟内不重发
function ShouldSendStateRevision(player, domain, revision)
    -- 如果 revision 相同且未超 heartbeat interval (300s)，跳过
end
```

**可借鉴**: GodSystem 的 `EconomySnapshot` / `EconomyDelta` 是全量/增量二层模式，但没有域订阅。如果未来增加更多子系统（拍卖、股票等），域订阅可以减少不必要的带宽。

### 3.2 声明式同步回复 (Reply 模式)

```lua
-- 命令处理器返回声明式 sync 表
Reply(player, "ok", {}, {
    player = true,                    -- 刷新玩家状态
    accountDelta = { pendingDeliveries = true },  -- 只刷新特定字段
})
```

**可借鉴**: 相比 GodSystem 手动调用 `SendState` / `SendEconomyDelta`，声明式 sync 表更不容易遗漏或重复发送。

### 3.3 快照差分 (sync_private.lua)

交易列表使用 snapshot-diff 模式：

```lua
-- 缓存上一次快照
previousTradeRows = deepCopy(currentRows)

-- 计算 delta
function BuildTradeDelta()
    local upserts, removed = {}, {}
    for _, row in ipairs(currentRows) do
        local sig = tradeRowSignature(row)
        if not previousSignatures[sig] then table.insert(upserts, row) end
    end
    -- ... 计算 removed ...
    return upserts, removed
end
```

**可借鉴**: GodSystem 的商城目录传输使用分页 chunk 模式，但玩家交易列表、任务完成记录等可以用 diff 模式减少传输量。

---

## 4. 命令路由模式

### 4.1 register() 批量注册

```lua
local routes = {}

local function register(names)
    for _, name in ipairs(names) do
        local wireName = Commands[name]
        local implementation = OrangeTradingModServer[name]
        if type(wireName) == "string" and type(implementation) == "function" then
            routes[wireName] = implementation
        end
    end
end

register({ "BuyGoods", "BuyBlackMarket", "Recycle", "RecycleAllToday" })
register({ "RequestTaskState", "AcceptTask", "SubmitTaskItems", ... })
```

**对比**: GodSystem 的 RouterConfig 使用显式 if-else 分发，OCE 的 register() 更简洁但调试时堆栈较深。

### 4.2 命令分类节流

```lua
local readOnlyCommands = {
    RequestState = true, RequestDomainState = true, ...  -- 30 个
}
local lightweightCommands = {
    RequestVehicleEntryPermit = true, ClaimZombieCurrencyReward = true, ...  -- 9 个
}

-- dispatch 中根据分类决定是否执行经济滚动/节流
if not readOnlyCommands[command] then
    RollPlayerFlowData(data)  -- 记录活跃
end
```

**可借鉴**: GodSystem 的 `StateCommands` 只做节流，没有区分 "只读" 和 "轻量"。增加分类可以更精细地控制副作用。

### 4.3 Action Request Guard (action_request_guard.lua, 81 行)

高风险操作的防重复提交：

```lua
-- 策略表：每命令一个冷却时间
local policies = {
    CreateBountyOrder = 2000,
    SubmitCommunityTreasuryDonation = 3000,
}

function S.CheckHighRiskActionRequest(player, command, raw)
    -- 1. 检查冷却时间
    local lastAt = lastAcceptedAt[playerKey .. "\31" .. command]
    if nowMs() - lastAt < interval then return false, "rate_limited" end

    -- 2. 检查 requestId 去重
    local seenIds = requestHistory[playerKey .. "\31" .. command]
    if seenIds[raw.requestId] then return false, "duplicate" end

    return true, nil, requestId
end
```

**对比**: GodSystem 的 `TransactionOps` 使用指纹去重（opId + payload hash），OCE 使用 requestId + 冷却时间。两者互补——指纹防重放，冷却防洪泛。

---

## 5. UI 架构模式

### 5.1 Shell + Page Registry + Store

```
client/ui/
  workbench/shell_window.lua  -- 主窗口 ISPanel
  bootstrap.lua               -- 入口，require 所有模块
  page_registry.lua           -- 页面注册表
  store.lua                   -- 状态快照（读全局表）
  actions.lua                 -- 命令发送（验证 + 发送）
  modal_layer.lua             -- 模态层管理
  pages/                      -- 37 个页面
  dialogs/                    -- 11 个对话框
  components/                 -- 5 个复用组件
```

**核心模式**:
- **Shell**: 单例 ISPanel，左侧导航栏 + 右侧内容区
- **Page Registry**: `Register(pageId, factory)` + `Create(pageId, context)` — 工厂函数按需创建页面
- **Store**: `Snapshot(player)` 从全局可变表组装一致状态
- **Actions**: `Send(command, payload)` 验证协议 + 发送

**对比**: GodSystem 的 UI 使用浮动按钮 + 直接创建面板模式，没有页面注册表和 Store 层。OCE 的模式更适合多页面应用，但 GodSystem 的当前规模（终端 + 装备 + 商城）用浮动按钮更轻量。

### 5.2 状态缓存与事件驱动

```lua
-- event_handlers.lua 监听 S2C 消息，更新全局表
OrangeTradingMod.PlayerData = {}
OrangeTradingMod.Vehicles = {}
OrangeTradingMod.AuctionState = {}

-- store.lua 从全局表组装快照
function Store.Snapshot(player)
    return {
        player = OrangeTradingMod.PlayerData,
        vehicles = OrangeTradingMod.Vehicles,
        auction = OrangeTradingMod.AuctionState,
    }
end

-- 页面渲染时调用 Snapshot
local state = Store.Snapshot(localPlayer)
```

**可借鉴**: GodSystem 的客户端状态管理分散在各模块，没有统一的 Store 层。如果未来 UI 复杂度增加，可以考虑引入类似的快照模式。

---

## 6. 维护调度模式

### 6.1 优先级队列 (server_runtime.lua)

```lua
local maintenanceQueue = {}

function queueMaintenance(name, delayMs, callback)
    table.insert(maintenanceQueue, {
        name = name,
        runAtMs = nowMs() + delayMs,
        callback = callback,
    })
    table.sort(maintenanceQueue, function(a, b) return a.runAtMs < b.runAtMs end)
end

-- OnTick 中处理
function OnTick()
    local now = nowMs()
    while #maintenanceQueue > 0 and maintenanceQueue[1].runAtMs <= now do
        local task = table.remove(maintenanceQueue, 1)
        local ok, err = pcall(task.callback)
        if not ok then log("maintenance " .. task.name .. " failed", err) end
    end
end
```

**可借鉴**: GodSystem 的 `Scheduler` 使用固定间隔，OCE 的优先级队列支持动态延迟和错误隔离。适合处理 "5秒后重试"、"30秒后清理" 等场景。

### 6.2 时间预算批处理

```lua
-- 排行榜收集：每 tick 最多处理 4 个账户，预算 3ms
function ProcessLeaderboardCollectionQueue()
    local budget = 3  -- ms
    local start = nowMs()
    local count = 0
    while #queue > 0 and count < 4 and (nowMs() - start) < budget do
        local task = table.remove(queue, 1)
        task.callback()
        count = count + 1
    end
end
```

**可借鉴**: GodSystem 的范围回收使用分帧预算（`RangeRecycleFrameBudget`），但其他批量操作（如全服状态广播）没有预算控制。OCE 的模式可以推广到更多批量场景。

---

## 7. 服务清单与规模

| 服务 | 文件数 | 职责 |
|------|--------|------|
| 经济核心 | 3 | 价格、趋势、审计 |
| 交易/商城 | 5 | 玩家市场、商店、悬赏 |
| 回收/世界市场 | 8 | 回收目录、世界市场、模板 |
| 载具 | 4 | 载具管理、税收、操作日志 |
| 动物 | 3 | 动物目录、饲养、凭证 |
| 社区治理 | 5 | 选举、法律、项目、财政 |
| 灾难/防御 | 4 | 灾难事件、桥梁战斗 |
| 职业 | 3 | 职业申请、工资、消息 |
| 任务 | 2 | 任务模板、奖励 |
| 股票/拍卖 | 4 | 股票市场、拍卖行 |
| 安全屋 | 4 | 安全屋管理、水电 |
| 福利/彩票 | 3 | 福利系统、彩票、刮刮卡 |
| 状态同步 | 4 | 域订阅、传输、私有/共享状态 |
| UI 客户端 | 100+ | Shell、37页面、11对话框、5组件 |

**规模对比**: OCE 的 240 Lua 文件约为 GodSystem 135 文件的 1.8 倍，但功能覆盖面更广（社区治理、灾难防御、股票市场等 GodSystem 没有的子系统）。

---

## 8. 可借鉴模式总结

### 高优先级（适合 GodSystem 当前阶段）

1. **AuthoritativeBuckets 内存缓存**: 减少 ModData I/O，适合高频交易场景
2. **读时归一化 (normalizePlayerRecord)**: 比写时保证更健壮，适合 MOD 数据兼容性
3. **Safe* 输入验证工具链**: 统一抽取到 shared 层，减少重复代码
4. **BeginTransmitBatch/EndTransmitBatch**: 批量去重，减少同一命令内的多次持久化
5. **Action Request Guard**: 冷却 + requestId 去重，补充 TransactionOps 的指纹去重

### 中优先级（适合未来扩展）

6. **域订阅模式**: 如果增加拍卖、股票等子系统，可以减少不必要的带宽
7. **声明式 Reply sync 表**: 减少手动发送状态遗漏
8. **优先级维护队列**: 替代固定间隔 Scheduler，支持动态延迟和错误隔离
9. **时间预算批处理**: 推广到全服广播等批量场景

### 低优先级（规模扩大后考虑）

10. **Shell + Page Registry UI**: GodSystem 当前规模用浮动按钮更轻量
11. **Store 快照层**: UI 复杂度增加后考虑引入
12. **快照差分传输**: 玩家交易列表等可以用 diff 减少传输量

---

## 9. 差异与取舍

| 模式 | OCE 选择 | GodSystem 选择 | 取舍分析 |
|------|----------|----------------|----------|
| 命名空间隔离 | 全局表 | Runtime Installer 沙箱 | GodSystem 更安全，OCE 更简单 |
| 数据持久化 | 内存缓存 + 批量写 | 直接 ModData 读写 | OCE 性能更好，GodSystem 更简单 |
| 状态同步 | 域订阅 + revision | 全量/增量二层 | OCE 带宽更省，GodSystem 更简单 |
| 命令分发 | register() 表驱动 | RouterConfig if-else | OCE 更简洁，GodSystem 更直观 |
| UI 架构 | Shell + Registry + Store | 浮动按钮 + 直接创建 | OCE 适合多页面，GodSystem 适合轻量 |

**结论**: OCE 的模式更适合大型多人经济 MOD（高频交易、多子系统、带宽敏感），GodSystem 的模式更适合中小型系统 MOD（简单直接、易调试、安全隔离）。两者的选择反映了不同的规模和需求，不应盲目照搬，但可以从 OCE 提取经过验证的模式用于 GodSystem 的瓶颈点。
