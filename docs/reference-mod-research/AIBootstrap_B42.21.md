# B42.21：AI 接入与订阅后自动安装可行性核查

日期：2026-10-10。研究基线：当前 GodSystem `42.21_3.21.5` 工作树、本机 B42.21 游戏文件。

## 结论

目标是玩家取得并启用工坊 MOD、正常启动游戏后，自动完成 AI 网络组件的首次安装；除填写模型 API Key 外，不要求玩家手动运行安装器、复制文件或修改启动参数。

本轮未找到满足目标的正常入口。已检查的关键路径不是单纯缺少示例，而是存在明确限制：原版 MOD 加载不把 JAR 加入类路径；Kahlua 没有执行系统命令或加载本地库的标准模块；Java 桥限制 Runtime/ClassLoader/Desktop；现有文件与浏览器接口不能启动安装器。用户允许自动操作不改变这些技术能力。

这不是对所有潜在代码路径的数学证明，也不是完整安全审计。结论适用于本机补丁、目前检查的正常加载及公开接口。不把修改游戏后的 Java 能力、开发工具中的 Java 调用或 debug 反射当作工坊 MOD 本来拥有的能力。

因此本轮不制作或部署一个无法自行运行的“自动安装器”，不声称已完成 AI 接入。若目标保持不变，需要游戏提供可用的网络接口或组件加载入口，或者发现并验证同补丁受支持的扩展途径。现成的一次安装方案可减少玩家操作，但仍不满足完全自动首次安装。

## 本机证据身份

- 游戏 JAR：`D:\SteamLibrary\steamapps\common\ProjectZomboid\projectzomboid.jar`。
- SHA-256：`e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33`。
- 游戏自带 Java：Zulu OpenJDK 25.0.1。
- 本地反编译工具：已有 CFR 0.152，仅作为阅读工具；输出保留于忽略目录，不发布游戏源码。
- 原生检查编译工具：已有 ECJ 3.40.0；SHA-256 `05cc22a24e7982970f63a405fc6c820bc80b806f27f3c5a6236fc475f8f7152b`。
- 扫描 5,095 个 `zombie/` 游戏类的常量引用；引用匹配只是候选发现，随后阅读相关实现。

## 1. 自动首次安装需要的完整链路

| 步骤 | 本轮证据 | 结果 |
|---|---|---|
| 工坊下载组件文件 | 工坊可分发文件，但文件下载不等于加载执行 | 可交付文件，不能据此判断能运行 |
| MOD 检测当前是否已有组件 | 可以使用受限 Lua 状态和文件接口实现 | 不是主要障碍 |
| 将组件放到会被加载的位置 | 常规写入受缓存/本 MOD 目录约束；原版加载只建立资源映射 | 没有验证到正常的首次加载路径 |
| 启动安装器或直接加载组件 | Kahlua 标准库和 Java 桥的限制，见下文 | 已检查入口不能完成 |
| 改变下一次游戏的启动方式 | 正常 Lua 写入不是任意游戏目录写入；启动时类路径已确定 | 尚无受支持的自动修改链路 |
| 发送 HTTPS、设置认证头、取回回答 | 已发现的内部联网函数不具备可用的完整 Lua 问答链路 | 未验证到 |
| 超时、取消、异步结果回到主线程 | 必须有可用的网络实现才能继续 | 不以 UI 原型代替验证 |

“准备文件”和“执行文件”是两个步骤；不能因为前一步可做就宣称后一步可做。

## 2. MOD 与 Java 加载

代码确认：

- `ZomboidFileSystem.loadMods(List<String>)` 调用 `loadMod`；后者搜索 common 和版本目录，把相对路径加入 `activeFileMap`。
- 当前实现没有在这一过程创建 MOD 类加载器或加载 MOD 自带 JAR。
- 游戏正常启动配置 `ProjectZomboid64.json` 使用 `.` 和 `projectzomboid.jar` 类路径；工坊目录并未因 MOD 启用自动加入此类路径。
- MOD 路径覆盖是游戏资源查找映射，不是操作系统文件复制，也不是 JVM 类加载替换。
- 在 `zombie/` 类中未匹配到 `javaJarFile`、`javaPkgName` 或 `java/net/URLClassLoader` 常量。这只提供辅助证据，不能单独证明不存在任何加载方式。
- `LuaManager.GlobalObject.require` 查找并执行 Lua；它不是 Lua C 模块或 JAR 加载器。

参考框架中 `javaJarFile` 等字段由框架解释，不能写进原版 `mod.info` 后期待原版识别。

## 3. Kahlua、Java 桥与 debug

代码与原生隔离检查确认：

- `J2SEPlatform.setupEnvironment` 注册 Kahlua 自有标准库。
- `OsLib` 仅提供 date/difftime/time；没有 `os.execute`。检查环境没有 `io`、`package` 或 `luajava`。
- `LuaJavaClassExposer` 明确限制 Class、ClassLoader、Module、Runtime、Desktop，并限制反射/方法句柄等类型。
- `LuaManager.validateReflectionAccess` 要求 debug，但即使 debug 开启仍拒绝 Class、ClassLoader、MethodHandles.Lookup。
- “Java 中存在方法”不等于“Lua 能调用该方法”；开发探针使用 Java 执行验证也不等于赋予游戏 MOD 这些能力。

没有通过执行任何系统命令来测试这些拒绝条件。

## 4. 文件接口：修正过宽的判断

| 接口 | 已确认行为 |
|---|---|
| `getFileWriter` | 文本写入缓存 Lua 目录，限制文件扩展名及 `..`；EXE/JAR 名称返回空值 |
| `getModFileWriter` | 写入目标 MOD 的 common 目录；拒绝绝对路径及 `..`；不等于任意游戏目录写入 |
| `getFileOutput` | 能在缓存 Lua 目录写入二进制数据；没有同样的文本扩展名限制 |
| `showFolderInDesktop` | 验证已知路径且要求目标为目录；固定调用 explorer/open/xdg-open |

**不能笼统说“PZ 不能写二进制或准备组件文件”。**本轮已在隔离缓存生成四字节测试文件，确认二进制写入存在。关键缺口仍是执行/加载入口，不是能否把字节写到缓存。

`showFolderInDesktop` 内部虽使用 Runtime.exec，但调用程序固定、参数是目录路径，不能把它当作执行任意安装器的公开接口。本轮没有启动资源管理器或安装器。

## 5. 浏览器与内部网络候选

- `openUrl` 和 Steam 页面入口经过 `LuaManager.isIndieStoneUrl` 检查。本机允许 Steam Community、Project Zomboid、The Indie Stone 和 PZ Wiki 的指定 HTTPS 域名。
- 任意模型 API URL、我们的网页域名和 file URL 未获允许；“有 openUrl 就能打开我们自己的 AI 网页”这一早期建议已更正。
- `PublicServerUtil.callPostJson` 存在：在工作线程发送 JSON，但没有读取并返回响应，也没有任意认证头参数；当前暴露登记没有该类。不能据此宣称普通 Lua 已能接 AI。
- `RCONClient.send` 存在：同步请求，固定 text JSON，返回布尔状态；不提供完整模型响应返回，当前暴露登记没有该类。
- `StackBot` 使用前述 JSON 发送函数用于事件通知；这不是通用模型问答接口。
- GameClient 的 URL 常量候选包含 URLEncoder 的身份验证字符串处理；不能因类名匹配就误判为通用 HTTP 下载入口。
- `CoopMaster.launchServer` 以及 GameClient 的本地服务器启动路径使用固定 Java/服务器入口和分开的参数列表，不提供通用安装器选择。
- `GameWindow.installRequiredLibrary` 是私有的原版 VC 运行库安装路径，调用位置固定，不作为 MOD 安装器接口。

没有为了验证候选而调用真实模型、发送游戏数据或连接外部服务。

## 6. 参考 MOD 与框架

### 橙子 AI 前置

- [PZ AI Server Telemetry，3777330954](https://steamcommunity.com/sharedfiles/filedetails/?id=3777330954)：本地代码以事件文件、受管回复队列连接外部 Bridge。
- [PZ Web Notices，3777409029](https://steamcommunity.com/sharedfiles/filedetails/?id=3777409029)：展示消息/回复，不负责模型调用。
- 作者说明 Bridge 在开服电脑运行；普通玩家不用单独安装 Bridge，服主仍需配置。不是全体用户只订阅即可自动完成首次安装的例子。
- 本机 AI 前置 `mod.info` 为 0.7.15-telemetry，versionMax 仍为 42.20.4；不当作 B42.21 实测兼容证据。

### RimTalk

[项目源码](https://github.com/jlibrary/RimTalk)、[编译配置](https://github.com/jlibrary/RimTalk/blob/main/RimTalk.csproj)确认它使用 C# 组件；其网络客户端能够发请求并取得回复。它说明“订阅加 API Key”的用户体验可以成立，但不能证明 PZ 有相同组件加载能力。

### ZombieBuddy / pz3d Loader

- [ZombieBuddy 安装文档](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/Installation.md)：Windows 自动安装器仍须首次运行，复制组件并修改启动配置；Java MOD 加载还有批准步骤。
- [Java MOD 文档](https://github.com/zed-0xff/ZombieBuddy/blob/master/doc/ModdingGuide.md)：额外加载器解释 javaJarFile/javaPkgName 等元数据。
- [pz3d Loader](https://github.com/pz3d-dev/pz3d-loader)：作者描述为一次安装，后续签名加载器更新跟随 MOD。
- [B42.21 加载签名变动记录](https://github.com/zed-0xff/ZombieBuddy/issues/59)：证明补丁更新也可能影响加载器，采用前需核对具体构建，不能把旧版本安装成功当作当前兼容。

本轮没有安装或实测这些框架，不声称哪个现成版本在本机已通过。

## 7. 原生隔离验证与复现

开发工具：

- `tools/research/AIBootstrapProbe.java`。
- `tools/research/inspect_ai_bootstrap.py`。

命令：

```powershell
python tools/research/inspect_ai_bootstrap.py --game "D:\SteamLibrary\steamapps\common\ProjectZomboid" --compiler ".test-runtime/tooling/ecj-3.40.0.jar"
```

结果：**19 项通过**，包括 Kahlua 标准模块缺失、真实 Java 桥限制、URL 判定、文件接口拒绝、隔离缓存二进制暂存，以及实际 GlobalObject 注册后的 Kahlua 调用。

结果保留在忽略目录 `.test-runtime/ai-bootstrap/result.json`、`native-probe.log`。探针只调用本机游戏方法，未启动完整游戏/世界/网络；不是多人实机验收，也没有对模型接入进行性能测试。二进制暂存仅在进程隔离的 user.home 下生成测试字节，并未创建可执行安装包。

本轮没有修改游戏启动配置、安装组件、改动 GodSystem 运行包、升级版本、部署、提交/推送或覆盖备份。

## 8. 二次复审与后续决策

- 不把文本 writer 拒绝 JAR 误写成所有二进制接口均拒绝；已增加二进制原生检查。
- 不把浏览器 API 的存在误写成任意 URL 均可打开。
- 不把内部 HTTP 方法误写成已经能从 Lua 发模型请求；认证、回复、异步和暴露可调用性必须同时成立。
- 不把资源映射覆盖误写成可以修改 JVM 启动文件或替换 Java 类。
- 不把 debug 设置误写成完全开放反射权限。
- 不把另装 Java 加载器后的自动更新称为原版环境下的自动首次安装。
- 不声称已经穷尽所有代码路径；若出现新的正常扩展入口或游戏补丁，重跑检查并增加针对性验证。

在当前目标不变时，研究结论是**未找到可交付的完全自动首次安装路径**。可以继续核查新的明确候选，但不建议以“必能找到入口”为前提开始整套 AI 功能开发。若接受一次运行安装器，或由服主预先配置 Bridge，另行制定可实际执行的接入方案。
