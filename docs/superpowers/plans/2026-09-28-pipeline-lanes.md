# Pipeline Lanes Implementation Plan

**Goal:** Implement `docs/superpowers/specs/2026-09-28-pipeline-lanes.md` in FinanceTracker so the required checks can be turned on after the release.
**Architecture:** Three standard-library Python scripts with unit tests, a per-project lane config, two workflows (`gates.yml` on `pull_request`, `review-evidence.yml` on `pull_request_target`), and edits to seven skills, the guard lists and AGENTS.md.
**Tech Stack:** Python 3 standard library only (`urllib`, `json`, `re`, `subprocess`, `unittest`), GitHub Actions, GitHub REST API.
**All commands run from:** `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/`
**Branch:** `chore/pipeline-lanes` (not `feature/*`: the guard hook and Gate 13 block gate-definition edits on `feature/*`).

## Decisions made here (from the spec's "Requirements carried to /plan")
- **Globs:** gitignore-style. `**/` matches zero or more directories, `**` matches anything, `*` and `?` do not cross `/`. Patterns match the whole repo-relative path.
- **Citations:** only citations on lines the PR adds are checked, so legacy citations in an edited file cannot block it. A backticked `path:N` or `path:N-M` counts when the path contains `/` or ends in `.md .py .swift .yml .yaml .json .sh .txt`; that rules out `host:port` and URLs. `pragma/...` and `../...` resolve against the repo's parent directory and are skipped with a note when absent.
- **Latest verdict:** the `## Review Agent verdict:` review with the latest `submitted_at`.
- **Concurrency:** each workflow has its own group (`gates-<PR>`, `review-evidence-<PR>`) with `cancel-in-progress`; a cancelled run is always superseded by the newer run of the same workflow.
- **Unit tests run on the PR head, not the base.** A correction to the spec: running the base's tests would test the base's scripts, not the PR's. The tamper protection is about the *gate* scripts, which still run from the base.
- **`none (<reason>)`** satisfies `motivating_incident`.
- **Bootstrap branch kept minimal:** `review-evidence.yml` keeps its warn-and-pass step for a base branch without the scripts; it only fires before rollout and is left as-is rather than removed afterwards.
- The back-merge PR and the `pull_request_target` head-SHA attachment are verified at rollout step 5, as the spec says.

## Tasks
Each script task is two commits: tests first (RED, confirm they fail), then the script (GREEN, confirm they pass).

1. **`scripts/pipeline_lanes.json`**: FinanceTracker lanes, `release_paths`, `carryover_paths` and evidence lists exactly as in the spec's "Lanes" section. No `sync` lane.
2. **`scripts/check_pr_lane.py`** + `scripts/tests/test_check_pr_lane.py`.
   - `glob_match(pattern, path)` and `lane_for(config, base, head, changed, release_changed) -> str`, in the spec's order: release, sync, app, pipeline, docs.
   - CLI `--git <base-ref> --head-branch <name> [--config PATH]` computes `changed` from `git diff --name-only <base-ref>...HEAD` and `release_changed` from `origin/develop...HEAD`, then prints the lane.
   - Invalid config exits 2.
   - Tests: every lane, rank order, a release PR whose own commits touch other paths, the back-merge, sync with and without `sync_paths`, glob edge cases (`**/`, root files, `*` not crossing `/`), invalid config.
3. **`scripts/check_review_evidence.py`** + tests.
   - Pure `evaluate(lane_evidence, head_sha, body, reviews, carryover, changed_between) -> list[(item, ok, detail)]`.
   - A thin `main()` does the GitHub API work: PR, paginated files, reviews, and `compare` for the lane's release check and for carryover. Token from `GH_TOKEN`.
   - Exits 1 on any missing item, and prints the lane and each item.
   - Tests: each item present, missing, at a stale SHA, and at an ancestor with only carryover paths changed (pass) or other paths changed (fail); latest verdict wins; CHANGES REQUESTED after APPROVED fails; `none (reason)`.
4. **`scripts/check_citations.py`** + tests.
   - `--base <ref>`: added lines in changed `.md` files under `docs/superpowers/` and `.claude/skills/`; validates path and line range.
   - Tests: valid, missing file, out-of-range, range, `host:port` ignored, URL ignored, other repo absent (skip), only added lines checked.
5. **`.github/workflows/gates.yml`**: `pull_request` on `develop` and `main`, no `paths:`.
   - Checks out the PR head and the base as today. The lane comes from the base copy of `check_pr_lane.py`, with the bootstrap fallback.
   - For the `release` lane it prints the lane and ends the job successfully. Otherwise it runs `check_tdd_commit_order.py`, `check_gate_integrity.py` and `check_citations.py` from the base, then `python3 -m unittest discover -s scripts/tests` on the head, then the hook self-test.
   - Branch names reach the scripts only through `env`.
6. **`.github/workflows/review-evidence.yml`**: `pull_request_target` (`opened`, `synchronize`, `reopened`, `edited`) on `develop` and `main`.
   - Permissions: `contents: read`, `pull-requests: read`.
   - Checks out the base only, with `persist-credentials: false`, and runs `check_review_evidence.py` with `GH_TOKEN`.
   - If the script is missing on the base, it warns and passes (bootstrap).
7. **`.github/workflows/pr-checks.yml`**: remove the `gates` job, and the guarded-path `paths:` entries with their comment.
8. **Guard lists**: add `scripts/pipeline_lanes.json` and `.github/workflows/*` to `GUARDED_PATH_GLOBS` (`scripts/check_gate_integrity.py:80-90`), `PROTECTED_GLOBS` (`.claude/hooks/guard_protected_paths.py:52-62`) and `_PROTECTED_FRAGMENTS` (`.claude/hooks/guard_protected_paths.py:154-160`). Run `--self-test`.
9. **Skills**:
   - `review`: lane first; `docs`, `release` and `sync` stop. `Reviewed at <sha>` and `Round <1|2|confirm>` lines. Round cap, delta round 2, `--confirm` and design mode in one section. It ends by writing a `Review: <url> at <sha>` line to the PR body.
   - `pr-followup`: `code-review` first, then `/review`; writes the `code-review:` line.
   - `spec` and `plan`: citation rule and a "Requirements carried to /plan" template section.
   - `test`: coverage-gap audit between `/feature` and `/gates`.
   - `gates`: the summary prints the lane.
   - `release`: the back-merge becomes a PR.
10. **`AGENTS.md`**: the pipeline line and the Merge rule point to lanes; stays at or under 50 lines. **`CHANGELOG.md`**: an Unreleased entry.

## Verification
- `python3 -m unittest discover -s scripts/tests -v`: all pass.
- `python3 .claude/hooks/guard_protected_paths.py --self-test`: all PASS.
- `python3 scripts/check_pr_lane.py --git origin/develop --head-branch chore/pipeline-lanes` prints `pipeline`.
- `python3 scripts/check_citations.py --base origin/develop` passes on this branch.
- `/gates`, then open the PR. `gates.yml` runs from the PR head's workflow file, so its check appears on this PR. `review-evidence` does not appear, because its workflow is not on the base yet.
