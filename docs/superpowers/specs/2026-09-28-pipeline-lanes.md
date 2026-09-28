# Pipeline Lanes and Enforced Merges — Design Spec

**Date:** 2026-09-28
**Status:** Draft
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
mechanically. Everything is driven by a per-project config file, so it ships to pragma unchanged apart from
that file.

## Decisions & Constraints
| Decision | Choice | Rationale |
|---|---|---|
| Relationship to #131 | Supersedes it | Keeps its two load-bearing ideas (the `gates` job runs on every PR; a missing check blocks). Drops the log split, the grep-gate script and the rule restatements, which lanes and the round cap make unnecessary. |
| How a PR's lane is decided | `scripts/pr_lane.py` reads the changed paths and a config file; the highest-ranked matching lane wins | Deterministic, testable, and the same code in every project |
| Lanes | `release`, `app`, `pipeline`, `docs` (rank: app > pipeline > docs; `release` by branch) | See "Lanes" below |
| Where enforcement lives | A `review-evidence` CI job plus branch protection requiring it and `gates` | Prose rules were skipped on most PRs; a required check cannot be |
| Branch protection | Required checks `gates` and `review-evidence` on `develop` and `main`, in FinanceTracker and pragma. Turned on only after `pipeline.yml` is on each repo's `develop` and `main`. | Confirmed by the user 2026-09-28. `enforce_admins` is already on in both repos, so the rule binds the owner too. Enabling it before the checks exist would block every open PR. |
| Review rounds | At most 2. Round 2 reviews only the changes since round 1 and whether round-1 findings were fixed. No round 3: remaining non-HIGH findings become GitHub issues and the verdict is APPROVED; a remaining HIGH goes to the user. | #130 and #131 show that unbounded rounds keep finding new detail |
| Spec and plan PRs | `/review` runs in design mode: contradictions, false claims, feasibility. Implementation detail is written into the spec's "Requirements carried to /plan" section instead of blocking. | A spec reviewed like code never converges |
| Cross-file claims in specs, plans and skills | Must cite `path:line` (or `path:start-end`); `scripts/check_citations.py` fails any citation whose file is missing or whose line is past the end of the file | Catches the cheap half of the false-claim problem mechanically. Whether the cited line *says* what the text claims stays a review question. |
| `/test` | Becomes a coverage-gap audit that runs after `/feature` and before `/gates` | Today it writes tests after `/review` APPROVED, so they are never reviewed and skip RED-before-GREEN |
| Pipeline-change brake | The `pipeline` lane requires a `Motivating incident:` line in the PR body naming a PR, issue or report that shows the problem | The review found 51 of the last 60 PRs were pipeline, docs or release work; the pipeline should change in response to observed failures, not by itself |

## Lanes
| Lane | Chosen when | Required evidence (checked by `review-evidence`) |
|---|---|---|
| `release` | Head branch is `release/*` | None beyond `gates` (unchanged: `/release`'s pre-flight test run is the gate) |
| `app` | Any changed path matches the config's `app` globs | Gate summary `Gates run at <head SHA>` in the PR body; a `Review Agent verdict: APPROVED` review containing `Reviewed at <head SHA>`; a `code-review:` line in the PR body giving the URL of the plugin's `### Code review` comment, or `code-review: no issues` |
| `pipeline` | No `app` match, and any path matches the `pipeline` globs | Gate summary at head SHA; an APPROVED verdict at head SHA; a `Motivating incident:` line |
| `docs` | Nothing above matches | Gate summary at head SHA |

`hotfix/*` branches are laned by their paths like any other branch, so an app hotfix gets the full `app` lane.

FinanceTracker's config, `scripts/pipeline_lanes.json`:
- `app`: `FinanceTracker/**`, `FinanceTrackerTests/**`, `FinanceTrackerUITests/**`, `*.xcodeproj/**`, `*.xctestplan`
- `pipeline`: `.claude/skills/**`, `.claude/hooks/**`, `.claude/commands/**`, `.claude/settings.json`,
  `.claude/context/invariants.md`, `scripts/**`, `.github/**`, `AGENTS.md`, `CLAUDE.md`, `CONSTRAINTS.md`,
  `docs/superpowers/**` (specs and plans are laned `pipeline` so they get a design-mode review)
- Everything else (`docs/**` outside `superpowers/`, `CHANGELOG.md`, `README.md`, `.claude/context/*.md` logs) is `docs`.

A spec for an *app* feature also lands in `docs/superpowers/`, so it is laned `pipeline` and needs a
`Motivating incident:` line. For an app spec that line names the feature request or issue. The line's rule
is "name what this change responds to", which fits both.

## Architecture
Pipeline only. No app code changes.

- **`scripts/pr_lane.py`** (new): `pr_lane.py <base-ref> <head-branch>` prints one lane name. Reads
  `scripts/pipeline_lanes.json` from the base branch (a PR cannot relane itself), matches
  `git diff --name-only <base-ref>...HEAD` against it, exits non-zero on a missing or invalid config.
- **`scripts/check_review_evidence.py`** (new): given the lane, the head SHA, the PR body and the PR's
  review bodies (as JSON on stdin, fetched by the workflow with the job's `GITHUB_TOKEN`), prints each
  required item as found or missing and exits non-zero if any is missing. It never evaluates PR text as
  shell.
- **`scripts/check_citations.py`** (new): scans the changed `.md` files under `docs/superpowers/` and
  `.claude/skills/` for backticked `path:line` and `path:start-end` citations and fails on a missing file or
  an out-of-range line. A citation into another repo (`pragma/...`, `../pragma/...`) is checked only when that
  repo is present, and skipped with a note otherwise.
- **`.github/workflows/pipeline.yml`** (new), on `pull_request` (`opened`, `synchronize`, `reopened`,
  `edited`) and `pull_request_review` (`submitted`), with its own `concurrency` group, not
  `pr-checks.yml`'s:
  - `gates`: today's `gates` job moved from `pr-checks.yml` with no `paths:` filter, plus
    `check_citations.py` and `python3 -m unittest discover scripts/tests`. For the `release` lane it exits
    successfully after printing the lane, which replaces today's job-level `if:` so the required check always
    reports.
  - `review-evidence`: runs `pr_lane.py`, fetches the PR body and reviews, and runs
    `check_review_evidence.py`. Re-runs whenever the body is edited or a review is posted, so adding the
    evidence turns the check green without a new commit.
  - Scripts run from the base-branch checkout, as the `gates` job already does, with the same bootstrap
    rule: the PR that first adds a script runs its own copy and says so in the log.
- **`.github/workflows/pr-checks.yml`**: loses the `gates` job and the comment tying its `paths:` filter to
  the guarded globs. The build and test jobs keep their `paths:` filter.
- **`.claude/skills/review/SKILL.md`**:
  - Starts by running `pr_lane.py` and states the lane in the verdict. The `docs` and `release` lanes need
    no `/review`; it says so and stops.
  - The verdict gains two required lines, `Reviewed at <head SHA>` and `Round <1|2>`.
  - The two-round rule and design mode are stated in one short section. Round 2 gives the subagent the diff
    since the round-1 SHA plus the round-1 findings, not the whole PR again.
  - The gate re-runs and the current severity, logging and isolation rules are otherwise unchanged. This
    spec does not reopen them.
- **`.claude/skills/spec/SKILL.md`** and **`.claude/skills/plan/SKILL.md`**: a step requiring `path:line`
  citations for every claim about another skill or file, and a `## Requirements carried to /plan` section
  in the spec template.
- **`.claude/skills/test/SKILL.md`**: trigger and purpose change to a coverage-gap audit between `/feature`
  and `/gates`. **`.claude/skills/pr-followup/SKILL.md`** chains `/review` then `code-review:code-review`
  and writes the `code-review:` line into the PR body.
- **`.claude/skills/gates/SKILL.md`**: the gate summary also prints the lane.
- **`AGENTS.md`**: the "Standard pipeline" line and the Merge rule are rewritten to point to lanes. The Merge
  rule becomes one sentence: the required checks decide mergeability, and the user merges.
- **`scripts/check_gate_integrity.py`** and **`.claude/hooks/guard_protected_paths.py`**:
  `scripts/pipeline_lanes.json` joins both guarded lists and the hook's `_PROTECTED_FRAGMENTS`
  (`.claude/hooks/guard_protected_paths.py:154-160`); the three new scripts are already covered where they
  match `scripts/check_*`, and `pr_lane.py` is added explicitly.
- **Branch protection** (FinanceTracker and pragma, `develop` and `main`): add required status checks
  `gates` and `review-evidence`, as the last step, after `pipeline.yml` is on both branches.

## Pragma port
Pragma ships the same scripts (in its root `scripts/`, which `setup.sh` copies into a project wholesale,
`pragma/scripts/setup.sh:11`) and the same `pipeline.yml` in `scaffold/.github/workflows/`. Placeholders
follow the existing convention: `setup.sh` replaces `<AppName>` only in skill files
(`pragma/scripts/setup.sh:16`) and `YOUR_PROJECT`/`YOUR_SCHEME` in workflows
(`pragma/scripts/setup.sh:176-177`). So the adopter's lane config is a template at
`scaffold/pipeline_lanes.json` using `YOUR_PROJECT`, and `setup.sh` gains one step that copies it to the
project's `scripts/pipeline_lanes.json` with the same substitution. This step runs after `scripts/` is
copied, so it overwrites the copy of pragma's own config that the wholesale copy brings along.

Pragma's own repo has no CI today. It gets its own `.github/workflows/pipeline.yml` and a
`scripts/pipeline_lanes.json` for itself (`pipeline`: `.claude/**`, `scripts/**`, `scaffold/**`,
`.github/**`; `docs`: everything else; no `app` lane). Its `gates` job runs the script unit tests and
`check_citations.py`.

## Rollout order (both repos)
1. This spec merges (FinanceTracker, under today's rules).
2. The implementation PR merges into FinanceTracker `develop`. It is the first PR laned by the new script,
   and it runs its own new scripts under the bootstrap rule.
3. `/sync-workflow` opens the pragma PR; it merges into pragma `develop`.
4. Both releases (`release/*` to `main`) carry `pipeline.yml` to `main`.
5. Branch protection is turned on for `develop` and `main` in both repos, and a docs-only test PR in each repo
   shows both checks reporting.

## Data Models / Domain Services / Navigation / Design
None.

## Requirements carried to /plan
- Several check runs named `review-evidence` can exist for one SHA (one per trigger). Confirm branch
  protection uses the latest, and if not, give each trigger's run the same check name via one job.
- `pull_request_review` runs use the PR head's workflow file; confirm the `GITHUB_TOKEN` there can read the PR
  body and reviews (`pull-requests: read`).
- The `Motivating incident:` requirement needs an escape for a genuine one-off (for example, a dependency
  bump): decide whether `none (reason)` is accepted.

## Future Extension Points
- Moving the grep gates into a script (from #131) stays possible later; it is not needed for enforcement.
- A lane for dependency-only changes.

## Testing Strategy
- Unit tests in `scripts/tests/` for each new script, using temporary git repos and JSON fixtures:
  - `pr_lane.py`: every lane, rank order, the `release/*` branch rule, a missing or invalid config, and
    that the base-branch config wins over the PR's.
  - `check_review_evidence.py`: each required item present, missing, or present at a stale SHA, per lane.
  - `check_citations.py`: valid, missing-file, out-of-range, a range citation, and a skipped other-repo
    citation.
- **Acceptance:**
  - The implementation PR shows `gates` and `review-evidence` checks.
  - After protection is on, a docs-only PR in each repo passes both checks with only a gate summary.
  - An app-lane test PR without a `/review` verdict shows `review-evidence` failing and cannot merge.
  - `/review` on the implementation PR stops at round 2 at most.
