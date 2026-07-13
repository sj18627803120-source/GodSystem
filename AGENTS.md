# GodSystem Repository Workflow

- This repository is the complete GodSystem source and may be cloned to any path. On the primary release device it is also the live Project Zomboid test MOD directory.
- Keep `main` as the last integrated development baseline. Create a feature branch before implementing a new version or substantial behavior change.
- Read `docs/GodSystem_DevHandoff_CN/00_继续开发入口.md` first, then open only the current task's relevant design or history documents.
- Inspect `git status`, `git diff --stat`, and the focused `git diff` before committing.
- Run `tools/Test-GodSystem.ps1` before committing. Historical tests under `tools/tests/legacy` are reference-only unless the changed subsystem requires them.
- Git commits and tags are the primary development history. Do not create a rolling ZIP for every version unless the user explicitly requests one.
- Do not delete existing rolling backups or replace `C:\Users\Admin\Desktop\PJ\GodSystem_v1.15.3_B42_WorkshopUpload.zip` without explicit user approval.
- Keep generated CN/CH translations and the ASCII-only Lua fallback synchronized with their UTF-8 YAML source.
- Keep project-specific Codex guidance in this repository. Use `tools/setup/Install-CodexSkill.ps1` on a new device to install the shared `pz-mod-dev` skill.
