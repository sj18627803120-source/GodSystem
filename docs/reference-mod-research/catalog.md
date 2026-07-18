# 参考 MOD 来源目录

本目录覆盖当前研究范围内的 11 个来源。另一台开发设备不需要持有第三方 MOD 文件；先读对应报告，需要确认新版本差异时再使用最后一列关键词联网检索，并继续按证据标签记录结论。

| 来源 | 主要 MOD ID | 本地主要版本 | 证据强度 | 重点主题 | 联网检索关键词 |
|---|---|---|---|---|---|
| [More Traits](mods/MoreTraits.md) | `1299328280/ToadTraits` | B42.17，含 Dynamic 子模块 | `旧 B42 参考` | 特质注册、动态特质、负重框架依赖 | `Project Zomboid More Traits 1299328280 ToadTraits B42` |
| [Extended Categories](mods/CAExtendedCategories.md) | `CAExtendedCategories` | 0.17.0，B42.0+ | `旧 B42 参考` | 物品分类、标签、隐藏物品过滤 | `Project Zomboid CAExtendedCategories Kechna 0.17.0` |
| [CaiGou's Shop](mods/CaiGou-Shop.md) | `CaiGou's ShopV2` | B42 目录，未声明最低小版本 | `旧 B42 参考` | 商店、玩家上架、回收 | `Project Zomboid CaiGou ShopV2` |
| [Cultivation Storage Artifacts](mods/CultivationStorageArtifacts.md) | `CultivationStorageArtifacts` | 0.1.10，说明适配 B42.17 | `旧 B42 参考` | 多穿戴容器、嵌套储物、递归减重、联机同步 | `Project Zomboid Cultivation Storage Artifacts Tofu 0.1.10` |
| [that DAMN Library](mods/damnlib.md) | `damnlib` | 0.9862b，B42.17 目录 | `旧 B42 参考` | 物品脚本 fallback、框架加载、全局补丁 | `Project Zomboid that DAMN Library KI5 0.9862b` |
| [DebugMenu](mods/DebugMenu.md) | `QNWDebugMenuB42` | B42.13+ | `旧 B42 参考` | 车辆修复、物品生成、调试接口 | `Project Zomboid QNWDebugMenuB42 DebugMenu` |
| [Psionic Awakening](mods/PsionicAwakening.md) | `PsionicAwakeningB41` | 0.13.2，B42.19 | `B42.19 同版本证据` | 技能系统、战斗效果、渲染、SP/MP 分层 | `Project Zomboid Psionic Awakening 0.13.2 B42.19` |
| [RuinBazaar](mods/RuinBazaar.md) | `RuinBazaar` | B42 目录，未声明最低小版本 | `旧 B42 参考` | 商店、回收、抽奖、交易管理器 | `Project Zomboid RuinBazaar 废墟集市` |
| [Server Shop](mods/Server-Shop.md) | `ServerShop` | B42.19 compatibility patch | `B42.19 同版本证据` | 服务端经济、发货、退款、离线队列、审计 | `Project Zomboid Server Shop zPoints B42.19` |
| [Traits Purchase System](mods/TraitsPurchaseSystem.md) | `TraitsPurchaseSystem` | 2，B42.0+ | `旧 B42 参考` | 特质购买、移除、冲突和多人声明 | `Project Zomboid Traits Purchase System hakcenter modversion 2` |
| [YeseMarket](mods/YeseMarket.md) | `YeseMarket` | B42 目录，SP/MP | `旧 B42 参考` | 统一协议、SP 本地后端、MP handler | `Project Zomboid YeseMarket Dusk SP MP` |

## 版本使用说明

- “本地主要版本”描述本次静态审计选择的代码树，不代表作者最新公开版本。
- 未声明准确 B42 小版本的来源统一按旧 B42 参考处理。
- 只有明确提供 B42.19 代码树的来源标为同版本证据。
- More Traits 等含多个版本目录的来源，只以最新 B42 目录为主，旧树用于确认迁移差异。
