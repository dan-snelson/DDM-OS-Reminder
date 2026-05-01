# DDM OS Reminder - Copilot Instructions (3.2.0)

## Big Picture
- DDM OS Reminder is a macOS-only, MDM-agnostic reminder system for DDM-enforced OS update deadlines. It reads `/var/log/install.log` and shows a swiftDialog prompt via a LaunchDaemon.
- Apple built-in DDM notifications are subtle; this project delivers a prominent, actionable, customizable end-user dialog via a LaunchDaemon-scheduled zsh script pair.
- Core scripts: `reminderDialog.zsh` (runtime logic and dialog), `launchDaemonManagement.zsh` (deploys/loads LaunchDaemon and writes reminder script), and `assemble.zsh` (builds deployable artifacts).
- `assemble.zsh` embeds `reminderDialog.zsh` into `launchDaemonManagement.zsh` via heredoc. Reminder logic changes require re-assembly before deployment.
- This project does not perform updates, remind about non-OS updates, or support non-macOS platforms.

## Core Components
1. `reminderDialog.zsh` - Parses `/var/log/install.log`, resolves DDM deadline state, checks user availability, loads preferences, and displays the swiftDialog reminder.
2. `launchDaemonManagement.zsh` - Writes `reminderDialog.zsh` to disk and creates/loads the LaunchDaemon. Handles reset/uninstall via MDM Script Parameter 4: `All` | `LaunchDaemon` | `Script` | `Uninstall` | blank.
3. `assemble.zsh` - Combines scripts into a single deployable artifact, harmonizes RDNN, runs `zsh -n`, and generates plist/mobileconfig artifacts.

## Naming and RDNN
- RDNN must match everywhere: `reminderDialog.zsh`, `launchDaemonManagement.zsh`, generated plist/mobileconfig, and release artifacts. Default placeholder is `org.churchofjesuschrist`.
- RDNN mismatch can cause silent preference-loading failures. `assemble.zsh` is the enforcement point.
- Script suffixes follow this pattern: `dor` = DDM OS Reminder LaunchDaemon label, `dorm` = DDM OS Reminder Message client script.
- Deployed paths follow RDNN: `/Library/LaunchDaemons/{RDNN}.dor.plist`, `/Library/Management/{RDNN}/dorm.zsh`, `/Library/Managed Preferences/{RDNN}.dorm.plist`, `/var/log/{RDNN}.log`.

## Preference System
- Preference hierarchy is Managed Preferences -> Local Preferences -> Defaults (`preferenceConfiguration` array).
- Reads use `/usr/libexec/PlistBuddy`, not `defaults read`, for nested value reliability.
- Managed keys must remain authoritative. Invalid managed numeric values should not fall through to local values.
- Key script defaults:
  - `DaysBeforeDeadlineDisplayReminder`: 60
  - `DaysBeforeDeadlineBlurscreen`: 45
  - `DaysBeforeDeadlineHidingButton2`: 21
  - `MeetingDelay`: 75 minutes
  - `DaysOfExcessiveUptimeWarning`: 0
  - `MinimumDiskFreePercentage`: 99
- `Resources/sample.plist` can intentionally use sample/demo-friendly values. Do not "fix" sample values to script defaults unless requested.
- 3.2.0 adds granular support visibility preferences such as `HideSupportTeamPhone`, `HideSupportTeamEmail`, `HideSupportTeamWebsite`, `HideSupportKB`, and `HideSupportAssistanceMessage`.
- Localization supports `LanguageOverride` and matching `*Localized_<code>` preference keys.

## Logging
- Logging format: `<scriptName> (<version>): <timestamp> - [<level>] <message>`.
- Levels: `[PRE-FLIGHT]`, `[NOTICE]`, `[INFO]`, `[WARNING]`, `[ERROR]`, `[FATAL ERROR]`.
- Default log: `/var/log/org.churchofjesuschrist.log`, configurable by `ScriptLog`.
- New deadline, declaration, suppression, or preference precedence logic should log at `[NOTICE]` or `[WARNING]`.

## Build, Deploy, Demo
- Build artifacts with `zsh assemble.zsh`; output goes to `Artifacts/`.
- Self-extracting bundle: `zsh Resources/createSelfExtracting.zsh` using newest artifact.
- Quick demo: `zsh reminderDialog.zsh demo`.
- Preference preview: `zsh Resources/reminderDialogPreferenceTest.zsh`.
- Syntax checks are required after zsh edits: `zsh -n reminderDialog.zsh` and `zsh -n launchDaemonManagement.zsh`.
- `assemble.zsh` validates generated `.mobileconfig` with `/usr/bin/plutil -lint`.

## Style and Structure
- Variables: lowerCamelCase. Only exception: `PLACEHOLDER_MAP`.
- Functions: lowerCamelCase and `function name() {` with brace on same line.
- Control flow uses same-line braces: `if [[ ... ]]; then`.
- Prefer braced variable references: `${var}`. Bare `$var` only inside arithmetic `$(( ))`.
- Keep existing whitespace style: three blank lines between top-level sections and one blank line between logical steps inside functions.
- Use hash-wall separators for top-level groups, hash-space separators for function clusters, and dash separators inside execution flow.
- Comments should explain why or what comes next. Inline comments should be rare.

## Known Constraints and Decisions
- LaunchDaemon schedule is not profile-driven; changing frequency requires redeploying the plist.
- Log parsing depends on Apple's `/var/log/install.log` format.
- Disable button2 instead of hiding it near deadline so users see deferral is unavailable.
- Quiet period is tied to user interaction return code, not dialog display.
- Wait up to 5 minutes if enforcement date is in the past so MDM can refresh state.
- LaunchDaemon is intentional, not LaunchAgent.
- No SQLite state management; plist preferences and logs are sufficient.

## Navigation
- `reminderDialog.zsh` is large; orient by function name, preference map, and log-level conventions.
- When editing `launchDaemonManagement.zsh`, remember `reminderDialog.zsh` is embedded only at build time.
- If preferences do not load or LaunchDaemon does not fire, check RDNN consistency first.
- If changing reminder logic, update source first, then rebuild or update generated artifacts consistently.
