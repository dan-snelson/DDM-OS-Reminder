#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: syntax, scriptVersion alignment, release versions, and the extraction count checks
#
####################################################################################################

function testSyntax() {
    local scriptPath="${1}"
    local syntaxOutput=""

    # stdin form: `zsh -n <path>` can hang on very large scripts in some shells
    if ! syntaxOutput="$(/bin/zsh -n < "${scriptPath}" 2>&1)"; then
        recordFailure "/bin/zsh -n < ${scriptPath#${repoRoot}/} failed"
        recordFailure "  ${syntaxOutput//$'\n'/ | }"
    fi
}

function testScriptVersionAlignment() {
    local asmVersion="$(scriptVersionOf "${asmPath}")"

    assertMatches "assemble.zsh scriptVersion format" '^[0-9]+\.[0-9]+\.[0-9]+' "${asmVersion}"
    assertEquals "launchDaemonManagement.zsh scriptVersion equals assemble.zsh" "${asmVersion}" "$(scriptVersionOf "${ldmPath}")"
    assertEquals "reminderDialog.zsh scriptVersion equals assemble.zsh" "${asmVersion}" "$(scriptVersionOf "${rdPath}")"
}

function testReleaseVersions() {
    if [[ -z "${releaseVersion}" ]]; then
        skipTest "no --release given; scripts $(scriptVersionOf "${rdPath}"), CHANGELOG '$(changelogTopHeading)'"
        return 0
    fi

    assertEquals "assemble.zsh scriptVersion" "${releaseVersion}" "$(scriptVersionOf "${asmPath}")"
    assertEquals "launchDaemonManagement.zsh scriptVersion" "${releaseVersion}" "$(scriptVersionOf "${ldmPath}")"
    assertEquals "reminderDialog.zsh scriptVersion" "${releaseVersion}" "$(scriptVersionOf "${rdPath}")"
    assertEquals "CHANGELOG.md top heading" "### Version ${releaseVersion}" "$(changelogTopHeading)"
}

function testDiagnoseHelperVersion() {
    local helperVersion="$(scriptVersionOf "${repoRoot}/Resources/diagnoseReminderState.zsh")"
    local changelogVersion=""

    # Highest `Resources/diagnoseReminderState.zsh` (`x.y.z`) named anywhere in CHANGELOG.md
    changelogVersion="$(grep -o -E '`Resources/diagnoseReminderState\.zsh` \(`[0-9]+\.[0-9]+\.[0-9]+`\)' "${changelogPath}" \
        | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"

    assertMatches "CHANGELOG names a diagnoseReminderState.zsh version" '^[0-9]+\.[0-9]+\.[0-9]+$' "${changelogVersion}"
    assertEquals "diagnoseReminderState.zsh scriptVersion equals highest CHANGELOG helper version" "${changelogVersion}" "${helperVersion}"
}

function testExtractionCounts() {
    local which="${1}"
    local functionsFile=""

    if ! functionsFile="$(preparedExtraction "${which}" 2>"${testDir}/extract.err")"; then
        recordFailure "extractFunctions failed for ${which}: $(cat "${testDir}/extract.err")"
        return 0
    fi

    assertMatches "extraction summary for ${which}" '^[0-9]+ functions extracted' "$(cat "${functionsFile}.summary")"
}

function testStarterExtraction() {
    local extractionMessage=""

    if ! extractionMessage="$(extractStarter "${ldmPath}" "${testDir}/starter")"; then
        recordFailure "extractStarter failed: ${extractionMessage}"
        return 0
    fi
    assertFileExists "extracted starter" "${testDir}/starter/dor-starter.zsh"
    assertFileExists "stub main script" "${testDir}/starter/dor.zsh"
}

registerTest "zsh -n reminderDialog.zsh" testSyntax "${rdPath}"
registerTest "zsh -n launchDaemonManagement.zsh" testSyntax "${ldmPath}"
registerTest "zsh -n assemble.zsh" testSyntax "${asmPath}"
for syntaxTarget in "${repoRoot}"/Resources/*.zsh(N) "${repoRoot}"/Resources/skills/*/*.zsh(N) "${testsRoot}"/**/*.zsh(N); do
    registerTest "zsh -n ${syntaxTarget#${repoRoot}/}" testSyntax "${syntaxTarget}"
done
unset syntaxTarget
registerTest "scriptVersion is equal in assemble.zsh, launchDaemonManagement.zsh, and reminderDialog.zsh" testScriptVersionAlignment
registerTest "--release version matches every scriptVersion and the CHANGELOG heading" testReleaseVersions
registerTest "diagnoseReminderState.zsh scriptVersion matches the highest helper version in CHANGELOG" testDiagnoseHelperVersion
registerTest "extractFunctions reminderDialog.zsh: count check and zsh -n" testExtractionCounts rd
registerTest "extractFunctions launchDaemonManagement.zsh: count check and zsh -n (starter heredoc skipped)" testExtractionCounts ldm
registerTest "extractStarter launchDaemonManagement.zsh: placeholders, rewrites, and zsh -n" testStarterExtraction
