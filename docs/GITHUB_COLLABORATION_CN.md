# GodSystem GitHub 多设备协作

## 仓库职责

- GitHub 私有仓库是代码、开发文档、测试、本地化源和 Codex 项目规则的共同来源。
- `main` 保存已整合的开发基线；稳定发布状态由标签和版本记录明确标注。
- 当前有 Project Zomboid 和 Steam 环境的设备负责最终实机测试与 Workshop 发布。
- 其他设备可以完整开发和审查，但每个任务使用独立分支，不能两台设备同时写同一分支。

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
