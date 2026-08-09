# GodSystem 开发、测试与 GitHub 交接流程

## 目录职责

```text
C:\Users\Admin\Documents\GodSystem-Dev\          # 唯一权威 GitHub 开发仓库
C:\Users\Admin\Documents\GodSystem-Worktrees\    # 临时功能工作树
C:\Users\Admin\Documents\GodSystem-Archives\     # 本地归档，不推送第三方源码或旧 ZIP
C:\Users\Admin\Zomboid\Workshop\GodSystem\      # 游戏测试镜像，不作为开发 Git 源
```

开发仓库必须有正确的 GitHub `origin`。Workshop 里的 `.git` 不是权威历史；在 GitHub 已包含当前测试基线且部署哈希核验完成前，不删除它，也不从它推送。

## 每轮固定流程

1. 游戏实测或人工修改发生在 Workshop 时，先以 Workshop 作为本轮输入。运行 `tools/workflow/Start-FeatureFromWorkshop.ps1` 创建新工作树；它复制内容时排除 `.git`，再从权威 Git 仓库建立 `codex/feature-<名称>` 分支。
2. 在功能工作树里开发。修改前阅读对应交接文档；修改后运行 `tools/Test-GodSystem.ps1` 和本轮专项测试。
3. 自动测试通过后，运行 `tools/workflow/Deploy-ToWorkshop.ps1 -ConfirmDeployment` 将整个工作树镜像到 Workshop。脚本排除 `.git`，部署后逐文件哈希比对。
4. 在游戏内完成 SP/MP 清单后，记录结果，提交源码、测试、交接和可复用技术经验到功能分支并推送 GitHub。确认后再合并 `main`、打版本标签。
5. 下一项计划再次从 Workshop 创建新功能工作树。旧功能工作树仅在 GitHub 已核验可恢复后移除；第三方 MOD 源码、历史 ZIP 和临时构建产物只进本地归档。

## 安全规则

- 不直接在 Workshop 编码；它只用于部署和游戏验证。
- 不把 `File\` 下的第三方 MOD 原始源码上传 GitHub。仓库只保留自己的研究结论和来源说明。
- 部署脚本检测到 Workshop 有未确认 Git 改动时默认拒绝覆盖。若这些改动已被本轮工作树吸收，才显式使用 `-AllowDestinationChanges`。
- 任何清理都先确认 GitHub 分支/标签或本地 Git bundle 可恢复；旧快照先归档，不能把未推送提交当作垃圾删除。
