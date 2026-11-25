#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: launchDaemonManagement.zsh removeDeployedRuntimeAssets (redeploy vs. Uninstall)
#
####################################################################################################

function seedDeployedAssets() {
    local deadPid=""

    sleep 0 &
    deadPid=$!
    wait "${deadPid}" 2>/dev/null

    print "# dor.zsh" > "${dormScriptPath}"
    print "# dor-starter.zsh" > "${dorStarterPath}"
    print "${deadPid}" > "${dorPidFilePath}"
    print "" > "${dorAggressiveKillSwitchPath}"
    print "icon" > "${organizationDirectory}/dor-icon-macos-26.png"
    print "icon" > "${organizationDirectory}/dor-icon-overlay-light.png"
    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "2027-03-01T17:00:00"
    makeStatePlist "${dorStatePlistPath}" \
        "NextScheduledReminder=2026-12-01:08:00:00" \
        "LastDeclarationFingerprint=0123456789abcdef0123456789abcdef" \
        "LastDeclarationChangeDetected=2026-11-20:09:15:00" \
        "PostBootConsoleUserSeen=1795607315:tester" \
        "LastBootReevaluation=1795607315"
}

function testRedeployKeepsState() {
    loadDeploymentFunctions || return 0
    seedDeployedAssets
    ( removeDeployedRuntimeAssets "redeploy" ) > /dev/null 2>&1

    assertFileAbsent "dor.zsh removed" "${dormScriptPath}"
    assertFileAbsent "dor-starter.zsh removed" "${dorStarterPath}"
    assertFileAbsent "dor.pid removed" "${dorPidFilePath}"
    assertFileAbsent "fallback plist removed (rewritten by Parameters 5 and 6)" "${dorFallbackDeclarationPlistPath}"
    assertFileExists "dor-state.plist kept" "${dorStatePlistPath}"
    assertPlistKey "NextScheduledReminder cleared" "${dorStatePlistPath}" "NextScheduledReminder" "__absent__"
    assertPlistKey "LastDeclarationFingerprint kept" "${dorStatePlistPath}" "LastDeclarationFingerprint" "0123456789abcdef0123456789abcdef"
    assertPlistKey "LastDeclarationChangeDetected kept" "${dorStatePlistPath}" "LastDeclarationChangeDetected" "2026-11-20:09:15:00"
    assertPlistKey "PostBootConsoleUserSeen kept" "${dorStatePlistPath}" "PostBootConsoleUserSeen" "1795607315:tester"
    assertFileExists "kill switch kept" "${dorAggressiveKillSwitchPath}"
    assertFileExists "dor-icon-macos cache kept" "${organizationDirectory}/dor-icon-macos-26.png"
    assertFileExists "dor-icon-overlay cache kept" "${organizationDirectory}/dor-icon-overlay-light.png"
    assertContains "kill switch preserved NOTICE" "Preserving aggressive-mode support kill switch" "${scriptLog}"
    assertContains "cleared schedule NOTICE" "Cleared NextScheduledReminder so the refreshed heartbeat evaluates reminders immediately." "${scriptLog}"
}

function testUninstallRemovesEverything() {
    loadDeploymentFunctions || return 0
    seedDeployedAssets
    ( removeDeployedRuntimeAssets ) > /dev/null 2>&1

    assertFileAbsent "dor.zsh removed" "${dormScriptPath}"
    assertFileAbsent "dor-starter.zsh removed" "${dorStarterPath}"
    assertFileAbsent "dor.pid removed" "${dorPidFilePath}"
    assertFileAbsent "fallback plist removed" "${dorFallbackDeclarationPlistPath}"
    assertFileAbsent "dor-state.plist removed" "${dorStatePlistPath}"
    assertFileAbsent "kill switch removed" "${dorAggressiveKillSwitchPath}"
    assertFileAbsent "dor-icon-macos cache removed" "${organizationDirectory}/dor-icon-macos-26.png"
    assertFileAbsent "dor-icon-overlay cache removed" "${organizationDirectory}/dor-icon-overlay-light.png"
}

registerTest "redeploy keeps dor-state.plist (minus NextScheduledReminder), kill switch, and icon cache" testRedeployKeepsState
registerTest "Uninstall removes state, kill switch, icon cache, and scripts" testUninstallRemovesEverything
