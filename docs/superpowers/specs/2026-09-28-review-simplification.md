# /review Simplification — Design Spec

**Date:** 2026-09-28
**Status:** Superseded by `2026-09-28-pipeline-lanes.md`

## Overview
`/review` grew from about 160 lines to 298 lines across PRs #126, #127 and #130: 57 commits, and PR #130's
review rounds on the skill itself added 47 `rejections.md` entries. This spec cuts `/review` down to the five things no other stage
does: pin the PR's SHA against the gate summary, run the isolated judgment subagent, run the design and
code-quality checklists, keep the violation log, and give the verdict. Deterministic work moves into scripts and CI. The
severity and logging rules are stated once, in a shorter form. Pipeline-text violations get their own
log, so app reviews stop reading them. Nothing in the app target changes.

The simplified skill is also the version that gets ported to pragma afterwards (see "Pragma port").

## What /review does that nothing else does (kept)
| Job | Why it stays in /review |
|---|---|
| SHA pin: the PR head equals the `Gates run at <sha>` line | CI cannot read the gate summary's claim |
| Isolated judgment subagent | `code-review:code-review` sees the PR summary, commits and blame, so it is not isolated |
| Design-system and domain checklists | `code-review` drops general quality issues that `CLAUDE.md` does not name, and `AGENTS.md` has no Theme or magic-number rules |
| Logging review findings to `rejections.md` | `/feature`, `/bugfix` and `/parallel-review` read it. /review is the only stage that logs its own findings and the blocking fixes a PR body documents; otherwise entries are added only when a code-review round or a person appends one by hand. (`incidents.md` is written by `/bugfix` and is unchanged here.) |
| APPROVED / CHANGES REQUESTED verdict | `code-review` gives no verdict, only issues scored 80 or higher |

## Decisions & Constraints
| Decision | Choice | Rationale |
|---|---|---|
| Overall approach | Keep /review, cut what it repeats (option 1 of 3) | Retiring it loses isolation, repeat escalation and the verdict. Keeping it as is keeps 298 lines. |
| Gate-script re-runs in /review | Remove, and make the `gates` CI job run on every PR and block when missing | The CI `gates` job already runs both scripts from the base branch. Today it is skipped for PRs outside `pr-checks.yml`'s `paths:` filter (docs, `.claude/context/`, `.claude/commands/`, workflows), and a missing `gates` check is only a note in /review (`review/SKILL.md:88-90`, `:230`). So the job moves to its own workflow with no `paths:` filter, and a missing, pending-past-timeout or failed `gates` check is CHANGES REQUESTED. Without both changes, removing the re-runs would leave those PRs with no gate checks. |
| Grep-only gates (3, 4, 5, 8, and the Gate 9 greps scoped to the branch diff) | Move to a new base-branch script that the CI `gates` job runs | Deterministic checks belong in CI, where the other two scripts already run. /review then checks only the SHA and that CI passed, plus the one hand check below. |
| Accepted grep-gate exceptions (for example `percentUsed`) | A guarded `scripts/gate_exceptions.txt`, one `path:pattern  # reason` line per exception | CI cannot read the gate summary. A guarded file keeps every exception visible in the diff and out of reach of the PR it would waive. Rejected: inline `// gate-allow: <rule>` comments, which let a PR waive a check in its own diff. |
| UI-selector check (Gate 9) | Stays out of the script: `/gates` keeps it as a hand cross-check, and /review keeps re-running that one grep | It scans all of `FinanceTrackerUITests/`, not the diff, and 9 of the 25 current selectors (`Cancel`, `Groceries`, `No Accounts Yet` and others) match by label text rather than `accessibilityIdentifier`, so a mechanical pass/fail would fail on every run |
| Subagent input prep (STOP / EMPTY / LOG-ONLY block) and the append-only log check | Move to `scripts/prep_review.py`, run from the base branch | About 31 lines of shell in the skill (`review/SKILL.md:100-118` and `159-170`) become a tested script. Running it from base means a PR cannot edit its own reviewer's inputs. |
| TODO/FIXME checklist item | Keep | Gate 3 greps only `*.swift` and has no "unless tracked in an issue" allowance, so it does not cover non-Swift code such as this spec's own scripts |
| Severity and blocking rules | State them once in a "Severity and blocking" section, and point to it | They are currently stated in four places (lines 139-142, 178-183, 230, 235) |
| Regressions within a PR (current lines 184-194) | Same behavior, stated in three sentences: a finding that matches a blocking fix made earlier in this PR is a regression and is rated HIGH. An entry this PR added to `rejections.md` counts as blocking; a PR-body fix or an `incidents.md` entry this PR added is rated on the severity scale from what it describes. A returning non-blocking item, or one never fixed, keeps its own severity. The session makes this comparison, not the isolated subagent, which sees only base-branch log copies and gets the PR number only to name it in findings. | The current paragraph mixes these rules with the severity scale and the logging rules. Changing the behavior (for example, raising every returning item to HIGH) would turn advisory MEDIUMs and non-blocking `incidents.md` items into blockers, so this spec only restates it. |
| Logging (current lines 233-260) | One list instead of two cases: log each blocking item in this verdict, and each blocking fix the PR body documents (from a `code-review` round, an earlier `/review` round or manual verification, rated as the regression rule rates PR-body fixes). Skip anything already logged for this PR. A regression gets a new entry that names what it repeats. | Same behavior as today's case 1 and case 2, in one place. |
| Pipeline-text violations | Split them into `.claude/context/pipeline-rejections.md`. For the one-time move of existing entries, an entry goes there when the first path in its **File:** is under `.claude/` (except `.claude/context/`), `scripts/`, `.github/`, or is `AGENTS.md`/`CLAUDE.md`; later paths in the same field do not count. For new entries, whoever logs a finding picks the file by what the violation is about: pipeline text, including a spec or plan for pipeline work under `docs/superpowers/`, goes to `pipeline-rejections.md`. | 57 of the 65 current entries move (4 are app code, 2 are `CHANGELOG.md` and 2 name `.claude/context/` first, and those 8 stay). App reviews should repeat-check against app violations only. |
| Who reads pipeline-rejections.md | The /review and `/parallel-review` subagents, and `/feature` and `/bugfix`, when the work touches a pipeline path or is a spec or plan for pipeline work under `docs/superpowers/` (for this purpose, `.claude/context/` does not count, so `/spec`'s `decisions.md` append alone does not trigger it); `/pipeline-review` always | Keeps repeat detection for skill PRs without feeding pipeline history to app reviews |
| Size target | `review/SKILL.md` at or under 180 lines | A measurable exit criterion for this spec |

## Architecture
Pipeline only. No app layers are touched.

- `scripts/check_grep_gates.py` (new, guarded by the `scripts/check_*` glob): takes `BASE` and the head
  branch name, runs Gates 3, 4, 5, 8 and the diff-scoped Gate 9 greps (every one except the UI-selector listing) against `BASE...HEAD`, applies
  `scripts/gate_exceptions.txt` as it is on `BASE` (so a PR cannot waive its own hit; a new exception
  lands first on its own `chore/*` PR; a file missing on `BASE` means no exceptions), and exits non-zero on any unexcepted hit. It prints each hit as
  `gate:rule:path:line`.
- `scripts/prep_review.py` (new): takes the PR's base ref. It writes `pr.diff` (without the two logs, and
  without `pipeline-rejections.md`) and the base-branch copies of all three logs to a temp dir, and prints
  `INPUTS <dir>`, `EMPTY`, `LOG-ONLY` or `STOP <reason>`. It also runs the append-only check on all three
  logs against the merge-base and prints `EDITED <path>` along with the diff. The isolated reviewer, and
  `/parallel-review`, rate repeats only against those base-branch copies and never open the working-tree
  copy of any of the three logs, as they already do for `rejections.md`. /review's clean-tree check in the
  SHA pin (`review/SKILL.md:44`) exempts `pipeline-rejections.md` as well as `rejections.md`.
- `.github/workflows/gates.yml` (new): the `gates` job moves here from `pr-checks.yml`, unchanged apart
  from the points below, with the same `pull_request` trigger and branches but no `paths:` filter, so
  it runs on every PR. Its existing `if:` (skip `release/*` PRs to `main`) stays; those PRs are exempt from
  /review anyway. `pr-checks.yml` keeps its `paths:` filter for the build and test jobs.
- The `gates` job adds `check_grep_gates.py` to its trusted-script loop
  and passes it `"$HEAD_REF"` as well, as the loop already does for `check_gate_integrity.py` (CI checks out a
  detached HEAD, so Gate 4 needs the branch name as an argument),
  and adds a step that runs `python3 -m unittest discover scripts/tests`. The job's comment (lines 80-82)
  still says the UI-selector cross-check "stays local to /gates", which stays true; its list of what CI runs
  is updated to include the grep gates. The comment in `pr-checks.yml`'s `paths:` filter about keeping the
  guarded paths listed there is removed, since the gates job no longer depends on that filter.
- `.claude/skills/gates/SKILL.md`: Gates 3, 4, 5, 8 and 9 (except the UI-selector listing) call the script instead of inline greps, so
  the local and CI checks cannot drift apart. The gate summary stops listing accepted exceptions, because
  the exceptions file now holds them.
- `.claude/skills/review/SKILL.md`: rewritten per the decisions above.
- `.claude/skills/pipeline-review/SKILL.md`: reads `pipeline-rejections.md`.
- `.claude/skills/parallel-review/SKILL.md`: gets the same regression and severity wording by pointing to
  /review's section, and reads `pipeline-rejections.md` under the same path condition.
- `.claude/skills/feature/SKILL.md` and `.claude/skills/bugfix/SKILL.md`: also read `pipeline-rejections.md`
  when the work touches a pipeline path, so pipeline work keeps its history after the split.
- `.claude/skills/gates/SKILL.md:134` and `:395` say /review re-runs the grep gates; both are updated to say
  CI runs them.
- `.claude/hooks/guard_protected_paths.py` and `scripts/check_gate_integrity.py`: add
  `scripts/gate_exceptions.txt` and `scripts/prep_review.py` to both glob lists. They must stay in step,
  which CI's self-test already checks. The hook's cheap prefilter, `_PROTECTED_FRAGMENTS`
  (`guard_protected_paths.py:154-159`), also gets `gate_exceptions.txt` and `prep_review.py`; without them
  the hook skips those writes before it reaches the glob match, and the self-test does not compare that
  list.
- `.claude/context/rejections.md`: entries whose first **File:** path is a pipeline path move to
  `pipeline-rejections.md`, verbatim and in their original order. The new file starts with the same
  append-only header comment as `rejections.md`, plus one line recording that its first entries were
  moved from `rejections.md` on that PR. `rejections.md` itself is left untouched apart from the removals,
  because the move check requires that it gains no line. This one-time move is the only
  non-append edit to either log, so it lands second, on its own `chore/*` PR that changes nothing else,
  after the implementation PR has put `prep_review.py --verify-move` and the new /review rule on
  `develop`. The implementation PR itself runs its own `prep_review.py` from the PR copy, reported as
  `NOT VERIFIED: scripts/prep_review.py not on <base>`, the convention /review already uses for a script
  a PR introduces.
  The append-only check prints `EDITED` on that PR. For that PR only, /review accepts the `EDITED`
  result when a move check passes, and states the exception and the check's output in its verdict. The
  move check compares against the merge-base (not the base tip, which may have new entries), treats any
  failed command as a failure rather than empty output, and passes only when `rejections.md` gained no
  line and every line it lost appears in `pipeline-rejections.md`, blank and `-`/`+`-prefixed lines
  included. `/plan` writes it as a `prep_review.py --verify-move` mode with its own tests, rather than
  a shell block in the skill.

## Data Models / Domain Services / Navigation / Design
None. This spec touches no Swift code, views or tokens.

## Requirements carried to /plan
Found in review and left to `/plan` rather than further spec rounds:
- The move check also verifies that only entries matching the move rule moved, and in their original order.
- `gates.yml` uses its own `concurrency` group, not `pr-checks.yml`'s `pr-<N>` group (`pr-checks.yml:32-34`),
  or the two workflows cancel each other.
- Line references in this spec are as of `develop` at 2026-09-28 and may shift by a line or two.

## Future Extension Points
- **Pragma port:** after this merges, `/sync-workflow` carries the simplified `/review`, both scripts, the
  CI step and the log split to pragma. It is its own piece of work, not a find-and-replace. Pragma's gate
  set differs: its Gate 8 is abstraction bloat, it has no CSV-concurrency gate, architecture is Gate 10,
  and RED-before-GREEN and gate integrity are 9 and 11. So `check_grep_gates.py` keeps its rule list,
  gate numbers, layer paths and money stems in one config block at the top, and each project defines its
  own. Porting still needs a pragma PR that writes that block from pragma's `gates/SKILL.md` and adds
  the `<AppName>` placeholders.
- **An AST-based money check** (SwiftSyntax) stays out of scope, as `gates/SKILL.md` already states.

## Testing Strategy
- `scripts/tests/test_check_grep_gates.py`: one passing and one failing fixture per rule, built with a
  temp git repo and two commits. It also checks that an exceptions-file entry suppresses exactly its own
  hit, and that a hit on a detached HEAD still reads the branch from the argument.
- `scripts/tests/test_prep_review.py`: covers `--verify-move` (a clean move, an added line, a dropped line, a failed git command), EMPTY, LOG-ONLY, a normal diff with the logs stripped, a
  missing base (STOP), an append-only pass, an edit to an earlier entry (EDITED), and a log missing on the
  base.
- The tests run in the CI `gates` job.
- **Acceptance:** `/review` run on this spec's implementation PR and on the next app PR both produce a
  verdict without hitting the review-loop stopping rule (2 rounds). `review/SKILL.md` is 180 lines or
  fewer. `check_grep_gates.py` fails on a throwaway branch off `develop` that commits one violation per
  rule, and passes when re-run over the range of a real merged app PR (`<merge>^1...<merge>`) that
  already passed `/gates` and whose diff has no hit that needs an exception. A docs-only PR opened after
  the change shows a `gates` check.
