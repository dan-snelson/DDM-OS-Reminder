#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Fixture checks for Resources/diagnoseReminderState.zsh
#
# Read-only. Writes only under a temporary directory, then deletes it.
#
####################################################################################################

set -u

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

repoRoot="${0:A:h:h:h:h}"
helperPath="${repoRoot}/Resources/diagnoseReminderState.zsh"
fixtureRoot="${0:A:h}/fixtures"
workDirectory=""

function failCheck() {
    echo "FAIL: ${1}" >&2
    exit 1
}

function requireText() {
    local label="${1}"
    local needle="${2}"
    local haystack="${3}"

    [[ "${haystack}" == *"${needle}"* ]] || failCheck "${label}: missing '${needle}'"
}

function rejectText() {
    local label="${1}"
    local needle="${2}"
    local haystack="${3}"

    [[ "${haystack}" != *"${needle}"* ]] || failCheck "${label}: unexpected '${needle}'"
}

function runHelper() {
    zsh "${helperPath}" "$@"
}

function requireExitStatus() {
    local label="${1}"
    local expectedStatus="${2}"
    local actualStatus=0

    shift 2
    zsh "${helperPath}" "$@" >/dev/null 2>&1
    actualStatus=$?
    (( actualStatus == expectedStatus )) || failCheck "${label}: exit ${actualStatus}, expected ${expectedStatus}"
}

function requireSkeletonHeadings() {
    local label="${1}"
    local haystack="${2}"
    local expected="## 1. Verdict|## 2. Files|## 3. Identity|## 4. Effective settings|## 5. DDM evidence (\`install.log\`)|## 6. Client-log runs|## 7. Do the client log and \`install.log\` agree?|## 8. Likely cause and next steps|## 9. Redaction"
    local actual=""
    local reportFileNamePattern='Suggested report filename: `ddm-os-reminder-[A-Za-z0-9._-]+-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}\.md`'

    requireText "${label} skeleton begin" "<!-- report-skeleton:begin -->" "${haystack}"
    requireText "${label} skeleton end" "<!-- report-skeleton:end -->" "${haystack}"
    requireText "${label} skeleton title" $'\n# [DDM OS Reminder](https://snelson.us/ddm) diagnosis: ' "${haystack}"
    [[ "${haystack}" =~ ${reportFileNamePattern} ]] || failCheck "${label}: missing timestamped report filename"
    actual="$(print -r -- "${haystack}" | sed -n '/<!-- report-skeleton:begin -->/,/<!-- report-skeleton:end -->/p' | grep -E '^## [1-9]\. ' | paste -sd '|' -)"
    [[ "${actual}" == "${expected}" ]] || failCheck "${label}: skeleton headings '${actual}'"
}

function writePlist() {
    local plistPath="${1}"
    local body="${2}"

    cat > "${plistPath}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${body}
</dict>
</plist>
EOF
}

[[ -f "${helperPath}" ]] || failCheck "helper not found at ${helperPath}"

workDirectory="$(mktemp -d "${TMPDIR:-/tmp}/diagnose-fixtures.XXXXXX")"
trap 'rm -rf "${workDirectory}"' EXIT

managedOverLocal="$(runHelper \
    --client-log "${fixtureRoot}/managed-over-local/client.log" \
    --install-log "${fixtureRoot}/managed-over-local/install.log" \
    --managed-plist "${fixtureRoot}/managed-over-local/managed.dorm.plist" \
    --local-plist "${fixtureRoot}/managed-over-local/local.dorm.plist")"
requireText "managed-over-local times" "| DailyReminderTimes | 09:00 | managed |" "${managedOverLocal}"
requireText "managed-over-local aggressive hours" "| AggressiveModePastDeadlineHours | 720 | local |" "${managedOverLocal}"

invalidTimes="$(runHelper \
    --client-log "${fixtureRoot}/invalid-times/client.log" \
    --install-log "${fixtureRoot}/invalid-times/install.log" \
    --plist "${fixtureRoot}/invalid-times/managed.dorm.plist")"
requireText "invalid times" "| DailyReminderTimes | 08:00 | managed | ignored invalid entries: 25:00, noon |" "${invalidTimes}"
requireText "unknown key" "NotARealPreference (managed.dorm.plist)" "${invalidTimes}"

minuteBody='    <key>MinutesBeforeDeadlineReminderSchedule</key>
    <string>5, 45, 10</string>'
writePlist "${workDirectory}/minutes.dorm.plist" "${minuteBody}"
minuteOrder="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${workDirectory}/minutes.dorm.plist")"
requireText "minute order" "| MinutesBeforeDeadlineReminderSchedule | 45,10,5 |" "${minuteOrder}"

cat > "${workDirectory}/offsets.log" <<'EOF'
2026-10-12 10:14:01-0700 SecretHost softwareupdated[123]: [com.apple.softwareupdated.declarationFromKeys]: Found currently applicable declaration |EnforcedInstallDate:2026-10-20T09:00:00|VersionString:15.7.1|BuildVersionString:24G90|
2026-10-12 10:14:02-07:00 SecretHost softwareupdated[123]: [com.apple.softwareupdated.declarationFromKeys]: Found currently applicable declaration |EnforcedInstallDate:2026-10-21T09:00:00|VersionString:15.7.2|BuildVersionString:24G91|
2026-10-12 10:14:03-07:00 SecretHost softwareupdated[123]: No updates found for DDM to enforce
EOF
cat > "${workDirectory}/runtime.log" <<'EOF'
dorm (5.1.0): 2026-10-12 10:00:00 - [INFO]            Return Code: 2
dorm (5.1.0): 2026-10-12 10:00:01 - [INFO]            Serial Number: ZZSERIAL123
dor (5.1.0): 2026-10-12 10:15:19 - [NOTICE]          Heartbeat launch triggered '/Library/Management/us.snelson/dor.zsh'.
dorm (5.1.0): 2026-10-12 10:15:20 - [PRE-FLIGHT]      Initiating …
dorm (5.1.0): 2026-10-12 10:15:21 - [NOTICE]          Display Reminder Dialog to zzuniqueuser with additional options: --ontop
dorm (5.1.0): 2026-10-12 10:15:22 - [INFO]            Resolved declaration context: 2026-10-12 10:14:02-07:00 ContextOnlyHost softwareupdated[123]: [com.apple.softwareupdated.declarationFromKeys]: Found currently applicable declaration
dorm (5.1.0): 2026-10-12 10:15:22 - [NOTICE]          Normal DDM resolver result: status=resolved; source=currentApplicableDeclaration; reason=none
dorm (5.1.0): 2026-10-12 10:15:23 - [NOTICE]          Scheduled next daemon reminder for 2026-10-12:16:00:00 (baseline).
dor  (5.1.0): 2026-10-12 11:00:00 - [PRE-FLIGHT]      Initiating …
EOF
offsetAndDeploy="$(runHelper \
    --client-log "${workDirectory}/runtime.log" \
    --install-log "${workDirectory}/offsets.log" \
    --plist "${fixtureRoot}/compliant/managed.dorm.plist")"
requireText "colon offset candidate" "15.7.2" "${offsetAndDeploy}"
rejectText "unparsed -0700 candidate" "15.7.1" "${offsetAndDeploy}"
requireText "redacted host" "<redacted-host>" "${offsetAndDeploy}"
rejectText "install.log computer name" "SecretHost" "${offsetAndDeploy}"
rejectText "client-log context computer name" "ContextOnlyHost" "${offsetAndDeploy}"
requireText "dialog line" "Display Reminder Dialog to <redacted>" "${offsetAndDeploy}"
rejectText "dialog username" "zzuniqueuser" "${offsetAndDeploy}"
requireText "next schedule" "Scheduled next daemon reminder for 2026-10-12:16:00:00" "${offsetAndDeploy}"
requireText "deployment window" "A deployment Initiating line follows the latest runtime run." "${offsetAndDeploy}"
requireText "resolver kept" "status=resolved" "${offsetAndDeploy}"
requireText "no-updates heading quotes marker" '### `No updates found for DDM to enforce` lines' "${offsetAndDeploy}"
requireText "no-updates bullet quotes marker" '- `No updates found for DDM to enforce` lines: 1 line(s); latest:' "${offsetAndDeploy}"
requireText "recovery bullet quotes markers" '- Recovery markers (`Found product with requested PMV` or `Armed DDM activity scheduler` lines): none' "${offsetAndDeploy}"
requireText "earlier return code" "Return Code: 2" "${offsetAndDeploy}"
requireText "earlier return code note" "Last quiet-period Return Code is from an earlier run." "${offsetAndDeploy}"
requireText "heartbeat line" "Heartbeat launch triggered" "${offsetAndDeploy}"
requireText "runtime script name" "| Log script name | dorm |" "${offsetAndDeploy}"
requireText "skeleton files table" "| File | Status | Note |" "${offsetAndDeploy}"
requireText "skeleton state missing" '| `dor-state.plist` | not in upload |' "${offsetAndDeploy}"
requireText "skeleton run row" '| 2026-10-12 10:15:20 | `dorm (5.1.0)` | `resolved` | dialog shown; no Return Code logged |' "${offsetAndDeploy}"
requireText "skeleton deployment version" '| Deployment version | `5.1.0` (deployment output, not a runtime run) |' "${offsetAndDeploy}"
rejectText "serial number" "ZZSERIAL123" "${offsetAndDeploy}"
rejectText "redacted computer name row" "| Computer name |" "${offsetAndDeploy}"
requireText "redacted read-only" "- Read-only: no files were written" "${offsetAndDeploy}"

unredacted="$(runHelper \
    --client-log "${workDirectory}/runtime.log" \
    --install-log "${workDirectory}/offsets.log" \
    --plist "${fixtureRoot}/compliant/managed.dorm.plist" \
    --no-redaction 2>/dev/null)"
requireSkeletonHeadings "unredacted" "${unredacted}"
rejectText "unredacted placeholder" "<redacted" "${unredacted}"
requireText "unredacted install.log computer name" "SecretHost softwareupdated" "${unredacted}"
requireText "unredacted dialog line" "Display Reminder Dialog to zzuniqueuser" "${unredacted}"
requireText "unredacted computer name row" "| Computer name | SecretHost (install.log) |" "${unredacted}"
requireText "unredacted serial number row" "| Serial number | ZZSERIAL123 (client log) |" "${unredacted}"
requireText "unredacted report filename" "-SecretHost-unredacted-" "${unredacted}"
requireText "unredacted section 9" "This report is not redacted (\`--no-redaction\`)" "${unredacted}"
requireText "unredacted without --rdnn writes nothing" "- Read-only: no files were written" "${unredacted}"
requireExitStatus "unredacted without --rdnn" 0 \
    --client-log "${workDirectory}/runtime.log" \
    --install-log "${workDirectory}/offsets.log" \
    --plist "${fixtureRoot}/compliant/managed.dorm.plist" \
    --no-redaction
requireExitStatus "unredacted save directory absent" 73 \
    --client-log "${workDirectory}/runtime.log" \
    --install-log "${workDirectory}/offsets.log" \
    --plist "${fixtureRoot}/compliant/managed.dorm.plist" \
    --rdnn zz.fixture.invalid \
    --no-redaction
unsaved="$(runHelper \
    --client-log "${workDirectory}/runtime.log" \
    --install-log "${workDirectory}/offsets.log" \
    --plist "${fixtureRoot}/compliant/managed.dorm.plist" \
    --rdnn zz.fixture.invalid \
    --no-redaction 2>/dev/null)"
requireSkeletonHeadings "unsaved" "${unsaved}"
requireText "unsaved writes nothing" "- Read-only: no files were written" "${unsaved}"

cat > "${workDirectory}/plain-language.log" <<'EOF'
dorm (5.2.0): 2026-10-16 10:31:05 - [PRE-FLIGHT]      Initiating …
dorm (5.2.0): 2026-10-16 10:31:06 - [NOTICE]          DDM update check: no DDM-enforced macOS update found (status=missing; source=none; reason=No DDM-enforced macOS update found in install.log)
dorm (5.2.0): 2026-10-16 10:31:06 - [NOTICE]          DDM Emergency Fallback not configured (dor-fallback-declaration.plist absent); nothing to fall back to (DDM status=missing)
dorm (5.2.0): 2026-10-16 10:31:06 - [NOTICE]          Version Comparison Result: No DDM update (status=missing)
dorm (5.2.0): 2026-10-16 10:31:06 - [NOTICE]          No reminder shown: this Mac has no DDM-enforced macOS update pending (No DDM-enforced macOS update found in install.log)
dorm (5.2.0): 2026-10-16 10:31:06 - [NOTICE]          Next step: If an update should be enforced, confirm this Mac is in scope of a DDM software-update declaration in your MDM, then search '/var/log/install.log' for 'EnforcedInstallDate'.
dorm (5.2.0): 2026-10-16 10:31:06 - [QUIT]            Exiting …
dorm (5.2.0): 2026-10-16 10:31:06 - [QUIT]            Ticking away the moments that make up a dull day …
dorm (5.2.0): 2026-10-16 12:00:05 - [PRE-FLIGHT]      Initiating …
dorm (5.2.0): 2026-10-16 12:00:05 - [PRE-FLIGHT]      Current Logged-in User: zzplainuser, Zzplainfirst, 501
dorm (5.2.0): 2026-10-16 12:00:06 - [NOTICE]          Currently installed macOS 15.6.1 (24G84)
dorm (5.2.0): 2026-10-16 12:00:06 - [NOTICE]          Opening Software Update for zzplainuser to install macOS 15.7.2 (deadline Wed, 21-Oct-2026, 9:00 a.m.; source=currentApplicableDeclaration; status=resolved); Zzplainfirst
dorm (5.2.0): 2026-10-16 12:00:06 - [NOTICE]          DDM update check: found DDM-enforced macOS 15.7.2, declared deadline 2026-10-21T09:00:00 (status=resolved; source=currentApplicableDeclaration; reason=none)
dorm (5.2.0): 2026-10-16 12:00:07 - [QUIT]            No reminder shown: deadline is 5 days away, beyond DaysBeforeDeadlineDisplayReminder (3), and the last reminder was 1 day(s) ago
dorm (5.2.0): 2026-10-16 12:00:07 - [NOTICE]          Next step: None; the next reminder appears after 28 day(s) (OutsideDisplayWindowPeriodicReminderDays) or 3 days before the deadline.
dorm (5.2.0): 2026-10-16 12:00:07 - [QUIT]            Exiting …
dorm (5.2.0): 2026-10-16 12:00:07 - [QUIT]            Ticking away the moments that make up a dull day …
EOF
plainLanguage="$(runHelper \
    --client-log "${workDirectory}/plain-language.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${fixtureRoot}/missing/managed.dorm.plist")"
requireText "plain-language missing row" '| 2026-10-16 10:31:05 | `dorm (5.2.0)` | `missing` | No reminder shown: this Mac has no DDM-enforced macOS update pending' "${plainLanguage}"
requireText "plain-language resolved row" '| 2026-10-16 12:00:05 | `dorm (5.2.0)` | `resolved` | No reminder shown: deadline is 5 days away' "${plainLanguage}"
requireText "plain-language recorded result" "DDM update check: found DDM-enforced macOS 15.7.2" "${plainLanguage}"
requireText "agree table client logged" "| Logged | 2026-10-16 12:00:06 | no declaration in lookback window |" "${plainLanguage}"
requireText "agree table client version" "| Version | 15.7.2 | n/a |" "${plainLanguage}"
requireText "agree table client deadline" "| Declared deadline | 2026-10-21T09:00:00 | n/a |" "${plainLanguage}"
requireText "agree table client status" '| Resolver status | `resolved` | n/a |' "${plainLanguage}"
requireText "cause last run" '- Last run: 2026-10-16 12:00:05 · `dorm (5.2.0)` · resolver `resolved` · No reminder shown: deadline is 5 days away' "${plainLanguage}"
requireText "cause no reminder" '- No reminder shown: `deadline is 5 days away, beyond DaysBeforeDeadlineDisplayReminder (3)' "${plainLanguage}"
requireText "cause next step" '- Next step: `None; the next reminder appears after 28 day(s)' "${plainLanguage}"
requireText "cause no user action" "- User action: none in the last run" "${plainLanguage}"
requireText "cause state not in upload" '- `NextScheduledReminder`: `dor-state.plist` not in upload' "${plainLanguage}"
requireText "plain-language installed version" "| Installed macOS version | 15.6.1 |" "${plainLanguage}"
requireText "plain-language installed build" "| Installed macOS build | 24G84 |" "${plainLanguage}"
requireText "plain-language user redacted" "Opening Software Update for <redacted> to install macOS 15.7.2" "${plainLanguage}"
rejectText "plain-language username" "zzplainuser" "${plainLanguage}"
rejectText "plain-language first name" "Zzplainfirst" "${plainLanguage}"
requireText "plain-language next step" "Next step: None; the next reminder appears after 28 day(s)" "${plainLanguage}"
rejectText "plain-language boilerplate outcome" "| quit: Ticking away" "${plainLanguage}"
requireSkeletonHeadings "plain-language" "${plainLanguage}"

cat > "${workDirectory}/legacy-missing.log" <<'EOF'
dorm (5.0.0): 2026-10-15 10:31:05 - [PRE-FLIGHT]      Initiating …
dorm (5.0.0): 2026-10-15 10:31:06 - [NOTICE]          Normal DDM resolver result: status=missing; source=none; reason=No DDM declaration candidates found in install.log
dorm (5.0.0): 2026-10-15 10:31:06 - [NOTICE]          Resolver suppression summary: missing | No DDM declaration candidates found in install.log
dorm (5.0.0): 2026-10-15 10:31:06 - [NOTICE]          Version Comparison Result: No DDM enforcement log entry found; please confirm this Mac is in-scope for DDM-enforced updates.
dorm (5.0.0): 2026-10-15 10:31:06 - [QUIT]            Exiting …
dorm (5.0.0): 2026-10-15 10:31:06 - [QUIT]            Ticking away the moments that make up a dull day …
EOF
legacyMissing="$(runHelper \
    --client-log "${workDirectory}/legacy-missing.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${fixtureRoot}/missing/managed.dorm.plist")"
requireText "legacy missing row" '| 2026-10-15 10:31:05 | `dorm (5.0.0)` | `missing` | quit: Exiting … |' "${legacyMissing}"
requireText "legacy recorded result" "Normal DDM resolver result: status=missing" "${legacyMissing}"

for fixtureName in compliant conflict invalid-times missing; do
    fixtureSheet="$(runHelper \
        --client-log "${fixtureRoot}/${fixtureName}/client.log" \
        --install-log "${fixtureRoot}/${fixtureName}/install.log" \
        --plist "${fixtureRoot}/${fixtureName}/managed.dorm.plist")"
    requireSkeletonHeadings "${fixtureName}" "${fixtureSheet}"
    requireText "${fixtureName} agree table" "| Field | Client log (last \`DDM update check:\`) | \`install.log\` (latest declaration span) |" "${fixtureSheet}"
    if [[ "${fixtureName}" == "compliant" ]]; then
        requireText "legacy agree version" "| Version | 15.7.1 | 15.7.1 |" "${fixtureSheet}"
        requireText "legacy agree deadline" "| Declared deadline | 2026-10-20T09:00:00 | 2026-10-20T09:00:00 |" "${fixtureSheet}"
    fi
done
requireSkeletonHeadings "managed-over-local" "${managedOverLocal}"
requireSkeletonHeadings "offset-and-deploy" "${offsetAndDeploy}"

cat > "${workDirectory}/repeats.log" <<'EOF'
2026-10-12 10:14:01-07:00 SecretHost softwareupdated[123]: [com.apple.softwareupdated.declarationFromKeys]: Falling back to default applicable declaration |EnforcedInstallDate:2025-10-02T14:10:00|VersionString:15.7.1|BuildVersionString:24G231|
2026-10-12 11:14:01-07:00 SecretHost softwareupdated[123]: [com.apple.softwareupdated.declarationFromKeys]: Falling back to default applicable declaration |EnforcedInstallDate:2025-10-02T14:10:00|VersionString:15.7.1|BuildVersionString:24G231|
2026-10-14 15:48:00-07:00 SecretHost softwareupdated[123]: [com.apple.softwareupdated.declarationFromKeys]: Found currently applicable declaration |EnforcedInstallDate:2026-10-20T00:00:00|VersionString:15.8.1|BuildVersionString:(null)|
EOF
cat > "${workDirectory}/deploy-only.log" <<'EOF'
dor  (5.0.0): 2026-10-15 12:22:02 - [PRE-FLIGHT]      Initiating …
dor  (5.0.0): 2026-10-15 12:25:56 - [QUIT]            Completed us.snelson.dor LaunchDaemon
updateScriptLog:1: no such file or directory:
updateScriptLog:1: no such file or directory:
EOF
deployOnly="$(runHelper \
    --client-log "${workDirectory}/deploy-only.log" \
    --install-log "${workDirectory}/repeats.log" \
    --plist "${fixtureRoot}/compliant/managed.dorm.plist")"
requireSkeletonHeadings "deploy-only" "${deployOnly}"
requireText "span collapses repeats" "| 2026-10-12 10:14:01-07:00 | 2026-10-12 11:14:01-07:00 | 15.7.1 | 24G231 | 2025-10-02T14:10:00 | defaultApplicableDeclaration | not checked |" "${deployOnly}"
requireText "span transition" "| 2026-10-14 15:48:00-07:00 | 2026-10-14 15:48:00-07:00 | 15.8.1 |" "${deployOnly}"
requireText "candidates grouped" "| 2026-10-12 10:14:01-07:00 | 2026-10-12 11:14:01-07:00 | 2 | defaultApplicableDeclaration | 15.7.1 | 2025-10-02T14:10:00 | 24G231 |" "${deployOnly}"
requireText "candidate single" "| 2026-10-14 15:48:00-07:00 | 2026-10-14 15:48:00-07:00 | 1 | currentApplicableDeclaration | 15.8.1 |" "${deployOnly}"
requireText "fact sheet title" "# [DDM OS Reminder](https://snelson.us/ddm) client-state fact sheet" "${deployOnly}"
requireText "redaction sentence" "Keep the raw client files and the helper fact sheet out of any public issue." "${deployOnly}"
requireText "no runtime run row" "| n/a | n/a | no runtime run in client log | n/a |" "${deployOnly}"
requireText "unprefixed lines" "Lines without a DDM OS Reminder prefix: 2; most frequent (2x): \`updateScriptLog:1: no such file or directory:" "${deployOnly}"
requireText "deploy-only runtime version" "| Runtime version | no runtime run in client log |" "${deployOnly}"
rejectText "deploy-only host" "SecretHost" "${deployOnly}"

/usr/bin/plutil -create xml1 "${workDirectory}/state.plist"
/usr/bin/plutil -insert NextScheduledReminder -string "FALSE" "${workDirectory}/state.plist"
/usr/bin/plutil -insert PreDeadlineThresholdDelivered -string "45" "${workDirectory}/state.plist"
/usr/bin/plutil -insert PreDeadlineThresholdSkipped -string "30" "${workDirectory}/state.plist"
stateSheet="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${fixtureRoot}/missing/managed.dorm.plist" \
    --state-plist "${workDirectory}/state.plist")"
requireText "state false" "NextScheduledReminder: FALSE" "${stateSheet}"
requireText "threshold delivered" "PreDeadlineThresholdDelivered: 45" "${stateSheet}"
requireText "threshold skipped" "PreDeadlineThresholdSkipped: 30" "${stateSheet}"
requireText "starter rule" "Starter exits quietly" "${stateSheet}"
requireText "skeleton state supplied" '| `dor-state.plist` | supplied | `NextScheduledReminder`: FALSE |' "${stateSheet}"
requireText "cause state value" '- `NextScheduledReminder`: `FALSE`' "${stateSheet}"
requireText "cause schedule line" '- Scheduling: `Scheduled next daemon reminder for 2026-10-12:16:00:00 (baseline).`' "${offsetAndDeploy}"

# --rdnn reads live paths; this RDNN must never be deployed, so inferred inputs stay "not present on this Mac"
fixtureRdnn="com.example.diagnosefixture"
requireExitStatus "rdnn without a dot" 64 --rdnn "nodots"
requireExitStatus "rdnn with a space" 64 --rdnn "bad rdnn"
requireExitStatus "rdnn without a value" 64 --rdnn

rdnnPrecedence="$(runHelper \
    --rdnn "${fixtureRdnn}" \
    --client-log "${fixtureRoot}/compliant/client.log" \
    --install-log "${fixtureRoot}/compliant/install.log" \
    --plist "${fixtureRoot}/compliant/managed.dorm.plist" \
    --state-plist "${workDirectory}/state.plist" \
    --aggressive-kill yes)"
requireSkeletonHeadings "rdnn-precedence" "${rdnnPrecedence}"
requireText "rdnn input row" "| --rdnn | ${fixtureRdnn} | supplied |" "${rdnnPrecedence}"
requireText "rdnn identity" "| RDNN | ${fixtureRdnn} |" "${rdnnPrecedence}"
requireText "rdnn explicit client log" "| Client log | supplied |" "${rdnnPrecedence}"
requireText "rdnn explicit state plist" '| `dor-state.plist` | supplied | `NextScheduledReminder`: FALSE |' "${rdnnPrecedence}"
requireText "rdnn inferred local plist absent" "| Local plist | not present on this Mac |" "${rdnnPrecedence}"
requireText "rdnn inferred fallback absent" '| `dor-fallback-declaration.plist` | not present on this Mac |' "${rdnnPrecedence}"
requireText "rdnn explicit aggressive kill" '| `dor-aggressive-kill` | present | aggressive mode uses the normal cadence until removed |' "${rdnnPrecedence}"
rejectText "rdnn explicit aggressive kill not inferred" "checked on this Mac (--rdnn)" "${rdnnPrecedence}"
requireText "rdnn ScriptLog default" "| ScriptLog | /var/log/${fixtureRdnn}.log | default |" "${rdnnPrecedence}"

rdnnConflict="$(runHelper \
    --rdnn "${fixtureRdnn}" \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${fixtureRoot}/missing/managed.dorm.plist")"
requireText "rdnn conflict" "| RDNN | conflict: " "${rdnnConflict}"
requireText "rdnn conflict supplied" "${fixtureRdnn}" "${rdnnConflict}"
requireText "rdnn conflict log" "us.snelson" "${rdnnConflict}"
requireText "rdnn conflict report filename" "Suggested report filename: \`ddm-os-reminder-rdnn-conflict-" "${rdnnConflict}"

/usr/bin/plutil -create xml1 "${workDirectory}/fallback-good.plist"
/usr/bin/plutil -insert SchemaVersion -integer 1 "${workDirectory}/fallback-good.plist"
/usr/bin/plutil -insert VersionString -string "15.7.1" "${workDirectory}/fallback-good.plist"
/usr/bin/plutil -insert BuildVersionString -string "(null)" "${workDirectory}/fallback-good.plist"
/usr/bin/plutil -insert EnforcedInstallDate -string "2026-10-20T09:00:00Z" "${workDirectory}/fallback-good.plist"
/usr/bin/plutil -insert Source -string "JamfProScriptParameters" "${workDirectory}/fallback-good.plist"
fallbackGood="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${fixtureRoot}/missing/managed.dorm.plist" \
    --fallback-plist "${workDirectory}/fallback-good.plist")"
requireText "fallback accept" "Runtime fallback gate: would accept" "${fallbackGood}"

/usr/bin/plutil -replace EnforcedInstallDate -string "2026-10-20T09:00:00" "${workDirectory}/fallback-good.plist"
fallbackBad="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${fixtureRoot}/missing/managed.dorm.plist" \
    --fallback-plist "${workDirectory}/fallback-good.plist")"
requireText "fallback reject" "would reject: deadline is invalid or timezone-free" "${fallbackBad}"

writePlist "${workDirectory}/managed-empty-bool.plist" '    <key>DisableButton2InsteadOfHide</key>
    <string></string>'
writePlist "${workDirectory}/local-bool.plist" '    <key>DisableButton2InsteadOfHide</key>
    <false/>'
emptyBoolean="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --managed-plist "${workDirectory}/managed-empty-bool.plist" \
    --local-plist "${workDirectory}/local-bool.plist")"
requireText "empty managed boolean falls through" "| DisableButton2InsteadOfHide | NO | local |" "${emptyBoolean}"

writePlist "${workDirectory}/managed-bad-bool.plist" '    <key>DisableButton2InsteadOfHide</key>
    <string>maybe</string>'
invalidBoolean="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --managed-plist "${workDirectory}/managed-bad-bool.plist" \
    --local-plist "${workDirectory}/local-bool.plist")"
requireText "invalid managed boolean uses default" "| DisableButton2InsteadOfHide | YES | default |" "${invalidBoolean}"

writePlist "${workDirectory}/legacy-percent.plist" '    <key>MinimumDiskFreePercentage</key>
    <integer>10</integer>'
legacyPercent="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${workDirectory}/legacy-percent.plist")"
requireText "legacy percentage honored" "| MinimumDiskFreeGB | 10% | unknown (deprecated percentage) |" "${legacyPercent}"

writePlist "${workDirectory}/bad-localized.plist" '    <key>TitleLocalized_123</key>
    <string>unused</string>'
badLocalized="$(runHelper \
    --client-log "${fixtureRoot}/missing/client.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${workDirectory}/bad-localized.plist")"
requireText "rejected localized key" "TitleLocalized_123 (bad-localized.plist): unrecognized language code" "${badLocalized}"

writePlist "${workDirectory}/battery.plist" '    <key>MinimumBatteryPercentage</key>
    <integer>101</integer>
    <key>BatteryWarningMessage</key>
    <string>Plug in</string>
    <key>BatteryWarningMessageLocalized_de</key>
    <string>Netzteil anschliessen</string>'
cat > "${workDirectory}/battery.log" <<'EOF'
dorm (5.2.0): 2026-10-18 09:00:05 - [PRE-FLIGHT]      Initiating …
dorm (5.2.0): 2026-10-18 09:00:06 - [INFO]            Disk space: 120.5 GB free; MinimumDiskFreeGB threshold 35 GB; warning suppressed
dorm (5.2.0): 2026-10-18 09:00:06 - [NOTICE]          Battery: power source Battery Power; internal battery 18%; MinimumBatteryPercentage threshold 50%; warning shown
dorm (5.2.0): 2026-10-18 09:00:07 - [QUIT]            Exiting …
EOF
battery="$(runHelper \
    --client-log "${workDirectory}/battery.log" \
    --install-log "${fixtureRoot}/missing/install.log" \
    --plist "${workDirectory}/battery.plist")"
requireText "battery threshold range" "| MinimumBatteryPercentage | 50 | default | invalid '101' (expected 0-100); using default 50 |" "${battery}"
rejectText "battery message known" "BatteryWarningMessage (battery.plist)" "${battery}"
rejectText "battery localized known" "BatteryWarningMessageLocalized_de (battery.plist)" "${battery}"
requireText "battery decision line" "Battery: power source Battery Power; internal battery 18%" "${battery}"
requireText "disk decision line" "Disk space: 120.5 GB free; MinimumDiskFreeGB threshold 35 GB" "${battery}"

echo "diagnose fixture checks passed"
