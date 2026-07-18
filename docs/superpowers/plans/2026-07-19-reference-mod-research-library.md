# Reference MOD Research Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained GitHub research library for all 11 local Project Zomboid reference MOD sources and distill verified reusable rules into the repository's portable `pz-mod-dev` skill.

**Architecture:** Keep source-specific evidence in one report per reference MOD, link all reports through a catalog and topic index, and promote only cross-project conclusions with explicit code evidence into `pz-b42-patterns.md`. A PowerShell integrity test enforces report coverage, evidence labels, portable paths, and the absence of copied third-party runtime assets.

**Tech Stack:** Markdown, PowerShell 5.1, Git, `rg`, Project Zomboid Lua/script static analysis.

## Global Constraints

- Cover exactly these 11 latest local sources: `1299328280`, `CAExtendedCategories`, `CaiGou's Shop`, `CultivationStorageArtifacts`, `damnlib`, `DebugMenu`, `PsionicAwakeningB41`, `RuinBazaar`, `Server Shop`, `TraitsPurchaseSystem`, and `YeseMarket`.
- Use the latest local version as primary evidence; mention older versions only when they change B42.19 applicability.
- Mark material claims as `代码确认`, `作者声明`, `合理推断`, or `待实机验证`.
- Mark version confidence as `B42.19 同版本证据`, `旧 B42 参考`, or `B41 弱参考`.
- Do not upload third-party source code, textures, audio, models, or full configuration files.
- New research reports must not depend on `C:\Users\Admin` or any other machine-specific absolute path.
- Do not modify GodSystem runtime files, Workshop files, or version numbers.
- Do not merge `main`; push only `feature/v1.16.57-carry-recycle` after verification.

---

### Task 1: Research Library Contract And Integrity Test

**Files:**
- Create: `tools/tests/Test-ReferenceModResearch.ps1`
- Create: `docs/reference-mod-research/README.md`
- Create: `docs/reference-mod-research/catalog.md`
- Modify: `tools/Test-GodSystem.ps1`

**Interfaces:**
- Consumes: the 11 source slugs declared in this plan.
- Produces: a stable report path list under `docs/reference-mod-research/mods/` and a test entry callable from `tools/Test-GodSystem.ps1`.

- [ ] **Step 1: Write the failing integrity test**

Create a PowerShell 5.1 test that defines the exact 11 report filenames, verifies that each exists and is linked by both `README.md` and `catalog.md`, requires the headings `身份与版本`, `关键证据`, `可采用机制`, `风险与限制`, and `待验证内容`, and scans all research Markdown for `U+FFFD`, common mojibake fragments, and `C:\Users\Admin`.

Use this report contract in the test:

```powershell
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
$ErrorActionPreference = 'Stop'
$researchRoot = Join-Path $Root 'docs\reference-mod-research'
$reports = @(
    'MoreTraits.md',
    'CAExtendedCategories.md',
    'CaiGou-Shop.md',
    'CultivationStorageArtifacts.md',
    'damnlib.md',
    'DebugMenu.md',
    'PsionicAwakening.md',
    'RuinBazaar.md',
    'Server-Shop.md',
    'TraitsPurchaseSystem.md',
    'YeseMarket.md'
)
$requiredHeadings = @('## 身份与版本', '## 关键证据', '## 可采用机制', '## 风险与限制', '## 待验证内容')
$indexFiles = @('README.md', 'catalog.md')
$failures = [System.Collections.Generic.List[string]]::new()

foreach ($report in $reports) {
    $path = Join-Path $researchRoot ('mods\' + $report)
    if (-not (Test-Path -LiteralPath $path)) {
        $failures.Add('Missing report: ' + $report)
        continue
    }
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    foreach ($heading in $requiredHeadings) {
        if (-not $text.Contains($heading)) { $failures.Add("$report missing heading: $heading") }
    }
    if ($text -notmatch '`代码确认`|`作者声明`|`合理推断`|`待实机验证`') {
        $failures.Add("$report has no evidence label")
    }
}

foreach ($index in $indexFiles) {
    $path = Join-Path $researchRoot $index
    if (-not (Test-Path -LiteralPath $path)) {
        $failures.Add('Missing index: ' + $index)
        continue
    }
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    foreach ($report in $reports) {
        if (-not $text.Contains('mods/' + $report)) { $failures.Add("$index missing link: $report") }
    }
}

if (Test-Path -LiteralPath $researchRoot) {
    foreach ($file in Get-ChildItem -LiteralPath $researchRoot -Recurse -File -Filter '*.md') {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        if ($text.Contains([char]0xFFFD)) { $failures.Add("Replacement character: $($file.Name)") }
        if ($text -match 'C:\\Users\\Admin') { $failures.Add("Machine path: $($file.Name)") }
        $mojibakeChars = @([char]0x951B, [char]0x9286, [char]0x9225, [char]0x7F01, [char]0x7EEF)
        if ($mojibakeChars | Where-Object { $text.Contains($_) }) {
            $failures.Add("Possible mojibake: $($file.Name)")
        }
    }
}

if ($failures.Count -gt 0) { throw ($failures -join [Environment]::NewLine) }
Write-Output ('ReferenceModResearchOK={0}' -f $reports.Count)
```

- [ ] **Step 2: Run the test and verify failure**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\tests\Test-ReferenceModResearch.ps1
```

Expected: failure listing the missing report files.

- [ ] **Step 3: Create the index and catalog skeleton**

Create a README explaining evidence labels, version-confidence labels, topic navigation, copyright boundaries, and how another Codex should use the reports. Create a catalog row for each source with report link, selected version, target PZ version, primary topics, and internet search terms. Do not add conclusions not yet established by source reports.

Every source report must follow this exact top-level structure:

```markdown
# <MOD name> 研究报告

## 身份与版本
## 功能地图
## 关键证据
## 单人与多人数据流
## 可采用机制
## 风险与限制
## 对 GodSystem 的应用
## 待验证内容
## 联网检索信息
```

- [ ] **Step 4: Register the test in the aggregate runner**

Add the test to `tools/Test-GodSystem.ps1` using the runner's existing invocation pattern. The research test must remain independent of the game installation and Lua runtime.

Insert this line immediately before `Test-GodSystemEncoding.ps1`:

```powershell
& (Join-Path $PSScriptRoot 'tests\Test-ReferenceModResearch.ps1') -Root $RepoRoot
```

- [ ] **Step 5: Run the test and retain the expected missing-report failure**

Run the same command and confirm that only the not-yet-created source reports fail.

### Task 2: Framework, Classification, And Debug Reports

**Files:**
- Create: `docs/reference-mod-research/mods/damnlib.md`
- Create: `docs/reference-mod-research/mods/CAExtendedCategories.md`
- Create: `docs/reference-mod-research/mods/DebugMenu.md`

**Interfaces:**
- Consumes: latest local `mod.info`, Lua entrypoints, item/script fallback logic, category utilities, and debug action implementations.
- Produces: evidence for item script compatibility, category filtering, safe temporary instantiation, official/debug command reuse, and global mutation risks.

- [ ] **Step 1: Audit latest-version entrypoints and manifests**

Record selected version, target PZ version, dependencies, key relative source paths, and older-version differences that affect B42.19.

- [ ] **Step 2: Trace the key mechanisms**

For `damnlib`, trace script fallbacks, registries, module loading, and global patching. For `CAExtendedCategories`, trace item enumeration, tags, hidden/debug/body-location filtering, cache behavior, and temporary item creation. For `DebugMenu`, trace vehicle repair, item generation, health/debug actions, context-menu entrypoints, and which calls delegate to vanilla commands.

- [ ] **Step 3: Write evidence-led reports**

Use relative internal paths and symbol names. Separate confirmed behavior from compatibility inference, and state which mechanisms GodSystem already adopted.

- [ ] **Step 4: Run the integrity test**

Expected: these three reports pass their section/path checks; eight reports remain missing.

### Task 3: Economy And Multiplayer Reports

**Files:**
- Create: `docs/reference-mod-research/mods/CaiGou-Shop.md`
- Create: `docs/reference-mod-research/mods/RuinBazaar.md`
- Create: `docs/reference-mod-research/mods/Server-Shop.md`
- Create: `docs/reference-mod-research/mods/YeseMarket.md`

**Interfaces:**
- Consumes: client/server command dispatchers, transaction handlers, inventory synchronization, shop data, refund flows, offline queues, and UI state handlers.
- Produces: evidence for SP/MP shared backends, server-authoritative economy, operation ordering, inventory synchronization, audit logs, and UI refresh boundaries.

- [ ] **Step 1: Map each shop architecture**

Record where catalog data, UI, transaction logic, persistence, and network handlers live. Identify whether SP and MP share business logic or use separate paths.

- [ ] **Step 2: Trace paid transaction lifecycles**

Trace request, server validation, stock reservation, payment, item/vehicle delivery, synchronization, refund, response, and audit handling. Do not infer transaction guarantees where no operation ID or persistent result cache exists.

- [ ] **Step 3: Trace listing, recycling, and offline behavior**

Record exact authority boundaries for item removal, user-created listings, recycling, offline delivery, hello/retry, and administrator actions.

- [ ] **Step 4: Write four source reports**

Give each report a concise mechanism map, evidence table, adoption guidance, and unverified risks. Explicitly distinguish author MP claims from code-confirmed server handling.

- [ ] **Step 5: Run the integrity test**

Expected: seven reports pass; four reports remain missing.

### Task 4: Traits, Perks, And Combat Ability Reports

**Files:**
- Create: `docs/reference-mod-research/mods/MoreTraits.md`
- Create: `docs/reference-mod-research/mods/TraitsPurchaseSystem.md`
- Create: `docs/reference-mod-research/mods/PsionicAwakening.md`

**Interfaces:**
- Consumes: latest B42 trait registration, dynamic trait events, perk/XP enumeration, purchase/removal checks, save data, visual/combat effects, and MP guards.
- Produces: evidence for trait lifecycle limits, standard MOD perk detection, XP mutation and synchronization, event throttling, and client-only visual ability patterns.

- [ ] **Step 1: Select the latest applicable source tree**

For `1299328280`, use the newest B42 implementation and treat B41 copies only as compatibility history. For `PsionicAwakeningB41`, prioritize its B42.19 tree despite the directory name.

- [ ] **Step 2: Trace trait and XP behavior**

Record registration, conflicts, dynamic addition/removal, initialization timing, standard perk curves, XP mutation, MP synchronization, and effects that cannot be made retroactive by merely adding a trait.

- [ ] **Step 3: Trace combat and rendering patterns**

Record target scans, cooldown timing, rendering events, entity mutation, client/server guards, cleanup paths, and performance controls. Mark any B41-only API as weak evidence.

- [ ] **Step 4: Write three source reports and run the integrity test**

Expected: ten reports pass; only the storage report remains missing.

### Task 5: Storage And Weight Report

**Files:**
- Create: `docs/reference-mod-research/mods/CultivationStorageArtifacts.md`

**Interfaces:**
- Consumes: custom body-location registration, capacity scripts, nested EnergyHub transfer, recursive weight processing, server commands, field synchronization, and restoration logic.
- Produces: evidence for multi-container capacity, recursive weight compression, MP synchronization claims, custom transfer risks, and a safer GodSystem adaptation.

- [ ] **Step 1: Document the actual capacity architecture**

Confirm that apparent large storage is multiple independent capacity-50 containers plus nested child containers, not one `ItemContainer` above the B42 limit.

- [ ] **Step 2: Document weight compression and restoration**

Trace per-container compression rates, original-weight storage, per-instance mutation, `ScriptItem`/`DoParam` mutation, server-to-client field updates, no-power behavior, and world-item restoration scans.

- [ ] **Step 3: Document MP evidence accurately**

Record code-confirmed server weight processing and explicit synchronization. Describe direct client `Remove/AddItem` transfer as a potential transaction risk, not a confirmed desync bug, because no observed player report or reproduction establishes failure.

- [ ] **Step 4: Write the report and run the integrity test**

Expected: all 11 reports and both indexes pass.

### Task 6: Cross-Source Distillation And Handoff Integration

**Files:**
- Modify: `docs/reference-mod-research/README.md`
- Modify: `docs/reference-mod-research/catalog.md`
- Modify: `docs/GodSystem_DevHandoff_CN/00_继续开发入口.md`
- Modify: `docs/GodSystem_DevHandoff_CN/08_参考MOD研究笔记.md`
- Modify: `tools/codex/skills/pz-mod-dev/SKILL.md`
- Modify: `tools/codex/skills/pz-mod-dev/references/pz-b42-patterns.md`

**Interfaces:**
- Consumes: all 11 completed source reports.
- Produces: topic-based discovery, concise handoff links, and portable workflow rules traceable to source reports.

- [ ] **Step 1: Build the final topic index**

Link reports under MP/networking, economy, containers/weight, traits/XP, item compatibility, UI, vehicles/debug, rendering/combat, and performance. Add a short selection guide for choosing same-version evidence.

- [ ] **Step 2: Convert the old monolithic note into an index**

Preserve GodSystem-specific historical conclusions, remove avoidable duplication, and link source reports for detail. Do not delete version history that remains useful.

- [ ] **Step 3: Promote stable patterns into the portable skill**

Add only rules supported by named source reports. Required topics include evidence labeling, reference-version selection, transaction authority, inventory sync, recursive-weight hazards, trait/XP timing, UI refresh discipline, and avoiding global `ScriptItem:DoParam()` mutation for per-instance mechanics.

- [ ] **Step 4: Add discovery links**

Link the research library from the handoff entrypoint and skill so another Codex finds it before internet-only research.

- [ ] **Step 5: Run integrity and encoding checks**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\tests\Test-ReferenceModResearch.ps1
powershell -ExecutionPolicy Bypass -File .\tools\Test-GodSystemEncoding.ps1 -IncludeDocs
```

Expected: both pass.

### Task 7: Final Verification, Review, And GitHub Push

**Files:**
- Verify only; no planned runtime changes.

**Interfaces:**
- Consumes: complete research-library diff.
- Produces: verified documentation commits on `feature/v1.16.57-carry-recycle` and a pushed GitHub branch.

- [ ] **Step 1: Verify scope and repository cleanliness**

Run `git diff --check`, inspect `git diff --stat`, and prove no files under `Contents/`, `workshop.txt`, or version metadata changed.

- [ ] **Step 2: Run the aggregate test suite**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Test-GodSystem.ps1
```

Expected: all currently runnable static, encoding, Lua, and research-library tests pass.

- [ ] **Step 3: Review evidence quality**

Check every `合理推断` statement for an explicit basis, every MP claim for an authority boundary, and every promoted skill rule for at least one linked source report. Correct overstatements before committing.

- [ ] **Step 4: Commit focused documentation changes**

Use focused commits grouped by research reports and cross-source skill consolidation. Do not amend the previously pushed runtime commits.

- [ ] **Step 5: Push the current feature branch**

Run:

```powershell
git push origin feature/v1.16.57-carry-recycle
```

Expected: GitHub branch points to the final documentation commit; `main` remains unchanged.
