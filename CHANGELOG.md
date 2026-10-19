# DDM OS Reminder

## Changelog

### Version 5.2.0b4 (19-Oct-2026)
- Fixed: `{minutesBeforeDeadline}` in `PreDeadlineThresholdMessage` showed the crossed threshold (for example, `45`) instead of the time actually left, so a late run (padded deadline from `setPastDuePaddedEnforcementDate`, heartbeat delay, wake from sleep, collapsed stale thresholds, or a manual run) overstated time remaining ([Issue #160](https://github.com/dan-snelson/DDM-OS-Reminder/issues/160))
    - The placeholder now shows minutes remaining until the effective deadline, rounded up and never above the crossed threshold, computed when the dialog copy is applied. On-time runs still show the threshold value.
    - `Pre-deadline threshold reminder due: …` and `Applying …-minute pre-deadline threshold dialog copy` notices now append `(<n> minute(s) remaining)`.
    - Threshold delivered/skipped state, scheduling, and preference keys are unchanged. Known: copy reads `1 minutes` when one minute remains.
- `Resources/diagnoseReminderState.zsh` checklist version now `5.2.0b4`; no diagnosis logic changes.

### Version 5.2.0b3 (18-Oct-2026)
- New low-battery warning: when a Mac is running on its internal battery below `MinimumBatteryPercentage`, the reminder dialog asks the user to connect power and leave it plugged in until the macOS update completes ([Issue #157](https://github.com/dan-snelson/DDM-OS-Reminder/issues/157); thanks, ebbg!)
    - New `MinimumBatteryPercentage` preference: integer `0`–`100`, script and `Resources/sample.plist` default `50`; `0` disables. A non-integer or out-of-range value logs `[WARNING]` and falls back to `50`.
    - New `BatteryWarningMessage` string (plus `BatteryWarningMessageLocalized_<code>` for `en`, `de`, `fr`, `es`, `pt`, `ja`, `nl`, and `it`) with the `{batteryPercentage}` placeholder, inserted through the new `{batteryWarningMessage}` placeholder.
    - `{batteryWarningMessage}` added after `{diskSpaceWarningMessage}` in `Message`, `AggressiveModeMessage`, and `PreDeadlineThresholdMessage`, and appended to `PastDeadlinePromptMessage` and `PastDeadlineForceMessage` (all localized variants included). Restart mode still suppresses the uptime and disk-space warnings but keeps the battery warning, because a restart does not charge the battery.
    - Detection uses positive evidence only from `pmset -g ps`: the warning appears only when the header reads `Now drawing from 'Battery Power'`, a charge parses from the `-InternalBattery-` line, and that charge is below the threshold. There is no warning on AC power (including `AC attached; not charging`), on UPS power, on Macs without an internal battery (desktops, VMs), or when the charge can't be read (logged at `[WARNING]`). The charge never comes from a UPS line.
    - Each run logs one `[NOTICE] Battery: power source <source>; internal battery <charge>|not present|unreadable; MinimumBatteryPercentage threshold <n>%; warning shown|suppressed|disabled` line.
    - Messaging only: `PastDeadlineRestartBehavior` `Prompt` / `Force` eligibility, timing, and suppression are unchanged.
    - Applied the same change to `Resources/reminderDialogPreferenceTest.zsh` and `Resources/createPlist.zsh`. The preference test helper adds `--battery-percentage <0-100>` to preview the warning on a desktop or AC-powered Mac; production `dor.zsh` never simulates power state.
    - When `assemble.zsh` imports a prior `.plist` / `.mobileconfig`, it prints an `ℹ️` line listing each imported template that lacks `{batteryWarningMessage}` (and adds it to **Recommended review items**); it never rewrites admin-authored copy.
    - The non-English `BatteryWarningMessageLocalized_<code>` strings are new and would benefit from native-speaker review.
- `Resources/diagnoseReminderState.zsh` (`1.4.0`) knows `MinimumBatteryPercentage` (flagged when outside `0`–`100`) and `BatteryWarningMessage`, so neither is reported as an unknown key, and it now lists the runtime `Battery:` and `Disk space:` lines under decision-related client-log lines.
- Fixed: when the Finder-aligned disk-space query failed, the fallback `[WARNING]` (and any `[ERROR]` for unreadable disk data) was attempted before the logging helpers were defined, so it was never written to the client-side log. Both are now logged right after the `Initiating …` preamble.
- **Upgrade note:** Deploy the updated `dor.zsh` before, or together with, any Configuration Profile that contains `{batteryWarningMessage}`; older scripts replace only the placeholders they know, so the dialog would show the literal text `{batteryWarningMessage}`. Customized `Message`, `AggressiveModeMessage`, `PreDeadlineThresholdMessage`, `PastDeadlinePromptMessage`, and `PastDeadlineForceMessage` strings (and their `Localized_<code>` variants) need `{batteryWarningMessage}` added by hand; without it, the warning never appears.

### Version 5.2.0b2 (16-Oct-2026)
- Client-side log entries now speak to Mac Admins: every run that shows no reminder ends with what happened, why no dialog appeared, and what to do next ([Issue #154](https://github.com/dan-snelson/DDM-OS-Reminder/issues/154))
    - `Normal DDM resolver result: status=…` is now `DDM update check: <plain-language outcome> (status=…; source=…; reason=…)`; `status=`, `source=`, and `reason=` tokens are unchanged for support and tooling.
    - `Resolver suppression summary: …` is replaced by `No reminder shown: …` followed by `Next step: …`, logged at the end of the run just before `Exiting …`. `missing` and up-to-date outcomes log at `[NOTICE]`; `conflict`, `noMatch`, `invalidVersion`, and unrecognized states keep `[WARNING]`.
    - Before: `Normal DDM resolver result: status=missing; source=none; reason=No DDM declaration candidates found in install.log` … `MDM fallback requirement is not configured; preserving normal DDM resolver status 'missing'.` After: `DDM update check: no DDM-enforced macOS update found (status=missing; …)`, `DDM Emergency Fallback not configured (dor-fallback-declaration.plist absent); nothing to fall back to`, `No reminder shown: this Mac has no DDM-enforced macOS update pending (…)`, and `Next step: If an update should be enforced, confirm this Mac is in scope of a DDM software-update declaration in your MDM, then search '/var/log/install.log' for 'EnforcedInstallDate'.`
    - Each unresolved state names its own next step (scope to one declaration, correct the target version, confirm the version is offered in Software Update, or configure a DDM Emergency Fallback). `reason=` text drops internal terms such as "declaration candidates", and `Resolver context:` lines are now `install.log context:`.
    - `conflict` now says which kind: two different declarations, an available update that does not match the declared version, or `softwareupdated found no update to enforce, yet DDM-enforced macOS <version> is still declared` (previously `Declaration persisted after 'No updates found for DDM to enforce'`), each with a matching next step. When installed macOS already meets the declared version and the conflict is either `softwareupdated` finding nothing to enforce or `softwareupdated` offering a different (for example, newer major) update, the outcome is `[NOTICE] No reminder shown: macOS <installed> already meets DDM-enforced macOS <version>; …` with a `Next step: None; …`; suppression and `status=conflict` are unchanged. Two different declarations always stay `[WARNING]`.
    - Up-to-date Macs now log `No reminder shown: macOS <installed> already meets DDM-enforced macOS <version>` with `Next step: None; this Mac is up to date.`
    - Display-window, periodic, Update Tonight, quiet-period, and presentation exits now log `[QUIT] No reminder shown: …` naming the controlling preference (`DaysBeforeDeadlineDisplayReminder`, `OutsideDisplayWindowPeriodicReminderDays`, `QuietPeriodMinutes`, `MeetingDelay`) plus when the reminder returns. Missing swiftDialog, non-root, no console user, and overlapping-run exits name a next step in the same `[FATAL ERROR]` line.
    - Demo mode now logs that it ignores DDM state and always shows a sample reminder, even on an up-to-date Mac.
    - Other everyday lines are shorter and plainer:
        - `Installed macOS Version: …` and `Installed macOS Build: …` are combined into `Currently installed macOS <version> (<build>)`.
        - `Current Logged-in User: …` and `Current Logged-in User First Name (ID): …` are combined into `Current Logged-in User: <user>, <first name>, <UID>`; while waiting for a console user, `Logged-in User Counter:` names the current console user.
        - The three `Resolved DDM declaration source/version/enforcement date` lines and the raw `Resolved declaration context: …` install.log line (declaration key, details URL, and all) are replaced by `[INFO] DDM declaration logged by softwareupdated at <timestamp> (<source>)`; version and declared deadline are on the `DDM update check:` line.
        - `install.log context:` lines drop the computer name and process ID.
        - `Software Update handoff: requirementSource=…; normalResolverStatus=…; target=…; deadline=…; action=…` is now `Opening Software Update for <user> to install macOS <version> (deadline <effective deadline>; source=…; status=…)`.
        - `Resolved DailyReminderTimes`, `Resolved MinutesBeforeDeadlineReminderSchedule`, and the dialog-language decision now log at `[PRE-FLIGHT]`; the language decision is logged once per run unless it changes.
    - Runtime and deployment logs say "DDM Emergency Fallback" (matching the documentation) instead of "MDM fallback requirement". Rejected Parameters 5 and 6 log a `Next step:` with the expected format.
    - No changes to reminder timing, DDM trust rules, suppression decisions, preferences, or log format `<scriptName> (<version>): <timestamp> - [<level>] <message>`.
- `Resources/diagnoseReminderState.zsh` (`1.3.0`) reads both `DDM update check:` and earlier `Normal DDM resolver result:` lines, both `Currently installed macOS` and earlier `Installed macOS Version` / `Build` lines, and both logged-in user formats (for redaction), so logs from older clients still diagnose
    - The **Client-log runs** outcome column now shows the run's `No reminder shown:` line or specific `[QUIT]` reason instead of the closing `Ticking away …` line every run ends with.
    - A generic `Mac` install.log computer name is no longer redacted, so plain-language lines such as "this Mac" stay readable.
- `MinimumDiskFreeGB` sample default (`Resources/sample.plist`, generated `.plist` / `.mobileconfig`) raised from `26` to `35` after a fully staged macOS update was observed at `Update Size: 26.60 GB`. The script default (`999`), `0`-disables behavior, and imported values from a prior `.plist` are unchanged.
- **Upgrade note:** Scripts, Extension Attributes, or log searches keyed on `Normal DDM resolver result`, `Resolver suppression summary`, `MDM fallback requirement`, `Version Comparison Result: No DDM enforcement log entry found`, `Installed macOS Version`, `Resolved DDM declaration`, or `Software Update handoff` must be updated; key on `DDM update check:`, `status=`, `No reminder shown:`, `Currently installed macOS`, `Opening Software Update`, and `DDM Emergency Fallback` instead.

### Version 5.2.0b1 (16-Oct-2026)
- `assemble.zsh` now accepts a prior `.mobileconfig` as well as a prior `.plist` for prior-configuration import, so a hand-edited Configuration Profile can be re-assembled without the generated `.plist` drifting out of sync ([Issue #153](https://github.com/dan-snelson/DDM-OS-Reminder/issues/153); thanks, @anewhouse!)
    - Works from the command line (`zsh assemble.zsh /path/to/prior.mobileconfig`) and the interactive drag-and-drop prompt; a `.mobileconfig` argument is no longer mistaken for an RDNN.
    - CMS-signed profiles are decoded with `security cms -D` before reading. No new dependencies: extraction uses `PlistBuddy -x`, so dotted preference domains work on macOS 14 and earlier.
    - `PayloadContent` is walked rather than assuming index `0`. Supported layouts: a `com.apple.ManagedClient.preferences` payload with a `*.dorm` domain (`Forced` preferred; `Set-Once` or `Often` used with a `⚠️` notice only when `Forced` is absent), or a payload whose `PayloadType` is the `*.dorm` domain (for example, iMazing Profile Editor), with `Payload*` metadata keys stripped.
    - Exactly one DDM OS Reminder domain is required. Missing, multiple, or ambiguous payloads fail with a clear `❌` message (for example, `❌ Prior mobileconfig contains multiple DDM OS Reminder preferences payloads (…)`), as do multiple `Forced` entries and files that are neither a profile nor a CMS envelope.
    - RDNN and deployment-lane inference use the original filename. New lane suffixes: `-<lane>.mobileconfig`, `-<lane>-unsigned.mobileconfig`, and `-<lane>-signed.mobileconfig`; near-miss filenames such as `…-prod-5.1.0.mobileconfig` print the existing warning.
    - Version metadata comes from the profile's `PayloadDescription` (`Configures DDM OS Reminder (<version>) …`), falling back to `PayloadDisplayName` (`DDM OS Reminder (<version>)`, as written by `Resources/createPlist.zsh`); profiles built elsewhere import with the existing best-effort `missing version metadata` warning.
    - RDNN is still inferred from the imported `ScriptLog`; a `⚠️` warning now flags a profile whose `*.dorm` domain disagrees with that RDNN (for example, a `createPlist.zsh` profile whose `ScriptLog` still uses the placeholder RDNN).
    - Extracted settings live in a `mktemp -d` directory under `$TMPDIR` (never `Artifacts/`), removed by an `EXIT` trap, including on Ctrl-C.
    - Supplying more than one prior `.plist` or `.mobileconfig` positional argument now fails with `❌ Only one prior .plist or .mobileconfig may be supplied …` instead of treating the extra path as an RDNN.
    - A prior `.plist` that is actually a Configuration Profile now adds a hint to rename it with a `.mobileconfig` extension. Otherwise, prior `.plist` import, messages, lane and RDNN inference, and generated output are unchanged.

### Version 5.1.0 (13-Oct-2026)
- Added a read-only client-state diagnosis helper and agent skill so Mac Admins can upload the client-side log, `/var/log/install.log`, and client-side `.plist` and get a fact sheet of effective settings, `install.log` declaration evidence, and the last run's recorded resolver result ([Issue #147](https://github.com/dan-snelson/DDM-OS-Reminder/issues/147))
    - `Resources/diagnoseReminderState.zsh` writes nothing. The client log's `Normal DDM resolver result` line is authoritative for what that Mac did. The fact sheet follows the `5.1.0` install.log timestamp rule and minute-threshold order, and it redacts usernames, `/Users` paths, install.log computer names, and labeled serial numbers.
    - Agent instructions live at `Resources/skills/diagnose-client-state/SKILL.md`, with links from `.github/skills`, `.agents/skills`, and `.claude/skills`.

- `All` and `Script` redeployments now keep `/Library/Management/<rdnn>/dor-state.plist`, so redeploying inside a `MinutesBeforeDeadlineReminderSchedule` window no longer shows an already-delivered pre-deadline threshold reminder again ([Issue #149](https://github.com/dan-snelson/DDM-OS-Reminder/issues/149))
    - Pre-deadline threshold delivery records and `UpdateTonightSuppressionUntil` carry across the redeploy; threshold records still reset automatically when the deadline/version signature changes.
    - Only `NextScheduledReminder` is cleared, so the refreshed heartbeat still evaluates reminders right after deployment (and a stale `FALSE` value cannot silence the Mac).
    - Deployment logs `[NOTICE]` when scheduler state is preserved and when `NextScheduledReminder` is cleared. An unreadable state file is logged at `[WARNING]` and left for the starter and runtime to quarantine.
    - `Script` now unloads and removes the current heartbeat LaunchDaemon before stopping the active runtime and clearing `NextScheduledReminder` (as `All` already did), so a heartbeat firing mid-redeploy can no longer relaunch the previous `dor.zsh` beside the replacement or overwrite the cleared schedule. The LaunchDaemon is recreated and loaded at the end of deployment as before.
    - **Upgrade note:** Only `Uninstall` removes `dor-state.plist`, matching the aggressive-mode kill switch `dor-aggressive-kill`.
- Replaced the percentage-based low-disk-space warning with a fixed GB threshold, so large disks no longer warn with hundreds of GB free and small disks no longer under-warn ([Issue #146](https://github.com/dan-snelson/DDM-OS-Reminder/issues/146); idea credit: @zte303, [DDM-Notify-Basic](https://github.com/zte303/DDM-Notify-Basic))
    - New `MinimumDiskFreeGB` preference (`Resources/sample.plist` default `26`, matching Apple's last published macOS upgrade requirement (Monterey: 26 GB); `0` disables) is compared against the existing Finder-aligned available-capacity value (`diskutil` fallback) in decimal GB, matching the displayed value.
    - `{diskSpaceHumanReadable}` and the infobox **Free Disk Space** line are unchanged.
    - Each evaluation logs `[INFO] Disk space: … free; MinimumDiskFreeGB threshold … GB; warning shown|suppressed`.
    - Applied the same change to `Resources/reminderDialogPreferenceTest.zsh` and `Resources/createPlist.zsh`.
    - **Upgrade note:** `MinimumDiskFreePercentage` is deprecated. When `MinimumDiskFreeGB` is not set, an existing `MinimumDiskFreePercentage` value is still honored and logged at `[WARNING]`; when both are set, `MinimumDiskFreeGB` wins and the legacy key is logged as ignored. Support will be removed in `6.0.0`. Regenerated configuration carries only `MinimumDiskFreeGB`.
    - Prior-plist import in `assemble.zsh` names the replacement instead of listing `MinimumDiskFreePercentage` as an unsupported key: `⚠️  Replaced deprecated MinimumDiskFreePercentage (10%) with MinimumDiskFreeGB (26 GB, sample default)`, or `⚠️  Dropping deprecated MinimumDiskFreePercentage (…%); keeping imported MinimumDiskFreeGB (… GB)` when the prior plist already has both (or `… imported MinimumDiskFreeGB '…' was invalid, using MinimumDiskFreeGB (26 GB, sample default)` when its value is outside `0`–`999`). When a prior plist carried `MinimumDiskFreePercentage`, production builds also list `MinimumDiskFreeGB` under **Recommended review items**.
- Prior-plist import in `assemble.zsh` now skips numeric values outside `0`–`999` (keeping the sample default and printing `⚠️  Skipping invalid integer value … (expected 0-999)`), matching the runtime, which already ignored them.
- Infobox **Deadline** now renders in red whenever **Day(s) Remaining** does, including the final ~12 hours before the effective deadline when **Day(s) Remaining** rounds to `0` (requires swiftDialog markdown-color support) ([Issue #143](https://github.com/dan-snelson/DDM-OS-Reminder/issues/143))
    - `Resources/reminderDialogPreferenceTest.zsh` applies the same highlighting, so `--pre-deadline-threshold` and `--aggressive` previews show **Deadline** and **Day(s) Remaining** in red.
    - Square brackets in a red-highlighted deadline (for example, from a custom `DateFormatDeadlineHumanReadable`) render as parentheses in the infobox **Deadline** and the red deadline enforcement sentence, so a literal `]` no longer ends swiftDialog's `:red[…]` markup early. Uncolored output is unchanged.

### Version 5.0.0 (04-Oct-2026)

> No preference keys, defaults, or precedence rules changed.

- Hardened DDM declaration trust. When `/var/db/softwareupdate/SoftwareUpdateDDMStatePersistence.plist` is readable, `install.log` declaration candidates must match a persisted active declaration's `TargetOSVersion` and `TargetLocalDateTime`.
    - Declarations that do not match are ignored and logged as `[WARNING] Ignoring N install.log DDM declaration(s) absent from softwareupdate DDM state`.
    - When no corroborated candidate remains, the resolver reports `missing`, which stays eligible for DDM Emergency Fallback.
    - When the plist is missing or has an unrecognized structure, resolution works as before and the runtime logs `[WARNING] softwareupdate DDM state is <unavailable|unrecognized> at '…'; trusting uncorroborated install.log declarations.`; `SECURITY.md` documents this as an accepted residual risk.
    - `Resources/JamfEA-Pending_OS_Update_Date.zsh` and `Resources/JamfEA-Pending_OS_Update_Version.zsh` apply the same corroboration.
- Added same-day reminder suppression after the user schedules the required update with **Update Tonight**. Normal reminders stop until local midnight once `/var/log/install.log` confirms that macOS accepted the request ([Issue #133](https://github.com/dan-snelson/DDM-OS-Reminder/issues/133)).
    - Detection requires daemon-side success evidence: `SUOSUInstallTonightManager: Queued … macOS <version>` must exactly match the active DDM (or DDM Emergency Fallback) target version, and a following `SUOSUScheduler: ARMED (… simulated=NO)` line must appear. The `Clicked to queue available updates for later` button event and untimestamped continuation lines (for example `ScheduleUpdateForLater = 1;`) are ignored, because the user can still cancel the authentication prompt.
    - Only `Queued` and `ARMED` evidence logged by `softwareupdated` is accepted. Evidence from other senders is skipped and logged at `[NOTICE]`, and invalidating lines from any sender still fail closed.
    - Evidence must be from the current local day and newer than the last boot. Any later disarm, dequeue, `Updated install tonight state (enabled = false …)`, different-version queue, or unrecognized `SUOSUScheduler:` / `SUOSUInstallTonightManager:` line fails closed, and the invalidating line is logged at `[NOTICE]`.
    - Pre-deadline threshold reminders, past-deadline aggressive mode, and Force mode bypass suppression. Suppression does not apply when the effective deadline is at or before local midnight, because DDM enforcement would come before the overnight installation window.
    - Suppressed runs schedule the first `DailyReminderTimes` slot after midnight, or an earlier pending pre-deadline threshold. Expiration never forces an immediate dialog.
    - Starter-launched runs record `UpdateTonightSuppressionUntil` in `dor-state.plist` and log `[NOTICE]` when suppression activates, expires, or is cleared. Manual and demo runs do not write scheduler state.
- swiftDialog now runs from its root-owned app bundle (`/Library/Application Support/Dialog/Dialog.app/Contents/MacOS/dialogcli`) instead of `/usr/local/bin/dialog`. `/usr/local` and `/usr/local/bin` were removed from the `PATH` of the runtime, the deployer, `dor-starter.zsh`, and the LaunchDaemon.
    - swiftDialog validation now reinstalls when the installed version cannot be read, instead of treating an empty version as current.
    - A swiftDialog Team ID verification failure is now logged as `[FATAL ERROR]` with the expected and received Team IDs, and the error dialog appears in the console user's session.
- Hardened runtime temporary-file handling. Each reminder run now creates a per-run, root-owned `/var/tmp/dorm.XXXXXX` directory (named after the runtime's `organizationScriptName`), mode `0755` so swiftDialog can read it as the console user. Downloaded icons, the swiftDialog command file (passed with `--commandfile`), and the threshold-refresh marker live in that directory, and every exit path, including fatal errors, removes it. A missing `dialogcli` is detected before the directory is created or icons are downloaded.
    - The runtime no longer writes fixed names such as `/var/tmp/icon.png`, `/var/tmp/overlayicon.png`, or `/var/tmp/dialog.log`.
    - The runtime no longer deletes the default swiftDialog command file used by other swiftDialog workflows.
    - Concurrent root runs no longer share icon or command files.
- Hardened console-user handling.
    - The runtime now waits for a console user other than `loginwindow`, `_mbsetupuser`, or `root`, so a Mac still in Setup Assistant no longer resolves `_mbsetupuser` as the dialog target. The deployer's Team ID error dialog and `Resources/reminderDialogPreferenceTest.zsh` also skip `_mbsetupuser`.
    - The **Info** button URL and the System Settings activation now open in the console user's session with `launchctl asuser`, instead of `su -` with an interpolated shell command.
    - The wait for System Settings after **Open Software Update** is bounded to 30 seconds, so a blocked or crashed System Settings can no longer hold `dor.pid` and stop all later reminders until reboot.
    - The macOS icon download now has a 10-second `--max-time`.
- Fixed `DailyReminderTimes` values that mix valid and invalid entries (for example, `8:00,17:00`) resolving to no baseline reminder slots. The invalid-entry warning text was captured into the resolved value instead of the log, so the valid `17:00` entry was dropped, the `08:00,12:00,16:00` default was not applied, and **Remind Me Later** fell through to the first pre-deadline threshold ([Issue #139](https://github.com/dan-snelson/DDM-OS-Reminder/issues/139); thanks, @TechTrekkie!)
    - Invalid entries are now logged as `[WARNING] Ignoring invalid DailyReminderTimes entry '…'` and skipped, valid entries are kept, and a fully invalid value still falls back to the default with the existing `defaulting to '…'` warning.
    - Affected standalone and deployed runs alike; deployed `dor.zsh` additionally lost the warning line entirely because it logs through the LaunchDaemon's standard output.
    - `HH:MM` still requires zero-padded hours; `8:00` is rejected (and now logged), not normalized.
    - Applied the same fix to `MinutesBeforeDeadlineReminderSchedule`, where mixed input such as `45,abc` previously disabled all pre-deadline threshold reminders.
    - Applied the same fix to `Resources/reminderDialogPreferenceTest.zsh`.
- Fixed baseline reminder-slot resolution skipping an entire day of `DailyReminderTimes` slots when a run occurred after 23:00 on the night before a spring-forward DST transition; next-day slots now resolve by calendar day instead of adding 86,400 seconds, which also covers Update Tonight suppression scheduling and preserves configured `00:00` slots ([PR #137](https://github.com/dan-snelson/DDM-OS-Reminder/pull/137) review; thanks, Copilot!)
- Hardened language-code handling for localized dialog text and deadline date formats.
    - Unrecognized language values now fall back to English and the global `DateFormatDeadlineHumanReadable`, and log a `[WARNING]`.
    - Localized preference key names are validated before they are applied; keys with an unrecognized language code are skipped and logged at `[WARNING]`.
    - Applied the same hardening to `Resources/reminderDialogPreferenceTest.zsh`.
- Hardened deployment.
    - `dor.zsh` and `dor-starter.zsh` are written to adjacent temporary files, validated with `zsh -n`, and moved into place atomically, so the heartbeat can never launch a partially written script.
    - Deployment now changes ownership only of the organization directory and DDM OS Reminder's own runtime assets, instead of recursively running `chown` across `/Library/Management/<rdnn>`.
- **Upgrade note:** `All` and `Script` redeployments now keep the aggressive-mode support kill switch `/Library/Management/<rdnn>/dor-aggressive-kill` and log a `[NOTICE]`; only `Uninstall` removes it. Script Parameter 4 still defaults to `All` when blank; the in-script comment now says so.
- Hardened prior-plist import in `assemble.zsh`. An imported `ScriptLog` is now kept only when it is a plain absolute path (letters, digits, `.`, `_`, `-`, and `/`; no `..`, `.`, or empty segments) with a `<rdnn>.log` basename. An unsafe path logs `⚠️  Imported ScriptLog '…' is not a safe absolute path`, a mismatched basename logs `⚠️  Imported ScriptLog basename '…' does not match '<rdnn>.log'`, and both fall back to `/var/log/<rdnn>.log`.
    - Assembly refuses to write an unsafe `scriptLog` path into the generated script.
    - The assembled script is checked again with `zsh -n` after the final `scriptLog` rewrite; previously the only syntax check ran before it.
    - `assemble.zsh` now re-prompts on an invalid deployment-mode selection instead of defaulting to production, and exits when no selection can be read.
- `Resources/createSelfExtracting.zsh` (`2.4.0`) generated wrappers have these changes:
    - They extract into a private `mktemp -d` directory.
    - They forward all MDM script parameters, so Parameters 4–6 now reach the deployer: reset mode, DDM Emergency Fallback, and `Uninstall`.
    - They remove the extracted payload on exit.
    - **Upgrade note:** Parameter values that earlier wrappers ignored now take effect; review wrapper-based policy parameters before rollout.
- `Resources/Jamf-getDDMstatusFromCSV.zsh` (`1.4.0`) has four changes:
    - API credentials and bearer tokens reach `curl` through stdin configuration instead of process arguments.
    - Debug logs no longer include token responses.
    - Entered passwords are no longer stripped of quote characters.
    - Supplying the password as a positional argument now prints a warning.
- `Resources/monitorRemoteSession.zsh` (`1.1.1`) also recognizes swiftDialog processes launched from the app bundle path.

### Version 4.2.2 (30-Sep-2026)
- Fixed the DDM resolver holding `conflict` after a transient `No updates found for DDM to enforce` marker, even when `softwareupdated` later recovered the same declaration; the marker is now superseded by a later `Found product with requested PMV (<candidate version>)` line or an `Armed DDM activity scheduler for <date>: YES` line whose date matches the candidate `EnforcedInstallDate` ([Issue #134](https://github.com/dan-snelson/DDM-OS-Reminder/issues/134))
    - Previously, suppression persisted until the marker aged out of the 4000-line `install.log` lookback window, so results depended on log volume.
    - A marker with no later recovery, a relapse marker after recovery, an `Armed ... YES` line for a different deadline, or a PMV match for a different version still fails closed with `conflict`.
- Added `[NOTICE]` logging when a `No updates found for DDM to enforce` marker is superseded, and `conflict` suppression caused by the marker now logs the marker line as `Resolver context:` instead of an unrelated `Removed 0 invalid declarations` line.
- Aligned `Resources/JamfEA-Pending_OS_Update_Date.zsh` and `Resources/JamfEA-Pending_OS_Update_Version.zsh` with the updated resolver so inventory stops reporting `conflict` for recovered declarations.

### Version 4.2.1 (30-Sep-2026)
- Fixed `InfoButtonText=hide` also suppressing `{supportAssistanceMessage}` when `HideSupportAssistanceMessage` was `false`; `HideSupportAssistanceMessage` is now the sole control for the `(?)` button guidance in both runtime and preference-test preview paths ([Issue #132](https://github.com/dan-snelson/DDM-OS-Reminder/issues/132); thanks for the heads-up, @shiftybird!)
    - **Upgrade note:** Deployments that relied on `InfoButtonText=hide` to hide the support assistance text should set `HideSupportAssistanceMessage=true`.
- Updated `assemble.zsh --interactive` so answering `NO` to the `Info Button` prompt defaults `Hide Support Assistance Message` to `YES`, preserving prior generated output, and clarified that the `(?)` help message button remains.

### Version 4.2.0 (21-Sep-2026)
- Updated URL for `organizationOverlayiconURL`
- Bounded padded enforcement-date resolution by wall-clock time so endpoint sleep or process suspension cannot extend the configured five-minute wait.
- Updated padded enforcement-date timeout logging to report actual wall-clock elapsed time and the configured maximum.
- Clarified active DDM Emergency Fallback display logging so `[NOTICE]` records fallback selection and `[WARNING]` records fallback activation only when the selected fallback reaches reminder display.
- Broadened DDM Emergency Fallback eligibility so a validated administrator requirement can cover normal resolver states `missing`, `conflict`, `noMatch`, and `invalidVersion`, while confirmed DDM still wins and unknown states fail closed. ([Issue #129](https://github.com/dan-snelson/DDM-OS-Reminder/issues/129))
- Preserved original resolver status, source, and reason through fallback evaluation; removed premature resolver-level quit logging and added explicit fallback-decision records.
- Renamed active operator guidance from “Missing-DDM Emergency Fallback” to “DDM Emergency Fallback” and documented that pending-update Extension Attributes continue reporting native DDM resolver health.
- Added an explicit macOS 27 icon ([Issue #127](https://github.com/dan-snelson/DDM-OS-Reminder/issues/127))
- Updated the preference-test preview helper to use the same macOS 27 icon mapping as runtime dialog rendering.

### Version 4.1.0 (14-Aug-2026)
- Fixed controlled `All`, `Script`, and `Uninstall` reset flows so a PID-validated active DDM OS Reminder runtime and its owned descendants receive a termination request before runtime assets are removed, preventing older reminder dialogs from surviving redeployment alongside the replacement version.
- Added runtime termination traps and owned swiftDialog/threshold-monitor cleanup so current deployments exit cleanly when controlled redeployment stops an active run, without broadly terminating unrelated swiftDialog processes.
- Hardened assembly so source lines containing backslash escapes remain byte-faithful in generated deployment scripts, and made embedded-runtime drift or syntax failures block artifact generation.
- Added explicit normal-resolver status/source/reason logging before fallback evaluation, plus distinct fallback evaluation, update-required contribution, actual reminder activation, and Software Update handoff records.
- Limited the decisive Missing-DDM fallback selection warning to actual reminder display; compliant Macs now log that fallback evaluation did not drive a reminder.
- Added fallback version/deadline/source logging after deployment writes the validated plist, and classified swiftDialog exit code `15` as external termination rather than user interaction.
- Documented collection of current and rotated `install.log` files for update-causality reviews and distinguished Apple declaration-selection `fallback` wording from DDM OS Reminder's Missing-DDM Emergency Fallback.
- Added an opt-in Missing-DDM Emergency Fallback using Script Parameters 5 and 6, with strict fail-closed validation, atomic RDNN-scoped plist persistence, exact-`missing` resolver eligibility, confirmed-DDM precedence, and direct past-deadline evaluation. ([Issue #120](https://github.com/dan-snelson/DDM-OS-Reminder/issues/120))
- Hardened LaunchDaemon installation for macOS 27 by validating a fresh adjacent temporary plist, atomically replacing the target, removing only `com.apple.quarantine`, and failing deployment when bootstrap or label-specific verification fails. ([Issue #117](https://github.com/dan-snelson/DDM-OS-Reminder/issues/117))
- Added actionable runtime heartbeat recovery logging for missing, quarantined, or unloadable LaunchDaemon plists without changing trust metadata outside the controlled installer path.
- Updated `Resources/monitorRemoteSession.zsh` to report LaunchDaemon quarantine state and documented fleet audit plus targeted remediation guidance.
- Fixed interactive assembly so custom `InfoButtonText` values also update `InfoButtonTextLocalized_en`, preventing stale sample English text from overriding admin-entered button labels. ([Issue #118](https://github.com/dan-snelson/DDM-OS-Reminder/issues/118); thanks for the heads-up, @macpancakes!)
- Added `Resources/JamfEA-DDM-OS-Reminder-Next-Scheduled-Reminder.zsh` so Jamf Pro administrators can inventory the device-local `NextScheduledReminder` value as a Date Extension Attribute, with documented sentinel dates for non-date scheduler states.

### Version 4.0.0 (09-Jul-2026)
- Reworked daemon orchestration so `/Library/LaunchDaemons/<rdnn>.dor.plist` now runs lightweight `dor-starter.zsh` every 60 seconds instead of launching the main reminder script directly.
- Added runtime scheduler assets `/Library/Management/<rdnn>/dor-starter.zsh`, `dor-state.plist`, and `dor.pid`, with `NextScheduledReminder` / `DaemonLastTriggered` state managed through `PlistBuddy`.
- Added `DailyReminderTimes` preference (`HH:MM` CSV, local time) so baseline reminder slots are admin-controlled through deployed `.plist` / `.mobileconfig` content, with default `08:00,12:00,16:00`.
- Added `MinutesBeforeDeadlineReminderSchedule` preference (`45,30,15,10,5` by default) for discrete final-minute reminders before the effective DDM enforcement deadline, with per-threshold delivery state stored in `dor-state.plist`.
- Added pre-deadline threshold dialog copy keys, localized sample strings, preview support, and quiet-period bypass logic so configured 45/30/15/10/5-minute reminders are not suppressed by earlier interactions.
- Added plist-backed timing controls for quiet-period suppression, outside-window periodic reminders, secondary-button disable/hide behavior, and past-deadline Force-mode restart cadence: `QuietPeriodMinutes`, `OutsideDisplayWindowPeriodicReminderDays`, `DisableButton2InsteadOfHide`, `PastDeadlineRestartMinimumUptimeMinutes`, `PastDeadlineForceTimerSeconds`, and `PastDeadlineForceRedisplayDelaySeconds`.
- Added default-on past-deadline aggressive mode with `AggressiveModePastDeadlineHours`, `AggressiveModeFrequencyMinutes`, update-focused aggressive title/message localization, demo/preview support, exact redisplay scheduling through `dor-state.plist`, and support kill switch `/Library/Management/<rdnn>/dor-aggressive-kill`.
- Tightened aggressive-mode scheduling so daemon-managed reminder runs continue exact redisplay cadence even after the user clicks `Open Software Update`, preserving persistent prompting until compliance or support suppression.
- Added color-safe pre-deadline threshold emphasis placeholders so final-minute warning and action sentences render red on swiftDialog builds with markdown color support.
- Added automatic refresh for open daemon-managed reminder dialogs when a configured final-minute threshold becomes due, closing the stale swiftDialog process and immediately queuing the latest due threshold reminder.
- Fixed post-dialog pre-deadline scheduling so if a threshold dialog remains open while later thresholds pass, the latest due threshold is queued immediately instead of falling back to the baseline schedule.
- Hardened runtime scheduler state handling so malformed `dor-state.plist` files are logged, quarantined, and recreated instead of causing the heartbeat to relaunch `dor.zsh` every 60 seconds.
- Updated `Resources/reminderDialogPreferenceTest.zsh` to warn when runtime scheduler state cannot be inspected instead of reporting unreadable `dor-state.plist` values as unset.
- Fixed rendered deadline punctuation so relative times such as `Today, 5:50 a.m.` do not gain a duplicate period when managed copy adds sentence punctuation after the deadline placeholder.
- Updated runtime scheduling to honor exact quiet-period redisplay times, while keeping direct/manual/demo runs from mutating daemon scheduler state.
- Updated `All`, `LaunchDaemon`, and `Uninstall` reset paths to unload and remove every discovered DDM OS Reminder LaunchDaemon plist before recreating the current heartbeat daemon, while reporting absent runtime assets separately from removed files.
- Added an `assemble.zsh` source-version guard so artifacts fail fast when the wrapper, assembler, and embedded `reminderDialog.zsh` versions are out of sync.
- Updated `Resources/sample.plist`, `Resources/reminderDialogPreferenceTest.zsh`, `README.md`, `Resources/README.md`, and `AGENTS.md` to document the heartbeat starter architecture and new `dor-` runtime asset names.
- Updated deadline display placeholders and infobox `Deadline` / `Day(s) Remaining` values to follow the effective enforcement deadline, including trusted padded enforcement dates, so reminder copy matches macOS managed-update notifications.

### Version 3.3.0 (21-May-2026)
- Added localization-surface filtering to `assemble.zsh` and `Resources/createPlist.zsh`, with support for full output, `--minimal` output (base keys plus English localized keys), and `--languages <csv>` subset generation for leaner `.plist` and `.mobileconfig` artifacts. (Addresses Issue #100)
- Extended `assemble.zsh --interactive` with localization artifact selection prompts, and pruned imported localized keys that fall outside the selected artifact mode so prior-plist upgrades stay explicit and predictable.
- Shortened skipped-localization import logs to a concise count plus sample keys, and tightened `--minimal` filtering so it keeps exact `_Localized_en` keys without carrying English region variants such as `en_GB`.
- Fixed localized preference precedence and explicit-setting lookup so base values like `InfoButtonText=hide` now override localized variants, correctly hiding the info button in both preview and runtime paths. (Thanks for the heads-up, @James Anzaldua!)
- Added region-aware `DateFormatDeadlineHumanReadableLocalized_<code>` fallback support for exact locale and base language variants, and aligned preview/runtime relative deadline time formatting with the same resolved locale-aware date/time policy. (Thanks for the suggestion, @coalliera!)
- Restored localized dialog-text override precedence when both shared base keys and matching `*Localized_<code>` values are present, while preserving the `InfoButtonText=hide` sentinel in preview and runtime paths. (Thanks for the heads-up, @coalliera!)
- Hardened `install.log` resolver handling for stale invalid declarations by ignoring failed `SoftwareUpdateSubscriber` declaration attempts, accepting full timezone-offset timestamps (including `+05:30` forms), and preserving real active-conflict suppression only for surviving valid DDM evidence. (Addresses Issue #99)
- Replaced legacy lowercase placeholder modifier handling with explicit `{titleMessageUpdateOrUpgradeLower}` placeholders across runtime defaults, preview defaults, sample localization strings, and placeholder documentation.
- Preserved recent German localization casing improvements by keeping noun-form `macOS-Update` / `macOS-Upgrade` strings title-cased where grammar requires it.
- Added a natural Japanese sample deadline format override (`DateFormatDeadlineHumanReadableLocalized_ja`) so Japanese previews render native-looking dates and times instead of inheriting the English-shaped global format.

### Version 3.2.0 (01-May-2026)
- Expanded locale-aware runtime rendering in `reminderDialog.zsh` and `Resources/reminderDialogPreferenceTest.zsh` so relative deadlines, date/time strings, uptime duration text, and free-disk availability reflect the resolved dialog language instead of remaining partly English.
- Trimmed surrounding whitespace from localized deadline/time placeholders before building deadline messaging and infobox content, preventing stray spacing from breaking relative-deadline display and markdown highlighting.
- Refined the sample preference profile’s French (`fr`) translations for Issue #93, including dialog copy, support/help text, and past-deadline restart messaging.
- Resolve dynamic localized overrides through `plistKeyMap` before falling back to lowercasing the plist key prefix (thanks for the heads-up, @Tony Do!)
- Updated `Resources/reminderDialogPreferenceTest.zsh` usage output to document `--rdnn <your.reverse.domain.notation>`
- Added per-field support-contact visibility controls (Addresses Feature Request #95; thanks for the inspiring PR #94, @mattmothersbaugh!)

### Version 3.1.0 (06-Apr-2026)
- Updated `reminderDialog.zsh` to treat a resolved DDM `VersionString` as already compliant when it matches or trails the installed macOS product version, preventing false reminder suppression failures on Apple log patterns that omit a usable `BuildVersionString`.
- Updated `Resources/JamfEA-Pending_OS_Update_Date.zsh` and `Resources/JamfEA-Pending_OS_Update_Version.zsh` to treat a resolved DDM `VersionString` as already compliant when it matches or trails the current macOS product version, covering Apple log patterns where `BuildVersionString:(null)` omits a usable build match.
- Added internal `currentVersionOverride` and `currentBuildOverride` fixture hooks to the two pending-update Jamf Extension Attributes so remote feedback traces can be validated locally without editing the scripts.

### Version 3.0.1 (30-Mar-2026)
- Fixed DDM declaration resolution for newer macOS `softwareupdated` log patterns by recognizing `Found currently applicable declaration` entries and preferring the most recent declaration state before applying source priority. (thanks for the assist, @phillnz!)
- Updated `reminderDialog.zsh` plus the bundled Jamf Pending OS Update EAs so real pending updates continue to resolve correctly when stale older declaration lines still exist in the recent `install.log` window.

### Version 3.0.0 (29-Mar-2026)
- Hardened `reminderDialog.zsh` DDM resolution by replacing the old `EnforcedInstallDate | tail -n 1` heuristic with a recent-window resolver that:
    - prioritizes `default applicable declaration` and `Found DDM enforced install` over generic `EnforcedInstallDate` matches
    - suppresses the reminder when declaration state is missing, conflicting, invalid, or no longer maps to an available update
    - only accepts `setPastDuePaddedEnforcementDate` when it safely matches the resolved declaration
    - adds explicit suppression logging for `conflict`, `noMatch`, and invalid-version cases
- Added optional prior-plist import to `assemble.zsh --interactive`, allowing Mac Admins to reuse supported values from an earlier DOR `.plist` while still generating current-version artifacts from the current sample
    - Imported values are read with `PlistBuddy` against the current runtime preference-key map so older plist formatting differences do not affect import behavior
    - The documented upgrade-assist path is based on plists generated by DDM OS Reminder `2.2.0` or later; earlier DOR plists now warn and continue on a best-effort basis
    - Missing newer keys now remain at current defaults instead of being dropped during upgrade reuse
    - Passing a prior `.plist` path directly to `zsh assemble.zsh` now auto-enables the import flow and infers the RDNN and deployment lane from that plist when its filename is unambiguous, reducing the need for extra CLI flags during upgrades
    - Older supported plists without a `-dev`, `-test`, or `-prod` filename suffix still import, but continue to prompt for deployment mode because the prior lane cannot be inferred
    - `ScriptLog` is preserved only when the imported basename matches the current RDNN; otherwise it is rewritten to the current assembly path to avoid domain leakage from older/internal plists
    - Assembled-script `scriptLog` updates now follow the same resolved path as the generated plist so operator messaging and deployed runtime behavior stay aligned
- Updated free-disk-space reporting in `reminderDialog.zsh` to prefer Finder-aligned available capacity via `NSURLVolumeAvailableCapacityForImportantUsageKey`, improving visibility of purgeable space such as local Time Machine snapshots and iCloud-managed capacity. ([Pull Request #80](https://github.com/dan-snelson/DDM-OS-Reminder/pull/80); thanks, @huexley!)
    - Added sanity checks and automatic fallback to the previous `diskutil` path when the JXA/Foundation disk-space query returns invalid data, preserving safe reminder behavior on affected systems.
    - Retained percentage-based warning behavior while updating the human-readable free-space display to use decimal `GB` formatting that better aligns with macOS/Finder conventions.
- Consolidated localization coverage across runtime and config generation, including FR-25 parity plus ES/PT/JA support (`LanguageOverride`, localized key families, localized infobox labels, and restart/deadline/support-assistance copy paths).
- Expanded locale-aware deadline date rendering so `%a`/`%b` in `DateFormatDeadlineHumanReadable` follow the resolved dialog language (`de`, `fr`, `es`, `pt`, `ja`, fallback `en`) across standard, padded past-due, and demo-mode flows.
- Added an internal `installLogPathOverride` fixture-testing hook for local validation of `reminderDialog.zsh` and the bundled Jamf EAs.
- Updated `Resources/JamfEA-Pending_OS_Update_Date.zsh` and `Resources/JamfEA-Pending_OS_Update_Version.zsh` to use the same fail-closed trust model as the runtime resolver, while keeping Jamf inventory execution lightweight.
- Updated `Resources/README.md`, `Diagrams/`, and related diagram PNG exports to document the hardened resolver, fail-closed EA behavior, corrected `dorm.zsh` client-script paths, and current beta-series behavior.
- Updated `Resources/createPlist.zsh` and `Resources/sample.plist` for restart-policy plus localization-key parity, then regenerated release artifacts from merged source.
- Merged `main` (2.6.0) into `3.0.0` while preserving `2.6.0` runtime behavior, including post-deadline restart workflow, KB support-assistance controls, and deadline/infobox urgency highlighting.

### Version 2.6.0 (01-Mar-2026)
- Added "Code Name: Yukon Cornelius" past-deadline restart workflow with `PastDeadlineRestartBehavior` values `Off`, `Prompt`, and `Force` ([Feature Request #75](https://github.com/dan-snelson/DDM-OS-Reminder/issues/75))
    - Added `DaysPastDeadlineRestartWorkflow` thresholding and a fixed 75-minute uptime minimum before restart workflow is activated
    - Added notice-level observability logs for both restart-workflow activation and uptime-based suppression
    - Updated docs and sample configuration to align with restart-workflow behavior, including the 75-minute uptime requirement and `DaysOfExcessiveUptimeWarning=0` semantics
- Added `computeInfoboxHighlights()` to render `Deadline`, `Day(s) Remaining`, and `Last Restart` as `:red[...]` when supported by swiftDialog markdown color
- Updated `assemble.zsh --interactive` to include a `Knowledge Base ('YES' to specify; 'NO' to hide)` prompt so Mac Admins can hide KB references without manual edits (`InfoButtonText`, `HelpImage`, and `HelpMessage` KB row) ([Feature Request #74](https://github.com/dan-snelson/DDM-OS-Reminder/issues/74); thanks for the idea, Adam!)
- Updated `assemble.zsh --interactive` to prompt for `PastDeadlineRestartBehavior` (`Off` / `Prompt` / `Force`) and conditionally prompt for `DaysPastDeadlineRestartWorkflow` when restart behavior is enabled, then stamp those values into generated `.plist` and `.mobileconfig` artifacts
- Updated `Force` mode restart execution to use root-level `sleep 1 && shutdown -r now &` for stronger enforcement reliability on managed macOS systems
- Added `SupportAssistanceMessage` placeholder/key so KB-disabled assemblies can suppress `(?)` button guidance without brittle `Message` regex rewrites

### Version 2.5.0 (19-Feb-2026)
- Enhanced `detectStagedUpdate` to read staged proposed macOS version/build metadata from `cryptex1/proposed` and confirm it matches the DDM-enforced version when available ([Feature Request #72](https://github.com/dan-snelson/DDM-OS-Reminder/issues/72))
- Updated staged metadata handling to normalize partially/fully staged states without proposed metadata to `Pending download`, so reminder flow continues and staging is re-evaluated on subsequent runs
- Updated reminder body text to use swiftDialog markdown color rendering so the automatic restart/update deadline sentence is displayed in red
- Added runtime fallback so older swiftDialog versions render the same enforcement sentence without color markdown
- For environments that override `Message` via Configuration Profile, redeploy an updated profile that includes `{deadlineEnforcementMessage}` to enable the new red/compatibility behavior
- Added relative deadline rendering (`Today` / `Tomorrow`) for enforcement messaging while preserving existing absolute deadline placeholders

### Version 2.4.0 (06-Feb-2026)
- Added space-delimited list of `acceptableAssertionApplicationNames` ([Feature Request #67](https://github.com/dan-snelson/DDM-OS-Reminder/issues/67); thanks for the suggestion, @yassermkh!)
- Added Dark Mode Overlay Icon [Feature Request #62](https://github.com/dan-snelson/DDM-OS-Reminder/issues/62) (thanks for the suggestion, @cyberotterpup!)
- Added DDM version validation to suppress reminders on invalid VersionString formats (thanks for the idea, @nessts!)
- Added deployment mode selection [ --dev | --test | --prod ] to `assemble.zsh` for improved artifact clarity during assembly
- Added `quitkey` option to swiftDialog invocation to allow users to dismiss the dialog via keyboard shortcut (thanks for the suggestion, @Jadah!)

### Version 2.3.1 (28-Jan-2026)
- Refactored `installedOSvsDDMenforcedOS()` to wait up to five minutes if `setPastDuePaddedEnforcementDate` is in the past

### Version 2.3.0 (19-Jan-2026)
- Refactored Update Required logic to address [Feature Request #55](https://github.com/dan-snelson/DDM-OS-Reminder/issues/55)
- Updated "Organization Variables" (i.e., removed redundant variable declarations)
- Refactored `OrganizationOverlayIconURL` logic to address [Bug Report #56](https://github.com/dan-snelson/DDM-OS-Reminder/issues/56) (thanks, @walkintom!)
- Added hard-coded `disableButton2InsteadOfHide` variable to disable `button2`, instead of only hiding it (Inspired by [Bug Report #58](https://github.com/dan-snelson/DDM-OS-Reminder/issues/58), thanks @ScottEKendall!)
- Updated `Resources/createPlist.zsh` to find the newest assembled script in `Artifacts/` (instead of a hard-coded `reminderDialog.zsh` file in `Resources/`) Thanks, Andrew!
- Updated `Resources/createSelfExtracting.zsh` to find the newest assembled script in `Artifacts/` (instead of a hard-coded `reminderDialog.zsh` file in `Resources/`) Thanks, Andrew!
- Replaced `defaults read` with PlistBuddy for prefs (Pull Request #61; thanks, @huexley!)

### Version 2.2.0 (06-Jan-2026)
- Added "quiet period" to skip reminder dialog if recently shown (Addresses [Feature Request #42](https://github.com/dan-snelson/DDM-OS-Reminder/issues/42))
- Added instructions for monitoring the client-side log to the log file itself
- `assemble.zsh` now outputs to `Artifacts/` (instead of `Resources/`)
- Updated `Resources/sample.plist` to address [Feature Request #43](https://github.com/dan-snelson/DDM-OS-Reminder/issues/43)
- Added Detection for staged macOS updates (Addresses [Feature Request #49](https://github.com/dan-snelson/DDM-OS-Reminder/issues/49))
- Refactored Configuration Profile-related code
- Refactored "Quiet Period" logic based on user-interaction via Return Code (rather than dialog display)

### Version 2.1.0 (13-Dec-2025)
- Added lowercase update-or-upgrade placeholder support ([Pull Request #26](https://github.com/dan-snelson/DDM-OS-Reminder/pull/26); thanks, @maxsundellacne!)
- Added logic to hide `button2` based on `DaysBeforeDeadlineHidingButton2` ([Pull Request #27](https://github.com/dan-snelson/DDM-OS-Reminder/pull/27); thanks, @maxsundellacne!)
- Refactored `resetConfiguration` function to avoid errors when attempting to `chmod` non-existent files
- Added warning for excessive uptime (configurable via `DaysOfExcessiveUptimeWarning` variable; [Issue #28](https://github.com/dan-snelson/DDM-OS-Reminder/issues/28))
- Added logic for when the reminder dialog is re-displayed after clicking the `infobutton` (based on if we're already hiding the secondary button; [Issue #31](https://github.com/dan-snelson/DDM-OS-Reminder/issues/31))
- Moved and renamed [`sample.plist`](Resources/sample.plist)
- Streamline Deployment & Documentation ([Feature Request #35](https://github.com/dan-snelson/DDM-OS-Reminder/issues/35))
- Addressed [Bugs #34](https://github.com/dan-snelson/DDM-OS-Reminder/issues/34) (thanks, @TechTrekkie!) and [#36](https://github.com/dan-snelson/DDM-OS-Reminder/issues/36) (I. Blame. AI.)
- Refactored `assemble.zsh` (thanks for the feedback, @Andrew!)
- Added warning for low disk space (configurable via `minimumDiskFreePercentage` variable; Feature Request #39. (Thanks for the suggestion, @prgsenright!)

### Version 2.0.0 (06-Dec-2025)
- Reorganized script structure for (hopefully) improved clarity
- Defined `swiftDialogMinimumRequiredVersion` (Addresses [Issue #16](https://github.com/dan-snelson/DDM-OS-Reminder/issues/16); thanks for the heads-up, @deski-arnaud!)
- Refactored `displayReminderDialog` function's Exit Code `3` to re-display dialog after 61 seconds when infobutton (i.e., KB) is clicked (Inspired by [Pull Request: #20](https://github.com/dan-snelson/DDM-OS-Reminder/pull/20); thanks, @TazNZ!)
- Refactored `daysBeforeDeadlineBlurscreen` logic to use seconds (instead of days) for more precise control (thanks for the suggestion, @Ancaeus!)
- Added a "demo" mode to the `reminderDialog.zsh` script for testing purposes (thanks for the suggestion, Max S!)
- Added ability to read variables from `.plist` ([Pull Request #22](https://github.com/dan-snelson/DDM-OS-Reminder/pull/22); thanks, Obi-@maxsundellacne!)

### Version 1.4.0 (18-Nov-2025)
- (Reluctantly) added swiftDialog installation detection
- Added `meetingDelay` variable to pause reminder display until meeting has completed ([Issue #14](https://github.com/dan-snelson/DDM-OS-Reminder/issues/14); thanks for the suggestion, @sabanessts!)
- Added `Resources/createSelfExtracting.zsh` script to create self-extracting version of assembled script
- Updated `Resources/README.md` to include "Assemble DDM OS Reminder" and "Create Self-extracting Script" instructions
- Re-re-refactored `installedOSvsDDMenforcedOS` to include @rgbpixel's recent discovery of `setPastDuePaddedEnforcementDate` (thanks again, @rgbpixel!)
- Added `daysBeforeDeadlineDisplayReminder` variable to better align with — or supersede — Apple's behavior of when reminders begin displaying before DDM-enforced deadline (thanks for the suggestion, @kristian!)
- Added `Resources/JamfEA-DDM_Executed_OS_Update_Date.zsh` script to report the date when the DDM-enforced macOS update was executed
- Removed placeholder `DDM-OS-Reminder End-user Message.zsh` from `ddmOSReminder.zsh`; use `Resources/assembleDDMOSReminder.zsh` to assemble your organization's customized script instead

### Version 1.3.0 (09-Nov-2025)
- Refactored `installedOSvsDDMenforcedOS` to better reflect the actual DDM-enforced restart date and time for past-due deadlines (thanks for the suggestion, @rgbpixel!)
- Refactored logged-in user detection
- Added fail-safe to make sure System Settings is brought to the forefront ([Pull Request #12](https://github.com/dan-snelson/DDM-OS-Reminder/pull/12); thanks, @techtrekkie!)
- Corrected an errant `mkdir` command that created an unnecessary nested directory (thanks for the heads-up, @jonathanchan!)
- Improved "Uninstall" behavior in `resetConfiguration` function to remove empty `organizationDirectory` (thanks for the suggestion, @Lab5!)

### Version 1.2.0 (20-Oct-2025)
- Addressed Issue #3: Use Dynamic icon based on OS Update version (thanks for the suggestion, @ScottEKendall!)
- Addressed Issue #5: Added logic to ignore Display Assertions 24 hours prior to enforcement (per [Apple's documentation](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/1/web/1.0))
- Added `softwareUpdateButtonText` variable, based on a minor-version "update" vs. a major-version "upgrade"
- Added `titleMessageUpdateOrUpgrade` variable for dynamic dialog title and message content

### Version 1.1.0 (16-Oct-2025)
> :warning: **Breaking Change** :warning:
>
> For users of version `1.0.0` _only_, please first uninstall version `1.0.0` **before** installing any later version via:
> 
> `resetConfiguration="${4:-"Uninstall"}"`
>
> Please feel free to reach out to the Mac Admins Slack [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel for assistance.
> 
> _Sorry for any Dan-induced headaches._

- Added `checkUserFocusDisplayAssertions` function to avoid interrupting users with Display Sleep Assertions enabled (thanks, @TechTrekkie!)
- Refactored `infobuttonaction` to disable blurscreen ([Pull Request #2](https://github.com/dan-snelson/DDM-OS-Reminder/pull/2); thanks, @TechTrekkie!)
- Updated `message` variable to clarify update instructions
- Tweaked `updateScriptLog` function to satisfy my CDO (i.e., the alphabetical version of "OCD")

### Version 1.0.0 (14-Oct-2025)
- First "official" release (thanks for the testing and feedback, @TechTrekkie!)
