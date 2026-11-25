#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Integration: deploy the assembled com.example.dortest artifact in Script mode only
#
# Never runs LDM All, LaunchDaemon, or Uninstall: those modes glob /Library/LaunchDaemons/*.dor.plist
# and would boot out the production org.churchofjesuschrist.dor daemon.
#
####################################################################################################

deployFutureDeadline="$(localISO8601 $(( $(date +%s) + 90 * 86400 )))"
deployPastDeadline="2020-01-01T00:00:00"

# Keep live heartbeat runs quiet: a fresh interaction (quiet period), the aggressive-mode kill switch,
# and MeetingDelay 0 (no display-sleep-assertion wait) in the test domain's local preferences
function prepareIntegrationEnvironment() {
    refuseProductionRdnn
    integrationPaths

    mkdir -p "${testManagementDirectory}"
    chown root:wheel "${testManagementDirectory}"
    chmod 755 "${testManagementDirectory}"
    : > "${testKillSwitch}"
    chown root:wheel "${testKillSwitch}"
    chmod 644 "${testKillSwitch}"

    rm -f "${testLocalPreferences}"
    /usr/bin/plutil -create xml1 "${testLocalPreferences}"
    /usr/bin/plutil -insert MeetingDelay -integer 0 "${testLocalPreferences}"
    chmod 644 "${testLocalPreferences}"

    seedInteraction
}

function requireDeployment() {
    integrationPaths
    [[ -x "${testDorScript}" && -f "${testLaunchDaemonPlist}" ]] && return 0
    skipTest "the ${testRdnn} deployment did not complete"
    return 1
}

function waitForStatePlist() {
    local waited=0

    while [[ ! -f "${testStatePlist}" ]] && (( waited < 30 )); do
        sleep 0.5
        (( waited++ ))
    done
}

function testInitialDeploy() {
    local deployRc=0

    prepareIntegrationEnvironment
    deployTestArtifact "${testDir}/deploy.out" "99.0" "${deployFutureDeadline}"
    deployRc=$?

    assertExit "Script-mode deploy" "0" "${deployRc}"
    (( deployRc == 98 )) && recordFailure "no assembled artifact; see unit/assemble"
    assertEquals "dor.zsh owner and mode" "root:wheel 755" "$(fileOwnerMode "${testDorScript}")"
    assertEquals "dor-starter.zsh owner and mode" "root:wheel 755" "$(fileOwnerMode "${testStarterScript}")"
    assertEquals "LaunchDaemon owner and mode" "root:wheel 644" "$(fileOwnerMode "${testLaunchDaemonPlist}")"
    assertEquals "fallback plist owner and mode" "root:wheel 644" "$(fileOwnerMode "${testFallbackPlist}")"
    launchctl print "system/${testLaunchDaemonLabel}" > /dev/null 2>&1
    assertExit "launchctl print system/${testLaunchDaemonLabel}" "0" "$?"
    assertPlistKey "Parameter 6 stored verbatim" "${testFallbackPlist}" "EnforcedInstallDate" "${deployFutureDeadline}"
    assertPlistKey "Parameter 5 stored" "${testFallbackPlist}" "VersionString" "99.0"
    assertContains "zone-less INFO" "DDM Emergency Fallback deadline has no timezone; each Mac reads it in its own local time" "${testDir}/deploy.out"
    assertNotContains "production daemon never touched" "${productionDaemonLabel}" "${testDir}/deploy.out"

    waitForStatePlist
    assertEquals "dor-state.plist (written by the first heartbeat) owner and mode" "root:wheel 644" "$(fileOwnerMode "${testStatePlist}")"
}

function testDeployPastDeadline() {
    requireDeployment || return 0
    deployTestArtifact "${testDir}/deploy.out" "99.0" "${deployPastDeadline}"

    assertContains "past-deadline WARNING" "DDM Emergency Fallback deadline '${deployPastDeadline}' is already in the past" "${testDir}/deploy.out"
    assertPlistKey "past deadline still written" "${testFallbackPlist}" "EnforcedInstallDate" "${deployPastDeadline}"
}

function testDeployMalformedDeadline() {
    requireDeployment || return 0
    deployTestArtifact "${testDir}/deploy.out" "99.0" "2026-02-30T10:00:00"

    assertContains "malformed P6 rejected" "Rejected malformed DDM Emergency Fallback deadline from Parameter 6: '2026-02-30T10:00:00'" "${testDir}/deploy.out"
    assertFileAbsent "fallback plist removed" "${testFallbackPlist}"
}

function testDeployBlankPair() {
    requireDeployment || return 0
    deployTestArtifact "${testDir}/deploy-valid.out" "99.0" "${deployFutureDeadline}"
    assertFileExists "fallback plist present before the blank pair" "${testFallbackPlist}"

    deployTestArtifact "${testDir}/deploy.out" "" ""
    assertContains "blank pair removal" "intentionally disabled by blank Parameters 5 and 6" "${testDir}/deploy.out"
    assertFileAbsent "fallback plist removed" "${testFallbackPlist}"
}

function testRedeployPreservesState() {
    local storedFingerprint=""
    local startLine=0

    requireDeployment || return 0
    waitForStatePlist
    storedFingerprint="$(persistencePlistFingerprint /var/db/softwareupdate/SoftwareUpdateDDMStatePersistence.plist)" || storedFingerprint="0123456789abcdef0123456789abcdef"
    setStateKey "${testStatePlist}" LastDeclarationFingerprint "${storedFingerprint}"
    setStateKey "${testStatePlist}" LastDeclarationChangeDetected "2026-01-01:00:00:00"
    setStateKey "${testStatePlist}" NextScheduledReminder "$(stateTimestamp $(( $(date +%s) + 7200 )))"
    : > "${testKillSwitch}"
    seedInteraction
    startLine="$(logLineCount "${testScriptLog}")"

    deployTestArtifact "${testDir}/deploy.out" "99.0" "${deployFutureDeadline}"

    assertContains "state preserved NOTICE" "Preserving scheduler state" "${testDir}/deploy.out"
    assertContains "NextScheduledReminder cleared" "Cleared NextScheduledReminder so the refreshed heartbeat evaluates reminders immediately." "${testDir}/deploy.out"
    assertContains "kill switch preserved NOTICE" "Preserving aggressive-mode support kill switch" "${testDir}/deploy.out"
    assertPlistKey "LastDeclarationFingerprint kept" "${testStatePlist}" "LastDeclarationFingerprint" "${storedFingerprint}"
    assertPlistKey "LastDeclarationChangeDetected kept" "${testStatePlist}" "LastDeclarationChangeDetected" "2026-01-01:00:00:00"
    assertFileExists "dor-aggressive-kill kept" "${testKillSwitch}"
    if ! waitForLogText "${testScriptLog}" "Heartbeat launch triggered '${testDorScript}'." "${startLine}" 15; then
        recordFailure "the cleared schedule did not produce a heartbeat launch within 15 s"
        recordHaystackContext "${testScriptLog}"
    fi
}

registerTest "deploy Script 99.0 <future zone-less>: files, owners, modes, launchctl, verbatim P6, INFO" testInitialDeploy
registerTest "redeploy with a past P6: WARNING and plist written" testDeployPastDeadline
registerTest "redeploy with a malformed P6: rejected and plist removed" testDeployMalformedDeadline
registerTest "redeploy with blank P5/P6 removes the plist" testDeployBlankPair
registerTest "redeploy keeps fingerprint, change time, and kill switch; clears NextScheduledReminder" testRedeployPreservesState
