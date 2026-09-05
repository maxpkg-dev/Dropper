# Release Process

This project currently releases by updating the script version, committing to
`main`, and pushing to `origin/main`. Git tags are not used in the existing
history.

## Version Selection

Before changing `VERSION`, decide the release number intentionally.

- If the user explicitly names a version, use that exact version.
- If the user corrects the version after a release, make a follow-up release
  commit with the corrected version unless they explicitly ask to rewrite
  history.
- Do not mechanically increment the last patch number just because the previous
  release used that pattern.
- Use a patch release, for example `1.1.9` -> `1.1.10`, for small fixes and
  internal improvements.
- Use a minor release, for example `1.1.9` -> `1.2.0`, when behavior changes
  how external systems consume output, API payloads, S3 object paths, file
  naming, or other integration contracts.
- When unsure whether the change is patch or minor, stop and ask the user
  before editing files or committing.

## Steps

1. Check the current state:

```powershell
git -c safe.directory=[...CURDIR...]/GLB-Checker status --short --branch
git -c safe.directory=[...CURDIR...]/GLB-Checker log --oneline --decorate -5
```

2. Update `GLB-Checker.ms`:

- Change `[INFO] VERSION` to the new version.
- Add a changelog block near the top, for example:

```ini
[1.0.7]
+ Added: ...
* Improved: ...
- BugFix: ...
* Changed: ...
- Deleted: ...
```

3. If new runtime/support files were added, make sure they are listed in the
`[FILES]` section of `GLB-Checker.ms`.

4. Run release checks:

```powershell
git -c safe.directory=[...CURDIR...]/GLB-Checker diff --check
rg -n -- "AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|aws_secret_access_key|aws_access_key_id|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID|secretAccessKey|accessKeyId" GLB-Checker.ms *.bat
```

`rg` should return no matches for credential patterns.

5. Commit the release:

```powershell
git -c safe.directory=[...CURDIR...]/GLB-Checker add GLB-Checker.ms <other changed files>
git -c safe.directory=[...CURDIR...]/GLB-Checker commit -m "1.0.7"
```

Use the version number as the commit message, matching the existing history.

6. Push to GitHub:

```powershell
git -c safe.directory=[...CURDIR...]/GLB-Checker push origin main
```

7. Confirm the release:

```powershell
git -c safe.directory=[...CURDIR...]/GLB-Checker status --short --branch
git -c safe.directory=[...CURDIR...]/GLB-Checker log --oneline --decorate -3
```

Expected result:

- `main` is synchronized with `origin/main`.
- The latest commit message is the release version.
- The working tree is clean.

## Notes

- Do not add runtime files such as `settings.ini` to git or `[FILES]`.
- Keep local settings files with credentials out of credential scans and out of
  commits.
- If `git push` prints a `credential-manager-core` warning but still updates
  `origin/main`, treat the push as successful and verify with `git status`.
