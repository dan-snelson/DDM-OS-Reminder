#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Integration: live heartbeats of the deployed com.example.dortest.dor (launchctl kickstart -k)
#
####################################################################################################

livePersistencePlist="/var/db/softwareupdate/SoftwareUpdateDDMStatePersistence.plist"
heartbeatTimestampPattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}$'

function requireHeartbeatDeployment() {
    integrationPaths
    if [[ ! -x "${testStarterScript}" || ! -f "${testStatePlist}" ]]; then
        skipTest "the ${testRdnn} deployment did not complete"
        return 1
    fi
    launchctl print "system/${testLaunchDaemonLabel}" > /dev/null 2>&1 && return 0
    skipTest "${testLaunchDaemonLabel} is not loaded"
    return 1
}

function disableHeartbeatLaunches() {
    setStateKey "${testStatePlist}" NextScheduledReminder "FALSE"
}

function testKickstartSeedsFingerprint() {
    local startLine=0
    local liveFingerprint=""

    requireHeartbeatDeployment || return 0
    waitForIdleRuntime
    deleteStateKey "${testStatePlist}" LastDeclarationFingerprint
    setStateKey "${testStatePlist}" NextScheduledReminder "$(stateTimestamp $(( $(date +%s) - 60 )))"
    seedInteraction
    startLine="$(logLineCount "${testScriptLog}")"
    kickstartTestDaemon

    if ! waitForLogText "${testScriptLog}" "Heartbeat launch triggered" "${startLine}" 15; then
        recordFailure "no heartbeat launch within 15 s of kickstart"
        recordHaystackContext "${testScriptLog}"
        return 0
    fi

    if liveFingerprint="$(persistencePlistFingerprint "${livePersistencePlist}")"; then
        assertPlistKey "seeded fingerprint equals the md5 of the live persistence plist" "${testStatePlist}" "LastDeclarationFingerprint" "${liveFingerprint}"
    else
        assertPlistKey "unreadable live persistence plist leaves the fingerprint unseeded" "${testStatePlist}" "LastDeclarationFingerprint" "__absent__"
    fi
    assertNotContains "seeding is not a change" "DDM declaration change recorded" "$(logTextSince "${testScriptLog}" "${startLine}")"

    waitForIdleRuntime
    disableHeartbeatLaunches
}

function testBogusFingerprintLaunchesDeclarationChange() {
    local startLine=0
    local liveFingerprint=""

    requireHeartbeatDeployment || return 0
    requireConsoleUser || return 0
    if ! liveFingerprint="$(persistencePlistFingerprint "${livePersistencePlist}")"; then
        skipTest "live persistence plist is unreadable; the starter cannot fingerprint it"
        return 0
    fi

    waitForIdleRuntime
    setStateKey "${testStatePlist}" NextScheduledReminder "$(stateTimestamp $(( $(date +%s) + 7200 )))"
    setStateKey "${testStatePlist}" LastBootReevaluation "$(bootEpoch)"
    setStateKey "${testStatePlist}" LastDeclarationFingerprint "00000000000000000000000000000000"
    startLine="$(logLineCount "${testScriptLog}")"
    print -r -- "${startLine}" > "${workDir}/declaration-change-start-line"
    kickstartTestDaemon

    if ! waitForLogText "${testScriptLog}" "DDM declaration change detected; re-evaluating deadline" "${startLine}" 15; then
        recordFailure "no declarationChange launch within 15 s of kickstart"
        recordHaystackContext "${testScriptLog}"
        return 0
    fi
    assertMatches "LastDeclarationChangeDetected format" "${heartbeatTimestampPattern}" "$(plistValue "${testStatePlist}" LastDeclarationChangeDetected)"
    assertPlistKey "fingerprint updated to the live value" "${testStatePlist}" "LastDeclarationFingerprint" "${liveFingerprint}"
}

function testDeclarationChangeRunLogsReevaluation() {
    local startLine=""
    local runText=""

    requireHeartbeatDeployment || return 0
    startLine="$(cat "${workDir}/declaration-change-start-line" 2>/dev/null)"
    if [[ ! "${startLine}" =~ ^[0-9]+$ ]]; then
        skipTest "the declarationChange heartbeat scenario did not run"
        return 0
    fi

    # dor.zsh needs time for preferences and DDM resolution; wait for its exit line
    if ! waitForLogText "${testScriptLog}" "Ticking away the moments" "${startLine}" 60; then
        recordFailure "the declarationChange run of dor.zsh did not finish within 60 s"
        recordHaystackContext "${testScriptLog}"
        return 0
    fi

    runText="$(logTextSince "${testScriptLog}" "${startLine}")"
    if [[ "${runText:l}" == *"declaration-change re-evaluation"* ]]; then
        assertContains "re-evaluation label" "eclaration-change re-evaluation" "${runText}"
    elif [[ "${runText}" == *"Version Comparison Result:"* ]]; then
        skipTest "this Mac needs no update for its live DDM state, so dor.zsh skips the re-evaluation gate (needs an outdated Mac with a DDM declaration)"
    else
        recordFailure "dor.zsh run after declarationChange logged neither a re-evaluation line nor a version comparison result"
        recordHaystackContext "${testScriptLog}"
    fi

    waitForIdleRuntime
    disableHeartbeatLaunches
}

function testFalseGivesNoLaunch() {
    local startLine=0
    local newText=""

    requireHeartbeatDeployment || return 0
    waitForIdleRuntime
    disableHeartbeatLaunches
    startLine="$(logLineCount "${testScriptLog}")"
    kickstartTestDaemon
    sleep 5

    newText="$(logTextSince "${testScriptLog}" "${startLine}")"
    assertNotContains "no heartbeat launch" "Heartbeat launch triggered" "${newText}"
    assertNotContains "no re-evaluation launch" "re-evaluating deadline" "${newText}"
}

function assertStalePidLaunch() {
    local pidValue="${1}"
    local expectedReason="${2}"
    local startLine=0

    waitForIdleRuntime
    setStateKey "${testStatePlist}" NextScheduledReminder "$(stateTimestamp $(( $(date +%s) - 60 )))"
    print -r -- "${pidValue}" > "${testPidFile}"
    seedInteraction
    startLine="$(logLineCount "${testScriptLog}")"
    kickstartTestDaemon

    if ! waitForLogText "${testScriptLog}" "Removing stale PID file '${testPidFile}' (${expectedReason})." "${startLine}" 15; then
        recordFailure "no stale-PID WARNING (${expectedReason}) within 15 s"
        recordHaystackContext "${testScriptLog}"
        return 1
    fi
    assertContains "stale PID line is a WARNING" "[WARNING]         Removing stale PID file '${testPidFile}' (${expectedReason})." "$(logTextSince "${testScriptLog}" "${startLine}")"
    if ! waitForLogText "${testScriptLog}" "Heartbeat launch triggered" "${startLine}" 15; then
        recordFailure "no launch after removing the stale PID file (${expectedReason})"
    fi
    [[ "$(head -n 1 "${testPidFile}" 2>/dev/null | tr -d '[:space:]')" == "${pidValue}" ]] && recordFailure "stale PID '${pidValue}' still in ${testPidFile}"
    waitForIdleRuntime
}

function testStalePidReplaced() {
    requireHeartbeatDeployment || return 0

    assertStalePidLaunch "1" "no valid PID"
    # A live PID that is not the deployed dor.zsh: this test runner
    assertStalePidLaunch "$$" "PID $$ is not '${testDorScript}'"

    disableHeartbeatLaunches
}

registerTest "kickstart seeds LastDeclarationFingerprint (md5 of the live persistence plist)" testKickstartSeedsFingerprint
registerTest "bogus stored fingerprint + future schedule: declarationChange launch and change time" testBogusFingerprintLaunchesDeclarationChange
registerTest "dor.zsh logs Declaration-change re-evaluation after that launch" testDeclarationChangeRunLogsReevaluation
registerTest "NextScheduledReminder FALSE: kickstart gives no launch" testFalseGivesNoLaunch
registerTest "stale dor.pid (PID 1; a live non-dor PID): WARNING, file replaced, launch" testStalePidReplaced
