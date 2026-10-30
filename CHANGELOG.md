# DDM OS Reminder

## Changelog

### Version 5.3.0 (29-Oct-2026)
- :new: A reminder that came due while the Mac slept could launch during a Maintenance DarkWake, before the network was ready. Both icon downloads then timed out (about 20 seconds), both icons fell back to the Finder icon, and the dialog waited on a sleeping or locked display until the user returned ([Issue #172](https://github.com/dan-snelson/DDM-OS-Reminder/issues/172); thanks, James Anzaldua!)
    - **DarkWake deferral:** `dor-starter.zsh` no longer launches `dor.zsh` while `pmset -g systemstate` lists `CPU` without `Graphics`. It logs `[NOTICE] DarkWake detected (system capabilities: …); deferring reminder launch to the next heartbeat.` and leaves `dor-state.plist` unchanged, including `LastBootReevaluation`, so the due reminder runs on the first heartbeat after a full wake. Unrecognized `pmset` output fails open and launches as before.
    - `dor.zsh` repeats the check just before it builds the dialog (after any `MeetingDelay` wait). A DarkWake run logs `[NOTICE] No reminder shown: the Mac is in a Maintenance DarkWake (system capabilities: …)` and, for starter-launched runs, schedules an exact `NextScheduledReminder` 60 seconds later instead of the next `DailyReminderTimes` slot. No mode bypasses this check, so pre-deadline threshold, aggressive, and Force reminders appear at the first full wake; a Force-mode timer can no longer count down to a restart on a display nobody can see. Demo mode is unchanged.
    - Force mode checks again before each redisplay in the same run and before a timer-driven restart, so a Force dialog that began during a full wake cannot redisplay or restart after the Mac enters a Maintenance DarkWake. The run logs `[NOTICE] Force restart redisplay deferred: the Mac is in a Maintenance DarkWake (system capabilities: …); no restart requested.` (or `Force restart timer expiry deferred: …`), requests no restart, and, for starter-launched runs, schedules an exact `NextScheduledReminder` 60 seconds later. Clicking **Restart Now** still restarts.
    - **Icon downloads:** `downloadBrandingAssets` waits up to 5 seconds for `scutil -r` to report the macOS icon host as reachable (if it never does, both downloads are skipped and the cache and fallbacks below apply), then downloads the overlay and macOS icons in parallel with `--connect-timeout 4 --max-time 10 --retry 1`. Only image content counts as success, so a captive-portal page is rejected. The curl error now appears in the `[ERROR] Failed to download …` line instead of on a separate raw line.
    - **Icon cache:** each successful download is copied to root-owned `/Library/Management/<rdnn>/dor-icon-macos-<major>.png` (`dor-icon-macos-default.png` when the major version is not numeric), `dor-icon-overlay-light.png`, or `dor-icon-overlay-dark.png` (not in demo mode). When a download fails, the cached copy is used. `All` and `Script` redeployments keep the cache; `Uninstall` removes it.
    - **Fallbacks:** with no download and no cache, the macOS icon falls back to `/System/Library/CoreServices/Software Update.app` (then `Finder.app`), and the dialog shows no overlay icon instead of the Finder icon. An empty `OrganizationOverlayIconURL` now also shows no overlay icon. `SwapOverlayAndLogo` keeps the macOS icon as the primary icon when no overlay icon is available. `Resources/reminderDialogPreferenceTest.zsh` previews the no-overlay and `SwapOverlayAndLogo` fallbacks; it still hands the macOS icon URL to swiftDialog, so it does not preview the `Software Update.app` fallback.
    - No changes to preference keys, defaults, or DDM trust rules.
    - Not covered: a locked screen or a sleeping display while the Mac is otherwise fully awake. These still show the reminder, which the user sees on return.
- :new: After a reboot, macOS can re-pad a past-due deadline to about one hour after login (`setPastDuePaddedEnforcementDate … (usersLoggedIn=1)`), but `dor-starter.zsh` kept exiting quietly until the stored `NextScheduledReminder`, so the new deadline and its pre-deadline thresholds could pass with no reminder ([Issue #165](https://github.com/dan-snelson/DDM-OS-Reminder/issues/165))
    - Once per boot, the first heartbeat that finds a console user other than `loginwindow`, `_mbsetupuser`, or `root` launches `dor.zsh` even when `NextScheduledReminder` is in the future. Heartbeats before login exit quietly, so the re-evaluation is not used up at the login window.
    - The starter records the boot in the new runtime-only `dor-state.plist` key `LastBootReevaluation` (the `kern.boottime` epoch) on any launch with a console user, and logs `[NOTICE] Starter launch after boot; re-evaluating deadline (NextScheduledReminder: …).`
    - The post-boot run re-resolves the deadline, including the existing wait of up to 5 minutes for a refreshed padded date. It then shows a reminder only when a pre-deadline threshold, aggressive mode, or Force mode is due, or when the stored schedule has come due. Otherwise it moves `NextScheduledReminder` earlier for a pending threshold or aggressive-mode start, never later, and logs `No reminder shown: post-boot re-evaluation found no reminder due`.
    - `NextScheduledReminder=FALSE`, `dor.pid` overlap protection, manual runs, and demo runs are unchanged. No changes to preferences, defaults, or DDM trust rules.
    - Not covered: logging out and back in without a reboot.
- **Fixed:** past-deadline aggressive mode was never scheduled when the next `DailyReminderTimes` slot came after the aggressive-mode start, leaving a Mac past its deadline without reminders until the next baseline slot (for example, overnight after a final pre-deadline threshold reminder at 16:25 for a 16:29 deadline) ([Issue #164](https://github.com/dan-snelson/DDM-OS-Reminder/issues/164))
    - The aggressive-mode start (effective deadline plus `AggressiveModePastDeadlineHours`) is now a scheduling candidate alongside pending pre-deadline thresholds and baseline slots. The earliest wins.
    - Applies after pre-deadline threshold reminders, after regular reminders shown between the deadline and the aggressive-mode start, and to quiet-period and Update Tonight scheduling, which aggressive mode already bypasses at runtime.
    - Skipped while `/Library/Management/<rdnn>/dor-aggressive-kill` exists; the next run re-evaluates once support removes it.
    - Runtime re-checks aggressive mode when the dialog returns. A reminder shown before the aggressive-mode start and answered after it now schedules `AggressiveModeFrequencyMinutes` from that answer. Before, a pre-deadline threshold reminder left open past the aggressive-mode start (for example, the 16:25 threshold answered at 18:31) waited until the next baseline slot, and other reminders waited for the quiet period. Logged as `(Scheduled aggressive-mode redisplay after late <n>-minute pre-deadline threshold acknowledgment)` or `(Scheduled aggressive-mode redisplay after return code <code>)`. The same re-check covers a dialog closed automatically for a pre-deadline threshold refresh but processed after the aggressive-mode start (for example, after sleep); a non-threshold dialog in that case logs `(Scheduled aggressive-mode redisplay after dialog auto-refresh for <n>-minute pre-deadline threshold)`.
    - Logged as `[NOTICE] Scheduled next daemon reminder for … (…: aggressive-mode start (<n> hour(s) past effective deadline))` or `(Quiet-period bypass for aggressive-mode start …)`.
    - No changes to preferences, defaults, DDM trust rules, or suppression rules.
- **Fixed:** a Mac that already met its DDM declaration could still evaluate the DDM Emergency Fallback when the resolver rated its state `conflict`. This happened when `softwareupdated` logged `No updates found for DDM to enforce` after the Mac installed its DDM-enforced update while install.log still showed the met declaration, or when `softwareupdated` offered a newer macOS (`Available descriptor <offered> disagrees with DDM declaration <version>`), for example macOS 27.0.1 with a 27.0.1 declaration while 27.2 is available. The run logged a `[WARNING]` and, when `dor-fallback-declaration.plist` existed, evaluated the fallback. A fallback targeting a newer macOS could then show a reminder for a version DDM does not enforce.
    - When the conflict is only `Declaration persisted after 'No updates found for DDM to enforce'` or `Available descriptor <offered> disagrees with DDM declaration <version>`, and the installed macOS meets that declaration, the resolver logs at `[NOTICE]` (`…; macOS <installed> already meets it`) instead of `[WARNING]`.
    - That case now skips fallback evaluation and logs `DDM Emergency Fallback not evaluated: macOS <installed> already meets DDM-enforced macOS <version> (DDM status=conflict)` when a fallback plist exists.
    - The run ends with `No reminder shown: macOS <installed> already meets DDM-enforced macOS <version>; softwareupdated has nothing left to enforce (status=conflict)` for a leftover declaration, or `No reminder shown: macOS <installed> already meets DDM-enforced macOS <version>; the different update softwareupdated offers (macOS <offered>) is not enforced by DDM (status=conflict)` for a different offered update. The different-offered-update outcome was previously logged only when no fallback was configured.
    - Resolver status stays `conflict`, so the `DDM update check:` line and both Pending-OS Extension Attributes are unchanged. A `conflict` between two different declarations, and `missing`, `noMatch`, and `invalidVersion`, still evaluate fallback.
    - No changes to preference keys, defaults, or scheduling.
- **Fixed:** a pre-deadline threshold reminder was recorded as delivered even when swiftDialog never showed it to the user (for example, `Return Code: 1` while macOS was shutting down), so a reminder the user never saw used up that threshold for the deadline
    - Only user-interaction return codes (`0`, `2`, `3`, `4`, `10`, the same codes that start the quiet period) and the open-dialog refresh now add a threshold to `PreDeadlineThresholdDelivered`.
    - Any other return code logs `[NOTICE] Pre-deadline threshold <n>-minute reminder not marked delivered; return code <code> is not a user interaction.` The next run shows that threshold if it is still the latest one due, or records it in `PreDeadlineThresholdSkipped` once a later threshold is due.
    - A starter-launched run then schedules an exact `NextScheduledReminder` 60 seconds later, logged as `[NOTICE] Scheduled next daemon reminder for … (Pre-deadline threshold <n>-minute reminder retry after return code <code>)`. Without the retry, a failed final threshold (for example, the 5-minute reminder) kept the schedule calculated before display, so the next reminder could wait until the aggressive-mode start.
    - The retry is skipped when it would land at or after the effective deadline, and for return code `9` (`SIGKILL`), which is usually a persistent block.
- **Fixed:** when a Mac woke from sleep after the effective deadline with a threshold reminder still open, the open-dialog check closed that reminder and nothing replaced it until the next scheduled run
    - Once the effective deadline has passed, the open reminder now stays on screen, logged as `[NOTICE] Pre-deadline threshold <n>-minute reminder became due while a reminder dialog was open, but the effective deadline has passed; leaving the open dialog in place.`
    - Before the deadline, a newly due threshold still closes the open dialog and shows the newer threshold reminder.
- **Fixed:** when swiftDialog exited with code `9`, the runtime logged `swiftDialog exited with code 9; confirm your .plist or .mobileconfig is installed:` and the expected preference paths. Code `9` does not mean missing preferences: `dialogcli` relays the signal number when `Dialog` is killed, so `9` is `SIGKILL`, usually from a code-signature or endpoint-security block. Admins with valid preferences were sent in the wrong direction.
    - The `[WARNING]` now reads `swiftDialog exited with code 9; Dialog was killed (SIGKILL) before <user> could respond, usually by a code-signature or endpoint-security block. Next step: …`, naming a `codesign --verify` check on `Dialog.app` and security or allowlisting tools. The `Expected managedPreferencesPlist` / `Expected localPreferencesPlist` `[INFO]` lines are removed from this path.
    - Exit handling is unchanged: the run still ends with code `9`, and the reminder is not marked as a user interaction.
    - No changes to preference keys, defaults, or scheduling.
- **Fixed:** `launchDaemonManagement.zsh` could report a failed swiftDialog install or upgrade as successful. It ignored the `installer` exit status, and after an upgrade it checked only that `dialogcli` existed, so a Mac that kept an older swiftDialog logged `swiftDialog version … installed; proceeding...` and finished deployment.
    - An `installer` failure now removes the temporary download and exits `1` with `[FATAL ERROR] swiftDialog installer failed for <url>`.
    - After installing, the script reads the `dialogcli` version again. It exits `1` with `[FATAL ERROR] swiftDialog version '<version>' after install; swiftDialog 3.1.0.4994 or newer is required.` when the version is empty or older than `swiftDialogMinimumRequiredVersion`.
    - The swiftDialog check runs before the reset, so a failed install leaves the existing deployment in place. Rerun the deployment once swiftDialog `3.1.0.4994` or later installs.
    - No changes to preference keys, defaults, or runtime behavior.
- :new: Re-assembling from a prior dev or test `.plist` / `.mobileconfig` into another lane carried its `Assembled` or `TEST` placeholder text into the new artifacts, so a dev configuration promoted with `--lane prod` still showed that text in the production `.plist` and `.mobileconfig` ([Issue #168](https://github.com/dan-snelson/DDM-OS-Reminder/issues/168))
    - `assemble.zsh` now rewrites its own leading lane marker (`Assembled`, legacy `Sample`, or `TEST`, optionally after leading `<br>` tags) in imported string values to match the selected lane: removed for `prod`, `TEST` for `test`, and `Assembled` for `dev`.
    - Matching is case-sensitive and anchored to the start of each value, so admin copy such as `Latest`, `Testing`, or `sample` elsewhere in a string is never changed.
    - Logged as `🧹 Normalized lane marker in <n> imported value(s) for '<lane>' lane`.
    - A prior file ending in `-dev.plist` or `-test.plist` still selects that lane automatically; pass `--lane prod` to promote it.
    - A valid `--lane` now skips filename lane inference regardless of argument order, so `--lane prod` after the file path no longer logs `🔎 Inferred deployment mode from prior plist: 'dev'` before `📦 Deployment Mode: prod`.
    - No changes to preference keys, defaults, or runtime behavior.
- **Fixed:** a missing or invalid `--lane` value (for example, `--lane production`) printed `Defaulting to interactive prompt.`, then re-parsed that value as a positional RDNN, so `assemble.zsh` could exit `0` with artifacts named for RDNN `production`. `assemble.zsh` now exits `1` with `❌ Invalid lane: '<value>'. Valid options: dev, test, prod` before importing or generating anything.
- :new: `Resources/diagnoseReminderState.zsh` (`1.6.5`) adds `--rdnn <rdnn>`, so a Mac Admin running the helper on the affected Mac no longer types up to nine paths ([Issue #166](https://github.com/dan-snelson/DDM-OS-Reminder/issues/166))
    - Each input that is not supplied is read from its live path: the effective `ScriptLog` (Managed, then Local) or `/var/log/<rdnn>.log`, `/var/log/install.log`, both `<rdnn>.dorm.plist` preference layers, `dor-state.plist`, `dor-fallback-declaration.plist`, `SoftwareUpdateDDMStatePersistence.plist`, the LaunchDaemon plist, and whether `dor-aggressive-kill` exists.
    - Explicit flags always win. An invalid RDNN exits `64`; a missing client log or `install.log` exits `66` and names the path. The supplied RDNN joins RDNN detection, so a mismatch is still reported as a `conflict`.
    - Missing optional files are reported as `not present on this Mac` (or `unreadable on this Mac`). A Mac with neither preference plist is reported with script defaults, which matches the runtime.
    - Fact-sheet and report-skeleton file statuses now read `supplied` (was `received`), `not in upload`, `inferred (--rdnn)`, `not present on this Mac`, or `unreadable on this Mac`.
    - The fact sheet's **Declaration candidates** table now groups identical `install.log` candidates into one row with first seen, last seen, and count, so a full `install.log` no longer produces hundreds of repeated rows. The fact-sheet title links to [snelson.us/ddm](https://snelson.us/ddm), and the report's redaction sentence says "raw client files" instead of "raw uploads".
    - `install.log` marker headings and report bullets now quote the log text they match (for example, `` `No updates found for DDM to enforce` lines: none ``), so an empty section reads as "this log line was not found" rather than as a verdict.
    - Report section 7 (**Do the client log and `install.log` agree?**) now opens with a helper table that puts the client log's last `DDM update check:` result (version, declared deadline, status, source) beside the latest `install.log` declaration span. Pre-`5.2.0` logs use their `Resolved DDM declaration` lines. The agent still writes the **Yes.** / **No.** / **Not comparable.** answer.
    - Report section 8 (**Likely cause and next steps**) now opens with recorded evidence from the last run: its outcome, the runtime's own `No reminder shown:` and `Next step:` text, the latest user action, the latest scheduling line, and `NextScheduledReminder`. The agent still writes the cause and next steps.
    - Non-root runs add a note that root-only files may be unreadable; run with `sudo`. The helper stays read-only, the RDNN is never auto-discovered, and redaction is unchanged.
- :new: `Resources/diagnoseReminderState.zsh` adds opt-in `--no-redaction`, so a Mac Admin diagnosing several Macs can tell the reports apart and match them to MDM records
    - Usernames, first names, `/Users` paths, `install.log` computer names, and serial numbers appear as logged. The fact-sheet header and report section 9 say the output is not redacted.
    - The fact-sheet and report-skeleton identity tables add **Computer name** and **Serial number** rows: from this Mac (`scutil --get ComputerName`, `IOPlatformSerialNumber`) with `--rdnn`, otherwise from the latest `install.log` computer name and a labeled client-log `Serial Number:` line.
    - The suggested report filename adds the computer name and `-unredacted`, for example `ddm-os-reminder-us.snelson-Mac-Lab-07-unredacted-2026-10-21-161500.md`.
    - With `--rdnn`, the full output is also saved to `/Library/Management/<rdnn>/…-unredacted-<timestamp>-fact-sheet.md` (mode `0600`). The helper never creates that directory; a missing, symbolic-link, non-root-owned, or unwritable directory still prints the fact sheet and exits `73`. Without `--rdnn`, nothing is saved.
    - Default runs are unchanged: redacted, and they write nothing.
- `Resources/diagnoseReminderState.zsh` follows the `5.3.0` runtime changes. Checklist updated to `reminderDialog.zsh` `5.3.0`; preference defaults are unchanged.
    - Reports `LastBootReevaluation` and describes the post-boot exception in its starter rule.
    - Includes `DarkWake` lines in the latest-run decision lines and describes the starter's DarkWake exit. A post-boot run's latest-run lines now start at the starter's `Starter launch after boot` line and include `Post-boot re-evaluation` lines, which earlier helper versions omitted.
    - Lists the macOS updates `softwareupdated` offered (`PrimaryDescriptor: … SU:` install.log lines), grouped by descriptor, version, and build with first seen, last seen, and count. A `conflict` from `Available descriptor <offered> disagrees with DDM declaration <version>` previously had no matching evidence in the fact sheet.
    - **Fixed:** the helper treated any script that shares `ScriptLog` and logs `<name> (<version>): … [PRE-FLIGHT] Initiating` as a DDM OS Reminder run. On a Mac where another script ran last, the fact sheet reported that script's name and version, no resolver status, and its outcome as the last run. The helper now takes the runtime script name from DDM OS Reminder log lines, counts only that script's runs and Return Codes, and names the other scripts in an identity note.
- **Fixed:** `Resources/createSelfExtracting.zsh` (`2.4.1`) with no `ddm-os-reminder-*.zsh` in `Artifacts/` ran a bare `ls -t`, so it could encode an unrelated file from the current directory instead of stopping. It now exits with `❌ Error: No file matching 'ddm-os-reminder-*.zsh' found in …`. Generated wrappers are unchanged.

### Version 5.2.0 (20-Oct-2026)
- New low-battery warning: when a Mac is running on its internal battery below `MinimumBatteryPercentage`, the reminder dialog asks the user to connect power and leave it plugged in until the macOS update completes ([Issue #157](https://github.com/dan-snelson/DDM-OS-Reminder/issues/157); thanks, ebbg!)
    - New `MinimumBatteryPercentage` preference: integer `0`–`100`, default `50`; `0` disables. Invalid values log `[WARNING]` and fall back to `50`.
    - New `BatteryWarningMessage` string (localized for `en`, `de`, `fr`, `es`, `pt`, `ja`, `nl`, and `it`) with a `{batteryPercentage}` placeholder, inserted through the new `{batteryWarningMessage}` placeholder in `Message`, `AggressiveModeMessage`, `PreDeadlineThresholdMessage`, `PastDeadlinePromptMessage`, and `PastDeadlineForceMessage`. Restart mode keeps the battery warning, because a restart does not charge the battery.
    - Shown only when `pmset -g ps` reports `Battery Power` and an internal-battery charge below the threshold; never on AC or UPS power, on Macs without an internal battery, or when the charge can't be read.
    - Each run logs one `[NOTICE] Battery: …` line with power source, charge, threshold, and whether the warning was shown.
    - Messaging only: `PastDeadlineRestartBehavior` `Prompt` / `Force` behavior is unchanged.
    - `Resources/reminderDialogPreferenceTest.zsh` adds `--battery-percentage <0-100>` to preview the warning on a desktop or AC-powered Mac.
    - `assemble.zsh` lists any imported message template missing `{batteryWarningMessage}` under **Recommended review items**; it never rewrites your copy.
    - Non-English battery strings are new and would benefit from native-speaker review.
- Client-side log entries now speak to Mac Admins: every run that shows no reminder ends with what happened, why, and what to do next ([Issue #154](https://github.com/dan-snelson/DDM-OS-Reminder/issues/154))
    - `Normal DDM resolver result: …` is now `DDM update check: <plain-language outcome> (status=…; source=…; reason=…)`; the `status=`, `source=`, and `reason=` tokens are unchanged.
    - `Resolver suppression summary: …` is replaced by `No reminder shown: …` and `Next step: …` at the end of the run. `missing` and up-to-date outcomes log at `[NOTICE]`; `conflict`, `noMatch`, `invalidVersion`, and unrecognized states stay `[WARNING]`.
    - Each unresolved state names its own next step (for example, scope to one declaration, correct the target version, or configure a DDM Emergency Fallback). `conflict` now says which kind of conflict occurred; when installed macOS already meets the declared version, it logs at `[NOTICE]` with `Next step: None`.
    - Up-to-date Macs log `No reminder shown: macOS <installed> already meets DDM-enforced macOS <version>`.
    - Display-window, periodic, Update Tonight, quiet-period, and meeting exits log `[QUIT] No reminder shown: …` naming the controlling preference and when the reminder returns. Fatal exits (missing swiftDialog, non-root, no console user, overlapping run) include a next step.
    - Demo mode logs that it ignores DDM state and always shows a sample reminder.
    - Routine lines are shorter and combined (installed macOS version/build, logged-in user, resolved declaration, Software Update handoff), and logs say "DDM Emergency Fallback" instead of "MDM fallback requirement".
    - No changes to reminder timing, DDM trust rules, suppression decisions, preferences, or log line format.
- `assemble.zsh` now accepts a prior `.mobileconfig` as well as a prior `.plist`, so a hand-edited Configuration Profile can be re-assembled without the generated `.plist` drifting out of sync ([Issue #153](https://github.com/dan-snelson/DDM-OS-Reminder/issues/153); thanks, @anewhouse!)
    - Works from the command line (`zsh assemble.zsh /path/to/prior.mobileconfig`) and the drag-and-drop prompt; signed profiles are supported.
    - The profile must contain exactly one DDM OS Reminder (`*.dorm`) preferences payload; `Forced` settings are preferred. Missing, multiple, or ambiguous payloads fail with a clear `❌` message.
    - RDNN and deployment lane are inferred as before; a `⚠️` warning flags a profile whose `*.dorm` domain disagrees with the RDNN in `ScriptLog`.
    - Supplying more than one prior `.plist` or `.mobileconfig` now fails instead of treating the extra path as an RDNN. Prior `.plist` import is otherwise unchanged.
- **Fixed:** `{minutesBeforeDeadline}` in `PreDeadlineThresholdMessage` showed the crossed threshold (for example, `45`) instead of the time actually left, overstating time remaining on late runs (padded deadline, heartbeat delay, wake from sleep, or manual run) ([Issue #160](https://github.com/dan-snelson/DDM-OS-Reminder/issues/160))
    - The placeholder now shows minutes remaining until the effective deadline, never above the crossed threshold; on-time runs still show the threshold value. Related `[NOTICE]` lines append `(<n> minute(s) remaining)`.
    - Known: copy reads `1 minutes` when one minute remains.
- **Fixed:** when the disk-space query failed, its fallback `[WARNING]` was never written to the client-side log.
- `MinimumDiskFreeGB` sample default (`Resources/sample.plist`, generated `.plist` / `.mobileconfig`) raised from `26` to `35` after a fully staged macOS update was observed at `26.60 GB`. The script default (`999`), `0`-disables behavior, and imported values are unchanged.
- `Resources/diagnoseReminderState.zsh` (`1.4.0`) reads both new and pre-`5.2.0` log lines, so logs from older clients still diagnose. It recognizes `MinimumBatteryPercentage` and `BatteryWarningMessage`, lists the runtime `Battery:` and `Disk space:` lines, and shows each run's `No reminder shown:` or `[QUIT]` reason in **Client-log runs**.
- Reviewed the bundled Jamf Pro Extension Attributes for `5.2.0`. The `5.2.0` client-side log changes do not affect them.
    - `JamfEA-Pending_OS_Update_Date.zsh`, `JamfEA-Pending_OS_Update_Version.zsh`, and `JamfEA-DDM-OS-Reminder-Next-Scheduled-Reminder.zsh` are now version `5.2.0`; their resolver and scheduler logic is unchanged.
    - **Fixed:** `JamfEA-DDM-OS-Reminder-User-Clicks.zsh` (`5.2.0`) also reported the unformatted `[INFO] … not re-showing dialog after <user> clicked …` line. It now reports only `[NOTICE]` `<user> clicked <button>` lines, and `/usr/local` was removed from its `PATH`.
    - **Fixed:** `JamfEA-Volume_Owners.zsh` reported every local cryptographic user; it now reports only users flagged `Volume Owner: Yes`.
    - `JamfEA-DDM_Executed_OS_Update_Date.zsh` (`5.2.0`): corrected its header and the `Resources/README.md` example to match its actual behavior and `YYYY-MM-DD HH:MM:SS` output (most recent matching `install.log` entry).
    - `JamfEA-SecureToken_Users.zsh` and `JamfEA-Volume_Owners.zsh` now run with `--no-rcs`, like the other bundled Extension Attributes.
- **Upgrade notes:**
    - Deploy the updated `dor.zsh` before, or together with, any Configuration Profile containing `{batteryWarningMessage}`; older scripts would show the literal placeholder. Customized message strings (and their `Localized_<code>` variants) need `{batteryWarningMessage}` added by hand, or the warning never appears.
    - Scripts, Extension Attributes, or log searches keyed on `Normal DDM resolver result`, `Resolver suppression summary`, `MDM fallback requirement`, `Version Comparison Result: No DDM enforcement log entry found`, `Installed macOS Version`, `Resolved DDM declaration`, or `Software Update handoff` must be updated; key on `DDM update check:`, `status=`, `No reminder shown:`, `Currently installed macOS`, `Opening Software Update`, and `DDM Emergency Fallback` instead.

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
