# GodSystem Carry Capacity 2.5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make B42.20.2 carry-capacity application and display follow the vanilla formula, while retaining the medical and MP reconnect fixes in version `42.20_2.5`.

**Architecture:** Keep `GodSystem_CarryCapacity.lua` as the shared authority for reading vanilla capacity, resolving the native multiplier, applying the level bonus, and reporting status. Reuse existing SP/MP player-update boundaries for bounded recalibration; do not add inventory scans or a new protocol.

**Tech Stack:** Lua 5.1, Project Zomboid B42.20.2 Java userdata, PowerShell regression tests, existing Git worktree/Workshop mirror.

## Global Constraints

- Target game: B42.20.2; target version: `42.20_2.5`.
- Preserve `setBandaged` removal and MP session reset; do not change terminal relief cleanup.
- Use explicit B42 Java method calls and existing SP/MP authority boundaries.
- Run the focused runtime test before the unified suite; static success does not replace SP/MP testing.

### Task 1: Add Failing Vanilla-Formula Regression

**Files:**
- Modify: `tools/tests/Test-GodSystemV422024.ps1`
- Modify: `tools/tests/Test-GodSystemV422024Runtime.lua`

- [x] Add assertions requiring a vanilla-capacity helper, native multiplier marker, and periodic carry recalibration call.
- [x] Add mock-player runtime cases for base 14 with neutral, Strong, Weak, and Hungry/Sick/Injured reducers; assert level bonus is applied to the vanilla final and repeated application does not stack.
- [x] Run the focused script and confirm RED because the current module lacks the new helper/behavior.

### Task 2: Implement Shared Formula and Status

**Files:**
- Modify: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_CarryCapacity.lua`

- [x] Implement exact Moodle reducer reads and `nativeCapacity = floor(base * weightMod) - reducers`.
- [x] Resolve native versus previous GodSystem multiplier from runtime state and existing ModData markers.
- [x] Apply `desiredFinal = nativeFinal + levelBonus`, write `targetDelta`, refresh the cache, persist only the migration markers, and report live `actualBonus`.
- [x] Preserve rollback when any write or read-back fails.
- [x] Run the focused runtime test and confirm GREEN.

### Task 3: Reuse Existing Player-Update Boundaries

**Files:**
- Modify: `Contents/mods/GodSystem/42/media/lua/client/GodSystem_Core.lua`
- Modify: `Contents/mods/GodSystem/42/media/lua/client/GodSystem_Network.lua`
- Modify: `Contents/mods/GodSystem/42/media/lua/server/GodSystem_Server.lua`

- [x] At the existing 60-tick player-update boundary, call the shared carry apply/reconcile entry for the local SP player and the authoritative MP server player.
- [x] Keep MP client state application behind the existing server-state handshake and avoid a second business path.
- [x] Extend the lifecycle regression to require SP, MP client, and MP server recalibration hooks.
- [x] Run the focused test and the relevant history tests.

### Task 4: Bump Version and Metadata

**Files:**
- Modify: `Contents/mods/GodSystem/mod.info`
- Modify: `Contents/mods/GodSystem/42/mod.info`
- Modify: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_Config.lua`
- Modify: `workshop.txt`
- Modify: `README_创意工坊上传说明.md`
- Modify: `tools/Test-GodSystem.ps1`
- Modify: `tools/tests/Test-GodSystemV422024.ps1`
- Create: `docs/GodSystem_DevHandoff_CN/89_42.20_2.5_负重公式与重连修复.md`

- [x] Change active version expectations and descriptions to `42.20_2.5` without changing Mod ID or Workshop ID.
- [x] Record the exact formula evidence, changed boundaries, test results, and pending SP/MP checks in the handoff.
- [x] Run focused version assertions before the full suite.

### Task 5: Verify and Deploy

**Files:**
- Runtime mirror: `C:\Users\Admin\Zomboid\Workshop\GodSystem\Contents`

- [x] Run `Test-GodSystemV422024.ps1 -Root .` and `tools/Test-GodSystem.ps1`.
- [x] Run `git diff --check`, encoding checks, and inspect `git status`/diff.
- [x] Mirror only `Contents` with `robocopy /MIR`.
- [x] SHA-256 compare the three handoff files plus carry module between worktree and Workshop.
- [x] Report automated results separately from pending B42.20.2 SP/MP behavior checks.
