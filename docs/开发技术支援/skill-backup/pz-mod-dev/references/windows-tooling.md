# Windows Development Tooling

Read this reference for Windows setup, shell choice, encoding-sensitive work, repository operations, and backup packaging.

## Installed Roles

- PowerShell 7: use the system application alias at `C:\Users\wan20\AppData\Local\Microsoft\WindowsApps\pwsh.exe` on this workstation. It is for Windows APIs, registry/package inspection, native `.ps1` tests, and simple filesystem checks. Do not silently fall back to Windows PowerShell 5.1 for UTF-8-sensitive scripts.
- Git for Windows: use `C:\Program Files\Git\cmd\git.exe` for Git commands and `C:\Program Files\Git\bin\bash.exe` when a repository script genuinely expects Bash. Keep repository paths quoted and prefer Git's own path handling over piping its output through another shell.
- 7-Zip: use `C:\Program Files\7-Zip\7z.exe` for rolling ZIP creation, integrity testing, and entry inspection. Do not implement a critical backup with an ad-hoc `System.IO.Compression` loop or assume `Compress-Archive` preserved the intended root.

Discover paths on another workstation instead of copying these paths blindly. Record the selected executable and version in the handoff when it affects reproducibility.

## Shell Selection

- Use `rg`/`rg --files` for search, `git` directly for repository state, `apply_patch` for source edits, Python for existing deterministic generators/tests, and 7-Zip for archives.
- Keep PowerShell commands small. Use arrays or literal paths rather than constructing command strings, and pass UTF-8 explicitly when reading generated/localized content.
- Use Git Bash for existing Bash scripts and familiar text pipelines, not as an automatic wrapper around every Windows command. Do not enumerate deletion/move targets in one shell and execute the destructive action in another.
- Do not reuse `$HOME`, `$home`, or `$CODEX_HOME` as task variables. Do not treat console mojibake as file corruption; validate bytes/text with the repository checks.

## Git Workflow

Run Git from the repository root:

```powershell
& 'C:\Program Files\Git\cmd\git.exe' status --short --branch
& 'C:\Program Files\Git\cmd\git.exe' diff --check
& 'C:\Program Files\Git\cmd\git.exe' diff --stat
```

Before a push, confirm the exact branch, remote URL, commit range, version surfaces, generated files, and test result. Push only when the user explicitly authorizes it. Never put access tokens in commands, logs, repository files, or Skill content.

## Test Workflow

Run PowerShell-native validation under PowerShell 7:

```powershell
& 'C:\Users\wan20\AppData\Local\Microsoft\WindowsApps\pwsh.exe' -NoProfile -File '.\tools\Test-GodSystem.ps1'
```

Run the Lua 5.1 VM behavior suite through its repository Python entry. If an independent `luac` is unavailable, report that exact gap; a mock VM does not prove Java/Kahlua overloads, UI rendering, persistence, or MP synchronization.

## Backup Workflow

GodSystem keeps one working MOD directory and one rolling ZIP only when the user asks. Build at a temporary exact path, exclude `.git`, `.test-runtime`, caches, existing archives, logs, and third-party references, then validate before replacing the existing ZIP.

Use 7-Zip to create and test the candidate, but verify semantics separately:

1. Inspect the archive root and required entries with `7z l -slt`.
2. Run `7z t` and require success.
3. Read both embedded `mod.info` files and verify the expected version.
4. Verify `workshop.txt`, `preview.png`, and the intended `Contents/mods/GodSystem` hierarchy.
5. Confirm excluded directories are absent, count entries, and compute SHA-256.
6. Only then replace the one exact rolling ZIP and remove the temporary candidate.

Do not infer correctness from a successful compression exit code. Wrong root nesting, omitted metadata, backslash-only entry names, or accidental cache inclusion are package failures even when the archive opens.
