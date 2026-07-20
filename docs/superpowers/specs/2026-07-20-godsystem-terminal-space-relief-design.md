# GodSystem v1.16.63 Space Relief Design

## Goal

Replace the ineffective post-Lv.8 terminal-capacity override with a native-weight-based "空间减载" upgrade. The player sees a normal paid upgrade; internally, one hidden protected `Food` instance contributes negative weight inside the system terminal so vanilla Java capacity checks remain authoritative.

## Confirmed Rules

- Keep terminal capacity Lv.1-8 at `10/15/20/25/30/35/42/49`.
- Keep the existing independent weight-reduction line at Lv.1-8.
- Add "空间减载" as a third upgrade button and status row.
- Defaults: `2000` coins per purchase, `5` relief per level, maximum relief `2000`.
- Default maximum is 400 purchases and an effective positive-item allowance of about `49 + 2000 = 2049`.
- Sandbox/admin settings expose price, relief per level, and maximum relief. Sandbox values initialize new worlds only; the existing admin settings store remains runtime authority.
- Existing unpublished v1.16.62 capacity levels above 8 are clamped to 8. They are not converted or refunded.

## Native Mechanism

B42.19 `ItemContainer.getContentsWeight()` sums every contained item's `getUnequippedWeight()` without clamping negative totals. A `Food` item with script `HungerChange = -1` and a positive instance `hungChange` produces a negative `Food.getActualWeight()` through vanilla's remaining-food weight formula.

GodSystem will define `GodSystem.SystemTerminalRelief` as a hidden, non-edible food item with script weight 1. For an offset `R`, the authoritative side writes `hungChange = R / 100`, then verifies that `getActualWeight()` is approximately `-R`. The script definition is never modified at runtime.

## Protection

- `Hidden = true` keeps the internal item out of the vanilla inventory list while retaining its weight contribution.
- The instance is marked favorite and unwanted so vanilla transfer-all and loot-all paths skip it.
- Its full type is excluded from shop listing, recycle, automatic terminal recycle, lottery, task item generation, and player-facing counts.
- Terminal creation, claim/recovery, page open, upgrade, auto-recycle command, SP game start, and MP hello audit the terminal.
- An audit keeps exactly one internal item, repairs its owner/version/value, removes duplicates, and recreates a missing item.
- Player/world audits neutralize or remove escaped relief items. No new `OnTick`, per-frame inventory scan, minute timer, or periodic terminal scan is added.
- MP mutations are server-authoritative. Clients only display synchronized level/status.

## Data And UI

- Player field: `autoRecyclerReliefLevel`, normalized from 0 to the runtime maximum.
- Terminal marker fields record relief level and audit version.
- Internal-item ModData records marker, terminal ID, relief level, offset, and version.
- The terminal page uses the currently unused fifth action button for `升级减载`.
- Status shows level, current relief, next relief, price, native capacity, and effective allowance.
- Raw terminal contents weight may include the hidden negative item; player-facing item counts and recycle groups exclude it.

## Failure And Rollback

- Upgrade first snapshots the old level and internal item state.
- Apply and verify the new negative weight before charging.
- If creation, mutation, verification, or synchronization fails, restore the previous level/item state and do not charge.
- If payment fails after apply, restore the previous state.
- Settings changes clamp the saved level to the new maximum and reapply the corresponding offset on the next explicit audit.

## Performance

The feature has no continuous checks. Audits scan only the top-level contents of the single known terminal during explicit lifecycle and transaction boundaries. Removing the v1.16.62 capacity wrapper also removes the need for periodic capacity re-registration.

## Attribution Boundary

The design uses behavior verified in B42.19 bytecode and independently implements the general negative-food-weight concept. It does not copy the reference Mod's code, names, assets, recipes, or balance values.
