# Extended Categories 研究报告

## 身份与版本

- 名称：Extended categories (B42)
- MOD ID：`CAExtendedCategories`
- 作者：Kechna
- 本地版本：`0.17.0`
- 最低版本声明：`42.0.0`
- 证据强度：`旧 B42 参考`

## 功能地图

- `common/media/lua/shared/CAExtendedCategories/CAEC.lua`：初始化、全物品遍历、分类器注册和结果缓存。
- `CAEC_Utils.lua`：标签查询、临时实例缓存、激活 MOD 查询和分类器包装。
- `CAEC_ItemCategorizer.lua`：分类器基类和错误隔离。
- `Categorizers/`：服装、武器、工具、食物、容器、液体、医疗、机械等领域分类器。
- `common/media/lua/shared/Translate/`：分类名称的 JSON 本地化。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `CAEC.lua`，`CAEC.Initialize()` | 初始化分类器后调用 `CAEC.CategorizeAllItems()`，并保存静态分类、实例专用分类和错误信息。 |
| `代码确认` | `CAEC.lua`，`CAEC.CategorizeAllItems()` | 一次遍历 `getAllItems()`，逐个调用 `CAEC.CategorizeItem()`；确定静态分类后用 `Item:DoParam("DisplayCategory", category)` 写回脚本。 |
| `代码确认` | `CAEC.lua`，`CAEC.CategorizeItem()` | 优先读取显式 tweak 和静态缓存，再调用脚本分类器；实例相关类型单独记录，不把所有结果都当作静态值。 |
| `代码确认` | `CAEC_Utils.lua`，`Utils.HasAnyTag()` | 先检查标签集合是否为空，再通过物品脚本标签判断多个候选标签。 |
| `代码确认` | `CAEC_Utils.lua`，`Utils.CreateInstanceIfNeeded()` | 只有分类器需要实例属性时才 `instanceItem()`，按 full name 缓存临时实例，并提供统一移除函数。 |
| `代码确认` | `Categorizers/CAEC_Apparel.lua`，`Apparel:validate()` | 排除容器以及 `WOUND`、`ZED_DMG`、`BANDAGE` BodyLocation，避免把伤口、僵尸损伤和绷带内部物品当普通服装。 |
| `代码确认` | `Categorizers/CAEC_Apparel.lua`，`resolveBodyLocation()` | 使用 `ItemBodyLocation.get(ResourceLocation.of(name))` 后再从 Human BodyLocationGroup 获取位置。 |

## 单人与多人数据流

- 核心分类器位于 shared，没有自定义 C2S/S2C 协议。
- 分类主要是脚本级预处理：两端加载同一套 MOD 时可独立得到分类结果，不需要为每个物品实例发送网络状态。
- 只有确实依赖实例属性的类别才保留实例分类路径；普通物品使用静态缓存。
- 该 MOD 不执行交易、扣款或玩家持久化，不能作为 MP 经济权威示例。

## 可采用机制

- 游戏启动阶段一次性建立分类缓存，UI 打开时读取结果，不重复遍历全部物品脚本。
- 优先使用 `hidden`、`obsolete`、官方标签、ItemType、BodyLocation 等结构化字段，名称黑名单仅作兜底。
- 将“脚本可判定”和“必须创建实例才能判定”分开，控制 `instanceItem()` 数量。
- 临时实例集中缓存和清理，不在每个分类器里重复创建。
- 自定义 BodyLocation 使用命名空间 `ResourceLocation` 解析，不用裸字符串比较所有槽位。

## 风险与限制

- `合理推断`：全量分类适合启动或显式重建，不适合商城每次绘制、分页或搜索时执行。
- `代码确认`：分类结果可能通过 `DoParam()` 修改全局 `DisplayCategory`；这适合全局分类 MOD，但不适合玩家私有状态。
- `代码确认`：创建临时实例可能触发第三方物品构造逻辑，因此只应在静态字段不足时使用。
- 分类代表展示归类，不代表商品可购买、可回收或可抽奖；经济池仍需独立资格规则。
- `旧 B42 参考`：0.17.0 只声明 B42.0+，B42.19 新增的 ItemType、标签和 BodyLocation 仍需原版复核。

## 对 GodSystem 的应用

- 商店、抽奖和回收候选池继续先过滤 `hidden`、`obsolete`、debug/占位 ItemType 和内部 BodyLocation。
- 大型商品候选表应在初始化或配置变化时重建，不在 UI `drawItem`、分页和点击路径重扫 `getAllItems()`。
- 标准 MOD 技能和物品识别应优先依赖注册表和结构化字段，不根据中文名称猜类型。
- 如果未来需要精细商品分类，可缓存少量临时实例，但必须与经济资格判断分离。

## 待验证内容

- `待实机验证`：B42.19 是否新增需要排除的内部 BodyLocation 或 ItemType。
- `待实机验证`：加载超大物品 MOD 集合时，全量 `instanceItem()` 的峰值耗时和构造副作用。
- `待实机验证`：其他分类 MOD 同时写 `DisplayCategory` 时的加载顺序和最终覆盖关系。

## 联网检索信息

- 搜索词：`Project Zomboid CAExtendedCategories Kechna 0.17.0 B42`
- 建议核对：Workshop 更新记录、GitHub 源码版本、B42.19 ItemTag 和 ItemBodyLocation 变更。
