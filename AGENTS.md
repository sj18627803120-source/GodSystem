# GodSystem Repository Workflow

- This repository is the live Project Zomboid test MOD at `C:\Users\Admin\Zomboid\Workshop\GodSystem`.
- Keep `main` as the last integrated development baseline. Create a feature branch before implementing a new version or substantial behavior change.
- Inspect `git status`, `git diff --stat`, and the focused `git diff` before committing.
- Commit only after the relevant GodSystem tests, encoding checks, and Lua 5.1 `luac -p` checks pass.
- Git commits and tags are the primary development history. Do not create a rolling ZIP for every version unless the user explicitly requests one.
- Do not delete existing rolling backups or replace `C:\Users\Admin\Desktop\PJ\GodSystem_v1.15.3_B42_WorkshopUpload.zip` without explicit user approval.
- Keep generated CN/CH translations and the ASCII-only Lua fallback synchronized with their UTF-8 YAML source.
