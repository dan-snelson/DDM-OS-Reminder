#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: assemble.zsh for the test RDNN (runs in a work-directory copy; never touches Artifacts/)
#
####################################################################################################

function assembledArtifactOrFail() {
    assembledArtifact="$(ensureAssembledArtifact)"
    if [[ -z "${assembledArtifact}" || ! -f "${assembledArtifact}" ]]; then
        recordFailure "zsh assemble.zsh ${testRdnn} --lane test did not produce an assembled script (exit $(cat "${workDir}/assemble/assemble.rc" 2>/dev/null))"
        recordHaystackContext "${workDir}/assemble/assemble.out"
        return 1
    fi
    assembledPlist="$(print -r -- "${workDir}"/assemble/Artifacts/${testRdnn}.dorm-*-test.plist(N[1]))"
    assembledMobileconfig="$(print -r -- "${workDir}"/assemble/Artifacts/${testRdnn}.dorm-*-test-unsigned.mobileconfig(N[1]))"
}

function testAssembleRuns() {
    assembledArtifactOrFail || return 0
    assertExit "assemble.zsh exit status" "0" "$(cat "${workDir}/assemble/assemble.rc" 2>/dev/null || print 0)"
    assertFileExists "assembled .plist" "${assembledPlist}"
    assertFileExists "assembled unsigned .mobileconfig" "${assembledMobileconfig}"
}

function testNoProductionRdnn() {
    local artifactFile=""

    assembledArtifactOrFail || return 0
    for artifactFile in "${assembledArtifact}" "${assembledPlist}" "${assembledMobileconfig}"; do
        if grep -q 'org\.churchofjesuschrist' "${artifactFile}" 2>/dev/null; then
            recordFailure "org.churchofjesuschrist remains in ${artifactFile:t}: $(grep -n -m 3 'org\.churchofjesuschrist' "${artifactFile}" | tr '\n' ' ')"
        fi
    done
}

function testRdnnLines() {
    local rdnnLines=""

    assembledArtifactOrFail || return 0
    rdnnLines="$(grep -E '^reverseDomainNameNotation=' "${assembledArtifact}")"
    assertEquals "two reverseDomainNameNotation= lines (LDM + embedded RD)" "2" "$(print -r -- "${rdnnLines}" | grep -c .)"
    assertEquals "both reverseDomainNameNotation= lines rewritten" "2" "$(print -r -- "${rdnnLines}" | grep -c -F "reverseDomainNameNotation=\"${testRdnn}\"")"
}

function testScriptLogRewrite() {
    local beforeStarter=""

    assembledArtifactOrFail || return 0
    beforeStarter="$(awk '/^function createDorStarterScript\(\)/ { exit } { print }' "${assembledArtifact}")"
    assertEquals "scriptLog= lines before createDorStarterScript" "2" "$(print -r -- "${beforeStarter}" | grep -c -E '^scriptLog=')"
    assertEquals "scriptLog= lines point at the test RDNN log" "2" "$(print -r -- "${beforeStarter}" | grep -c -F "scriptLog=\"/var/log/${testRdnn}.log\"")"
    assertContains "embedded preferenceConfiguration scriptLog default" "[\"scriptLog\"]=\"string|/var/log/${testRdnn}.log\"" "${beforeStarter}"
}

function testStarterPlaceholders() {
    local extractionMessage=""

    assembledArtifactOrFail || return 0
    for placeholder in __SCRIPT_VERSION__ __SCRIPT_LOG__ __MAIN_SCRIPT_PATH__ __STATE_PLIST_PATH__ __PID_FILE_PATH__; do
        assertContains "starter placeholder ${placeholder} survives assembly" "=\"${placeholder}\"" "${assembledArtifact}"
    done
    if ! extractionMessage="$(extractStarter "${assembledArtifact}" "${testDir}/starter")"; then
        recordFailure "extractStarter on the assembled artifact failed: ${extractionMessage}"
    fi
}

function testDemoModeStripped() {
    assembledArtifactOrFail || return 0
    assertNotContains "Demo Mode header removed" "# Demo Mode (i.e., zsh" "${assembledArtifact}"
    assertNotContains "demo branch removed" 'if [[ "${1}" == "demo" ]]; then' "${assembledArtifact}"
    assertContains "embedded script tee commented out" '# | tee -a "${scriptLog}"' "${assembledArtifact}"
}

function testArtifactsLintAndSyntax() {
    local lintOutput=""
    local syntaxOutput=""

    assembledArtifactOrFail || return 0
    lintOutput="$(/usr/bin/plutil -lint "${assembledPlist}" 2>&1)" || recordFailure "plutil -lint .plist: ${lintOutput}"
    lintOutput="$(/usr/bin/plutil -lint "${assembledMobileconfig}" 2>&1)" || recordFailure "plutil -lint .mobileconfig: ${lintOutput}"
    syntaxOutput="$(/bin/zsh -n < "${assembledArtifact}" 2>&1)" || recordFailure "/bin/zsh -n assembled script: ${syntaxOutput}"
}

function testAssembleRejectsBogusLane() {
    local laneDirectory="${testDir}/lane"
    local laneRc=0

    mkdir -p "${laneDirectory}/Resources"
    cp "${asmPath}" "${ldmPath}" "${rdPath}" "${laneDirectory}/"
    cp "${repoRoot}/Resources/sample.plist" "${repoRoot}/Resources/localizationFilter.zsh" "${laneDirectory}/Resources/"

    ( cd "${laneDirectory}" && /bin/zsh assemble.zsh "${testRdnn}" --lane bogus < /dev/null > "${laneDirectory}/bogus.out" 2>&1 )
    laneRc=$?
    if (( laneRc == 0 )); then
        recordFailure "assemble.zsh --lane bogus exited 0; expected a failure"
    fi
    assertContains "invalid lane message" "Invalid lane" "${laneDirectory}/bogus.out"

    ( cd "${laneDirectory}" && /bin/zsh assemble.zsh --help < /dev/null > "${laneDirectory}/help.out" 2>&1 )
    assertExit "assemble.zsh --help" "0" "$?"
    assertContains "help text" "Usage:" "${laneDirectory}/help.out"
}

registerTest "assemble.zsh ${testRdnn} --lane test builds three artifacts" testAssembleRuns
registerTest "no org.churchofjesuschrist remains in .zsh, .plist, or .mobileconfig" testNoProductionRdnn
registerTest "both reverseDomainNameNotation= lines are rewritten" testRdnnLines
registerTest "scriptLog is /var/log/${testRdnn}.log before createDorStarterScript" testScriptLogRewrite
registerTest "starter placeholders are intact in the assembled script" testStarterPlaceholders
registerTest "Demo Mode block is stripped from the assembled script" testDemoModeStripped
registerTest "plutil -lint and zsh -n pass on the artifacts" testArtifactsLintAndSyntax
registerTest "--lane bogus fails and --help exits 0" testAssembleRejectsBogusLane
