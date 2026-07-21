# RuinBazaar 研究报告

## 身份与版本

- 名称：废墟集市
- MOD ID：`RuinBazaar`
- 本地代码树：`42`
- `mod.info` 未声明准确 B42 小版本
- 证据强度：`旧 B42 参考`

## 功能地图

- `media/lua/client/RuinBazaar_Main/RuinBazaar_Data.lua`：商城分类、商品和价格数据。
- `RuinBazaar_Shop.lua`、`RuinBazaar_Recycle.lua`：购买和回收 UI。
- `RuinBazaar_VendingManager.lua`：货币、发物品和回收的统一容器操作。
- `RuinBazaar_Main.lua`：售货机右键入口和功能导航。
- 同目录其他模块：兑换、抽奖、贷款、悬赏、策略、古董和跨境商店。
- `client/RuinBazaar/Skills/`：大量战斗能力和状态效果。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `RuinBazaar_VendingManager.lua`，`getVendingContainer()` | 从玩家运行时 ModData 获取指定售货机容器；缺失时回退到玩家主库存。 |
| `代码确认` | 同文件，货币与回收函数 | 只扫描目标容器第一层，不递归玩家全部背包。 |
| `代码确认` | 同文件，`takeGold()`、`recycleAll()` 等 | 删除多个物品时反向遍历 Java 列表，避免删除导致索引跳项。 |
| `代码确认` | 同文件，`addItem()`、`takeGold()` | 直接在客户端 Lua 中调用容器 `AddItem()`/`Remove()`，没有 GodSystem 式服务端事务 handler。 |
| `代码确认` | `RuinBazaar_Data.lua` | 商品数据与 UI/交易代码分开，条目以名称键、价格、full type 和图标描述。 |
| `代码确认` | `RuinBazaar_Main.lua` | 使用 `OnPreFillWorldObjectContextMenu` 找售货机，保存容器引用后打开单例式主窗口。 |
| `代码确认` | `client/RuinBazaar/Skills/` | 多个技能分别维护状态，部分通过 `OnTick`、武器命中和僵尸死亡事件运行。 |

## 单人与多人数据流

- 核心商城、回收和货币文件位于 client，未发现统一 C2S/S2C 商城协议。
- 交易直接修改当前客户端持有的容器和物品，适合作为 SP 组织结构参考。
- `player:getModData().vendingContainer` 保存的是运行时容器引用，不是可跨设备复用的服务端持久化 ID。
- 因缺少服务端重新查价、余额验证和库存同步，不能将其作为 GodSystem MP 经济实现。

## 可采用机制

- 数据、UI 和交易管理器分离，所有容器读写集中到一个 manager。
- 把交易限定到明确容器第一层，可显著降低递归扫描成本并减少误操作范围。
- 删除 Java 列表元素时反向遍历。
- 每个页面只负责自己的展示与按钮，主入口负责导航和单例窗口生命周期。
- 战斗能力按效果拆成独立模块，比把所有状态塞进一个大文件更容易清理和测试。

## 风险与限制

- `代码确认`：交易是客户端直接修改，缺少服务端权威、显式同步、失败退款和重复请求处理。
- `合理推断`：将 Java 容器对象放入玩家 ModData 适合当前会话引用，不应视为可序列化持久数据。
- 回退到主库存改变了“只处理售货机”的边界，正式经济系统应明确失败而不是静默扩大范围。
- 多个能力使用 `OnTick`；若每个技能都独立扫描实体，组合启用时可能叠加主线程开销。
- 源码和脚本存在编码混乱，不能将其中文文本或文件编码直接复制到 GodSystem。

## 对 GodSystem 的应用

- GodSystem 已将交易逻辑逐步集中到服务/事务模块，UI 不直接承担扣币和库存删除。
- 系统空间终端、快捷回收等固定容器操作继续优先第一层扫描和稳定 ID。
- MP 中容器边界、价格和删除必须由服务端重新验证；RuinBazaar 只提供 SP 模块拆分参考。
- 同伴状态效果应统一调度和统一伤害结算，避免每个效果各自常驻全场扫描。

## 待验证内容

- `待实机验证`：作者是否通过游戏原生本地托管机制获得了部分库存同步，源码中没有明确协议证明。
- `待实机验证`：大量战斗技能同时启用时的 OnTick 调用数量和尸群帧率。
- `待实机验证`：B42.19 对其旧物品脚本字段和自定义武器回调的兼容性。

## 联网检索信息

- 搜索词：`Project Zomboid RuinBazaar 废墟集市`
- 建议核对：Workshop 目标版本、MP 支持声明和最近更新记录。
