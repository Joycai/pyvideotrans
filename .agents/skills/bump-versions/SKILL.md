---
name: bump-versions
description: Bump a Flutter desktop app's version everywhere it is written — pubspec.yaml plus every hard-coded copy in build and packaging scripts (macOS dmg script, Windows Runner.rc and Inno Setup .iss, Linux .desktop / snapcraft / metainfo) and project config (Info.plist, xcconfig, CHANGELOG). Use this whenever the user wants to change, bump, raise, set, or release a version number ("升版本", "改版本号", "发 1.2.0", "bump patch", "prepare the release", "版本号统一改一下"), even if they only mention pubspec or one platform — a version that is updated in one place and forgotten in another is exactly the bug this skill prevents.
---

# Bump versions

A Flutter app's version has one source of truth, `pubspec.yaml` (`version: X.Y.Z+B`), and
Flutter pushes it into the platform builds at build time. The trouble is that projects also
keep *copies* of the number: fallback `#define`s in `windows/runner/Runner.rc`, a literal
`AppVersion` in an Inno Setup script, `VERSION="…"` in a dmg script, `version:` in
`snapcraft.yaml`, a CHANGELOG heading. Nobody remembers all of them, so releases ship with
a 1.0.0 file-version on Windows and a 1.2.0 dmg on macOS. This skill exists to update every
copy in one pass and to prove nothing was missed.

## Workflow

1. **Pin down the target.** The user gives either an explicit version (`1.2.0`) or a bump
   kind (`major` / `minor` / `patch`). If they said only "bump the version" with no kind,
   ask which — a patch and a minor release mean different things to their users, and
   guessing wrong is worse than one question. Build number (`+B`) increments by default;
   keep it if the user says so (`--build keep`), or set it explicitly (`--build 42`).

2. **Dry-run the script first**, from anywhere inside the repo:

   ```bash
   python3 <skill-dir>/scripts/bump_version.py <version|major|minor|patch> --dry-run [--build keep|reset|N] [--root app]
   ```

   It finds the app's pubspec, computes the new version, and lists every line it would
   change (pubspec plus hard-coded copies in the usual files), then a "still mention the
   old version" list of other files for you to judge. Read that list: a CHANGELOG entry for
   the old release is history and stays; a `const appVersion = '…'` in `lib/`, a README
   download link or a Dockerfile `ARG` is a copy and should be updated by hand. The script
   never rewrites CHANGELOG-style history files, so a hit there is expected.

3. **Apply** by re-running without `--dry-run`. Then handle what the script deliberately
   leaves to you:
   - **CHANGELOG / release notes**: if the repo keeps one, add or rename the heading for the
     new version (an `## [Unreleased]` section becomes `## [X.Y.Z] - YYYY-MM-DD`). Do not
     invent release notes; move what is already there.
   - **Leftovers** the dry-run flagged that are real copies.
   - **`.desktop` files**: the `Version=1.0` key is the *Desktop Entry spec* version, not
     the app's. Leave it. (The script never touches it; this note is so you don't "fix" it.)

4. **Verify** — this is the point of the skill, so don't skip it:

   ```bash
   git diff --stat
   grep -rn "<old version>" --exclude-dir=build --exclude-dir=.dart_tool --exclude-dir=Pods --exclude-dir=.git . | grep -v "\.lock"
   ```

   Anything the grep still finds is either history (fine) or a miss (fix it). If the
   project's packaging scripts *derive* the version (a `sed` on pubspec, Inno Setup's
   `GetVersionNumbersString` on the exe, `$(FLUTTER_BUILD_NAME)` in Info.plist) they need no
   edit, and it is worth saying so in the final message so the user knows those platforms
   are covered without a diff. `references/version-sources.md` explains how each platform
   gets its number and which files are derivations versus copies.

5. **Commit / tag only when asked.** Suggest `chore: bump version to X.Y.Z` and a `vX.Y.Z`
   tag; run neither unless the user asked for a commit or a release.

## Final message

Lead with the version change (`1.0.0+1 → 1.1.0+2`). Then a short list: files changed, and
per platform where the version comes from (edited copy vs. derived from pubspec). Close
with anything left for the user — an untouched CHANGELOG, a leftover you weren't sure
about, the tag/commit you did not create.

## When the project isn't Flutter

The script needs a Flutter `pubspec.yaml`. For anything else (Tauri, Electron, a plain
CMake app) follow the same shape by hand: find the source of truth (`package.json`,
`tauri.conf.json`, `Cargo.toml`, `CMakeLists.txt` `project(VERSION …)`), change it, then
grep the repo for the old number and update every copy that is not history.
