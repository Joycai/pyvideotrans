# Claude Code → Codex migration

Date: 2026-10-01 (Asia/Shanghai)

## Goal and baseline

Make this repository usable by Codex while retaining the existing Flutter architecture,
Chinese comments and commit conventions, release workflow, and regression checks.

The initial checkout was clean on `Joycai-main` at `a78b5239`. After fetching
`origin`, it was fast-forwarded by 27 commits to `b7a2e28a`.
`Joycai-main` is the documented development branch. `origin/main` is an old
upstream snapshot, so it was not used as the development baseline.
Migration changes are on `codex/migrate-agent-workflow`.

## Plan and acceptance criteria

1. **Update the development baseline — complete.**
   Fetch origin and fast-forward the clean checkout. Preserve local work and avoid
   merging the upstream snapshot into the Flutter branch.
2. **Migrate repository instructions — complete.**
   Rename `CLAUDE.md` to root `AGENTS.md`, preserve all architecture constraints,
   and add Codex branch, planning, and review guidance.
   Remove the `AGENTS.md` ignore rule so future clones receive the instructions.
3. **Migrate reusable workflows — complete.**
   Move `bump-versions` with its script, reference, and evaluation examples into
   `.agents/skills/`. Convert the Claude reviewer into a read-only Codex skill:
   remove Claude-specific tool/model metadata and absolute paths, retain its checks,
   and align provider guidance with the fetched code.
4. **Update navigation and local-state boundaries — complete.**
   Fix the codemap link and add README links. Keep `PLAN.md` as the product roadmap.
   Ignore local Codex state and old Claude worktrees. Preserve the existing
   `.claude/worktrees/` checkout and Claude Design source links.
5. **Verify the handover — complete.**
   Validate both skill manifests and resources, compare moved resources with their
   originals, run the version script in read-only/show and dry-run modes, check
   instruction links and Git whitespace, and confirm no application files changed.
   Record results below.

## Mapping

| Claude Code source | Codex destination | Treatment |
| --- | --- | --- |
| `CLAUDE.md` | `AGENTS.md` | Canonical repository instructions |
| `.claude/skills/bump-versions/` | `.agents/skills/bump-versions/` | Preserve script, reference, and evaluation examples |
| `.claude/agents/code-reviewer.md` | `.agents/skills/code-reviewer/SKILL.md` | Portable skill, normally executed in the current chat |
| `.claude/tasks/`, local worktrees | Ignored local state | No deletion of existing local work |
| Claude Design links and prompts | Existing `docs/design-prompts/` | Retain design provenance |

There are no tracked Claude hook settings, MCP server definitions, or permission
configuration to translate. The reviewer is not represented as a fictional Codex agent
configuration. Its procedure is a repository skill; independent delegation requires
an explicit user request. No API-provider or application model migration is needed.

## Using Codex after migration

Open this checkout in Codex and start a new chat to load the root `AGENTS.md`.
Codex discovers repository skills in `.agents/skills/`; if the skill list is stale,
restart Codex. This migration session reads the new files directly.

- Ask for normal development work; use `Joycai-main` as the base and PR target.
- For a release version change, invoke `$bump-versions` with an explicit version
  or bump kind. The script first runs in dry-run mode.
- For review, invoke `$code-reviewer`. Review never edits code or updates goldens.
- Application code changes require `flutter analyze` and `flutter test` in `app/`.
  UI changes also require the existing golden workflow. Live tests remain opt-in
  and require the user's service credentials.
- Documentation and agent-configuration changes use focused structural validation.

No global Codex settings, credentials, model selection, plugins, Git history, or
application dependencies need changing for this repository migration.

## Verification record

- Both migrated skills passed the Skill Creator `quick_validate.py` check.
- All four version-workflow resources match their Git originals after normalizing
  Windows line endings; the evaluation JSON parses successfully.
- Local links in instructions, skills, and this plan resolve.
- `AGENTS.md` is below Codex's default 32 KiB instruction limit; it and both skills
  are visible to Git rather than ignored.
- The moved script reports `1.1.0+2`. A patch dry-run proposes `1.1.1+3` in
  pubspec and both Windows resource fallback values, with no leftover old-version copies.
  The application version was not changed.
- `git diff --check` passed. Application code, design prompts, archive, and `PLAN.md`
  have no migration diff; the migration starts from the fetched `origin/Joycai-main`.
- Flutter analyze/test and golden tests were not run: this migration changes only
  documentation and workflow locations. The newly fetched application baseline has
  not been independently tested in this session.
- Codex's available-skill catalog now includes both repository skills
  (bump-versions and code-reviewer), confirming automatic skill discovery.
  Root AGENTS.md has been read directly in this chat; automatic instruction
  loading at the start of a new chat has not been independently observed.

## Recovery and remaining steps

Migration changes are submitted from `codex/migrate-agent-workflow` for review. The previous instructions and workflows
remain available from Git at `b7a2e28a`; a rollback can restore those specific tracked
files and remove only the migration-created files after preserving any later edits.
Do not delete the whole `.claude/` directory because it contains a local worktree.

The migration PR targets `Joycai-main`. Merge after review.
Repository skill discovery is confirmed. A fresh Codex chat will load the root
AGENTS.md at startup; this chat has already read it directly.

## Official references

- [Custom instructions with AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Build skills and repository discovery](https://learn.chatgpt.com/docs/build-skills)
