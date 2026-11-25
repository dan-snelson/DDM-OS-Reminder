#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# DDM OS Reminder pre-release test suite: shared helpers
#
# Sourced by Tests/runTests.zsh. Unit helpers write only under the run's work directory
# (/var/tmp/dor-tests.XXXXXX). Integration helpers touch the test RDNN (com.example.dortest) only.
#
# Production scripts are never edited: helpers extract functions (or the starter heredoc) into the
# work directory and rewrite only those copies.
#
####################################################################################################



####################################################################################################
#
# Output and Banners
#
####################################################################################################

typeset -ga attentionItems=()

function say() {
    print -r -- "${1}"
    [[ -n "${resultsLog:-}" ]] && print -r -- "${1}" >> "${resultsLog}"
}

function logOnly() {
    [[ -n "${resultsLog:-}" ]] && print -r -- "${1}" >> "${resultsLog}"
}

function bannerRule() {
    local width=80

    if [[ -t 1 ]]; then
        width="$( tput cols 2>/dev/null || echo 80 )"
        [[ "${width}" == <-> ]] || width=80
    fi
    (( width > 100 )) && width=100
    (( width < 60 )) && width=60

    print -r -- "${(l:${width}::━:)}"
}

# banner <STOP|WARN|INFO> <title> <what happened> <why it matters> <next step> [exit code for STOP]
function banner() {
    local level="${1}"
    local title="${2}"
    local whatHappened="${3}"
    local whyItMatters="${4}"
    local nextStep="${5}"
    local exitCode="${6:-69}"
    local heading=""
    local colorOn=""
    local colorOff=""
    local rule=""
    local bannerLine=""
    local -a bannerLines=()

    case "${level}" in
        STOP ) heading="❌ STOP: ${title}";        colorOn=$'\e[1;31m' ;;
        WARN ) heading="⚠️  WARNING: ${title}";    colorOn=$'\e[1;33m' ;;
        *    ) heading="ℹ️  NOTE: ${title}";       colorOn=$'\e[1;36m' ;;
    esac

    if [[ -t 1 ]]; then
        colorOff=$'\e[0m'
    else
        colorOn=""
    fi

    rule="$(bannerRule)"
    bannerLines=(
        "${rule}"
        "${heading}"
        "${rule}"
        "What happened:   ${whatHappened}"
        "Why it matters:  ${whyItMatters}"
        "Next step:       ${nextStep}"
        "${rule}"
    )

    print ""
    logOnly ""
    for bannerLine in "${bannerLines[@]}"; do
        print -r -- "${colorOn}${bannerLine}${colorOff}"
        logOnly "${bannerLine}"
    done
    print ""
    logOnly ""

    if [[ "${level}" == "STOP" ]]; then
        exit "${exitCode}"
    fi

    attentionItems+=( "${heading} | Next step: ${nextStep}" )
}

# Ask the person running the suite to confirm what they saw; 0 = yes, 1 = no, 2 = no terminal
function askTester() {
    local question="${1}"
    local answer=""

    if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
        return 2
    fi

    print -n -- $'\n'"❓ ${question} [y/n] " > /dev/tty
    read -r answer < /dev/tty || return 2
    print -r -- "askTester: ${question} -> ${answer}"
    [[ "${answer:l}" == y* ]]
}



####################################################################################################
#
# Test Registration
#
####################################################################################################

typeset -ga registeredTiers=()
typeset -ga registeredGroups=()
typeset -ga registeredDescriptions=()
typeset -ga registeredCommands=()

# registerTest "<description>" <function> [argument …]; the current ${testGroup} and ${testTier} apply
function registerTest() {
    local description="${1}"
    shift

    registeredTiers+=( "${testTier:-unit}" )
    registeredGroups+=( "${testGroup:-unknown}" )
    registeredDescriptions+=( "${description}" )
    registeredCommands+=( "${(j: :)${(q)@}}" )
}



####################################################################################################
#
# Assertions (each failure appends detail lines to ${testFailFile})
#
####################################################################################################

function recordFailure() {
    print -r -- "${1}" >> "${testFailFile}"
}

# A test calls skipTest "<reason>" and then returns
function skipTest() {
    print -r -- "${1}" > "${testSkipFile}"
}

function haystackText() {
    if [[ -f "${1}" ]]; then
        cat -- "${1}" 2>/dev/null
    else
        print -r -- "${1}"
    fi
}

function recordHaystackContext() {
    local haystack="${1}"
    local contextLine=""

    if [[ -f "${haystack}" ]]; then
        recordFailure "  in file: ${haystack} (last 8 lines)"
        while IFS= read -r contextLine; do
            recordFailure "    | ${contextLine}"
        done < <(tail -n 8 "${haystack}" 2>/dev/null)
    else
        recordFailure "  actual: ${haystack[1,600]}"
    fi
}

function assertEquals() {
    local label="${1}"
    local expected="${2}"
    local actual="${3}"

    [[ "${actual}" == "${expected}" ]] && return 0

    recordFailure "${label}"
    recordFailure "  expected: ${expected}"
    recordFailure "  actual:   ${actual}"
    return 1
}

function assertMatches() {
    local label="${1}"
    local pattern="${2}"
    local actual="${3}"

    [[ "${actual}" =~ ${pattern} ]] && return 0

    recordFailure "${label}"
    recordFailure "  expected to match: ${pattern}"
    recordFailure "  actual:            ${actual}"
    return 1
}

# assertContains <label> <needle> <file path or string>
function assertContains() {
    local label="${1}"
    local needle="${2}"
    local haystack="${3}"
    local text=""

    text="$(haystackText "${haystack}")"
    [[ "${text}" == *"${needle}"* ]] && return 0

    recordFailure "${label}"
    recordFailure "  expected to contain: ${needle}"
    recordHaystackContext "${haystack}"
    return 1
}

function assertNotContains() {
    local label="${1}"
    local needle="${2}"
    local haystack="${3}"
    local text=""

    text="$(haystackText "${haystack}")"
    [[ "${text}" != *"${needle}"* ]] && return 0

    recordFailure "${label}"
    recordFailure "  expected NOT to contain: ${needle}"
    recordHaystackContext "${haystack}"
    return 1
}

function assertExit() {
    local label="${1}"
    local expected="${2}"
    local actual="${3}"

    [[ "${actual}" == "${expected}" ]] && return 0

    recordFailure "${label}"
    recordFailure "  expected exit status: ${expected}"
    recordFailure "  actual exit status:   ${actual}"
    return 1
}

function assertFileExists() {
    local label="${1}"
    local filePath="${2}"

    [[ -e "${filePath}" ]] && return 0

    recordFailure "${label}"
    recordFailure "  expected file to exist: ${filePath}"
    return 1
}

function assertFileAbsent() {
    local label="${1}"
    local filePath="${2}"

    [[ ! -e "${filePath}" && ! -L "${filePath}" ]] && return 0

    recordFailure "${label}"
    recordFailure "  expected file to be absent: ${filePath}"
    return 1
}

# assertPlistKey <label> <plist> <key> <value | __absent__>
function assertPlistKey() {
    local label="${1}"
    local plistPath="${2}"
    local plistKey="${3}"
    local expected="${4}"
    local actual=""

    if ! actual="$(/usr/libexec/PlistBuddy -c "Print :${plistKey}" "${plistPath}" 2>/dev/null)"; then
        actual="__absent__"
    fi

    assertEquals "${label} (${plistPath:t} :${plistKey})" "${expected}" "${actual}"
}

function plistValue() {
    /usr/libexec/PlistBuddy -c "Print :${2}" "${1}" 2>/dev/null
}



####################################################################################################
#
# Function Extraction
#
####################################################################################################

# Bracket expressions instead of backslash escapes: awk -v would consume the escapes
functionDefinitionPattern='^(function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[(][)]|[A-Za-z_][A-Za-z0-9_]*[(][)])[[:space:]]*[{]'

# extractFunctions <source> <output>
# Copies every top-level function definition (function name() {, bare name() {, and one-liners);
# skips heredoc bodies and all top-level code. Writes "<definitions> <definitions inside heredocs>
# <unclosed>" to <output>.stats.
function extractFunctions() {
    local sourcePath="${1}"
    local outputPath="${2}"

    /usr/bin/awk -v definitionPattern="${functionDefinitionPattern}" -v statsFile="${outputPath}.stats" '
        function noteHeredoc(text,    rest, position, after, stripTabs, marker) {
            if (text ~ /^[ \t]*#/) {
                return
            }
            rest = text
            while ((position = index(rest, "<<")) > 0) {
                if (position > 1 && substr(rest, position - 1, 1) == "<") {
                    rest = substr(rest, position + 2)
                    continue
                }
                after = substr(rest, position + 2)
                if (substr(after, 1, 1) == "<") {
                    rest = substr(after, 2)
                    continue
                }
                stripTabs = 0
                if (substr(after, 1, 1) == "-") {
                    stripTabs = 1
                    after = substr(after, 2)
                }
                sub(/^[ \t]*/, "", after)
                if (match(after, /^["\047]?[A-Za-z_][A-Za-z0-9_]*["\047]?/)) {
                    marker = substr(after, RSTART, RLENGTH)
                    gsub(/["\047]/, "", marker)
                    heredocTerminator = marker
                    heredocStripTabs = stripTabs
                    inHeredoc = 1
                    return
                }
                rest = after
            }
        }

        {
            line = $0

            if (inHeredoc) {
                if (line ~ definitionPattern) {
                    heredocDefinitions++
                }
                if (inFunction) {
                    print line
                }
                check = line
                if (heredocStripTabs) {
                    sub(/^\t+/, "", check)
                }
                if (check == heredocTerminator) {
                    inHeredoc = 0
                }
                next
            }

            if (!inFunction) {
                if (line ~ definitionPattern) {
                    definitions++
                    print line
                    body = line
                    sub(/^[^{]*\{/, "", body)
                    if (body ~ /\}[ \t]*$/) {
                        print ""
                        next
                    }
                    inFunction = 1
                    noteHeredoc(line)
                    next
                }
                noteHeredoc(line)
                next
            }

            print line
            if (line ~ /^\}/) {
                inFunction = 0
                print ""
                next
            }
            noteHeredoc(line)
        }

        END {
            printf "%d %d %d\n", definitions, heredocDefinitions, inFunction + inHeredoc > statsFile
        }
    ' "${sourcePath}" > "${outputPath}"
}

# validateExtraction <source> <output>; prints a failure message and returns 1 on any mismatch
function validateExtraction() {
    local sourcePath="${1}"
    local outputPath="${2}"
    local definitionCount=0
    local heredocDefinitionCount=0
    local unclosedCount=0
    local sourceDefinitionLines=0
    local sourcedFunctionCount=""
    local syntaxOutput=""

    read -r definitionCount heredocDefinitionCount unclosedCount < "${outputPath}.stats"
    sourceDefinitionLines="$(grep -c -E "${functionDefinitionPattern}" "${sourcePath}")"

    if (( unclosedCount != 0 )); then
        print -r -- "extraction of '${sourcePath:t}' ended inside a function or heredoc"
        return 1
    fi

    if (( sourceDefinitionLines - heredocDefinitionCount != definitionCount )); then
        print -r -- "'${sourcePath:t}' has ${sourceDefinitionLines} definition lines (${heredocDefinitionCount} inside heredocs), but ${definitionCount} functions were extracted"
        return 1
    fi

    if ! syntaxOutput="$(/bin/zsh -n < "${outputPath}" 2>&1)"; then
        print -r -- "extracted functions from '${sourcePath:t}' fail /bin/zsh -n: ${syntaxOutput//$'\n'/; }"
        return 1
    fi

    sourcedFunctionCount="$(/bin/zsh -f -c 'before=${#functions}; source "${1}" >/dev/null 2>&1; print $(( ${#functions} - before ))' extractionCheck "${outputPath}" 2>/dev/null)"
    if [[ "${sourcedFunctionCount}" != "${definitionCount}" ]]; then
        print -r -- "sourcing extracted '${sourcePath:t}' defined ${sourcedFunctionCount:-no} functions; expected ${definitionCount} (duplicate names or broken extraction)"
        return 1
    fi

    print -r -- "${definitionCount} functions extracted (${heredocDefinitionCount} heredoc definition lines skipped)"
}

# preparedExtraction <rd|ldm>; prints the cached functions file (pmset rewritten to the stub)
function preparedExtraction() {
    local which="${1}"
    local sourcePath=""
    local outputPath="${extractDir}/${which}.functions.zsh"
    local validationMessage=""

    case "${which}" in
        rd  ) sourcePath="${rdPath}" ;;
        ldm ) sourcePath="${ldmPath}" ;;
        *   ) print -r -- "unknown extraction '${which}'" >&2; return 1 ;;
    esac

    if [[ -f "${outputPath}.invalid" ]]; then
        cat "${outputPath}.invalid" >&2
        return 1
    fi

    if [[ ! -f "${outputPath}" ]]; then
        mkdir -p "${extractDir}"
        extractFunctions "${sourcePath}" "${outputPath}.raw"
        if ! validationMessage="$(validateExtraction "${sourcePath}" "${outputPath}.raw")"; then
            print -r -- "${validationMessage}" > "${outputPath}.invalid"
            print -r -- "${validationMessage}" >&2
            return 1
        fi
        print -r -- "${validationMessage}" > "${outputPath}.summary"
        sed -e "s|/usr/bin/pmset|${stubDir}/pmset|g" "${outputPath}.raw" > "${outputPath}"
        if grep -q '/usr/bin/pmset' "${outputPath}" || ! /bin/zsh -n < "${outputPath}" >/dev/null 2>&1; then
            print -r -- "pmset stub rewrite failed for '${sourcePath:t}'" > "${outputPath}.invalid"
            rm -f "${outputPath}"
            cat "${outputPath}.invalid" >&2
            return 1
        fi
    fi

    print -r -- "${outputPath}"
}

# Copy RD top-of-file globals by anchor: simple assignments, typeset/declare lines, and the
# preferenceConfiguration / plistKeyMap blocks (declare -A becomes typeset -gA so they stay global)
function preparedRuntimeGlobals() {
    local outputPath="${extractDir}/rd.globals.zsh"

    if [[ ! -f "${outputPath}" ]]; then
        mkdir -p "${extractDir}"
        /usr/bin/awk '
            /^# Functions$/ { exit }
            inBlock {
                print
                if ($0 ~ /^\)$/) { inBlock = 0 }
                next
            }
            /^declare -A (preferenceConfiguration|plistKeyMap)=\($/ {
                line = $0
                sub(/^declare -A /, "typeset -gA ", line)
                print line
                inBlock = 1
                next
            }
            /^declare -A [A-Za-z_]+=\(\)$/ {
                line = $0
                sub(/^declare -A /, "typeset -gA ", line)
                print line
                next
            }
            /^typeset -g[aA] / { print; next }
            /^[A-Za-z_][A-Za-z0-9_]*=/ {
                if ($0 ~ /\$\(/ || $0 ~ /\$\{?1/) { next }
                print
            }
        ' "${rdPath}" > "${outputPath}"
    fi

    print -r -- "${outputPath}"
}

# Build the unit environment for reminderDialog.zsh functions inside the current test subshell
function loadRuntimeFunctions() {
    local functionsFile=""
    local globalsFile=""

    functionsFile="$(preparedExtraction rd 2>"${testDir}/extract.err")" || {
        recordFailure "Unable to extract reminderDialog.zsh functions: $(cat "${testDir}/extract.err")"
        return 1
    }
    globalsFile="$(preparedRuntimeGlobals)"

    source "${globalsFile}"
    source "${functionsFile}"
    autoload -Uz is-at-least

    mkdir -p "${testDir}/Managed Preferences" "${testDir}/Preferences" "${testDir}/Management"
    scriptLog="${testDir}/client.log"
    : > "${scriptLog}"
    # loadDefaultPreferences resets scriptLog from this default; never let it point at the production log
    preferenceConfiguration[scriptLog]="string|${scriptLog}"
    preferenceDomain="com.example.dortest.dorm"
    managedPreferencesPlist="${testDir}/Managed Preferences/${preferenceDomain}"
    localPreferencesPlist="${testDir}/Preferences/${preferenceDomain}"
    deploymentScriptDirectory="${testDir}/Management"
    dorScriptPath="${deploymentScriptDirectory}/dor.zsh"
    dorStarterPath="${deploymentScriptDirectory}/dor-starter.zsh"
    dorStatePlistPath="${deploymentScriptDirectory}/dor-state.plist"
    dorPidFilePath="${deploymentScriptDirectory}/dor.pid"
    aggressiveModeKillSwitchPath="${deploymentScriptDirectory}/dor-aggressive-kill"
    dorFallbackDeclarationPlistPath="${deploymentScriptDirectory}/dor-fallback-declaration.plist"
    dorLaunchDaemonLabel="com.example.dortest.unit.dor"
    dorLaunchDaemonPath="${testDir}/com.example.dortest.unit.dor.plist"
    installLogPath="${testDir}/install.log"
    ddmStatePersistencePlistPath="${testDir}/persistence.plist"

    lastBootTime="$( sysctl kern.boottime | awk -F'[ |,]' '{print $5}' )"
    currentTime="$( date +%s )"
    upTimeMin=$(( (currentTime - lastBootTime) / 60 ))
    errorCount=0
    schedulerEnabledForCurrentRun="NO"
    launchSource="manual"
    export DOR_STUB_STATE="${testDir}"
}

# Build the unit environment for launchDaemonManagement.zsh functions inside the current test subshell
function loadDeploymentFunctions() {
    local functionsFile=""

    functionsFile="$(preparedExtraction ldm 2>"${testDir}/extract.err")" || {
        recordFailure "Unable to extract launchDaemonManagement.zsh functions: $(cat "${testDir}/extract.err")"
        return 1
    }

    source "${functionsFile}"
    autoload -Uz is-at-least

    scriptVersion="tests"
    scriptLog="${testDir}/deploy.log"
    : > "${scriptLog}"
    humanReadableScriptName="DDM OS Reminder"
    reverseDomainNameNotation="com.example.dortest"
    organizationScriptName="dor"
    organizationDirectory="${testDir}/Management"
    mkdir -p "${organizationDirectory}"
    dormScriptPath="${organizationDirectory}/dor.zsh"
    dorStarterPath="${organizationDirectory}/dor-starter.zsh"
    dorStatePlistPath="${organizationDirectory}/dor-state.plist"
    dorPidFilePath="${organizationDirectory}/dor.pid"
    dorAggressiveKillSwitchPath="${organizationDirectory}/dor-aggressive-kill"
    dorFallbackDeclarationPlistPath="${organizationDirectory}/dor-fallback-declaration.plist"
    launchDaemonLabel="com.example.dortest.unit.dor"
    launchDaemonPath="${testDir}/com.example.dortest.unit.dor.plist"
    errorCount=0
}



####################################################################################################
#
# Stubs
#
####################################################################################################

# Stub scripts read their canned output from ${DOR_STUB_STATE} (the current test directory)
function createStubs() {
    mkdir -p "${stubDir}"

    cat > "${stubDir}/pmset" <<'ENDOFSTUB'
#!/bin/zsh -f
stubState="${DOR_STUB_STATE:-}"
stubFile=""
case "${2:-}" in
    ps          ) stubFile="pmset-ps.txt" ;;
    systemstate ) stubFile="pmset-systemstate.txt" ;;
    *           ) exit 1 ;;
esac
if [[ -n "${stubState}" && -f "${stubState}/${stubFile}" ]]; then
    cat "${stubState}/${stubFile}"
    exit 0
fi
case "${stubFile}" in
    pmset-systemstate.txt )
        print -r -- "Current System Capabilities are: CPU Graphics Audio Network"
        print -r -- "Current Power State: 4"
        ;;
    pmset-ps.txt )
        print -r -- "Now drawing from 'AC Power'"
        ;;
esac
exit 0
ENDOFSTUB

    cat > "${stubDir}/scutil" <<'ENDOFSTUB'
#!/bin/zsh -f
consoleUser=""
if [[ -n "${DOR_STUB_STATE:-}" && -f "${DOR_STUB_STATE}/console-user" ]]; then
    consoleUser="$(< "${DOR_STUB_STATE}/console-user")"
fi
cat > /dev/null
if [[ -n "${consoleUser}" ]]; then
    print -r -- "<dictionary> {"
    print -r -- "  Name : ${consoleUser}"
    print -r -- "  UID : 501"
    print -r -- "}"
else
    print -r -- "  No such key"
fi
ENDOFSTUB

    chmod 755 "${stubDir}/pmset" "${stubDir}/scutil"
}

function setPmsetSystemState() {
    print -r -- "${1}" > "${testDir}/pmset-systemstate.txt"
}

function setPmsetPowerSource() {
    print -r -- "${1}" > "${testDir}/pmset-ps.txt"
}



####################################################################################################
#
# Fixtures
#
####################################################################################################

# Local install.log timestamp for an epoch: "YYYY-MM-DD HH:MM:SS±HH:MM" (current TZ)
function installLogTimestamp() {
    local epoch="${1}"
    local baseTimestamp=""
    local offset=""

    baseTimestamp="$(date -r "${epoch}" '+%Y-%m-%d %H:%M:%S')"
    offset="$(date -r "${epoch}" '+%z')"
    print -r -- "${baseTimestamp}${offset[1,3]}:${offset[4,5]}"
}

# Line shapes copied from Resources/skills/diagnose-client-state/fixtures/*/install.log and the
# resolver's match strings in reminderDialog.zsh
function ilDeclaration() {
    # <epoch> <version> <EnforcedInstallDate> [build]
    print -r -- "$(installLogTimestamp "${1}") Mac softwareupdated[123]: [com.apple.softwareupdated.declarationFromKeys]: Found currently applicable declaration |EnforcedInstallDate:${3}|VersionString:${2}|BuildVersionString:${4:-(null)}|"
}

function ilDescriptor() {
    # <epoch> <offered version>
    print -r -- "$(installLogTimestamp "${1}") Mac softwareupdated[617]: "$'\t'"majorPrimaryDescriptor: SUMacControllerDescriptor(UUID:F22178C0-D78B-5284-9361-C87780D05B87 SU:macOS ${2} 26B123 (Customer)(SU) SFR:(null) BRAIN:26B123 BRIDGEOS:NO((null)) ROSETTA:YES((null)) RECOVERYOS:YES SPLAT:(null))"
}

function ilNoUpdates() {
    print -r -- "$(installLogTimestamp "${1}") Mac softwareupdated[123]: No updates found for DDM to enforce"
}

function ilRequestedPMV() {
    print -r -- "$(installLogTimestamp "${1}") Mac softwareupdated[123]: SUOSUServiceDaemon: Scanning for updates (requestedPMV=${2}, requestedBuild=(null))"
}

function ilNoMatch() {
    print -r -- "$(installLogTimestamp "${1}") Mac softwareupdated[123]: Download failed: MADownloadNoMatchFound"
}

function ilQueued() {
    # <epoch> <version> [sender]
    print -r -- "$(installLogTimestamp "${1}") Mac ${3:-softwareupdated}[123]: SUOSUInstallTonightManager: Queued update for macOS ${2} (25C56)"
}

function ilArmed() {
    # <epoch> <simulated YES|NO> [sender]
    print -r -- "$(installLogTimestamp "${1}") Mac ${3:-softwareupdated}[123]: SUOSUScheduler: ARMED (scheduledDate=tonight, simulated=${2})"
}

function ilDequeued() {
    print -r -- "$(installLogTimestamp "${1}") Mac softwareupdated[123]: SUOSUInstallTonightManager: Dequeued pending install"
}

function ilGeneric() {
    print -r -- "$(installLogTimestamp "${1}") Mac softwareupdated[123]: SUOSUCatalog: Loaded catalog"
}

# makeInstallLog <path> <line> …
function makeInstallLog() {
    local logPath="${1}"
    shift
    print -rl -- "$@" > "${logPath}"
}

# makePersistencePlist <path> [--unrecognized | --no-declarations] ["<version>|<TargetLocalDateTime>" …]
# Shape read by dor-starter.zsh and reminderDialog.zsh: SUCorePersistedStatePolicyFields:Declarations:<id>
function makePersistencePlist() {
    local plistPath="${1}"
    local declaration=""
    local declarationIndex=0
    shift

    rm -f "${plistPath}"
    /usr/bin/plutil -create xml1 "${plistPath}"

    if [[ "${1:-}" == "--unrecognized" ]]; then
        /usr/bin/plutil -insert SomethingElse -string "unrecognized" "${plistPath}"
        return 0
    fi

    /usr/bin/plutil -insert SUCorePersistedStatePolicyFields -dictionary "${plistPath}"
    /usr/bin/plutil -insert SUCorePersistedStatePolicyFields.PersistedStateVersion -string "1" "${plistPath}"

    if [[ "${1:-}" == "--no-declarations" ]]; then
        return 0
    fi

    /usr/bin/plutil -insert SUCorePersistedStatePolicyFields.Declarations -dictionary "${plistPath}"
    for declaration in "$@"; do
        (( declarationIndex++ ))
        /usr/bin/plutil -insert "SUCorePersistedStatePolicyFields.Declarations.declaration-${declarationIndex}" -dictionary "${plistPath}"
        /usr/bin/plutil -insert "SUCorePersistedStatePolicyFields.Declarations.declaration-${declarationIndex}.TargetOSVersion" -string "${declaration%%|*}" "${plistPath}"
        /usr/bin/plutil -insert "SUCorePersistedStatePolicyFields.Declarations.declaration-${declarationIndex}.TargetLocalDateTime" -string "${declaration#*|}" "${plistPath}"
    done
}

# expectedFingerprint ["<version>|<TargetLocalDateTime>" …]; independent of the starter's parser
function expectedFingerprint() {
    local declaration=""
    local -a signatures=()

    for declaration in "$@"; do
        signatures+=( "${declaration%%|*}|${${declaration#*|}//[^0-9]/}" )
    done

    md5 -q -s "$( (( ${#signatures[@]} > 0 )) && printf '%s\n' "${signatures[@]}" | LC_ALL=C sort -u | paste -sd ';' - )"
}

# makeStatePlist <path> [key=value …]
function makeStatePlist() {
    local plistPath="${1}"
    local keyValue=""
    shift

    mkdir -p "${plistPath:h}"
    rm -f "${plistPath}"
    /usr/bin/plutil -create xml1 "${plistPath}"
    for keyValue in "$@"; do
        /usr/libexec/PlistBuddy -c "Add :${keyValue%%=*} string ${keyValue#*=}" "${plistPath}" >/dev/null
    done
}

function setStateKey() {
    local plistPath="${1}"
    local stateKey="${2}"
    local stateValue="${3}"

    if /usr/libexec/PlistBuddy -c "Print :${stateKey}" "${plistPath}" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :${stateKey} ${stateValue}" "${plistPath}" >/dev/null
    else
        /usr/libexec/PlistBuddy -c "Add :${stateKey} string ${stateValue}" "${plistPath}" >/dev/null
    fi
}

function deleteStateKey() {
    /usr/libexec/PlistBuddy -c "Delete :${2}" "${1}" >/dev/null 2>&1 || true
}

# makeFallbackPlist <path> <version> <deadline> [schema] [source] [build]; same keys as
# writeFallbackDeclarationPlist in launchDaemonManagement.zsh
function makeFallbackPlist() {
    local plistPath="${1}"

    mkdir -p "${plistPath:h}"
    rm -f "${plistPath}"
    /usr/bin/plutil -create xml1 "${plistPath}"
    /usr/bin/plutil -insert SchemaVersion -integer "${4:-1}" "${plistPath}"
    /usr/bin/plutil -insert VersionString -string "${2}" "${plistPath}"
    /usr/bin/plutil -insert BuildVersionString -string "${6:-(null)}" "${plistPath}"
    /usr/bin/plutil -insert EnforcedInstallDate -string "${3}" "${plistPath}"
    /usr/bin/plutil -insert Source -string "${5:-JamfProScriptParameters}" "${plistPath}"
}

# Schedule timestamp (dor-state.plist format) for an epoch
function stateTimestamp() {
    date -r "${1}" '+%Y-%m-%d:%H:%M:%S'
}

# Zone-less ISO 8601 (device-local) for an epoch
function localISO8601() {
    date -r "${1}" '+%Y-%m-%dT%H:%M:%S'
}

function bootEpoch() {
    sysctl kern.boottime | awk -F'[ |,]' '{print $5}'
}

function touchBeforeBoot() {
    local filePath="${1}"
    local earlierEpoch=$(( $(bootEpoch) - 3600 ))

    touch -t "$(date -r "${earlierEpoch}" '+%Y%m%d%H%M.%S')" "${filePath}"
}



####################################################################################################
#
# Starter (dor-starter.zsh heredoc)
#
####################################################################################################

# extractStarter <launchDaemonManagement.zsh or assembled artifact> <directory>
# Writes <directory>/dor-starter.zsh plus a stub main script <directory>/dor.zsh
function extractStarter() {
    local sourcePath="${1}"
    local starterDirectory="${2}"
    local rawStarter="${starterDirectory}/dor-starter.zsh.raw"
    local starterPath="${starterDirectory}/dor-starter.zsh"
    local placeholder=""

    mkdir -p "${starterDirectory}"

    /usr/bin/awk -v startMarker="cat <<'ENDOFSTARTER'" '
        $0 == startMarker { inside = 1; next }
        inside && $0 == "ENDOFSTARTER" { exit }
        inside { print }
    ' "${sourcePath}" > "${rawStarter}"

    if [[ ! -s "${rawStarter}" ]]; then
        print -r -- "No ENDOFSTARTER heredoc found in '${sourcePath}'"
        return 1
    fi

    for placeholder in __SCRIPT_VERSION__ __SCRIPT_LOG__ __MAIN_SCRIPT_PATH__ __STATE_PLIST_PATH__ __PID_FILE_PATH__; do
        if ! grep -q "${placeholder}" "${rawStarter}"; then
            print -r -- "Starter placeholder ${placeholder} missing in '${sourcePath}'"
            return 1
        fi
    done

    sed \
        -e "s|__SCRIPT_VERSION__|tests|g" \
        -e "s|__SCRIPT_LOG__|${starterDirectory}/starter.log|g" \
        -e "s|__MAIN_SCRIPT_PATH__|${starterDirectory}/dor.zsh|g" \
        -e "s|__STATE_PLIST_PATH__|${starterDirectory}/dor-state.plist|g" \
        -e "s|__PID_FILE_PATH__|${starterDirectory}/dor.pid|g" \
        -e "s|^ddmStatePersistencePlistPath=.*\$|ddmStatePersistencePlistPath=\"${starterDirectory}/persistence.plist\"|" \
        -e "s|^export PATH=/usr/bin:/bin:/usr/sbin:/sbin\$|export PATH=${stubDir}:/usr/bin:/bin:/usr/sbin:/sbin|" \
        -e "s|/usr/bin/pmset|${stubDir}/pmset|g" \
        "${rawStarter}" > "${starterPath}"

    if grep -q -E '__[A-Z_]+__' "${starterPath}" \
        || ! grep -q "^ddmStatePersistencePlistPath=\"${starterDirectory}/persistence.plist\"\$" "${starterPath}" \
        || ! grep -q "^export PATH=${stubDir}:" "${starterPath}" \
        || grep -q '/usr/bin/pmset' "${starterPath}"; then
        print -r -- "Starter rewrite incomplete for '${sourcePath}' (placeholder, persistence path, PATH, or pmset)"
        return 1
    fi

    if ! /bin/zsh -n < "${starterPath}" >/dev/null 2>&1; then
        print -r -- "Extracted starter fails /bin/zsh -n"
        return 1
    fi

    cat > "${starterDirectory}/dor.zsh" <<'ENDOFSTUB'
#!/bin/zsh -f
if [[ -n "${STUB_SLEEP:-}" ]]; then
    sleep "${STUB_SLEEP}"
    exit 0
fi
print -r -- "${DOR_LAUNCH_SOURCE:-}|${DOR_LAUNCH_REASON:-}|$(date +%s)" >> "${0:A:h}/launches.log"
exit 0
ENDOFSTUB
    chmod 755 "${starterDirectory}/dor.zsh" "${starterPath}"
    : > "${starterDirectory}/starter.log"
    : > "${starterDirectory}/launches.log"
}

# Prepare the per-test starter directory (${testDir}/starter); records a failure on error
function prepareStarter() {
    local extractionMessage=""

    starterDir="${testDir}/starter"
    if ! extractionMessage="$(extractStarter "${ldmPath}" "${starterDir}")"; then
        recordFailure "extractStarter failed: ${extractionMessage}"
        return 1
    fi
    starterLog="${starterDir}/starter.log"
    starterState="${starterDir}/dor-state.plist"
    starterPersistence="${starterDir}/persistence.plist"
    starterLaunches="${starterDir}/launches.log"
}

function setConsoleUser() {
    print -r -- "${1}" > "${starterDir}/console-user"
}

function launchCount() {
    [[ -f "${starterLaunches}" ]] || { print 0; return; }
    wc -l < "${starterLaunches}" | tr -d '[:space:]'
}

# runStarter; sets starterExitCode and starterNewLaunches (launch lines written by this heartbeat)
function runStarter() {
    local launchesBefore=0
    local waitTenths=0
    local expectLaunch="${1:-maybe}"

    launchesBefore="$(launchCount)"
    env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin DOR_STUB_STATE="${starterDir}" /bin/zsh "${starterDir}/dor-starter.zsh" > "${starterDir}/starter.stdout" 2>&1
    starterExitCode=$?

    # The starter backgrounds the main script; give it time to record the launch
    while (( waitTenths < 30 )); do
        (( $(launchCount) > launchesBefore )) && break
        [[ "${expectLaunch}" == "no" ]] && (( waitTenths >= 5 )) && break
        sleep 0.1
        (( waitTenths++ ))
    done

    starterNewLaunches="$(tail -n +$(( launchesBefore + 1 )) "${starterLaunches}" 2>/dev/null)"
}

function assertLaunchReason() {
    local label="${1}"
    local expectedReason="${2}"

    if [[ -z "${starterNewLaunches}" ]]; then
        recordFailure "${label}"
        recordFailure "  expected a '${expectedReason}' launch of the main script; none recorded (starter exit ${starterExitCode})"
        recordHaystackContext "${starterLog}"
        return 1
    fi
    assertEquals "${label}" "starter|${expectedReason}" "${starterNewLaunches%|*}"
}

function assertNoLaunch() {
    local label="${1}"

    [[ -z "${starterNewLaunches}" ]] && return 0
    recordFailure "${label}"
    recordFailure "  expected no launch; recorded: ${starterNewLaunches}"
    recordHaystackContext "${starterLog}"
    return 1
}



####################################################################################################
#
# Assembled Artifact (shared by unit/20-assemble and the integration tier)
#
####################################################################################################

# ensureAssembledArtifact; prints the assembled .zsh path (built once per run in the work directory)
function ensureAssembledArtifact() {
    local assembleDirectory="${workDir}/assemble"
    local artifactPath=""

    artifactPath="$(print -r -- "${assembleDirectory}"/Artifacts/ddm-os-reminder-${testRdnn}-*-test.zsh(N[1]))"
    if [[ -n "${artifactPath}" && -f "${artifactPath}" ]]; then
        print -r -- "${artifactPath}"
        return 0
    fi

    rm -rf "${assembleDirectory}"
    mkdir -p "${assembleDirectory}/Resources"
    cp "${asmPath}" "${ldmPath}" "${rdPath}" "${assembleDirectory}/"
    cp "${repoRoot}/Resources/sample.plist" "${repoRoot}/Resources/localizationFilter.zsh" "${assembleDirectory}/Resources/"

    ( cd "${assembleDirectory}" && /bin/zsh assemble.zsh "${testRdnn}" --lane test < /dev/null > "${assembleDirectory}/assemble.out" 2>&1 )
    print -r -- "${?}" > "${assembleDirectory}/assemble.rc"

    artifactPath="$(print -r -- "${assembleDirectory}"/Artifacts/ddm-os-reminder-${testRdnn}-*-test.zsh(N[1]))"
    [[ -n "${artifactPath}" && -f "${artifactPath}" ]] || return 1
    print -r -- "${artifactPath}"
}



####################################################################################################
#
# Integration (test RDNN only)
#
####################################################################################################

function integrationPaths() {
    testManagementDirectory="/Library/Management/${testRdnn}"
    testDorScript="${testManagementDirectory}/dor.zsh"
    testStarterScript="${testManagementDirectory}/dor-starter.zsh"
    testStatePlist="${testManagementDirectory}/dor-state.plist"
    testPidFile="${testManagementDirectory}/dor.pid"
    testKillSwitch="${testManagementDirectory}/dor-aggressive-kill"
    testFallbackPlist="${testManagementDirectory}/dor-fallback-declaration.plist"
    testLaunchDaemonLabel="${testRdnn}.dor"
    testLaunchDaemonPlist="/Library/LaunchDaemons/${testLaunchDaemonLabel}.plist"
    testScriptLog="/var/log/${testRdnn}.log"
    testLocalPreferences="/Library/Preferences/${testRdnn}.dorm.plist"
}

function refuseProductionRdnn() {
    if [[ -z "${testRdnn}" || "${testRdnn}" == "org.churchofjesuschrist" ]]; then
        print -r -- "Refusing to run integration helpers against RDNN '${testRdnn}'" >&2
        exit 70
    fi
}

function testRdnnLeftoversPresent() {
    integrationPaths
    [[ -e "${testLaunchDaemonPlist}" || -d "${testManagementDirectory}" || -e "${testLocalPreferences}" ]] && return 0
    launchctl print "system/${testLaunchDaemonLabel}" >/dev/null 2>&1
}

# Never calls LDM Uninstall: that mode globs /Library/LaunchDaemons/*.dor.plist and would boot out production
function teardownTestRdnn() {
    refuseProductionRdnn
    integrationPaths

    launchctl bootout "system/${testLaunchDaemonLabel}" >/dev/null 2>&1 || true
    rm -f "${testLaunchDaemonPlist}"
    if [[ -d "${testManagementDirectory}" ]]; then
        chflags -R nouchg "${testManagementDirectory}" 2>/dev/null || true
        rm -rf "${testManagementDirectory}"
    fi
    rm -f "${testLocalPreferences}"
}

function copyTestRdnnLog() {
    integrationPaths
    [[ -f "${testScriptLog}" && -n "${resultsLog:-}" ]] && cp "${testScriptLog}" "${resultsLog%.log}-${testRdnn}.log" 2>/dev/null
}

function consoleUserName() {
    echo "show State:/Users/ConsoleUser" | /usr/sbin/scutil 2>/dev/null | awk '/Name :/ { print $3; exit }'
}

function consoleUserIsReady() {
    local consoleUser="$(consoleUserName)"
    [[ -n "${consoleUser}" && "${consoleUser}" != "loginwindow" && "${consoleUser}" != "_mbsetupuser" && "${consoleUser}" != "root" ]]
}

function requireConsoleUser() {
    consoleUserIsReady && return 0
    skipTest "no console user is logged in"
    return 1
}

function logLineCount() {
    [[ -f "${1}" ]] || { print 0; return; }
    wc -l < "${1}" | tr -d '[:space:]'
}

# waitForLogText <file> <text> <start line count> [timeout seconds]; 0 when text appears after the start line
function waitForLogText() {
    local logPath="${1}"
    local needle="${2}"
    local startLine="${3}"
    local timeoutSeconds="${4:-15}"
    local waited=0

    while (( waited < timeoutSeconds * 2 )); do
        if tail -n +$(( startLine + 1 )) "${logPath}" 2>/dev/null | grep -qF -- "${needle}"; then
            return 0
        fi
        sleep 0.5
        (( waited++ ))
    done
    return 1
}

function logTextSince() {
    tail -n +$(( ${2} + 1 )) "${1}" 2>/dev/null
}

# Append a user interaction so live heartbeat runs stay in their quiet period (no dialog)
function seedInteraction() {
    local interactionEpoch="${1:-$(date +%s)}"

    integrationPaths
    print -r -- "dorm (tests): $(date -r "${interactionEpoch}" '+%Y-%m-%d %H:%M:%S') - [INFO]            Return Code: 2" >> "${testScriptLog}"
}

function kickstartTestDaemon() {
    integrationPaths
    launchctl kickstart -k "system/${testLaunchDaemonLabel}" >/dev/null 2>&1
}

# Independent fingerprint of a persistence plist: enumerate Declarations keys from XML, read each pair
function persistencePlistFingerprint() {
    local plistPath="${1}"
    local declarationKey=""
    local targetVersion=""
    local targetDateTime=""
    local -a declarations=()

    [[ -r "${plistPath}" ]] || return 1
    /usr/libexec/PlistBuddy -c "Print :SUCorePersistedStatePolicyFields" "${plistPath}" >/dev/null 2>&1 || return 1

    for declarationKey in ${(f)"$(/usr/bin/plutil -extract SUCorePersistedStatePolicyFields.Declarations xml1 -o - "${plistPath}" 2>/dev/null | /usr/bin/awk '
        /<dict>/ { depth++; next }
        /<\/dict>/ { depth--; next }
        depth == 1 && /<key>/ { line = $0; sub(/.*<key>/, "", line); sub(/<\/key>.*/, "", line); print line }
    ')"}; do
        targetVersion="$(/usr/libexec/PlistBuddy -c "Print :SUCorePersistedStatePolicyFields:Declarations:${declarationKey}:TargetOSVersion" "${plistPath}" 2>/dev/null)"
        targetDateTime="$(/usr/libexec/PlistBuddy -c "Print :SUCorePersistedStatePolicyFields:Declarations:${declarationKey}:TargetLocalDateTime" "${plistPath}" 2>/dev/null)"
        [[ -n "${targetVersion}" && -n "${targetDateTime}" ]] && declarations+=( "${targetVersion}|${targetDateTime}" )
    done

    expectedFingerprint "${declarations[@]}"
}

# Deploy the assembled test-RDNN artifact in Script mode only; output goes to ${1}
function deployTestArtifact() {
    local outputPath="${1}"
    local fallbackVersion="${2}"
    local fallbackDeadline="${3}"
    local artifactPath=""

    refuseProductionRdnn
    artifactPath="$(ensureAssembledArtifact)" || return 98
    /bin/zsh "${artifactPath}" x x x Script "${fallbackVersion}" "${fallbackDeadline}" > "${outputPath}" 2>&1
}

function fileOwnerMode() {
    /usr/bin/stat -f '%Su:%Sg %Lp' "${1}" 2>/dev/null
}

# Wait (up to 90 s) until no deployed dor.zsh run is active, so scenarios do not overlap
function waitForIdleRuntime() {
    local waited=0
    local recordedPid=""

    integrationPaths
    while (( waited < 180 )); do
        recordedPid="$(head -n 1 "${testPidFile}" 2>/dev/null | tr -d '[:space:]')"
        if [[ ! "${recordedPid}" =~ ^[0-9]+$ ]] || ! ps -p "${recordedPid}" -o command= 2>/dev/null | grep -qF "${testDorScript}"; then
            return 0
        fi
        sleep 0.5
        (( waited++ ))
    done
    return 1
}

# runWithTimeout <seconds> <output> <command …>; 124 when the command had to be killed
function runWithTimeout() {
    local timeoutSeconds="${1}"
    local outputPath="${2}"
    local commandPid=""
    local waited=0
    shift 2

    "$@" > "${outputPath}" 2>&1 &
    commandPid=$!
    while kill -0 "${commandPid}" 2>/dev/null; do
        if (( waited >= timeoutSeconds * 2 )); then
            kill -TERM "${commandPid}" 2>/dev/null
            sleep 2
            kill -KILL "${commandPid}" 2>/dev/null
            print -r -- "runWithTimeout: killed after ${timeoutSeconds} s" >> "${outputPath}"
            return 124
        fi
        sleep 0.5
        (( waited++ ))
    done
    wait "${commandPid}"
}

# Tell the person at the Mac what is about to appear (the test's own output goes to a file)
function tellTester() {
    [[ -w /dev/tty ]] && print -r -- $'\n'"👉 ${1}" > /dev/tty
}
