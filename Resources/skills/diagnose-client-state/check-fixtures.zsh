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
dor (5.1.0): 2026-10-12 10:15:19 - [NOTICE]          Heartbeat launch triggered '/Library/Management/us.snelson/dor.zsh'.
dorm (5.1.0): 2026-10-12 10:15:20 - [PRE-FLIGHT]      Initiating …
dorm (5.1.0): 2026-10-12 10:15:21 - [NOTICE]          Display Reminder Dialog to zzuniqueuser with additional options: --ontop
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
requireText "dialog line" "Display Reminder Dialog to <redacted>" "${offsetAndDeploy}"
rejectText "dialog username" "zzuniqueuser" "${offsetAndDeploy}"
requireText "next schedule" "Scheduled next daemon reminder for 2026-10-12:16:00:00" "${offsetAndDeploy}"
requireText "deployment window" "A deployment Initiating line follows the latest runtime run." "${offsetAndDeploy}"
requireText "resolver kept" "status=resolved" "${offsetAndDeploy}"
requireText "earlier return code" "Return Code: 2" "${offsetAndDeploy}"
requireText "earlier return code note" "Last quiet-period Return Code is from an earlier run." "${offsetAndDeploy}"
requireText "heartbeat line" "Heartbeat launch triggered" "${offsetAndDeploy}"
requireText "runtime script name" "| Log script name | dorm |" "${offsetAndDeploy}"

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

echo "diagnose fixture checks passed"
