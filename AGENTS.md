# AGENTS.md

**Single source of truth for coding agents** working in this repo. This file takes precedence over `README.md`, `CONTRIBUTING.md`, `Resources/projectPlan.md`, and other general guidance when agent workflow rules conflict.


## Project Overview
- DDM OS Reminder is macOS-only, MDM-agnostic reminder system for DDM-enforced macOS update deadlines.
- Primary runtime flow lives in `reminderDialog.zsh`, deployed through `launchDaemonManagement.zsh`, and packaged by `assemble.zsh`.
- `assemble.zsh` embeds `reminderDialog.zsh` into `launchDaemonManagement.zsh` via heredoc. Changes to reminder logic are not deployment-ready until re-assembled.
- Script reads `/var/log/install.log`, resolves trustworthy DDM enforcement state, then uses swiftDialog to present user-facing reminder messaging.
- Project does not perform OS updates, target non-macOS platforms, or act as general-purpose update/remediation framework.


## Key Commands
- Validate syntax after every Zsh edit: `zsh -n reminderDialog.zsh`, `zsh -n launchDaemonManagement.zsh`, `zsh -n assemble.zsh`
- Fastest runtime smoke test: `zsh reminderDialog.zsh demo`
- Build deployable artifacts: `zsh assemble.zsh`
- Review build and packaging workflow: `zsh assemble.zsh --help`
- Preference/dialog validation helper: `zsh Resources/reminderDialogPreferenceTest.zsh --help`


## Agent Workflow
- Start by confirming this `AGENTS.md` is loaded before making non-trivial changes.
- Prefer surgical, minimal edits over broad rewrites. Reference exact functions, sections, or keys whenever possible.
- Ground decisions in repo truth first: read script behavior, docs, and helpers before changing policy or behavior.
- After any edit to `reminderDialog.zsh`, `launchDaemonManagement.zsh`, or `assemble.zsh`, immediately run `zsh -n` on modified scripts.
- After changes to reminder runtime behavior, use `zsh reminderDialog.zsh demo` as first feedback loop.
- When reminder logic changes affect deployment behavior, re-assemble before treating change as ready for deployment validation.
- Never introduce debug, fixture, or local-test behavior into default production paths unless task explicitly requires it.


## Boundaries

**Always allowed without asking**
- Read any file in repository.
- Run non-mutating searches, diffs, syntax checks, and demo-mode validation.
- Make small, targeted edits that preserve established Zsh style and repo contracts.
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
When files disagree, use this order:

1. `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and `assemble.zsh` for implemented behavior, deployment flow, defaults, and `scriptVersion`.
2. `README.md`, `Resources/README.md`, and `Diagrams/` for current operator and deployment documentation.
3. `CHANGELOG.md` for shipped behavior history and release notes.
4. `Resources/projectPlan.md` for historical architecture/product context, not runtime truth.


## Mission
DDM OS Reminder should give Mac admins prominent, actionable, customizable user messaging for DDM-enforced macOS update deadlines while staying MDM-agnostic, deployment-friendly, and operationally observable.


## Product Boundaries

### In Scope
- DDM-enforced macOS update deadline detection and reminder messaging
- swiftDialog-based UX and supporting deployment workflow
- LaunchDaemon-managed scheduling, preference-driven customization, and structured logging
- Packaging helpers, configuration generation, localization support, and admin validation tooling

### Out of Scope
- Non-macOS support
- Performing OS updates as primary behavior
- General software-update prompting beyond DDM-enforced macOS deadlines
- Replacing MDM platforms, softwareupdate orchestration, or full compliance suites


## Implementation Priorities
1. Preserve trustworthy DDM deadline/version resolution from `/var/log/install.log`.
2. Preserve RDNN consistency end-to-end. Silent RDNN mismatch is highest-risk configuration bug.
3. Keep preference behavior stable: `Managed Preferences -> Local Preferences -> Defaults`.
4. Keep subtle reminder semantics stable: quiet period begins after user interaction, not dialog display; past-due enforcement state may wait up to 5 minutes for refreshed DDM state before acting.
5. Keep user-facing reminder behavior clear, actionable, and observable through structured logging.
6. Keep assembled deployment workflow predictable across script, plist, mobileconfig, and self-extracting helper paths.


## Key Files
- `reminderDialog.zsh`: core runtime logic, deadline parsing, user checks, dialog rendering, logging
- `launchDaemonManagement.zsh`: deployment/reset logic, LaunchDaemon creation/loading, embedded reminder script writer, MDM Script Parameter 4 reset/uninstall handling (`All`, `LaunchDaemon`, `Script`, `Uninstall`, or blank)
- `assemble.zsh`: artifact builder, RDNN harmonization, heredoc embedding, syntax checks, plist/mobileconfig generation
- `README.md`: current project overview, features, upgrade notes, operator guidance
- `Resources/README.md`: assembly, packaging, plist/mobileconfig, EA, and preference-test instructions
- `Resources/sample.plist`: canonical localization and preference surface for generated configs
- `Resources/reminderDialogPreferenceTest.zsh`: preference-driven dialog validation helper
- `CHANGELOG.md`: release history and shipped behavior summary
- `Artifacts/`: generated build outputs that may be tracked; do not refresh casually


## Repository Rules
- Repo does not use `VERSION.txt`. Release-state truth comes from script `scriptVersion` values plus `README.md` and `CHANGELOG.md`.
- `assemble.zsh` is enforcement point for RDNN alignment and deployable artifact generation.
- Default RDNN placeholder is `org.churchofjesuschrist`. Preserve suffix meanings: `dor` = LaunchDaemon label, `dorm` = deployed reminder script.
- `reminderDialog.zsh` changes are not live inside `launchDaemonManagement.zsh` until you run `assemble.zsh`.
- Treat `Artifacts/` as generated but potentially tracked output. Do not rebuild or replace artifacts unless task specifically calls for it.
- Localization additions should usually start in `Resources/sample.plist`; runtime and config generators are designed to carry those keys forward.
- Submit PR-targeted guidance against `development` branch unless task or maintainer instruction says otherwise.
- Check `git status` before editing shared docs, generated artifacts, or cross-cutting files so you do not clobber local work.


## Scripting Style
Maintain established style in shipped scripts unless user explicitly requests otherwise.

1. Keep lowerCamelCase for variables and function names. Exception: existing `PLACEHOLDER_MAP`.
2. Keep function declaration style `function name() {` with same-line braces for control flow.
3. Prefer `"${var}"` expansions and existing quoting patterns.
4. Preserve visual sectioning: hash-wall separators, hash-space cluster separators, dash sub-sections, and roomy spacing.
5. Keep comments intentional and sparse. Use them for why/what-next, not line-by-line narration.
6. Route logging through existing helper functions and preserve format `<scriptName> (<version>): <timestamp> - [<level>] <message>`.
7. Keep new deadline, suppression, or restart-threshold logic observable with `[NOTICE]` or `[WARNING]` logs.
8. Preserve preference reads through `PlistBuddy` and existing key-mapping logic.
9. Preserve deployed naming/path conventions tied to RDNN:
   - `/Library/LaunchDaemons/{RDNN}.dor.plist`
   - `/Library/Management/{RDNN}/dorm.zsh`
   - `/Library/Managed Preferences/{RDNN}.dorm.plist`
   - `/var/log/{RDNN}.log`


## Quality Bar
- DDM resolution must fail safely when declaration state is missing, conflicting, invalid, or stale.
- Reminder suppression rules must stay explicit and logged.
- Demo mode must remain fast, reliable local validation path.
- LaunchDaemon deployment/reset flow must stay predictable and recoverable.
- Generated plist/mobileconfig output must remain aligned with runtime preference surface.
- Localization changes must not break English fallback behavior or existing language families.


## Required Validation
1. Run `zsh -n` on every modified Zsh script. This is required.
2. For `reminderDialog.zsh` behavior changes, run `zsh reminderDialog.zsh demo`.
3. For `assemble.zsh` or deployment-flow changes, review generated artifact expectations against `Resources/README.md` and relevant docs before calling work complete.
4. For packaging changes, account for self-extracting bundle workflow in `Resources/createSelfExtracting.zsh` and generated `.mobileconfig` validation via `/usr/bin/plutil -lint`.
5. For `AGENTS.md` or docs-only changes, verify Markdown structure, terminology, links, and repo references.
6. When behavior, preferences, or operator workflows change, update affected docs in `README.md`, `Resources/README.md`, `Diagrams/`, and `CHANGELOG.md` as needed.
7. Do not add new production dependencies without explicit confirmation.


## Release / Build Checklist
1. Keep `scriptVersion` aligned across shipped scripts when release-affecting changes touch versioned artifacts.
2. Confirm `README.md` and `CHANGELOG.md` match current behavior, defaults, and deployment workflow.
3. Rebuild artifacts only when release/package task explicitly requires it.
4. Review RDNN-sensitive paths, plist/mobileconfig output names, and script log path behavior when touching assembly/deployment code.
5. Verify no test-only, demo-only, or local fixture behavior leaked into production reminder flow.


## Maintenance
- Keep this file concise, directive, and focused on agent decision-making.
- Update `AGENTS.md` when workflow rules, validation requirements, repo boundaries, or source-of-truth guidance change.
- Avoid duplicating long narrative product docs here; link agents toward canonical runtime and operator docs instead.
