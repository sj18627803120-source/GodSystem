# GodSystem v1.16.63 Space Relief Implementation Plan

> 历史实施计划：按根目录 `AGENTS.md` 和任务复选框逐项执行，不依赖任何 Superpowers 技能。

**Goal:** Replace the failed oversized terminal-capacity experiment with a hidden native negative-weight item controlled by a paid, configurable "空间减载" upgrade.

**Architecture:** `GodSystem_TerminalRelief.lua` owns relief formulas, internal-item creation, validation, rollback snapshots, and escaped-item cleanup. `GodSystem_TerminalUpgrades.lua` remains the single terminal-upgrade facade and delegates relief application to that module. SP mutates locally; MP mutates only in `GodSystem_Server.lua` and returns the existing structured state/result payloads.

**Tech Stack:** Project Zomboid B42.19 Lua 5.1, Kahlua Java bindings, PowerShell static tests, Lua runtime tests, UTF-8 YAML localization generator.

## Global Constraints

- Version becomes `1.16.63` in config, both `mod.info` files, and `workshop.txt`.
- Defaults are fixed price 2000, 5 relief per level, maximum relief 2000.
- Add three sandbox/admin settings and increase metadata parity from 68 to 71.
- Do not register `OnTick`, new `OnPlayerUpdate`, minute events, or periodic inventory scans.
- Do not modify shared `ScriptItem` weight or hunger definitions at runtime.
- Do not copy source, names, recipes, or assets from the reference Mod.

---

### Task 1: Failing v1.16.63 Contract Tests

**Files:**
- Create: `tools/tests/Test-GodSystemV11663.ps1`
- Create: `tools/tests/Test-GodSystemV11663Runtime.lua`
- Modify later: `tools/Test-GodSystem.ps1`

**Interfaces:**
- Consumes: repository paths and the existing v1.16.62 test conventions.
- Produces: static and Lua behavior contracts for the new shared module and integration points.

- [ ] Write tests for version, item script, 71 settings, sandbox keys, relief formulas, protection, UI route, MP route, and removal of `GodSystem_TerminalCapacity.lua`.
- [ ] Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/tests/Test-GodSystemV11663.ps1 -Root <worktree>`.
- [ ] Verify it fails because `GodSystem_TerminalRelief.lua` and v1.16.63 metadata do not exist.

### Task 2: Shared Relief Engine And Item Definition

**Files:**
- Create: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_TerminalRelief.lua`
- Modify: `Contents/mods/GodSystem/42/media/scripts/GodSystem_Items.txt`
- Modify: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_Config.lua`
- Modify: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_TerminalUpgrades.lua`
- Delete: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_TerminalCapacity.lua`

**Interfaces:**
- Produces: `getLevel(data)`, `setLevel(data, level)`, `getOffset(data)`, `getMaxLevel()`, `getUpgradeInfo(data)`, `snapshot(terminal)`, `restore(snapshot)`, `ensureTerminal(terminal, data)`, `isReliefItem(item)`, and `removeEscapedFromPlayer(player, ownedTerminal)`.

- [ ] Define the hidden `base:food` item with `HungerChange = -1`, `Weight = 1`, `CantEat = true`, and `Hidden = true`.
- [ ] Implement formula settings through `GodSystemAdminConfig.getSetting()` with config fallbacks.
- [ ] Create/update exactly one top-level internal item, set favorite/unwanted, write `hungChange = offset / 100`, and verify actual weight.
- [ ] Clamp capacity levels to 8, delegate relief upgrade metadata, and keep rollback transactional.
- [ ] Run the v1.16.63 runtime test and verify it passes.

### Task 3: SP And MP Transaction Integration

**Files:**
- Modify: `Contents/mods/GodSystem/42/media/lua/client/GodSystem_Core.lua`
- Modify: `Contents/mods/GodSystem/42/media/lua/client/GodSystem_Network.lua`
- Modify: `Contents/mods/GodSystem/42/media/lua/server/GodSystem_Server.lua`
- Modify: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_Protocol.lua`

**Interfaces:**
- Consumes: `upgradeTerminal("relief")` and shared relief snapshot/apply APIs.
- Produces: `upgradeType="terminalRelief"` through the existing idempotent `upgradeSystem` command.

- [ ] Add SP relief purchase with apply-before-charge and rollback.
- [ ] Add MP terminal-relief mapping to the existing upgrade command and server-authoritative settlement.
- [ ] Audit on claim/recovery, terminal discovery, hello, explicit refresh, and auto-recycle boundaries.
- [ ] Remove the v1.16.62 periodic terminal re-registration block from server player updates.
- [ ] Synchronize added/changed internal item state with existing container/item sync helpers.

### Task 4: Protection, UI, Settings, And Localization

**Files:**
- Modify: `Contents/mods/GodSystem/42/media/lua/client/GodSystem_UI.lua`
- Modify: `Contents/mods/GodSystem/42/media/lua/shared/GodSystem_AdminConfig.lua`
- Modify: `Contents/mods/GodSystem/42/media/sandbox-options.txt`
- Modify: `tools/localization/godsystem_v11645_localization.yml`
- Regenerate: CN/CH `IG_UI`, `Sandbox.json`, item names/tooltips, and Lua fallback.

**Interfaces:**
- Produces: fifth terminal action button, relief status fields, and settings `TerminalReliefUpgradeCost`, `TerminalReliefPerLevel`, `TerminalReliefMaxOffset`.

- [ ] Show `升级减载` with cost/max state and a non-selectable relief status row.
- [ ] Add the three base-group admin/sandbox settings with defaults 2000/5/2000.
- [ ] Exclude the internal item from recycle, auto-recycle, listing, lottery, task candidates, history counts, and empty-state checks.
- [ ] Generate all localization layers from the UTF-8 YAML source.

### Task 5: Version, Regression, Git, And Live Deployment

**Files:**
- Modify: `Contents/mods/GodSystem/mod.info`
- Modify: `Contents/mods/GodSystem/42/mod.info`
- Modify: `workshop.txt`
- Modify: current handoff, test checklist, and version history documents.

- [ ] Add v1.16.63 to `tools/Test-GodSystem.ps1` and run the full suite.
- [ ] Run Lua 5.1 `luac -p` on every packaged Lua file.
- [ ] Run strict encoding and CN/CH parity checks.
- [ ] Inspect `git diff --check`, focused diff, and worktree status.
- [ ] Commit the focused feature branch.
- [ ] Mirror only runtime Workshop files into `C:\Users\Admin\Zomboid\Workshop\GodSystem`.
- [ ] Verify hashes, version, and Lua compilation in the live test directory.
