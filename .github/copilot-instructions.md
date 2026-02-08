# DDM OS Reminder — Copilot Instructions (3.0.0a1)

## Big Picture
- DDM OS Reminder is a macOS-only, MDM-agnostic reminder system for DDM-enforced OS update deadlines. It reads `/var/log/install.log` and shows a swiftDialog prompt via a LaunchDaemon.
- Core scripts: `reminderDialog.zsh` (runtime logic + dialog), `launchDaemonManagement.zsh` (deploys/loads LaunchDaemon and writes reminder script), `assemble.zsh` (builds deployable artifacts).
- `assemble.zsh` embeds `reminderDialog.zsh` into `launchDaemonManagement.zsh` via heredoc. Edits to reminder logic require re-assembly before deployment.
- It does **not** perform updates, remind about non-OS updates, or support non-macOS platforms.

## Critical Conventions
- **RDNN must match everywhere**: `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and generated plist/mobileconfig. Default placeholder is `org.churchofjesuschrist`. Mismatch causes silent preference-loading failures. `assemble.zsh` is the enforcement point.
- Preference hierarchy is **Managed Preferences → Local Preferences → Defaults** (`preferenceConfiguration` array). Reads use `PlistBuddy`, not `defaults read` (deliberate decision for nested value reliability).
- Key parameters (script defaults): `DaysBeforeDeadlineDisplayReminder` (60), `DaysBeforeDeadlineBlurscreen` (45), `DaysBeforeDeadlineHidingButton2` (21), `MeetingDelay` (75 min). `Resources/sample.plist` intentionally uses shorter demo values (14/3/1) for the first three keys.
- Logging format: `<scriptName> (<version>): <timestamp> - [<level>] <message>` with levels `[PRE-FLIGHT]`, `[NOTICE]`, `[INFO]`, `[WARNING]`, `[ERROR]`, `[FATAL]`. New deadline/suppression logic should log at `[NOTICE]` or `[WARNING]`.

## Build, Deploy, Demo
- Build artifacts: run `zsh assemble.zsh` (see [Resources/README.md](Resources/README.md)). Output in `Artifacts/`.
- Self-extracting bundle: `zsh Resources/createSelfExtracting.zsh` (uses newest artifact).
- Quick demo: `zsh reminderDialog.zsh demo` — fastest feedback loop. Use it.
- Syntax checks are a quality gate: `zsh -n reminderDialog.zsh` and `zsh -n launchDaemonManagement.zsh`.

## Style and Structure (observed)
- **Variables**: lowerCamelCase exclusively. Only exception: `PLACEHOLDER_MAP` (global associative array).
- **Functions**: Always `function name() {` with brace on same line. Control-flow uses same-line braces (`if [[ ... ]]; then`).
- **Variable references**: Braced `${var}` is the default; bare `$var` only inside arithmetic `$(( ))` contexts.
- **Whitespace**: Three blank lines between top-level sections. One blank line between logical steps inside functions. Don't compress it.
- **Section separators**: Hash-wall (`####...`) for top-level groups, hash-space (`# # # ...`) for function clusters, dash separator (`# -------...`) within execution flow.
- **Comments**: 16% density. Full-line comments narrate *why* or *what's next*. Inline comments rare, only for non-obvious expressions.

## Examples to keep in mind
- Deployed paths follow RDNN: `/Library/LaunchDaemons/{RDNN}.dor.plist`, `/Library/Management/{RDNN}/dorm.zsh`, `/Library/Managed Preferences/{RDNN}.dorm.plist`, `/var/log/{RDNN}.log`.
- `launchDaemonManagement.zsh` accepts MDM Script Parameter 4: `All` | `LaunchDaemon` | `Script` | `Uninstall` | blank (for reset/uninstall actions).
- User-facing behavior and escalation timelines are documented in [Diagrams/README.md](Diagrams/README.md).

## Known Constraints & Decisions
- LaunchDaemon schedule is not profile-driven; changing frequency requires redeploying the plist.
- Log parsing depends on Apple's `/var/log/install.log` format — upstream changes break deadline detection.
- Disable button2 instead of hiding near deadline (gives visual feedback that deferral is unavailable).
- Quiet period tied to user interaction (return code), not dialog display (prevents spam only after user actually interacted).
- LaunchDaemon (not LaunchAgent) for consistent execution regardless of logged-in user.

## Navigation
- When editing `reminderDialog.zsh`: script is large (~1,400 lines) — orient by function name and log-level conventions above.
- RDNN consistency is the #1 source of subtle bugs. If preferences aren't loading or LaunchDaemon isn't firing, check RDNN first.
