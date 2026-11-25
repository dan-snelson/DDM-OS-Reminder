#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: reminderDialog.zsh runtime state (PID file, scheduler state reads, re-evaluation schedule,
# aggressive mode, Update Tonight, battery, DarkWake)
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# PID file
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function assertStalePidReason() {
    local label="${1}"
    local expectedReason="${2}"

    if dorPidFileNamesActiveRuntime; then
        recordFailure "${label}: PID file treated as an active runtime"
        return 1
    fi
    assertEquals "${label}: stale reason" "${expectedReason}" "${stalePidReason}"
}

function testDorPidStaleReasons() {
    local deadPid=""
    local otherPid=""
    local livePid=""

    loadRuntimeFunctions || return 0
    sleep 0 &
    deadPid=$!
    wait "${deadPid}" 2>/dev/null

    print "$$" > "${dorPidFilePath}"
    touchBeforeBoot "${dorPidFilePath}"
    assertStalePidReason "before boot" "written before the current boot"

    print "abc" > "${dorPidFilePath}"
    assertStalePidReason "not a number" "no valid PID"

    print "1" > "${dorPidFilePath}"
    assertStalePidReason "PID 1" "no valid PID"

    print "$$" > "${dorPidFilePath}"
    assertStalePidReason "this run" "PID $$ is this run"

    print "${deadPid}" > "${dorPidFilePath}"
    assertStalePidReason "not running" "PID ${deadPid} is not running"

    sleep 30 &
    otherPid=$!
    print "${otherPid}" > "${dorPidFilePath}"
    assertStalePidReason "other process" "PID ${otherPid} is not '${dorScriptPath}'"
    kill "${otherPid}" 2>/dev/null

    print '#!/bin/zsh -f\nsleep 30' > "${dorScriptPath}"
    chmod 755 "${dorScriptPath}"
    /bin/zsh -f "${dorScriptPath}" &
    livePid=$!
    sleep 0.3
    print "${livePid}" > "${dorPidFilePath}"
    if ! dorPidFileNamesActiveRuntime; then
        recordFailure "a running '${dorScriptPath}' was not recognized as active (${stalePidReason})"
    fi
    kill "${livePid}" 2>/dev/null
}

function testInitializeDorPidFile() {
    loadRuntimeFunctions || return 0

    initializeDorPidFile > /dev/null
    assertFileAbsent "manual run writes no PID file" "${dorPidFilePath}"

    schedulerEnabledForCurrentRun="YES"
    print "1" > "${dorPidFilePath}"
    initializeDorPidFile > /dev/null
    assertContains "stale PID WARNING" "[WARNING]         Removing stale PID file '${dorPidFilePath}' (no valid PID)." "${scriptLog}"
    assertEquals "PID file now names this run" "$$" "$(head -n 1 "${dorPidFilePath}")"
    assertEquals "this run owns the PID file" "YES" "${ownsDorPidFile}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Scheduler state reads
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function testReadReminderStateKey() {
    local readOutput=""
    local readStatus=0

    loadRuntimeFunctions || return 0

    readOutput="$(readReminderStateKey "NextScheduledReminder")"
    readStatus=$?
    assertExit "missing plist (manual run)" "0" "${readStatus}"
    assertEquals "missing plist gives empty output" "" "${readOutput}"
    assertFileAbsent "manual run does not create the state plist" "${dorStatePlistPath}"

    print "not a plist" > "${dorStatePlistPath}"
    cp "${dorStatePlistPath}" "${testDir}/state-before"
    readOutput="$(readReminderStateKey "NextScheduledReminder" 2>/dev/null)"
    assertContains "unreadable plist WARNING (log file, not stdout)" "[WARNING]         Unreadable scheduler state plist '${dorStatePlistPath}'; ignoring state for non-daemon run." "${scriptLog}"
    cmp -s "${testDir}/state-before" "${dorStatePlistPath}" || recordFailure "manual run modified the unreadable state plist"

    makeStatePlist "${dorStatePlistPath}" "NextScheduledReminder=2026-12-01:08:00:00"
    assertEquals "present key" "2026-12-01:08:00:00" "$(readReminderStateKey "NextScheduledReminder")"
    assertEquals "absent key gives empty output (PlistBuddy error text never kept)" "" "$(readReminderStateKey "LastDeclarationChangeDetected")"

    schedulerEnabledForCurrentRun="YES"
    print "not a plist" > "${dorStatePlistPath}"
    readReminderStateKey "NextScheduledReminder" > /dev/null
    assertContains "scheduler run quarantines an unreadable plist" "Moved unreadable scheduler state plist to '${dorStatePlistPath}.invalid." "${scriptLog}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Re-evaluation schedule (post-boot / declaration change): earlier, never later
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function prepareReevaluation() {
    loadRuntimeFunctions || return 1
    loadDefaultPreferences
    schedulerEnabledForCurrentRun="YES"
    reevaluationLabel="Post-boot"
    ddmVersionString="26.2"
    ddmBuildVersionString="(null)"
    versionComparisonResult="Update Required"
    parseMinuteThresholdSchedule "45,30,15,10,5" > /dev/null
    nowEpochForTest="$(date +%s)"
    makeStatePlist "${dorStatePlistPath}"
}

# Real runs record the threshold signature first (resolveDuePreDeadlineThresholdReminder); without it the
# reset NOTICE is printed inside the $(…) capture of resolveNextPendingPreDeadlineThresholdEpoch
function seedThresholdSignature() {
    setStateKey "${dorStatePlistPath}" PreDeadlineThresholdSignature "${ddmVersionString}|${ddmBuildVersionString}|${ddmEnforcedInstallDateEpoch}"
}

function testReevaluationKeepsLaterSchedule() {
    local storedEpoch=""

    prepareReevaluation || return 0
    storedEpoch=$(( nowEpochForTest + 7200 ))
    setStateKey "${dorStatePlistPath}" NextScheduledReminder "$(stateTimestamp "${storedEpoch}")"
    ddmEnforcedInstallDateEpoch=$(( nowEpochForTest + 10 * 86400 ))
    seedThresholdSignature

    setNextReminderScheduleForReevaluation > /dev/null
    assertEquals "mode" "exact" "${nextReminderScheduleMode}"
    assertEquals "keeps the stored epoch" "${storedEpoch}" "${nextReminderScheduleEpoch}"
    assertContains "reason" "Post-boot re-evaluation kept existing schedule" "${nextReminderScheduleReason}"
}

function testReevaluationMovesEarlierForThreshold() {
    local storedEpoch=""

    prepareReevaluation || return 0
    storedEpoch=$(( nowEpochForTest + 7200 ))
    setStateKey "${dorStatePlistPath}" NextScheduledReminder "$(stateTimestamp "${storedEpoch}")"
    ddmEnforcedInstallDateEpoch=$(( nowEpochForTest + 3600 ))
    seedThresholdSignature

    setNextReminderScheduleForReevaluation > /dev/null
    assertEquals "moves to the 45-minute threshold" "$(( ddmEnforcedInstallDateEpoch - 45 * 60 ))" "${nextReminderScheduleEpoch}"
    assertContains "reason" "45-minute pre-deadline threshold" "${nextReminderScheduleReason}"
}

function testReevaluationNeverLater() {
    local storedEpoch=""

    prepareReevaluation || return 0
    storedEpoch=$(( nowEpochForTest + 600 ))
    setStateKey "${dorStatePlistPath}" NextScheduledReminder "$(stateTimestamp "${storedEpoch}")"
    ddmEnforcedInstallDateEpoch=$(( nowEpochForTest + 3600 ))
    seedThresholdSignature

    setNextReminderScheduleForReevaluation > /dev/null
    assertEquals "a later threshold never pushes the schedule out" "${storedEpoch}" "${nextReminderScheduleEpoch}"
}

function testReevaluationMovesEarlierForAggressive() {
    local storedEpoch=""

    prepareReevaluation || return 0
    storedEpoch=$(( nowEpochForTest + 7200 ))
    setStateKey "${dorStatePlistPath}" NextScheduledReminder "$(stateTimestamp "${storedEpoch}")"
    ddmEnforcedInstallDateEpoch=$(( nowEpochForTest - 3600 ))
    seedThresholdSignature
    aggressiveModePastDeadlineHours=2

    setNextReminderScheduleForReevaluation > /dev/null
    assertEquals "moves to the aggressive-mode start" "$(( ddmEnforcedInstallDateEpoch + 7200 ))" "${nextReminderScheduleEpoch}"
    assertContains "reason" "aggressive-mode start" "${nextReminderScheduleReason}"

    print "" > "${aggressiveModeKillSwitchPath}"
    setNextReminderScheduleForReevaluation > /dev/null
    assertEquals "kill switch: keeps the stored epoch" "${storedEpoch}" "${nextReminderScheduleEpoch}"
}

function testReevaluationDueOrMissing() {
    prepareReevaluation || return 0
    ddmEnforcedInstallDateEpoch=$(( nowEpochForTest + 10 * 86400 ))
    seedThresholdSignature

    setNextReminderScheduleForReevaluation > /dev/null
    assertExit "missing stored schedule returns 1 (continue normal flow)" "1" "$?"

    setStateKey "${dorStatePlistPath}" NextScheduledReminder "$(stateTimestamp $(( nowEpochForTest - 60 )))"
    setNextReminderScheduleForReevaluation > /dev/null
    assertExit "due stored schedule returns 1 (continue normal flow)" "1" "$?"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Aggressive mode
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function testEvaluateAggressiveModeState() {
    loadRuntimeFunctions || return 0
    loadDefaultPreferences
    versionComparisonResult="Update Required"
    aggressiveModePastDeadlineHours=2

    ddmEnforcedInstallDateEpoch=$(( $(date +%s) - 3600 ))
    evaluateAggressiveModeState > /dev/null
    assertEquals "1 hour past a 2-hour threshold: inactive" "NO" "${aggressiveModeActive}"
    assertContains "not-yet NOTICE" "Aggressive mode not yet active (1 hour(s) past effective deadline; threshold 2 hour(s))." "${scriptLog}"

    ddmEnforcedInstallDateEpoch=$(( $(date +%s) - 3 * 3600 - 60 ))
    evaluateAggressiveModeState > /dev/null
    assertEquals "3 hours past: active" "YES" "${aggressiveModeActive}"

    print "" > "${aggressiveModeKillSwitchPath}"
    evaluateAggressiveModeState > /dev/null
    assertEquals "kill switch: inactive" "NO" "${aggressiveModeActive}"
    assertEquals "kill switch detected" "YES" "${aggressiveModeKillSwitchDetected}"

    rm -f "${aggressiveModeKillSwitchPath}"
    versionComparisonResult="Up-to-date"
    evaluateAggressiveModeState > /dev/null
    assertEquals "up-to-date Mac: inactive" "NO" "${aggressiveModeActive}"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Tonight
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# "Now" is today 12:00 local; boot was today 08:00
function prepareUpdateTonight() {
    loadRuntimeFunctions || return 1
    ddmVersionString="26.2"
    updateTonightNoon="$(date -j -f '%Y-%m-%d %H:%M:%S' "$(date '+%Y-%m-%d') 12:00:00" '+%s')"
    lastBootTime=$(( updateTonightNoon - 4 * 3600 ))
}

function runUpdateTonight() {
    detectUpdateTonightScheduled "${updateTonightNoon}" > /dev/null
    updateTonightReturn=$?
}

function testUpdateTonightValid() {
    prepareUpdateTonight || return 0
    makeInstallLog "${installLogPath}" \
        "$(ilQueued $(( updateTonightNoon - 7200 )) "26.2")" \
        "$(ilArmed $(( updateTonightNoon - 7170 )) "NO")"
    runUpdateTonight

    assertExit "Queued + ARMED (simulated=NO) from softwareupdated" "0" "${updateTonightReturn}"
    assertEquals "evidence epoch" "$(( updateTonightNoon - 7200 ))" "${updateTonightEvidenceEpoch}"
}

function testUpdateTonightRejected() {
    local scenario=""

    for scenario in untrustedSender simulated beforeBoot beforeMidnight superseded otherVersion notArmed; do
        prepareUpdateTonight || return 0
        case "${scenario}" in
            untrustedSender )
                makeInstallLog "${installLogPath}" "$(ilQueued $(( updateTonightNoon - 7200 )) "26.2" "fakeupdater")" "$(ilArmed $(( updateTonightNoon - 7170 )) "NO" "fakeupdater")"
                ;;
            simulated )
                makeInstallLog "${installLogPath}" "$(ilQueued $(( updateTonightNoon - 7200 )) "26.2")" "$(ilArmed $(( updateTonightNoon - 7170 )) "YES")"
                ;;
            beforeBoot )
                makeInstallLog "${installLogPath}" "$(ilQueued $(( updateTonightNoon - 5 * 3600 )) "26.2")" "$(ilArmed $(( updateTonightNoon - 5 * 3600 + 30 )) "NO")"
                ;;
            beforeMidnight )
                lastBootTime=$(( updateTonightNoon - 3 * 86400 ))
                makeInstallLog "${installLogPath}" "$(ilQueued $(( updateTonightNoon - 13 * 3600 )) "26.2")" "$(ilArmed $(( updateTonightNoon - 13 * 3600 + 30 )) "NO")"
                ;;
            superseded )
                makeInstallLog "${installLogPath}" "$(ilQueued $(( updateTonightNoon - 7200 )) "26.2")" "$(ilArmed $(( updateTonightNoon - 7170 )) "NO")" "$(ilDequeued $(( updateTonightNoon - 3600 )))"
                ;;
            otherVersion )
                makeInstallLog "${installLogPath}" "$(ilQueued $(( updateTonightNoon - 7200 )) "26.3")" "$(ilArmed $(( updateTonightNoon - 7170 )) "NO")"
                ;;
            notArmed )
                makeInstallLog "${installLogPath}" "$(ilQueued $(( updateTonightNoon - 7200 )) "26.2")"
                ;;
        esac
        runUpdateTonight
        assertExit "Update Tonight evidence rejected: ${scenario}" "1" "${updateTonightReturn}"
        case "${scenario}" in
            untrustedSender ) assertContains "untrusted sender NOTICE" "Ignored Update Tonight evidence not logged by softwareupdated" "${scriptLog}" ;;
            superseded      ) assertContains "superseded NOTICE" "was superseded or canceled; not suppressing" "${scriptLog}" ;;
        esac
        : > "${scriptLog}"
    done
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# pmset: battery and DarkWake (stubbed through the rewritten /usr/bin/pmset path)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function testResolveBatteryPowerState() {
    loadRuntimeFunctions || return 0

    setPmsetPowerSource "Now drawing from 'AC Power'"$'\n'" -InternalBattery-0 (id=4653155)	100%; charged; 0:00 remaining present: true"
    resolveBatteryPowerState > /dev/null
    assertEquals "AC: source" "AC Power" "${batteryPowerSource}"
    assertEquals "AC: percentage" "100" "${batteryPercentage}"

    setPmsetPowerSource "Now drawing from 'Battery Power'"$'\n'" -InternalBattery-0 (id=4653155)	20%; discharging; 1:23 remaining present: true"
    resolveBatteryPowerState > /dev/null
    assertEquals "battery 20%: source" "Battery Power" "${batteryPowerSource}"
    assertEquals "battery 20%: percentage" "20" "${batteryPercentage}"

    setPmsetPowerSource "Now drawing from 'UPS Power'"$'\n'" -UPS CP1500 (id=1234)	80%; discharging; 0:45 remaining present: true"
    resolveBatteryPowerState > /dev/null
    assertEquals "UPS: no internal battery" "NO" "${batteryInternalPresent}"
    assertEquals "UPS: no percentage" "" "${batteryPercentage}"

    setPmsetPowerSource "Now drawing from 'Battery Power'"$'\n'" -InternalBattery-0 (id=4653155)	charging; (no estimate) present: true"
    resolveBatteryPowerState > /dev/null
    assertEquals "unreadable: no percentage" "" "${batteryPercentage}"
    assertContains "unreadable WARNING" "[WARNING]         Internal battery detected, but its charge could not be read from 'pmset -g ps'; suppressing low-battery warning." "${scriptLog}"
}

function testIsSystemInDarkWake() {
    loadRuntimeFunctions || return 0

    setPmsetSystemState "Current System Capabilities are: CPU"$'\n'"Current Power State: 3"
    isSystemInDarkWake
    assertExit "CPU only: DarkWake" "0" "$?"

    setPmsetSystemState "Current System Capabilities are: CPU Graphics Audio Network"$'\n'"Current Power State: 4"
    isSystemInDarkWake
    assertExit "CPU Graphics: awake" "1" "$?"

    setPmsetSystemState "something unexpected"
    isSystemInDarkWake
    assertExit "unrecognized output fails open" "1" "$?"
}

registerTest "dorPidFileNamesActiveRuntime stale reasons and a live dor.zsh" testDorPidStaleReasons
registerTest "initializeDorPidFile: manual no-op; stale PID WARNING and replacement" testInitializeDorPidFile
registerTest "readReminderStateKey: missing, unreadable (WARNING, untouched), output only on rc 0" testReadReminderStateKey
registerTest "re-evaluation keeps a later stored schedule" testReevaluationKeepsLaterSchedule
registerTest "re-evaluation moves earlier for a pre-deadline threshold" testReevaluationMovesEarlierForThreshold
registerTest "re-evaluation never moves the schedule later" testReevaluationNeverLater
registerTest "re-evaluation moves earlier for the aggressive-mode start (not with kill switch)" testReevaluationMovesEarlierForAggressive
registerTest "re-evaluation with a missing or due stored schedule continues the normal flow" testReevaluationDueOrMissing
registerTest "evaluateAggressiveModeState: before, after, kill switch, up-to-date" testEvaluateAggressiveModeState
registerTest "detectUpdateTonightScheduled: valid Queued + ARMED" testUpdateTonightValid
registerTest "detectUpdateTonightScheduled rejects untrusted, simulated, pre-boot, pre-midnight, superseded, other version, unarmed" testUpdateTonightRejected
registerTest "resolveBatteryPowerState: AC, battery 20%, UPS, unreadable" testResolveBatteryPowerState
registerTest "isSystemInDarkWake: CPU only, CPU Graphics, unknown" testIsSystemInDarkWake
