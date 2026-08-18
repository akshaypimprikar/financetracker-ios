# Changelog

All notable changes to FinanceTracker are documented here.

---

## [Unreleased]

### Added
- **`Theme.Glass` design tokens** — translucent-material card style (`cardMaterial`, `netWorthTint`, `spendingTint`, shadow tokens) for Dashboard hero cards, matching the app's existing iOS 26 glass tab bar instead of the prior flat-tint card style. `Theme.Typography.amountDisplay` now uses `.rounded` font design (Wallet/Stocks-style numerals). Tokens only — `DashboardView` adoption lands in a follow-up feature PR.

### Fixed
- **"Creditcard" account type label** — `AccountType.rawValue.capitalized` rendered `creditCard` as "Creditcard" (capitalize doesn't split camelCase) in `AccountRow` and `AccountDetailView`. Added `AccountType.displayName` as the single source of truth for both call sites.
- **`/review`'s pre-review-fix logging pointed at a non-invokable `/code-review`** — the correct skill name, used correctly two lines away in the same file, is `code-review:code-review`. Found by the 2026-08-17 pipeline review.
- **`.claude/settings.json`** — removed 4 redundant double-slash permission entries (`Read(//Users/akshaypimprikar/.claude/**)` and three narrower subsets of it) already covered by the existing single-slash `Read(/Users/akshaypimprikar/.claude/**)` grant, plus the blanket `Read(//Users/akshaypimprikar/Desktop/**)` grant, already redundant with `additionalDirectories`' explicit `/Users/akshaypimprikar/Desktop` entry. Left the equivalent `Read(//Users/akshaypimprikar/Documents/**)` grant in place — unlike Desktop, Documents isn't in `additionalDirectories` and no memory or command file references it, so narrowing or removing it risks cutting off a workflow with no visibility into whether it's actually used; flagged for the user to decide rather than guessed at. Found by the 2026-08-17 pipeline review.

---

## [1.2.2] — 2026-08-17

### Fixed
- **Re-render cleanup pass** — memoized `TransactionViewModel.filteredTransactions` (previously re-filtered/re-sorted on every access); `AccountListView` now computes `netWorth()` once per render instead of twice (each call does one repository fetch per account); `BudgetListView`'s month-change reload is now debounced (150ms); dropped unused `@Bindable` in `BudgetDetailView`/`TransactionDetailView` (no `$viewModel` bindings existed in either). All 5 fixes sourced from the same Instruments profiling session; see `docs/superpowers/specs/2026-08-16-re-render-cleanup-pass.md`.
- **`UITestImportFlowTests` simulator-launch failure (`SBMainWorkspace RequestDenied`)** — the "iPhone 17" (iOS 26.4) simulator's internal SpringBoard state was corrupt; killing `Simulator.app`/`CoreSimulatorService` didn't fix it (tried during the v1.2.1 release, see [1.2.1]'s Known issues). `xcrun simctl erase` on the affected device followed by a reboot did — verified by re-running the previously-failing test to a pass. Not an app-code issue.
- **CLAUDE.md's destination string ambiguous across two "iPhone 17" simulators** — an iOS 26.5 runtime is now installed alongside iOS 26.4, each with its own "iPhone 17" device, so `-destination 'platform=iOS Simulator,name=iPhone 17'` could silently resolve to either. Pinned to `OS=26.4.1` explicitly in CLAUDE.md, README.md, and every `.claude/commands/*.md` that runs `xcodebuild`; same fix applied to the global `ios-build-verify`/`ios-coverage` skills (pragma's template `.claude/commands/*.md` already used a `<simulator from CLAUDE.md>` placeholder, so it wasn't affected).
- **`/feature`'s TDD instruction referenced a non-invokable skill** — `Skill(test-driven-development)` errors with `Unknown skill` in this environment; the Superpowers plugin flag in `.claude/settings.json` being `true` doesn't mean its skills are actually loadable here, confirmed empirically (no Superpowers skill name has ever appeared in an available-skills listing this repo has seen). Replaced with a self-contained instruction carrying the same substance (the Iron Law, verify-red-for-the-right-reason, the tests-after-prove-nothing argument) directly in `feature.md` instead of depending on an invocation that doesn't work. Same fix ported to pragma's template `feature.md`. Found by the 2026-08-16 pipeline review.
- **`.githooks/pre-push` blocked deleting an already-merged branch's remote ref** — the merged-PR check had no exemption for delete pushes (all-zero `local_sha`), the way it already exempted tag pushes; routine `git push origin --delete <branch>` cleanup after a merge was incorrectly blocked, forcing a `gh api -X DELETE` workaround. Added the same class of exemption tag pushes already had, scoped so deleting `develop`/`main` directly is still blocked. Found and fixed during the v1.2.1 release, formalized by the 2026-08-16 pipeline review.
- **`.claude/settings.json`** — removed 6 `WebFetch(domain:...)` entries made redundant by the existing blanket `WebFetch(*)` grant

---

## [1.2.1] — 2026-08-16

### Added
- **README screenshots** — Dashboard, Transactions, Budgets, and Accounts, captured with realistic seeded data via a new `--seedscreenshots` launch argument (`DemoDataSeeder`, in-memory only, never touches a real persisted store) and a `--starttab=<name>` argument for capturing each tab without scripted UI taps
- **`/gates` Gate 10** — restored the generic duplication/abstraction-bloat heuristic that was silently dropped when Gate 8 was replaced with the app-specific CSV import concurrency check; added as a new gate rather than reusing the slot, so it doesn't collide with the app-specific check
- **`/gates` Gate 11 — RED-before-GREEN commit order** — `/feature` now commits RED (failing test) and GREEN (implementation) separately, and `scripts/check_tdd_commit_order.py` verifies from git history that the test commit precedes the implementation commit, rather than trusting the agent's self-report. A git-history audit of three merged feature branches found every ViewModel task commit bundled the failing test and its implementation together — the exact failure mode documented in Martin Fowler's "TDD inside the agent loop" and corroborated independently by Simon Willison and testdouble. `/feature` also now invokes the already-installed `test-driven-development` Superpowers skill instead of a one-line paraphrase. Ported to the pragma template repo as a generic gate.

### Fixed
- **`.claude/settings.json`** — removed 20 redundant/dead permission entries (8 pragma `git -C` entries and 2 `GITFLOW_RELEASE_MERGE` entries already covered by broader patterns already in the file, plus 12 session-specific one-off artifacts from past debugging/LinkedIn-drafting sessions)
- **`DemoDataSeederTests`** — the CI coverage gate correctly failed on `DemoDataSeeder.swift` at 0% (no exception carved out for debug tooling); added real tests asserting seeded counts and computed account balances, now at 96.5%
- **Pipeline: `/review` now logs pre-review fixes to `rejections.md` and posts its verdict as a real GitHub review** — the file previously only logged this review's own CHANGES REQUESTED violations, but real bugs are typically caught and fixed earlier (via `/code-review` or manual verification) before `/review`'s formal pass runs, so the file never accumulated anything across 75+ PRs despite recurring bug patterns; `/review` also now posts its verdict via `gh pr review --comment` instead of only reporting it in-session, giving it an independent, timestamped trace instead of prose in the same PR it's approving
- **Pipeline: `/feature` now requires both a repeat-call/duplicate test and a missing-field test for any new mutation on a shared/persisted entity** — closes the gaps documented in `docs/2026-05-18-correctness-review-postmortem.md` (Rule 6 and issue #10), where TDD's write-test-first sequencing didn't prevent a missing-negative-path bug because the failure mode was never imagined; `/test`'s coverage targets updated to match, and fixed a same-PR inconsistency where `/feature` said "or" while `/test` said "and" for the same rule
- **Pipeline: fixed `/test`'s Trigger description contradicting `/pr-followup` and `/feature`** — it previously claimed to run "in parallel with `/review`"; it actually runs after `/review` reports APPROVED
- **Pipeline: `/sync-workflow` now self-reviews before opening a pragma PR** — pragma has no `CLAUDE.md` and no equivalent to `/review`, and every prior sync PR merged with zero GitHub reviews; added a 3-point checklist (no FinanceTracker-specific literals leaked into template content, `<placeholder>` convention held, gate numbering/counts internally consistent) run before committing
- **`/sync-workflow`'s self-review checklist** — fixed two bugs `code-review:code-review` found on its own first PR: step 5's checks ran against `git diff --cached` before staging happened (staging was in the later step 6), and step 5c's gate-count check was case-sensitive, silently missing the capitalized `All N gates` line in `gates.md`'s "Done when" section — the exact line that's historically gone stale (commits `ddb58f0`, `1137aea`)
- **`scripts/check_tdd_commit_order.py`** — fixed `git log develop...HEAD` (triple-dot) to `develop..HEAD` (double-dot); for `git log` (unlike `git diff`), triple-dot is symmetric difference and would pull in `develop`-only commits into the branch's commit list once `develop` advances past the fork point, corrupting the RED/GREEN ordering check. Also updated `/gates` Gate 5's CHANGELOG fallback text, which still assumed one commit per task

### Known issues
- **`UITestImportFlowTests.testImportButtonOpensSheetAndChooseFileLaunchesDocumentPicker` fails locally due to simulator infrastructure, not app code** — the ephemeral test-runner simulator clone fails to launch (`SBMainWorkspace RequestDenied`), unrelated to any change in this release (zero Swift files touched by the PRs that shipped it). Tracked in `Project Actions.md` (This Week, #p1). This release's pre-flight test run was waived past this specific failure with that context confirmed.

---

## [1.2.0] — 2026-07-31

### Added
- **On-device CSV category suggestions** — `CategorySuggesting` Domain Service protocol and `FoundationModelsCategorySuggester` (on-device Apple Intelligence, zero network calls, fails safe when unavailable); suggestion chips in `ImportSheet` with sparkle-opacity-by-confidence, one-tap category creation via `ImportViewModel.createAndAssignCategory`, and a `CategoryNameMatching` token-set matcher shared by suggestion-matching, AI-create dedup, and manual category creation (`AddCategorySheet` near-duplicate warning, `CategoryViewModel.findNearDuplicate`)
- **`TransactionImportActor`** — `@ModelActor`-based chunked, cancellable CSV import writes replacing the old per-row scan/save; determinate progress bar and cancel button in `ImportSheet`; a generation-tokened `ImportRecord` audit trail that survives partial failures instead of silently dropping them
- **Versioned SwiftData schema** — all `@Model` types wrapped in `SchemaV1: VersionedSchema` with a no-op `FinanceTrackerMigrationPlan`, preventing silent data corruption on future model changes
- **Budget empty-state, device-aware** — `AddBudgetSheet` offers CSV-import-only messaging when on-device suggestions are available, a manual "Add Category" fallback when they aren't
- **`Theme/Chips.swift`** — `chipLabel` typography token for the category-suggestion chip pattern
- **Persistent memory layer** — `.claude/context/` (invariants, decisions, rejections, feature-log) wired as read/write pre/postambles into all 8 agent commands
- **Pipeline commands** — `/parallel-review` (runs `/review`'s architecture checklist and `code-review:code-review` in parallel before `/gates`); `/pr-followup` (auto-chains `/review` then `/test` after a PR opens); `/goal` usage tips on `/gates`/`/test`
- **`/gates`** — Gate 8 (`TransactionImportActor` concurrency-shape check) and Gate 9 (architecture-compliance/Patterns checklist, ported from `/review`); skips Gates 1–2 (build/test) when no Swift files changed

### Fixed
- **CSV import correctness** — category-seeding partial-failure rollback (no more orphaned categories), suggestion-loading generation guard (no stale writes into a fresh session), connector-word-only name false-matching, untrimmed category name persistence, new categories staged until import actually completes (no more orphaned unused categories on cancel), `ImportSheet` re-loading categories/accounts on every appear
- **`CategoryNameMatching` type-blindness** — Income and Expense categories sharing a name (e.g. "Rent") are no longer cross-matched or cross-suggested, since CSV import only ever creates `.debit` transactions
- **`BudgetListView`** — toolbar Add button was disabled exactly when its own empty-state message needed to be shown, making the message unreachable
- **`/gates` false positives** — missing `chore/*` branch-naming pattern; ViewModels-concrete-repo check flagging legitimate in-memory test fixtures under `Tests/`
- **CI flakiness** — disabled parallel simulator testing for the UI Tests job (clone contention on shared `macos-26` runners); replaced a timing-guess in the import-cancellation test with a deterministic chunk-start signal
- **Pipeline docs** — removed stale auto-merge instruction from `/review` (added a CLAUDE.md merge rule instead, since GitHub blocks self-approval); corrected `/parallel-review` docs that claimed an automated `code-review:code-review` invocation the skill's `disable-model-invocation` flag makes impossible

---

## [1.1.0] — 2026-05-23

### Added
- **Charts** — running balance line chart on Account detail; month-over-month spending bar chart on Budget detail; both gated on data presence
- **Theme token system** — `Colors.swift`, `Spacing.swift`, `Typography.swift` with semantic tokens; all existing views refactored to use tokens
- **`Theme/Charts.swift`** — chart visualisation tokens: `balanceLine`, `balanceAreaFill`, `spendingBar`, `gridLine`, `minHeight`, `lineStrokeWidth`
- **`docs/design-system.md`** — canonical token reference and component pattern guide, including Data Visualisation section
- **Theme unit tests** — 15 tests covering all color and spacing token values
- **`/design` agent** — bootstrap and extend modes; establishes `Theme/` token system before UI features; enforced via `/spec` and `/review`
- **PR checks CI** — GitHub Actions workflow with coverage enforcement (fail <60%, warn <80%) and path-filtered triggers
- **UI tests CI** — separate workflow blocking PRs on `UITestChartsTests` failures; `pull_request` trigger added so broken tests can no longer reach `develop`
- **Coverage enforcement** — `xccov` check reports per-file line coverage
- **Pre-push git hook** — blocks direct pushes to `develop`/`main` and already-merged PR branches
- **Pipeline tooling** — `/gates`, `/pipeline-review`, `/status` commands; CHANGELOG rule in `/bugfix`; cross-repo shell safety rule in CLAUDE.md

### Fixed
- **Correctness** — `BalanceService` anchor offset; `CSVImportService` negative amounts and date-only hash; `BudgetViewModel` duplicate detection; `TransactionRepository` transfer fetch; `BudgetRepository` sort order
- **Chart UI tests** — corrected accessibility identifiers, removed wrong NavigationStack navigation assumption, skipped redundant Picker interaction in budget test
- **All UI tests** — increased timeouts from 3s to 10s and added navigation bar existence checks before button taps; 3s was consistently too short for CI runners
- **UX** — rendering and interaction correctness across ViewModels and Views

---

## [1.0.0] — 2026-05-11

### Added
- **Multi-agent workflow** — 8 slash commands (`/spec`, `/plan`, `/feature`, `/test`, `/review`, `/bugfix`, `/release`, `/sync-workflow`) defining a full spec → plan → TDD → PR → release pipeline
- **UI tests** — 6 XCUITest flows covering tab navigation, add account, add transaction, add budget, and add category; `--uitesting` launch arg switches SwiftData to in-memory store for clean isolation
- **Accessibility identifiers** — 13 identifiers across 8 view files for stable test targeting
- **Gitflow** — `develop` integration branch; `feature/*`, `fix/*`, `spec/*` → `develop`; `release/*` → `main` via PR
- **README** — project overview, pipeline diagram, architecture summary, repo structure guide
- `.gitignore` covering Xcode derived data, `.DS_Store`, Claude local files, and plugin cache
- `CLAUDE.md` trimmed to 44 lines with always-on architecture rules and agent pipeline

### Fixed
- Removed nested duplicate Xcode project structure that caused `PBXFileSystemSynchronizedRootGroup` to compile every Swift file twice

---

## [0.2.0] — 2026-05-08

### Added
- **CSV Import** — 3-step import flow (file picker → column mapping → preview/confirm) with SHA256 deduplication
- **`ImportViewModel`** — state machine managing the 3-step import process
- **`ImportSheet`** — SwiftUI sheet for the full import flow
- **`ImportRecordRepositoryProtocol`** + **`SwiftDataImportRecordRepository`** — audit log persistence
- **Budgets tab** — `BudgetViewModel`, `BudgetListView`, `AddBudgetSheet`, `BudgetDetailView` with month selection and progress tracking
- **Settings tab** — `CategoryViewModel`, `SettingsView`, `AddCategorySheet` for managing expense/income categories
- All 6 ViewModels wired into `ContentView` via repository injection
- Tests for `ImportViewModel` (4), `BudgetViewModel` (4)

### Fixed
- `AddTransactionSheet` Picker tags switched from `Category?` to `UUID?` to avoid `Hashable` conformance conflict on `@Model` types

---

## [0.1.0] — 2026-05-07

### Added
- **Foundation** — full MVVM + Repository architecture
- **Data models** — `Account`, `Transaction`, `Category`, `Budget`, `ImportRecord` (`@Model`)
- **Domain services** — `BalanceService`, `NetWorthService`, `BudgetCalculationService`, `CSVImportService`, `NotificationService`
- **Repository protocols** — `AccountRepositoryProtocol`, `TransactionRepositoryProtocol`, `CategoryRepositoryProtocol`, `BudgetRepositoryProtocol`, `ImportRecordRepositoryProtocol`
- **SwiftData repositories** — implementations for all 5 protocols
- **ViewModels** — `AccountViewModel`, `TransactionViewModel`, `DashboardViewModel`
- **Core screens** — Dashboard, Transaction list + detail, Account list + add sheet, Add Transaction sheet
- **5-tab navigation** — Dashboard · Transactions · Budgets · Accounts · Settings (`TabView` + `NavigationStack`)
- Unit and integration tests for all Domain Services and repository implementations
