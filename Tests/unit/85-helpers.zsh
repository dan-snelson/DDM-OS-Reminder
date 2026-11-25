#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: diagnose-client-state fixtures, diagnoseReminderState.zsh exit codes, and the Pending-OS EAs
#
####################################################################################################

helperEADeadline="2027-01-15T10:00:00"

function testDiagnoseFixtures() {
    local fixtureRc=0

    /bin/zsh "${repoRoot}/Resources/skills/diagnose-client-state/check-fixtures.zsh" > "${testDir}/check-fixtures.out" 2>&1
    fixtureRc=$?
    assertExit "check-fixtures.zsh" "0" "${fixtureRc}"
    (( fixtureRc == 0 )) || recordHaystackContext "${testDir}/check-fixtures.out"
}

function testDiagnoseExitCodes() {
    /bin/zsh "${repoRoot}/Resources/diagnoseReminderState.zsh" --help > /dev/null 2>&1
    assertExit "diagnoseReminderState.zsh --help" "0" "$?"

    /bin/zsh "${repoRoot}/Resources/diagnoseReminderState.zsh" --definitely-not-a-flag > /dev/null 2>&1
    assertExit "diagnoseReminderState.zsh with a bad flag" "64" "$?"
}

function runPendingEA() {
    local eaName="${1}"
    local persistencePath="${2}"

    env installLogPathOverride="${testDir}/install.log" \
        ddmStatePersistencePlistPathOverride="${persistencePath}" \
        currentVersionOverride="26.1" \
        currentBuildOverride="25B99" \
        /bin/zsh "${repoRoot}/Resources/JamfEA-Pending_OS_Update_${eaName}.zsh" 2>/dev/null
}

function testPendingEAs() {
    makeInstallLog "${testDir}/install.log" "$(ilDeclaration $(( $(date +%s) - 3600 )) "26.2" "${helperEADeadline}")"

    makePersistencePlist "${testDir}/persistence.plist" "26.2|${helperEADeadline}"
    assertEquals "Date EA, corroborated" "<result>2027-01-15 10:00:00</result>" "$(runPendingEA Date "${testDir}/persistence.plist")"
    assertEquals "Version EA, corroborated" "<result>26.2</result>" "$(runPendingEA Version "${testDir}/persistence.plist")"

    makePersistencePlist "${testDir}/persistence.plist" "26.3|2027-02-01T10:00:00"
    assertEquals "Date EA, uncorroborated declaration ignored (missing sentinel)" "<result>2000-01-01 00:00:03</result>" "$(runPendingEA Date "${testDir}/persistence.plist")"
    assertEquals "Version EA, uncorroborated declaration ignored" "<result>missing</result>" "$(runPendingEA Version "${testDir}/persistence.plist")"

    assertEquals "Date EA, persistence plist missing (install.log only)" "<result>2027-01-15 10:00:00</result>" "$(runPendingEA Date "${testDir}/absent.plist")"
    assertEquals "Version EA, persistence plist missing (install.log only)" "<result>26.2</result>" "$(runPendingEA Version "${testDir}/absent.plist")"
}

registerTest "Resources/skills/diagnose-client-state/check-fixtures.zsh exits 0" testDiagnoseFixtures
registerTest "diagnoseReminderState.zsh --help exits 0; a bad flag exits 64" testDiagnoseExitCodes
registerTest "Pending-OS EAs: corroborated, uncorroborated ignored, persistence missing" testPendingEAs
