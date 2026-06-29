# AGENTS.md
**Single source of truth for coding agents** (Claude Code, Cursor, Copilot, Aider, etc.) working in this repo.  
Takes precedence over `README.md`, `CONTRIBUTING.md`, `Resources/projectPlan.md`, and similar instruction files when workflow rules conflict.  
Claude Code users: symlink with `ln -s AGENTS.md CLAUDE.md` or reference via `@AGENTS.md` from a minimal `CLAUDE.md`.

## Orchestration Contract
This file codifies repo rules, boundaries, workflows, and repeatable skills. If same correction repeats, formalize it here instead of re-prompting it.

## Project Overview
DDM OS Reminder is macOS-only, MDM-agnostic reminder system for DDM-enforced macOS update deadlines.

- Primary runtime flow lives in `reminderDialog.zsh`, deployed as `/Library/Management/<rdnn>/dor.zsh` through `launchDaemonManagement.zsh`, and packaged by `assemble.zsh`.
- v4 scheduling uses a heartbeat `LaunchDaemon` which calls `dor-starter.zsh`; the starter consults `/Library/Management/<rdnn>/dor-state.plist` before deciding whether to launch `dor.zsh`.
- `assemble.zsh` embeds `reminderDialog.zsh` into `launchDaemonManagement.zsh` via heredoc. Reminder logic changes are not deployment-ready until re-assembled.
- Runtime reads `/var/log/install.log`, resolves trustworthy DDM enforcement state, then uses swiftDialog to present user-facing reminder messaging.
- Baseline reminder slots are admin-controlled through `DailyReminderTimes` in deployed preferences. Mutable scheduler state does not belong in managed/local preference payloads.
- Past-deadline aggressive mode is default-on through `AggressiveModePastDeadlineHours` / `AggressiveModeFrequencyMinutes`; support suppression is runtime-only via `/Library/Management/<rdnn>/dor-aggressive-kill`.
- Project does not perform OS updates, target non-macOS platforms, or act as general-purpose update/remediation framework.

## Key Commands
- Validate syntax after every Zsh edit: `zsh -n reminderDialog.zsh`, `zsh -n launchDaemonManagement.zsh`, `zsh -n assemble.zsh`, and `zsh -n Resources/reminderDialogPreferenceTest.zsh` when touched
- Fastest runtime smoke test: `zsh reminderDialog.zsh demo`
- Build deployable artifacts: `zsh assemble.zsh`
- Review build and packaging workflow: `zsh assemble.zsh --help`
- Preference/dialog validation helper: `zsh Resources/reminderDialogPreferenceTest.zsh --help`

## Agent Workflow
- Confirm this file is loaded before starting non-trivial work.
- Default user-facing communication mode: `$caveman full`, except for security warnings, irreversible actions, or clear user confusion.
- Ground decisions in repo truth first: inspect script behavior, nearby docs, and helpers before changing policy or behavior.
- Use surgical edits. Reference exact functions, sections, preference keys, or paths instead of pasting broad rewrites.
- Treat context like scalpel, not net. Gather only enough local evidence to make smallest correct change.
- After any edit to `reminderDialog.zsh`, `launchDaemonManagement.zsh`, or `assemble.zsh`, run `zsh -n` on modified scripts immediately.
- After reminder runtime behavior changes, use `zsh reminderDialog.zsh demo` as first feedback loop.
- When reminder logic affects deployment behavior, re-assemble before treating change as deployment-ready.
- Never introduce debug, fixture, or local-test behavior into default production paths unless task explicitly requires it.
- Prefer batching related work into one well-scoped prompt; if repeated task pattern emerges, capture it in Skills below.

## Skills
Invoke relevant skill name during planning.

### Reminder Runtime Change Skill
1. Start from nearest owning function or decision path in `reminderDialog.zsh`.
2. Preserve DDM trust rules, suppression semantics, and structured logging.
3. Preserve scheduler contract: baseline runs resolve from `DailyReminderTimes`; exact-time reschedules live in `dor-state.plist`; manual/demo runs do not mutate daemon scheduler state.
4. Run `zsh -n reminderDialog.zsh` immediately after edit.
5. Run `zsh reminderDialog.zsh demo` as first behavior check.
6. If deployment behavior changed, re-assemble and review affected docs.

### Deployment Flow Change Skill
1. Trace change across `launchDaemonManagement.zsh`, `assemble.zsh`, generated plist/mobileconfig expectations, `dor-starter.zsh`/`dor-state.plist`/`dor.pid` runtime assets, and RDNN-sensitive paths.
2. Preserve embedded-script contract: `reminderDialog.zsh` changes are not live in deployment flow until assembled.
3. Run `zsh -n` on every touched Zsh script immediately after edit.
4. Review `Resources/README.md` and packaging helpers before calling work complete.
5. Do not regenerate tracked `Artifacts/` unless task explicitly requires it.

### Preference or Localization Change Skill
1. Start from `Resources/sample.plist` and nearby runtime preference reads.
2. Preserve precedence `Managed Preferences -> Local Preferences -> Defaults`.
3. Keep `PlistBuddy`-based reads and existing key-mapping behavior.
4. Validate fallback behavior, especially English and existing language families.
5. Update docs and changelog when operator-facing behavior changes.

## Boundaries
**Always allowed without asking**
- Read any repository file.
- Run non-mutating searches, diffs, syntax checks, and demo-mode validation.
- Make small targeted edits that preserve established Zsh style and repo contracts.
- Update docs that must stay aligned with behavior changed in current task.

**Ask before doing**
- Add new production dependencies or external runtime checks.
- Regenerate or replace tracked files under `Artifacts/`.
- Change preference names, default values, precedence, or deployed plist/mobileconfig contracts.
- Change LaunchDaemon label/path conventions, RDNN placeholder strategy, or script/log path contracts.
- Change default reminder timing, post-deadline restart behavior, or user-facing suppression semantics.
- Prepare release-facing updates whose main purpose is packaging, artifact refresh, or release publication.

**Never do**
- Break RDNN consistency across `reminderDialog.zsh`, `launchDaemonManagement.zsh`, generated plist, and generated mobileconfig.
- Replace `PlistBuddy`-based preference reads with `defaults read`.
- Add non-macOS behavior or vendor-lock core reminder flow to one MDM.
- Overwrite unrelated local changes or edit outside task scope without explicit approval.

## Source of Truth
When files disagree, prefer:

1. `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and `assemble.zsh` for implemented behavior, deployment flow, and `scriptVersion`.
2. `Resources/sample.plist` for canonical deployable preference surface and shipped default values.
3. `README.md`, `Resources/README.md`, and `Diagrams/` for current operator and deployment documentation.
4. `CHANGELOG.md` for shipped behavior history and release notes.
5. `Resources/projectPlan.md` for historical architecture and product context, not runtime truth.

## Mission and Scope
Mission: give Mac admins prominent, actionable, customizable user messaging for DDM-enforced macOS update deadlines while staying MDM-agnostic, deployment-friendly, and operationally observable.

In scope:
- DDM-enforced macOS update deadline detection and reminder messaging
- swiftDialog UX and supporting deployment workflow
- LaunchDaemon-managed scheduling, preference-driven customization, and structured logging
- Packaging helpers, configuration generation, localization support, and admin validation tooling

Out of scope:
- non-macOS support
- performing OS updates as primary behavior
- general software-update prompting beyond DDM-enforced macOS deadlines
- replacing MDM platforms, softwareupdate orchestration, or full compliance suites

## Implementation Priorities
1. Preserve trustworthy DDM deadline and target-version resolution from `/var/log/install.log` and related declaration state.
2. Preserve RDNN consistency end-to-end. Silent RDNN mismatch is highest-risk configuration bug.
3. Keep preference behavior stable: `Managed Preferences -> Local Preferences -> Defaults`.
4. Keep reminder semantics stable: quiet period begins after user interaction, not dialog display; past-due enforcement state may wait up to 5 minutes for refreshed DDM state before acting; aggressive mode starts after `AggressiveModePastDeadlineHours` unless the support kill switch exists; once aggressive mode is active, `Open Software Update` and dismissal paths keep exact-time redisplay scheduling until compliance or support suppression.
5. Keep user-facing reminder behavior clear, actionable, and observable through structured logging.
6. Keep assembled deployment workflow predictable across heartbeat daemon, starter/state assets, script, plist, mobileconfig, and self-extracting helper paths.

## Key Files
- `reminderDialog.zsh`: core runtime logic, deadline parsing, user checks, dialog rendering, logging
- `launchDaemonManagement.zsh`: deployment and reset logic, heartbeat LaunchDaemon creation/loading, embedded `dor.zsh` and generated `dor-starter.zsh` writer, runtime asset cleanup, MDM Script Parameter 4 reset and uninstall handling (`All`, `LaunchDaemon`, `Script`, `Uninstall`, or blank)
- `assemble.zsh`: artifact builder, RDNN harmonization, heredoc embedding, syntax checks, plist and mobileconfig generation
- `README.md`: current project overview, features, upgrade notes, operator guidance
- `Resources/README.md`: assembly, packaging, plist/mobileconfig, EA, and preference-test instructions
- `Resources/sample.plist`: canonical localization and preference surface for generated configs
- `Resources/reminderDialogPreferenceTest.zsh`: preference-driven dialog validation helper
- `CHANGELOG.md`: release history and shipped behavior summary
- `Artifacts/`: generated build outputs that may be tracked; do not refresh casually

## Current Runtime Hotspots
- Deadline resolution must fail safely when declaration state is missing, conflicting, invalid, or stale. Resolver conflicts suppress reminder dialog entirely.
- Post-deadline restart workflow gates on effective post-deadline epoch when safely resolved, not raw `EnforcedInstallDate` alone.
- Quiet period starts after user interaction, not when dialog first appears.
- Baseline reminder slots resolve from `DailyReminderTimes` in deployed preferences. Default sample values (`08:00,12:00,16:00`) are fallback defaults, not runtime hardcodes.
- Pre-deadline minute thresholds resolve from `MinutesBeforeDeadlineReminderSchedule` (`45,30,15,10,5` by default). Per-threshold delivery state stays in `dor-state.plist`.
- Past-deadline aggressive cadence resolves from `AggressiveModePastDeadlineHours` (`2` by default) and `AggressiveModeFrequencyMinutes` (`20` by default). Mac Admins can effectively suppress it with a high hour value such as `720`; support can temporarily suppress it with `/Library/Management/<rdnn>/dor-aggressive-kill`.
- `dor-starter.zsh` is expected to exit quietly when `NextScheduledReminder` is `FALSE` or future-dated. Check `dor-state.plist` before treating a no-op heartbeat as failure.
- Only starter-launched runs should mutate `dor-state.plist` or `dor.pid`; direct/manual/demo runs bypass daemon scheduler writes.
- Once aggressive mode is active, `Open Software Update` and dismissal paths should keep exact-time redisplay scheduling; non-aggressive update flows still return to the next baseline reminder slot unless a configured pre-deadline minute threshold is earlier.
- `reminderDialog.zsh` changes are not live inside `launchDaemonManagement.zsh` until `zsh assemble.zsh` runs.

## Repository Rules
- Repo does not use `VERSION.txt`. Release-state truth comes from script `scriptVersion` values plus `README.md` and `CHANGELOG.md`.
- `assemble.zsh` is enforcement point for RDNN alignment and deployable artifact generation.
- Default RDNN placeholder is `org.churchofjesuschrist`. Preserve suffix meanings: `dor` = LaunchDaemon/runtime asset prefix, `dorm` = managed preference domain suffix.
- Admin-controlled baseline schedule lives in `DailyReminderTimes` within managed/local preferences. Mutable scheduler state must stay in `dor-state.plist`, not deployable preference payloads.
- Treat `Artifacts/` as generated but potentially tracked output. Do not rebuild or replace artifacts unless task specifically calls for it.
- Localization additions should usually start in `Resources/sample.plist`; runtime and config generators are designed to carry those keys forward.
- Submit PR-targeted guidance against `development` branch unless task or maintainer instruction says otherwise.
- Check `git status` before editing shared docs, generated artifacts, or cross-cutting files so unrelated local work is not overwritten.
- Avoid hidden behavior changes during refactors.
- If behavior, preferences, or operator workflow change, update affected docs in `README.md`, `Resources/README.md`, `Diagrams/`, and `CHANGELOG.md` as needed.

## Scripting Style
These rules override ad-hoc prompting. Match established shipped-script style unless user explicitly asks otherwise.

1. Keep lowerCamelCase for variables and function names. Exception: existing `PLACEHOLDER_MAP`.
2. Keep function declaration style `function name() {` with same-line braces for control flow.
3. Prefer `"${var}"` expansions and existing quoting patterns.
4. Preserve visual sectioning: hash walls, hash-space clusters, dash sub-sections, and roomy spacing.
5. Keep comments intentional and sparse. Use them for why or what-next, not line-by-line narration.
6. Route logging through existing helper functions and preserve format `<scriptName> (<version>): <timestamp> - [<level>] <message>`.
7. Keep new deadline, suppression, or restart-threshold logic observable with `[NOTICE]` or `[WARNING]` logs.
8. Preserve preference reads through `PlistBuddy` and existing key-mapping logic.
9. Preserve deployed naming and path conventions tied to RDNN:
   - `/Library/LaunchDaemons/{RDNN}.dor.plist`
   - `/Library/Management/{RDNN}/dor.zsh`
   - `/Library/Management/{RDNN}/dor-starter.zsh`
   - `/Library/Management/{RDNN}/dor-state.plist`
   - `/Library/Management/{RDNN}/dor.pid`
   - `/Library/Managed Preferences/{RDNN}.dorm.plist`
   - `/var/log/{RDNN}.log`

## Quality Bar
- DDM resolution must fail safely when declaration state is missing, conflicting, invalid, or stale.
- Reminder suppression rules must stay explicit and logged.
- Demo mode must remain fast, reliable local validation path.
- LaunchDaemon deployment and reset flow must stay predictable and recoverable.
- Generated plist and mobileconfig output must remain aligned with runtime preference surface.
- Localization changes must not break English fallback behavior or existing language families.

## Required Validation
1. Run `zsh -n` on every modified Zsh script.
2. For `reminderDialog.zsh` behavior changes, run `zsh reminderDialog.zsh demo`.
3. For `assemble.zsh` or deployment-flow changes, review generated artifact expectations against `Resources/README.md` and related docs before calling work complete.
4. For packaging changes, account for self-extracting bundle workflow in `Resources/createSelfExtracting.zsh` and validate generated `.mobileconfig` with `/usr/bin/plutil -lint`.
5. For `AGENTS.md` or docs-only changes, verify Markdown structure, terminology, links, and repo references.
6. When behavior, preferences, or operator workflows change, update affected docs in `README.md`, `Resources/README.md`, `Diagrams/`, and `CHANGELOG.md` as needed.
7. Do not add new production dependencies without explicit approval.

## Release Checklist
Apply only for release or packaging prep.

1. Keep `scriptVersion` aligned across shipped scripts when release-affecting changes touch versioned artifacts.
2. Confirm `README.md` and `CHANGELOG.md` match current behavior, defaults, and deployment workflow.
3. Rebuild artifacts only when release or packaging task explicitly requires it.
4. Review RDNN-sensitive paths, plist/mobileconfig output names, and script log path behavior when touching assembly or deployment code.
5. Verify no test-only, demo-only, or local fixture behavior leaked into production reminder flow.

## Maintenance
This file is versioned with project. When workflow rules, validation requirements, repo boundaries, or source-of-truth guidance change, update `AGENTS.md`. Keep file concise, directive, and focused on agent decision-making.
