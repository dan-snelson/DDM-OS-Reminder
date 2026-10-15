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

Read-only against the affected Mac. Do not write preferences, scheduler state, LaunchDaemons, or logs. The only file this skill may write is the redacted findings Markdown, and only after the user confirms a path.

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

The helper is read-only. It prints a fact sheet that ends with a `## Report skeleton`. Preference ranges, plist key names, and `install.log` source-type markers live in the helper; do not restate them here. This skill matches the `diagnoseReminderState.zsh` 1.2.1 report skeleton.

If the helper cannot run, read the three files and build the report from the template below by hand. Treat `reminderDialog.zsh` `validatePreferenceLoad` / `resolveDDMEnforcementFromInstallLog` as the runtime source of truth.

## Rules

- The client log line `Normal DDM resolver result:` is what that Mac did. Quote it.
- `install.log` explains that result. Do not invent a different resolver status.
- If the log and `install.log` evidence disagree, say they disagree and quote both.
- Without `SoftwareUpdateDDMStatePersistence.plist`, do not drop `install.log` candidates as uncorroborated. Quote client-log warnings about uncorroborated trust when present.
- `NextScheduledReminder` lives in `dor-state.plist`. If that file is missing, say it was not in the upload.
- `dor-starter.zsh` exits 0 with no new `dorm` run and no new log line in three cases: `NextScheduledReminder` is `FALSE`; `NextScheduledReminder` is `YYYY-MM-DD:HH:MM:SS` and that local time is still in the future; `dor.pid` names a live process. A missing `NextScheduledReminder` key lets the starter launch. An older healthy `dorm` run does not mean the heartbeat launched again.
- `--aggressive-kill yes` means `/Library/Management/<rdnn>/dor-aggressive-kill` existed, so aggressive mode uses the normal cadence until that file is removed.
- Read `dorm (<version>):` from the log. A later `dor  (` line (two spaces) is deployment, not the runtime run. This skill matches `reminderDialog.zsh` 5.1.0. If the version differs, say the checklist is best-effort.
- The helper redacts usernames, first names, `/Users/…` paths, install.log computer names, and labeled serial numbers in the fact sheet. Keep RDNN, versions, deadlines, and preference keys. Attach the redacted report. Keep raw uploads and the fact sheet out of public issues.

## Report

Every report uses one format. Do not add, drop, rename, merge, or reorder sections.

1. Copy the helper's `## Report skeleton` block, from `<!-- report-skeleton:begin -->` to `<!-- report-skeleton:end -->`. Drop the two marker lines.
2. Fill only the `<!-- agent: … -->` slots: sections 1, 7, and 8, plus optional extra bullets in section 5. Replace each slot; do not leave comments behind.
3. Do not reformat, re-sort, trim, or re-word helper tables, bullets, or the section 9 sentence. If a helper row is wrong, say so in section 8; do not edit the row.

Template (helper-filled parts shown as `…`):

````markdown
# DDM OS Reminder diagnosis: `<rdnn>`

Analysis date: YYYY-MM-DD · Helper: `Resources/diagnoseReminderState.zsh` (1.2.1) · Checklist: `reminderDialog.zsh` 5.1.0

## 1. Verdict

**<Category>** (`<status>`). One or two sentences.

## 2. Files

| File | Status | Note |
|---|---|---|
…  fixed rows: Client log, `install.log`, Managed plist, Local plist (or Supplied plist (layer unknown)), `dor-state.plist`, `dor-fallback-declaration.plist`, `SoftwareUpdateDDMStatePersistence.plist`, LaunchDaemon plist, `dor-aggressive-kill`

## 3. Identity

| Field | Value |
|---|---|
…  RDNN, Runtime version, Deployment version, Installed macOS, Checklist match
- Helper notes: none | - Helper note: …

## 4. Effective settings

Precedence: …

| Plist key | Effective | Source | Flags |
|---|---|---|---|
…
- Deprecated keys: none | …
- Unknown keys: none | …
- Rejected localized keys: none | …

## 5. DDM evidence (`install.log`)

Window: … Corroboration: …

| First seen | Last seen | Version | Build | EnforcedInstallDate | Source types | Corroborated |
|---|---|---|---|---|---|---|
…
- Invalid declarations: …
- No updates found for DDM to enforce: …
- Recovery markers: …
- No-match markers: …
- Update Tonight softwareupdated lines: …
- (optional agent bullets)

## 6. Client-log runs

| Started | Script | Resolver result | Outcome |
|---|---|---|---|
…
Last run (YYYY-MM-DD HH:MM:SS):

```text
…
```

- Lines without a DDM OS Reminder prefix: …

## 7. Do the client log and `install.log` agree?

**Yes.** | **No.** | **Not comparable.** Up to three sentences.

## 8. Likely cause and next steps

### Likely cause

One short paragraph.

### Next steps

1. … (read-only)
2. …

## 9. Redaction

This report is redacted: usernames, first names, `/Users` paths, `install.log` computer names, and labeled serial numbers are removed. Keep the raw uploads and the helper fact sheet out of any public issue.
````

Verdict categories (pick exactly one, bold, sentence case): **Resolver suppression**, **Fallback selected**, **Already compliant**, **Outside the display window**, **Quiet period**, **Update Tonight**, **Meeting or Focus delay**, **Threshold dialog**, **Aggressive dialog**, **Dialog shown**, **Fatal setup error**, **Not enough evidence**. Follow with the recorded resolver status in backticks when the last run has one, for example **Resolver suppression** (`conflict`).

Style:

- Headings exactly as in the template, including numbers. Use `###` only for the two section 8 subheadings.
- Tables stay tables; never convert helper tables to bullets or bullets to tables.
- Full timestamps (`YYYY-MM-DD HH:MM` or as logged). Never short forms like `10-14`.
- US English spelling (labeled, honored, analyze).
- Backticks for preference keys, file names, paths, statuses, versions, and quoted log fragments.
- Bold only for the verdict category and the section 7 lead word.
- Quote log lines in `text` fenced blocks. Redact as the helper does.
- In section 8, mark inferences as inferences. Number next steps; put read-only checks first and end each with `(read-only)`.

After that report, ask the user whether to save the findings as a Markdown file. Do not write the file until the user confirms a path. Suggest `ddm-os-reminder-<rdnn>-<YYYY-MM-DD>.md` next to the uploads, outside this repository. Save only the completed report. Do not save the raw uploads or the rest of the helper fact sheet.
