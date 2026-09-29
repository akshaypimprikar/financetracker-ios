# Pipeline Lanes and Enforced Merges — Design Spec

**Date:** 2026-09-28
**Status:** Approved
**Supersedes:** `2026-09-28-review-simplification.md` (PR #131)

## Overview
The 2026-09-28 pipeline review of the last 40 merged PRs (#92-#131) found three root causes behind its findings:

1. **Rules are prose, so skipping them is free.** Of 37 non-release PRs, 20 had no `/review` verdict and 3
   merged without APPROVED, although AGENTS.md's Merge rule requires it. Nothing checks it.
2. **One heavy process for every PR.** A docs edit and an app feature face the same rule, so the rule is
   routed around rather than followed.
3. **Review is unbounded.** PR #130 took 56 verdicts and #131 took 5 rounds whose blocking findings
   (4, 5, 2, 3, 4) did not converge. Six of the logged findings were false claims about another skill that
   the author could have checked while writing.

This spec fixes the causes: a script sorts each PR into a **lane** by its changed paths, each lane has its
own required evidence, a CI job checks that evidence, and branch protection makes the check binding.
`/review` gets a hard two-round cap and a design mode for specs. Claims that cite `file:line` are checked
mechanically. The scripts and workflows are the same in every project; a per-project config file holds the lane
globs and each lane's evidence, so pragma ships them with its own config.

## Decisions & Constraints
| Decision | Choice | Rationale |
|---|---|---|
| Relationship to #131 | Supersedes it | Keeps its two load-bearing ideas (the `gates` job runs on every PR; a missing check blocks). Drops the log split, the grep-gate script and the rule restatements, which lanes and the round cap make unnecessary. |
| How a PR's lane is decided | `scripts/check_pr_lane.py` reads the changed paths, the head and base branches, and a per-project config; see "Lanes" | Deterministic, testable, the same code in every project. The `check_` prefix puts it under the existing `scripts/check_*` guard glob and the hook's `scripts/check_` fragment. |
| What each lane requires | Listed in the config per lane, as evidence items (`gate_summary`, `review_verdict`, `code_review`, `motivating_incident`, `synced_from`) | Projects differ: pragma has no Xcode project, so it cannot produce a `/gates` summary, and its lanes simply do not list one |
| Where enforcement lives | A `review-evidence` check that runs the **base branch's** workflow and scripts (`pull_request_target`) and never checks out PR code, plus branch protection requiring it and `gates` | A PR can edit a `pull_request` workflow to pass itself; it cannot edit the base branch's. Reading PR data only through the API keeps `pull_request_target` safe. |
| Branch protection | Required checks `gates` and `review-evidence` on `develop` and `main`, in FinanceTracker and pragma, turned on last (see "Rollout order") | Confirmed by the user 2026-09-28. `enforce_admins` is already on in both repos. |
| Evidence at a moved head | Evidence recorded at SHA `X` counts for head `H` when `X` = `H`, or `X` is an ancestor of `H` and every file changed in `X..H` is on the config's `carryover_paths` list (FinanceTracker: `.claude/context/rejections.md`, `.claude/context/incidents.md`) | /review's own log commit, and the `code-review` line edit, must not invalidate the verdict they follow |
| Review rounds | At most 2 full rounds. Round 2 reviews only `X..H` since round 1 plus whether round-1 findings were fixed. After that, remaining non-HIGH findings become GitHub issues and the verdict is APPROVED; a remaining HIGH goes to the user. | #130 and #131 show unbounded rounds keep finding new detail |
| Code changes after APPROVED | A `/review --confirm` verdict covers only `X..H` since the last APPROVED SHA and blocks only on a HIGH introduced in that delta. It is not a round. | Without it, any fix after approval (for example a `code-review` finding) could never get evidence at the new head |
| Order after a PR opens | `/pr-followup` runs `code-review:code-review` first and fixes its findings, then `/review` | Fixes land before the review rounds, so the head moves less after approval |
| Spec and plan PRs | `/review` runs in design mode: contradictions, false claims, feasibility. Implementation detail goes to the spec's "Requirements carried to /plan" section instead of blocking. | A spec reviewed like code never converges |
| Cross-file claims in specs, plans and skills | Must cite `path:line` (or `path:start-end`); `scripts/check_citations.py` fails a citation whose file is missing or whose line is past the end | Catches the cheap half of the false-claim problem mechanically. Whether the cited line *says* what the text claims stays a review question. |
| `/test` | Becomes a coverage-gap audit that runs after `/feature` and before `/gates` | Today it writes tests after `/review` APPROVED, so they are never reviewed and skip RED-before-GREEN |
| Pipeline-change brake | The `pipeline` lane requires a `Motivating incident:` line naming a PR, issue or report that shows the problem, or `none (<reason>)` | 51 of the last 60 PRs were pipeline, docs or release work; the pipeline should change in response to observed failures. `none (<reason>)` keeps genuine one-offs possible and visible. |
| `code-review` on pipeline PRs | Required in the `pipeline` lane too | The user's standing rule: run `code-review:code-review` on pipeline and tooling PRs, not only app PRs |

## Lanes
Evaluated in this order; the first that applies wins.

| Lane | Chosen when | Evidence (FinanceTracker config) |
|---|---|---|
| `release` | (head `release/*` and base `main`) or (head `main` and base `develop`, the back-merge), **and** every path changed on the release branch itself is on the config's `release_paths`: for a `release/*` PR that is `develop...head` (the commits unique to the release branch, the same check `/release` runs at `.claude/skills/release/SKILL.md:82`), not the PR's diff against `main`, which holds the whole release delta (`.github/workflows/gates.yml:7-9`); for the back-merge it is the PR's diff (FinanceTracker: `FinanceTracker.xcodeproj/project.pbxproj`, `CHANGELOG.md`, `.claude/context/feature-log.md`). Otherwise the PR is laned by its paths, including when that list is empty. A PR from a fork never gets this lane or `sync`, and a `release/*` PR whose `develop...head` compare fails, or hits GitHub's 300-file cap, makes `review-evidence` exit with an error rather than guess. | none (the `gates` check still runs; `/release`'s pre-flight test run is the gate) |
| `sync` | head `sync/*` **and** every changed path is on the config's `sync_paths` (pragma: `.claude/skills/**`, `scaffold/**`, the only paths `/sync-workflow` stages). Otherwise laned by paths. Only in configs that define it. | `synced_from`: a line naming the source PR, whose content was already reviewed there |
| `app` | any changed path matches `app` globs | `gate_summary`, `review_verdict`, `code_review` |
| `pipeline` | any changed path matches `pipeline` globs | `gate_summary`, `review_verdict`, `code_review`, `motivating_incident` |
| `docs` | otherwise | `gate_summary` |

Evidence items (the first three are tied to a SHA and subject to the carryover rule):
- `gate_summary`: `Gates run at <sha>` in the PR body.
- `review_verdict`: the latest `## Review Agent verdict:` review posted by an owner, member or collaborator (other accounts' reviews are ignored) is APPROVED (a full round or `--confirm`) and contains `Reviewed at <sha>`.
- `code_review`: a `code-review: <comment URL> at <sha>` or `code-review: no issues at <sha>` line in the PR body.
- `motivating_incident`, `synced_from`: a non-empty line with that label in the PR body.

FinanceTracker's lane globs:
- `app`: `FinanceTracker/**`, `FinanceTrackerTests/**`, `FinanceTrackerUITests/**`, `*.xcodeproj/**`, `**/*.xctestplan`
- `pipeline`: `.claude/skills/**`, `.claude/hooks/**`, `.claude/commands/**`, `.claude/settings.json`,
  `.claude/context/invariants.md`, `scripts/**`, `.github/**`, `.githooks/**`, `AGENTS.md`, `CLAUDE.md`,
  `CONSTRAINTS.md`, `docs/superpowers/**` (specs and plans get a design-mode review)
- `docs`: everything else (`docs/**` outside `superpowers/`, `CHANGELOG.md`, `README.md`, the `.claude/context/` logs)

`hotfix/*` branches are laned by their paths, so an app hotfix gets the full `app` lane. A spec for an app
feature is laned `pipeline`; its `Motivating incident:` line names the feature request or issue.

## Architecture
Pipeline only. No app code changes.

- **`scripts/check_pr_lane.py`** (new): prints the lane for a list of changed paths, a head branch, a base
  branch and a config file. It exits non-zero on an invalid config.
- **`scripts/check_review_evidence.py`** (new): given the lane, the head SHA, the PR body, the PR's reviews
  and, for the carryover rule, the files changed between an evidence SHA and the head (all as JSON on stdin),
  prints each required item as found or missing and exits non-zero if any is missing. It treats PR text as
  data only.
- **`scripts/check_citations.py`** (new): scans the changed `.md` files under `docs/superpowers/` and
  `.claude/skills/` for backticked `path:line` and `path:start-end` citations and fails on a missing file or
  out-of-range line. A citation into another repo is checked when that repo is present, skipped with a note
  otherwise.
- **`scripts/pipeline_lanes.json`** (new): the lane globs, `release_paths`, `carryover_paths` and each lane's
  evidence items.
- **`.github/workflows/gates.yml`** (new, `pull_request` only, its own `concurrency` group): today's
  `gates` job moved from `pr-checks.yml` with no `paths:` filter, reading base and head from
  `github.event.pull_request.base.ref` and `.head.ref`, plus `check_citations.py` and
  `python3 -m unittest discover scripts/tests`. It keeps today's two checkouts (PR head, and the base branch
  as the trusted copy) and runs every script, `check_citations.py` and the unit tests included, from the base
  checkout, with the same bootstrap fallback to the PR's copy only for a script the base does not have yet
  (`.github/workflows/gates.yml:70-96`). A PR therefore cannot edit a gate script and have its own
  copy judge it. It runs on every PR so the required check always reports. For the `release` lane it prints the lane and
  exits 0 without running the scripts, as today's job skips release PRs because they diff the whole release
  delta (`.github/workflows/gates.yml:70-71`).
- **`.github/workflows/review-evidence.yml`** (new, `pull_request_target` on `opened`, `synchronize`,
  `reopened`, `edited`): checks out the base branch only, gets changed files, the PR body, reviews and
  `compare` results from the GitHub API with the job's read-only `GITHUB_TOKEN`, then runs
  `check_pr_lane.py` and `check_review_evidence.py` from the base checkout. Posting a review does not
  trigger `pull_request_target`, so `/review` and `/pr-followup` finish by editing the PR body (the verdict
  link and the `code-review:` line), which does.
- **Bootstrap:** while the base branch has no `pipeline_lanes.json` or no checker scripts (only before
  rollout step 4), `review-evidence` prints a warning and passes. Branch protection is turned on only after
  both are on `develop` and `main`, so the warning path is never binding.
- **`.github/workflows/pr-checks.yml`**: loses the `gates` job and the comment tying its `paths:` filter to
  the guarded globs. Its build and test jobs keep their `paths:` filter.
- **Guard lists** (`scripts/check_gate_integrity.py` `GUARDED_PATH_GLOBS`, the hook's `PROTECTED_GLOBS` and
  `_PROTECTED_FRAGMENTS` at `.claude/hooks/guard_protected_paths.py:154-160`): add
  `scripts/pipeline_lanes.json` and `.github/workflows/*`, with fragments `pipeline_lanes.json` and
  `.github/workflows/`. The three scripts are already covered by `scripts/check_*` and its fragment.
- **`.claude/skills/review/SKILL.md`**: runs `check_pr_lane.py` first and states the lane; `docs`,
  `release` and `sync` lanes need no `/review`, and it says so and stops. The verdict gains `Reviewed at
  <sha>` and `Round <1|2|confirm>`. One short section states the round cap, `--confirm` and design mode.
  It ends by writing the verdict link into the PR body. The gate re-runs and the current severity, logging
  and isolation rules are otherwise unchanged.
- **`.claude/skills/pr-followup/SKILL.md`**: `code-review:code-review` first, fix its findings, then `/review`;
  writes the `code-review:` line with the SHA it ran at.
- **`.claude/skills/spec/SKILL.md`** and **`plan/SKILL.md`**: require `path:line` citations for claims about
  another skill or file, and add a "Requirements carried to /plan" section to the spec template.
- **`.claude/skills/test/SKILL.md`**: a coverage-gap audit between `/feature` and `/gates`.
- **`.claude/skills/gates/SKILL.md`**: the gate summary prints the lane.
- **`.claude/skills/release/SKILL.md`**: the back-merge from `main` to `develop`
  (`.claude/skills/release/SKILL.md:105-107`) becomes a PR, which the `release` lane covers, instead of a
  direct push that the existing `develop` protection already forbids.
- **`AGENTS.md`**: the "Standard pipeline" line and the Merge rule point to lanes. The Merge rule becomes one
  sentence: the required checks decide mergeability, and the user merges.

## Pragma port
A hand-authored pragma PR, not `/sync-workflow`, which stages only `.claude/skills/` and `scaffold/`
(`.claude/skills/sync-workflow/SKILL.md:65`). It carries:
- The same three scripts and their tests in pragma's `scripts/`, plus explicit `cp` lines for them in
  `setup.sh`'s script-copy step (`pragma/scripts/setup.sh:117-124`, which copies named files, not the
  directory).
- `scaffold/.github/workflows/gates.yml` and `review-evidence.yml`, and removal of the `gates` job from
  `scaffold/.github/workflows/pr-checks.yml` (done in pragma #85).
  `setup.sh` skips workflow files that already exist, so the pragma CHANGELOG tells existing adopters to
  delete that job by hand.
- `scaffold/pipeline_lanes.json`, a template using `YOUR_PROJECT` like the scaffold workflows
  (`pragma/scripts/setup.sh:177-178`), and a `setup.sh` step that copies it to the project's
  `scripts/pipeline_lanes.json` with the same substitution, skipping it if the file already exists.
- The same skill edits, with pragma's placeholders.
- Pragma's own CI, for the first time: `.github/workflows/gates.yml` (script unit tests and
  `check_citations.py`) and `review-evidence.yml`, with its own `scripts/pipeline_lanes.json`: no `app` lane;
  `pipeline` = `.claude/**`, `scripts/**`, `scaffold/**`, `.github/**`, `.claude-plugin/**`, `evals/**`,
  `CONSTRAINTS.md`, `AGENTS.md`, `CLAUDE.md`, requiring `review_verdict`, `code_review` and
  `motivating_incident` but no `gate_summary`, since pragma has no Xcode project for `/gates`; `sync` for
  `sync/*` heads that change only `sync_paths`; `docs` for the rest, requiring nothing.

## Rollout order (both repos)
1. This spec merges.
2. The FinanceTracker implementation PR merges into `develop`. `review-evidence` does not run on it yet,
   because `pull_request_target` uses the base branch's workflow, which does not exist.
3. The pragma PR merges into pragma `develop`.
4. Each repo's `release/*` PR merges to `main`, then the back-merge PR from `main` to `develop`. Both are
   `release` lane.
5. Branch protection is turned on for `develop` and `main` in both repos. A docs-only test PR in each repo
   shows both checks passing, and an app-lane test PR without a verdict shows `review-evidence` failing.

## Data Models / Domain Services / Navigation / Design
None.

## Requirements carried to /plan
- Several `review-evidence` runs can exist for one SHA. With `cancel-in-progress`, make sure a cancelled run
  can't be the latest one branch protection sees (or don't cancel in progress for this workflow).
- `check_review_evidence.py` uses the latest verdict review by submission time, not any review containing
  the string.
- Glob semantics: gitignore-style `**`, and whether a pattern without `/` matches at any depth.
- The citation regex must not match `host:port`, `ref:path` or URLs.
- `check_citations.py` checks every citation in a changed file, old ones included; decide whether that is
  wanted or only added lines count.
- The release back-merge PR needs the `develop` PR requirement's settings (reviews: 0) to allow it; confirm.
- Confirm on the rollout step-5 test PR that a `pull_request_target` check run attaches to the PR head SHA,
  so branch protection counts it as `review-evidence`.
- The bootstrap warning path may be unreachable (`pull_request_target` has no workflow until the base has
  one); keep it minimal or drop it.
- Release PRs must be merged with a merge commit, not squashed, or the back-merge re-diffs the whole release.

## Future Extension Points
- Moving the grep gates into a script (from #131) stays possible later; it is not needed for enforcement.
- A lane for dependency-only changes.

## Testing Strategy
- Unit tests in `scripts/tests/` for each new script, using temporary git repos and JSON fixtures:
  - `check_pr_lane.py`: every lane, rank order, the `release` rule's branch and path conditions (a
    `release/*` PR with other paths is laned by its paths), the back-merge, `sync`, and an invalid config.
  - `check_review_evidence.py`: each item present, missing, at a stale SHA, and at an ancestor SHA with
    only carryover paths changed (passes) or other paths changed (fails), per lane; `--confirm` verdicts.
  - `check_citations.py`: valid, missing-file, out-of-range, a range citation, and a skipped other-repo
    citation.
- **Acceptance:**
  - The implementation PR shows the `gates` check (`review-evidence` cannot run on it; see Rollout step 2).
  - After protection is on, a docs-only PR in each repo passes both checks with only its lane's evidence.
  - An app-lane test PR without a `/review` verdict shows `review-evidence` failing and cannot merge.
  - `/review` on the implementation PR stops at round 2 at most, plus `--confirm` verdicts if needed.
