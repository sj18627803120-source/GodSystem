# GodSystem GitHub 多设备协作

## 仓库职责

- GitHub 私有仓库是代码、开发文档、测试、本地化源和 Codex 项目规则的共同来源。
- `main` 保存已整合的开发基线；稳定发布状态由标签和版本记录明确标注。
- 当前有 Project Zomboid 和 Steam 环境的设备负责最终实机测试与 Workshop 发布。
- 其他设备可以完整开发和审查，但每个任务使用独立分支，不能两台设备同时写同一分支。
- 本项目不再依赖或要求 Superpowers 技能。开发流程直接以根目录 `AGENTS.md`、交接文档、官方/原版证据和仓库内 `pz-mod-dev` 技能为准。

## 新设备初始化

1. 克隆仓库。
2. 在 PowerShell 运行 `tools\setup\Install-CodexSkill.ps1`。
3. 让 Codex 先读取根目录 `AGENTS.md` 和 `docs\GodSystem_DevHandoff_CN\00_继续开发入口.md`。
4. 运行 `tools\Test-GodSystem.ps1`，确认测试环境可用。
5. 开始任务前执行 `git switch -c feature/<version-or-topic>`。

本地化生成器需要真实的 Python 3 环境；Windows 的 Microsoft Store `python.exe` 占位符不能作为验证通过的 Python。Lua 编译检查需要 Lua 5.1 `luac`，缺失时测试入口会明确提示跳过。

## 协作约束

- 开始任务前先拉取 `main` 最新提交。
- 一个分支只承载一个明确任务，提交信息说明功能或修复目的。
- 推送后通过 Pull Request 交给另一设备复核；不要直接覆盖远端 `main`。
- 合并前必须检查 `git diff --stat`、相关专项测试、编码检查和 Lua 5.1 编译。
- 不上传备份 ZIP、Steam Workshop 缓存、参考 MOD、日志、临时截图、密码或访问令牌。

## 主测试机流程

1. 在 Git worktree 的独立分支中完成阅读、实现和自动测试。
2. 自动测试通过后，只把 `Contents`、`workshop.txt` 和 `preview.png` 覆盖到 `C:\Users\Admin\Zomboid\Workshop\GodSystem`。
3. 核对仓库与 Workshop 运行文件哈希，再由用户直接进游戏测试。
4. 用户明确确认正常后，更新实测记录并推送当前功能分支；未确认前不把该版本当成兼容或发布基线。
5. `main` 是否合并、是否打标签和是否发布 Workshop，由用户确认后另行决定。

## 证据优先级

1. 当前 B42.19 原版 Lua、脚本和反编译 Java。
2. The Indie Stone 官方迁移指南与 Inventory Items API。
3. 仓库 `docs/reference-mod-research/` 中标记为同版本的证据。
4. 旧版本官方资料和社区 MOD，仅用于弱参考。

详见 `docs/PZ_B42_OFFICIAL_DEVELOPMENT_CN.md`。不要根据记忆猜 Java/Kahlua 方法签名、Timed Action 生命周期或多人同步接口。
