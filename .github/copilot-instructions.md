# DDM OS Reminder — GitHub Copilot Instructions

> **Author**: Dan K. Snelson | **Version**: 2.3.1b1 | **Status**: In Progress (Phase 3 — nearing completion)
> **Language**: zsh (Shell 100%) | **Platform**: macOS only | **License**: MIT

---

## What This Project Is

DDM OS Reminder is an MDM-agnostic, swiftDialog-based reminder system for Apple's Declarative Device Management (DDM) enforced macOS update deadlines. Apple's built-in DDM notification is too subtle; this project delivers a prominent, actionable, customizable end-user dialog via a LaunchDaemon-scheduled zsh script pair.

It does **not** perform updates, remind about non-OS updates, or support non-macOS platforms.

---

## Code Style

- **Variables**: lowerCamelCase exclusively (220 variables, zero exceptions). The only SCREAMING_SNAKE in the file is `PLACEHOLDER_MAP` — a global associative array, which is the sole permitted exception.
- **Functions**: Always `function name() {` — never bare `name() {`. Opening brace on the same line as the declaration (29 functions, zero exceptions).
- **Control flow**: Opening brace on the same line: `if [[ ... ]]; then` / `while ... do` / `case ... in`. No standalone `{` lines.
- **Variable references**: Braced `${var}` is the strong default (394 uses vs. 32 bare `$var`). Use bare `$var` only inside arithmetic `$(( ))` contexts.
- **Whitespace**: Three blank lines between top-level sections (hash-wall or hash-space separator blocks). One blank line between logical steps inside a function. This is the "human-readable white space" — don't compress it.
- **Section separators**: Two styles, used at different scopes:
  - `####################################################################################################` — top-level groupings (Global Variables, Functions, Exit)
  - `# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #` — individual functions or logical clusters within a group
  - `# -------------------------------------------------------------------------` — sub-sections inside the main execution block
- **Comments**: 16% comment density. Full-line comments narrate *why* or *what's next*; inline comments are rare and used only for non-obvious single expressions. Comments inside functions are terse and action-oriented (e.g., `# Read managed value`, `# Apply the preference based on type`).

---

## Core Components

1. **`reminderDialog.zsh`** (CORE) — Parses `/var/log/install.log`, checks user availability, displays the swiftDialog reminder.
2. **`launchDaemonManagement.zsh`** (DEPLOY) — Writes `reminderDialog.zsh` to disk and creates/loads the LaunchDaemon. Receives the reminder script embedded inside it via heredoc at build time. Handles reset/uninstall via MDM Script Parameter 4: `All` | `LaunchDaemon` | `Script` | `Uninstall` | blank.
3. **`assemble.zsh`** (BUILD) — Combines the two scripts into a single deployable artifact. Validates and harmonizes RDNN, runs `zsh -n`, generates `.mobileconfig`.

---

## Naming Conventions & RDNN

- **RDNN** (Reverse Domain Name Notation) is the single most critical configuration value. It must be consistent across `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and all plist/profile files. `assemble.zsh` is the enforcement point.
- Default RDNN in source: `org.churchofjesuschrist` — this is the example/placeholder. Organizations substitute their own.
- Script name suffixes follow a pattern: `dor` = DDM OS Reminder (LaunchDaemon label), `dorm` = DDM OS Reminder Message (the client-side script written to disk).
- Example paths on a deployed Mac:
  - Script: `/Library/Management/{RDNN}/dorm.zsh`
  - LaunchDaemon: `/Library/LaunchDaemons/{RDNN}.dor.plist`
  - Managed prefs: `/Library/Managed Preferences/{RDNN}.dorm.plist`
  - Log: `/var/log/{RDNN}.log`

---

## Preference System

**Priority (highest → lowest):** Managed Preferences → Local Preferences → hard-coded defaults (`preferenceConfiguration` array). **Read via `PlistBuddy`**, not `defaults read`.

| Parameter | Default | Effect |
|-----------|---------|--------|
| `DaysBeforeDeadlineDisplayReminder` | 14 | When the reminder window opens |
| `DaysBeforeDeadlineBlurscreen` | 3 | When the dialog background blurs |
| `DaysBeforeDeadlineHidingButton2` | 1 | When "Remind Me Later" is disabled |
| `MeetingDelay` | 75 min | How long to delay if a meeting is detected |
| `DaysOfExcessiveUptimeWarning` | 7 | Uptime threshold for warning |
| `MinimumDiskFreePercentage` | 10 | Disk space threshold for warning |

---

## Logging

Structured format: `<scriptName> (<version>): <timestamp> - [<level>] <message>`

Levels: `[PRE-FLIGHT]`, `[NOTICE]`, `[INFO]`, `[WARNING]`, `[ERROR]`, `[FATAL]`

Default log: `/var/log/org.churchofjesuschrist.log` (path is configurable via `ScriptLog` preference).

---

## Build & Test

```bash
zsh reminderDialog.zsh demo       # test dialog without MDM
zsh -n reminderDialog.zsh         # syntax check (quality gate)
zsh -n launchDaemonManagement.zsh
```

---

## Known Issues & Technical Debt

1. **LaunchDaemon schedule is not profile-driven** — changing reminder frequency requires redeploying the LaunchDaemon plist, not just a profile update.
2. **Log-parsing fragility** — `/var/log/install.log` format is Apple-controlled; any change breaks deadline detection.
3. **RDNN must match everywhere** — mismatch between scripts and config files causes silent preference-loading failures. `assemble.zsh` is the safeguard.
4. **Limited automated test surface** — most validation is manual (demo mode). A mocked-log test harness would reduce regressions.

---

## Key Decisions — Don't Re-litigate These

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

---

## Copilot Interaction Tips

- When editing `reminderDialog.zsh`, the function list and log-level conventions above are your map. The script is large — orient by function name.
- When editing `launchDaemonManagement.zsh`, remember that `reminderDialog.zsh` is **embedded at build time** — changes to the reminder script are not live in the management script until you run `assemble.zsh`.
- RDNN consistency is the #1 source of subtle bugs. If something isn't loading preferences or the LaunchDaemon isn't firing, check RDNN first.
- Demo mode (`zsh reminderDialog.zsh demo`) is your fastest feedback loop. Use it.
- All new logic that touches deadlines or suppression should log at `[NOTICE]` or `[WARNING]` level so it's observable in production.
