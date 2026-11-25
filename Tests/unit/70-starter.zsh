#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: dor-starter.zsh extracted from launchDaemonManagement.zsh, run against the work directory
# (#177 post-boot, #180 declaration change, #192 change time, stale PID, DarkWake)
#
####################################################################################################

starterDeclarationA="26.2|2026-12-15T10:00:00"
starterDeclarationB="26.3|2027-01-20T09:30:00"
starterTimestampPattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}$'

function futureSchedule() {
    stateTimestamp $(( $(date +%s) + 7200 ))
}

function pastSchedule() {
    stateTimestamp $(( $(date +%s) - 600 ))
}

# Common setup: future schedule, console user ready, post-boot already done, fingerprint = declaration A
function prepareQuietStarter() {
    prepareStarter || return 1
    setConsoleUser "${1:-tester}"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
    makeStatePlist "${starterState}" \
        "NextScheduledReminder=$(futureSchedule)" \
        "LastBootReevaluation=$(bootEpoch)" \
        "LastDeclarationFingerprint=$(expectedFingerprint "${starterDeclarationA}")"
}

function testFalseExitsSilently() {
    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationB}"
    makeStatePlist "${starterState}" "NextScheduledReminder=FALSE" "LastDeclarationFingerprint=$(expectedFingerprint "${starterDeclarationA}")"
    runStarter no

    assertExit "starter exit" "0" "${starterExitCode}"
    assertNoLaunch "FALSE never launches"
    assertEquals "starter log stays empty" "" "$(cat "${starterLog}")"
    assertPlistKey "FALSE skips the fingerprint check" "${starterState}" "LastDeclarationFingerprint" "$(expectedFingerprint "${starterDeclarationA}")"
}

function testFutureUnchangedExitsSilently() {
    prepareQuietStarter || return 0
    runStarter no

    assertExit "starter exit" "0" "${starterExitCode}"
    assertNoLaunch "future schedule with an unchanged fingerprint"
    assertEquals "starter log stays empty" "" "$(cat "${starterLog}")"
}

function testMissingFingerprintSeedsWithoutChange() {
    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
    makeStatePlist "${starterState}" "NextScheduledReminder=$(pastSchedule)" "LastBootReevaluation=$(bootEpoch)"
    runStarter yes

    assertLaunchReason "due schedule launches" "scheduled"
    assertPlistKey "fingerprint seeded" "${starterState}" "LastDeclarationFingerprint" "$(expectedFingerprint "${starterDeclarationA}")"
    assertPlistKey "seeding is not a change" "${starterState}" "LastDeclarationChangeDetected" "__absent__"
    assertNotContains "no change NOTICE when seeding" "DDM declaration change" "${starterLog}"
}

function testFutureSilentWithoutFingerprint() {
    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
    makeStatePlist "${starterState}" "NextScheduledReminder=$(futureSchedule)" "LastBootReevaluation=$(bootEpoch)"
    runStarter no

    assertNoLaunch "a missing stored fingerprint is not a change"
    assertPlistKey "nothing seeded without a launch" "${starterState}" "LastDeclarationFingerprint" "__absent__"
}

function testChangedFingerprintLaunchesDeclarationChange() {
    prepareQuietStarter || return 0
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}" "${starterDeclarationB}"
    runStarter yes

    assertLaunchReason "changed fingerprint" "declarationChange"
    assertContains "change NOTICE" "[NOTICE]          DDM declaration change detected; re-evaluating deadline (NextScheduledReminder:" "${starterLog}"
    assertMatches "LastDeclarationChangeDetected format" "${starterTimestampPattern}" "$(plistValue "${starterState}" LastDeclarationChangeDetected)"
    assertPlistKey "new fingerprint (independent md5 of sorted signatures)" "${starterState}" "LastDeclarationFingerprint" "$(expectedFingerprint "${starterDeclarationB}" "${starterDeclarationA}")"
}

function testZeroDeclarationsFingerprint() {
    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}"
    makeStatePlist "${starterState}" "NextScheduledReminder=$(pastSchedule)" "LastBootReevaluation=$(bootEpoch)"
    runStarter yes

    assertLaunchReason "due schedule launches" "scheduled"
    assertPlistKey "zero declarations fingerprint" "${starterState}" "LastDeclarationFingerprint" "d41d8cd98f00b204e9800998ecf8427e"
}

function testDueScheduleRecordsChange() {
    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationB}"
    makeStatePlist "${starterState}" \
        "NextScheduledReminder=$(pastSchedule)" \
        "LastBootReevaluation=$(bootEpoch)" \
        "LastDeclarationFingerprint=$(expectedFingerprint "${starterDeclarationA}")"
    runStarter yes

    assertLaunchReason "due schedule keeps the scheduled reason" "scheduled"
    assertContains "change recorded NOTICE" "[NOTICE]          DDM declaration change recorded at" "${starterLog}"
    assertMatches "LastDeclarationChangeDetected format" "${starterTimestampPattern}" "$(plistValue "${starterState}" LastDeclarationChangeDetected)"
    assertPlistKey "fingerprint updated" "${starterState}" "LastDeclarationFingerprint" "$(expectedFingerprint "${starterDeclarationB}")"
}

function testUnreadablePersistenceLeavesFingerprint() {
    local persistenceVariant=""

    for persistenceVariant in missing unrecognized; do
        prepareStarter || return 0
        setConsoleUser "tester"
        if [[ "${persistenceVariant}" == "missing" ]]; then
            rm -f "${starterPersistence}"
        else
            makePersistencePlist "${starterPersistence}" --unrecognized
        fi
        makeStatePlist "${starterState}" \
            "NextScheduledReminder=$(pastSchedule)" \
            "LastBootReevaluation=$(bootEpoch)" \
            "LastDeclarationFingerprint=0123456789abcdef0123456789abcdef"
        runStarter yes

        assertLaunchReason "${persistenceVariant} persistence plist still launches" "scheduled"
        assertPlistKey "${persistenceVariant} persistence plist leaves the fingerprint untouched" "${starterState}" "LastDeclarationFingerprint" "0123456789abcdef0123456789abcdef"
        assertPlistKey "${persistenceVariant} persistence plist records no change" "${starterState}" "LastDeclarationChangeDetected" "__absent__"
        rm -rf "${starterDir}"
    done
}

function testPostBootTwoHeartbeats() {
    local bootValue="$(bootEpoch)"

    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
    makeStatePlist "${starterState}" \
        "NextScheduledReminder=$(futureSchedule)" \
        "LastDeclarationFingerprint=$(expectedFingerprint "${starterDeclarationA}")"

    runStarter no
    assertNoLaunch "heartbeat 1 does not launch"
    assertPlistKey "heartbeat 1 writes PostBootConsoleUserSeen" "${starterState}" "PostBootConsoleUserSeen" "${bootValue}:tester"
    assertContains "heartbeat 1 NOTICE" "[NOTICE]          Console user 'tester' detected after boot; deferring post-boot re-evaluation one heartbeat so login can settle." "${starterLog}"

    runStarter yes
    assertLaunchReason "heartbeat 2 launches" "postBoot"
    assertPlistKey "heartbeat 2 records LastBootReevaluation" "${starterState}" "LastBootReevaluation" "${bootValue}"

    runStarter no
    assertNoLaunch "heartbeat 3 is silent"
}

function testConsoleUserNotReady() {
    local consoleUser=""

    for consoleUser in loginwindow root _mbsetupuser ""; do
        prepareStarter || return 0
        setConsoleUser "${consoleUser}"
        makePersistencePlist "${starterPersistence}" "${starterDeclarationB}"
        makeStatePlist "${starterState}" \
            "NextScheduledReminder=$(futureSchedule)" \
            "LastDeclarationFingerprint=$(expectedFingerprint "${starterDeclarationA}")"
        runStarter no

        assertNoLaunch "console user '${consoleUser:-none}' is not ready"
        assertPlistKey "console user '${consoleUser:-none}' writes no PostBootConsoleUserSeen" "${starterState}" "PostBootConsoleUserSeen" "__absent__"
        rm -rf "${starterDir}"
    done
}

function testDarkWakeDefers() {
    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationB}"
    makeStatePlist "${starterState}" \
        "NextScheduledReminder=$(pastSchedule)" \
        "LastDeclarationFingerprint=$(expectedFingerprint "${starterDeclarationA}")"
    print -r -- "Current System Capabilities are: CPU"$'\n'"Current Power State: 3" > "${starterDir}/pmset-systemstate.txt"
    cp "${starterState}" "${testDir}/state-before.plist"
    runStarter no

    assertExit "starter exit" "0" "${starterExitCode}"
    assertNoLaunch "DarkWake defers the launch"
    assertContains "DarkWake NOTICE" "[NOTICE]          DarkWake detected (system capabilities: CPU); deferring reminder launch to the next heartbeat." "${starterLog}"
    if ! cmp -s "${testDir}/state-before.plist" "${starterState}"; then
        recordFailure "state plist changed during DarkWake (expected byte-identical)"
    fi
}

function testStalePidFile() {
    local pidVariant=""
    local expectedReason=""
    local deadPid=""

    sleep 0 &
    deadPid=$!
    wait "${deadPid}" 2>/dev/null

    for pidVariant in beforeBoot notRunning pidOne otherProcess; do
        prepareStarter || return 0
        setConsoleUser "tester"
        makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
        makeStatePlist "${starterState}" "NextScheduledReminder=$(pastSchedule)" "LastBootReevaluation=$(bootEpoch)"

        case "${pidVariant}" in
            beforeBoot )
                print "$$" > "${starterDir}/dor.pid"
                touchBeforeBoot "${starterDir}/dor.pid"
                expectedReason="written before the current boot"
                ;;
            notRunning )
                print "${deadPid}" > "${starterDir}/dor.pid"
                expectedReason="PID ${deadPid} is not running"
                ;;
            pidOne )
                print "1" > "${starterDir}/dor.pid"
                expectedReason="no valid PID"
                ;;
            otherProcess )
                print "$$" > "${starterDir}/dor.pid"
                expectedReason="PID $$ is not '${starterDir}/dor.zsh'"
                ;;
        esac
        runStarter yes

        assertContains "${pidVariant}: stale PID WARNING" "[WARNING]         Removing stale PID file '${starterDir}/dor.pid' (${expectedReason})." "${starterLog}"
        assertFileAbsent "${pidVariant}: stale PID file removed" "${starterDir}/dor.pid"
        assertLaunchReason "${pidVariant}: launch follows" "scheduled"
        rm -rf "${starterDir}"
    done
}

function testLivePidExitsSilently() {
    local livePid=""

    prepareStarter || return 0
    setConsoleUser "tester"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
    makeStatePlist "${starterState}" "NextScheduledReminder=$(pastSchedule)" "LastBootReevaluation=$(bootEpoch)"

    STUB_SLEEP=30 /bin/zsh -f "${starterDir}/dor.zsh" &
    livePid=$!
    print "${livePid}" > "${starterDir}/dor.pid"
    sleep 0.3

    runStarter no
    kill "${livePid}" 2>/dev/null
    wait "${livePid}" 2>/dev/null

    assertExit "starter exit" "0" "${starterExitCode}"
    assertNoLaunch "a live main script blocks the launch"
    assertFileExists "live PID file kept" "${starterDir}/dor.pid"
    assertEquals "starter log stays empty" "" "$(cat "${starterLog}")"
}

function testMissingStatePlistLaunches() {
    prepareStarter || return 0
    setConsoleUser ""
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
    rm -f "${starterState}"
    runStarter yes

    assertLaunchReason "missing state plist reads as empty" "scheduled"
    assertFileExists "state plist created" "${starterState}"
    assertPlistKey "fingerprint seeded" "${starterState}" "LastDeclarationFingerprint" "$(expectedFingerprint "${starterDeclarationA}")"
}

function testInvalidScheduleLaunches() {
    prepareStarter || return 0
    setConsoleUser ""
    makePersistencePlist "${starterPersistence}" "${starterDeclarationA}"
    makeStatePlist "${starterState}" "NextScheduledReminder=garbage"
    runStarter yes

    assertContains "invalid schedule WARNING" "[WARNING]         Invalid NextScheduledReminder 'garbage'; launching main script now." "${starterLog}"
    assertLaunchReason "invalid schedule launches" "scheduled"
}

# chflags uchg makes every state write fail. Each test clears the flag right after the heartbeat;
# runTests.zsh also runs chflags -R nouchg on the work directory before removing it.
function lockStatePlist() {
    chflags uchg "${starterState}"
}

function testWriteFailureBlocksDeclarationChange() {
    local storedFingerprint=""

    prepareQuietStarter || return 0
    storedFingerprint="$(expectedFingerprint "${starterDeclarationA}")"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationB}"
    lockStatePlist
    runStarter no
    chflags nouchg "${starterState}"

    assertContains "[ERROR] for a declaration-change launch" "[ERROR]" "${starterLog}"
    assertContains "not launching" "not launching main script." "${starterLog}"
    assertNoLaunch "a declaration-change launch that cannot write state does not launch"
    assertPlistKey "fingerprint unchanged" "${starterState}" "LastDeclarationFingerprint" "${storedFingerprint}"
}

function testWriteFailureWarnsForScheduledLaunch() {
    local storedFingerprint=""

    prepareStarter || return 0
    setConsoleUser ""
    storedFingerprint="$(expectedFingerprint "${starterDeclarationA}")"
    makePersistencePlist "${starterPersistence}" "${starterDeclarationB}"
    makeStatePlist "${starterState}" "NextScheduledReminder=$(pastSchedule)" "LastDeclarationFingerprint=${storedFingerprint}"
    lockStatePlist
    runStarter maybe
    chflags nouchg "${starterState}"

    assertContains "[WARNING] for a scheduled launch" "[WARNING]         Unable to record DDM declaration change time; launching main script anyway." "${starterLog}"
    assertPlistKey "fingerprint unchanged" "${starterState}" "LastDeclarationFingerprint" "${storedFingerprint}"
}

registerTest "NextScheduledReminder FALSE exits silently with no launch" testFalseExitsSilently
registerTest "future schedule with unchanged fingerprint exits silently" testFutureUnchangedExitsSilently
registerTest "no stored fingerprint: a launch seeds it and it is not a change" testMissingFingerprintSeedsWithoutChange
registerTest "no stored fingerprint with a future schedule: no launch" testFutureSilentWithoutFingerprint
registerTest "fingerprint change launches declarationChange" testChangedFingerprintLaunchesDeclarationChange
registerTest "zero declarations give d41d8cd98f00b204e9800998ecf8427e" testZeroDeclarationsFingerprint
registerTest "due schedule plus changed fingerprint: change recorded NOTICE and scheduled launch" testDueScheduleRecordsChange
registerTest "unreadable or unrecognized persistence plist leaves the fingerprint untouched" testUnreadablePersistenceLeavesFingerprint
registerTest "post-boot: heartbeat 1 marks, heartbeat 2 launches postBoot, heartbeat 3 silent" testPostBootTwoHeartbeats
registerTest "console user loginwindow, root, _mbsetupuser, or none is not ready" testConsoleUserNotReady
registerTest "DarkWake: NOTICE, exit 0, state plist byte-identical" testDarkWakeDefers
registerTest "stale dor.pid (before boot, not running, PID 1, other process): WARNING then launch" testStalePidFile
registerTest "live main-script PID exits silently" testLivePidExitsSilently
registerTest "missing state plist reads as empty and launches" testMissingStatePlistLaunches
registerTest "invalid NextScheduledReminder: WARNING and launch" testInvalidScheduleLaunches
registerTest "state write failure (uchg) blocks a declarationChange launch with [ERROR]" testWriteFailureBlocksDeclarationChange
registerTest "state write failure (uchg) on a scheduled launch: [WARNING] … launching anyway" testWriteFailureWarnsForScheduledLaunch
