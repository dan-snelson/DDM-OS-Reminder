#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Integration (headless): manual runs of the deployed dor.zsh with install.log / persistence fixtures
# through the existing installLogPathOverride and ddmStatePersistencePlistPathOverride hooks.
#
# Manual runs never mutate scheduler state and log to stdout only (assemble.zsh comments out tee),
# so assertions read the captured output. Every scenario either exits before the reminder dialog
# (no random 30-90 s pause, no display-sleep-assertion wait) or fails fatally.
#
####################################################################################################

function requireFixtureRun() {
    integrationPaths
    if [[ ! -x "${testDorScript}" || ! -f "${testStatePlist}" ]]; then
        skipTest "the ${testRdnn} deployment did not complete"
        return 1
    fi
    requireConsoleUser || return 1
    if [[ "${consoleDependentScenarios}" != "YES" ]]; then
        skipTest "console-dependent scenario skipped"
        return 1
    fi

    # Keep the live heartbeat out of the way and start each scenario without a fallback plist
    waitForIdleRuntime
    setStateKey "${testStatePlist}" NextScheduledReminder "FALSE"
    rm -f "${testFallbackPlist}"
    installedVersionForTest="$(sw_vers -productVersion)"
}

function runDeployedWithFixtures() {
    runWithTimeout 120 "${testDir}/run.out" env \
        installLogPathOverride="${testDir}/install.log" \
        ddmStatePersistencePlistPathOverride="${testDir}/persistence.plist" \
        /bin/zsh "${testDorScript}"
}

function testUncorroboratedMetNotice() {
    requireFixtureRun || return 0
    makeInstallLog "${testDir}/install.log" "$(ilDeclaration $(( $(date +%s) - 3600 )) "15.0" "2025-01-01T10:00:00")"
    makePersistencePlist "${testDir}/persistence.plist"
    runDeployedWithFixtures

    assertContains "already-met NOTICE" "[NOTICE]          Ignoring 1 install.log DDM declaration(s) absent from softwareupdate DDM state; macOS ${installedVersionForTest} already meets them;" "${testDir}/run.out"
    assertContains "no reminder" "No reminder shown:" "${testDir}/run.out"
}

function testImpossibleDeadlineFatal() {
    requireFixtureRun || return 0
    makeInstallLog "${testDir}/install.log" "$(ilDeclaration $(( $(date +%s) - 3600 )) "99.0" "2026-02-30T10:00:00")"
    makePersistencePlist "${testDir}/persistence.plist" "99.0|2026-02-30T10:00:00"
    runDeployedWithFixtures

    assertContains "impossible deadline is fatal" "[FATAL ERROR]     Unable to parse DDM-enforced requirement deadline: 2026-02-30T10:00:00 (not a valid calendar date and time)" "${testDir}/run.out"
}

function testResolvedWithStaleFallback() {
    local declaredDeadline="$(localISO8601 $(( $(date +%s) + 30 * 86400 )))"

    requireFixtureRun || return 0
    makeInstallLog "${testDir}/install.log" "$(ilDeclaration $(( $(date +%s) - 3600 )) "${installedVersionForTest}" "${declaredDeadline}")"
    makePersistencePlist "${testDir}/persistence.plist" "${installedVersionForTest}|${declaredDeadline}"
    makeFallbackPlist "${testFallbackPlist}" "99.0" "$(localISO8601 $(( $(date +%s) + 40 * 86400 )))"
    runDeployedWithFixtures
    rm -f "${testFallbackPlist}"

    assertContains "stale fallback WARNING" "[WARNING]         DDM Emergency Fallback is stale: macOS 99.0 by" "${testDir}/run.out"
    assertContains "resolver outcome unchanged (resolved)" "DDM update check: found DDM-enforced macOS ${installedVersionForTest}" "${testDir}/run.out"
    assertContains "resolver outcome unchanged (compliant)" "already meets DDM-enforced macOS ${installedVersionForTest}" "${testDir}/run.out"
    assertNotContains "fallback not used" "Using DDM Emergency Fallback" "${testDir}/run.out"
}

function testResolvedWithInvalidFallback() {
    local declaredDeadline="$(localISO8601 $(( $(date +%s) + 30 * 86400 )))"

    requireFixtureRun || return 0
    makeInstallLog "${testDir}/install.log" "$(ilDeclaration $(( $(date +%s) - 3600 )) "${installedVersionForTest}" "${declaredDeadline}")"
    makePersistencePlist "${testDir}/persistence.plist" "${installedVersionForTest}|${declaredDeadline}"
    makeFallbackPlist "${testFallbackPlist}" "99.0" "${declaredDeadline}" 1 "SomeOtherSource"
    runDeployedWithFixtures
    rm -f "${testFallbackPlist}"

    assertContains "invalid fallback WARNING" "[WARNING]         DDM Emergency Fallback would be ignored if needed:" "${testDir}/run.out"
}

# Update required, deadline 120 days out (beyond DaysBeforeDeadlineDisplayReminder 60)
function prepareOutsideWindow() {
    local declaredDeadline="$(localISO8601 $(( $(date +%s) + 120 * 86400 )))"

    makeInstallLog "${testDir}/install.log" "$(ilDeclaration $(( $(date +%s) - 3600 )) "99.0" "${declaredDeadline}")"
    makePersistencePlist "${testDir}/persistence.plist" "99.0|${declaredDeadline}"
    setStateKey "${testStatePlist}" LastDeclarationChangeDetected "${1}"
    sleep 1
    seedInteraction
}

function assertOutsideWindowSuppressed() {
    assertContains "${1}: suppressed outside the display window" "No reminder shown: deadline is" "${testDir}/run.out"
    assertContains "${1}: periodic reminder not due" "the last reminder was 0 day(s) ago" "${testDir}/run.out"
    assertNotContains "${1}: interaction not ignored" "Ignoring reminder interaction from" "${testDir}/run.out"
}

function testOutsideWindowInteractionAfterChange() {
    requireFixtureRun || return 0
    prepareOutsideWindow "$(stateTimestamp $(( $(date +%s) - 3600 )))"
    runDeployedWithFixtures
    assertOutsideWindowSuppressed "interaction after the change time"
}

function testOutsideWindowInvalidChangeTime() {
    requireFixtureRun || return 0
    prepareOutsideWindow "garbage"
    runDeployedWithFixtures
    assertContains "invalid change time WARNING" "[WARNING]         Invalid LastDeclarationChangeDetected 'garbage'; using all reminder interaction history." "${testDir}/run.out"
    assertOutsideWindowSuppressed "invalid change time"
}

function testOutsideWindowFutureChangeTime() {
    local futureChange="$(stateTimestamp $(( $(date +%s) + 86400 )))"

    requireFixtureRun || return 0
    prepareOutsideWindow "${futureChange}"
    runDeployedWithFixtures
    assertContains "future change time WARNING" "[WARNING]         LastDeclarationChangeDetected '${futureChange}' is in the future; using all reminder interaction history." "${testDir}/run.out"
    assertOutsideWindowSuppressed "future change time"
    deleteStateKey "${testStatePlist}" LastDeclarationChangeDetected
}

registerTest "uncorroborated but already-met declaration: NOTICE" testUncorroboratedMetNotice
registerTest "impossible deadline 2026-02-30: [FATAL ERROR] not a valid calendar date and time" testImpossibleDeadlineFatal
registerTest "resolved DDM + stale fallback: WARNING, resolver outcome unchanged" testResolvedWithStaleFallback
registerTest "resolved DDM + invalid fallback: would be ignored if needed" testResolvedWithInvalidFallback
registerTest "outside window, interaction after the change time: suppressed" testOutsideWindowInteractionAfterChange
registerTest "outside window, invalid LastDeclarationChangeDetected: WARNING, still suppressed" testOutsideWindowInvalidChangeTime
registerTest "outside window, future LastDeclarationChangeDetected: WARNING, still suppressed" testOutsideWindowFutureChangeTime
