# PZ B42 MOD Patterns

## Reference Priority

Use this order when designing or debugging:

1. Same-version official manual, official examples, or vanilla scripts.
2. Same-version reference mods supplied by the user.
3. Other same-version community mods.
4. Different-version official docs.
5. Different-version mods or old tutorials.

Version match matters. Official source wins only when it matches or clearly applies to the target version.

## Lessons From GodSystem

- A mod can work as one SP/MP entry when client and server files are guarded correctly.
- Preserve the known-good SP path. Add MP bridge/server handlers instead of rewriting stable SP logic unless there is a clear reason.
- Keep MP data separate from SP data. Example: append `_MP` to the SP `DataKey`.
- Do not write MP server state back into the player's SP local `ModData`; update client memory for UI display only.
- Use `sendClientCommand(player, module, command, args)` first and fall back to the shorter form if needed.
- MP hello/initial state must retry until the player/network objects are ready.
- Wrap server command handlers in `pcall` and send an error/state response when a command fails.

## Inventory and Currency

- Entity currency is more robust for SP persistence than a pure Lua number, but MP operations must sync real item add/remove.
- For server item grants, add item to inventory and call `sendAddItemToContainer` when available.
- For removals, remove from the real container and call `sendRemoveItemFromContainer` when available.
- For buy flows, either charge after all grantable items are confirmed or roll back granted items if charging fails.
- For sell/recycle flows, verify that the item still exists in the player's real inventory/container before paying.
- For local UI balance, scanning the client backpack can be useful for real operations, but never do it from high-frequency UI paths such as `prerender`, top status bars, hover detail updates, or every tab switch. Use a short-lived display cache and invalidate it after buy/sell/bank/recycle/waist operations.
- In MP, prefer server state balances for display and keep real item scans for server-side transaction validation. A client display getter should not recursively scan all carried containers every frame.
- Recycle, waist, and "sell all" pages are allowed to scan real inventory, but only on page entry, explicit refresh, search/filter changes when needed, or after key inventory-changing operations. Cache grouped display results by `fullType`; transaction execution must re-read and validate real items.
- Inventory context-menu batch transactions must identify instances with `item:getID()`, not only `fullType/count`. Expand stacked selection payloads, deduplicate IDs, and resolve every ID again at execution time.
- For loot-window, floor, or vehicle selections, queue vanilla `ISInventoryTransferUtil.newInventoryTransferAction()` operations into the player inventory, then append a callback-capable queue barrier such as `ISWaitWhileGettingUp`. Do not assume the final transfer action has `setOnComplete()`; human corpses return `ISGrabCorpseItem`. Revalidate every ID after the barrier.
- Treat `ItemContainer:Remove(item)` as an attempted mutation. Before paying, verify the exact item no longer appears in the source container. On failure, restore already removed instances and any cleared primary-hand, secondary-hand, or worn state.
- Do not append an item to a transaction's `removed` ledger until exact removal has been verified. Otherwise a failed removal can be counted as payment and then duplicated again by rollback.
- For mixed bank/cash payments, retain `fromBank` and `fromCash`. Refund cash to inventory when possible; if item creation fails, credit the same value to the bank so a failed rollback never destroys currency.
- For destructive non-empty-container operations, capture a compact recursive content-instance signature when the player confirms. Recompute it immediately before settlement and cancel the whole batch if it changed.

## Item Script Compatibility

- Missing or incorrect B42 item fields can make a mod appear dependent on another framework mod.
- GodSystem's currency issue was fixed by adding `ItemType = base:normal` and a usable `WorldStaticModel`, avoiding dependency on `that DAMN Library`.
- Do not add third-party framework dependencies just because they mask a script issue. Fix the mod's own scripts first.

## B42 Item Durability Layers

- In B42.19, `Condition` / `ConditionMax` is the primary per-instance durability layer. For composite weapons, vanilla `OnBreak.HandleHandler` behavior shows this layer also represents the body or handle.
- Composite heads use a separate `HeadCondition` / `HeadConditionMax`. Check `hasHeadCondition()` before calling `getHeadCondition()`, `getHeadConditionMax()`, or `setHeadCondition()`.
- Sharpenable blades may also expose `hasSharpness()`, `getSharpness()`, and `setSharpness()`. The B42.19 admin item editor treats sharpness as a 0-to-1 value.
- `InventoryItem:setConditionMax()` is used by B42.19 vanilla code and changes one item instance, not every item of that script type.
- Do not assume a public `setHeadConditionMax()` exists. No stable B42.19 vanilla call was found during the GodSystem v1.16.47 work. Prefer increasing only primary maximum condition unless a same-version source proves a head-max API.
- If `OnBreak` has already removed a composite weapon and spawned separate parts, a repair action cannot restore the deleted original item without implementing a separate reconstruction system.
- For paid or consumable maintenance, snapshot all supported layers first. Mutate and verify, consume only after success, and roll back the snapshot if consumption fails.
- MOD compatibility should be capability-based: probe the standard methods with `pcall` and avoid module-name whitelists. Document that custom `ModData` durability systems are outside generic support.

## Multiplayer Light Sync

Use this when compatibility and low pressure matter more than anti-cheat:

- UI open: request state once.
- Key operations: send command and wait for server state/result.
- Background: sync on a low-frequency real-time interval, such as 5 minutes.
- UI tab switch: do not request state.
- Frequent events: batch them. Example: zombie kill rewards sync after 10 kills, UI open, key sync, or background sync.
- If key operation and background sync collide, process key operation first and let background sync happen later.
- Online-only timers that do not advance reliably in dedicated-server player callbacks can use a client session baseline: report only complete positive world hours, let the server own settlement, reset the baseline on `OnConnected`, `OnDisconnect`, or time rollback, and never backfill offline time.
- Key commands that spend currency or consume items need idempotency in addition to a single in-flight guard. Use a globally unique operation ID that survives reconnect and Lua module reload, and persist a bounded result cache in server `ModData` under stable player identity rather than temporary online ID. Store a normalized request fingerprint with each `processing/done/unknown` record, reject an ID reused for different payload, and convert persisted `processing` records to `unknown` after server restart. If the UI retries after timeout, reuse the previous ID only when the command and scalar payload are identical.

## B42.19 Attribute XP Purchases

- Enumerate through `Perks.getMaxIndex()` and `Perks.fromIndex()`, then resolve metadata through `PerkFactory.getPerk(perk)`. Prefer the registered object's `getParent()`, `getName()`, and `getTotalXpForLevel()` over assumptions based on enum names.
- Skip category nodes, perks without a parent, missing XP curves, and custom skill systems that do not expose the standard player XP state. The generic GodSystem path is intentionally limited to the standard ten-level curve unless a same-version API proves a different maximum.
- B42.19 vanilla `ISPlayerStatsUI` uses `player:getXp():AddXP(perk, amount, false, false, false, false)` for no-multiplier edits. Re-read XP afterward; charge and history must use the actual delta. If only part of the requested XP applied, refund the difference using the original payment-source split.
- In MP, the server re-resolves the perk and quote, mutates XP, then calls `SyncXp(player)`. If `SyncXp` fails after XP changed, do not refund the purchase: record a pending resync and retry it during the next server-authoritative hello/reconnect path.

## B42.19 Vehicle Repair

- Vanilla `ISVehicleMechanics` sends the server `vehicle/repair` command, and `VehicleCommands` resolves the vehicle before calling `vehicle:repair()`. Use `getVehicleById()` on the server for MOD requests and validate item ownership, distance, floor, and vehicle state first.
- The vanilla command is admin/cheat oriented. A paid repair consumable should keep its own server-authoritative business checks and call `vehicle:repair()` only after those checks; never trust a client-side repair result.
- Treat `vehicle:repair()` as `BaseVehicle` compatibility. Do not promise support for MOD vehicles that replace the standard part or repair system.

## Sandbox Defaults

- Generate `media/sandbox-options.txt` from the same metadata that drives an admin settings panel when the option sets must stay identical.
- Sandbox values are initialization defaults unless the product explicitly defines them as live authority. Import only when the persistent settings field is `nil`; do not treat an existing empty table as a new world.
- Keep structured item overrides out of scalar sandbox options. Preserve them in the existing admin storage and synchronization path.
- Generate CN/CH sandbox localization from the same UTF-8 source and test that admin keys, sandbox keys, and translation keys form matching sets.

Recommended trust split:

- Trust client: kill count deltas, move distance, survive time, non-item task progress.
- Verify server-side: buy affordability, item grants, item removals, recycle items, item-turn-in tasks, waist/container inventory.

## Tasks

- On accept, store baselines from the side that will later compute progress. If client computes kill/move progress, send client baselines at accept time.
- On claim, include `clientProgress` for non-item tasks.
- For item tasks, ignore client progress for final validation and count/remove real server-side items.
- For timeouts in client-first MP, client tracks time and sends `clientExpired=true`; server applies failure and penalty.

## UI and Selection

- Page population functions should be pure display work. Avoid server requests inside drawing/populate functions except an initial "state missing" bootstrap.
- UI drawing and resize paths must not call recursive inventory scans, price table rebuilds, or server syncs. If a player carries thousands of stack items, these paths run on the main thread and can make clicks, page switches, and unrelated actions feel delayed.
- Capture selection before list rebuild and restore by stable IDs.
- Do not assume `ISScrollingListBox:clear()` resets scroll state in B42. When reusing list boxes across pages, also reset `setYScroll(0)`, `setScrollHeight(0)`, `smoothScrollTargetY`, and `smoothScrollY`; otherwise rows can exist and remain selectable while rendering outside the visible area.
- When changing a reused `ISScrollingListBox` width or height, also update its child `vscroll` geometry. B42 initializes `vscroll.x = parent.width - 16` and `vscroll.height = parent.height` once, and `setWidth/setHeight` on the parent does not reattach the scrollbar. `ISScrollingListBox:prerender()` uses `self.vscroll.x + 3` as the stencil width when the scrollbar is visible, so stale scrollbar geometry can make long lists render black/empty while short filtered lists still display. For heavily reused custom UI list boxes, install a local safe `prerender` wrapper that resyncs scrollbar geometry immediately before and after vanilla `ISScrollingListBox.prerender()`, and apply it to every list instance, not only the page where the bug was first seen.
- For custom `ISScrollingListBox` row rendering, store display text in the row payload as a fallback such as `displayText`; do not rely only on the wrapper's `item.text`.
- Keep task open/active columns distinct; do not reset the selected column during every redraw.
- Long history/info pages should use wrapped single-column list rows, not a detail pane that can be hidden/cleared during relayout.
- When resizing UI, recompute stable dimensions and constrain minimum sizes.
- For small state-driven windows such as shortcut bars, do not rely on one-time `createChildren()` button creation. Use a low-frequency action/state signature refresh, such as every 5 real seconds while open, and rebuild controls only when the signature changes. The refresh path must stay local and lightweight: no server sync, no price-table rebuild, and no recursive inventory scan.

## Localization and Mojibake

- Lua source can contain valid UTF-8 while PowerShell displays mojibake. Distinguish display problems from file corruption.
- Use .NET UTF-8 reads to check for replacement characters.
- Avoid writing Chinese text through fragile shell quoting. Prefer `apply_patch` or escaped strings.
- MP history/notify should be structured codes and args; the client localizes with `HistoryMP_*` or `NotifyMP_*`.
- For GodSystem-style commands, prefer a helper such as `finishCode(player, ok, code, args, payload)` so new MP results carry stable codes instead of server-side Chinese sentences.
- When a generated localization source exists, update the UTF-8 YAML source first, then regenerate CN/CH Translate files and the ASCII-only Lua fallback. Do not hand-edit only one layer.
- B42.19 vanilla translations use JSON files such as `ItemName.json` and `Tooltip.json`. When a mod still carries legacy `Items_CN.txt`, generate both formats from one source for new item names/tooltips instead of assuming a `Tooltip_*` key inside the item-name table will load.
- Do not automatically delete old mojibake history from player saves unless the user asks.
- Windows PowerShell 5.1 parses UTF-8 `.ps1` files without a BOM as the active ANSI code page. Do not put Chinese source literals in these test scripts; use ASCII keys/patterns and validate Chinese files through explicit UTF-8 APIs or Python. The target UTF-8 file may be correct even when a script literal becomes mojibake during parsing.

## Packaging Notes

- Workshop upload directory should usually be the folder containing `workshop.txt`, `preview.png`, and `Contents`.
- Stable backups are user-confirmed artifacts. Do not overwrite them after code edits until the user has tested and explicitly asks.
- Keep reference mods outside the packaged mod unless licensing and the user's request explicitly allow bundling.

## B42.19 SP Render-Only Companion Pattern

- Runtime isolation: client-runtime files still load in multiplayer environments unless guarded. Return immediately when `isClient()` or `isServer()` is true, and conditionally require the runtime only from the SP UI path. Do not add protocol/server handlers for an SP-only feature.
- Pure visual rule: use logical coordinates plus `OnPreUIDraw` textures for a harmless companion. A zombie-backed shell remains an `IsoZombie` to vanilla and third-party systems and cannot reliably suppress bites, panic, stress, knockdown, or corpse behavior.
- Migration: old marked shells may be removed once on startup. After migration, the companion runtime must not call `addZombiesInOutfit()`, rebuild `ItemVisual`, or expose appearance/shape-switch endpoints.
- Position safety: choose same-floor, visible, non-solid target squares. Smooth toward low-frequency orbit targets and recall after floor changes, teleport, vehicle transitions, or excessive distance.
- Light lifecycle: `IsoLightSource.new(x,y,z,r,g,b,radius)` plus `cell:addLamppost(light)` works in B42.19 references. Recreate only after tile/radius changes and remove with the same cell's `removeLamppost(light)` on hide, vehicle entry, death, world exit, or rebuild.
- Rendering: do not infer Kahlua-callable overloads from Java signatures or commented vanilla Lua. In B42.19, GodSystem successfully loaded a `Texture` but `SpriteRenderer.render(Texture,Double...)` still raised `No implementation found`. For compact visual companions and effects, use the already verified `mask_white.png + renderline()` path from `OnPreUIDraw`; only use `render()` after a live same-version call has been proven.
- Direct kills: set the attacker, subtract health, and call `zombie:Kill(player)` when lethal so original death events run. Read the player's kill count before the hit and only use `setZombieKills(old+1)` as a fallback when `Kill(player)` did not increment it.
- Damage layering: send direct hits, damage-over-time, chains, and area splash through one kill-ownership helper. Pass an explicit flag that suppresses all on-hit effects for secondary damage, so chain and blast targets cannot recurse into additional chains, blasts, marks, or status refreshes.
- Performance: throttle no-target attack searches, skip guardian scanning during cooldown, detect the guardian threshold in a fixed 7x7 area with early exit, and gather/cap sight targets only on manual activation.
- Random APIs: do not assume standard Lua `math.random()` exists in the B42.19 Kahlua runtime. Use the same-version vanilla APIs `ZombRandFloat(min,max)` for float ranges and `ZombRand(min,max)` for integer ranges, and add a static regression check for new runtime random helpers.

## Useful Static Checks

- Version consistency in config, root `mod.info`, versioned `mod.info`, `workshop.txt`, and upload notes.
- Client send commands have matching `Commands.*` server handlers.
- No stale duplicate mod IDs such as draft MP entries.
- No `U+FFFD` replacement characters in Lua files.
- No accidental state refresh calls on UI tab switches when using light sync.
- Lua 5.1 `luac -p` on every packaged Lua file. Large entry chunks fail once the main function exceeds 200 locals; avoid adding more top-level locals and group helpers under the existing module table instead.
