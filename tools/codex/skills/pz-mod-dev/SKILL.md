---
name: pz-mod-dev
description: Project Zomboid mod development workflow for Build 42/B42.19 and similar versions. Use when Codex needs to inspect, modify, debug, localize, package, or document a Project Zomboid mod, especially Lua client/server/shared code, Workshop folder structure, SP/MP compatibility, item scripts, UI, tasks, economy, teleport, reference-mod research, or GodSystem-style development handoff work.
---

# Project Zomboid MOD Development

## Core Workflow

1. Confirm the target game version, mod directory, and whether the user wants live-test edits or stable backup edits.
2. Use the direct repository workflow: clarify requirements, inspect the existing call path, verify B42.19 APIs against vanilla or official evidence, define the smallest change, implement on a Git branch, and run fresh verification before handoff. For bugs, trace the stack and data flow to the root cause before editing. Do not guess method signatures or silently expand scope.
3. Read the existing mod before designing changes. Prefer `rg`, `rg --files`, and focused file reads.
4. Check same-version official docs or vanilla files first when available; then inspect same-version reference mods; then use older docs/mods only as weaker evidence.
5. Make the smallest change that matches the existing mod style. Do not refactor unrelated systems while fixing one feature.
6. Preserve single-player behavior unless the user explicitly asks to redesign it.
7. For functional changes, bump the mod version and update handoff notes/changelogs.
8. When the MOD is in Git, use focused commits and user-confirmed stable tags as the primary version history. Create rolling ZIP backups only when the user explicitly requests them or before a risky directory/package migration; do not infer that every version bump needs a ZIP.
9. Run static checks after edits: command parity, version consistency, encoding sanity, path/package structure, and obvious Lua string/block issues.
10. Do not replace stable backups or zip packages until the user confirms the live build is stable.

For detailed patterns learned from GodSystem and reference mods, read `references/pz-b42-patterns.md` when working on multiplayer, packaging, localization, item scripts, or UI stability.

## Reference Research Workflow

When the current repository contains `docs/reference-mod-research/README.md`, read that index before relying on internet summaries or asking for local third-party source trees. The library is designed to be sufficient for a second development machine that has only the Git repository.

When `docs/PZ_B42_游戏本体API技术参考.md` is present, use it as a same-version API navigation index. It is derived from B42.19 vanilla Lua call sites, not an official interface contract: verify the exact environment, Kahlua-callable overload, and authority path against the cited vanilla file or a minimal live test before implementation.

- Select evidence by target version: same-version vanilla/official files first, then `B42.19 同版本证据`, then `旧 B42 参考`, and use `B41 弱参考` only for architecture.
- Keep four claim types distinct: `代码确认`, `作者声明`, `合理推断`, and `待实机验证`.
- A source comment or Workshop MP claim does not prove server authority. Trace request, server validation, mutation, synchronization, result, refund, and retry behavior.
- Never promote an inferred risk into a confirmed defect without a reproduction, log, or explicit code path that guarantees the failure.
- Do not copy or commit third-party source/assets. Record relative source paths, symbol names, behavior summaries, limits, search terms, and adoption guidance.
- When a stable cross-source rule is promoted into this skill, retain a link to at least one source report in `references/pz-b42-patterns.md`.

## Direct Engineering Workflow

- For new features, UI, economy, or multiplayer changes, confirm the business rules, scope, failure paths, and acceptance checks before editing.
- For multi-file or high-risk changes, write a short task checklist with affected files, protocol/save impact, rollback behavior, and verification commands. Do not use a plan as permission to refactor unrelated code.
- For bugs, preserve the stack trace, reproduce or model the smallest failing path, compare against a working same-version example, and add a focused regression test when practical.
- For independent research, read-only audits may be separated by file or topic. Never let concurrent workers edit the same Lua file, decide final architecture independently, or replace the main integration and verification pass.
- Before handoff, run the relevant tests, encoding checks, and Lua 5.1 compilation. State exactly what was verified and what still needs game or MP testing.

Subagent boundaries:

- Subagents may research, compare reference mods, audit docs/code, or implement a bounded task with a disjoint file ownership set when the user has authorized subagent work.
- Do not let multiple subagents edit the same Lua files in parallel.
- Do not let a subagent bypass the main plan, decide final architecture alone, overwrite user edits, or replace main-agent verification.
- The main agent owns integration, version bump decisions, Git/backup decisions, final static checks, and the final explanation to the user.

## Directory Checklist

Use this common Workshop shape:

```text
WorkshopRoot/
  workshop.txt
  preview.png
  Contents/
    mods/
      ModFolder/
        mod.info
        42/
          mod.info
          media/
            lua/
              client/
              server/
              shared/
            scripts/
            textures/
            ui/
```

Check both root `mod.info` and `42/mod.info` when bumping versions. Keep `id=` stable unless the user asks for a new Workshop entry.

## Lua Placement

- `shared`: config, prices, localization fallback, data definitions safe for both sides.
- `client`: UI, local inventory scanning, local-only SP logic, MP network bridge.
- `server`: MP authoritative or semi-authoritative operations, persistent MP `ModData`, command handlers.

Guard environment-specific files:

```lua
if not (isClient and isClient()) then return end
if not (isServer and isServer()) then return end
```

## Multiplayer Design

Choose MP authority based on the user's goal:

- Strict economy: server validates most state and sends state snapshots.
- Compatibility-first: client computes low-risk progress, server validates only real item/currency receive/remove operations.

For compatibility-first B42 mods:

- Trust client progress for kill, move, survive, spend, buy, and similar non-item tasks.
- Validate real items for buy, sell, recycle, waist/container actions, and item-turn-in tasks.
- Use command handlers for operations that change inventory or persistent data.
- Avoid requesting server state on every UI tab switch. Sync on UI open, key operations, and a low-frequency background timer.
- Batch frequent signals such as zombie kills; do not send every update tick.
- Treat client operation IDs as transaction identifiers for paid or consumable commands. Generate IDs that remain unique across reconnects and Lua reloads, bind each ID to a normalized request fingerprint, and persist a bounded `processing/done/unknown` result cache under stable player identity in server `ModData`. On server restart, convert leftover `processing` entries to `unknown`; retry an identical timed-out request with the same ID, but reject the same ID with different payload instead of charging twice.
- When a transaction draws from multiple sources, retain the exact bank/cash split. Refund the original sources on failure; if physical currency restoration fails, preserve the value by crediting the bank balance and report the degraded refund path honestly.

## B42 Attribute XP

- Enumerate standard and standard-compatible MOD perks with `Perks.getMaxIndex()`, `Perks.fromIndex()`, and `PerkFactory.getPerk(perk)`. Read the registered perk object's parent, name, and `getTotalXpForLevel()` curve; skip category nodes and incomplete custom XP systems.
- B42.19's own player-stats UI applies no-multiplier XP with `player:getXp():AddXP(perk, amount, false, false, false, false)`. Re-read XP after the call and settle against the actual delta rather than assuming the requested amount was applied.
- In MP, re-resolve the perk, XP curve, price, balance, and actual payment sources on the server. Call `SyncXp(player)` after mutation; if synchronization fails after XP was already applied, keep the purchase authoritative, record a pending resync, and retry on reconnect instead of refunding and granting free XP.
- Unless same-version evidence proves otherwise, advertise compatibility only with the standard ten-level `PerkFactory` XP model.

## B42 Vehicle Repair

- Resolve multiplayer vehicles on the server with `getVehicleById(vehicleId)`, then validate the real consumable, floor, distance, and vehicle state before mutation.
- B42.19's vanilla server vehicle command ultimately calls `vehicle:repair()`. A paid MOD item may call that server-side method after its own validation; do not expose a client-authoritative repair path, and do not claim compatibility with vehicles that replace `BaseVehicle` repair behavior.
- Keep SP paid repair behind the same command boundary when direct client mutation proves ineffective. A guarded SP server Lua file can handle the existing command locally, consume/refund the real item, call the shared repair helper, and return a structured result without adding a second business path.
- After full repair, refresh part and bullet statistics and transmit each part's condition, inventory item, and ModData where those methods exist. Verify the real post-repair damage summary before reporting success.
- Some MOD vehicles retain an invalid missing part after `vehicle:repair()` while other damage is actually fixed. Settle a paid repair by measurable progress: success when the post-repair damaged count is lower, and refund only on an exception or no change. Do not duplicate the consumable because one unrecoverable custom part remains.

## B42 Wearable Containers

- A custom wearable container needs the same namespaced location in four places: `ItemBodyLocation.register(...)`, `BodyLocations.getGroup("Human"):getOrCreateLocation(...)`, script `BodyLocation`, and script `CanBeEquipped`. Registering the ID without adding it to the Human group leaves the runtime slot incomplete.
- Treat those four declarations as necessary, not sufficient. Verify the target B42 patch in SP and MP before calling the slot stable.
- On MP clients, container discovery and UI reads must not mutate capacity, reduction, name, ModData, or internal helper items. Keep instance mutation authoritative on the server and skip setter/stat/ModData synchronization when the verified value is already correct.
- Dynamic server-side container fields may persist correctly while an already-held client item instance remains stale. Send a server-authored payload keyed by the real item ID, use native item-field synchronization, and let the client apply only that explicit payload. A one-shot page-open request may repair missed state, but must not run from list population or rendering.
- Defer background item/state synchronization while a vanilla Timed Action or inventory interaction is active. Use a bounded retry interval rather than checking a deferred interaction every frame.
- B42.19 rejects `ItemContainer.setCapacity()` values above 50. Keep dynamic container capacity at 49 or below and verify the game log; wrapping the call in `pcall` does not make an over-limit assignment succeed.
- When a custom container has a unique full type, identify it by that full type instead of retaining name-based recognition and vanilla-container aliases from an unpublished prototype.

## UI Stability

- B42.19 `ISModalDialog:new(..., target, onclick, player, param1, param2)` invokes `onclick(target, button, param1, param2)`. The `player` argument is assigned to `button.player`; it is not inserted into the callback's positional arguments. When payload is `param1`, use a callback shaped like `function(target, button, payload)`. A visible dialog proves only creation, not that the callback or command ran.
- Do not trigger server refreshes from list drawing or page population.
- Avoid clearing selection without restoring by stable payload IDs such as `taskId`, `fullType`, or shop `id`.
- For actions followed by an MP state round trip, store a one-shot pending stable ID and scroll position before sending. Do not let a temporary syncing/empty list overwrite that pending selection; clear it only after the rebuilt real list restores the row.
- For long text pages such as history/info, prefer single-column wrapped text over split detail panes.
- Hide ordinary manual refresh controls in MP when automatic/key-operation sync is enough.
- Use local cached data for display when possible, then let key operations refresh from the server.

## Single-Player Visual Companions

- Put an SP-only hard return at the top of every runtime and shortcut-UI file: return when `isClient()` or `isServer()` is true. Shared number/config modules may load on both sides but must not register events.
- Prefer a render-only companion for decorative or combat-assist visuals. Keep logical world coordinates and render textures from `OnPreUIDraw`; do not create an `IsoZombie`, world item, or interactive object unless real entity behavior is an explicit requirement.
- GodSystem v1.16.49 proved that a zombie-backed shell remains visible to vanilla and third-party zombie systems despite no-teeth, useless, target, aggro, collision, and lunge suppression. It can still cause bites, panic, stress, knockdown, and corpse-state problems. Do not reuse that architecture for a harmless companion.
- For old saves, a one-time startup cleanup may remove legacy entities marked in ModData, but the active runtime must not retain the spawn endpoint.
- Validate candidate visual positions on the player's current floor, loaded squares, and non-solid geometry. Visibility may be a preference rather than a hard movement requirement: keep logical movement active off-screen, pause only body rendering while unseen, and recall only after teleport, floor change, or excessive distance.
- Throttle attack target searches; keep large-radius sight scans manual and capped. Skip guardian scans entirely while the ability is cooling down.
- Create `IsoLightSource` only when tile/radius/visibility changes and always retain the owning cell for `removeLamppost()` cleanup.
- For short screen effects, use same-version `ISCoordConversion.ToScreen()`, current zoom correction, and `renderline()` from `OnPreUIDraw`.
- For direct companion damage, call `setAttackedBy(player)` before damage and enter the B42 death path with `Kill(player)`; only correct `setZombieKills()` when the original kill path did not increment it.
- Route direct, damage-over-time, chain, and area companion damage through one ownership/death helper. Secondary damage must not recursively trigger marks, chains, blasts, or other on-hit effects.

## Lua 5.1 Limits

- Lua 5.1 main chunks are limited to 200 local variables. Large monolithic server files can hit this limit even when each helper is small. Before adding a top-level `local`, check the current file with the project's Lua 5.1 `luac -p`; place related helpers on an existing module namespace or inside command functions when the main chunk is near the limit.

## UI Prototyping

For complex GodSystem UI redesigns, prototype first in local HTML/CSS, then port the approved design to PZ Lua.

- Keep prototypes constrained to PZ-friendly primitives: fixed-size panels, simple borders, flat/tiled textures, icon images, list rows, progress bars, and button states.
- Avoid browser-only effects as core design requirements: blur filters, complex shadows, continuous animations, responsive layout tricks, CSS grid dependencies that cannot map to fixed Lua coordinates, and text scaling by viewport width.
- Use the current `GodSystem_UITheme.lua` values as the starting token source: window size, colors, spacing, row heights, action heights, detail widths, tab order, and icon paths.
- Produce a migration spec with every prototype: color table, dimensions, component states, task/shop/bank row layout, detail sections, and the exact Lua/theme functions or constants to update.
- Treat the HTML screenshot as a design target, not the implementation source of truth. Final behavior must still preserve PZ UI stability rules, selection restore, MP light sync, and localization fallback behavior.
- For external visual resources, use direct assets only when the license is explicit and redistributable. Prefer CC0/public-domain assets; for CC BY assets, add attribution in Workshop notes/readme; for unclear or mixed-license sources, use them for inspiration only and do not package them.

## Localization

- Check all localization layers used by the mod. Some mods rely on `Translate/*`; others also use Lua fallback tables.
- For B42 third-party localization patches, check whether the original mod uses JSON translations such as `Translate/EN/UI.json` or legacy text tables such as `UI_EN.txt`. If the original uses JSON, generate matching `CN/*.json` files as well as `_CN.txt` files when stability matters.
- Keep the live test mod directory synchronized with the workshop/source directory. On Windows PZ tests often load `C:\Users\Admin\Zomboid\mods\<ModId>` while the editable Workshop source may be under `C:\Users\Admin\Zomboid\Workshop\...\Contents\mods\<ModId>`.
- When a dedicated localization patch is used alongside broad translation packs, place the dedicated patch after the broad packs in active `mods.txt` so its keys win load-order conflicts.
- If a Lua fallback override is the runtime source of truth, update it with every new UI key.
- Avoid direct Chinese in Lua bridge/patch files for third-party localization. Prefer ASCII-only Lua that calls `getText("...")`, and keep Chinese text in Translate files.
- For hardcoded English context menus, patch the actual B42 `ISContextMenu:addOption`/`addOptionOnTop` methods and retry installation from menu-related events such as `OnFillWorldObjectContextMenu`; one early `OnGameStart` attempt may miss the class.
- In MP, prefer structured `{ code, args }` history/notify payloads and localize on the client. Avoid sending full localized Chinese sentences from the server.
- For GodSystem-style MP results, add new server outcomes as stable `code` plus optional `args`, then add `NotifyMP_*` or `HistoryMP_*` localization keys on the client side. Keep direct server Chinese only in legacy paths that are intentionally left as fallback.
- For GodSystem localization, treat the UTF-8 YAML text source plus generator as the source of truth when present. Add or change UI text in the YAML, rerun the generator, and commit the generated `Translate\CN`, `Translate\CH`, and Lua fallback together.
- Before finishing, check for UTF-8 replacement characters (`U+FFFD`) and accidental mojibake introduced by shell commands.
- Do not judge Chinese files by PowerShell console display. Always read/write with explicit UTF-8 APIs or `apply_patch`, and validate with a script.
- In `GodSystem_Localization_Override.lua`, prefer generated escaped UTF-8 byte strings for new Chinese fallback values when they are loaded directly by Lua; do not hand-type fallback Chinese unless there is no generator for that mod.
- For Translate files and Markdown docs, UTF-8 text is acceptable; still scan for replacement characters and common mojibake fragments after edits.

## Packaging and Backup Discipline

- Edit live test directories only when the user asks for direct testing.
- Keep stable zip backups untouched until the user says the new version is stable.
- Prefer Git commits for routine development history and add a tag only when the version's status is clear. Create or prune rolling backup ZIPs only under the user's current project rule or explicit request; never delete user-confirmed stable packages as part of cleanup.
- Treat only user-confirmed published versions as compatibility baselines. Unpublished local test versions do not require item or data migration unless the user explicitly requests it. Keep feature branches and commits local until the user confirms the live test, then decide whether to push, merge, and tag.
- When packaging, verify the zip root contains `Contents`, `workshop.txt`, `preview.png`, and any upload notes expected by the project.
- Do not repack third-party dependency mods unless license and user request explicitly allow it.

## Validation Commands

Use PowerShell-safe commands on Windows:

```powershell
rg -n "1\.16\.5|modversion=|GodSystemConfig.Version" "C:\path\to\mod"
rg -n 'send\("[A-Za-z0-9_]+"' "C:\path\to\client.lua"
rg -n 'function Commands\.[A-Za-z0-9_]+' "C:\path\to\server.lua"
```

For UTF-8 replacement checks:

```powershell
$files = Get-ChildItem -LiteralPath "C:\path\to\media\lua" -Recurse -Filter *.lua
foreach($f in $files){
  $text=[System.IO.File]::ReadAllText($f.FullName,[System.Text.Encoding]::UTF8)
  if($text.Contains([char]0xFFFD)){ Write-Output $f.FullName }
}
```

If `lua`/`luac` are unavailable, state that compile checking could not be run and report the static checks that did run.
