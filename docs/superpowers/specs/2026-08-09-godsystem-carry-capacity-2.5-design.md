# GodSystem 42.20_2.5 负重与重连修复设计

## 目标

修复 B42.20.2 下人物负重升级的实际应用值与界面展示值不一致，并保留已验证的医疗 Java 调用移除和 MP 重连握手恢复，形成 `42.20_2.5` 测试候选。

## 根因证据

B42.20.2 `BodyDamage.UpdateStrength()` 持续执行以下本体计算：

```text
nativeCapacity = max(0, floor(maxWeightBase * getWeightMod()) - strengthMoodles)
maxWeight = floor(nativeCapacity * maxWeightDelta)
```

其中 `strengthMoodles` 来自 HUNGRY、THIRST、SICK、BLEEDING、INJURED 五类 Moodle；`maxWeightDelta` 是角色运行时字段，重连后不会作为 GodSystem 存档字段自动恢复。

现有实现用 `maxWeightBase * (1 + externalDelta)` 估算基础，并依赖 `setMaxWeight()` 的缓存值。该缓存会被下一次本体 `UpdateStrength()` 覆盖，导致升级页的基础、实际加成和最终值失真。

## 方案

1. 在共享负重模块中按同版本本体公式读取 `getMaxWeightBase()`、`getWeightMod()` 和五类 Moodle 减益。
2. 首次应用时记录当前原版 `maxWeightDelta`；后续只在当前值仍等于 GodSystem 上次写入值时复用该原版倍率，否则把当前值视为外部新倍率，保留第三方/特征变化。
3. 设 `bonus = level * CarryCapacityPerLevel`，计算 `desiredFinal = nativeFinal + bonus`，写入 `targetDelta = desiredFinal / nativeCapacity`；`setMaxWeight()` 只用于即时刷新，不能作为持久事实。
4. 在 SP 与 MP 已有每 60 ticks 的玩家更新边界重新校准，登录、升级、状态同步仍复用同一入口；不增加库存扫描或独立高频定时器。
5. 升级页状态使用实时 `getMaxWeight()` 和排除 GodSystem 后的 `nativeFinal`，展示 `actualBonus = total - nativeFinal`；无法取得本体字段时显示未知，不伪造理论值。
6. 旧 `GodSystemCarryApplied*` ModData 继续读取并迁移，新增原版倍率/最终值标记不改变等级、费用、协议和既有存档结构。

## 边界

- 保留医疗收尾中移除不兼容的 `setBandaged` 调用。
- 保留 MP `OnConnected`/`OnDisconnect` 握手状态重置。
- 本版不修改空间终端减载物品清理，等待独立实机证据。
- 版本元数据统一为 `42.20_2.5`；Workshop 只更新 `Contents`。

## 验证

- Lua 行为测试覆盖普通倍率、Strong/Weak 倍率、Moodle 减益、重复校准、旧标记迁移和失败回滚。
- B42.20.2 专项测试断言原版公式 helper、生命周期校准和版本一致性。
- 统一测试必须通过 Lua 5.1 编译、编码、历史回归和 `git diff --check`。
- 实机分别验证 SP、MP 主机、MP 远程玩家的升级、力量/Moodle 变化、断线重连和最终显示；减载只做回归观察，不以本版声称修复。
