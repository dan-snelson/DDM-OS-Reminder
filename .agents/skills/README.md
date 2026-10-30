# Agent Skills (DDM OS Reminder 5.2.0)

Project skills for coding agents that discover skills under `.agents/skills/`.

Each entry here is a symlink to the canonical skill in [`Resources/skills/`](../../Resources/skills/). Edit the canonical copy; do not replace these symlinks with copies.

| Skill | Canonical source | Purpose |
| --- | --- | --- |
| `diagnose-client-state` | [`Resources/skills/diagnose-client-state/SKILL.md`](../../Resources/skills/diagnose-client-state/SKILL.md) | Diagnose why a reminder dialog did or did not appear, from an uploaded client log, `/var/log/install.log`, and client `.plist` |
| `pre-release-review` | [`Resources/skills/pre-release-review/SKILL.md`](../../Resources/skills/pre-release-review/SKILL.md) | Independently audit release readiness, target-version beta references, repository contracts, and generated artifacts |

The same skills are mirrored in [`.claude/skills/`](../../.claude/skills/) and [`.codex/skills/`](../../.codex/skills/).

See [`AGENTS.md`](../../AGENTS.md) for repo rules.
