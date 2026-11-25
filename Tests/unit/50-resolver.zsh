#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: resolveDDMEnforcementFromInstallLog with install.log and persistence fixtures (#178 + regressions)
#
####################################################################################################

# Fixed install.log timeline (past) and a future declared deadline
resolverT1=$(( $(date +%s) - 7200 ))
resolverT2=$(( resolverT1 + 60 ))
resolverT3=$(( resolverT1 + 120 ))
resolverDeadline="2027-01-15T10:00:00"

function prepareResolver() {
    loadRuntimeFunctions || return 1
    installedmacOSVersion="${1}"
    installedmacOSBuild="25Z999"
}

function runResolver() {
    resolveDDMEnforcementFromInstallLog > /dev/null 2>&1
    resolverReturn=$?
}

function testResolvedAndCorroborated() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" "$(ilGeneric "${resolverT1}")" "$(ilDeclaration "${resolverT2}" "26.2" "${resolverDeadline}")"
    makePersistencePlist "${ddmStatePersistencePlistPath}" "26.2|${resolverDeadline}"
    runResolver

    assertExit "resolver return" "0" "${resolverReturn}"
    assertEquals "status" "resolved" "${ddmResolverStatus}"
    assertEquals "version" "26.2" "${ddmVersionString}"
    assertEquals "deadline" "${resolverDeadline}" "${ddmEnforcedInstallDate}"
    assertEquals "persistence status" "available" "${ddmStatePersistenceStatus}"
    assertNotContains "no WARNING" "[WARNING]" "${scriptLog}"
}

function testPersistenceMissingTrustsInstallLog() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" "$(ilDeclaration "${resolverT2}" "26.2" "${resolverDeadline}")"
    runResolver

    assertEquals "status" "resolved" "${ddmResolverStatus}"
    assertContains "trusting-uncorroborated WARNING" "[WARNING]         softwareupdate DDM state is unavailable at '${ddmStatePersistencePlistPath}'; trusting uncorroborated install.log declarations." "${scriptLog}"
}

function testUncorroboratedAlreadyMet() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" "$(ilDeclaration "${resolverT2}" "15.7.1" "2026-10-20T09:00:00")"
    makePersistencePlist "${ddmStatePersistencePlistPath}"
    runResolver

    assertEquals "status" "missing" "${ddmResolverStatus}"
    assertContains "already-met NOTICE" "[NOTICE]          Ignoring 1 install.log DDM declaration(s) absent from softwareupdate DDM state; macOS 26.1 already meets them;" "${scriptLog}"
    assertNotContains "no WARNING" "[WARNING]" "${scriptLog}"
}

function testUncorroboratedNewer() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" "$(ilDeclaration "${resolverT2}" "26.2" "${resolverDeadline}")"
    makePersistencePlist "${ddmStatePersistencePlistPath}" "26.3|2027-02-01T10:00:00"
    runResolver

    assertEquals "status" "missing" "${ddmResolverStatus}"
    assertContains "uncorroborated WARNING" "[WARNING]         Ignoring 1 install.log DDM declaration(s) absent from softwareupdate DDM state; latest:" "${scriptLog}"
    assertNotContains "no already-met NOTICE" "already meets them" "${scriptLog}"
}

function testUncorroboratedMixed() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" \
        "$(ilDeclaration "${resolverT1}" "15.7.1" "2026-10-20T09:00:00")" \
        "$(ilDeclaration "${resolverT2}" "27.0" "${resolverDeadline}")"
    makePersistencePlist "${ddmStatePersistencePlistPath}"
    runResolver

    assertContains "mixed met/unmet WARNING" "[WARNING]         Ignoring 2 install.log DDM declaration(s) absent from softwareupdate DDM state; latest:" "${scriptLog}"
    assertNotContains "no already-met NOTICE" "already meets them" "${scriptLog}"
}

function testConflictNoUpdatesFound() {
    local installedVersion="${1}"
    local expectedLevel="${2}"

    prepareResolver "${installedVersion}" || return 0
    makeInstallLog "${installLogPath}" \
        "$(ilDeclaration "${resolverT1}" "26.2" "${resolverDeadline}")" \
        "$(ilNoUpdates "${resolverT2}")" \
        "$(ilDeclaration "${resolverT3}" "26.2" "${resolverDeadline}")"
    makePersistencePlist "${ddmStatePersistencePlistPath}" "26.2|${resolverDeadline}"
    runResolver

    assertEquals "status" "conflict" "${ddmResolverStatus}"
    assertEquals "conflict summary" "Declaration persisted after 'No updates found for DDM to enforce'" "${ddmResolverConflictSummary}"
    if [[ "${expectedLevel}" == "NOTICE" ]]; then
        assertContains "NOTICE when macOS ${installedVersion} meets 26.2" "[NOTICE]          softwareupdated found no update to enforce, yet DDM-enforced macOS 26.2 is still declared: Declaration persisted after 'No updates found for DDM to enforce'; macOS ${installedVersion} already meets it" "${scriptLog}"
    else
        assertContains "WARNING when macOS ${installedVersion} does not meet 26.2" "[WARNING]         softwareupdated found no update to enforce, yet DDM-enforced macOS 26.2 is still declared: Declaration persisted after 'No updates found for DDM to enforce'" "${scriptLog}"
    fi
}

function testConflictAvailableDescriptor() {
    local installedVersion="${1}"
    local expectedLevel="${2}"

    prepareResolver "${installedVersion}" || return 0
    makeInstallLog "${installLogPath}" \
        "$(ilDeclaration "${resolverT1}" "26.2" "${resolverDeadline}")" \
        "$(ilDescriptor "${resolverT2}" "27.2")"
    makePersistencePlist "${ddmStatePersistencePlistPath}" "26.2|${resolverDeadline}"
    runResolver

    assertEquals "status" "conflict" "${ddmResolverStatus}"
    assertEquals "conflict summary" "Available descriptor 27.2 disagrees with DDM declaration 26.2" "${ddmResolverConflictSummary}"
    if [[ "${expectedLevel}" == "NOTICE" ]]; then
        assertContains "NOTICE when macOS ${installedVersion} meets 26.2" "[NOTICE]          softwareupdated offers macOS 27.2, not DDM-enforced macOS 26.2: Available descriptor 27.2 disagrees with DDM declaration 26.2; macOS ${installedVersion} already meets it" "${scriptLog}"
    else
        assertContains "WARNING when macOS ${installedVersion} does not meet 26.2" "[WARNING]         softwareupdated offers macOS 27.2, not DDM-enforced macOS 26.2: Available descriptor 27.2 disagrees with DDM declaration 26.2" "${scriptLog}"
    fi
}

function testConflictingCandidates() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" \
        "$(ilDeclaration "${resolverT2}" "26.2" "${resolverDeadline}")" \
        "$(ilDeclaration "${resolverT2}" "26.3" "2027-02-01T10:00:00")"
    makePersistencePlist "${ddmStatePersistencePlistPath}" "26.2|${resolverDeadline}" "26.3|2027-02-01T10:00:00"
    runResolver

    assertEquals "status" "conflict" "${ddmResolverStatus}"
    assertContains "conflicting candidates WARNING" "[WARNING]         install.log shows conflicting DDM-enforced macOS updates" "${scriptLog}"
}

function testInvalidVersion() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" "$(ilDeclaration "${resolverT2}" "26.x" "${resolverDeadline}")"
    makePersistencePlist "${ddmStatePersistencePlistPath}" "26.x|${resolverDeadline}"
    runResolver

    assertEquals "status" "invalidVersion" "${ddmResolverStatus}"
    assertContains "invalidVersion WARNING" "[WARNING]         DDM-enforced macOS version in install.log is invalid: 26.x" "${scriptLog}"
}

function testNoMatch() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" \
        "$(ilDeclaration "${resolverT1}" "26.2" "${resolverDeadline}")" \
        "$(ilRequestedPMV "${resolverT2}" "26.2")" \
        "$(ilNoMatch "${resolverT3}")"
    makePersistencePlist "${ddmStatePersistencePlistPath}" "26.2|${resolverDeadline}"
    runResolver

    assertEquals "status" "noMatch" "${ddmResolverStatus}"
    assertEquals "failure marker" "MADownloadNoMatchFound" "${ddmResolverFailureMarker}"
}

function testMissing() {
    prepareResolver "26.1" || return 0
    makeInstallLog "${installLogPath}" "$(ilGeneric "${resolverT1}")"
    makePersistencePlist "${ddmStatePersistencePlistPath}"
    runResolver

    assertEquals "status (no declaration)" "missing" "${ddmResolverStatus}"
    assertEquals "reason (no declaration)" "No DDM-enforced macOS update found in install.log" "${ddmResolverReason}"

    rm -f "${installLogPath}"
    runResolver
    assertEquals "status (install.log missing)" "missing" "${ddmResolverStatus}"
    assertEquals "reason (install.log missing)" "install.log is missing or unreadable" "${ddmResolverReason}"
}

registerTest "resolved and corroborated by the persistence plist" testResolvedAndCorroborated
registerTest "persistence plist missing: trusting-uncorroborated WARNING" testPersistenceMissingTrustsInstallLog
registerTest "uncorroborated declaration already met: NOTICE" testUncorroboratedAlreadyMet
registerTest "uncorroborated declaration targeting a newer version: WARNING" testUncorroboratedNewer
registerTest "uncorroborated mixed met/unmet set: WARNING" testUncorroboratedMixed
registerTest "conflict 'Declaration persisted after No updates found', met: NOTICE" testConflictNoUpdatesFound "26.2" NOTICE
registerTest "conflict 'Declaration persisted after No updates found', unmet: WARNING" testConflictNoUpdatesFound "26.1" WARNING
registerTest "conflict 'Available descriptor … disagrees', met: NOTICE" testConflictAvailableDescriptor "26.3" NOTICE
registerTest "conflict 'Available descriptor … disagrees', unmet: WARNING" testConflictAvailableDescriptor "26.1" WARNING
registerTest "conflict between two latest candidates: WARNING" testConflictingCandidates
registerTest "invalidVersion" testInvalidVersion
registerTest "noMatch (MADownloadNoMatchFound after requestedPMV)" testNoMatch
registerTest "missing (no declaration, and install.log absent)" testMissing
