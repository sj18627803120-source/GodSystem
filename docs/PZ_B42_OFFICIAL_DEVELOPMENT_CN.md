# Project Zomboid B42 官方开发资料与适用边界

更新日期：2026-07-21。GodSystem 当前目标版本：Build 42.19.0。

## 已确认的官方资料

- [The Indie Stone: Modding Migration Guide (42.13)](https://theindiestone.com/forums/topic/88499-modding-migration-guide-4213/)
  - 官方帖子包含 `Migration Guide.pdf`、`testmod_registries.zip` 和 `Project Zomboid_ API for Inventory Items.pdf`。
  - 该帖针对 42.13 引入的标识符、注册表和多人 Inventory Item 处理架构，不是单独的 42.19 手册。
- [The Indie Stone: Build 42.19.0 UNSTABLE Released](https://theindiestone.com/forums/topic/95733-build-42190-unstable-released/)
  - 这是 42.19 官方版本说明，主要是版本改动和修复记录，没有提供一份新的完整 MOD API 手册。
- [PZwiki Modding](https://pzwiki.net/wiki/Modding)、[Lua API](https://pzwiki.net/wiki/Lua_%28API%29)、[Lua event](https://pzwiki.net/wiki/Lua_event)
  - PZwiki 是社区持续维护的官方 Wiki，页面标题通常不写版本号，但正文使用 `Page version` 标记内容最后核对的游戏版本。不同页面更新不同步，必须读取页内版本提示；具体方法签名仍需与本机 B42.19 原版代码交叉验证。
- [B42 迁移资料镜像](https://github.com/PZ-Wiki-Modding/Archive.Project-Zomboid-Modding/tree/main/TIS%20guides/B42%20unstable%20MP)
  - 该 GitHub 仓库是社区存档镜像，便于附件无法下载时读取；资料原始来源仍是 The Indie Stone 官方论坛。

PZwiki 页面版本机制、PZ Community API、SpawnerAPI 和资料镜像的详细核验见 [社区开发资源核验](PZ_COMMUNITY_DEVELOPMENT_RESOURCES_CN.md)。

## 42.13 迁移指南确认的规则

1. `media/registries.lua` 文件名和位置必须精确；它在脚本和其他 Lua 之前加载。
2. `CharacterTrait`、`CharacterProfession`、`ItemTag`、`ItemBodyLocation`、`ItemType`、`MoodleType`、`WeaponCategory`、`AmmoType` 等自定义标识符需先注册，再在脚本中使用。
3. B42 物品脚本的 `Type` 改为 `ItemType`，并使用已注册的 ItemType，例如 `ItemType = base:normal`。
4. 物品脚本 `DisplayName` 已移除，名称从 `Module.ItemId` 对应翻译键读取。
5. 自定义 Tags 需要 ItemTag 注册；脚本和配方标识符要使用正确命名空间。
6. 官方指南明确提示：部分 Lua API 已修改，接口失效时应检查反编译 Java；后续不稳定版本还会继续改变 API。

## Inventory Items API 确认的多人规则

1. 多人中的物品创建、删除和修改必须在服务端执行。客户端自行创建的物品不能正常交互，并会在重登后消失。
2. 推荐使用 B42 网络 Timed Action：文件放在 `media/lua/shared`，客户端 `perform()` 只处理动画、声音和 UI，服务端/SP 的 `complete()` 负责修改物品和对象。
3. 网络 Timed Action 的 `new()` 参数名必须与对象字段匹配，传入值不能在构造阶段被二次变换；耗时由服务端 `getDuration()` 重新计算，不能信任客户端时长。
4. 不适合 Timed Action 的操作可使用 `sendClientCommand(player, module, command, args)`；服务端通过 `OnClientCommand(module, command, player, args)` 重新查找对象、验证权限和执行修改。
5. 服务端修改后必须显式同步。官方列出的接口包括：
   - `sendAddItemToContainer`
   - `sendRemoveItemFromContainer`
   - `syncItemFields`
   - `syncItemModData`
   - `syncHandWeaponFields`
   - `sendItemStats`
   - `transmitCompleteItemToClients`
   - `transmitRemoveItemFromSquare`
   - 对象 `sync()` 和 `transmitUpdatedSpriteToClients()`
6. `sendClientCommand` 在单人模式也可触发对应处理器，但实际项目仍需按本机 B42.19 加载环境验证，不能仅凭文档假设某个 server 文件一定在 SP 加载。

## 对 Build 42.19 的使用方式

42.13 指南是 42.19 注册表和多人物品架构的基础证据，但不是所有 42.19 Java/Kahlua 方法签名的最终答案。GodSystem 采用以下顺序：

1. 先查 `C:\APP\Steam\steamapps\common\ProjectZomboid\media` 中的 B42.19 原版 Lua、脚本和示例。
2. 原版 Lua 没有覆盖时，查 `projectzomboid.jar` 的反编译 Java 或同版本可调用签名。
3. 再用官方 42.13 迁移指南确认架构目的和同步规则。
4. 最后参考 `docs/reference-mod-research/` 的同版本社区实现。
5. Java 方法存在不代表 Kahlua 暴露了同样的重载；必须通过原版调用或实机最小测试证明。

GodSystem 已遇到的典型案例是 `isFavorite()`、`isUnwanted(player)` 和 `setUnwanted(player, value)` 参数不同。只按方法名猜签名会直接产生运行时红字。

## 从“开发技术支援”目录提炼的有效内容

- 保留：UTF-8 编码检查、CN/CH 与 Lua fallback 同源生成、UI 列表滚动状态复位、稳定 ID 恢复选择、服务端经济验证、物品增删同步、失败退款和操作幂等。
- 保留：大文件和 Lua 5.1 顶层 local 上限属于持续风险；新增服务器 helper 优先放入现有模块表或独立文件，并以 `luac -p` 为准。
- 谨慎采用：拆分 `GodSystem_Server.lua`、`GodSystem_Core.lua`、`GodSystem_UI.lua` 可以降低维护冲突，但属于高风险架构任务，不能作为普通功能修改顺带执行。
- 不采用：把 10K 行价格 Lua 改成 JSON/CSV 不能仅凭“文件大”决定。PZ 加载方式、解析成本、打包兼容和生成流程未验证前，拆分只改善维护性，不代表启动性能一定提升。
- 不采用：支援目录中的旧绝对路径、v1.16.62 状态、已删除的容量包装和旧理财计时结论均不是当前事实。

## 当前直接开发流程

本项目不再要求 Superpowers 技能。每次任务按以下顺序执行：

1. 明确目标、范围、成功标准和是否影响 SP/MP、经济、存档或协议。
2. 阅读当前实现和调用链，查证 B42.19 接口。
3. 制定最小改动及失败路径；Bug 优先增加可复现回归。
4. 在 Git 独立分支实施，不顺带重构无关模块。
5. 运行专项、完整回归、编码检查和全部 Lua 5.1 编译。
6. 覆盖 Workshop 运行文件并核对部署内容，由用户实机测试。
7. 用户确认后更新实测记录并推送 GitHub；未确认部分继续标为待测。
