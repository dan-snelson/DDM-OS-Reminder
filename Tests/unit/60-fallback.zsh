#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: DDM Emergency Fallback in reminderDialog.zsh (read / select / stale) and
# launchDaemonManagement.zsh (Parameters 5 and 6) (#182)
#
####################################################################################################

fallbackFutureDeadline="2027-03-01T17:00:00"

function testReadFallbackDeclarationValid() {
    local deadline=""

    loadRuntimeFunctions || return 0
    for deadline in "${fallbackFutureDeadline}" "2027-03-01T22:00:00Z" "2027-03-01T17:00:00-05:00"; do
        makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${deadline}"
        if readFallbackDeclaration; then
            assertEquals "version for '${deadline}'" "26.2" "${fallbackDeclarationVersion}"
            assertEquals "deadline kept verbatim for '${deadline}'" "${deadline}" "${fallbackDeclarationDeadline}"
        else
            recordFailure "readFallbackDeclaration rejected valid deadline '${deadline}': ${fallbackDeclarationReason}"
        fi
    done
}

function assertFallbackRejected() {
    local label="${1}"
    local expectedReason="${2}"

    if readFallbackDeclaration; then
        recordFailure "readFallbackDeclaration accepted ${label}"
        return 1
    fi
    assertContains "rejection reason for ${label}" "${expectedReason}" "${fallbackDeclarationReason}"
}

function testReadFallbackDeclarationRejects() {
    loadRuntimeFunctions || return 0

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}" 2
    assertFallbackRejected "SchemaVersion 2" "has an unexpected schema"

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}" 1 "SomeOtherSource"
    assertFallbackRejected "a different Source" "has an unexpected schema"

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}" 1 "JamfProScriptParameters" "25C56"
    assertFallbackRejected "BuildVersionString other than (null)" "has an unexpected schema"

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.x" "${fallbackFutureDeadline}"
    assertFallbackRejected "version 26.x" "macOS version '26.x' is invalid"

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "2026-02-30T10:00:00"
    assertFallbackRejected "deadline 2026-02-30T10:00:00" "deadline '2026-02-30T10:00:00' is invalid; redeploy with a valid Parameter 6"

    print "not a plist" > "${dorFallbackDeclarationPlistPath}"
    assertFallbackRejected "a corrupt plist" "is unreadable or corrupt"
}

function testSelectFallbackRequirement() {
    local selectStatus=0

    loadRuntimeFunctions || return 0

    selectMDMFallbackRequirement "missing" > /dev/null
    selectStatus=$?
    assertExit "absent plist is not selected" "1" "${selectStatus}"
    assertContains "absent plist NOTICE" "[NOTICE]          DDM Emergency Fallback not configured (dor-fallback-declaration.plist absent); nothing to fall back to (DDM status=missing)" "${scriptLog}"

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}" 1 "SomeOtherSource"
    selectMDMFallbackRequirement "conflict" > /dev/null
    selectStatus=$?
    assertExit "invalid plist is not selected" "1" "${selectStatus}"
    assertContains "invalid plist WARNING" "[WARNING]         DDM Emergency Fallback ignored:" "${scriptLog}"

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}"
    selectMDMFallbackRequirement "noMatch" > /dev/null
    selectStatus=$?
    assertExit "valid plist is selected" "0" "${selectStatus}"
    assertEquals "resolver status" "fallback" "${ddmResolverStatus}"
    assertEquals "fallback version" "26.2" "${ddmVersionString}"
    assertContains "selection NOTICE" "[NOTICE]          Using DDM Emergency Fallback: macOS 26.2, deadline ${fallbackFutureDeadline} (DDM status=noMatch)" "${scriptLog}"
}

# Run installedOSvsDDMenforcedOS with a stubbed resolver status; the fallback targets the installed
# version so a selected fallback returns "Up-to-date" without the dialog path
function runDecisionWithResolverStatus() {
    stubResolverStatus="${1}"
    stubResolverVersion="${2:-}"
    stubResolverDeadline="${3:-}"

    function sw_vers() {
        case "${1}" in
            -productVersion ) print "26.1" ;;
            -buildVersion   ) print "25B99" ;;
        esac
    }

    function resolveDDMEnforcementFromInstallLog() {
        ddmResolverStatus="${stubResolverStatus}"
        ddmResolverSource="stub"
        ddmResolverReason="stubbed ${stubResolverStatus}"
        ddmResolverConflictSummary=""
        ddmVersionString="${stubResolverVersion}"
        ddmEnforcedInstallDate="${stubResolverDeadline}"
        ddmBuildVersionString="(null)"
        ddmDeclarationRawLine="stub declaration line"
        [[ "${stubResolverStatus}" == "resolved" ]]
    }

    loadDefaultPreferences
    hideStagedInfo="YES"
    installedOSvsDDMenforcedOS > /dev/null 2>&1
}

function testFallbackEligibleStatuses() {
    local resolverStatus=""

    for resolverStatus in missing conflict noMatch invalidVersion; do
        (
            loadRuntimeFunctions || exit 0
            makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.1" "${fallbackFutureDeadline}"
            runDecisionWithResolverStatus "${resolverStatus}"
            assertEquals "status ${resolverStatus} selects the fallback" "fallback" "${ddmResolverStatus}"
            assertContains "status ${resolverStatus} logs the selection" "Using DDM Emergency Fallback: macOS 26.1, deadline ${fallbackFutureDeadline} (DDM status=${resolverStatus})" "${scriptLog}"
        )
    done
}

function testFallbackFailsClosedForOtherStatuses() {
    loadRuntimeFunctions || return 0
    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.1" "${fallbackFutureDeadline}"
    runDecisionWithResolverStatus "somethingNew"

    assertNotContains "unknown status never uses the fallback" "Using DDM Emergency Fallback" "${scriptLog}"
    assertContains "unknown status WARNING" "[WARNING]         Unrecognized DDM update check status 'somethingNew'; DDM Emergency Fallback is not eligible." "${scriptLog}"
    assertEquals "versionComparisonResult" "Unresolved DDM state (status=somethingNew)" "${versionComparisonResult}"
}

function testResolvedFallbackStaleness() {
    (
        loadRuntimeFunctions || exit 0
        makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.3" "${fallbackFutureDeadline}"
        runDecisionWithResolverStatus "resolved" "26.1" "2027-01-15T10:00:00"
        assertContains "stale fallback WARNING" "[WARNING]         DDM Emergency Fallback is stale: macOS 26.3 by ${fallbackFutureDeadline} vs DDM-enforced macOS 26.1 by 2027-01-15T10:00:00;" "${scriptLog}"
        assertContains "stale fallback Next step" "Next step: update Parameters 5 and 6 to match the DDM declaration" "${scriptLog}"
        assertNotContains "confirmed DDM still wins" "Using DDM Emergency Fallback" "${scriptLog}"
        assertEquals "resolver outcome unchanged" "Up-to-date" "${versionComparisonResult}"
    )
    (
        loadRuntimeFunctions || exit 0
        makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.1" "${fallbackFutureDeadline}" 1 "SomeOtherSource"
        runDecisionWithResolverStatus "resolved" "26.1" "2027-01-15T10:00:00"
        assertContains "invalid fallback WARNING" "[WARNING]         DDM Emergency Fallback would be ignored if needed:" "${scriptLog}"
    )
    (
        loadRuntimeFunctions || exit 0
        makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.1" "2027-01-15T10:00:00"
        runDecisionWithResolverStatus "resolved" "26.1" "2027-01-15T10:00:00"
        assertContains "matching fallback NOTICE" "DDM-enforced update found in install.log takes precedence over configured DDM Emergency Fallback." "${scriptLog}"
        assertNotContains "matching fallback is not stale" "is stale" "${scriptLog}"
    )
}

function prepareDeploymentFallback() {
    if [[ "$(id -u)" -ne 0 ]]; then
        skipTest "writeFallbackDeclarationPlist sets root:wheel ownership; needs root"
        return 1
    fi
    loadDeploymentFunctions || return 1
}

function testApplyFallbackZoneless() {
    prepareDeploymentFallback || return 0
    fallbackVersionString="26.2"
    fallbackEnforcedInstallDate="${fallbackFutureDeadline}"
    ( applyFallbackDeclarationParameters ) > /dev/null 2>&1

    assertPlistKey "Parameter 6 stored verbatim" "${dorFallbackDeclarationPlistPath}" "EnforcedInstallDate" "${fallbackFutureDeadline}"
    assertPlistKey "Parameter 5 stored" "${dorFallbackDeclarationPlistPath}" "VersionString" "26.2"
    assertContains "zone-less INFO" "[INFO]            DDM Emergency Fallback deadline has no timezone; each Mac reads it in its own local time (this Mac: UTC" "${scriptLog}"
    assertEquals "owner and mode" "root:wheel 644" "$(fileOwnerMode "${dorFallbackDeclarationPlistPath}")"
}

function testApplyFallbackPast() {
    prepareDeploymentFallback || return 0
    fallbackVersionString="26.2"
    fallbackEnforcedInstallDate="2020-01-01T00:00:00Z"
    ( applyFallbackDeclarationParameters ) > /dev/null 2>&1

    assertContains "past-deadline WARNING" "[WARNING]         DDM Emergency Fallback deadline '2020-01-01T00:00:00Z' is already in the past" "${scriptLog}"
    assertContains "past-deadline Next step" "Next step: confirm Parameter 6." "${scriptLog}"
    assertPlistKey "past deadline still written verbatim" "${dorFallbackDeclarationPlistPath}" "EnforcedInstallDate" "2020-01-01T00:00:00Z"
}

function testApplyFallbackMalformed() {
    prepareDeploymentFallback || return 0
    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}"
    fallbackVersionString="26.2"
    fallbackEnforcedInstallDate="2026-02-30T10:00:00"
    ( applyFallbackDeclarationParameters ) > /dev/null 2>&1

    assertContains "malformed P6 rejection" "[WARNING]         Rejected malformed DDM Emergency Fallback deadline from Parameter 6: '2026-02-30T10:00:00'" "${scriptLog}"
    assertContains "malformed P6 removal reason" "malformed deadline rejected" "${scriptLog}"
    assertFileAbsent "plist removed" "${dorFallbackDeclarationPlistPath}"
}

function testApplyFallbackPartialAndBlank() {
    prepareDeploymentFallback || return 0

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}"
    fallbackVersionString="26.2"
    fallbackEnforcedInstallDate=""
    ( applyFallbackDeclarationParameters ) > /dev/null 2>&1
    assertContains "partial pair WARNING" "[WARNING]         Rejected partial DDM Emergency Fallback; Parameters 5 and 6 must both be populated." "${scriptLog}"
    assertFileAbsent "partial pair removes the plist" "${dorFallbackDeclarationPlistPath}"

    makeFallbackPlist "${dorFallbackDeclarationPlistPath}" "26.2" "${fallbackFutureDeadline}"
    fallbackVersionString=""
    fallbackEnforcedInstallDate=""
    ( applyFallbackDeclarationParameters ) > /dev/null 2>&1
    assertContains "blank pair removal" "Removed DDM Emergency Fallback plist (intentionally disabled by blank Parameters 5 and 6)" "${scriptLog}"
    assertFileAbsent "blank pair removes the plist" "${dorFallbackDeclarationPlistPath}"
}

registerTest "readFallbackDeclaration accepts zone-less, Z, and offset deadlines" testReadFallbackDeclarationValid
registerTest "readFallbackDeclaration rejects bad schema, Source, BuildVersionString, version, 2026-02-30, corrupt plist" testReadFallbackDeclarationRejects
registerTest "selectMDMFallbackRequirement: absent NOTICE, invalid WARNING, valid selected" testSelectFallbackRequirement
registerTest "missing, conflict, noMatch, invalidVersion use the fallback" testFallbackEligibleStatuses
registerTest "any other resolver status fails closed" testFallbackFailsClosedForOtherStatuses
registerTest "resolved DDM: stale fallback WARNING, invalid fallback WARNING, matching fallback NOTICE" testResolvedFallbackStaleness
registerTest "LDM P6 zone-less: plist verbatim and no-timezone INFO" testApplyFallbackZoneless
registerTest "LDM P6 in the past: WARNING + Next step, plist still written" testApplyFallbackPast
registerTest "LDM P6 malformed: rejected and plist removed" testApplyFallbackMalformed
registerTest "LDM partial pair rejected; blank pair removes the plist" testApplyFallbackPartialAndBlank
