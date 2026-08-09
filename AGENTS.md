# GodSystem Repository Workflow

- This repository is the complete GodSystem source and may be cloned to any path. The Git worktree is the development source; `C:\Users\Admin\Zomboid\Workshop\GodSystem` is only the live game-test copy.
- Do not use Superpowers skills for this project. Follow this file, the handoff documents, and the bundled `pz-mod-dev` skill directly.
- Keep `main` as the last integrated development baseline. Create a focused feature or fix branch before implementing a new version or substantial behavior change.
- Read `docs/GodSystem_DevHandoff_CN/00_继续开发入口.md` first, then open only the current task's relevant design, official-reference, or history documents.
- Do not guess Project Zomboid APIs. Check the same-version vanilla Lua or decompiled Java first, then official migration material, then same-version reference MOD evidence.
- Before editing, trace the existing call path and define the smallest change and verification target. For bugs, preserve the reported stack trace and add a focused regression when practical.
- Inspect `git status`, `git diff --stat`, and the focused `git diff` before committing.
- Run `tools/Test-GodSystem.ps1` before committing. Historical tests under `tools/tests/legacy` are reference-only unless the changed subsystem requires them.
- Develop and verify in Git first. After automated checks pass, deploy through `tools/workflow/Deploy-ToWorkshop.ps1`, which mirrors the tested source while preserving the Workshop `.git` metadata and verifies the deployed files. Wait for the user's game-test result before merging or treating it as a release baseline; source/test/documentation branches may be pushed to GitHub as test candidates.
- Git commits and tags are the primary development history. Do not create a rolling ZIP for every version unless the user explicitly requests one.
- Do not delete existing rolling backups or replace `C:\Users\Admin\Desktop\PJ\GodSystem_v1.15.3_B42_WorkshopUpload.zip` without explicit user approval.
- Keep generated CN/CH translations and the ASCII-only Lua fallback synchronized with their UTF-8 YAML source.
- Keep project-specific Codex guidance in this repository. Use `tools/setup/Install-CodexSkill.ps1` on a new device to install the shared `pz-mod-dev` skill.
