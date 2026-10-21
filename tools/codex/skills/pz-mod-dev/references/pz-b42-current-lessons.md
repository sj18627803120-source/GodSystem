# B42.21 Recent Engineering Lessons

Use these when changing carry, initialization, accounting, online clocks, simulation or charts. They are code/native-isolation lessons from GodSystem 3.21.5–3.23, not universal compatibility promises. Resolve the current source/acceptance through handoff00. User acceptance on 2026-10-21 covers the current3.23 build as reported, not every unreported multiplayer case.

## Carry authority and character lifecycle

- In OnInitGlobalModData a real player may not exist. Do not call getModData on nil or manufacture a persisted zero level; wait for character creation. Existing account level, including zero, outranks character migration markers.
- Do not infer a trusted base from arbitrary externally overwritten carry fields. Current GodSystem controls only upgraded characters, retaining native strength/body-state calculations and legal native traits. Never change zero-level characters as a side effect of a failed first purchase.
- Native Java float0.9 reads back as0.8999999761581421. Normalize at the native boundary before equality checks to avoid endless corrections.
- Locate methods through the actual instance metatable/inheritance chain; an exposed class table may not own its instance methods. Wrappers need internal bypass and exception-safe reset; restore only an entry still owned by this module. Cached native setters can bypass Lua wrappers, so no absolute-priority claim.
- A client must not continuously restore an old final carry cache over legitimate damage/body-state packets. Distinguish authority business revision, session identity and independent monotonic push sequence; same-revision heartbeats are valid.
- Stable carry checks read fields only. Keep account lookup, inventory scans and full state projection out of the100ms worker. Interface failure, external interference and valid zero final capacity are different states.

## Exact money and persistent recovery

- Target Kahlua can disagree with Lua5.1 for large-number modulo because its quotient narrows internally. Do not use extreme `a % d` or `% 2` as proof of safe money arithmetic. Use bounded quotient/remainder arithmetic, validate every intermediate, and run Python big-integer oracles in both VMs.
- Retried successful transactions must not re-charge, re-issue assets or re-submit activity. Bounded receipt eviction needs a durable high-water sequence when old operations must remain unreplayable.
- An old bank-balance snapshot is not authority for a restart refund: unrelated deposits may have happened. Persist mutation evidence and isolate only the uncertain subsystem when outcome cannot be proven.
- Exclude private receipts/stock holdings from both ordinary state payloads and their revision signatures; omitting only the payload can still deep-copy private tables on each normal sync.

## Online simulation and bounded subscriptions

- Persist logical elapsed game time; keep wall/world-clock anchors session-local. Restart, offline time, disabled periods and worlds moving backward cannot silently add elapsed time.
- Stage each hour's inputs, RNG and computed output before one commit. Cancellation must discard all staged state together. Late inputs go to an unsealed period.
- Separate RNG streams for prices, events, publication scheduling and text. UI reads, news status and news disable must not perturb prices.
- Publish only bounded public views to open subscribers. Same price revision may still have a newer balance/position: use monotonic message ordering. Stable closed windows must not request or receive full histories.
- Show the market's logical hour and next publication time. Lack of an error stack does not prove a news timer progressed; expose paused/disabled/awaiting-schedule states without leaking hidden events or rumor truth.

## ISUI and honest charts

- Draw candle wicks and narrow bodies; filling the bounding rectangle between adjacent prices produces an opaque block. Axis values, period labels, up/down colors and an empty-history state make the result interpretable.
- Hourly price samples can produce sampled OHLC bars, not tick-level intrahour extremes. State the source and candle period. Keep aggregation/geometry cached and out of prerender; hidden news pages should not calculate quotes or charts.
- Size a two-line fee area from two caption font heights, not one body row. Verify the real controller's drawing coordinates at all supported terminal fonts, including nonzero scrolling and screen clamping.
- An offline drawing export approximates game fonts; call it an offline preview, never an in-game screenshot or proof of multiplayer behavior.
- A row's viewport position is y+getYScroll(); clipped background coordinates must compensate for scroll. Text must fit vertically as well as horizontally.

## Evidence and maintenance routing

- Carry details/probes: handoffs131/133; fixed-head-position guard and independent recycle menu display:132; stock model/ledger/UI:135. Resolve the latest acceptance/archive through handoff00 instead of updating this skill's baseline every release.
- Source skill lives in tools/codex/skills/pz-mod-dev. When asked to update it, validate then synchronize installed skill and docs/开发技术支援/skill-backup/pz-mod-dev by exact relative-file hashes. Preserve interface policy unless the user changes it.
- Keep native probes and external compilers in developer-only paths. Inspecting a Java API does not make it a player runtime dependency. A deferred AI bootstrap experiment is not authorization to install or auto-launch components.
