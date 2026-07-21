# Project Zomboid 社区开发资源核验

核验日期：2026-07-21。目标版本：Project Zomboid Build 42.19.0。

本页核验 `PZwiki` 开发页面、`PZ Community API / SpawnerAPI` 和 `Archive.Project-Zomboid-Modding`。这些资源可以提高研究效率，但证据等级、目标版本和许可证不同，不能统称为“官方 B42.19 API”。

本次复核使用的公开快照为：`SimKDT/Wiki-Editing@f4e6fc1`（2026-07-15）、`Konijima/PZ-Community-API@0a5c1f0`（2021-11-09）和 `PZ-Wiki-Modding/Archive.Project-Zomboid-Modding@12ef04d`（2026-06-29）。提交日期只能描述本次读取的快照，不能证明其中每个页面或文件都在该日期完成 B42.19 核对。

## PZwiki 页面是否需要版本说明

结论：页面标题确实采用 `Modding`、`Lua API`、`Lua event` 等通用名称，PZwiki 也确实由社区持续维护；但仍然需要检查页面正文中的版本标记。

PZwiki 页面源码使用 `{{Page version|...}}` 标记内容最后核对的游戏版本。社区维护是异步的，不同页面不会随游戏更新同时完成复核。通用标题只说明主题长期有效，不能证明页面内的接口、路径和示例已经适配到 B42.19。

由于 pzwiki 对当前自动请求返回 403，本次使用活跃 Wiki 编辑者的公开草稿仓库 [SimKDT/Wiki-Editing](https://github.com/SimKDT/Wiki-Editing) 交叉检查页面版本机制。该仓库不是 PZwiki 官方发布渠道，下面的数字只能证明该快照存在页面版本标记且各页更新不同步，不能代替直接查看线上页面：

| 页面 | 公开编辑快照中的 `Page version` |
|---|---:|
| Modding | 42.19.0 |
| Mod structure | 42.14.0 |
| Lua API | 42.17.0 |
| Lua event | 42.2.0 |
| Lua language | 42.3.1 |
| Game files | 42.7.0 |
| File formats | 42.14.0 |
| Scripts | 42.17.0 |
| Startup parameters | 42.17.0 |
| Mod optimization | 42.1.1 |
| Mapping | 42.18.0 |
| Translations | 42.16.3 |
| Modeling / Animation | 42.14.0 |

使用规则：

1. PZwiki 适合查概念、目录、工具链和搜索入口。
2. 打开页面后检查页内版本标记、警告框和最后更新时间，不根据标题判断版本。
3. 页面版本低于 B42.19 时，可采用稳定概念，但 Lua/Java 方法、文件格式、网络路径和示例代码必须再查本机 B42.19 原版。
4. Wiki 页面没有覆盖的方法签名，以当前原版 Lua、脚本和反编译 Java为准。

因此，“页面名称通用，所以不需要版本说明”的结论不完整。准确说法应是：无需把版本写进链接标题，但索引必须提醒读者检查每个页面自己的版本标记。

## PZ Community API

仓库：[Konijima/PZ-Community-API](https://github.com/Konijima/PZ-Community-API)

### 身份与状态

- README 和 `mod.info` 明确目标为 `41.56-IWBUMS`。
- 默认分支为 `master`，最新代码提交停留在 2021 年，标签只有 `v0.0.1`。
- 仓库未归档，但不能把 GitHub 页面在 2026 年仍可访问或仍有关注误认为 B42 维护状态。
- 许可证为 MIT；如果复制或修改实质代码，必须保留版权与许可证文本。

### 可以借鉴的工程方法

- 每个 API 独立目录、公开模块表和私有 helper 的组织方式。
- EmmyLua `---@class`、`---@param`、`---@return` 注解及一致命名约定。
- API 模板把可变状态封装在模块内部，只公开有限函数。
- `LightAPI` 展示了光源创建、更新、格子重载和销毁的生命周期思路。
- `IsoUtils` 展示了环形/分块扫描、类型过滤和调用方谓词的可组合结构，但只能借鉴接口拆分思想，不能复制当前实现。
- `SpawnerAPI` 的“目标格未加载时记录请求，格子加载后执行”可以作为延迟工作队列的概念参考。

### 不能直接采用的部分

- 这是 B41.56 代码，不包含 B42.13 后的注册表、网络 Timed Action 和服务端 Inventory Item 规则。
- `SpawnerAPIServer.lua` 只有空模块；实际生成逻辑全部在客户端。
- 客户端直接调用 `AddWorldInventoryItem`、`addVehicleDebug` 和 `addZombiesInOutfit`。这些调用在 B42.19 原版仍能找到，但物品/车辆生成主要出现在服务端、教程或 Debug 路径，不能据此认为客户端生成适合多人玩法。
- 延迟队列读取 `SpawnerAPI["spawn" .. entry.spawnFuncType]`，实际公开函数却名为 `SpawnItem`、`SpawnVehicle` 和 `SpawnZombie`。Lua 区分大小写，因此当前延迟执行分支找不到目标函数；这段代码不能作为已验证可用的队列实现。
- 待生成表保存进 `ModData`，条目可携带 Lua 函数回调；函数不是可靠的持久化/网络序列化数据。
- `IsoUtils.GetIsoRange()` 把楼层固定为 `z=0`，并调用 `getOrCreateGridSquare()`；`RecursiveGetSquare()` 还存在对未赋值局部变量调用 `getSquare()` 的路径。它不适合直接用于多楼层或大范围运行时扫描。
- `BodyLocationsAPI` 通过反射访问内部字段，B42 已引入 `registries.lua` 和 `ItemBodyLocation.register()`；不能用旧反射方案替代当前注册流程。
- 没有 GodSystem 所需的服务端价格/权限/所有权验证、结构化结果、退款、操作幂等和物品同步闭环。

### GodSystem 决策

- 不把 Community API 加为依赖，不打包其代码。
- 可以借鉴模块边界、注解、延迟队列和扫描分批思想。
- 需要类似功能时，在 GodSystem 内按 B42.19 原版接口重新实现，并运行 SP/MP 实测。

## SpawnerAPI

[SpawnerAPI](https://github.com/Konijima/PZ-Community-API/tree/master/Contents/mods/CommunityAPI/media/lua/client/SpawnerAPI) 不是第二个 GitHub 项目，而是 `PZ-Community-API` 仓库中的一个子模块。

它适合作为“未加载格子的延迟任务”概念样例，不适合作为 B42.19 多人生成服务。若将来需要远程生成物品、车辆或僵尸，至少需要：

1. 请求只携带可序列化的类型、坐标和标量参数，不能携带函数。
2. 服务端验证权限、目标格、类型白名单和数量限制。
3. 服务端创建真实对象并调用当前 B42.19 同步接口。
4. 使用稳定操作 ID 防止重试重复生成。
5. 对未加载格子的待办队列设置持久化格式、上限、过期和重启恢复规则。

## Project Zomboid Modding Archive

仓库：[PZ-Wiki-Modding/Archive.Project-Zomboid-Modding](https://github.com/PZ-Wiki-Modding/Archive.Project-Zomboid-Modding)

### 身份与状态

- 这是资料档案库，不是运行时 API 或 MOD 依赖。
- 本次读取的默认分支快照为 2026-06-29 的 `12ef04d`，内容包括 Lua 示例、地图资料、建模/动画资源和 The Indie Stone 指南镜像。
- B42 MP 目录保存 `Migration Guide.pdf`、`Project Zomboid_ API for Inventory Items.pdf` 和 `testmod_registries`。
- 仓库根目录没有统一许可证。README 为部分条目记录作者和原始来源，但不能由此推定所有内容都允许复制、修改或重新分发。

### 正确用途

- 官方论坛附件不可下载时，用它读取官方指南镜像，并回到原始 TIS 帖子确认来源。
- 用目录和 README 找到历史教程、示例、作者及原始发布位置。
- 对每个文件单独记录来源版本、作者、许可和证据等级。

### 禁止默认行为

- 不把整个仓库复制进 GodSystem。
- 不把档案中的脚本、模型、贴图、Blend 文件或地图资源视为公共领域。
- 不因文件位于 `TIS guides` 之外的同一仓库，就把它标为官方资料。
- 不把旧示例中的方法签名直接用于 B42.19，而不核对当前原版。

## 最终采用顺序

1. B42.19 本机原版 Lua、脚本和反编译 Java。
2. The Indie Stone 官方帖子及指南；档案仓库只作为镜像。
3. PZwiki 页面，并读取页内版本标记。
4. 同版本参考 MOD 的完整调用链。
5. PZ Community API 等旧版本社区项目，只借鉴架构和算法思想。
