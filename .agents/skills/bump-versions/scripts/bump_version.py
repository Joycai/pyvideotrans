#!/usr/bin/env python3
"""Bump the app version everywhere it is written down in a Flutter desktop project.

pubspec.yaml is the source of truth (`version: X.Y.Z+B`). Flutter feeds that into
FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER, which macOS / iOS Info.plist and the
Windows resource file normally read at build time. But projects also carry
*hard-coded* copies of the version — fallback defines in Runner.rc, literal
AppVersion in an Inno Setup script, VERSION="…" in a shell script, snapcraft.yaml,
a .desktop file, a changelog heading — and those silently go stale. This script
updates pubspec and then rewrites every hard-coded copy of the OLD version it can
find in the usual places, listing each change so the caller can review it.

Usage:
  bump_version.py 1.2.0                # set an explicit version
  bump_version.py patch|minor|major    # bump one component
  bump_version.py 1.2.0 --build keep   # build number: increment (default), keep, reset, or a number
  bump_version.py patch --dry-run      # show what would change, touch nothing
  bump_version.py patch --root path/to/flutter/app
  bump_version.py --show               # just print the current version

Exit codes: 0 ok, 1 bad arguments / pubspec not found, 2 pubspec has no parsable version.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$")

# Files that commonly carry a hard-coded copy of the version, relative to the
# Flutter app root. Globs are allowed. Lock files and generated code are
# deliberately absent: they are regenerated, not edited.
CANDIDATE_GLOBS = [
    "windows/runner/Runner.rc",
    "windows/runner/*.rc",
    "macos/Runner/Info.plist",
    "macos/Runner/Configs/*.xcconfig",
    "ios/Runner/Info.plist",
    "linux/*.desktop",
    "linux/**/*.desktop",
    "packaging/**/*",
    "installer/**/*",
    "scripts/**/*",
    "snap/snapcraft.yaml",
    "flatpak/*.json",
    "flatpak/*.yml",
    "flatpak/*.yaml",
    "*.appdata.xml",
    "*.metainfo.xml",
    "linux/**/*.metainfo.xml",
    "linux/**/*.appdata.xml",
    "debian/changelog",
    "README.md",
]
# History files are never rewritten: an old release heading must keep its number.
# They still show up in the leftovers list so the caller adds a *new* entry.
HISTORY_FILES = {"CHANGELOG.md", "CHANGES.md", "HISTORY.md", "debian/changelog"}
SKIP_DIRS = {"build", ".dart_tool", ".git", "Pods", "node_modules", "ephemeral", ".plugin_symlinks"}
SKIP_SUFFIXES = {".png", ".jpg", ".jpeg", ".ico", ".icns", ".gif", ".pdf", ".zip", ".dmg", ".exe", ".lock"}


def find_pubspec(start: Path) -> Path | None:
    """The pubspec of the *app*: look in start, then upward, then one level down."""
    for directory in [start, *start.parents]:
        candidate = directory / "pubspec.yaml"
        if candidate.is_file() and "flutter" in candidate.read_text(encoding="utf-8"):
            return candidate
    for child in sorted(start.iterdir()):
        if child.is_dir() and child.name not in SKIP_DIRS:
            candidate = child / "pubspec.yaml"
            if candidate.is_file() and "flutter" in candidate.read_text(encoding="utf-8"):
                return candidate
    return None


def read_version(pubspec: Path) -> tuple[str, str | None, str]:
    """Return (name, build, raw_line) — name is X.Y.Z, build the +B part or None."""
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^version:\s*([^\s#]+)", line)
        if match:
            raw = match.group(1).strip("'\"")
            parts = SEMVER.match(raw)
            if not parts:
                sys.exit(f"pubspec version '{raw}' is not X.Y.Z or X.Y.Z+B")
            return ".".join(parts.group(1, 2, 3)), parts.group(4), line
    print("pubspec.yaml has no `version:` line", file=sys.stderr)
    sys.exit(2)


def next_version(current: str, spec: str) -> str:
    major, minor, patch = (int(p) for p in current.split("."))
    if spec == "major":
        return f"{major + 1}.0.0"
    if spec == "minor":
        return f"{major}.{minor + 1}.0"
    if spec == "patch":
        return f"{major}.{minor}.{patch + 1}"
    parts = SEMVER.match(spec)
    if not parts or parts.group(4):
        sys.exit(f"'{spec}' is neither major/minor/patch nor an X.Y.Z version (build number goes in --build)")
    return spec


def next_build(current: str | None, policy: str) -> str | None:
    if policy == "keep":
        return current
    if policy == "reset":
        return "1" if current is not None else None
    if policy == "increment":
        return str(int(current) + 1) if current is not None else None
    if policy.isdigit():
        return policy
    sys.exit(f"--build must be increment, keep, reset or a number, not '{policy}'")


def candidate_files(root: Path) -> list[Path]:
    seen: dict[Path, None] = {}
    for pattern in CANDIDATE_GLOBS:
        for path in root.glob(pattern):
            if not path.is_file() or path.suffix.lower() in SKIP_SUFFIXES:
                continue
            rel = path.relative_to(root)
            if any(part in SKIP_DIRS for part in rel.parts) or str(rel) in HISTORY_FILES:
                continue
            seen[path] = None
    return list(seen)


def rewrite(path: Path, old_name: str, new_name: str, old_build: str | None, new_build: str | None, apply: bool) -> list[dict]:
    """Replace hard-coded copies of the old version in one file. Returns the edits made."""
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []
    dotted = re.compile(rf"(?<![\d.]){re.escape(old_name)}(?![\d.])")
    old_full = f"{old_name}+{old_build}" if old_build else None
    new_full = f"{new_name}+{new_build}" if new_build else new_name
    # Windows .rc fallback: `1,0,0,0` — the fourth number is whatever the template
    # left there, so match any fourth component and write the new build number.
    comma_new = ",".join(new_name.split(".")) + "," + (new_build or "0")
    comma = re.compile(rf"(?<![\d,]){re.escape(','.join(old_name.split('.')))},\d+(?![\d,])")

    edits: list[dict] = []
    out_lines = []
    lines = text.splitlines(keepends=True)
    for number, line in enumerate(lines, start=1):
        new_line = line
        # Info.plist: CFBundleVersion holds the *build number* on its own line after
        # its key; a literal there is a copy of pubspec's +B and must follow it.
        if (path.suffix == ".plist" and old_build and new_build and number >= 2
                and "<key>CFBundleVersion</key>" in lines[number - 2]
                and f"<string>{old_build}</string>" in line):
            new_line = line.replace(f"<string>{old_build}</string>", f"<string>{new_build}</string>")
        # Lines that *derive* the version from pubspec or a build define are not
        # copies; leave them alone even if they happen to mention the number.
        derives = "pubspec" in line or "FLUTTER_VERSION" in line or "FLUTTER_BUILD" in line
        if not derives:
            if old_full and old_full in new_line:
                new_line = new_line.replace(old_full, new_full)
            new_line = dotted.sub(new_name, new_line)
            new_line = comma.sub(comma_new, new_line)
        if new_line != line:
            edits.append({"file": str(path), "line": number, "before": line.rstrip("\n"), "after": new_line.rstrip("\n")})
        out_lines.append(new_line)
    if edits and apply:
        path.write_text("".join(out_lines), encoding="utf-8")
    return edits


def leftovers(root: Path, old_name: str, touched: set[Path]) -> list[str]:
    """Other files that still mention the old version, for the caller to judge."""
    hits = []
    pattern = re.compile(rf"(?<![\d.]){re.escape(old_name)}(?![\d.])")
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            if path in touched or path.suffix.lower() in SKIP_SUFFIXES or name.endswith(".lock"):
                continue
            try:
                for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
                    if pattern.search(line) and "pubspec" not in line:
                        hits.append(f"{path.relative_to(root)}:{number}: {line.strip()[:120]}")
                        break
            except (UnicodeDecodeError, OSError):
                continue
    return hits


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version", nargs="?", help="X.Y.Z, or major / minor / patch")
    parser.add_argument("--build", default="increment", help="increment (default) | keep | reset | <number>")
    parser.add_argument("--root", default=".", help="Flutter app directory (or any directory inside / above it)")
    parser.add_argument("--dry-run", action="store_true", help="report changes without writing")
    parser.add_argument("--show", action="store_true", help="print the current version and exit")
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    args = parser.parse_args()

    pubspec = find_pubspec(Path(args.root).resolve())
    if pubspec is None:
        sys.exit(f"no Flutter pubspec.yaml found at or around {args.root}")
    root = pubspec.parent
    old_name, old_build, old_line = read_version(pubspec)

    if args.show or not args.version:
        current = f"{old_name}+{old_build}" if old_build else old_name
        print(json.dumps({"pubspec": str(pubspec), "version": current}) if args.json else f"{current}  ({pubspec})")
        if not args.show:
            print("give a version (X.Y.Z) or major/minor/patch to bump", file=sys.stderr)
            sys.exit(1)
        return

    new_name = next_version(old_name, args.version)
    new_build = next_build(old_build, args.build)
    new_full = f"{new_name}+{new_build}" if new_build else new_name
    apply = not args.dry_run

    # pubspec first: it is the only place that must change.
    new_line = re.sub(r"^(version:\s*)\S+", rf"\g<1>{new_full}", old_line)
    edits = [{"file": str(pubspec), "line": None, "before": old_line, "after": new_line}]
    if apply:
        text = pubspec.read_text(encoding="utf-8").replace(old_line, new_line, 1)
        pubspec.write_text(text, encoding="utf-8")

    touched = {pubspec}
    for path in candidate_files(root):
        if path == pubspec:
            continue
        file_edits = rewrite(path, old_name, new_name, old_build, new_build, apply)
        if file_edits:
            touched.add(path)
            edits.extend(file_edits)

    remaining = leftovers(root, old_name, touched)

    if args.json:
        print(json.dumps({"root": str(root), "old": f"{old_name}+{old_build}" if old_build else old_name,
                          "new": new_full, "dry_run": args.dry_run, "edits": edits, "leftovers": remaining}, indent=2, ensure_ascii=False))
        return

    verb = "would change" if args.dry_run else "changed"
    print(f"{old_name}{'+' + old_build if old_build else ''} -> {new_full}   ({root})\n")
    for edit in edits:
        where = f"{Path(edit['file']).relative_to(root)}" + (f":{edit['line']}" if edit["line"] else "")
        print(f"{verb} {where}\n  - {edit['before'].strip()}\n  + {edit['after'].strip()}")
    if remaining:
        print("\nstill mention the old version (decide by hand — may be history, may be a copy):")
        for hit in remaining:
            print(f"  {hit}")
    else:
        print("\nno other file mentions the old version.")


if __name__ == "__main__":
    main()
