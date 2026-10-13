---
name: diagnose-client-state
description: >
  Diagnose why a DDM OS Reminder dialog did not appear or appeared unexpectedly
  from uploaded client files. Use when a Mac Admin uploads the client-side log
  (/var/log/<rdnn>.log), /var/log/install.log, and a client-side .plist, or asks
  to triage resolver suppression, missing reminders, or DDM OS Reminder client
  state. Use when the user runs /diagnose-client-state.
---

# Diagnose DDM OS Reminder client state

Read-only. Do not write preferences, scheduler state, LaunchDaemons, or logs.

Mac Admins upload files from the affected Mac. Do not assume live access to that Mac.

## Required uploads

Ask for any of these that are missing:

1. Client-side log: `/var/log/<rdnn>.log`
2. `/var/log/install.log` (full copy is fine; analysis uses the last 4000 lines)
3. Client-side preferences, whichever exist:
   - `/Library/Managed Preferences/<rdnn>.dorm.plist`
   - `/Library/Preferences/<rdnn>.dorm.plist`

A single unlabeled plist is valid. Do not invent the other layer.

## Optional uploads

Use only when the admin includes them: `dor-state.plist`, `dor-fallback-declaration.plist`, `SoftwareUpdateDDMStatePersistence.plist`, `/Library/LaunchDaemons/<rdnn>.dor.plist`, and whether `/Library/Management/<rdnn>/dor-aggressive-kill` existed.

## Extract facts

When `zsh` and `PlistBuddy` are available, run:

```zsh
zsh Resources/diagnoseReminderState.zsh \
  --client-log <path> \
  --install-log <path> \
  --plist <path>
```

Label layers when both exist:

```zsh
zsh Resources/diagnoseReminderState.zsh \
  --client-log <path> \
  --install-log <path> \
  --managed-plist <managed-path> \
  --local-plist <local-path>
```

The helper is read-only. It prints a fact sheet. Preference ranges, plist key names, and `install.log` source-type markers live there; do not restate them here.

If the helper cannot run, read the three files and follow the same sections the helper prints. Treat `reminderDialog.zsh` `validatePreferenceLoad` / `resolveDDMEnforcementFromInstallLog` as the runtime source of truth.

## Rules

- The client log line `Normal DDM resolver result:` is what that Mac did.
- `install.log` explains that result. Do not invent a different resolver status.
- If the log and `install.log` evidence disagree, say they disagree and quote both.
- Without `SoftwareUpdateDDMStatePersistence.plist`, do not drop `install.log` candidates as uncorroborated. Quote client-log warnings about uncorroborated trust when present.
- `NextScheduledReminder` lives in `dor-state.plist`. If that file is missing, say it was not in the upload.
- `dor-starter.zsh` exits 0 with no new `dorm` run and no new log line in three cases: `NextScheduledReminder` is `FALSE`; `NextScheduledReminder` is `YYYY-MM-DD:HH:MM:SS` and that local time is still in the future; `dor.pid` names a live process. A missing `NextScheduledReminder` key lets the starter launch. An older healthy `dorm` run does not mean the heartbeat launched again.
- `--aggressive-kill yes` means `/Library/Management/<rdnn>/dor-aggressive-kill` existed, so aggressive mode uses the normal cadence until that file is removed.
- Read `dorm (<version>):` from the log. A later `dor  (` line (two spaces) is deployment, not the runtime run. This skill matches `reminderDialog.zsh` 5.1.0. If the version differs, say the checklist is best-effort.
- The helper redacts usernames, first names, `/Users/…` paths, install.log computer names, and labeled serial numbers in the fact sheet. Keep RDNN, versions, deadlines, and preference keys. Attach the redacted report. Keep raw uploads and the fact sheet out of public issues.

## Report

Write Markdown in this order:

1. Verdict in one sentence, from the last run: resolver suppression (`missing`, `conflict`, `noMatch`, `invalidVersion`), fallback selected, already compliant, outside the display window, quiet period, Update Tonight, meeting or Focus delay, threshold or aggressive dialog, dialog shown, fatal setup error, or not enough evidence.
2. Files received and files that were not in the upload.
3. Identity: RDNN, script version, installed macOS from the log.
4. Effective settings for the decision-critical keys in the helper table, with source and any rejected raw value.
5. DDM evidence from `install.log`, with timestamps.
6. What the last run did, quoted from the client log (redacted).
7. Whether the log and `install.log` agree.
8. Likely cause and operator next steps.
9. A line that the report is redacted and that raw uploads should stay out of a public issue.
