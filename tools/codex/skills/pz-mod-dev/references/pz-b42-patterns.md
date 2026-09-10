# Project Zomboid B42 Engineering Patterns

These rules consolidate GodSystem development through the user-tested `42.20_3.5` baseline. Unless a bullet explicitly says B42.20.4 live-tested or code-confirmed, revalidate it on the target patch.

## Evidence and Diagnosis

1. Same-patch vanilla/official source and live reproduction.
2. Same-patch reference mods supplied by the user.
3. Other same-patch community implementations.
4. Different-patch official material.
5. Older mods/tutorials as architecture hints only.

- Keep `代码确认`, `实机验证`, `合理推断`, and `待实机验证` separate in reports.
- The official 42.13 migration guide is useful architectural evidence for registries and multiplayer inventory items, but it is not proof of 42.20.4 signatures.
- Java bytecode proves a method exists; a same-patch vanilla Lua call or minimal live test is still required to prove its Kahlua overload.
- Compare log timestamps, deployed-file hashes, and the exact stack before attributing errors. Errors from map translation, animation, or model mods that occur before GodSystem code are not GodSystem conflicts without a matching call path.
- B42.20.4 Kahlua can log an `error()` even when an outer `pcall` catches it. Use structured returns for ordinary refusal paths and reserve exceptions for unexpected failures.
- The standard Lua 5.1 global environment is not identical to PZ Kahlua. GodSystem startup failed because `next()` was unavailable even though desktop Lua tests passed. Test harnesses should disable or shim only APIs proven available in game.

## Registries, Items, and Persistence

- `media/registries.lua` must use that exact name/path and loads before scripts and normal Lua. Register custom item types, tags, body locations, traits, and professions before script use.
- B42 item scripts use `ItemType`, not old `Type`. Missing native fields can look like a dependency on another framework. Fix the item's script before adding a dependency.
- Never mutate shared `ScriptItem` prototypes for player-specific state. Store instance state on the real item and synchronize it through the correct authority path.
- A custom wearable slot needs the same namespaced location in `ItemBodyLocation.register`, the Human `BodyLocations` group, script `BodyLocation`, and script `CanBeEquipped`.
- MP clients should not mutate discovered container capacity, reduction, name, or ModData. The server changes the real instance and sends a payload keyed by exact item ID; defer client application during wear/transfer actions.
- Historical B42.19 evidence showed `ItemContainer:setCapacity()` rejecting values above 50. Treat 49 as the old verified safe cap, not a timeless B42 rule; recheck any newer target patch.
- A native item ID may persist across saves, but it is not sufficient as a long-lived asset identity. For bound equipment use world ID + equipment UUID + generation + native item ID, with a world-authoritative record and item ModData only as a locator/snapshot.
- Never recover a high-value record merely because a same-type item exists. Missing identity becomes a lost/unavailable state; recovery creates a new generation and invalidates the old generation.

## Equipment Findings from B42.20.4

- The checked save path did not persist an arbitrary expanded `ConditionMax`, while damaged `Condition` used a one-byte representation. Do not build unlimited durability-cap growth around per-instance `ConditionMax`.
- Composite weapons may have body condition, head condition, and sharpness. Capability-check each layer. Natural wear paths use the wear/chance parameters, so improve resistance rather than inventing an unbounded condition maximum.
- Once vanilla break logic removes a composite weapon and produces parts, normal repair cannot resurrect that entity; recovery must be a separate reconstruction/generation operation.
- `HandWeapon` actual weight is derived from type base weight and attachment weight in the checked path; an ordinary instance weight setter is not a reliable equipment weight upgrade.
- Reload action duration is driven by animation variables, skills, and panic in the checked vanilla actions. A single `ReloadTime` mutation is not a reliable reload-speed feature.
- Keep permanent base values separate from attachment/sharpness-derived values. Reapply enhancement from the stored base on every handoff or config change; never multiply the already-enhanced current value.
- Apply equipment effects only for the verified owner/current generation. Restore base values when unequipped, used by another account, identity-invalid, or awaiting authoritative config.
- Server item messages should include the scalar growth configuration needed to apply the item. A stale client sandbox value or old page snapshot must not choose equipment multipliers.
- Stop paid upgrades when the underlying native parameter is already at its effective bound. Show expected parameters separately from final combat outcomes; skill, fatigue, panic, sharpness, and vanilla clamps still affect play.
- Validate a newly constructed equipment record before writing its item marker, slot, receipt, or world record. A target weapon with unsupported durability or attribute shapes must fail only that bind attempt and leave the player free to choose another weapon.
- Separate root-store corruption from one-record corruption. Invalid world/account shells, receipts, or uncertain transactions may fail closed; a malformed slot record should become an isolated row state so other slots remain usable. Releasing an invalid slot must preserve the raw record for diagnosis and remove its active slot relationship without deleting any physical weapon.
- A marked record is active only while the owning account has a valid slot reference to that equipment UUID. Tooltip projection, attribute application, freeze, rename, repair, and recovery must share this rule so an orphaned marker cannot retain benefits.

## Equipment Tooltip, Rename, and Freeze Findings

- Inventory tooltips have no dedicated extension event in the checked B42.20.4 path. Chain the currently installed `ISToolTipInv.render`, call it exactly once, append only after a validated projection, restore any temporary instance methods/layout state, and protect the add-on path so a failure cannot suppress the vanilla tooltip or flood the render log.
- Tooltip rows must be generated from the shared attribute registry and projection level map rather than hard-coding damage/freeze. New attributes then extend capability checks, projection, formatting metadata, translations, and tests in one explicit path.
- `ISTextEntryBox:getText()` may arrive as `java.lang.String` userdata. Normalize that specific text boundary safely before the shared UTF-8 validator; do not broaden authority requests to accept arbitrary tables or numeric payloads. Client and authority must run the same trim, code-point, control-character, BMP, and length rules.
- Multiplayer tooltip inspection is read-only and keyed by the complete world/equipment/generation/item/fullType/revision identity. Cache and deduplicate in-flight requests; never scan inventory or trust item ModData as authorization.
- A real melee swing should produce at most one freeze trigger even when it hits multiple zombies. Keep feature/weapon checks constant-time, let the authority select loaded nearby same-floor targets, merge one strongest timed effect per zombie, batch changes, and unregister temporary workers when inactive.
- A Java method existing does not prove a render overload is callable. In B42.20.4, the tested `SpriteRenderer.render(Texture, x, y, w, h, r, g, b, a)` Lua call had no matching exposed implementation. Use a same-patch proven drawing path such as the existing line renderer/UI primitive and keep visual state separate from gameplay authority.
- Freeze visuals and movement are separate acceptance paths. A working slowdown does not prove a marker is rendered; SP effect creation must initialize visual flags/frame lifetime, and render callbacks must tolerate an uninitialized configuration cache without indexing a function or nil value.

## Multiplayer Authority and Paid Operations

- The server resolves listings, price, stock, balance, item ownership, feature status, configuration, and final mutation. A server handler that trusts client price or a client item table is not authoritative.
- Network Timed Actions keep visuals in client `perform()` and authority mutations in server/SP `complete()`. Non-timed commands use stable scalar IDs and re-resolve real objects in `OnClientCommand`.
- Use one business service for SP and MP with different authority adapters. Do not maintain divergent pricing, validation, or rollback implementations.
- Transaction order: validate → intent/snapshot → reserve/charge → mutate → verify → commit → sync. For recovery, verify the generated real item before changing the active generation.
- Preserve `fromBank` and `fromCash`. Refund original sources; if physical coin restoration fails, preserve value in the documented bank fallback.
- Operation IDs must survive reconnect/module reload, bind to a normalized request fingerprint, and have bounded persistent `processing/done/unknown` results. On restart, unresolved `processing` becomes `unknown`, not an automatic replay.
- If mutation committed but sync failed, retry sync rather than refunding and leaving the player with both value and benefit.
- Keep client/server feature gates. Hiding a button is presentation, not authorization.

## Inventory and Context-Menu Performance

- Gate by the clicked object first. A world right-click should determine whether a vehicle exists before searching for a repair module. Inventory actions should first classify the selected items, then search only the data required by relevant actions.
- Share one immutable selection snapshot among menu builders. Expand stack selections, deduplicate exact `item:getID()` values, and do not let a later selection change alter the pending request.
- Menu construction must not recursively scan unrelated inventory, count cash, rebuild full prices, load/sort files, or request server refreshes.
- Range allow/deny lists should be normalized into membership sets when loaded, edited, imported, or synchronized. Cache by player/session/version and expose a read-only prepared-state query to the menu.
- For large selection analysis, defer expensive count/category/price/container checks until click. GodSystem uses more than 200 items as the deferred boundary, processes at most 64 entries per frame with an approximately 2 ms budget, and allows only one preparation job per player. These numbers are project defaults, not engine constants.
- Cancel preparation when selection identity, item location/content signature, configuration, player, or connection changes. Move/delete nothing until the completed analysis is confirmed.
- Build one exact item-ID index per validation/execution phase, then reuse it inside that phase. Do not cache a full inventory index across operations and never trust a client-built index.
- `ItemContainer:Remove(item)` is only an attempted mutation. Verify the exact item is absent before paying; record it in the removed ledger only after verification. Restore equipment/worn state on rollback.
- Non-empty containers need a compact recursive content-instance signature at confirmation and immediate revalidation before settlement.
- Loot/floor/vehicle selections should use vanilla transfer actions followed by a callback-capable queue barrier; do not assume the final transfer action supports `setOnComplete()`.

## UI Layers, Lists, and Theme Safety

- Main mod window: normal layer. Owned secondary pages: above main. Their confirmation dialogs: above the secondary page. Reassert this on reuse/focus, not every frame.
- Close or detach owned dialogs when the parent closes. Prevent duplicate confirmations and do not globally override vanilla UI classes.
- B42.20.4 `ISButton:setEnable(false)` mutates the assigned border/background color objects. Passing shared theme tables lets one disabled button turn unrelated panels red. Clone color tables per control/window.
- Read the target-patch modal constructor/callback. Historical B42 behavior stores `player` on `button.player` and passes `param1/param2` positionally; a visible modal does not prove its callback ran.
- Page population and row drawing must be presentation-only. No inventory scans, price rebuilds, server requests, or filesystem work.
- Preserve selection through rebuilds using stable IDs. Keep a one-shot pending ID and scroll position across MP placeholder/empty states; clear it only after the real row is restored.
- Reusing/resizing `ISScrollingListBox` requires resetting y-scroll, scroll height, smooth-scroll fields, and resynchronizing `vscroll.x/height`. Stale scrollbar geometry can corrupt stencil width.
- Do not rely solely on stencil clipping for custom rows. Submit row backgrounds and text only when their coordinates intersect the visible viewport; use UTF-8-safe cached ellipsis for long names.
- Hide disabled feature tabs, task trackers, shortcut actions, loans/investments blocks, and feature-specific shop entries. If the active page becomes hidden, select the first visible page.

## Localization and Encoding

- In GodSystem, the UTF-8 YAML plus generator is the source of truth. Generate CN/CH `IG_UI.json`, legacy `IG_UI_*.txt`, `ItemName.json`, `Tooltip.json`, sandbox JSON, legacy item text, and the ASCII-safe Lua fallback together.
- Parse item scripts during generation and fail if any scripted item name or tooltip key is missing. SystemCoin and LotteryTicket IDs appearing in English can simply mean this mod omitted `ItemName` entries and another translator masked the omission on the developer's machine.
- PZ uses CN and CH as separate language codes. GodSystem intentionally mirrors simplified Chinese into both for compatibility; other projects may provide distinct translations.
- When the active language is CN/CH, a native English fallback should not prevent the mod's own Chinese fallback. For other languages, preserve the normal translator priority.
- Literal percent signs in formatted PZ translation strings may require escaping as `%%`; otherwise sandbox text can throw `UnknownFormatConversionException` at load time.
- Keep server results as stable `{code,args}` and localize on the client. Avoid server-authored Chinese sentences in new protocol paths.
- PowerShell console mojibake is not file corruption. Use `apply_patch`/explicit UTF-8 reads, reject U+FFFD and known mojibake fragments, and avoid Chinese literals in Windows PowerShell 5.1 test scripts without a safe encoding strategy.

## Sandbox Configuration and Tasks

- Generate sandbox options and their CN/CH labels/tooltips from the same metadata as runtime/admin configuration when they must stay aligned.
- Distinguish a sandbox base from purchased progression. A persisted absolute task limit can shadow later lower sandbox values. Prefer `effective = clamp(sandbox base + purchased bonus)` with a schema that states what is stored.
- If the product explicitly rejects old-save protection for an unpublished schema, reset obsolete absolute fields rather than guessing which portion was purchased.
- Explain each option's units and edge cases. Examples: daily task count 0 creates none; active limit 0 permits none; a 24-hour baseline shifts new template durations; reward/penalty multipliers apply when the task is created or settled as documented.
- Configuration changes that affect generated tasks need a generation token/version. Preserve accepted tasks and regenerate only unaccepted tasks when the token changes, even on the same in-game day.
- Server-authored runtime configuration is authoritative in MP. UI opening/local data hydration must not overwrite it with the client's local sandbox file.
- Disabling tasks must stop generation, auto-claim, and progress/timeout work as designed, while the server still rejects stale direct task commands.

## Event and Performance Discipline

- Prefer load/connect/create-player, hand changes, explicit page open, transaction completion, save/death/disconnect, and low-frequency real-time validation.
- On weapon attacks, inspect only the known current weapon and mark a deferred durability snapshot dirty. Do not send a full equipment state on every hit.
- Inventory/container events should mark dirty state, not immediately recurse through all carried containers.
- UI open or an explicit operation may build one temporary inventory index. Drawing never does.
- Temporary frame workers must have an item budget, time budget, cancellation conditions, and guaranteed event unregistration.
- Measure menu cost, traversal count, indexing, application, transaction, and message size. Validate realistic 1/200/201/1,000/10,000 item cases where relevant.

## Validation and Backup Checklist

- Run focused behavior suites, full regressions, generated localization checks, sandbox key-set checks, protocol parity, UTF-8 scans, and Lua 5.1 compilation for every packaged Lua file.
- Lua 5.1 main chunks allow at most 200 locals. Prefer modules/namespaces before an entry file reaches the limit.
- Mock tests cannot validate Java overloads, stencil behavior, final weapon performance, save persistence, or MP synchronization. Record target-patch SP, hosted MP, and dedicated-server coverage separately.
- A user-confirmed stable build may replace the project's one rolling ZIP when requested. Create a temporary archive, exclude `.git`/test caches, verify `Contents`, `workshop.txt`, `preview.png`, embedded version, and entry count, then replace only the exact intended ZIP and record SHA-256.
- Never package reference mods or third-party assets without explicit permission and redistributable licensing.

## Repository References

- `docs/reference-mod-research/README.md`
- `docs/reference-mod-research/catalog.md`
- `docs/PZ_B42_OFFICIAL_DEVELOPMENT_CN.md`
- `docs/PZ_B42_游戏本体API技术参考.md`
- `docs/GodSystem_DevHandoff_CN/03_开发经验与踩坑.md`
- Latest numbered GodSystem handoff files
