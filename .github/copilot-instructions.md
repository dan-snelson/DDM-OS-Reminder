# DDM OS Reminder — Copilot Instructions

## Big picture
- DDM OS Reminder is a macOS-only, MDM-agnostic reminder system for DDM-enforced OS update deadlines. It reads `/var/log/install.log` and shows a swiftDialog prompt via a LaunchDaemon.
- Core scripts: `reminderDialog.zsh` (runtime logic + dialog), `launchDaemonManagement.zsh` (deploys/loads LaunchDaemon and writes reminder script), `assemble.zsh` (builds deployable artifacts).
- `assemble.zsh` embeds `reminderDialog.zsh` into `launchDaemonManagement.zsh` via heredoc. Edits to reminder logic require re-assembly before deployment.

## Critical conventions
- **RDNN must match everywhere**: `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and generated plist/mobileconfig. Default placeholder is `org.churchofjesuschrist`.
- Preference hierarchy is **Managed Preferences → Local Preferences → Defaults** (`preferenceConfiguration` array). Reads use `PlistBuddy`, not `defaults`.
- Logging format: `<scriptName> (<version>): <timestamp> - [<level>] <message>` with levels `[PRE-FLIGHT]`, `[NOTICE]`, `[INFO]`, `[WARNING]`, `[ERROR]`, `[FATAL]`.

## Build, deploy, demo
- Build artifacts: run `zsh assemble.zsh` (see [Resources/README.md](Resources/README.md)). Output in `Artifacts/`.
- Self-extracting bundle: `zsh Resources/createSelfExtracting.zsh` (uses newest artifact).
- Quick demo: `zsh reminderDialog.zsh demo`.
- Syntax checks are a quality gate: `zsh -n reminderDialog.zsh` and `zsh -n launchDaemonManagement.zsh`.

## Style and structure (observed)
- Functions use `function name() {` with brace on the same line; control-flow uses same-line braces.
- Variables are lowerCamelCase; braced `${var}` is the default outside arithmetic.
- Section separators are meaningful: hash-wall for top-level groups, hash-space for function clusters, and `# -------------------------------------------------------------------------` within execution flow.

## Examples to keep in mind
- Deployed paths follow RDNN (e.g., `/Library/LaunchDaemons/{RDNN}.dor.plist`, `/Library/Management/{RDNN}/dorm.zsh`, `/var/log/{RDNN}.log`).
- User-facing behavior and escalation timelines are documented in [Diagrams/README.md](Diagrams/README.md).

## Known constraints
- LaunchDaemon schedule is not profile-driven; changing frequency requires redeploying the plist.
- Log parsing depends on Apple’s `/var/log/install.log` format.
