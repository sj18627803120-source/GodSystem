# Psionic Awakening 研究报告

## 身份与版本

- 名称：Psionic Awakening (B41/B42)。
- MOD ID：`PsionicAwakeningB41`；目录名保留 B41，但本次代码树明确是 Build 42 实现。
- `mod.info`：`modversion=0.13.2`、`versionMin=42.19`。
- 证据强度：`B42.19 同版本证据`。

## 功能地图

- `media/lua/shared/PsionicAwakening/PA_State.lua`：玩家 ModData、等级、资源、冷却、冥想、感染净化和每帧状态更新。
- `PA_Config.lua`：范围、冷却、成本、扫描间隔和技能树常量。
- `media/lua/client/PsionicAwakening/PA_Crush.lua`：鼠标范围选目标并直接击杀僵尸或动物。
- `PA_Sense.lua`：手动感知、全屏标记和分批资源扫描。
- `PA_Expansion.lua`：击倒、标记、拉取物品、强化门窗、被动危险感知和叙事提示。
- `PA_Shatter.lua`/`PA_PsionicHand.lua`：破坏世界对象和远程容器交互。
- `PA_Effects.lua`/`PA_HUD.lua`：临时覆盖特效、技能面板和侧栏入口。

## 关键证据

| 标签 | 相对文件与符号 | 已确认行为 |
|---|---|---|
| `代码确认` | `PA_State.lua`，`State.get()` | 技能 XP、等级、节点、资源、统计和冷却保存在玩家 ModData，并按 `DATA_VERSION` 校正。 |
| `代码确认` | 同文件，`State.cooldownRemaining()`/`State.update()` | 技能冷却使用现实秒；长周期事件使用世界小时；每次状态更新的 elapsed 被夹到 0–10 秒。 |
| `代码确认` | 同文件，`Events.OnPlayerUpdate` | 资源恢复和状态衰减每次玩家更新执行，但主体是常量字段运算，没有每帧扫描僵尸列表。 |
| `代码确认` | `PA_Expansion.lua`，`passiveSense()` | 最多每 4 秒扫描一次当前 cell 的僵尸列表；触发警告后 45 秒内在扫描前提前返回。 |
| `代码确认` | `PA_Sense.lua`，`updateResourceScan()` | 手动资源感知通过 `OnTick` 每次最多处理 220 个格子，扫描完成或覆盖持续时间结束后清空任务。 |
| `代码确认` | `PA_Effects.lua`/`PA_HUD.lua` | 特效由临时 UI overlay 自行过期；HUD 的 `OnTick` 只在等待侧栏时注册，成功或重置后移除。 |
| `代码确认` | `PA_Crush.lua`，`Crush.activate()` | 僵尸先 `setAttackedBy(player)` 再 `setHealth(0)`，随后手工校正玩家击杀数；代码没有调用 `Kill(player)`。 |
| `代码确认` | `PA_State.lua`，`State.purgeInfection()` | 同时清除 BodyDamage 感染、感染时间、`ZOMBIE_INFECTION` 和 `ZOMBIE_FEVER`，再施加资源与过载代价。 |
| `代码确认` | 客户端能力文件 | Crush、Shatter、扩展能力和远程手部操作有 `isClient()` 禁用路径；Sense 与共享 State 没有统一的文件级 MP hard return。 |

## 单人与多人数据流

- 仓库树没有 `media/lua/server`、`OnClientCommand` 或自定义 C2S/S2C 协议。
- 破坏、击杀、拉取和强化世界对象的主要能力在客户端文件中主动拒绝 `isClient()`，定位为 SP 能力。
- 共享 `PA_State.lua` 仍会注册 `OnPlayerUpdate`；Sense 的按键、overlay 和资源扫描也没有同样的 MP 文件级退出。
- `合理推断`：多人中可能仍加载部分本地状态、UI 或感知逻辑，但没有服务端权威链路，不能作为 MP 战斗、物品转移或持久化模板。
- 所有实际能力结算和 XP 都直接修改本地玩家或世界对象，没有交易去重、服务器回包或离线恢复。

## 可采用机制

- 冷却与世界小时分离：短技能用现实秒，在线成长和长期事件用世界小时。
- 在高频 update 中只做常量状态运算；全量目标扫描单独节流，手动大范围格子扫描按固定预算跨 Tick 完成。
- 临时渲染使用自清理 overlay，入口等待成功后立即注销临时 `OnTick`。
- 技能状态统一放在一个有版本号的玩家 ModData 根节点，并集中迁移和范围夹取。
- 感染清理同时处理 BodyDamage 和 CharacterStat 两层状态，避免界面或症状残留。
- SP 世界修改在能力入口统一 hard return MP，而不是只隐藏按钮。

## 风险与限制

- `代码确认`：Crush 没有进入 `Kill(player)` 路径，而是 `setHealth(0)` 后手工补击杀数。
- `合理推断`：手工击杀数能修正计数，但不能证明原版死亡事件、掉落、击杀奖励和第三方任务监听都完整触发。
- `代码确认`：被动感知虽然节流，执行时仍遍历整个 cell 僵尸列表；超大尸群和大 cell 下成本与目标总量相关。
- `代码确认`：Sense 常驻注册一个 `OnTick`，空闲时会快速返回；模式可用，但多个 MOD 叠加时仍应控制常驻事件数量。
- `代码确认`：多人禁用不是统一文件级策略，shared 状态与 Sense 仍可加载；不能把“部分动作提示仅单人”解释为多人完全不运行。
- `代码确认`：Ward、Pull、Shatter 直接变更世界对象，适合 SP 参考，不适合直接搬到 MP。

## 对 GodSystem 的应用

- 同伴伤害继续统一调用玩家归属和 B42 死亡路径；不要只用 `setHealth(0)` 加手工击杀数。
- 灵视的 50 目标上限和手动触发策略优于持续全场扫描；大范围格子能力可采用每帧预算。
- 所有同伴客户端运行文件保持统一 SP hard return，MP 不注册扫描、渲染和快捷栏事件。
- 临时光束、标记和环形特效使用固定生命周期队列，结束、死亡、乘车和退出时集中清理。
- 感染治理继续同时复查 BodyDamage 与 CharacterStat，且必须在目标 B42.19 实机验证。

## 待验证内容

- `待实机验证`：`setHealth(0)` 路径是否触发 B42.19 全部僵尸死亡事件、尸体生成和第三方击杀监听。
- `待实机验证`：高尸群下被动感知全 cell 遍历和 220 格/Tick 资源扫描的帧时间。
- `待实机验证`：多人加载时共享 State、Sense overlay 和按键事件是否产生本地状态或红字。
- `待实机验证`：不同 UI 缩放和分辨率下全屏 overlay 的坐标与输入穿透。

## 联网检索信息

- 搜索词：`Project Zomboid Psionic Awakening 0.13.2 B42.19`
- 建议核对：Workshop 的单人/多人声明、B42.19 死亡归属 API、作者更新记录和性能问题反馈。
