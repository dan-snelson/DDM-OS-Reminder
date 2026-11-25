#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Integration (dialogs): real swiftDialog windows confirmed by the person at the Mac.
# Left out by --skip-dialogs.
#
# The deployed dor.zsh has no demo mode (assemble.zsh strips it), so demo runs use a work-directory
# copy of this checkout's reminderDialog.zsh with its RDNN and scriptLog rewritten to the test RDNN.
#
####################################################################################################

interactionReturnCodePattern='Return Code: (0|2|3|4|10)'

function requireDialogs() {
    integrationPaths
    if [[ "${skipDialogs}" == "YES" ]]; then
        skipTest "--skip-dialogs"
        return 1
    fi
    if [[ ! -x "${testDorScript}" || ! -f "${testStatePlist}" ]]; then
        skipTest "the ${testRdnn} deployment did not complete"
        return 1
    fi
    requireConsoleUser || return 1
    if [[ ! -r /dev/tty ]]; then
        skipTest "no terminal to confirm what the dialog showed"
        return 1
    fi
    waitForIdleRuntime
    setStateKey "${testStatePlist}" NextScheduledReminder "FALSE"
    rm -f "${testFallbackPlist}"
}

function confirmDialog() {
    local question="${1}"
    local answerStatus=0

    askTester "${question}"
    answerStatus=$?
    case "${answerStatus}" in
        0 ) return 0 ;;
        2 ) skipTest "no terminal answer for: ${question}" ;;
        * ) recordFailure "tester answered no: ${question}" ;;
    esac
}

function assertInteractionReturnCode() {
    local outputPath="${1}"
    local pattern="${2:-${interactionReturnCodePattern}}"
    local returnLine=""

    returnLine="$(grep -E "${pattern}" "${outputPath}" | tail -n 1)"
    if [[ -z "${returnLine}" ]]; then
        recordFailure "no user-interaction return code (${pattern}) in ${outputPath:t}"
        recordHaystackContext "${outputPath}"
    fi
}

# Work-directory copy of reminderDialog.zsh for the test RDNN (demo mode lives only in the unassembled script)
function prepareDemoCopy() {
    demoCopy="${workDir}/demo/reminderDialog.zsh"
    if [[ ! -f "${demoCopy}" ]]; then
        mkdir -p "${demoCopy:h}"
        sed \
            -e "s|^reverseDomainNameNotation=\"org.churchofjesuschrist\"\$|reverseDomainNameNotation=\"${testRdnn}\"|" \
            -e "s|^scriptLog=\"/var/log/org.churchofjesuschrist.log\"\$|scriptLog=\"/var/log/${testRdnn}.log\"|" \
            -e "s|\[\"scriptLog\"\]=\"string\|/var/log/org.churchofjesuschrist.log\"|[\"scriptLog\"]=\"string\|/var/log/${testRdnn}.log\"|" \
            -e "s|^aggressiveModeKillSwitchPath=\"\${deploymentScriptDirectory}/dor-aggressive-kill\"\$|aggressiveModeKillSwitchPath=\"${demoCopy:h}/dor-aggressive-kill\"|" \
            "${rdPath}" > "${demoCopy}"
    fi
    if grep -q 'org\.churchofjesuschrist' "${demoCopy}"; then
        recordFailure "demo copy still references org.churchofjesuschrist: $(grep -n -m 3 'org\.churchofjesuschrist' "${demoCopy}" | tr '\n' ' ')"
        return 1
    fi
    # The tier keeps the test-RDNN kill switch in place for live heartbeats; it would turn 'demo aggressive' into a normal reminder
    if ! grep -qF "aggressiveModeKillSwitchPath=\"${demoCopy:h}/dor-aggressive-kill\"" "${demoCopy}"; then
        recordFailure "demo copy still reads the test-RDNN aggressive-mode kill switch: $(grep -n -m 1 '^aggressiveModeKillSwitchPath=' "${demoCopy}")"
        return 1
    fi
}

function testIgnoredInteractionShowsInitialDialog() {
    local declaredDeadline="$(localISO8601 $(( $(date +%s) + 120 * 86400 )))"

    requireDialogs || return 0
    makeInstallLog "${testDir}/install.log" "$(ilDeclaration $(( $(date +%s) - 3600 )) "99.0" "${declaredDeadline}")"
    makePersistencePlist "${testDir}/persistence.plist" "99.0|${declaredDeadline}"
    setStateKey "${testStatePlist}" LastDeclarationChangeDetected "$(stateTimestamp $(( $(date +%s) - 3600 )))"
    # Older than the change time, and outside the 76-minute quiet period
    seedInteraction $(( $(date +%s) - 7200 ))

    tellTester "A 'macOS Upgrade Required' reminder for macOS 99.0 will appear. Read it, then click 'Remind Me Later'."
    # DOR_LAUNCH_SOURCE=starter skips the random 30-90 s pause; it writes test-RDNN scheduler state only
    runWithTimeout 900 "${testDir}/run.out" env \
        DOR_LAUNCH_SOURCE=starter \
        installLogPathOverride="${testDir}/install.log" \
        ddmStatePersistencePlistPathOverride="${testDir}/persistence.plist" \
        /bin/zsh "${testDorScript}"
    setStateKey "${testStatePlist}" NextScheduledReminder "FALSE"
    deleteStateKey "${testStatePlist}" LastDeclarationChangeDetected

    assertContains "interaction before the change time is ignored" "[NOTICE]          Ignoring reminder interaction from" "${testDir}/run.out"
    assertContains "initial reminder dialog" "displaying initial reminder dialog" "${testDir}/run.out"
    assertInteractionReturnCode "${testDir}/run.out"
    confirmDialog "Did the initial macOS 99.0 reminder dialog appear and look correct?"
}

function testDemoDialog() {
    local demoArgument="${1}"
    local demoLabel="${2}"

    requireDialogs || return 0
    prepareDemoCopy || return 0

    tellTester "The '${demoLabel}' demo reminder will appear. Click 'Remind Me Later' (or 'Open Software Update')."
    runWithTimeout 900 "${testDir}/demo.out" /bin/zsh "${demoCopy}" demo ${=demoArgument}

    assertContains "demo mode ran" "Demo mode enabled" "${testDir}/demo.out"
    if [[ "${demoArgument}" == "aggressive" ]]; then
        assertContains "aggressive mode active" "Aggressive mode active (" "${testDir}/demo.out"
    fi
    assertInteractionReturnCode "${testDir}/demo.out"
    confirmDialog "Did the '${demoLabel}' demo dialog appear and look correct?"
}

function testDemoForceSkipped() {
    requireDialogs || return 0
    skipTest "demo Force restarts the Mac (button or timer runs /sbin/shutdown -r now); on a disposable Mac run: sudo zsh reminderDialog.zsh demo Force"
}

function testPreferenceTestDialog() {
    local previewArguments="${1}"
    local previewLabel="${2}"

    requireDialogs || return 0

    tellTester "The reminderDialogPreferenceTest.zsh '${previewLabel}' preview will appear. Click any button to close it."
    runWithTimeout 900 "${testDir}/preview.out" /bin/zsh "${repoRoot}/Resources/reminderDialogPreferenceTest.zsh" --rdnn "${testRdnn}" ${=previewArguments}

    assertInteractionReturnCode "${testDir}/preview.out" 'swiftDialog return code: (0|2|3|4|10)'
    confirmDialog "Did the '${previewLabel}' preview appear and look correct?"
}

registerTest "interaction before LastDeclarationChangeDetected: Ignoring NOTICE and initial reminder dialog" testIgnoredInteractionShowsInitialDialog
registerTest "demo (test-RDNN copy of reminderDialog.zsh)" testDemoDialog "" "demo"
registerTest "demo aggressive (test-RDNN copy of reminderDialog.zsh)" testDemoDialog "aggressive" "demo aggressive"
registerTest "demo Force (skipped: restarts the Mac)" testDemoForceSkipped
registerTest "reminderDialogPreferenceTest.zsh --pre-deadline-threshold 5" testPreferenceTestDialog "--pre-deadline-threshold 5" "pre-deadline threshold 5"
registerTest "reminderDialogPreferenceTest.zsh --aggressive" testPreferenceTestDialog "--aggressive" "aggressive"
registerTest "reminderDialogPreferenceTest.zsh --battery-percentage 99" testPreferenceTestDialog "--battery-percentage 99" "battery 99%"
