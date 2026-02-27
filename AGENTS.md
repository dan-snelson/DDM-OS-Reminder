# DDM OS Reminder — Agent Instructions

> **Author**: Dan K. Snelson | **Version**: 2.6.0b3 | **Language**: zsh (Shell 100%) | **Platform**: macOS only | **License**: MIT

## Big picture
- DDM OS Reminder is a macOS-only, MDM-agnostic reminder system for DDM-enforced OS update deadlines. It reads `/var/log/install.log` and shows a swiftDialog prompt via a LaunchDaemon.
- Apple’s built-in DDM notification is subtle; this project delivers a prominent, actionable, customizable end-user dialog via a LaunchDaemon-scheduled zsh script pair.
- Core scripts: `reminderDialog.zsh` (runtime logic + dialog), `launchDaemonManagement.zsh` (deploys/loads LaunchDaemon and writes reminder script), `assemble.zsh` (builds deployable artifacts).
- `assemble.zsh` embeds `reminderDialog.zsh` into `launchDaemonManagement.zsh` via heredoc. Edits to reminder logic require re-assembly before deployment.
- It does **not** perform updates, remind about non-OS updates, or support non-macOS platforms.

## Core components
1. **`reminderDialog.zsh`** (CORE) — Parses `/var/log/install.log`, checks user availability, displays the swiftDialog reminder.
2. **`launchDaemonManagement.zsh`** (DEPLOY) — Writes `reminderDialog.zsh` to disk and creates/loads the LaunchDaemon. Receives the reminder script embedded inside it via heredoc at build time. Handles reset/uninstall via MDM Script Parameter 4: `All` | `LaunchDaemon` | `Script` | `Uninstall` | blank.
3. **`assemble.zsh`** (BUILD) — Combines the two scripts into a single deployable artifact, harmonizes RDNN, runs `zsh -n`, and generates `.mobileconfig`.

## Naming conventions & RDNN
- **RDNN must match everywhere**: `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and generated plist/mobileconfig. Default placeholder is `org.churchofjesuschrist`. Mismatch causes silent preference-loading failures. `assemble.zsh` is the enforcement point.
- Script name suffixes follow a pattern: `dor` = DDM OS Reminder (LaunchDaemon label), `dorm` = DDM OS Reminder Message (the client-side script written to disk).
- Deployed paths follow RDNN: `/Library/LaunchDaemons/{RDNN}.dor.plist`, `/Library/Management/{RDNN}/dorm.zsh`, `/Library/Managed Preferences/{RDNN}.dorm.plist`, `/var/log/{RDNN}.log`.

## Preference system
- Preference hierarchy is **Managed Preferences → Local Preferences → Defaults** (`preferenceConfiguration` array).
- Reads use `PlistBuddy`, not `defaults read` (deliberate decision for nested value reliability).

| Parameter | Default | Effect |
|-----------|---------|--------|
| `DaysBeforeDeadlineDisplayReminder` | 60 | When the reminder window opens |
| `DaysBeforeDeadlineBlurscreen` | 45 | When the dialog background blurs |
| `DaysBeforeDeadlineHidingButton2` | 21 | When "Remind Me Later" is disabled |
| `MeetingDelay` | 75 min | How long to delay if a meeting is detected |
| `DaysOfExcessiveUptimeWarning` | 0 | Uptime threshold for warning |
| `MinimumDiskFreePercentage` | 99 | Disk space threshold for warning |

## Logging
- Logging format: `<scriptName> (<version>): <timestamp> - [<level>] <message>`
- Levels: `[PRE-FLIGHT]`, `[NOTICE]`, `[INFO]`, `[WARNING]`, `[ERROR]`, `[FATAL ERROR]`
- Default log: `/var/log/org.churchofjesuschrist.log` (path is configurable via `ScriptLog` preference)
- New deadline/suppression logic should log at `[NOTICE]` or `[WARNING]`.

## Build, deploy, demo
- Build artifacts: run `zsh assemble.zsh` (see [Resources/README.md](Resources/README.md)). Output in `Artifacts/`.
- Self-extracting bundle: `zsh Resources/createSelfExtracting.zsh` (uses newest artifact).
- Quick demo: `zsh reminderDialog.zsh demo` — fastest feedback loop. Use it.
- Syntax checks are a quality gate: `zsh -n reminderDialog.zsh` and `zsh -n launchDaemonManagement.zsh`.
- `assemble.zsh` validates the generated `.mobileconfig` with `/usr/bin/plutil -lint`.

## Style and structure (observed)
- **Variables**: lowerCamelCase exclusively. Only exception: `PLACEHOLDER_MAP` (global associative array).
- **Functions**: Always `function name() {` with brace on same line. Control-flow uses same-line braces (`if [[ ... ]]; then`).
- **Variable references**: Braced `${var}` is the default; bare `$var` only inside arithmetic `$(( ))` contexts.
- **Whitespace**: Three blank lines between top-level sections. One blank line between logical steps inside functions. Don’t compress it.
- **Section separators**: Hash-wall line for top-level groups (example: `####################################################################################################`).
- **Section separators**: Hash-space line for function clusters (example: `# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #`).
- **Section separators**: Dash line for sub-sections inside execution flow (example: `# -------------------------------------------------------------------------`).
- **Comments**: 16% density. Full-line comments narrate *why* or *what’s next*; inline comments rare, only for non-obvious expressions.

## Known issues & technical debt
- LaunchDaemon schedule is not profile-driven; changing frequency requires redeploying the plist.
- Log parsing depends on Apple’s `/var/log/install.log` format — upstream changes break deadline detection.
- RDNN mismatch causes silent preference-loading failures. `assemble.zsh` is the safeguard.
- Limited automated test surface; most validation is manual (demo mode). A mocked-log test harness would reduce regressions.

## Key decisions — don’t re-litigate these

| Decision | Rationale |
|----------|-----------|
| Single assembled script via heredoc embedding | Simplifies MDM deployment to one script execution |
| Preference hierarchy: Managed > Local > Defaults | Enterprise control with per-device flexibility |
| Disable button2 instead of hiding near deadline | Gives visual feedback that deferral is unavailable |
| `PlistBuddy` over `defaults read` | More reliable for complex/nested plist values |
| Quiet period tied to user interaction (return code), not dialog display | Prevents spam only after the user actually interacted |
| Wait up to 5 min if enforcement date is in the past | Handles edge case before MDM refreshes its state |
| LaunchDaemon (not LaunchAgent) | Consistent execution regardless of which user is logged in |
| No SQLite state management | Plist preferences + log files are sufficient |

## Navigation
- When editing `reminderDialog.zsh`: script is large (~1,400 lines) — orient by function name and log-level conventions above.
- When editing `launchDaemonManagement.zsh`, remember that `reminderDialog.zsh` is **embedded at build time** — changes to the reminder script are not live in the management script until you run `assemble.zsh`.
- RDNN consistency is the #1 source of subtle bugs. If preferences aren’t loading or LaunchDaemon isn’t firing, check RDNN first.
- Demo mode (`zsh reminderDialog.zsh demo`) is your fastest feedback loop. Use it.
- All new logic that touches deadlines or suppression should log at `[NOTICE]` or `[WARNING]` level so it’s observable in production.
