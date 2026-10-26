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

Read-only against the affected Mac. Do not write preferences, scheduler state, LaunchDaemons, or logs. The only file this skill may write is the findings Markdown, and only after the user confirms a path. Never add `--no-redaction` unless the Mac Admin asks for it.

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

### On the affected Mac

If the Mac Admin runs the helper on the affected Mac, `--rdnn` reads each input that is not supplied from its live path. Explicit flags still win, and `sudo` lets root-only files be read:

```zsh
sudo zsh Resources/diagnoseReminderState.zsh --rdnn <rdnn>
```

To track several Macs internally, the Mac Admin may add `--no-redaction`. With `--rdnn`, the helper then also saves its fact sheet as `/Library/Management/<rdnn>/ddm-os-reminder-<rdnn>-<computer-name>-unredacted-<YYYY-MM-DD-HHMMSS>-fact-sheet.md` (mode `0600`) and exits `73` if it cannot. That saved file is the helper's only write.

Treat the resulting fact sheet exactly like one built from uploads. Uploads stay the default; do not ask for live access.

The helper is read-only, apart from that opt-in save. It prints a fact sheet that ends with a `## Report skeleton`. Preference ranges, plist key names, and `install.log` source-type markers live in the helper; do not restate them here. This skill matches the `diagnoseReminderState.zsh` 1.6.3 report skeleton.

If the helper cannot run, read the three files and build the report from the template below by hand. Treat `reminderDialog.zsh` `validatePreferenceLoad` / `resolveDDMEnforcementFromInstallLog` as the runtime source of truth.

## Rules

- The client log line `DDM update check:` (`5.2.0` and later) or `Normal DDM resolver result:` (earlier) is what that Mac did. Quote it, along with any `No reminder shown:` and `Next step:` lines.
- `install.log` explains that result. Do not invent a different resolver status.
- If the log and `install.log` evidence disagree, say they disagree and quote both.
- Without `SoftwareUpdateDDMStatePersistence.plist`, do not drop `install.log` candidates as uncorroborated. Quote client-log warnings about uncorroborated trust when present.
- `NextScheduledReminder` lives in `dor-state.plist`. If that file is missing, say it was not in the upload.
- `dor-starter.zsh` exits 0 with no new `dorm` run and no new log line in three cases: `NextScheduledReminder` is `FALSE`; `NextScheduledReminder` is `YYYY-MM-DD:HH:MM:SS` and that local time is still in the future; `dor.pid` names a live process. Exception (`5.3.0b2` and later): once per boot, the first heartbeat that finds a console user other than `loginwindow`, `_mbsetupuser`, or `root` launches a post-boot re-evaluation even when `NextScheduledReminder` is still in the future. It logs `Starter launch after boot; re-evaluating deadline (NextScheduledReminder: …).` and records the `kern.boottime` epoch in `LastBootReevaluation`. That run shows a reminder only when a pre-deadline threshold, aggressive mode, or Force mode is due, or when the stored schedule has come due; otherwise it logs `No reminder shown: post-boot re-evaluation found no reminder due` and may move `NextScheduledReminder` earlier, never later. Starting with `5.3.0b4`, a due starter during a Maintenance DarkWake also launches no `dorm` run, but logs `DarkWake detected (system capabilities: …); deferring reminder launch to the next heartbeat.` and leaves `dor-state.plist` unchanged; the reminder runs at the first heartbeat after a full wake. A missing `NextScheduledReminder` key lets the starter launch. An older healthy `dorm` run does not mean the heartbeat launched again.
- `--aggressive-kill yes`, or a `present` row checked on the Mac with `--rdnn`, means `/Library/Management/<rdnn>/dor-aggressive-kill` existed, so aggressive mode uses the normal cadence until that file is removed.
- Files-table statuses: `supplied` (named on the command line), `not in upload`, and with `--rdnn` also `inferred (--rdnn)`, `not present on this Mac`, and `unreadable on this Mac`. Report an `unreadable on this Mac` file as missing evidence, not as absent.
- Read `dorm (<version>):` from the log. A later `dor  (` line (two spaces) is deployment, not the runtime run. This skill matches `reminderDialog.zsh` 5.3.0b4. If the version differs, say the checklist is best-effort.
- The helper redacts usernames, first names, `/Users/…` paths, install.log computer names, and labeled serial numbers in the fact sheet. Keep RDNN, versions, deadlines, and preference keys. Attach the redacted report. Keep raw client files and the fact sheet out of public issues.
- With `--no-redaction`, the fact sheet says `Redaction is off`, values appear as logged, section 3 adds `Computer name` and `Serial number` rows, section 9 says the report is not redacted, and the suggested report filename carries the computer name and `-unredacted`. Do not redact such a report by hand. Never attach an unredacted report to a public issue.

## Report

Every report uses one format. Do not add, drop, rename, merge, or reorder sections.

1. Copy the helper's `## Report skeleton` block, from `<!-- report-skeleton:begin -->` to `<!-- report-skeleton:end -->`. Drop the two marker lines.
2. Fill only the `<!-- agent: … -->` slots: sections 1, 7, and 8, plus optional extra bullets in section 5. Replace each slot; do not leave comments behind. In section 7, base the answer on the helper's comparison table; it lists facts only and does not decide agreement. In section 8, base the cause and next steps on the helper's recorded evidence; when the runtime logged a `Next step:`, keep it as the first next step.
3. Do not reformat, re-sort, trim, or re-word helper tables, bullets, or the section 9 sentence. If a helper row is wrong, say so in section 8; do not edit the row.

Template (helper-filled parts shown as `…`):

````markdown
# [DDM OS Reminder](https://snelson.us/ddm) diagnosis: `<rdnn>`

Analysis date: YYYY-MM-DD · Helper: `Resources/diagnoseReminderState.zsh` (1.6.3) · Checklist: `reminderDialog.zsh` 5.3.0b4

## 1. Verdict

**<Category>** (`<status>`). One or two sentences.

## 2. Files

| File | Status | Note |
|---|---|---|
…  fixed rows: Client log, `install.log`, Managed plist, Local plist (or Supplied plist (layer unknown)), `dor-state.plist`, `dor-fallback-declaration.plist`, `SoftwareUpdateDDMStatePersistence.plist`, LaunchDaemon plist, `dor-aggressive-kill`

## 3. Identity

| Field | Value |
|---|---|
…  RDNN, Runtime version, Deployment version, Installed macOS, Checklist match (plus Computer name, Serial number with --no-redaction)
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
- Invalid declarations (`Failed to add declaration: … Invalid declaration:` lines): …
- `No updates found for DDM to enforce` lines: …
- Recovery markers (`Found product with requested PMV` or `Armed DDM activity scheduler` lines): …
- No-match markers (`MADownloadNoMatchFound`, `pallasNoPMVMatchFound=true`, or `No available updates found` lines): …
- Update Tonight (`SUOSUInstallTonightManager:` or `SUOSUScheduler:` softwareupdated lines): …
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

| Field | Client log (last `DDM update check:`) | `install.log` (latest declaration span) |
|---|---|---|
…  helper rows: Logged, Version, Declared deadline, Resolver status, Source, Corroborated

**Yes.** | **No.** | **Not comparable.** Up to three sentences, below the helper table.

## 8. Likely cause and next steps

Recorded evidence (helper-filled from the last run; interpret it below):

…  helper bullets: Last run, No reminder shown, Next step, User action, Scheduling, `NextScheduledReminder`

### Likely cause

One short paragraph.

### Next steps

1. … (read-only)
2. …

## 9. Redaction

This report is redacted: usernames, first names, `/Users` paths, `install.log` computer names, and labeled serial numbers are removed. Keep the raw client files and the helper fact sheet out of any public issue.
````

With `--no-redaction`, the helper writes the section 9 sentence as `This report is not redacted (--no-redaction): …`. Copy it unchanged.

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

After that report, ask the user whether to save the findings as a Markdown file. Do not write the file until the user confirms a path. Suggest the helper's `Suggested report filename` (`ddm-os-reminder-<rdnn>-<YYYY-MM-DD-HHMMSS>.md`, for example `ddm-os-reminder-us.snelson-2026-10-15-201132.md`; with `--no-redaction`, `ddm-os-reminder-<rdnn>-<computer-name>-unredacted-<YYYY-MM-DD-HHMMSS>.md`) next to the uploads, outside this repository. Save only the completed report. Do not save the raw uploads or the rest of the helper fact sheet.
