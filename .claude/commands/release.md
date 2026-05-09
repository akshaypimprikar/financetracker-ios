# Release Agent

You are the **Release Agent** for FinanceTracker. Your job is to prepare and tag a release.

## Trigger
Invoked with a version number (e.g. `/release 1.0.0`).

## Pre-flight checks (must all pass before continuing)

- [ ] All tests pass on `main`:
  ```bash
  xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"
  ```
- [ ] No TODO/FIXME in any file added since last release:
  ```bash
  git diff <last-tag>..main -- '*.swift' | grep -E "TODO|FIXME"
  ```
- [ ] No force-unwraps in production code added since last release:
  ```bash
  git diff <last-tag>..main -- 'FinanceTracker/*.swift' | grep -E '^\+.*[^!]![^=]'
  ```

If any check fails, stop and report what must be fixed.

## Process

All commands run from git root `/Users/akshaypimprikar/Desktop/FinanceTracker/`.

### 1. Create the release branch
```bash
git checkout main && git pull
git checkout -b release/<version>
```

### 2. Version bump
Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `FinanceTracker.xcodeproj/project.pbxproj`:
- `MARKETING_VERSION = <version>;`
- `CURRENT_PROJECT_VERSION = <increment by 1>;`

### 3. Update CHANGELOG.md
Add a new section at the top:

```markdown
## [<version>] — YYYY-MM-DD

### Added
- <feature 1>

### Fixed
- <bug 1>
```

Use `git log <last-tag>..HEAD --oneline` to find what changed.

### 4. Commit and tag
```bash
git add FinanceTracker.xcodeproj/project.pbxproj CHANGELOG.md
git commit -m "chore: bump version to <version>"
git tag -a v<version> -m "Release <version>"
```

### 5. Merge to main
```bash
git checkout main
git merge release/<version> --no-ff
git push origin main
git push origin v<version>
git branch -d release/<version>
```

### 6. Create GitHub release
```bash
gh release create v<version> \
  --title "v<version>" \
  --notes "$(git log <last-tag>..v<version> --oneline)"
```

## Done when
`main` tagged, GitHub release created, `CHANGELOG.md` committed.
