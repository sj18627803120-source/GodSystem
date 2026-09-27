---
name: pz-mod-dev
description: Project Zomboid Build 42 mod engineering workflow. Use when Codex needs to inspect, debug, modify, localize, test, package, back up, or document a PZ mod, including Lua client/server/shared code, Workshop structure, SP/MP authority, UI, inventory transactions, sandbox settings, equipment, tasks, economy, and GodSystem development handoffs.
---

# Project Zomboid Build 42 Mod Development

## Required Workflow

1. Confirm the exact game patch, repository/workshop directory, requested deliverable, and whether the user authorized deployment, publication, or backup replacement.
2. Read repository instructions and the relevant call path before proposing code. Use `rg`, `rg --files`, focused file reads, logs, and existing tests.
3. For bugs, preserve the stack and trace the smallest failing path through UI, client request, authority validation, mutation, synchronization, and result. Do not treat a nearby third-party error as this mod's fault without a matching path.
4. Use evidence in this order: same-patch vanilla/official source, same-patch live reproduction, same-patch reference mods, newer/older official material, then old community examples. Java method existence does not prove a Kahlua-callable overload.
5. Label conclusions as code-confirmed, live-tested, inferred, or still needing in-game validation. Never turn an inference into a confirmed defect or compatibility promise.
6. Make the smallest compatible change. Preserve unrelated user changes, IDs, save/network formats, and published behavior unless the user approves a migration or redesign.
7. Keep unpublished test builds free of compatibility baggage unless the user explicitly asks. Do not bump the version for every fix; bump when the release boundary or user request calls for it, and update all version surfaces together.
8. Run focused regression tests, generated-file checks, UTF-8 checks, command parity, package validation, and Lua 5.1 compilation. State exactly what was automated and what was tested in game.
9. Update the current handoff/changelog with decisions, evidence, remaining risks, and verification commands.
10. Do not deploy to Steam Workshop, publish, commit, push, tag, or replace a stable ZIP unless the user explicitly authorizes that action.

## Current GodSystem Repository Discovery

For GodSystem, read `docs/开发技术支援/README.md`, its engineering document, and the top `当前基线` section of `docs/GodSystem_DevHandoff_CN/00_继续开发入口.md` before using an older handoff. As of 2026-09-24 the worktree and user-accepted rolling backup are `42.20_3.18.2` on B42.20.4. The user's overall test pass does not individually establish SP/host/dedicated-server behavior for splash combat, multiplayer fixes, or the utility generator; retain the specific game checks in handoffs 110–113. Never infer acceptance from an automated suite or from pushing a development branch.

The working source is `GodSystem-main`. A sibling `历史资料` directory contains old UI test code, a discarded candidate ZIP, and notes; it is not a deployment or recovery source. The installable skill source is `tools/codex/skills/pz-mod-dev`; `docs/开发技术支援/skill-backup/pz-mod-dev` is a synchronized documentation backup. Update the repository source first, validate it, then synchronize both copies when the user asks to update the skill.

Read `references/pz-b42-patterns.md` completely when the task touches multiplayer authority, inventory/economy transactions, equipment, context-menu performance, UI layers/lists, sandbox tasks, localization, or packaging.

On Windows, read `references/windows-tooling.md` before installing development tools, composing non-trivial shell commands, packaging a backup, or diagnosing encoding/path behavior. Prefer the system PowerShell 7, Git for Windows/Git Bash, and 7-Zip roles documented there instead of relying on Windows PowerShell 5.1 or ad-hoc ZIP code.

## Repository and Package Safety

- Treat the repository as the editable source. Treat Steam Workshop and live test copies as deployment targets, not source-of-truth folders.
- Keep `id=` and Workshop metadata stable unless the user explicitly requests a new entry. Never rewrite user-authored Workshop description text as a side effect of development.
- Typical B42 package shape:

```text
WorkshopRoot/
  workshop.txt
  preview.png
  Contents/mods/ModId/
    mod.info
    42/
      mod.info
      media/lua/{client,server,shared}/
      media/scripts/
```

- Check both `mod.info` files, runtime version constants, Workshop version text, generated translations, and release notes when a version changes.
- Prefer Git history for routine development. Create or replace a rolling ZIP only when the user asks or the project rule explicitly requires it.
- Build a replacement ZIP at a temporary exact path, validate required entries and embedded version, then replace the one intended archive. Exclude `.git`, test runtimes, caches, and temporary files.

## Runtime Boundaries

- `shared`: schemas, deterministic rules, protocol constants, generated fallback text, and helpers safe on both sides.
- `client`: UI, local selection snapshots, presentation caches, SP adapters, and the MP request bridge.
- `server`: authoritative MP persistence, object resolution, validation, transactions, and command routing.
- Guard environment-specific entry files. A file under a server directory may load in SP; directory placement alone is not an authority check.
- Avoid permanent per-tick scans. Use lifecycle events, explicit operations, cached known references, low-frequency real-time throttles, and temporary bounded workers that unregister when finished.

## Authority and Transactions

- The client submits intent and stable identifiers, never trusted prices, success results, ownership, or item snapshots.
- The authority re-resolves the player, account, real item/container/vehicle, distance, feature switch, configuration, quote, balance, and expected revision immediately before mutation.
- Paid or destructive operations follow: validate → record intent/snapshot → charge/reserve → mutate → verify → commit → synchronize.
- Preserve the exact bank/cash split for rollback. If physical cash restoration fails, preserve value through the documented fallback and report it honestly.
- Use globally unique operation IDs plus normalized request fingerprints and bounded persistent `processing/done/unknown` results. Identical retries return the original result; reused IDs with different payloads are rejected.
- Expected business refusals return structured result codes. Do not call `error()` for insufficient funds, stale quotes, missing items, or disabled features: B42 Kahlua can still log a red error even when an outer `pcall` catches it.
- True engine/programming exceptions remain exceptional and must trigger the transaction rollback path.

## UI, Localization, and Sandbox Rules

- Keep the main mod window on the normal layer; place owned secondary windows and their confirmation dialogs above it. Avoid global UI class overrides or per-frame layer sorting.
- Never scan inventory, rebuild prices, read files, or request server state from `prerender`, row drawing, resize, or routine tab switching.
- Reused lists must restore selection by stable IDs, reset scroll animation/height, synchronize the child scrollbar geometry after resize, and clip submitted row backgrounds/text to the viewport.
- Copy theme color tables per control. B42 `ISButton:setEnable(false)` mutates its color objects and can contaminate every window sharing the same table.
- Hide disabled feature entry points, trackers, and sub-blocks in the UI, while retaining authority-side feature checks for old clients and direct commands.
- When a UTF-8 YAML/generator exists, it is the localization source of truth. Generate CN/CH JSON, required legacy text tables, sandbox text, and Lua fallback together; never patch just one layer.
- Inventory item names and tooltips need their own `ItemName.json` and `Tooltip.json` coverage. A different translation mod making them Chinese on one machine is not proof this mod is complete.
- CN and CH are separate PZ language codes. Mirroring simplified Chinese into both is a project policy, not an engine requirement; document the chosen policy.
- Escape literal percent signs required by PZ formatted translations, and validate for U+FFFD/mojibake with explicit UTF-8 reads rather than console appearance.
- Sandbox labels and tooltips must explain the unit, base/bonus relationship, zero behavior, timing, and whether changes affect existing or only newly generated state.
- Never let a client-local `SandboxVars` read overwrite a newer server-authored runtime snapshot.

## Validation

- Prefer the repository's own test runner and generation checks. Add a focused regression for every reproduced bug when practical.
- Compile every packaged Lua file under Lua 5.1. Main chunks have a 200-local limit; split modules or attach helpers to an existing namespace rather than adding endless top-level locals.
- Validate all client commands have handlers, all generated translation key sets agree, all item script names/tooltips exist, and no feature switch is UI-only.
- Performance tests must cover realistic large selections/inventories and record traversal counts or phase costs, not just wall-clock UI impressions.
- A successful Lua mock test does not prove Java/Kahlua calls, rendering, item persistence, or multiplayer synchronization. Keep target-patch SP/MP validation explicit.

## Reference Research

When present, start from `docs/reference-mod-research/README.md`, `docs/PZ_B42_游戏本体API技术参考.md`, and the latest handoffs. Treat version-labelled research as navigation evidence until rechecked against the target patch. Record symbols, paths, behavior, limits, and adoption guidance; do not copy third-party code or assets without permission and licensing.

The B42.19 API guide and reference reports that call B42.19 “same version” predate the current B42.20.4 target. Use `docs/开发技术支援/参考资料索引.md` to distinguish original evidence from historical navigation notes.
