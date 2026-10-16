#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Declarative Device Management macOS Reminder: Client-state Diagnosis
#
# Read-only extractor for Mac Admin uploads:
#   client-side log, /var/log/install.log, and client-side .plist
#
# Prints a structured fact sheet that ends with a pre-filled report skeleton.
# Does not write files, change preferences, mutate scheduler state, or
# re-decide resolver status. The client log's recorded resolver result is
# authoritative for what that Mac did.
#
# Usage:
#   zsh Resources/diagnoseReminderState.zsh --help
#   zsh Resources/diagnoseReminderState.zsh \
#       --client-log /path/to/<rdnn>.log \
#       --install-log /path/to/install.log \
#       --plist /path/to/<rdnn>.dorm.plist
#
# http://snelson.us/ddm
#
####################################################################################################

set -u

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

scriptVersion="1.3.0"
checklistScriptVersion="5.2.0b2"
scriptRelativePath="Resources/diagnoseReminderState.zsh"
ddmResolverLookbackLines=4000
ddmVersionRegex='^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$'
# Keep identical to reminderDialog.zsh ddmLogTimestampRegex.
ddmLogTimestampRegex='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}(:[0-9]{2})?$'
rdnnRegex='^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$'

clientLogPath=""
installLogPath=""
managedPlistPath=""
localPlistPath=""
unknownPlistPath=""
statePlistPath=""
fallbackPlistPath=""
persistencePlistPath=""
launchDaemonPlistPath=""
aggressiveKillState="unknown"

typeset -a extraPlistPaths=()
typeset -a rdnnCandidates=()
typeset -a unknownPlistKeys=()
typeset -a deprecatedPlistKeys=()
typeset -a preferenceRows=()
typeset -a latestRunDecisionLines=()
typeset -a installLogCandidates=()
typeset -a installLogInvalidDeclarations=()
typeset -a installLogNoUpdatesLines=()
typeset -a installLogRecoveryLines=()
typeset -a installLogNoMatchLines=()
typeset -a installLogTonightLines=()
typeset -a inputNotes=()
typeset -a identityNotes=()
typeset -a rejectedLocalizedKeys=()
typeset -a redactedIdentityTokens=()
typeset -a redactedHostTokens=()
typeset -a runHistoryRows=()
typeset -a installLogDeclarationSpans=()

typeset -A preferenceConfiguration=(
    ["scriptLog"]="string|/var/log/org.churchofjesuschrist.log"
    ["daysBeforeDeadlineDisplayReminder"]="numeric|60"
    ["daysBeforeDeadlineBlurscreen"]="numeric|45"
    ["daysBeforeDeadlineHidingButton2"]="numeric|21"
    ["daysOfExcessiveUptimeWarning"]="numeric|0"
    ["quietPeriodMinutes"]="numeric|76"
    ["outsideDisplayWindowPeriodicReminderDays"]="numeric|28"
    ["daysPastDeadlineRestartWorkflow"]="numeric|2"
    ["pastDeadlineRestartBehavior"]="string|Off"
    ["pastDeadlineRestartMinimumUptimeMinutes"]="numeric|75"
    ["pastDeadlineForceTimerSeconds"]="numeric|60"
    ["pastDeadlineForceRedisplayDelaySeconds"]="numeric|5"
    ["meetingDelay"]="numeric|75"
    ["dailyReminderTimes"]="string|08:00,12:00,16:00"
    ["minutesBeforeDeadlineReminderSchedule"]="string|45,30,15,10,5"
    ["aggressiveModePastDeadlineHours"]="numeric|2"
    ["aggressiveModeFrequencyMinutes"]="numeric|20"
    ["acceptableAssertionApplicationNames"]="string|MSTeams zoom.us Webex"
    ["minimumDiskFreeGB"]="numeric|999"
    ["disableButton2InsteadOfHide"]="boolean|YES"
    ["languageOverride"]="string|auto"
)

typeset -A plistKeyMap=(
    ["scriptLog"]="ScriptLog"
    ["daysBeforeDeadlineDisplayReminder"]="DaysBeforeDeadlineDisplayReminder"
    ["daysBeforeDeadlineBlurscreen"]="DaysBeforeDeadlineBlurscreen"
    ["daysBeforeDeadlineHidingButton2"]="DaysBeforeDeadlineHidingButton2"
    ["daysOfExcessiveUptimeWarning"]="DaysOfExcessiveUptimeWarning"
    ["quietPeriodMinutes"]="QuietPeriodMinutes"
    ["outsideDisplayWindowPeriodicReminderDays"]="OutsideDisplayWindowPeriodicReminderDays"
    ["daysPastDeadlineRestartWorkflow"]="DaysPastDeadlineRestartWorkflow"
    ["pastDeadlineRestartBehavior"]="PastDeadlineRestartBehavior"
    ["pastDeadlineRestartMinimumUptimeMinutes"]="PastDeadlineRestartMinimumUptimeMinutes"
    ["pastDeadlineForceTimerSeconds"]="PastDeadlineForceTimerSeconds"
    ["pastDeadlineForceRedisplayDelaySeconds"]="PastDeadlineForceRedisplayDelaySeconds"
    ["meetingDelay"]="MeetingDelay"
    ["dailyReminderTimes"]="DailyReminderTimes"
    ["minutesBeforeDeadlineReminderSchedule"]="MinutesBeforeDeadlineReminderSchedule"
    ["aggressiveModePastDeadlineHours"]="AggressiveModePastDeadlineHours"
    ["aggressiveModeFrequencyMinutes"]="AggressiveModeFrequencyMinutes"
    ["acceptableAssertionApplicationNames"]="AcceptableAssertionApplicationNames"
    ["minimumDiskFreeGB"]="MinimumDiskFreeGB"
    ["disableButton2InsteadOfHide"]="DisableButton2InsteadOfHide"
    ["organizationOverlayiconURL"]="OrganizationOverlayIconURL"
    ["organizationOverlayiconURLdark"]="OrganizationOverlayIconURLdark"
    ["swapOverlayAndLogo"]="SwapOverlayAndLogo"
    ["dateFormatDeadlineHumanReadable"]="DateFormatDeadlineHumanReadable"
    ["supportTeamName"]="SupportTeamName"
    ["supportTeamPhone"]="SupportTeamPhone"
    ["hideSupportTeamPhone"]="HideSupportTeamPhone"
    ["supportTeamEmail"]="SupportTeamEmail"
    ["hideSupportTeamEmail"]="HideSupportTeamEmail"
    ["supportTeamWebsite"]="SupportTeamWebsite"
    ["hideSupportTeamWebsite"]="HideSupportTeamWebsite"
    ["supportKB"]="SupportKB"
    ["hideSupportKB"]="HideSupportKB"
    ["infobuttonaction"]="InfoButtonAction"
    ["supportKBURL"]="SupportKBURL"
    ["languageOverride"]="LanguageOverride"
    ["supportAssistanceMessage"]="SupportAssistanceMessage"
    ["hideSupportAssistanceMessage"]="HideSupportAssistanceMessage"
    ["title"]="Title"
    ["button1text"]="Button1Text"
    ["button2text"]="Button2Text"
    ["infobuttontext"]="InfoButtonText"
    ["excessiveUptimeWarningMessage"]="ExcessiveUptimeWarningMessage"
    ["diskSpaceWarningMessage"]="DiskSpaceWarningMessage"
    ["stagedUpdateMessage"]="StagedUpdateMessage"
    ["partiallyStagedUpdateMessage"]="PartiallyStagedUpdateMessage"
    ["pendingDownloadMessage"]="PendingDownloadMessage"
    ["hideStagedInfo"]="HideStagedUpdateInfo"
    ["relativeDeadlineToday"]="RelativeDeadlineToday"
    ["relativeDeadlineTomorrow"]="RelativeDeadlineTomorrow"
    ["updateWord"]="UpdateWord"
    ["upgradeWord"]="UpgradeWord"
    ["softwareUpdateButtonTextUpdate"]="SoftwareUpdateButtonTextUpdate"
    ["softwareUpdateButtonTextUpgrade"]="SoftwareUpdateButtonTextUpgrade"
    ["restartNowButtonText"]="RestartNowButtonText"
    ["infoboxLabelCurrent"]="InfoboxLabelCurrent"
    ["infoboxLabelRequired"]="InfoboxLabelRequired"
    ["infoboxLabelDeadline"]="InfoboxLabelDeadline"
    ["infoboxLabelDaysRemaining"]="InfoboxLabelDaysRemaining"
    ["infoboxLabelLastRestart"]="InfoboxLabelLastRestart"
    ["infoboxLabelFreeDiskSpace"]="InfoboxLabelFreeDiskSpace"
    ["deadlineEnforcementMessageAbsolute"]="DeadlineEnforcementMessageAbsolute"
    ["deadlineEnforcementMessageRelative"]="DeadlineEnforcementMessageRelative"
    ["preDeadlineThresholdTitle"]="PreDeadlineThresholdTitle"
    ["preDeadlineThresholdMessage"]="PreDeadlineThresholdMessage"
    ["pastDeadlinePromptTitle"]="PastDeadlinePromptTitle"
    ["pastDeadlinePromptMessage"]="PastDeadlinePromptMessage"
    ["pastDeadlineForceTitle"]="PastDeadlineForceTitle"
    ["pastDeadlineForceMessage"]="PastDeadlineForceMessage"
    ["aggressiveModeTitle"]="AggressiveModeTitle"
    ["aggressiveModeMessage"]="AggressiveModeMessage"
    ["message"]="Message"
    ["infobox"]="InfoBox"
    ["helpmessage"]="HelpMessage"
    ["helpimage"]="HelpImage"
)

typeset -A knownPlistKeys=()
typeset -A ddmStatePersistenceSignatures=()
ddmStatePersistenceStatus="not-supplied"

detectedRdnn=""
logScriptVersion=""
logOrganizationScriptName=""
installedMacOSVersion=""
installedMacOSBuild=""
resolverStatusLine=""
installLogLineCount=0
installLogWindowCount=0
latestRunLineCount=0
plistLintStatus=""
deploymentScriptVersion=""
runHistoryTotal=0
unprefixedLineCount=0
unprefixedTopLine=""
unprefixedTopCount=0
fallbackGate=""
reportSkeletonRunLimit=5
reportSkeletonSpanLimit=20



####################################################################################################
#
# Helpers
#
####################################################################################################

function printUsage() {
    echo "Usage:"
    echo "  zsh ${scriptRelativePath} --help"
    echo "  zsh ${scriptRelativePath} --client-log <path> --install-log <path> --plist <path>"
    echo ""
    echo "Required:"
    echo "  --client-log <path>         Client-side DDM OS Reminder log (/var/log/<rdnn>.log)"
    echo "  --install-log <path>        Copy of /var/log/install.log"
    echo "  --plist <path>              Client-side .plist (repeatable; layer inferred from path/name)"
    echo "  --managed-plist <path>      Managed Preferences plist"
    echo "  --local-plist <path>        /Library/Preferences plist"
    echo ""
    echo "Optional:"
    echo "  --state-plist <path>        /Library/Management/<rdnn>/dor-state.plist"
    echo "  --fallback-plist <path>     /Library/Management/<rdnn>/dor-fallback-declaration.plist"
    echo "  --persistence-plist <path>  /var/db/softwareupdate/SoftwareUpdateDDMStatePersistence.plist"
    echo "  --launch-daemon-plist <path> /Library/LaunchDaemons/<rdnn>.dor.plist"
    echo "  --aggressive-kill yes|no    Whether dor-aggressive-kill existed on the Mac"
    echo ""
    echo "At least one of --plist, --managed-plist, or --local-plist is required."
    echo "Read-only: prints a fact sheet to stdout and writes nothing."
    echo "The fact sheet ends with a pre-filled report skeleton for the agent to complete."
}

function failUsage() {
    echo "Error: ${1}" >&2
    echo "" >&2
    printUsage >&2
    exit 64
}

function failMissing() {
    echo "Error: ${1}" >&2
    exit 66
}

function requireReadableFile() {
    local label="${1}"
    local filePath="${2}"

    [[ -n "${filePath}" ]] || failUsage "${label} is required"
    [[ -f "${filePath}" ]] || failMissing "${label} not found: ${filePath}"
    [[ -r "${filePath}" ]] || failMissing "${label} is not readable: ${filePath}"
}

function trimSurroundingWhitespace() {
    local value="${1}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    echo "${value}"
}

function addUniqueRdnnCandidate() {
    local candidate="${1}"
    local existing=""

    [[ "${candidate}" =~ ${rdnnRegex} ]] || return 0
    for existing in "${rdnnCandidates[@]:-}"; do
        if [[ "${existing}" == "${candidate}" ]]; then
            return 0
        fi
    done
    rdnnCandidates+=("${candidate}")
}

function rdnnFromPlistFileName() {
    local baseName="${1:t}"
    local candidate=""

    if [[ "${baseName}" =~ ^(.+)\.dorm([.-].*)?\.plist$ ]]; then
        candidate="${match[1]}"
        addUniqueRdnnCandidate "${candidate}"
    fi
}

function rdnnFromLogFileName() {
    local baseName="${1:t}"
    local candidate=""

    if [[ "${baseName}" == *.log ]]; then
        candidate="${baseName%.log}"
        addUniqueRdnnCandidate "${candidate}"
    fi
}

function inferPlistLayer() {
    local plistPath="${1}"
    local baseName="${plistPath:t}"

    case "${plistPath}" in
        *"/Managed Preferences/"*)
            echo "managed"
            return
            ;;
        *"/Library/Preferences/"*)
            echo "local"
            return
            ;;
    esac

    case "${baseName:l}" in
        managed.dorm.plist|managed.*.plist|*.managed.dorm.plist)
            echo "managed"
            ;;
        local.dorm.plist|local.*.plist|*.local.dorm.plist)
            echo "local"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

function assignPlistPath() {
    local layer="${1}"
    local plistPath="${2}"

    requireReadableFile "Plist" "${plistPath}"
    rdnnFromPlistFileName "${plistPath}"

    case "${layer}" in
        managed)
            [[ -z "${managedPlistPath}" ]] || failUsage "Multiple managed plists supplied"
            managedPlistPath="${plistPath}"
            ;;
        local)
            [[ -z "${localPlistPath}" ]] || failUsage "Multiple local plists supplied"
            localPlistPath="${plistPath}"
            ;;
        unknown)
            extraPlistPaths+=("${plistPath}")
            ;;
    esac
}

function isKnownPlistKey() {
    local plistKey="${1}"
    (( ${+knownPlistKeys[${plistKey}]} ))
}

function plistKeyExists() {
    local plistPath="${1}"
    local plistKey="${2}"

    [[ -n "${plistPath}" ]] || return 1
    /usr/libexec/PlistBuddy -c "Print :${plistKey}" "${plistPath}" >/dev/null 2>&1
}

function plistKeyValue() {
    local plistPath="${1}"
    local plistKey="${2}"
    local value=""

    value="$(/usr/libexec/PlistBuddy -c "Print :${plistKey}" "${plistPath}" 2>/dev/null)" || value=""
    echo "${value}"
}

function plistTopLevelKeys() {
    local plistPath="${1}"

    /usr/libexec/PlistBuddy -c "Print" "${plistPath}" 2>/dev/null | awk '
        /^    [^ ].* = / {
            key=$0
            sub(/^    /, "", key)
            sub(/ =.*/, "", key)
            print key
        }
    '
}

function normalizeBooleanValue() {
    local value="${1}"
    case "${value:l}" in
        1|true|yes) echo "YES" ;;
        0|false|no) echo "NO" ;;
        *)         echo "" ;;
    esac
}

function normalizePastDeadlineRestartBehaviorValue() {
    local value="${1}"
    local normalizedValue="${value//[[:space:]]/}"

    case "${normalizedValue:l}" in
        off)    echo "Off" ;;
        prompt) echo "Prompt" ;;
        force)  echo "Force" ;;
        *)      echo "" ;;
    esac
}

function validateReminderTimeEntry() {
    local timeEntry="$(trimSurroundingWhitespace "${1}")"

    if [[ "${timeEntry}" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        echo "${timeEntry}"
        return 0
    fi

    return 1
}

function normalizeDailyReminderTimes() {
    local rawValue="${1}"
    local rawEntry=""
    local normalizedEntry=""
    local -a rawEntries=()
    local -a validEntries=()
    local -a ignoredEntries=()

    normalizedDailyReminderTimesCSV=""
    ignoredDailyReminderTimesCSV=""

    IFS=',' read -r -A rawEntries <<< "${rawValue}"
    for rawEntry in "${rawEntries[@]}"; do
        normalizedEntry="$(validateReminderTimeEntry "${rawEntry}")"
        if [[ -n "${normalizedEntry}" ]]; then
            validEntries+=("${normalizedEntry}")
        elif [[ -n "$(trimSurroundingWhitespace "${rawEntry}")" ]]; then
            ignoredEntries+=("$(trimSurroundingWhitespace "${rawEntry}")")
        fi
    done

    if (( ${#validEntries[@]} == 0 )); then
        if (( ${#ignoredEntries[@]} > 0 )); then
            ignoredDailyReminderTimesCSV="${(j:, :)ignoredEntries}"
        fi
        return 1
    fi

    validEntries=($(printf "%s\n" "${validEntries[@]}" | LC_ALL=C sort -u))
    normalizedDailyReminderTimesCSV="${(j:,:)validEntries}"
    if (( ${#ignoredEntries[@]} > 0 )); then
        ignoredDailyReminderTimesCSV="${(j:, :)ignoredEntries}"
    fi
    return 0
}

function normalizeMinuteThresholdSchedule() {
    local rawValue="${1}"
    local rawEntry=""
    local trimmedEntry=""
    local normalizedEntry=""
    local -a rawEntries=()
    local -a validEntries=()
    local -a ignoredEntries=()

    normalizedMinuteThresholdScheduleCSV=""
    ignoredMinuteThresholdScheduleCSV=""

    rawValue="$(trimSurroundingWhitespace "${rawValue}")"
    if [[ -z "${rawValue}" ]]; then
        return 0
    fi

    IFS=',' read -r -A rawEntries <<< "${rawValue}"
    for rawEntry in "${rawEntries[@]}"; do
        trimmedEntry="$(trimSurroundingWhitespace "${rawEntry}")"
        if [[ "${trimmedEntry}" =~ ^[0-9]+$ ]]; then
            normalizedEntry=$(( 10#${trimmedEntry} ))
            if (( normalizedEntry >= 1 && normalizedEntry <= 999 )); then
                validEntries+=("${normalizedEntry}")
            else
                ignoredEntries+=("${trimmedEntry}")
            fi
        elif [[ -n "${trimmedEntry}" ]]; then
            ignoredEntries+=("${trimmedEntry}")
        fi
    done

    if (( ${#validEntries[@]} == 0 )); then
        if (( ${#ignoredEntries[@]} > 0 )); then
            ignoredMinuteThresholdScheduleCSV="${(j:, :)ignoredEntries}"
        fi
        return 1
    fi

    validEntries=($(printf "%s\n" "${validEntries[@]}" | LC_ALL=C sort -nr -u))
    normalizedMinuteThresholdScheduleCSV="${(j:,:)validEntries}"
    if (( ${#ignoredEntries[@]} > 0 )); then
        ignoredMinuteThresholdScheduleCSV="${(j:, :)ignoredEntries}"
    fi
    return 0
}

function escapeTableCell() {
    local value="${1}"
    value="${value//|/\\|}"
    value="${value//$'\n'/ }"
    echo "${value}"
}

function parseDDMDeclarationFieldsFromText() {
    local declarationText="${1}"

    parsedDDMEnforcedInstallDate=""
    parsedDDMVersionString=""
    parsedDDMBuildVersionString=""

    if [[ "${declarationText}" != *"|EnforcedInstallDate:"* || "${declarationText}" != *"|VersionString:"* || "${declarationText}" != *"|BuildVersionString:"* ]]; then
        return 1
    fi

    parsedDDMEnforcedInstallDate="${${declarationText##*|EnforcedInstallDate:}%%|*}"
    parsedDDMVersionString="${${declarationText##*|VersionString:}%%|*}"
    parsedDDMBuildVersionString="${${declarationText##*|BuildVersionString:}%%|*}"

    if [[ -z "${parsedDDMEnforcedInstallDate}" || -z "${parsedDDMVersionString}" || -z "${parsedDDMBuildVersionString}" ]]; then
        return 1
    fi

    return 0
}

function extractDDMLogTimestamp() {
    local logLine="${1}"
    local dateToken="${logLine%% *}"
    local remainder="${logLine#* }"
    local timeToken=""

    parsedDDMLogTimestamp=""

    if [[ "${remainder}" == "${logLine}" ]]; then
        return 1
    fi

    timeToken="${remainder%% *}"
    parsedDDMLogTimestamp="${dateToken} ${timeToken}"

    if [[ ! "${parsedDDMLogTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
        parsedDDMLogTimestamp=""
        return 1
    fi

    return 0
}

function parseDDMDeclarationFromLine() {
    local logLine="${1}"

    parsedDDMSourceType=""
    parsedDDMLogTimestamp=""
    parsedDDMEnforcedInstallDate=""
    parsedDDMVersionString=""
    parsedDDMBuildVersionString=""

    if [[ "${logLine}" == *"declarationFromKeys]: Found currently applicable declaration"* ]]; then
        parsedDDMSourceType="currentApplicableDeclaration"
    elif [[ "${logLine}" == *"declarationFromKeys]: Falling back to default applicable declaration"* ]]; then
        parsedDDMSourceType="defaultApplicableDeclaration"
    elif [[ "${logLine}" == *"Found DDM enforced install ("* ]]; then
        parsedDDMSourceType="foundDdmEnforcedInstall"
    elif [[ "${logLine}" == *"EnforcedInstallDate:"* && "${logLine}" == *"softwareupdated["* ]]; then
        parsedDDMSourceType="genericEnforcedInstallDate"
    else
        return 1
    fi

    extractDDMLogTimestamp "${logLine}" || return 1
    parseDDMDeclarationFieldsFromText "${logLine}" || return 1
    return 0
}

function loadDDMStatePersistenceSignatures() {
    local persistenceOutput=""
    local persistenceLine=""
    local trimmedLine=""
    local dictionaryDepth=0
    local targetOSVersion=""
    local targetLocalDateTime=""
    local declarationSignature=""

    ddmStatePersistenceStatus="unavailable"
    ddmStatePersistenceSignatures=()

    [[ -n "${persistencePlistPath}" && -r "${persistencePlistPath}" ]] || return 1

    if ! /usr/libexec/PlistBuddy -c "Print :SUCorePersistedStatePolicyFields" "${persistencePlistPath}" >/dev/null 2>&1; then
        ddmStatePersistenceStatus="unrecognized"
        return 1
    fi

    ddmStatePersistenceStatus="available"
    persistenceOutput="$(/usr/libexec/PlistBuddy -c "Print :SUCorePersistedStatePolicyFields:Declarations" "${persistencePlistPath}" 2>/dev/null)" || return 0

    for persistenceLine in "${(@f)persistenceOutput}"; do
        trimmedLine="${persistenceLine#"${persistenceLine%%[![:space:]]*}"}"
        case "${trimmedLine}" in
            *"Dict {"|*"Array {")
                dictionaryDepth=$(( dictionaryDepth + 1 ))
                if (( dictionaryDepth == 2 )); then
                    targetOSVersion=""
                    targetLocalDateTime=""
                fi
                ;;
            "}")
                if (( dictionaryDepth == 2 )) && [[ -n "${targetOSVersion}" && -n "${targetLocalDateTime}" ]]; then
                    declarationSignature="${targetOSVersion}|${targetLocalDateTime//[^0-9]/}"
                    ddmStatePersistenceSignatures[${declarationSignature}]="1"
                fi
                dictionaryDepth=$(( dictionaryDepth - 1 ))
                ;;
            "TargetOSVersion = "*)
                (( dictionaryDepth == 2 )) && targetOSVersion="${trimmedLine#TargetOSVersion = }"
                ;;
            "TargetLocalDateTime = "*)
                (( dictionaryDepth == 2 )) && targetLocalDateTime="${trimmedLine#TargetLocalDateTime = }"
                ;;
        esac
    done

    return 0
}

function corroborationLabelForCandidate() {
    local versionString="${1}"
    local enforcedInstallDate="${2}"
    local declarationSignature="${versionString}|${enforcedInstallDate//[^0-9]/}"

    case "${ddmStatePersistenceStatus}" in
        available)
            if (( ${+ddmStatePersistenceSignatures[${declarationSignature}]} )); then
                echo "yes"
            else
                echo "no"
            fi
            ;;
        unrecognized)
            echo "plist unrecognized"
            ;;
        unavailable)
            echo "plist unreadable"
            ;;
        *)
            echo "not checked"
            ;;
    esac
}

function sanitizeLanguageCode() {
    local languageCode="${1:l}"
    local languageCodeRegex='^[a-z]{2,3}(_[a-z0-9]{2,8})*$'

    languageCode="${languageCode#\"}"
    languageCode="${languageCode%\"}"
    languageCode="${languageCode#\'}"
    languageCode="${languageCode%\'}"
    languageCode="${languageCode//-/_}"
    languageCode="${languageCode// /}"

    while [[ "${languageCode}" == *"__"* ]]; do
        languageCode="${languageCode//__/_}"
    done
    while [[ "${languageCode}" == _* ]]; do
        languageCode="${languageCode#_}"
    done
    while [[ "${languageCode}" == *_ ]]; do
        languageCode="${languageCode%_}"
    done

    [[ "${languageCode}" =~ ${languageCodeRegex} ]] || languageCode=""
    echo "${languageCode}"
}

function languageSuffixForCode() {
    local code=""
    local firstSegment=""
    local segmentIndex=0
    local -a codeSegments=()

    code="$(sanitizeLanguageCode "${1}")"
    [[ -z "${code}" ]] && echo "" && return

    IFS='_' read -r -A codeSegments <<< "${code}"
    firstSegment="${codeSegments[1]:l}"
    code="${(C)firstSegment}"

    if (( ${#codeSegments[@]} > 1 )); then
        for (( segmentIndex=2; segmentIndex<=${#codeSegments[@]}; segmentIndex++ )); do
            code="${code}_${codeSegments[segmentIndex]:u}"
        done
    fi

    echo "${code}"
}

function localizedKeyRejectionReason() {
    local rawKey="${1}"
    local baseRaw="${rawKey%%Localized_*}"
    local codePart="${rawKey##*Localized_}"
    local languageCode=""
    local internalBase=""
    local internalSuffix=""
    local internalKey=""
    local variableNameRegex='^[A-Za-z][A-Za-z0-9_]*$'

    [[ "${rawKey}" == *Localized_* ]] || return 1

    languageCode="$(sanitizeLanguageCode "${codePart}")"
    if [[ -z "${languageCode}" ]]; then
        echo "unrecognized language code"
        return 0
    fi

    if isKnownPlistKey "${baseRaw}"; then
        internalBase="${knownPlistKeys[${baseRaw}]}"
    else
        internalBase="${baseRaw:0:1:l}${baseRaw:1}"
    fi

    internalSuffix="$(languageSuffixForCode "${languageCode}")"
    internalKey="${internalBase}Localized${internalSuffix}"
    if [[ ! "${internalKey}" =~ ${variableNameRegex} ]]; then
        echo "unrecognized preference name"
        return 0
    fi

    return 1
}

function rememberRedactedToken() {
    local token="${1}"
    local existing=""

    [[ -n "${token}" ]] || return 0
    (( ${#token} >= 2 )) || return 0
    [[ "${token}" =~ '^[0-9]+$' ]] && return 0
    case "${token}" in
        root|loginwindow|_mbsetupuser|dorm|dor|"<redacted>"|"<redacted-host>") return 0 ;;
    esac

    if (( ${#redactedIdentityTokens[@]} > 0 )); then
        for existing in "${redactedIdentityTokens[@]}"; do
            [[ "${existing}" == "${token}" ]] && return 0
        done
    fi
    redactedIdentityTokens+=("${token}")
}

function rememberRedactedHostToken() {
    local token="${1}"

    [[ -n "${token}" ]] || return 0
    (( ${#token} >= 2 )) || return 0
    case "${token}" in
        # Generic "Mac" is not identifying and would mangle plain-language runtime lines ("this Mac")
        localhost|Mac|"|"*|"<redacted>"|"<redacted-host>") return 0 ;;
    esac

    (( ${redactedHostTokens[(Ie)${token}]} )) && return 0
    redactedHostTokens+=("${token}")
}

function collectIdentityTokens() {
    local logLine=""
    # install.log line prefix: date, time with offset, computer name, process[pid]:
    local installLogHostRegex='[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9:]{2,5} ([^[:space:]]+) [^[:space:]]+\[[0-9]+\]:'

    # Client-log context lines quote install.log lines, computer name included
    for logLine in "${installLogWindow[@]}"; do
        if [[ "${logLine}" =~ "^${installLogHostRegex}" ]]; then
            rememberRedactedHostToken "${match[1]}"
        fi
    done

    while IFS= read -r logLine; do
        if [[ "${logLine}" =~ "${installLogHostRegex}" ]]; then
            rememberRedactedHostToken "${match[1]}"
        fi
        # 5.2.0b2+ "Current Logged-in User: <user>, <first name>, <UID>"; earlier "Current Logged-in User: <user>"
        if [[ "${logLine}" =~ 'Current Logged-in User: ([^,[:space:]]+), ([^,]+), [0-9]+' ]]; then
            rememberRedactedToken "${match[1]}"
            rememberRedactedToken "${match[2]}"
        elif [[ "${logLine}" =~ 'Current Logged-in User: ([^,[:space:]]+)' ]]; then
            rememberRedactedToken "${match[1]}"
        fi
        if [[ "${logLine}" =~ 'Current Logged-in User First Name \(ID\): ([^[:space:]]+)' ]]; then
            rememberRedactedToken "${match[1]}"
        fi
        if [[ "${logLine}" =~ 'Display Reminder Dialog to ([^[:space:]]+) with' ]]; then
            rememberRedactedToken "${match[1]}"
        fi
        if [[ "${logLine}" =~ '\][[:space:]]+([^[:space:]]+) clicked ' ]]; then
            rememberRedactedToken "${match[1]}"
        fi
        if [[ "${logLine}" =~ 'Serial Number: ([A-Za-z0-9]+)' ]]; then
            rememberRedactedToken "${match[1]}"
        fi
    done < "${clientLogPath}"
}

function redactBoundedToken() {
    local value="${1}"
    local token="${2}"
    local replacement="${3:-<redacted>}"
    local head=""
    local tail=""
    local beforeChar=""
    local afterChar=""
    local out=""

    while [[ "${value}" == *"${token}"* ]]; do
        head="${value%%"${token}"*}"
        tail="${value#*"${token}"}"
        beforeChar="${head[-1]:- }"
        afterChar="${tail[1]:- }"
        if [[ ! "${beforeChar}" =~ [[:alnum:]_.-] && ! "${afterChar}" =~ [[:alnum:]_.-] ]]; then
            out+="${head}${replacement}"
        else
            out+="${head}${token}"
        fi
        value="${tail}"
    done

    echo "${out}${value}"
}

function redactUsersPaths() {
    local value="${1}"
    local previous=""

    while [[ "${value}" != "${previous}" && "${value}" =~ '/Users/[^/[:space:]]+' ]]; do
        previous="${value}"
        value="${value//${MATCH}/\/Users\/<redacted>}"
    done

    echo "${value}"
}

function redactSensitiveText() {
    local value="${1}"
    local token=""

    value="$(redactUsersPaths "${value}")"
    if (( ${#redactedHostTokens[@]} > 0 )); then
        for token in "${redactedHostTokens[@]}"; do
            value="$(redactBoundedToken "${value}" "${token}" "<redacted-host>")"
        done
    fi
    if (( ${#redactedIdentityTokens[@]} > 0 )); then
        for token in "${redactedIdentityTokens[@]}"; do
            [[ -n "${token}" ]] || continue
            value="$(redactBoundedToken "${value}" "${token}")"
        done
    fi
    echo "${value}"
}

function redactInstallLogLine() {
    local line="${1}"
    local dateToken=""
    local timeToken=""
    local hostToken=""
    local remainder=""

    line="$(redactSensitiveText "${line}")"
    dateToken="${line%% *}"
    remainder="${line#* }"
    if [[ "${remainder}" == "${line}" ]]; then
        echo "${line}"
        return
    fi

    timeToken="${remainder%% *}"
    remainder="${remainder#* }"
    if [[ "${dateToken}" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' && "${timeToken}" =~ '^[0-9]{2}:[0-9]{2}:[0-9]{2}' && "${remainder}" != "${timeToken}" ]]; then
        hostToken="${remainder%% *}"
        if [[ "${hostToken}" == "|"* ]]; then
            echo "${line}"
            return
        fi
        if [[ "${remainder}" == *' '* ]]; then
            remainder="${remainder#* }"
        else
            remainder=""
        fi
        if [[ -n "${hostToken}" ]]; then
            echo "${dateToken} ${timeToken} <redacted-host> ${remainder}"
            return
        fi
    fi

    echo "${line}"
}

function isValidFallbackEnforcementDate() {
    local value="${1}"
    local timestampRegex='^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(Z|[+-][0-9]{2}:[0-9]{2})$'
    local year=0
    local month=0
    local day=0
    local hour=0
    local minute=0
    local second=0
    local daysInMonth=31

    [[ "${value}" =~ ${timestampRegex} ]] || return 1
    [[ "${value}" =~ '^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})' ]] || return 1
    year=$(( 10#${match[1]} ))
    month=$(( 10#${match[2]} ))
    day=$(( 10#${match[3]} ))
    hour=$(( 10#${match[4]} ))
    minute=$(( 10#${match[5]} ))
    second=$(( 10#${match[6]} ))
    (( hour <= 23 && minute <= 59 && second <= 59 )) || return 1
    (( month >= 1 && month <= 12 && day >= 1 )) || return 1

    if [[ "${value}" =~ '([+-])([0-9]{2}):([0-9]{2})$' ]]; then
        (( 10#${match[2]} <= 23 && 10#${match[3]} <= 59 )) || return 1
    fi

    case "${month}" in
        2)
            daysInMonth=28
            if (( (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 )); then
                daysInMonth=29
            fi
            ;;
        4|6|9|11)
            daysInMonth=30
            ;;
    esac

    (( day <= daysInMonth ))
}

function firstLegacyDiskPercentage() {
    local candidatePath=""
    local candidateLayer=""
    local candidateValue=""

    legacyDiskLayer=""
    legacyDiskRaw=""

    for candidateLayer in managed local unknown; do
        case "${candidateLayer}" in
            managed) candidatePath="${managedPlistPath}" ;;
            local)   candidatePath="${localPlistPath}" ;;
            unknown) candidatePath="${unknownPlistPath}" ;;
        esac
        [[ -n "${candidatePath}" ]] || continue
        if plistKeyExists "${candidatePath}" "MinimumDiskFreePercentage"; then
            candidateValue="$(plistKeyValue "${candidatePath}" "MinimumDiskFreePercentage")"
            legacyDiskLayer="${candidateLayer}"
            legacyDiskRaw="${candidateValue}"
            return 0
        fi
    done

    return 1
}

function appendPreferenceFlag() {
    local extraFlag="${1}"

    if [[ -n "${flags}" ]]; then
        flags="${flags}; ${extraFlag}"
    else
        flags="${extraFlag}"
    fi
}



####################################################################################################
#
# Argument Parsing
#
####################################################################################################

while [[ "$#" -gt 0 ]]; do
    case "${1}" in
        --help|-h)
            printUsage
            exit 0
            ;;
        --client-log)
            [[ -n "${2:-}" ]] || failUsage "--client-log requires a path"
            clientLogPath="${2}"
            shift 2
            ;;
        --install-log)
            [[ -n "${2:-}" ]] || failUsage "--install-log requires a path"
            installLogPath="${2}"
            shift 2
            ;;
        --plist)
            [[ -n "${2:-}" ]] || failUsage "--plist requires a path"
            assignPlistPath "$(inferPlistLayer "${2}")" "${2}"
            shift 2
            ;;
        --managed-plist)
            [[ -n "${2:-}" ]] || failUsage "--managed-plist requires a path"
            assignPlistPath "managed" "${2}"
            shift 2
            ;;
        --local-plist)
            [[ -n "${2:-}" ]] || failUsage "--local-plist requires a path"
            assignPlistPath "local" "${2}"
            shift 2
            ;;
        --state-plist)
            [[ -n "${2:-}" ]] || failUsage "--state-plist requires a path"
            statePlistPath="${2}"
            shift 2
            ;;
        --fallback-plist)
            [[ -n "${2:-}" ]] || failUsage "--fallback-plist requires a path"
            fallbackPlistPath="${2}"
            shift 2
            ;;
        --persistence-plist)
            [[ -n "${2:-}" ]] || failUsage "--persistence-plist requires a path"
            persistencePlistPath="${2}"
            shift 2
            ;;
        --launch-daemon-plist)
            [[ -n "${2:-}" ]] || failUsage "--launch-daemon-plist requires a path"
            launchDaemonPlistPath="${2}"
            shift 2
            ;;
        --aggressive-kill)
            [[ -n "${2:-}" ]] || failUsage "--aggressive-kill requires yes or no"
            case "${2:l}" in
                yes|true|present|1) aggressiveKillState="yes" ;;
                no|false|absent|0)  aggressiveKillState="no" ;;
                *) failUsage "--aggressive-kill must be yes or no" ;;
            esac
            shift 2
            ;;
        *)
            failUsage "Unknown option '${1}'"
            ;;
    esac
done

requireReadableFile "Client log (--client-log)" "${clientLogPath}"
requireReadableFile "install.log (--install-log)" "${installLogPath}"

if (( ${#extraPlistPaths[@]} > 1 )); then
    failUsage "Multiple unlabeled --plist files; use --managed-plist and --local-plist"
fi

if (( ${#extraPlistPaths[@]} == 1 )); then
    if [[ -n "${managedPlistPath}" || -n "${localPlistPath}" ]]; then
        failUsage "Unlabeled --plist plus a managed/local plist; label every plist"
    fi
    unknownPlistPath="${extraPlistPaths[1]}"
fi

if [[ -z "${managedPlistPath}" && -z "${localPlistPath}" && -z "${unknownPlistPath}" ]]; then
    failUsage "At least one plist is required (--plist, --managed-plist, or --local-plist)"
fi

for optionalPathLabel in \
    "State plist:${statePlistPath}" \
    "Fallback plist:${fallbackPlistPath}" \
    "Persistence plist:${persistencePlistPath}" \
    "LaunchDaemon plist:${launchDaemonPlistPath}"
do
    optionalLabel="${optionalPathLabel%%:*}"
    optionalPath="${optionalPathLabel#*:}"
    if [[ -n "${optionalPath}" ]]; then
        requireReadableFile "${optionalLabel}" "${optionalPath}"
    fi
done

rdnnFromLogFileName "${clientLogPath}"



####################################################################################################
#
# Known-key index and plist lint
#
####################################################################################################

for prefKey in "${(@k)plistKeyMap}"; do
    knownPlistKeys[${plistKeyMap[$prefKey]}]=${prefKey}
done
knownPlistKeys[MinimumDiskFreePercentage]=minimumDiskFreePercentage

plistLintStatus="not checked"
for plistPath in "${managedPlistPath}" "${localPlistPath}" "${unknownPlistPath}"; do
    [[ -n "${plistPath}" ]] || continue
    if /usr/bin/plutil -lint "${plistPath}" >/dev/null 2>&1; then
        [[ "${plistLintStatus}" == "not checked" ]] && plistLintStatus="ok"
    else
        plistLintStatus="failed"
        inputNotes+=("plutil -lint failed for ${plistPath}")
    fi
done



####################################################################################################
#
# Preference evaluation
#
####################################################################################################

function collectUnknownKeysFromPlist() {
    local plistPath="${1}"
    local rawKey=""
    local rejectionReason=""

    [[ -n "${plistPath}" ]] || return 0
    while IFS= read -r rawKey; do
        [[ -n "${rawKey}" ]] || continue
        if [[ "${rawKey}" == *Localized_* ]]; then
            rejectionReason="$(localizedKeyRejectionReason "${rawKey}")"
            if [[ -n "${rejectionReason}" ]]; then
                rejectedLocalizedKeys+=("${rawKey} (${plistPath:t}): ${rejectionReason}")
            fi
            continue
        fi
        if [[ "${rawKey}" == "MinimumDiskFreePercentage" ]]; then
            deprecatedPlistKeys+=("${rawKey} (${plistPath:t})")
            continue
        fi
        if ! isKnownPlistKey "${rawKey}"; then
            unknownPlistKeys+=("${rawKey} (${plistPath:t})")
        fi
    done < <(plistTopLevelKeys "${plistPath}")
}

function resolvedPreferenceSourceAndValue() {
    local plistKey="${1}"
    local emptyFallsThrough="${2:-NO}"
    local managedValue=""
    local localValue=""
    local unknownValue=""
    local managedExists="false"
    local localExists="false"
    local unknownExists="false"

    resolvedPrefSource=""
    resolvedPrefRaw=""

    if [[ -n "${managedPlistPath}" ]] && plistKeyExists "${managedPlistPath}" "${plistKey}"; then
        managedExists="true"
        managedValue="$(plistKeyValue "${managedPlistPath}" "${plistKey}")"
    fi
    if [[ -n "${localPlistPath}" ]] && plistKeyExists "${localPlistPath}" "${plistKey}"; then
        localExists="true"
        localValue="$(plistKeyValue "${localPlistPath}" "${plistKey}")"
    fi
    if [[ -n "${unknownPlistPath}" ]] && plistKeyExists "${unknownPlistPath}" "${plistKey}"; then
        unknownExists="true"
        unknownValue="$(plistKeyValue "${unknownPlistPath}" "${plistKey}")"
    fi

    if [[ "${emptyFallsThrough}" == "YES" && -z "${managedValue}" ]]; then
        managedExists="false"
    fi
    if [[ "${emptyFallsThrough}" == "YES" && -z "${localValue}" ]]; then
        localExists="false"
    fi
    if [[ "${emptyFallsThrough}" == "YES" && -z "${unknownValue}" ]]; then
        unknownExists="false"
    fi

    if [[ "${managedExists}" == "true" ]]; then
        resolvedPrefSource="managed"
        resolvedPrefRaw="${managedValue}"
    elif [[ "${localExists}" == "true" ]]; then
        resolvedPrefSource="local"
        resolvedPrefRaw="${localValue}"
    elif [[ "${unknownExists}" == "true" ]]; then
        resolvedPrefSource="supplied plist (layer unknown)"
        resolvedPrefRaw="${unknownValue}"
    else
        resolvedPrefSource="default"
        resolvedPrefRaw=""
    fi
}

function evaluateDecisionCriticalPreference() {
    local prefKey="${1}"
    local prefConfig="${preferenceConfiguration[$prefKey]}"
    local prefType="${prefConfig%%|*}"
    local defaultValue="${prefConfig#*|}"
    local plistKey="${plistKeyMap[$prefKey]}"
    local flags=""
    local effective="${defaultValue}"
    local booleanNormalized=""
    local restartNormalized=""

    if [[ "${prefType}" == "boolean" ]]; then
        resolvedPreferenceSourceAndValue "${plistKey}" "YES"
    else
        resolvedPreferenceSourceAndValue "${plistKey}"
    fi

    case "${prefType}" in
        numeric)
            if [[ "${resolvedPrefSource}" != "default" ]]; then
                if [[ "${resolvedPrefRaw}" =~ ^[0-9]+$ ]] && (( resolvedPrefRaw >= 0 && resolvedPrefRaw <= 999 )); then
                    effective="${resolvedPrefRaw}"
                    case "${prefKey}" in
                        aggressiveModeFrequencyMinutes|pastDeadlineForceTimerSeconds|pastDeadlineForceRedisplayDelaySeconds)
                            if (( effective < 1 )); then
                                flags="invalid '${resolvedPrefRaw}' (expected 1-999); using default ${defaultValue}"
                                effective="${defaultValue}"
                                resolvedPrefSource="default"
                            fi
                            ;;
                    esac
                else
                    flags="invalid '${resolvedPrefRaw}' (expected integer 0-999); using default ${defaultValue}"
                    effective="${defaultValue}"
                    resolvedPrefSource="default"
                fi
            fi
            ;;
        boolean)
            if [[ "${resolvedPrefSource}" != "default" ]]; then
                booleanNormalized="$(normalizeBooleanValue "${resolvedPrefRaw}")"
                if [[ -n "${booleanNormalized}" ]]; then
                    effective="${booleanNormalized}"
                else
                    flags="invalid '${resolvedPrefRaw}' (expected boolean); using default ${defaultValue}"
                    effective="${defaultValue}"
                    resolvedPrefSource="default"
                fi
            fi
            ;;
        string)
            if [[ "${prefKey}" == "dailyReminderTimes" ]]; then
                if [[ "${resolvedPrefSource}" == "default" ]]; then
                    effective="${defaultValue}"
                elif normalizeDailyReminderTimes "${resolvedPrefRaw}"; then
                    effective="${normalizedDailyReminderTimesCSV}"
                    if [[ -n "${ignoredDailyReminderTimesCSV}" ]]; then
                        flags="ignored invalid entries: ${ignoredDailyReminderTimesCSV}"
                    fi
                else
                    flags="invalid '${resolvedPrefRaw}'; using default ${defaultValue}"
                    effective="${defaultValue}"
                    resolvedPrefSource="default"
                fi
            elif [[ "${prefKey}" == "minutesBeforeDeadlineReminderSchedule" ]]; then
                if [[ "${resolvedPrefSource}" == "default" ]]; then
                    effective="${defaultValue}"
                elif [[ -z "$(trimSurroundingWhitespace "${resolvedPrefRaw}")" ]]; then
                    effective=""
                    flags="empty; pre-deadline threshold reminders disabled"
                elif normalizeMinuteThresholdSchedule "${resolvedPrefRaw}"; then
                    effective="${normalizedMinuteThresholdScheduleCSV}"
                    if [[ -n "${ignoredMinuteThresholdScheduleCSV}" ]]; then
                        flags="ignored invalid entries: ${ignoredMinuteThresholdScheduleCSV}"
                    fi
                else
                    flags="invalid '${resolvedPrefRaw}'; using default ${defaultValue}"
                    effective="${defaultValue}"
                    resolvedPrefSource="default"
                fi
            elif [[ "${prefKey}" == "pastDeadlineRestartBehavior" ]]; then
                if [[ "${resolvedPrefSource}" == "default" ]]; then
                    effective="${defaultValue}"
                else
                    restartNormalized="$(normalizePastDeadlineRestartBehaviorValue "${resolvedPrefRaw}")"
                    if [[ -n "${restartNormalized}" ]]; then
                        effective="${restartNormalized}"
                    else
                        flags="invalid '${resolvedPrefRaw}' (expected Off, Prompt, Force); using default ${defaultValue}"
                        effective="${defaultValue}"
                        resolvedPrefSource="default"
                    fi
                fi
            else
                if [[ "${resolvedPrefSource}" != "default" ]]; then
                    effective="${resolvedPrefRaw}"
                fi
            fi
            ;;
    esac

    if [[ "${prefKey}" == "minimumDiskFreeGB" ]] && firstLegacyDiskPercentage; then
        if [[ "${resolvedPrefSource}" == "default" ]]; then
            if [[ "${legacyDiskRaw}" =~ ^[0-9]+$ ]] && (( legacyDiskRaw <= 100 )); then
                effective="${legacyDiskRaw}%"
                resolvedPrefSource="${legacyDiskLayer} (deprecated percentage)"
                appendPreferenceFlag "honored MinimumDiskFreePercentage ${legacyDiskRaw}% because MinimumDiskFreeGB is not set"
            else
                appendPreferenceFlag "invalid deprecated MinimumDiskFreePercentage '${legacyDiskRaw}'; using MinimumDiskFreeGB ${effective}"
            fi
        else
            appendPreferenceFlag "MinimumDiskFreePercentage ${legacyDiskRaw} ignored because MinimumDiskFreeGB is set"
        fi
    fi

    preferenceRows+=("$(escapeTableCell "${plistKey}")|$(escapeTableCell "${effective}")|$(escapeTableCell "${resolvedPrefSource}")|$(escapeTableCell "${flags}")")
}

collectUnknownKeysFromPlist "${managedPlistPath}"
collectUnknownKeysFromPlist "${localPlistPath}"
collectUnknownKeysFromPlist "${unknownPlistPath}"

decisionCriticalOrder=(
    scriptLog
    dailyReminderTimes
    minutesBeforeDeadlineReminderSchedule
    daysBeforeDeadlineDisplayReminder
    daysBeforeDeadlineBlurscreen
    daysBeforeDeadlineHidingButton2
    quietPeriodMinutes
    outsideDisplayWindowPeriodicReminderDays
    aggressiveModePastDeadlineHours
    aggressiveModeFrequencyMinutes
    pastDeadlineRestartBehavior
    daysPastDeadlineRestartWorkflow
    pastDeadlineRestartMinimumUptimeMinutes
    pastDeadlineForceTimerSeconds
    pastDeadlineForceRedisplayDelaySeconds
    meetingDelay
    acceptableAssertionApplicationNames
    minimumDiskFreeGB
    daysOfExcessiveUptimeWarning
    disableButton2InsteadOfHide
    languageOverride
)

for prefKey in "${decisionCriticalOrder[@]}"; do
    evaluateDecisionCriticalPreference "${prefKey}"
done



####################################################################################################
#
# Client log
#
####################################################################################################

function extractRdnnFromLogText() {
    local logLine=""
    local managementRegex='/Library/Management/([^/]+)/'
    local managedPrefsRegex='/Library/Managed Preferences/([^/]+)\.dorm'
    local localPrefsRegex='/Library/Preferences/([^/]+)\.dorm'
    local launchDaemonRegex='/Library/LaunchDaemons/([^/]+)\.dor'
    local scriptLogRegex='/var/log/([^[:space:]/]+)\.log'

    while IFS= read -r logLine; do
        if [[ "${logLine}" =~ ${managementRegex} ]]; then
            addUniqueRdnnCandidate "${match[1]}"
        fi
        if [[ "${logLine}" =~ ${managedPrefsRegex} ]]; then
            addUniqueRdnnCandidate "${match[1]}"
        fi
        if [[ "${logLine}" =~ ${localPrefsRegex} ]]; then
            addUniqueRdnnCandidate "${match[1]}"
        fi
        if [[ "${logLine}" =~ ${launchDaemonRegex} ]]; then
            addUniqueRdnnCandidate "${match[1]}"
        fi
        if [[ "${logLine}" =~ ${scriptLogRegex} ]]; then
            addUniqueRdnnCandidate "${match[1]}"
        fi
    done < "${clientLogPath}"
}

extractRdnnFromLogText

if (( ${#rdnnCandidates[@]} == 1 )); then
    detectedRdnn="${rdnnCandidates[1]}"
elif (( ${#rdnnCandidates[@]} == 0 )); then
    identityNotes+=("RDNN could not be detected from filenames or log paths")
else
    identityNotes+=("Multiple RDNN candidates: ${(j:, :)rdnnCandidates}")
fi

runtimeInitiatingLines="$(awk '
    /^[^ ]+ \([^)]+\): .*\[PRE-FLIGHT\].*Initiating/ { previous=last; last=NR }
    END { printf "%s %s\n", previous+0, last+0 }
' "${clientLogPath}")"
previousRuntimeInitiating="${runtimeInitiatingLines%% *}"
latestRuntimeInitiating="${runtimeInitiatingLines##* }"
deploymentInitiatingLine="$(awk '
    /^[^ ]+  \([^)]+\): .*\[PRE-FLIGHT\].*Initiating/ { last=NR }
    END { print last+0 }
' "${clientLogPath}")"

if (( latestRuntimeInitiating > 0 )); then
    heartbeatLine="$(awk -v rangeStart="${previousRuntimeInitiating}" -v rangeEnd="${latestRuntimeInitiating}" '
        NR > rangeStart && NR < rangeEnd && /Heartbeat launch triggered/ { hit=NR }
        END { print hit+0 }
    ' "${clientLogPath}")"
    if (( heartbeatLine > 0 )); then
        latestRunStart="${heartbeatLine}"
    else
        latestRunStart="${latestRuntimeInitiating}"
    fi
    if (( deploymentInitiatingLine > latestRuntimeInitiating )); then
        identityNotes+=("A deployment Initiating line follows the latest runtime run. This fact sheet stays on that runtime run.")
    fi
else
    latestRunStart=1
    identityNotes+=("No runtime 'Initiating' pre-flight line found; using the entire client log as the latest run")
    if (( deploymentInitiatingLine > 0 )); then
        identityNotes+=("A deployment Initiating line is present. Deployment log lines use a different logger and are not the runtime run.")
    fi
fi

typeset -a latestRunLines=()
while IFS= read -r logLine; do
    latestRunLines+=("${logLine}")
done < <(tail -n +"${latestRunStart}" "${clientLogPath}")
latestRunLineCount="${#latestRunLines[@]}"

decisionPattern='(ddm update check|no reminder shown|next step|currently installed macos|ddm declaration logged|opening software update|normal ddm resolver result|resolver suppression summary|resolved ddm declaration|installed macos|already satisfies|emergency fallback|mdm fallback|softwareupdate ddm state|ignoring .* install\.log ddm declaration|conflicting|update tonight|quiet period|quietperiodminutes|pre-deadline threshold|aggressive mode|past deadline|do not disturb|meeting|display window|periodic reminder|swiftdialog|resolved dailyremindertimes|resolved minutesbeforedeadlinereminderschedule|no client-side preferences|reading preference overrides|preferences loaded|invalid |ignoring invalid|ignored invalid|display reminder dialog|scheduled next daemon reminder|accepted padded enforcement date|heartbeat launch triggered|return code:| clicked )'
clientLogLineRegex='^([^ ]+) \(([^)]+)\): ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}) - \[([A-Z -]+)\][[:space:]]+(.*)$'

for logLine in "${latestRunLines[@]}"; do
    if [[ "${logLine}" =~ ${clientLogLineRegex} ]]; then
        logLevel="${match[4]}"
        logMessage="${match[5]}"
        if [[ "${logMessage}" == *"Initiating"* ]]; then
            logOrganizationScriptName="${match[1]}"
            logScriptVersion="${match[2]}"
        elif [[ -z "${logScriptVersion}" && "${logMessage}" != *"Heartbeat launch triggered"* ]]; then
            logOrganizationScriptName="${match[1]}"
            logScriptVersion="${match[2]}"
        fi
        # 5.2.0b2+ "Currently installed macOS <version> (<build>)"; earlier separate Version / Build lines
        if [[ "${logMessage}" =~ '^Currently installed macOS ([^ ]+) \(([^)]+)\)$' ]]; then
            installedMacOSVersion="${match[1]}"
            installedMacOSBuild="${match[2]}"
        elif [[ "${logMessage}" == "Installed macOS Version: "* ]]; then
            installedMacOSVersion="${logMessage#Installed macOS Version: }"
        elif [[ "${logMessage}" == "Installed macOS Build: "* ]]; then
            installedMacOSBuild="${logMessage#Installed macOS Build: }"
        fi
        # 5.2.0b2+ "DDM update check: … (status=…; …)"; earlier "Normal DDM resolver result: status=…"
        if [[ "${logMessage}" == "DDM update check: "*"(status="* || "${logMessage}" == "Normal DDM resolver result:"* ]]; then
            resolverStatusLine="${logMessage}"
        fi
        if [[ "${logLevel}" == "QUIT" || "${logLevel}" == "FATAL ERROR" || "${logLevel}" == "ERROR" || "${logLevel}" == "WARNING" ]]; then
            latestRunDecisionLines+=("${logLine}")
        elif [[ "${logMessage:l}" =~ ${decisionPattern} ]]; then
            latestRunDecisionLines+=("${logLine}")
        fi
    fi
done

lastQuietPeriodReturnCodeRecord="$(grep -n -E '\[INFO\].*Return Code: (0|2|3|4|10)' "${clientLogPath}" | tail -1)"
if [[ -n "${lastQuietPeriodReturnCodeRecord}" ]]; then
    quietPeriodReturnCodeLineNumber="${lastQuietPeriodReturnCodeRecord%%:*}"
    quietPeriodReturnCodeLine="${lastQuietPeriodReturnCodeRecord#*:}"
    if (( quietPeriodReturnCodeLineNumber < latestRunStart )); then
        if (( ${#latestRunDecisionLines[@]} > 0 )); then
            latestRunDecisionLines=("${quietPeriodReturnCodeLine}" "${latestRunDecisionLines[@]}")
        else
            latestRunDecisionLines=("${quietPeriodReturnCodeLine}")
        fi
        identityNotes+=("Last quiet-period Return Code is from an earlier run. Quiet period uses that line from the whole client log.")
    fi
fi

if [[ -n "${logScriptVersion}" && "${logScriptVersion}" != "${checklistScriptVersion}" ]]; then
    identityNotes+=("Client log scriptVersion is ${logScriptVersion}; this helper's preference defaults and log phrases match ${checklistScriptVersion}")
fi

deploymentScriptVersion="$(awk '
    /^[^ ]+  \([^)]+\): / { version=$0; sub(/^[^ ]+  \(/, "", version); sub(/\).*$/, "", version) }
    END { print version }
' "${clientLogPath}")"

# One row per runtime run: start, script, resolver status, outcome
typeset -a allRunHistoryRows=()
while IFS= read -r logLine; do
    [[ -n "${logLine}" ]] && allRunHistoryRows+=("${logLine}")
done < <(awk '
    function outcome() {
        if (dialog) return (rc != "" ? "dialog shown; " rc : "dialog shown; no Return Code logged")
        if (fatal != "") return "fatal: " fatal
        if (noreminder != "") return noreminder
        if (quit != "") return "quit: " quit
        if (quitend != "") return "quit: " quitend
        if (rc != "") return rc
        return "no outcome logged"
    }
    function flush() {
        if (started) printf "%s\t%s\t%s\t%s\n", start, script, status, outcome()
    }
    /^[^ ]+ \([^)]+\): [0-9-]+ [0-9:]+ - \[/ {
        if ($0 ~ /\[PRE-FLIGHT\].*Initiating/) {
            flush()
            started=1; start=$3 " " $4; script=$1 " " $2; sub(/:$/, "", script)
            status="no resolver line"; dialog=0; rc=""; quit=""; quitend=""; fatal=""; noreminder=""
            next
        }
        if (!started) next
        message=substr($0, index($0, "]") + 1); sub(/^[ \t]+/, "", message)
        if (message ~ /^Normal DDM resolver result: status=/ || message ~ /^DDM update check: .*\(status=/) {
            status=substr(message, index(message, "status=") + 7); sub(/;.*$/, "", status)
        }
        if (message ~ /^No reminder shown: /) noreminder=message
        if (message ~ /^Display Reminder Dialog/) dialog=1
        if (match(message, /Return Code: [0-9]+/)) rc=substr(message, RSTART, RLENGTH)
        # Every run ends with "Exiting …" / "Ticking away …"; keep the specific reason when one was logged
        if ($0 ~ / - \[QUIT\]/) {
            if (message ~ /^(Exiting|Ticking away)/) { if (quitend == "") quitend=message }
            else quit=message
        }
        if ($0 ~ / - \[FATAL ERROR\]/) fatal=message
    }
    END { flush() }
' "${clientLogPath}")
runHistoryTotal="${#allRunHistoryRows[@]}"
if (( runHistoryTotal > 0 )); then
    runHistoryRows=("${(@)allRunHistoryRows[$(( runHistoryTotal > reportSkeletonRunLimit ? runHistoryTotal - reportSkeletonRunLimit + 1 : 1 )),-1]}")
fi

# Lines without a DDM OS Reminder prefix are usually shell errors from the starter or runtime
unprefixedSummary="$(awk '
    NF == 0 { next }
    /^[^ ]+ +\([^)]+\): / { next }
    { total++; seen[$0]++; if (seen[$0] > topCount) { topCount=seen[$0]; topLine=$0 } }
    END { printf "%d\t%d\t%s\n", total+0, topCount+0, topLine }
' "${clientLogPath}")"
IFS=$'\t' read -r unprefixedLineCount unprefixedTopCount unprefixedTopLine <<< "${unprefixedSummary}"



####################################################################################################
#
# install.log evidence (same 4000-line window as reminderDialog.zsh)
#
####################################################################################################

installLogLineCount="$(wc -l < "${installLogPath}" | tr -d ' ')"
typeset -a installLogWindow=()
while IFS= read -r logLine; do
    installLogWindow+=("${logLine}")
done < <(tail -n "${ddmResolverLookbackLines}" "${installLogPath}")
installLogWindowCount="${#installLogWindow[@]}"

if (( installLogLineCount < ddmResolverLookbackLines )); then
    inputNotes+=("install.log has ${installLogLineCount} line(s); runtime lookback is ${ddmResolverLookbackLines}. Analysis used the entire upload.")
fi

if [[ -n "${persistencePlistPath}" ]]; then
    loadDDMStatePersistenceSignatures || true
fi

# Consecutive candidates with the same version, deadline, and build collapse into one span
spanKey=""
spanFirst=""
spanLast=""
typeset -a spanSourceList=()
spanVersion=""
spanBuild=""
spanDate=""
spanCorroboration=""

function flushDeclarationSpan() {
    [[ -n "${spanKey}" ]] || return 0
    installLogDeclarationSpans+=("${spanFirst} | ${spanLast} | ${spanVersion} | ${spanBuild} | ${spanDate} | ${(j:, :)spanSourceList} | ${spanCorroboration}")
}

for logLine in "${installLogWindow[@]}"; do
    if parseDDMDeclarationFromLine "${logLine}"; then
        versionValid="yes"
        [[ "${parsedDDMVersionString}" =~ ${ddmVersionRegex} ]] || versionValid="no"
        corroboration="$(corroborationLabelForCandidate "${parsedDDMVersionString}" "${parsedDDMEnforcedInstallDate}")"
        installLogCandidates+=("${parsedDDMLogTimestamp} | ${parsedDDMSourceType} | ${parsedDDMVersionString} | ${parsedDDMEnforcedInstallDate} | ${parsedDDMBuildVersionString} | versionValid=${versionValid}; corroborated=${corroboration}")
        candidateSpanKey="${parsedDDMVersionString}|${parsedDDMEnforcedInstallDate}|${parsedDDMBuildVersionString}"
        if [[ "${candidateSpanKey}" == "${spanKey:-}" ]]; then
            spanLast="${parsedDDMLogTimestamp}"
            (( ${spanSourceList[(Ie)${parsedDDMSourceType}]} )) || spanSourceList+=("${parsedDDMSourceType}")
        else
            flushDeclarationSpan
            spanKey="${candidateSpanKey}"
            spanFirst="${parsedDDMLogTimestamp}"
            spanLast="${parsedDDMLogTimestamp}"
            spanSourceList=("${parsedDDMSourceType}")
            spanVersion="${parsedDDMVersionString}"
            [[ "${versionValid}" == "yes" ]] || spanVersion+=" (invalid)"
            spanBuild="${parsedDDMBuildVersionString}"
            spanDate="${parsedDDMEnforcedInstallDate}"
            spanCorroboration="${corroboration}"
        fi
    fi
    if [[ "${logLine}" == *"Failed to add declaration:"* && "${logLine}" == *"Invalid declaration:"* ]]; then
        if extractDDMLogTimestamp "${logLine}" && parseDDMDeclarationFieldsFromText "${logLine}"; then
            installLogInvalidDeclarations+=("${parsedDDMLogTimestamp} | ${parsedDDMVersionString} | ${parsedDDMEnforcedInstallDate} | ${parsedDDMBuildVersionString}")
        else
            installLogInvalidDeclarations+=("${logLine}")
        fi
    fi
    if [[ "${logLine}" == *"No updates found for DDM to enforce"* ]]; then
        installLogNoUpdatesLines+=("${logLine}")
    fi
    if [[ "${logLine}" == *"Found product with requested PMV ("* || "${logLine}" == *"Armed DDM activity scheduler for "* ]]; then
        installLogRecoveryLines+=("${logLine}")
    fi
    if [[ "${logLine}" == *"MADownloadNoMatchFound"* || "${logLine}" == *"pallasNoPMVMatchFound=true"* || "${logLine}" == *"No available updates found. Please try again later."* ]]; then
        installLogNoMatchLines+=("${logLine}")
    fi
    if [[ "${logLine}" == *"softwareupdated["* ]] && [[ "${logLine}" == *"SUOSUInstallTonightManager:"* || "${logLine}" == *"SUOSUScheduler:"* ]]; then
        installLogTonightLines+=("${logLine}")
    fi
done
flushDeclarationSpan



####################################################################################################
#
# Fact sheet
#
####################################################################################################

echo "# DDM OS Reminder client-state fact sheet"
echo ""
echo "- Helper: ${scriptRelativePath} (${scriptVersion})"
echo "- Checklist: reminderDialog.zsh ${checklistScriptVersion} preference defaults and log phrases"
echo "- Read-only: no files were written"
echo "- Client log resolver result is authoritative for what this Mac did"
echo "- This helper lists install.log evidence; it does not re-decide resolver status"
echo "- Usernames, first names, /Users paths, install.log computer names, and labeled serial numbers are redacted below"
echo ""

echo "## Inputs"
echo ""
echo "| Input | Path |"
echo "|---|---|"
collectIdentityTokens

echo "| Client log | $(redactSensitiveText "${clientLogPath}") |"
echo "| install.log | $(redactSensitiveText "${installLogPath}") |"
if [[ -n "${managedPlistPath}" ]]; then
    echo "| Managed plist | $(redactSensitiveText "${managedPlistPath}") |"
fi
if [[ -n "${localPlistPath}" ]]; then
    echo "| Local plist | $(redactSensitiveText "${localPlistPath}") |"
fi
if [[ -n "${unknownPlistPath}" ]]; then
    echo "| Supplied plist (layer unknown) | $(redactSensitiveText "${unknownPlistPath}") |"
fi
if [[ -n "${statePlistPath}" ]]; then
    echo "| State plist | $(redactSensitiveText "${statePlistPath}") |"
else
    echo "| State plist | not supplied |"
fi
if [[ -n "${fallbackPlistPath}" ]]; then
    echo "| Fallback plist | $(redactSensitiveText "${fallbackPlistPath}") |"
else
    echo "| Fallback plist | not supplied |"
fi
if [[ -n "${persistencePlistPath}" ]]; then
    echo "| softwareupdate DDM state plist | $(redactSensitiveText "${persistencePlistPath}") |"
else
    echo "| softwareupdate DDM state plist | not supplied |"
fi
if [[ -n "${launchDaemonPlistPath}" ]]; then
    echo "| LaunchDaemon plist | $(redactSensitiveText "${launchDaemonPlistPath}") |"
else
    echo "| LaunchDaemon plist | not supplied |"
fi
echo "| dor-aggressive-kill | ${aggressiveKillState} |"
echo "| Plist lint | ${plistLintStatus} |"
echo ""

if (( ${#inputNotes[@]} > 0 )); then
    echo "Notes:"
    for note in "${inputNotes[@]}"; do
        echo "- $(redactSensitiveText "${note}")"
    done
    echo ""
fi

echo "## Identity"
echo ""
echo "| Field | Value |"
echo "|---|---|"
if (( ${#rdnnCandidates[@]} == 1 )); then
    echo "| RDNN | ${detectedRdnn} |"
elif (( ${#rdnnCandidates[@]} == 0 )); then
    echo "| RDNN | undetected |"
else
    echo "| RDNN | conflict: ${(j:, :)rdnnCandidates} |"
fi
echo "| Log script name | ${logOrganizationScriptName:-undetected} |"
echo "| Log scriptVersion | ${logScriptVersion:-undetected} |"
echo "| Installed macOS version | ${installedMacOSVersion:-not in latest run} |"
echo "| Installed macOS build | ${installedMacOSBuild:-not in latest run} |"
echo "| Latest run lines | ${latestRunLineCount} (from last Initiating line) |"
echo ""

if (( ${#identityNotes[@]} > 0 )); then
    echo "Notes:"
    for note in "${identityNotes[@]}"; do
        echo "- $(redactSensitiveText "${note}")"
    done
    echo ""
fi

if [[ -n "${unknownPlistPath}" && -z "${managedPlistPath}" && -z "${localPlistPath}" ]]; then
    echo "Preference precedence: a single unlabeled plist was supplied. Defaults apply only for keys missing from that file. Managed vs local precedence could not be evaluated."
    echo ""
fi

echo "## Effective settings"
echo ""
echo "Precedence: Managed Preferences -> Local Preferences -> script defaults (${checklistScriptVersion})."
echo ""
echo "| Plist key | Effective | Source | Flags |"
echo "|---|---|---|---|"
for row in "${preferenceRows[@]}"; do
    IFS='|' read -r colKey colEffective colSource colFlags <<< "${row}"
    echo "| ${colKey} | ${colEffective} | ${colSource} | ${colFlags} |"
done
echo ""

if (( ${#deprecatedPlistKeys[@]} > 0 )); then
    echo "Deprecated keys:"
    for key in "${deprecatedPlistKeys[@]}"; do
        echo "- ${key} (honored only when MinimumDiskFreeGB is not set; see that row. Support ends in 6.0.0)"
    done
    echo ""
fi

if (( ${#unknownPlistKeys[@]} > 0 )); then
    echo "Unknown keys:"
    for key in "${unknownPlistKeys[@]}"; do
        echo "- ${key}"
    done
    echo ""
fi

if (( ${#rejectedLocalizedKeys[@]} > 0 )); then
    echo "Rejected localized keys:"
    for key in "${rejectedLocalizedKeys[@]}"; do
        echo "- ${key}"
    done
    echo ""
fi

echo "## Latest client-log run"
echo ""
if [[ -n "${resolverStatusLine}" ]]; then
    echo "Recorded resolver result:"
    echo ""
    echo "    $(redactSensitiveText "${resolverStatusLine}")"
    echo ""
else
    echo "No \`DDM update check\` (5.2.0b2+) or \`Normal DDM resolver result\` line in the latest run."
    echo ""
fi

if (( ${#latestRunDecisionLines[@]} == 0 )); then
    echo "No decision-related NOTICE/WARNING/ERROR/QUIT lines found in the latest run."
    echo ""
else
    echo "Decision-related lines:"
    echo ""
    echo '```'
    for logLine in "${latestRunDecisionLines[@]}"; do
        echo "$(redactSensitiveText "${logLine}")"
    done
    echo '```'
    echo ""
fi

echo "## install.log evidence"
echo ""
echo "- Lines in upload: ${installLogLineCount}"
echo "- Window used: last ${installLogWindowCount} line(s) (runtime lookback ${ddmResolverLookbackLines})"
echo "- Corroboration: ${ddmStatePersistenceStatus}"
echo ""

echo "### Declaration candidates"
echo ""
if (( ${#installLogCandidates[@]} == 0 )); then
    echo "None in the lookback window."
    echo ""
else
    echo "| Timestamp | Source type | Version | EnforcedInstallDate | Build | Flags |"
    echo "|---|---|---|---|---|---|"
    for row in "${installLogCandidates[@]}"; do
        echo "| ${row} |"
    done
    echo ""
fi

echo "### Invalid declarations"
echo ""
if (( ${#installLogInvalidDeclarations[@]} == 0 )); then
    echo "None."
    echo ""
else
    for row in "${installLogInvalidDeclarations[@]}"; do
        echo "- $(redactInstallLogLine "${row}")"
    done
    echo ""
fi

echo "### No updates found for DDM to enforce"
echo ""
if (( ${#installLogNoUpdatesLines[@]} == 0 )); then
    echo "None."
    echo ""
else
    echo '```'
    for row in "${installLogNoUpdatesLines[@]}"; do
        echo "$(redactInstallLogLine "${row}")"
    done
    echo '```'
    echo ""
fi

echo "### Recovery markers"
echo ""
if (( ${#installLogRecoveryLines[@]} == 0 )); then
    echo "None."
    echo ""
else
    echo '```'
    for row in "${installLogRecoveryLines[@]}"; do
        echo "$(redactInstallLogLine "${row}")"
    done
    echo '```'
    echo ""
fi

echo "### No-match markers"
echo ""
if (( ${#installLogNoMatchLines[@]} == 0 )); then
    echo "None."
    echo ""
else
    echo '```'
    for row in "${installLogNoMatchLines[@]}"; do
        echo "$(redactInstallLogLine "${row}")"
    done
    echo '```'
    echo ""
fi

echo "### Update Tonight softwareupdated lines"
echo ""
if (( ${#installLogTonightLines[@]} == 0 )); then
    echo "None."
    echo ""
else
    echo '```'
    for row in "${installLogTonightLines[@]}"; do
        echo "$(redactInstallLogLine "${row}")"
    done
    echo '```'
    echo ""
fi

echo "## Optional runtime files"
echo ""

if [[ -n "${statePlistPath}" ]]; then
    echo "### dor-state.plist"
    echo ""
    for stateKey in NextScheduledReminder UpdateTonightSuppressionUntil DaemonLastTriggered PreDeadlineThresholdSignature PreDeadlineThresholdDelivered PreDeadlineThresholdSkipped; do
        if plistKeyExists "${statePlistPath}" "${stateKey}"; then
            echo "- ${stateKey}: $(redactSensitiveText "$(plistKeyValue "${statePlistPath}" "${stateKey}")")"
        else
            echo "- ${stateKey}: absent"
        fi
    done
    echo ""
else
    echo "dor-state.plist not supplied. NextScheduledReminder cannot be reported from this upload."
    echo ""
fi

echo "Starter exits quietly, with no new dorm run and no new log line, when NextScheduledReminder is FALSE, when that value is YYYY-MM-DD:HH:MM:SS and still in the future, or when dor.pid names a live process. A missing NextScheduledReminder key lets the starter launch."
echo ""

if [[ -n "${fallbackPlistPath}" ]]; then
    echo "### dor-fallback-declaration.plist"
    echo ""
    fallbackSchemaVersion="$(/usr/bin/plutil -extract SchemaVersion raw -expect integer "${fallbackPlistPath}" 2>/dev/null)" || fallbackSchemaVersion=""
    fallbackVersion="$(/usr/bin/plutil -extract VersionString raw -expect string "${fallbackPlistPath}" 2>/dev/null)" || fallbackVersion=""
    fallbackBuild="$(/usr/bin/plutil -extract BuildVersionString raw -expect string "${fallbackPlistPath}" 2>/dev/null)" || fallbackBuild=""
    fallbackDeadline="$(/usr/bin/plutil -extract EnforcedInstallDate raw -expect string "${fallbackPlistPath}" 2>/dev/null)" || fallbackDeadline=""
    fallbackSource="$(/usr/bin/plutil -extract Source raw -expect string "${fallbackPlistPath}" 2>/dev/null)" || fallbackSource=""
    fallbackGate="would accept"
    if ! /usr/bin/plutil -lint "${fallbackPlistPath}" >/dev/null 2>&1; then
        fallbackGate="would reject: plist is unreadable or corrupt"
    elif [[ "${fallbackSchemaVersion}" != "1" || "${fallbackBuild}" != "(null)" || "${fallbackSource}" != "JamfProScriptParameters" ]]; then
        fallbackGate="would reject: schema or constants are invalid"
    elif [[ ! "${fallbackVersion}" =~ ${ddmVersionRegex} ]]; then
        fallbackGate="would reject: version is invalid"
    elif ! isValidFallbackEnforcementDate "${fallbackDeadline}"; then
        fallbackGate="would reject: deadline is invalid or timezone-free"
    fi
    echo "- SchemaVersion: ${fallbackSchemaVersion:-missing}"
    echo "- VersionString: ${fallbackVersion:-missing}"
    echo "- BuildVersionString: ${fallbackBuild:-missing}"
    echo "- EnforcedInstallDate: ${fallbackDeadline:-missing}"
    echo "- Source: ${fallbackSource:-missing}"
    echo "- Runtime fallback gate: ${fallbackGate}"
    echo "- The client log resolver result remains what this Mac did"
    echo ""
fi

if [[ -n "${launchDaemonPlistPath}" ]]; then
    echo "### LaunchDaemon plist"
    echo ""
    echo "- Label: $(plistKeyValue "${launchDaemonPlistPath}" "Label")"
    echo "- ProgramArguments: $(redactSensitiveText "$(plistKeyValue "${launchDaemonPlistPath}" "ProgramArguments")")"
    echo "- StartInterval: $(plistKeyValue "${launchDaemonPlistPath}" "StartInterval")"
    echo "- RunAtLoad: $(plistKeyValue "${launchDaemonPlistPath}" "RunAtLoad")"
    echo ""
fi



####################################################################################################
#
# Report skeleton (single report format; see Resources/skills/diagnose-client-state/SKILL.md)
#
####################################################################################################

function plistLintLabel() {
    if /usr/bin/plutil -lint "${1}" >/dev/null 2>&1; then
        echo "plutil lint ok"
    else
        echo "plutil lint failed"
    fi
}

function skeletonFileRow() {
    echo "| ${1} | ${2} | $(escapeTableCell "${3}") |"
}

function skeletonPlistRow() {
    local label="${1}"
    local plistPath="${2}"
    local missingNote="${3}"

    if [[ -n "${plistPath}" ]]; then
        skeletonFileRow "${label}" "received" "\`$(redactSensitiveText "${plistPath:t}")\`; $(plistLintLabel "${plistPath}")"
    else
        skeletonFileRow "${label}" "not in upload" "${missingNote}"
    fi
}

function skeletonMarkerBullet() {
    local label="${1}"
    local latestLine=""

    shift
    if (( $# == 0 )); then
        echo "- ${label}: none"
        return 0
    fi
    latestLine="$(redactInstallLogLine "${@[-1]}")"
    latestLine="${latestLine//\`/}"
    echo "- ${label}: ${#} line(s); latest: \`${latestLine}\`"
}

if [[ -n "${detectedRdnn}" ]]; then
    skeletonRdnn="\`${detectedRdnn}\`"
    reportFileRdnn="${detectedRdnn//[^A-Za-z0-9._-]/-}"
elif (( ${#rdnnCandidates[@]} == 0 )); then
    skeletonRdnn="undetected"
    reportFileRdnn="rdnn-undetected"
else
    skeletonRdnn="conflict: ${(j:, :)rdnnCandidates}"
    reportFileRdnn="rdnn-conflict"
fi
reportFileName="ddm-os-reminder-${reportFileRdnn}-$(date +%Y-%m-%d-%H%M%S).md"

if (( latestRuntimeInitiating > 0 )) && [[ -n "${logScriptVersion}" ]]; then
    skeletonRuntimeVersion="\`${logOrganizationScriptName} (${logScriptVersion})\`"
    if [[ "${logScriptVersion}" == "${checklistScriptVersion}" ]]; then
        skeletonChecklistMatch="yes (\`${checklistScriptVersion}\`)"
    else
        skeletonChecklistMatch="no: runtime \`${logScriptVersion}\`, checklist \`${checklistScriptVersion}\`; checklist is best-effort"
    fi
else
    skeletonRuntimeVersion="no runtime run in client log"
    skeletonChecklistMatch="unknown: no runtime version; checklist \`${checklistScriptVersion}\` is best-effort"
fi

if [[ -n "${deploymentScriptVersion}" ]]; then
    skeletonDeploymentVersion="\`${deploymentScriptVersion}\` (deployment output, not a runtime run)"
else
    skeletonDeploymentVersion="no deployment lines in client log"
fi

if [[ -n "${installedMacOSVersion}" && -n "${installedMacOSBuild}" ]]; then
    skeletonInstalledMacOS="${installedMacOSVersion} (${installedMacOSBuild})"
else
    skeletonInstalledMacOS="${installedMacOSVersion:-not in latest run}"
fi

case "${ddmStatePersistenceStatus}" in
    available)    skeletonCorroboration="checked against \`SoftwareUpdateDDMStatePersistence.plist\`" ;;
    unrecognized) skeletonCorroboration="\`SoftwareUpdateDDMStatePersistence.plist\` unrecognized; install.log-only" ;;
    unavailable)  skeletonCorroboration="\`SoftwareUpdateDDMStatePersistence.plist\` unreadable; install.log-only" ;;
    *)            skeletonCorroboration="not checked; \`SoftwareUpdateDDMStatePersistence.plist\` not in upload" ;;
esac

skeletonResolverHint="none recorded"
if [[ -n "${resolverStatusLine}" ]]; then
    skeletonResolverHint="${resolverStatusLine#*status=}"
    skeletonResolverHint="${skeletonResolverHint%%;*}"
fi

echo "## Report skeleton"
echo ""
echo "Copy everything between the markers into the report. Fill only the \`<!-- agent: … -->\` slots; do not reformat helper tables. Rules: Resources/skills/diagnose-client-state/SKILL.md."
echo ""
echo "Suggested report filename: \`${reportFileName}\`"
echo ""
echo "<!-- report-skeleton:begin -->"
echo "# [DDM OS Reminder](https://snelson.us/ddm) diagnosis: ${skeletonRdnn}"
echo ""
echo "Analysis date: $(date +%F) · Helper: \`${scriptRelativePath}\` (${scriptVersion}) · Checklist: \`reminderDialog.zsh\` ${checklistScriptVersion}"
echo ""

echo "## 1. Verdict"
echo ""
echo "<!-- agent: **<Category>** (\`<status>\`). One or two sentences. Category from the SKILL.md verdict list. Last recorded resolver status: ${skeletonResolverHint}. -->"
echo ""

echo "## 2. Files"
echo ""
echo "| File | Status | Note |"
echo "|---|---|---|"
skeletonFileRow "Client log" "received" "\`$(redactSensitiveText "${clientLogPath:t}")\`"
skeletonFileRow "\`install.log\`" "received" "${installLogLineCount} line(s); last ${installLogWindowCount} analyzed"
if [[ -n "${unknownPlistPath}" ]]; then
    skeletonFileRow "Supplied plist (layer unknown)" "received" "\`$(redactSensitiveText "${unknownPlistPath:t}")\`; $(plistLintLabel "${unknownPlistPath}"); managed versus local precedence not evaluated"
fi
if [[ -n "${managedPlistPath}" || -z "${unknownPlistPath}" ]]; then
    skeletonPlistRow "Managed plist" "${managedPlistPath}" ""
fi
if [[ -n "${localPlistPath}" || -z "${unknownPlistPath}" ]]; then
    skeletonPlistRow "Local plist" "${localPlistPath}" ""
fi
if [[ -n "${statePlistPath}" ]]; then
    if plistKeyExists "${statePlistPath}" "NextScheduledReminder"; then
        skeletonFileRow "\`dor-state.plist\`" "received" "\`NextScheduledReminder\`: $(redactSensitiveText "$(plistKeyValue "${statePlistPath}" "NextScheduledReminder")")"
    else
        skeletonFileRow "\`dor-state.plist\`" "received" "\`NextScheduledReminder\`: absent (starter may launch)"
    fi
else
    skeletonFileRow "\`dor-state.plist\`" "not in upload" "\`NextScheduledReminder\` cannot be reported"
fi
if [[ -n "${fallbackPlistPath}" ]]; then
    skeletonFileRow "\`dor-fallback-declaration.plist\`" "received" "runtime fallback gate: ${fallbackGate}"
else
    skeletonFileRow "\`dor-fallback-declaration.plist\`" "not in upload" "fallback gate cannot be evaluated"
fi
if [[ -n "${persistencePlistPath}" ]]; then
    skeletonFileRow "\`SoftwareUpdateDDMStatePersistence.plist\`" "received" "corroboration: ${ddmStatePersistenceStatus}"
else
    skeletonFileRow "\`SoftwareUpdateDDMStatePersistence.plist\`" "not in upload" "declarations not cross-checked"
fi
if [[ -n "${launchDaemonPlistPath}" ]]; then
    skeletonFileRow "LaunchDaemon plist" "received" "Label: $(plistKeyValue "${launchDaemonPlistPath}" "Label"); StartInterval: $(plistKeyValue "${launchDaemonPlistPath}" "StartInterval")"
else
    skeletonFileRow "LaunchDaemon plist" "not in upload" ""
fi
case "${aggressiveKillState}" in
    yes) skeletonFileRow "\`dor-aggressive-kill\`" "present" "aggressive mode uses the normal cadence until removed" ;;
    no)  skeletonFileRow "\`dor-aggressive-kill\`" "absent" "" ;;
    *)   skeletonFileRow "\`dor-aggressive-kill\`" "unknown" "not reported with the upload" ;;
esac
echo ""

echo "## 3. Identity"
echo ""
echo "| Field | Value |"
echo "|---|---|"
echo "| RDNN | ${skeletonRdnn} |"
echo "| Runtime version | ${skeletonRuntimeVersion} |"
echo "| Deployment version | ${skeletonDeploymentVersion} |"
echo "| Installed macOS | ${skeletonInstalledMacOS} |"
echo "| Checklist match | ${skeletonChecklistMatch} |"
echo ""
if (( ${#identityNotes[@]} == 0 )); then
    echo "- Helper notes: none"
else
    for note in "${identityNotes[@]}"; do
        echo "- Helper note: $(redactSensitiveText "${note}")"
    done
fi
echo ""

echo "## 4. Effective settings"
echo ""
if [[ -n "${unknownPlistPath}" && -z "${managedPlistPath}" && -z "${localPlistPath}" ]]; then
    echo "Precedence: single unlabeled plist -> script defaults (${checklistScriptVersion}). Managed versus local precedence could not be evaluated."
else
    echo "Precedence: Managed Preferences -> Local Preferences -> script defaults (${checklistScriptVersion})."
fi
echo ""
echo "| Plist key | Effective | Source | Flags |"
echo "|---|---|---|---|"
for row in "${preferenceRows[@]}"; do
    IFS='|' read -r colKey colEffective colSource colFlags <<< "${row}"
    echo "| ${colKey} | ${colEffective} | ${colSource} | ${colFlags} |"
done
echo ""
if (( ${#deprecatedPlistKeys[@]} == 0 )); then
    echo "- Deprecated keys: none"
else
    echo "- Deprecated keys: ${(j:; :)deprecatedPlistKeys}; honored only when MinimumDiskFreeGB is not set; support ends in 6.0.0"
fi
if (( ${#unknownPlistKeys[@]} == 0 )); then
    echo "- Unknown keys: none"
else
    echo "- Unknown keys: ${(j:; :)unknownPlistKeys}"
fi
if (( ${#rejectedLocalizedKeys[@]} == 0 )); then
    echo "- Rejected localized keys: none"
else
    echo "- Rejected localized keys: ${(j:; :)rejectedLocalizedKeys}"
fi
echo ""

echo "## 5. DDM evidence (\`install.log\`)"
echo ""
echo "Window: last ${installLogWindowCount} of ${installLogLineCount} line(s) (runtime lookback ${ddmResolverLookbackLines}). Corroboration: ${skeletonCorroboration}."
echo ""
if (( ${#installLogDeclarationSpans[@]} == 0 )); then
    echo "No declaration candidates in the lookback window."
else
    if (( ${#installLogDeclarationSpans[@]} > reportSkeletonSpanLimit )); then
        echo "Showing the last ${reportSkeletonSpanLimit} of ${#installLogDeclarationSpans[@]} declaration spans."
        echo ""
    fi
    echo "| First seen | Last seen | Version | Build | EnforcedInstallDate | Source types | Corroborated |"
    echo "|---|---|---|---|---|---|---|"
    spanTotal="${#installLogDeclarationSpans[@]}"
    for row in "${(@)installLogDeclarationSpans[$(( spanTotal > reportSkeletonSpanLimit ? spanTotal - reportSkeletonSpanLimit + 1 : 1 )),-1]}"; do
        echo "| ${row} |"
    done
fi
echo ""
skeletonMarkerBullet "Invalid declarations" "${installLogInvalidDeclarations[@]}"
skeletonMarkerBullet "No updates found for DDM to enforce" "${installLogNoUpdatesLines[@]}"
skeletonMarkerBullet "Recovery markers" "${installLogRecoveryLines[@]}"
skeletonMarkerBullet "No-match markers" "${installLogNoMatchLines[@]}"
skeletonMarkerBullet "Update Tonight softwareupdated lines" "${installLogTonightLines[@]}"
echo "<!-- agent: optional extra install.log observations as bullets; delete this line if none. -->"
echo ""

echo "## 6. Client-log runs"
echo ""
echo "| Started | Script | Resolver result | Outcome |"
echo "|---|---|---|---|"
if (( runHistoryTotal == 0 )); then
    echo "| n/a | n/a | no runtime run in client log | n/a |"
else
    for row in "${runHistoryRows[@]}"; do
        IFS=$'\t' read -r runStart runScript runStatus runOutcome <<< "${row}"
        [[ "${runStatus}" == "no resolver line" ]] || runStatus="\`${runStatus}\`"
        echo "| ${runStart} | \`${runScript}\` | ${runStatus} | $(escapeTableCell "$(redactSensitiveText "${runOutcome}")") |"
    done
fi
echo ""
if (( runHistoryTotal > 0 )); then
    echo "Showing the last ${#runHistoryRows[@]} of ${runHistoryTotal} runtime run(s)."
    echo ""
    echo "Last run (${${runHistoryRows[-1]}%%$'\t'*}):"
else
    echo "Last run: no runtime \`Initiating\` line; lines below come from the entire client log."
fi
echo ""
if (( ${#latestRunDecisionLines[@]} == 0 )); then
    echo "No decision-related lines in the latest run."
else
    echo '```text'
    for logLine in "${latestRunDecisionLines[@]}"; do
        echo "$(redactSensitiveText "${logLine}")"
    done
    echo '```'
fi
echo ""
if (( unprefixedLineCount == 0 )); then
    echo "- Lines without a DDM OS Reminder prefix: none"
else
    unprefixedTopLine="$(redactSensitiveText "${unprefixedTopLine}")"
    echo "- Lines without a DDM OS Reminder prefix: ${unprefixedLineCount}; most frequent (${unprefixedTopCount}x): \`${unprefixedTopLine//\`/}\`"
fi
echo ""

echo "## 7. Do the client log and \`install.log\` agree?"
echo ""
echo "<!-- agent: start with **Yes.**, **No.**, or **Not comparable.**, then up to three sentences. If they disagree, quote both. -->"
echo ""

echo "## 8. Likely cause and next steps"
echo ""
echo "### Likely cause"
echo ""
echo "<!-- agent: one short paragraph; mark inferences as inferences. -->"
echo ""
echo "### Next steps"
echo ""
echo "<!-- agent: numbered list; read-only checks first, each ending with (read-only). -->"
echo ""

echo "## 9. Redaction"
echo ""
echo "This report is redacted: usernames, first names, \`/Users\` paths, \`install.log\` computer names, and labeled serial numbers are removed. Keep the raw uploads and the helper fact sheet out of any public issue."
echo "<!-- report-skeleton:end -->"
