# Project Zomboid 参考 MOD 研究库

本目录保存 GodSystem 开发中使用过的第三方参考 MOD 静态研究结果。目标读者是在另一台没有参考源码的设备上继续开发的 Codex 或开发者。

研究库只提供机制摘要、相对文件路径、接口名称和工程判断，不包含第三方 MOD 源码或资源。需要实现功能时，仍应优先核对目标游戏版本的原版文件，再将这里的社区实现作为补充证据。

## 使用顺序

1. 在[来源目录](catalog.md)确认参考 MOD 的目标版本和证据强度。
2. 按下面的主题索引选择来源报告。
3. 在报告的“关键证据”中确认真实文件和符号。
4. 区分代码事实、作者声明、工程推断和待实机项目。
5. 跨项目稳定结论以 `tools/codex/skills/pz-mod-dev/references/pz-b42-patterns.md` 为准。

## 选择来源

- 先看目标接口是否与来源版本一致。B42.19 功能优先使用同版本原版文件，再选带 `B42.19 同版本证据` 的报告。
- 研究付费、库存或多人命令时，至少同时看一个服务端权威来源和一个失败/退款来源，不以“作者声明支持多人”代替调用链审计。
- 研究容器、特质和战斗能力时，区分脚本定义、实例状态、创建期副作用和运行期事件；它们通常不是同一层能力。
- 只有报告中的 `代码确认` 可以直接作为静态事实；`合理推断` 必须保留推断依据，`待实机验证` 不能写成已解决。

## 证据标签

- `代码确认`：在本地参考源码中找到明确文件、函数、事件或字段。
- `作者声明`：来自 `mod.info`、说明文本或源码注释，尚未通过实机验证。
- `合理推断`：由静态调用链得到的工程判断，不能写成已发生的问题。
- `待实机验证`：必须在对应游戏版本或多人服务器中测试。

## 版本标签

- `B42.19 同版本证据`：可作为当前 GodSystem 目标版本的强参考，但社区代码仍低于原版证据。
- `旧 B42 参考`：接口可能接近 B42.19，采用前必须复核当前原版文件。
- `B41 弱参考`：只借鉴架构和业务组织，不直接采用接口调用。

## 主题索引

### 多人协议与同步

- [Server Shop](mods/Server-Shop.md)：服务端余额、库存预留、发货、退款、离线队列和审计。
- [YeseMarket](mods/YeseMarket.md)：共享协议表、SP 本地 dispatcher、MP handler 和库存回滚。
- [CaiGou's Shop](mods/CaiGou-Shop.md)：真实物品 ID 上架与快照，同时展示客户端价格信任风险。

### 经济、商城与回收

- [CaiGou's Shop](mods/CaiGou-Shop.md)
- [RuinBazaar](mods/RuinBazaar.md)
- [Server Shop](mods/Server-Shop.md)
- [YeseMarket](mods/YeseMarket.md)

### 容器、穿戴与重量

- [Cultivation Storage Artifacts](mods/CultivationStorageArtifacts.md)
- [More Traits](mods/MoreTraits.md)
- [that DAMN Library](mods/damnlib.md)

### 特质、技能 XP 与成长

- [More Traits](mods/MoreTraits.md)
- [Traits Purchase System](mods/TraitsPurchaseSystem.md)
- [Psionic Awakening](mods/PsionicAwakening.md)

### 物品分类与兼容

- [Extended Categories](mods/CAExtendedCategories.md)
- [that DAMN Library](mods/damnlib.md)
- [DebugMenu](mods/DebugMenu.md)

### UI、车辆与调试

- [Traits Purchase System](mods/TraitsPurchaseSystem.md)
- [YeseMarket](mods/YeseMarket.md)
- [DebugMenu](mods/DebugMenu.md)
- [Server Shop](mods/Server-Shop.md)

### 渲染、战斗与性能

- [Psionic Awakening](mods/PsionicAwakening.md)
- [RuinBazaar](mods/RuinBazaar.md)
- [Extended Categories](mods/CAExtendedCategories.md)
- [Cultivation Storage Artifacts](mods/CultivationStorageArtifacts.md)

## 全部来源

- [More Traits](mods/MoreTraits.md)
- [Extended Categories](mods/CAExtendedCategories.md)
- [CaiGou's Shop](mods/CaiGou-Shop.md)
- [Cultivation Storage Artifacts](mods/CultivationStorageArtifacts.md)
- [that DAMN Library](mods/damnlib.md)
- [DebugMenu](mods/DebugMenu.md)
- [Psionic Awakening](mods/PsionicAwakening.md)
- [RuinBazaar](mods/RuinBazaar.md)
- [Server Shop](mods/Server-Shop.md)
- [Traits Purchase System](mods/TraitsPurchaseSystem.md)
- [YeseMarket](mods/YeseMarket.md)

## 许可边界

- 不将参考 MOD 源码、贴图、音效、模型或完整配置提交到 GodSystem 仓库。
- 不因本研究库记录了接口，就推定原作者允许复制实现或重新分发资源。
- 对许可不明或明确限制再分发的来源，只保留事实性分析。
- 联网搜索时优先使用 MOD 名称、MOD ID、作者和目标版本，搜索结果仍需与当前原版文件交叉验证。
