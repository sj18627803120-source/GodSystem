# GodSystem GitHub 多设备协作

## 仓库职责

- GitHub 私有仓库是代码、开发文档、测试、本地化源和 Codex 项目规则的共同来源。
- `main` 保存已整合的开发基线；稳定发布状态由标签和版本记录明确标注。
- 当前有 Project Zomboid 和 Steam 环境的设备负责最终实机测试与 Workshop 发布。
- 其他设备可以完整开发和审查，但每个任务使用独立分支，不能两台设备同时写同一分支。
- 本项目不再依赖或要求 Superpowers 技能。开发流程直接以根目录 `AGENTS.md`、交接文档、官方/原版证据和仓库内 `pz-mod-dev` 技能为准。
- GitHub `main` 在 2026-09-23 整理前仍为 `42.20_3.5`；当前开发分支 `codex/fix-independent-carry` 的工作树为 `42.20_3.18.1`。最近已由用户实机验收并备份的是 `42.20_3.16`，3.17–3.18.1 尚待实机测试。目标补丁为 B42.20.4。以[当前技术支援入口](开发技术支援/README.md)和交接 00 为新设备入口，旧版文档只作历史证据。

## 新设备初始化

1. 克隆仓库。
2. 在 PowerShell 7 运行 `tools\setup\Install-CodexSkill.ps1`。
3. 让 Codex 先读取根目录 `AGENTS.md`、`docs\开发技术支援\GodSystem_工程文档.md` 和 `docs\GodSystem_DevHandoff_CN\00_继续开发入口.md`。
4. 运行 `tools\Test-GodSystem.ps1` 和 `tools\tests\run_lua_tests.py`，确认测试环境可用。
5. 开始任务前执行 `git switch -c feature/<version-or-topic>`。

本地化生成器需要真实的 Python 3 环境；Windows 的 Microsoft Store `python.exe` 占位符不能作为验证通过的 Python。Lua 编译检查需要 Lua 5.1 `luac` 或仓库已配置的 Lua 5.1 VM；缺失项必须明确记录。Windows 推荐使用 PowerShell 7、Git for Windows/Git Bash 和 7-Zip，具体分工见仓库 Skill 的 `references/windows-tooling.md`。

## 协作约束

- 开始任务前先核对远端目标分支和本地改动；有未提交工作树时不要直接拉取旧 `main` 覆盖当前开发状态。
- 一个分支只承载一个明确任务，提交信息说明功能或修复目的。
- 常规协作优先推送功能分支并通过 Pull Request 复核；把测试版推到开发分支不表示通过实机验收。只有用户明确要求更新 `main` 时才完成对应集成。
- 合并前必须检查 `git diff --stat`、相关专项测试、编码检查和 Lua 5.1 编译。
- 不上传备份 ZIP、Steam Workshop 缓存、参考 MOD、日志、临时截图、密码或访问令牌。

## 主测试机流程

1. 在 Git worktree 的独立分支中完成阅读、实现和自动测试。
2. 自动测试通过后，先确认当前用户实际测试目录，再只同步 `Contents`、`workshop.txt` 和 `preview.png`。
3. 核对仓库与 Workshop 运行文件哈希，再由用户直接进游戏测试。
4. 通常在用户确认实机正常后更新实测记录并推送功能分支；用户明确要求提前同步开发分支时可推送，但必须标记待验收，不能把它当成兼容或发布基线。
5. `main` 是否合并、是否打标签和是否发布 Workshop，由用户确认后另行决定。

## 证据优先级

1. 当前目标补丁 B42.20.4 原版 Lua、脚本、反编译 Java与实机复现。
2. 明确适用于同补丁的 The Indie Stone 官方资料。
3. 仓库 `docs/reference-mod-research/` 中标记为同补丁的证据。
4. 其他 B42 版本官方资料和社区 MOD，仅用于导航或弱参考。

详见 `docs/PZ_B42_OFFICIAL_DEVELOPMENT_CN.md`。不要根据记忆猜 Java/Kahlua 方法签名、Timed Action 生命周期或多人同步接口。
