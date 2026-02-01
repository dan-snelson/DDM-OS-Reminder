# DDM OS Reminder — GitHub Copilot Instructions

> **Author**: Dan K. Snelson | **Version**: 2.3.1b1 | **Status**: In Progress (Phase 3 — nearing completion)
> **Language**: zsh (Shell 100%) | **Platform**: macOS only | **License**: MIT

---

## What This Project Is

DDM OS Reminder is an MDM-agnostic, swiftDialog-based reminder system for Apple's Declarative Device Management (DDM) enforced macOS update deadlines. Apple's built-in DDM notification is too subtle; this project delivers a prominent, actionable, customizable end-user dialog via a LaunchDaemon-scheduled zsh script pair.

It does **not** perform updates, remind about non-OS updates, or support non-macOS platforms.

---

## Repository Layout

```
DDM-OS-Reminder/
├── .github/                          # GitHub config (this file lives here)
├── Resources/
│   ├── sample.plist                  # Preference template; basis for .mobileconfig generation
│   ├── createPlist.zsh               # Standalone plist/profile generator
│   └── createSelfExtracting.zsh      # Wraps assembled script into a self-extracting .sh
├── images/                           # README screenshots
├── assemble.zsh                      # BUILD SCRIPT — assembles the two scripts into one deployable artifact
├── launchDaemonManagement.zsh        # DEPLOYMENT SCRIPT — writes reminderDialog.zsh to disk + creates/loads LaunchDaemon
├── reminderDialog.zsh                # CORE SCRIPT — parses install.log, checks user availability, displays swiftDialog
├── org.churchofjesuschrist.dorm.plist # Default preference file (example RDNN)
├── CHANGELOG.md
├── CONTRIBUTING.md
└── README.md
```

**Artifacts/ directory** is the build output target for `assemble.zsh`.

---

## Core Components & Responsibilities

### 1. `reminderDialog.zsh` — the runtime brain
- Parses `/var/log/install.log` for the most recent `EnforcedInstallDate` and `setPastDuePaddedEnforcementDate` entries.
- Compares installed macOS version against the DDM-enforced version.
- Checks end-user availability: skips if in a meeting (display sleep assertions) or within a quiet period.
- Loads preferences via `PlistBuddy` (not `defaults read`) from the managed → local → hard-coded hierarchy.
- Renders a `swiftDialog` reminder with variable substitution, conditional warnings, and deadline-driven behavior changes.
- Logs structured entries to `scriptLog`.

**Key functions**: `installedOSvsDDMenforcedOS()`, `checkUserDisplaySleepAssertions()`, `detectStagedUpdate()`, `loadPreferenceOverrides()`

### 2. `launchDaemonManagement.zsh` — the deployment wrapper
- Receives `reminderDialog.zsh` embedded inside it (via heredoc, injected by `assemble.zsh` at build time).
- Creates the organization directory, writes the reminder script to disk, generates and loads the LaunchDaemon plist.
- Handles reset/uninstall via MDM Script Parameter 4: `resetConfiguration` (`All` | `LaunchDaemon` | `Script` | `Uninstall` | blank).

**Key functions**: `createDDMOSReminderScript()`, `createLaunchDaemon()`, `resetConfiguration()`

### 3. `assemble.zsh` — the build system
- Validates that `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and `Resources/sample.plist` all exist.
- Checks and harmonizes the Reverse Domain Name Notation (RDNN) across both scripts — mismatched RDNN causes preference loading failures.
- Embeds `reminderDialog.zsh` into `launchDaemonManagement.zsh` via heredoc.
- Runs `zsh -n` syntax validation on the assembled output.
- Generates the `.mobileconfig` Configuration Profile from the sample plist.
- Outputs everything to `Artifacts/` with consistent timestamps.

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

**Priority (highest → lowest):**
1. Managed Preferences — `/Library/Managed Preferences/{RDNN}.dorm.plist` (MDM-deployed, cannot be overridden)
2. Local Preferences — `/Library/Preferences/{RDNN}.dorm.plist`
3. Hard-coded defaults in the script's `preferenceConfiguration` array

**Read via `PlistBuddy`**, not `defaults read` — this was a deliberate decision for reliability with nested values.

**Key parameters that govern behavior:**

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

## Build & Test Workflow

**Demo/test (no MDM required):**
```bash
zsh reminderDialog.zsh demo
```

**Assemble for deployment:**
```bash
zsh assemble.zsh
# Prompts for RDNN, outputs to Artifacts/
```

**Syntax check (should be clean before any release):**
```bash
zsh -n reminderDialog.zsh
zsh -n launchDaemonManagement.zsh
```

**Validate a plist:**
```bash
plutil -lint Resources/sample.plist
```

---

## Deployment Summary

1. `assemble.zsh` produces a single assembled script + `.plist` + `.mobileconfig`.
2. Upload an assembled `.zsh` script and either a `.plist` or `.mobileconfig` to MDM. Deploy profile first, then run script (Parameter 4 = `All`).
3. The assembled script self-installs: writes the reminder script to disk, creates and loads the LaunchDaemon.
4. LaunchDaemon fires on schedule → `reminderDialog.zsh` runs → checks install.log → shows dialog if needed.
5. Optionally wrap in a self-extracting shell script via `Resources/createSelfExtracting.zsh`.

---

## External Dependencies

- **swiftDialog** (minimum v2.5.6.4805) — the dialog rendering engine. Must be installed on target Macs before DDM OS Reminder is deployed.
- **macOS system commands used**: `pmset`, `diskutil`, `sysctl`, `uptime`, `PlistBuddy`, `launchctl`
- **Log source**: `/var/log/install.log` — Apple's system log containing DDM enforcement entries. Core behavior depends on parsing this file; upstream format changes from Apple can break deadline detection.

---

## Known Issues & Technical Debt

1. **LaunchDaemon schedule is not profile-driven** — changing reminder frequency requires redeploying the LaunchDaemon plist, not just a profile update.
2. **Log-parsing fragility** — `/var/log/install.log` format is Apple-controlled; any change breaks deadline detection.
3. **RDNN must match everywhere** — mismatch between scripts and config files causes silent preference-loading failures. `assemble.zsh` is the safeguard.
4. **Limited automated test surface** — most validation is manual (demo mode). A mocked-log test harness would reduce regressions.

---

## Open Questions (as of 2026-01-31)

1. Should the project support multiple language localizations out of the box?

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
