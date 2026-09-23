# GodSystem 开发技术支援

本目录是当前工程资料入口。GitHub `main` 截至本次整理前仍停在 `42.20_3.5`；本地开发树为 `42.20_3.18.1`。后者已通过自动检查并部署测试副本，仍待 SP、房主联机和专用服务器实机验收。最近一次用户验收且更新滚动备份的版本是 `42.20_3.16`。同步 GitHub 的开发分支不表示 3.17–3.18.1 已通过实机验收或已发布 Workshop。

## 从这里开始

1. [工程文档](GodSystem_工程文档.md)：仓库结构、运行边界、核心调用链、配置/存档、验证与交付。
2. [当前交接入口](../GodSystem_DevHandoff_CN/00_继续开发入口.md)：实时基线；[最新交接 112](../GodSystem_DevHandoff_CN/112_v42.20_3.18.1_水电一体机.md) 记录待测项。
3. [版本记录](../GodSystem_DevHandoff_CN/07_版本记录.md)：版本差异，旧段落只代表当时状态。
4. [参考资料索引](参考资料索引.md)：原版/官方证据与参考 MOD 的适用边界。
5. [技能备份](skill-backup/pz-mod-dev/SKILL.md)：与 `tools/codex/skills/pz-mod-dev` 同步的完整技能快照，供 GitHub 浏览和恢复；安装以仓库 `tools/setup/Install-CodexSkill.ps1` 为准。

## 资料分工

- `Contents/`：MOD 运行包，修改后才需要游戏部署。
- `tools/`：本地化生成器、行为/静态测试、UI 工具和可安装技能。
- `docs/GodSystem_DevHandoff_CN/`：按时间编号的实施与验收记录；历史交接不反向改写。
- `docs/reference-mod-research/`：第三方 MOD 的分析，不包含第三方源代码。
- 本目录：面向新接手者的当前工程概览和技能备份。

本次资料整理不修改玩家存档格式、Workshop 身份或运行包版本。
