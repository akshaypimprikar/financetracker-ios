#!/usr/bin/env python3
"""
PreToolUse guard: blocks Write/Edit/MultiEdit (and, best-effort, Bash writes)
against gate-definition / guardrail files while the current git branch is
feature/*. Same branch semantics as scripts/check_gate_integrity.py, which
only fires on feature/* — a real feature never needs to change what counts as
passing; that belongs on a chore/* or fix/* branch.

Hook contract (Claude Code hooks reference, code.claude.com/docs/en/hooks):
  stdin  JSON with tool_name, tool_input (file_path, or command for Bash), cwd
  exit 2 blocks the tool call and feeds stderr back to Claude
  exit 0 allows; any other exit code is a non-blocking error (tool proceeds)

Limits (deliberate — see the PR that added this file):
  - Bash detection is a best-effort parse of redirects, tee, sed/perl -i,
    cp/mv/rm; `python -c`, heredoc-into-interpreter, git plumbing and the
    like are not detected.
  - This file is itself protected only on feature/* — it is editable on any
    other branch, and a chore/* edit is not blocked at all.
  - Fails open: bad stdin, no git repo, or a detached HEAD allow the call.

Usage: guard_protected_paths.py            (reads hook JSON on stdin)
       guard_protected_paths.py --self-test
"""
import fnmatch
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile

# Repo-relative globs. fnmatch's `*` also crosses `/`, so nested paths match.
PROTECTED_GLOBS = (
    ".claude/commands/*.md",
    "scripts/check_*.py",
    "CLAUDE.md",
    ".claude/context/invariants.md",
    ".claude/settings.json",
    ".claude/hooks/*",
    "FinanceTrackerTests/ImportHashGoldenTests.swift",
)
GUARDED_BRANCH = re.compile(r"^feature/")
FILE_TOOLS = ("Write", "Edit", "MultiEdit")
WRAPPER_WORDS = ("sudo", "env", "command", "time", "nohup", "exec")


def git(cwd, *args):
    try:
        out = subprocess.run(
            ("git", "-C", cwd) + args, capture_output=True, text=True, check=True
        ).stdout
        return out.strip()
    except (subprocess.CalledProcessError, OSError):
        return None


def nearest_existing_dir(path):
    d = os.path.dirname(path)
    while d and not os.path.isdir(d):
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent
    return d if os.path.isdir(d) else None


def protected_relpath(abs_path):
    """(repo_root, relpath) if abs_path is a protected file inside a git repo, else None."""
    d = nearest_existing_dir(abs_path)
    if not d:
        return None
    root = git(d, "rev-parse", "--show-toplevel")
    if not root:
        return None
    rel = os.path.relpath(os.path.realpath(abs_path), os.path.realpath(root))
    # macOS volumes are case-insensitive by default: claude.md is CLAUDE.md there.
    for glob in PROTECTED_GLOBS:
        if fnmatch.fnmatchcase(rel.lower(), glob.lower()):
            return root, rel
    return None


def resolve(path, cwd):
    return os.path.normpath(os.path.join(cwd, os.path.expanduser(path)))


def split_words(segment):
    # punctuation_chars splits `x>f` into x, >, f while keeping quoted text intact.
    try:
        lex = shlex.shlex(segment, posix=True, punctuation_chars=True)
        lex.whitespace_split = False
        return list(lex)
    except ValueError:
        return segment.split()


def bash_write_targets(command):
    """Best-effort list of paths a shell command writes to."""
    targets = []
    for segment in re.split(r"\n|;|&&|\|\||\|", command):
        words = split_words(segment)
        for i, w in enumerate(words):
            if w in (">", ">>", "&>", "&>>", ">|") and i + 1 < len(words):  # `>&` (fd dup) is not a file
                targets.append(words[i + 1])
        cmd_idx = next(
            (i for i, w in enumerate(words) if "=" not in w and w not in WRAPPER_WORDS), None
        )
        if cmd_idx is None:
            continue
        cmd = os.path.basename(words[cmd_idx])
        args = [w for w in words[cmd_idx + 1 :] if not w.startswith("-")]
        flags = [w for w in words[cmd_idx + 1 :] if w.startswith("-")]
        if cmd == "tee":
            targets += args
        elif cmd in ("sed", "gsed", "perl") and any(
            f.startswith("--in-place") or re.match(r"^-[A-Za-z]*i", f) for f in flags
        ):
            targets += args
        elif cmd in ("cp", "install") and args:
            targets.append(args[-1])
        elif cmd == "mv":
            targets += args
        elif cmd == "rm":
            targets += args
    return targets


def evaluate(payload):
    """Return a block message, or None to allow."""
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    cwd = payload.get("cwd") or os.getcwd()

    if tool in FILE_TOOLS:
        candidates = [tool_input.get("file_path")]
    elif tool == "Bash":
        candidates = bash_write_targets(tool_input.get("command") or "")
    else:
        return None

    for raw in candidates:
        if not raw:
            continue
        hit = protected_relpath(resolve(raw, cwd))
        if not hit:
            continue
        root, rel = hit
        branch = git(root, "branch", "--show-current")
        if not branch or not GUARDED_BRANCH.match(branch):
            continue  # detached HEAD or a non-feature branch: allow
        return (
            f"BLOCKED: `{rel}` is a gate-definition/guardrail file and the current branch is "
            f"`{branch}` (feature/*). A feature branch must not change what counts as passing. "
            "Remedy: make this change on a chore/* or fix/* branch in its own PR, then rebase "
            "this feature branch onto it. If the edit really belongs to this feature, stop and "
            "ask the user instead of editing around the guard."
        )
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        message = evaluate(payload)
    except Exception:  # fail open: a broken guard must not wedge every tool call
        return 0
    if message:
        print(message, file=sys.stderr)
        return 2
    return 0


def self_test():
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp = os.path.realpath(tmp)
        repos = {}
        for name, branch in (("feat", "feature/demo"), ("chore", "chore/demo"), ("detached", None)):
            d = os.path.join(tmp, name)
            os.makedirs(os.path.join(d, ".claude", "commands"))
            os.makedirs(os.path.join(d, "scripts"))
            os.makedirs(os.path.join(d, "FinanceTracker"))
            subprocess.run(["git", "-C", d, "init", "-q"], check=True)
            for f in (".claude/commands/gates.md", "scripts/check_x.py", "CLAUDE.md", "FinanceTracker/A.swift"):
                open(os.path.join(d, f), "w").close()
            subprocess.run(["git", "-C", d, "add", "-A"], check=True)
            subprocess.run(
                ["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "i"],
                check=True,
            )
            if branch:
                subprocess.run(["git", "-C", d, "checkout", "-q", "-B", branch], check=True)
            else:
                subprocess.run(["git", "-C", d, "checkout", "-q", "--detach"], check=True)
            repos[name] = d

        def write(tool, repo, rel):
            return {"tool_name": tool, "cwd": repos[repo], "tool_input": {"file_path": os.path.join(repos[repo], rel)}}

        def bash(repo, cmd):
            return {"tool_name": "Bash", "cwd": repos[repo], "tool_input": {"command": cmd}}

        cases = [
            # (label, payload, expect_block)
            ("feature: Write gates.md", write("Write", "feat", ".claude/commands/gates.md"), True),
            ("feature: Edit gates.md", write("Edit", "feat", ".claude/commands/gates.md"), True),
            ("feature: MultiEdit CLAUDE.md", write("MultiEdit", "feat", "CLAUDE.md"), True),
            ("feature: Write CLAUDE.md, wrong case", write("Write", "feat", "claude.md"), True),
            ("feature: Write scripts/check_x.py", write("Write", "feat", "scripts/check_x.py"), True),
            ("feature: Write .claude/settings.json (new)", write("Write", "feat", ".claude/settings.json"), True),
            ("feature: Write .claude/hooks/new.py (new dir)", write("Write", "feat", ".claude/hooks/new.py"), True),
            ("feature: Write invariants.md (new dirs)", write("Write", "feat", ".claude/context/invariants.md"), True),
            ("feature: Write ImportHashGoldenTests (new dirs)", write("Write", "feat", "FinanceTrackerTests/ImportHashGoldenTests.swift"), True),
            ("feature: Write ordinary .swift", write("Write", "feat", "FinanceTracker/A.swift"), False),
            ("feature: Read tool is ignored", write("Read", "feat", "CLAUDE.md"), False),
            ("chore: Write gates.md", write("Write", "chore", ".claude/commands/gates.md"), False),
            ("chore: Edit CLAUDE.md", write("Edit", "chore", "CLAUDE.md"), False),
            ("detached HEAD: Write gates.md (fail open)", write("Write", "detached", ".claude/commands/gates.md"), False),
            ("feature: Bash redirect >", bash("feat", "echo x > .claude/commands/gates.md"), True),
            ("feature: Bash append >>", bash("feat", "echo x >> CLAUDE.md"), True),
            ("feature: Bash cat > file <<EOF", bash("feat", "cat > CLAUDE.md <<'EOF'\nhello\nEOF"), True),
            ("feature: Bash tee", bash("feat", "echo x | tee -a scripts/check_x.py"), True),
            ("feature: Bash sed -i", bash("feat", "sed -i '' 's/a/b/' .claude/commands/gates.md"), True),
            ("feature: Bash chained after &&", bash("feat", "ls && echo x>CLAUDE.md"), True),
            ("feature: Bash mv onto protected", bash("feat", "mv /tmp/x scripts/check_x.py"), True),
            ("feature: Bash rm protected", bash("feat", "rm CLAUDE.md"), True),
            ("feature: Bash read-only cat", bash("feat", "cat CLAUDE.md"), False),
            ("feature: Bash protected path as SOURCE of redirect", bash("feat", "cat CLAUDE.md > /tmp/out.txt"), False),
            ("feature: Bash 2>&1 is not a redirect target", bash("feat", "ls CLAUDE.md 2>&1"), False),
            ("feature: Bash sed without -i", bash("feat", "sed 's/a/b/' CLAUDE.md"), False),
            ("feature: Bash redirect to ordinary file", bash("feat", "echo x > FinanceTracker/A.swift"), False),
            ("chore: Bash redirect", bash("chore", "echo x > CLAUDE.md"), False),
        ]
        for label, payload, expect_block in cases:
            proc = subprocess.run(
                [sys.executable, os.path.abspath(__file__)],
                input=json.dumps(payload), capture_output=True, text=True,
            )
            blocked = proc.returncode == 2
            ok = blocked == expect_block and (not blocked or "BLOCKED" in proc.stderr)
            failures += 0 if ok else 1
            print(f"{'PASS' if ok else 'FAIL'}  exit={proc.returncode}  {label}")

        for label, stdin in (("malformed JSON fails open", "not json"), ("empty stdin fails open", "")):
            proc = subprocess.run(
                [sys.executable, os.path.abspath(__file__)], input=stdin, capture_output=True, text=True
            )
            ok = proc.returncode == 0
            failures += 0 if ok else 1
            print(f"{'PASS' if ok else 'FAIL'}  exit={proc.returncode}  {label}")

    print(f"\n{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(self_test() if "--self-test" in sys.argv[1:] else main())
