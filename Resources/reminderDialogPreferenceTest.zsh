#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Declarative Device Management macOS Reminder: Preference Preview
#
# This standalone preview script reads DDM OS Reminder preferences, resolves
# localized dialog content, and displays the standard reminder dialog using
# preview runtime values so Mac Admins can validate Configuration Profile
# deployment.
#
# Usage:
#   zsh Resources/reminderDialogPreferenceTest.zsh
#   zsh Resources/reminderDialogPreferenceTest.zsh --rdnn org.churchofjesuschrist
#
# Notes:
# - To test another language, set `LanguageOverride` in the target preference
#   domain (for example: `defaults write /Library/Preferences/org.churchofjesuschrist.dorm
#   LanguageOverride -string "de"`), then re-run this script.
# - This script previews dialog appearance only. It intentionally omits DDM log
#   parsing, LaunchDaemon behavior, meeting-aware delays, and enforcement logic.
#
# http://snelson.us/ddm
#
####################################################################################################



####################################################################################################
#
# Argument Parsing
#
####################################################################################################

cliReverseDomainNameNotation=""

while [[ "$#" -gt 0 ]]; do
    case "${1}" in
        --rdnn)
            if [[ -z "${2:-}" ]]; then
                echo "Usage: zsh Resources/reminderDialogPreferenceTest.zsh [--rdnn <value>]"
                exit 64
            fi

            cliReverseDomainNameNotation="${2}"
            shift 2
            ;;
        *)
            echo "Usage: zsh Resources/reminderDialogPreferenceTest.zsh [--rdnn <value>]"
            exit 64
            ;;
    esac
done



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

scriptVersion="3.2.0b2"
humanReadableScriptName="DDM OS Reminder Preference Preview"
errorCount=0

autoload -Uz is-at-least

typeset -ga temporaryFiles=()
declare -A preferenceExplicitlySet=()

foundManagedPreferences="false"
foundLocalPreferences="false"
dialogLanguage="en"
dialogSupportsMarkdownColor="NO"
hideSecondaryButton="NO"
blurscreen="--noblurscreen"
updateOrUpgradeMode="update"
updateStagingStatus="Fully staged"
requestedAppearanceMode=""



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

reverseDomainNameNotation="${cliReverseDomainNameNotation:-org.churchofjesuschrist}"
organizationScriptName="dorm"

# Preference plist domains
preferenceDomain="${reverseDomainNameNotation}.${organizationScriptName}"
managedPreferencesPlist="/Library/Managed Preferences/${preferenceDomain}"
localPreferencesPlist="/Library/Preferences/${preferenceDomain}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Preference Configuration Map
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

declare -A preferenceConfiguration=(
    ["daysOfExcessiveUptimeWarning"]="numeric|0"
    ["minimumDiskFreePercentage"]="numeric|99"
    ["organizationOverlayiconURL"]="string|https://use2.ics.services.jamfcloud.com/icon/hash_2d64ce7f0042ad68234a2515211adb067ad6714703dd8ebd6f33c1ab30354b1d"
    ["organizationOverlayiconURLdark"]="string|https://use2.ics.services.jamfcloud.com/icon/hash_d3a3bc5e06d2db5f9697f9b4fa095bfecb2dc0d22c71aadea525eb38ff981d39"
    ["swapOverlayAndLogo"]="boolean|NO"
    ["dateFormatDeadlineHumanReadable"]="string|+%a, %d-%b-%Y, %-l:%M %p"
    ["supportTeamName"]="string|IT Support"
    ["supportTeamPhone"]="string|+1 (801) 555-1212"
    ["supportTeamEmail"]="string|rescue@domain.org"
    ["supportTeamWebsite"]="string|https://support.domain.org"
    ["supportKB"]="string|Update macOS on Mac"
    ["infobuttonaction"]="string|https://support.apple.com/108382"
    ["supportKBURL"]="string|[Update macOS on Mac](https://support.apple.com/108382)"
    ["supportAssistanceMessage"]="string|<br><br>For assistance, please contact **{supportTeamName}** by clicking the (?) button in the bottom, right-hand corner."
    ["languageOverride"]="string|auto"
    ["title"]="string|macOS {titleMessageUpdateOrUpgrade} Required"
    ["button1text"]="string|Open Software Update"
    ["button2text"]="string|Remind Me Later"
    ["infobuttontext"]="string|Update macOS on Mac"
    ["excessiveUptimeWarningMessage"]="string|<br><br>**Note:** Your Mac has been powered-on for **{uptimeHumanReadable}**. For more reliable results, please manually restart your Mac before proceeding."
    ["diskSpaceWarningMessage"]="string|<br><br>**Note:** Your Mac has only **{diskSpaceHumanReadable}**, which may prevent this macOS {titleMessageUpdateOrUpgrade:l}."
    ["stagedUpdateMessage"]="string|<br><br>**Good news!** The macOS {ddmVersionString} update has already been downloaded to your Mac and is ready to install. Installation will proceed quickly when you click **{button1text}**."
    ["partiallyStagedUpdateMessage"]="string|<br><br>Your Mac has begun downloading and preparing required macOS update components. Installation will be quicker once all assets have finished staging."
    ["pendingDownloadMessage"]="string|<br><br>Your Mac will begin downloading the update shortly."
    ["hideStagedInfo"]="boolean|NO"
    ["relativeDeadlineToday"]="string|Today"
    ["relativeDeadlineTomorrow"]="string|Tomorrow"
    ["updateWord"]="string|Update"
    ["upgradeWord"]="string|Upgrade"
    ["softwareUpdateButtonTextUpdate"]="string|Restart Now"
    ["softwareUpdateButtonTextUpgrade"]="string|Upgrade Now"
    ["restartNowButtonText"]="string|Restart Now"
    ["infoboxLabelCurrent"]="string|Current"
    ["infoboxLabelRequired"]="string|Required"
    ["infoboxLabelDeadline"]="string|Deadline"
    ["infoboxLabelDaysRemaining"]="string|Day(s) Remaining"
    ["infoboxLabelLastRestart"]="string|Last Restart"
    ["infoboxLabelFreeDiskSpace"]="string|Free Disk Space"
    ["deadlineEnforcementMessageAbsolute"]="string|However, your Mac **will automatically restart and {titleMessageUpdateOrUpgrade:l}** on **{deadlineDisplay}** if you have not {titleMessageUpdateOrUpgrade:l}d before the deadline."
    ["deadlineEnforcementMessageRelative"]="string|However, your Mac **will automatically restart and {titleMessageUpdateOrUpgrade:l}** **{deadlineDisplay}** if you have not {titleMessageUpdateOrUpgrade:l}d before the deadline."
    ["message"]="string|**A required macOS {titleMessageUpdateOrUpgrade:l} is now available**<br><br>Happy {weekday}, {loggedInUserFirstname}!<br><br>Please {titleMessageUpdateOrUpgrade:l} to macOS **{ddmVersionString}** to ensure your Mac remains secure and compliant with organizational policies.{updateReadyMessage}<br><br>To perform the {titleMessageUpdateOrUpgrade:l} now, click **{button1text}**, review the on-screen instructions, then click **{softwareUpdateButtonText}**.<br><br>If you are unable to perform this {titleMessageUpdateOrUpgrade:l} now, click **{button2text}** to be reminded again later (which is disabled when the deadline is imminent).<br><br>{deadlineEnforcementMessage}{excessiveUptimeWarningMessage}{diskSpaceWarningMessage}{supportAssistanceMessage}"
    ["infobox"]="string|**{infoboxLabelCurrent}:** macOS {installedmacOSVersion}<br><br>**{infoboxLabelRequired}:** macOS {ddmVersionString}<br><br>**{infoboxLabelDeadline}:** {infoboxDeadlineDisplay}<br><br>**{infoboxLabelDaysRemaining}:** {infoboxDaysRemainingDisplay}<br><br>**{infoboxLabelLastRestart}:** {infoboxLastRestartDisplay}<br><br>**{infoboxLabelFreeDiskSpace}:** {diskSpaceHumanReadable}"
    ["helpmessage"]="string|For assistance, please contact: **{supportTeamName}**<br>- **Telephone:** {supportTeamPhone}<br>- **Email:** {supportTeamEmail}<br>- **Website:** {supportTeamWebsite}<br>- **Knowledge Base Article:** {supportKBURL}<br><br>**User Information:**<br>- **Full Name:** {userfullname}<br>- **User Name:** {username}<br><br>**Computer Information:**<br>- **Computer Name:** {computername}<br>- **Serial Number:** {serialnumber}<br>- **macOS:** {osversion}<br><br>**Script Information:**<br>- **Dialog:** {dialogVersion}<br>- **Script:** {scriptVersion}<br>"
    ["helpimage"]="string|qr={infobuttonaction}"
)

declare -A plistKeyMap=(
    ["daysOfExcessiveUptimeWarning"]="DaysOfExcessiveUptimeWarning"
    ["minimumDiskFreePercentage"]="MinimumDiskFreePercentage"
    ["organizationOverlayiconURL"]="OrganizationOverlayIconURL"
    ["organizationOverlayiconURLdark"]="OrganizationOverlayIconURLdark"
    ["swapOverlayAndLogo"]="SwapOverlayAndLogo"
    ["dateFormatDeadlineHumanReadable"]="DateFormatDeadlineHumanReadable"
    ["supportTeamName"]="SupportTeamName"
    ["supportTeamPhone"]="SupportTeamPhone"
    ["supportTeamEmail"]="SupportTeamEmail"
    ["supportTeamWebsite"]="SupportTeamWebsite"
    ["supportKB"]="SupportKB"
    ["infobuttonaction"]="InfoButtonAction"
    ["supportKBURL"]="SupportKBURL"
    ["supportAssistanceMessage"]="SupportAssistanceMessage"
    ["languageOverride"]="LanguageOverride"
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
    ["message"]="Message"
    ["infobox"]="InfoBox"
    ["helpmessage"]="HelpMessage"
    ["helpimage"]="HelpImage"
)



####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Console Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateConsoleLog() {
    echo "${organizationScriptName} (${scriptVersion}): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}"
}

function preFlight()    { updateConsoleLog "[PRE-FLIGHT]      ${1}"; }
function notice()       { updateConsoleLog "[NOTICE]          ${1}"; }
function info()         { updateConsoleLog "[INFO]            ${1}"; }
function warning()      { updateConsoleLog "[WARNING]         ${1}"; let errorCount++; }
function error()        { updateConsoleLog "[ERROR]           ${1}"; let errorCount++; }
function fatal()        { updateConsoleLog "[FATAL ERROR]     ${1}"; exit 1; }



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Cleanup
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function cleanupTemporaryFiles() {
    local filePath=""

    for filePath in "${temporaryFiles[@]}"; do
        [[ -n "${filePath}" && -e "${filePath}" ]] && rm -f "${filePath}"
    done
}

trap cleanupTemporaryFiles EXIT



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Preference Utilities
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function plistFileIsReadable() {
    local plistPath="${1}"

    [[ -f "${plistPath}" ]] || return 1

    /usr/bin/plutil -lint "${plistPath}" >/dev/null 2>&1
}

function readPlistValue() {
    local plistPath="${1}"
    local plistKey="${2}"
    local plistValue=""

    plistValue=$(/usr/libexec/PlistBuddy -c "Print :${plistKey}" "${plistPath}" 2>/dev/null)
    echo "${plistValue}"
}

function currentConsoleUser() {
    echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }'
}

function resolveEffectiveUserContext() {
    local currentUser="$(id -un 2>/dev/null)"
    local consoleUser="$(currentConsoleUser)"

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        loggedInUser="${SUDO_USER}"
        notice "Running with sudo; resolving language and appearance for '${loggedInUser}'."
    elif [[ -n "${currentUser}" && "${currentUser}" != "root" ]]; then
        loggedInUser="${currentUser}"
    elif [[ -n "${consoleUser}" && "${consoleUser}" != "loginwindow" && "${consoleUser}" != "root" ]]; then
        loggedInUser="${consoleUser}"
    else
        fatal "Unable to determine a non-root user context for preview."
    fi

    if ! id "${loggedInUser}" >/dev/null 2>&1; then
        fatal "Resolved user '${loggedInUser}' does not exist on this Mac."
    fi

    loggedInUserID=$(id -u "${loggedInUser}" 2>/dev/null)
    loggedInUserFullname=$(id -F "${loggedInUser}" 2>/dev/null)
    [[ -z "${loggedInUserFullname}" ]] && loggedInUserFullname="${loggedInUser}"

    loggedInUserFirstname=$(echo "${loggedInUserFullname}" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}')
    [[ -z "${loggedInUserFirstname}" ]] && loggedInUserFirstname="${loggedInUser}"

    loggedInUserHomeDirectory=$(dscl . read "/Users/${loggedInUser}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    [[ -z "${loggedInUserHomeDirectory}" && "${USER:-}" == "${loggedInUser}" ]] && loggedInUserHomeDirectory="${HOME}"

    preFlight "Effective user: ${loggedInUser} (${loggedInUserID})"
    preFlight "Effective user home: ${loggedInUserHomeDirectory}"
}

function normalizeBooleanValue() {
    local value="${1}"

    case "${value:l}" in
        1|true|yes) echo "YES" ;;
        0|false|no) echo "NO" ;;
        *)          echo "" ;;
    esac
}

function loadDefaultPreferences() {
    local prefKey=""

    preferenceExplicitlySet=()

    for prefKey in "${(@k)preferenceConfiguration}"; do
        local prefConfig="${preferenceConfiguration[$prefKey]}"
        local defaultValue="${prefConfig#*|}"
        printf -v "${prefKey}" '%s' "${defaultValue}"
    done
}

function internalPreferenceKeyForPlistKey() {
    local plistKey="${1}"
    local prefKey=""

    for prefKey in "${(@k)preferenceConfiguration}"; do
        if [[ "${plistKeyMap[$prefKey]:-$prefKey}" == "${plistKey}" ]]; then
            echo "${prefKey}"
            return 0
        fi
    done

    return 1
}

function isKnownPreferencePlistKey() {
    internalPreferenceKeyForPlistKey "${1}" >/dev/null 2>&1
}

function setNumericPreferenceValue() {
    local targetVariable="${1}"
    local rawValue="${2}"

    if [[ "${rawValue}" =~ ^[0-9]+$ ]] && (( rawValue >= 0 && rawValue <= 999 )); then
        printf -v "${targetVariable}" '%s' "${rawValue}"
        preferenceExplicitlySet["${targetVariable}"]="true"
    else
        warning "Ignoring invalid numeric value '${rawValue}' for '${targetVariable}'; keeping default '${(P)targetVariable}'."
    fi
}

function setBooleanPreferenceValue() {
    local targetVariable="${1}"
    local rawValue="${2}"
    local normalizedValue=""

    normalizedValue="$(normalizeBooleanValue "${rawValue}")"
    if [[ -n "${normalizedValue}" ]]; then
        printf -v "${targetVariable}" '%s' "${normalizedValue}"
        preferenceExplicitlySet["${targetVariable}"]="true"
    else
        warning "Ignoring invalid boolean value '${rawValue}' for '${targetVariable}'; keeping default '${(P)targetVariable}'."
    fi
}

function setStringPreferenceValue() {
    local targetVariable="${1}"
    local rawValue="${2}"

    printf -v "${targetVariable}" '%s' "${rawValue}"
    preferenceExplicitlySet["${targetVariable}"]="true"
}

function languageSuffixForCode() {
    local code="${1:l}"

    [[ -z "${code}" || "${code}" == "en" ]] && echo "En" && return

    echo "${(C)code}"
}

function loadDynamicLocalizedPreferenceOverridesFromPlist() {
    local plistPath="${1}"
    local rawKey=""
    local -a plistKeys=()

    while IFS= read -r rawKey; do
        [[ -n "${rawKey}" ]] && plistKeys+=("${rawKey}")
    done < <(/usr/libexec/PlistBuddy -c "Print" "${plistPath}" 2>/dev/null | awk '
        /^[[:space:]]+/ && /Localized_/ {
            key=$0
            sub(/^[[:space:]]+/, "", key)
            sub(/ =.*/, "", key)
            print key
        }
    ')

    for rawKey in "${plistKeys[@]}"; do
        local baseRaw="${rawKey%%Localized_*}"
        local codePart="${rawKey##*Localized_}"
        local internalBase=""
        local internalSuffix=""
        local internalKey=""
        local dynamicValue=""

        [[ -z "${baseRaw}" || -z "${codePart}" ]] && continue

        if internalBase="$(internalPreferenceKeyForPlistKey "${baseRaw}")"; then
            :
        else
            internalBase="${baseRaw:0:1:l}${baseRaw:1}"
        fi

        internalSuffix="$(languageSuffixForCode "${codePart}")"
        internalKey="${internalBase}Localized${internalSuffix}"
        dynamicValue="$(readPlistValue "${plistPath}" "${rawKey}")"

        printf -v "${internalKey}" '%s' "${dynamicValue}"
        preferenceExplicitlySet["${internalKey}"]="true"
    done
}

function loadPreferenceOverrides() {
    local prefKey=""

    loadDefaultPreferences

    if plistFileIsReadable "${managedPreferencesPlist}.plist"; then
        foundManagedPreferences="true"
        preFlight "Reading managed preferences from '${managedPreferencesPlist}.plist'"
    elif [[ -f "${managedPreferencesPlist}.plist" ]]; then
        warning "Managed preferences plist exists but failed validation: ${managedPreferencesPlist}.plist"
    fi

    if plistFileIsReadable "${localPreferencesPlist}.plist"; then
        foundLocalPreferences="true"
        preFlight "Reading local preferences from '${localPreferencesPlist}.plist'"
    elif [[ -f "${localPreferencesPlist}.plist" ]]; then
        warning "Local preferences plist exists but failed validation: ${localPreferencesPlist}.plist"
    fi

    if [[ "${foundManagedPreferences}" == "false" && "${foundLocalPreferences}" == "false" ]]; then
        warning "No valid preference plist found for domain '${preferenceDomain}'."
        return 1
    fi

    for prefKey in "${(@k)preferenceConfiguration}"; do
        local prefConfig="${preferenceConfiguration[$prefKey]}"
        local prefType="${prefConfig%%|*}"
        local plistKey="${plistKeyMap[$prefKey]:-$prefKey}"
        local sourcePlist=""
        local rawValue=""

        if [[ "${foundManagedPreferences}" == "true" ]] && /usr/libexec/PlistBuddy -c "Print :${plistKey}" "${managedPreferencesPlist}.plist" >/dev/null 2>&1; then
            sourcePlist="${managedPreferencesPlist}.plist"
        elif [[ "${foundLocalPreferences}" == "true" ]] && /usr/libexec/PlistBuddy -c "Print :${plistKey}" "${localPreferencesPlist}.plist" >/dev/null 2>&1; then
            sourcePlist="${localPreferencesPlist}.plist"
        else
            continue
        fi

        rawValue="$(readPlistValue "${sourcePlist}" "${plistKey}")"

        case "${prefType}" in
            numeric)
                setNumericPreferenceValue "${prefKey}" "${rawValue}"
                ;;
            boolean)
                setBooleanPreferenceValue "${prefKey}" "${rawValue}"
                ;;
            string|*)
                setStringPreferenceValue "${prefKey}" "${rawValue}"
                ;;
        esac
    done

    if [[ "${foundLocalPreferences}" == "true" ]]; then
        loadDynamicLocalizedPreferenceOverridesFromPlist "${localPreferencesPlist}.plist"
    fi

    if [[ "${foundManagedPreferences}" == "true" ]]; then
        loadDynamicLocalizedPreferenceOverridesFromPlist "${managedPreferencesPlist}.plist"
    fi

    [[ -n "${dateFormatDeadlineHumanReadable}" && "${dateFormatDeadlineHumanReadable}" != +* ]] && dateFormatDeadlineHumanReadable="+${dateFormatDeadlineHumanReadable}"

    preFlight "Preferences loaded"
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Localization and Date Formatting
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function localeForDialogLanguageCode() {
    local languageCode="${1:l}"
    local discoveredLocale=""

    discoveredLocale=$(locale -a 2>/dev/null | awk -v code="${languageCode}" '
        BEGIN { IGNORECASE = 1 }
        {
            localeLower = tolower($0)
            if (localeLower ~ ("^" code "(_[^[:space:]]+)?(\\.utf-?8)?$")) {
                print $0
                exit
            }
        }
    ')

    if [[ -n "${discoveredLocale}" ]]; then
        echo "${discoveredLocale}"
        return
    fi

    case "${languageCode}" in
        de) echo "de_DE.UTF-8" ;;
        en) echo "en_US.UTF-8" ;;
        es) echo "es_ES.UTF-8" ;;
        fr) echo "fr_FR.UTF-8" ;;
        it) echo "it_IT.UTF-8" ;;
        ja) echo "ja_JP.UTF-8" ;;
        nl) echo "nl_NL.UTF-8" ;;
        pt) echo "pt_PT.UTF-8" ;;
        *)  echo "" ;;
    esac
}

function formatDateWithDialogLocale() {
    local inputFormat="${1}"
    local inputValue="${2}"
    local outputFormat="${3}"
    local localeForDate=""
    local formattedDate=""

    localeForDate="$(localeForDialogLanguageCode "${dialogLanguage}")"

    if [[ -n "${localeForDate}" ]]; then
        formattedDate=$(LC_TIME="${localeForDate}" date -jf "${inputFormat}" "${inputValue}" "${outputFormat}" 2>/dev/null)
    fi

    if [[ -z "${formattedDate}" ]]; then
        formattedDate=$(date -jf "${inputFormat}" "${inputValue}" "${outputFormat}" 2>/dev/null)
    fi

    echo "${formattedDate}"
}

function trimSurroundingWhitespace() {
    local value="${1}"

    value=$(printf '%s' "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    echo "${value}"
}

function formatDeadlineFromEpoch() {
    local sourceEpoch="${1}"
    local requestedFormat="${2}"
    local formattedDeadline=""

    formattedDeadline=$(formatDateWithDialogLocale "%s" "${sourceEpoch}" "${requestedFormat}")
    if [[ -z "${formattedDeadline}" ]]; then
        formattedDeadline=$(formatDateWithDialogLocale "%s" "${sourceEpoch}" "+%a, %d-%b-%Y, %-l:%M %p")
    fi

    formattedDeadline="$(trimSurroundingWhitespace "${formattedDeadline}")"
    echo "${formattedDeadline}"
}

function formatTimeHumanReadableFromEpoch() {
    local targetEpoch="${1}"
    local timeHumanReadable=""

    if [[ -z "${targetEpoch}" ]] || ! [[ "${targetEpoch}" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    timeHumanReadable=$(formatDateWithDialogLocale "%s" "${targetEpoch}" "+%-l:%M %p")
    [[ -z "${timeHumanReadable}" ]] && return 1

    timeHumanReadable=${timeHumanReadable// AM/ a.m.}
    timeHumanReadable=${timeHumanReadable// PM/ p.m.}
    timeHumanReadable="$(trimSurroundingWhitespace "${timeHumanReadable}")"
    echo "${timeHumanReadable}"
}

function formatRelativeDeadlineHumanReadable() {
    local targetEpoch="${1}"
    local absoluteFallback="${2}"
    local targetDate=""
    local todayDate=""
    local tomorrowDate=""
    local targetTime=""
    local relativeDeadlineHumanReadable=""

    if [[ -n "${targetEpoch}" && "${targetEpoch}" =~ ^[0-9]+$ ]]; then
        targetDate=$(date -jf "%s" "${targetEpoch}" "+%Y-%m-%d" 2>/dev/null)
        todayDate=$(date "+%Y-%m-%d")
        tomorrowDate=$(date -v+1d "+%Y-%m-%d")
        targetTime=$(formatTimeHumanReadableFromEpoch "${targetEpoch}" 2>/dev/null)

        if [[ -n "${targetDate}" && -n "${targetTime}" ]]; then
            if [[ "${targetDate}" == "${todayDate}" ]]; then
                relativeDeadlineHumanReadable="${relativeDeadlineToday}, ${targetTime}"
            elif [[ "${targetDate}" == "${tomorrowDate}" ]]; then
                relativeDeadlineHumanReadable="${relativeDeadlineTomorrow}, ${targetTime}"
            fi
        fi
    fi

    [[ -z "${relativeDeadlineHumanReadable}" ]] && relativeDeadlineHumanReadable="${absoluteFallback}"
    relativeDeadlineHumanReadable="$(trimSurroundingWhitespace "${relativeDeadlineHumanReadable}")"
    echo "${relativeDeadlineHumanReadable}"
}

function detectLoggedInUserLanguageCode() {
    local globalPreferencesPath="${loggedInUserHomeDirectory}/Library/Preferences/.GlobalPreferences.plist"
    local detectedLanguage=""

    if [[ -r "${globalPreferencesPath}" ]]; then
        detectedLanguage=$(/usr/libexec/PlistBuddy -c "Print :AppleLanguages:0" "${globalPreferencesPath}" 2>/dev/null)
    fi

    echo "${detectedLanguage}"
}

function normalizeDialogLanguageCode() {
    local languageCode="${1:l}"
    local sentinelKey=""

    languageCode="${languageCode#\"}"
    languageCode="${languageCode%\"}"
    languageCode="${languageCode#\'}"
    languageCode="${languageCode%\'}"
    languageCode="${languageCode%%-*}"
    languageCode="${languageCode%%_*}"

    [[ "${languageCode}" == "en" ]] && echo "en" && return

    sentinelKey="TitleLocalized_${languageCode}"
    if [[ "${foundManagedPreferences}" == "true" ]] && /usr/libexec/PlistBuddy -c "Print :${sentinelKey}" "${managedPreferencesPlist}.plist" >/dev/null 2>&1; then
        echo "${languageCode}"
        return
    fi

    if [[ "${foundLocalPreferences}" == "true" ]] && /usr/libexec/PlistBuddy -c "Print :${sentinelKey}" "${localPreferencesPlist}.plist" >/dev/null 2>&1; then
        echo "${languageCode}"
        return
    fi

    echo "en"
}

function localizedWeekdayName() {
    local languageCode="${1}"
    local localeForWeekday=""
    local localizedWeekday=""

    localeForWeekday="$(localeForDialogLanguageCode "${languageCode}")"
    if [[ -n "${localeForWeekday}" ]]; then
        localizedWeekday=$(LC_TIME="${localeForWeekday}" date "+%A" 2>/dev/null)
    fi

    [[ -z "${localizedWeekday}" ]] && localizedWeekday=$(date "+%A")
    echo "${localizedWeekday}"
}

function localizedDurationSeparator() {
    case "${dialogLanguage}" in
        ja) echo "、" ;;
        *)  echo ", " ;;
    esac
}

function localizedDurationComponent() {
    local quantity="${1}"
    local unit="${2}"
    local localizedComponent=""

    case "${dialogLanguage}" in
        de)
            case "${unit}" in
                day)    localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "Tag" || echo "Tage")" ;;
                hour)   localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "Stunde" || echo "Stunden")" ;;
                minute) localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "Minute" || echo "Minuten")" ;;
            esac
            ;;
        es)
            case "${unit}" in
                day)    localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "día" || echo "días")" ;;
                hour)   localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "hora" || echo "horas")" ;;
                minute) localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "minuto" || echo "minutos")" ;;
            esac
            ;;
        fr)
            case "${unit}" in
                day)    localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "jour" || echo "jours")" ;;
                hour)   localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "heure" || echo "heures")" ;;
                minute) localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "minute" || echo "minutes")" ;;
            esac
            ;;
        it)
            case "${unit}" in
                day)    localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "giorno" || echo "giorni")" ;;
                hour)   localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "ora" || echo "ore")" ;;
                minute) localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "minuto" || echo "minuti")" ;;
            esac
            ;;
        ja)
            case "${unit}" in
                day)    localizedComponent="${quantity}日" ;;
                hour)   localizedComponent="${quantity}時間" ;;
                minute) localizedComponent="${quantity}分" ;;
            esac
            ;;
        nl)
            case "${unit}" in
                day)    localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "dag" || echo "dagen")" ;;
                hour)   localizedComponent="${quantity} uur" ;;
                minute) localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "minuut" || echo "minuten")" ;;
            esac
            ;;
        pt)
            case "${unit}" in
                day)    localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "dia" || echo "dias")" ;;
                hour)   localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "hora" || echo "horas")" ;;
                minute) localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "minuto" || echo "minutos")" ;;
            esac
            ;;
        en|*)
            case "${unit}" in
                day)    localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "day" || echo "days")" ;;
                hour)   localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "hour" || echo "hours")" ;;
                minute) localizedComponent="${quantity} $([[ "${quantity}" -eq 1 ]] && echo "minute" || echo "minutes")" ;;
            esac
            ;;
    esac

    echo "${localizedComponent}"
}

function localizedLessThanOneMinute() {
    case "${dialogLanguage}" in
        de) echo "weniger als 1 Minute" ;;
        es) echo "menos de 1 minuto" ;;
        fr) echo "moins d'une minute" ;;
        it) echo "meno di 1 minuto" ;;
        ja) echo "1分未満" ;;
        nl) echo "minder dan 1 minuut" ;;
        pt) echo "menos de 1 minuto" ;;
        en|*) echo "less than 1 minute" ;;
    esac
}

function localizedDiskAvailabilitySuffix() {
    local percentage="${1}"

    case "${dialogLanguage}" in
        de) echo "(${percentage}% verfügbar)" ;;
        es) echo "(${percentage}% disponible)" ;;
        fr) echo "(${percentage}% disponibles)" ;;
        it) echo "(${percentage}% disponibile)" ;;
        ja) echo "(${percentage}% 利用可能)" ;;
        nl) echo "(${percentage}% beschikbaar)" ;;
        pt) echo "(${percentage}% disponível)" ;;
        en|*) echo "(${percentage}% available)" ;;
    esac
}

function refreshLocalizedRuntimeFacts() {
    local separator=""
    local component=""
    local -a durationComponents=()

    if [[ "${upTimeDays:-0}" =~ ^[0-9]+$ ]] && (( upTimeDays > 0 )); then
        durationComponents+=( "$(localizedDurationComponent "${upTimeDays}" day)" )
    fi

    if [[ "${upTimeHoursRemainder:-0}" =~ ^[0-9]+$ ]] && (( upTimeHoursRemainder > 0 )); then
        durationComponents+=( "$(localizedDurationComponent "${upTimeHoursRemainder}" hour)" )
    fi

    if [[ "${upTimeMinutesRemainder:-0}" =~ ^[0-9]+$ ]] && (( upTimeMinutesRemainder > 0 )); then
        durationComponents+=( "$(localizedDurationComponent "${upTimeMinutesRemainder}" minute)" )
    fi

    if (( ${#durationComponents[@]} > 0 )); then
        separator="$(localizedDurationSeparator)"
        uptimeHumanReadable=""

        for component in "${durationComponents[@]}"; do
            if [[ -n "${uptimeHumanReadable}" ]]; then
                uptimeHumanReadable="${uptimeHumanReadable}${separator}"
            fi

            uptimeHumanReadable="${uptimeHumanReadable}${component}"
        done
    else
        uptimeHumanReadable="$(localizedLessThanOneMinute)"
    fi

    if [[ -n "${freeSpace:-}" && -n "${freePercentage:-}" && "${freePercentage}" != "Unknown" ]]; then
        diskSpaceHumanReadable="${freeSpace} $(localizedDiskAvailabilitySuffix "${freePercentage}")"
    else
        diskSpaceHumanReadable="${freeSpace:-Unknown}"
    fi
}

function resolveDialogLanguage() {
    local normalizedOverride=""
    local detectedLanguage=""

    if [[ -n "${languageOverride}" && "${languageOverride:l}" != "auto" ]]; then
        normalizedOverride="$(normalizeDialogLanguageCode "${languageOverride}")"
        dialogLanguage="${normalizedOverride}"
        notice "LanguageOverride is '${languageOverride}'; using '${dialogLanguage}'"
        return
    fi

    detectedLanguage="$(detectLoggedInUserLanguageCode)"
    if [[ -z "${detectedLanguage}" ]]; then
        dialogLanguage="en"
        notice "Could not detect logged-in user language; defaulting to '${dialogLanguage}'"
        return
    fi

    dialogLanguage="$(normalizeDialogLanguageCode "${detectedLanguage}")"
    notice "Detected logged-in user language '${detectedLanguage}'; using '${dialogLanguage}'"
}

function applyLocalizedFieldValue() {
    local baseVariable="${1}"
    local languageCode="${2}"
    local localizedSuffix=""
    local localizedVariable=""
    local localizedValue=""

    localizedSuffix="$(languageSuffixForCode "${languageCode}")"
    localizedVariable="${baseVariable}Localized${localizedSuffix}"
    localizedValue="${(P)localizedVariable}"

    if [[ "${preferenceExplicitlySet[${localizedVariable}]}" == "true" ]]; then
        printf -v "${baseVariable}" '%s' "${localizedValue}"
        return
    fi

    if [[ "${preferenceExplicitlySet[${baseVariable}]}" == "true" ]]; then
        return
    fi

    [[ -n "${localizedValue}" ]] && printf -v "${baseVariable}" '%s' "${localizedValue}"
}

function initializeLocalizedRuntimeFields() {
    local runtimeField=""
    local runtimeFields=("relativeDeadlineToday" "relativeDeadlineTomorrow")

    for runtimeField in "${runtimeFields[@]}"; do
        applyLocalizedFieldValue "${runtimeField}" "${dialogLanguage}"
    done
}

function applyLocalizedDialogText() {
    local localizedField=""
    local localizedFields=(
        "title" "button1text" "button2text" "infobuttontext"
        "message" "helpmessage"
        "excessiveUptimeWarningMessage" "diskSpaceWarningMessage"
        "stagedUpdateMessage" "partiallyStagedUpdateMessage" "pendingDownloadMessage"
        "supportAssistanceMessage"
        "updateWord" "upgradeWord"
        "softwareUpdateButtonTextUpdate" "softwareUpdateButtonTextUpgrade" "restartNowButtonText"
        "infoboxLabelCurrent" "infoboxLabelRequired" "infoboxLabelDeadline"
        "infoboxLabelDaysRemaining" "infoboxLabelLastRestart" "infoboxLabelFreeDiskSpace"
        "deadlineEnforcementMessageAbsolute" "deadlineEnforcementMessageRelative"
    )

    for localizedField in "${localizedFields[@]}"; do
        applyLocalizedFieldValue "${localizedField}" "${dialogLanguage}"
    done
}

function applyLocalizedUpdateVocabulary() {
    if [[ "${updateOrUpgradeMode:l}" == "upgrade" ]]; then
        titleMessageUpdateOrUpgrade="${upgradeWord}"
        softwareUpdateButtonText="${softwareUpdateButtonTextUpgrade}"
    else
        titleMessageUpdateOrUpgrade="${updateWord}"
        softwareUpdateButtonText="${softwareUpdateButtonTextUpdate}"
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Local Runtime Facts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function collectUptimeFacts() {
    local lastBootTime=""
    local currentTime=""

    lastBootTime=$(sysctl kern.boottime | awk -F'[ |,]' '{print $5}')
    currentTime=$(date +"%s")
    upTimeRaw=$(( currentTime - lastBootTime ))
    upTimeMin=$(( upTimeRaw / 60 ))
    upTimeDays=$(( upTimeMin / 1440 ))
    upTimeHoursRemainder=$(( (upTimeMin % 1440) / 60 ))
    upTimeMinutesRemainder=$(( upTimeMin % 60 ))
    uptimeHumanReadable=""

    if [[ "${upTimeDays}" -gt 0 ]]; then
        if [[ "${upTimeDays}" -eq 1 ]]; then
            uptimeHumanReadable="1 day"
        else
            uptimeHumanReadable="${upTimeDays} days"
        fi
    fi

    if [[ "${upTimeHoursRemainder}" -gt 0 ]]; then
        [[ -n "${uptimeHumanReadable}" ]] && uptimeHumanReadable="${uptimeHumanReadable}, "

        if [[ "${upTimeHoursRemainder}" -eq 1 ]]; then
            uptimeHumanReadable="${uptimeHumanReadable}1 hour"
        else
            uptimeHumanReadable="${uptimeHumanReadable}${upTimeHoursRemainder} hours"
        fi
    fi

    if [[ "${upTimeMinutesRemainder}" -gt 0 ]]; then
        [[ -n "${uptimeHumanReadable}" ]] && uptimeHumanReadable="${uptimeHumanReadable}, "

        if [[ "${upTimeMinutesRemainder}" -eq 1 ]]; then
            uptimeHumanReadable="${uptimeHumanReadable}1 minute"
        else
            uptimeHumanReadable="${uptimeHumanReadable}${upTimeMinutesRemainder} minutes"
        fi
    fi

    [[ -z "${uptimeHumanReadable}" ]] && uptimeHumanReadable="less than 1 minute"
}

function collectDiskFacts() {
    local diskRawValues=""
    local freeBytes=""
    local diskBytes=""

    diskRawValues=$(osascript -l JavaScript -e "ObjC.import('Foundation'); var url = \$.NSURL.fileURLWithPath('/'); var result = url.resourceValuesForKeysError(['NSURLVolumeAvailableCapacityForImportantUsageKey','NSURLVolumeTotalCapacityKey'], null); [result.valueForKey('NSURLVolumeAvailableCapacityForImportantUsageKey').js, result.valueForKey('NSURLVolumeTotalCapacityKey').js].join(' ');" 2>/dev/null)
    read freeBytes diskBytes <<< "${diskRawValues}"

    if [[ "${freeBytes}" == <-> && "${diskBytes}" == <-> ]] && (( freeBytes > 0 && diskBytes >= freeBytes )); then
        freeSpace=$(echo "scale=1; ${freeBytes} / 1000000000" | bc)
        freeSpace="${freeSpace} GB"
        freePercentage=$(echo "scale=2; (${freeBytes} * 100) / ${diskBytes}" | bc)
    else
        warning "JXA disk space query returned invalid data; falling back to diskutil. diskBytes=${diskBytes}, freeBytes=${freeBytes}"
        freeSpace=$(diskutil info / | awk -F ': ' '/Free Space|Available Space|Container Free Space/ {print $2}' | awk -F '(' '{print $1}' | xargs)
        diskBytes=$(diskutil info / | awk -F '[()]' '/Total Space/ {print $2}' | awk '{print $1}')
        freeBytes=$(diskutil info / | awk -F '[()]' '/Free Space|Available Space|Container Free Space/ {print $2}' | awk '{print $1}')

        if [[ "${freeBytes}" == <-> && "${diskBytes}" == <-> ]] && (( diskBytes > 0 && diskBytes >= freeBytes )); then
            freePercentage=$(echo "scale=2; (${freeBytes} * 100) / ${diskBytes}" | bc)
        else
            error "Invalid disk space data: diskBytes=${diskBytes}, freeBytes=${freeBytes}"
            freeSpace="Unknown"
            freePercentage="Unknown"
        fi
    fi

    diskSpaceHumanReadable="${freeSpace} (${freePercentage}% available)"
}

function collectMachineFacts() {
    installedmacOSVersion=$(sw_vers -productVersion 2>/dev/null)
    [[ -z "${installedmacOSVersion}" ]] && installedmacOSVersion="Unknown"

    username="${loggedInUser}"
    userfullname="${loggedInUserFullname}"
    osversion="${installedmacOSVersion}"

    computername=$(scutil --get ComputerName 2>/dev/null)
    [[ -z "${computername}" ]] && computername="$(hostname -s 2>/dev/null)"
    [[ -z "${computername}" ]] && computername="Unknown"

    serialnumber=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformSerialNumber/ {print $4; exit}')
    [[ -z "${serialnumber}" ]] && serialnumber="Unknown"
}

function prepareDemoRuntimeState() {
    local installedMajorVersion=""
    local installedMinorVersion="0"
    local installedPatchVersion="0"

    collectUptimeFacts
    collectDiskFacts
    collectMachineFacts

    IFS='.' read -r installedMajorVersion installedMinorVersion installedPatchVersion <<< "${installedmacOSVersion}"
    [[ -z "${installedMajorVersion}" || ! "${installedMajorVersion}" =~ ^[0-9]+$ ]] && installedMajorVersion="15"
    [[ -z "${installedMinorVersion}" || ! "${installedMinorVersion}" =~ ^[0-9]+$ ]] && installedMinorVersion="0"
    [[ -z "${installedPatchVersion}" || ! "${installedPatchVersion}" =~ ^[0-9]+$ ]] && installedPatchVersion="0"

    ddmVersionString="${installedMajorVersion}.${installedMinorVersion}.$(( installedPatchVersion + 1 ))"
    deadlineEpoch=$(date -v+7d +%s)
    ddmEnforcedInstallDateEpoch="${deadlineEpoch}"
    ddmVersionStringDaysRemaining="7"
    ddmEnforcedInstallDateHumanReadable="$(formatDeadlineFromEpoch "${deadlineEpoch}" "${dateFormatDeadlineHumanReadable}")"
    ddmEnforcedInstallDateRelativeHumanReadable="$(formatRelativeDeadlineHumanReadable "${deadlineEpoch}" "${ddmEnforcedInstallDateHumanReadable}")"
    ddmVersionStringDeadlineHumanReadable="${ddmEnforcedInstallDateHumanReadable}"
    versionComparisonResult="Update Required"
    hideSecondaryButton="NO"
    blurscreen="--noblurscreen"
    updateOrUpgradeMode="update"
    updateStagingStatus="Fully staged"

    notice "Prepared demo runtime state: required macOS ${ddmVersionString}, deadline ${ddmEnforcedInstallDateHumanReadable}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Branding and Dialog Preparation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function detectDarkMode() {
    local interfaceStyle=""
    local globalPreferencesPath="${loggedInUserHomeDirectory}/Library/Preferences/.GlobalPreferences.plist"

    interfaceStyle=$(defaults read "${globalPreferencesPath}" AppleInterfaceStyle 2>/dev/null)
    if [[ "${interfaceStyle}" == "Dark" ]]; then
        echo "Dark"
    else
        echo "Light"
    fi
}

function resolveDialogIconValue() {
    local sourceValue="${1}"
    local resolvedValue=""

    if [[ -z "${sourceValue}" ]]; then
        echo ""
        return
    fi

    if [[ -e "${sourceValue}" ]]; then
        resolvedValue="${sourceValue}"
    elif [[ "${sourceValue}" =~ ^file:// ]]; then
        resolvedValue="${sourceValue#file://}"
        if [[ -e "${resolvedValue}" ]]; then
            :
        else
            resolvedValue=""
        fi
    else
        resolvedValue="${sourceValue}"
    fi

    echo "${resolvedValue}"
}

function downloadBrandingAssets() {
    local appearanceMode="$(detectDarkMode)"
    local overlayIconURL="${organizationOverlayiconURL}"
    local majorDDM="${ddmVersionString%%.*}"

    requestedAppearanceMode="${appearanceMode}"

    if [[ "${appearanceMode}" == "Dark" && -n "${organizationOverlayiconURLdark}" ]]; then
        notice "Dark mode detected; using dark mode overlay icon"
        overlayIconURL="${organizationOverlayiconURLdark}"
    else
        notice "${appearanceMode} mode detected; using standard overlay icon"
    fi

    if [[ -n "${overlayIconURL}" ]]; then
        overlayicon="$(resolveDialogIconValue "${overlayIconURL}")"
        if [[ -n "${overlayicon}" ]]; then
            info "Resolved overlay icon: ${overlayicon}"
        else
            warning "Could not resolve overlay icon from '${overlayIconURL}'; using Finder icon."
            overlayicon="/System/Library/CoreServices/Finder.app"
        fi
    else
        overlayicon="/System/Library/CoreServices/Finder.app"
    fi

    case "${majorDDM}" in
        14) macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_eecee9688d1bc0426083d427d80c9ad48fa118b71d8d4962061d4de8d45747e7" ;;
        15) macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_0968afcd54ff99edd98ec6d9a418a5ab0c851576b687756dc3004ec52bac704e" ;;
        26) macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_7320c100c9ca155dc388e143dbc05620907e2d17d6bf74a8fb6d6278ece2c2b4" ;;
        *)  macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_4555d9dc8fecb4e2678faffa8bdcf43cba110e81950e07a4ce3695ec2d5579ee" ;;
    esac

    icon="$(resolveDialogIconValue "${macOSIconURL}")"
    [[ -z "${icon}" ]] && icon="/System/Library/CoreServices/Finder.app"

    if [[ "${swapOverlayAndLogo}" == "YES" ]]; then
        local tmp="${icon}"
        icon="${overlayicon}"
        overlayicon="${tmp}"
        info "SwapOverlayAndLogo enabled; swapped primary and overlay icons."
    fi

    info "Using primary icon: ${icon}"
}

function computeDynamicWarnings() {
    local allowedUptimeMinutes=$(( daysOfExcessiveUptimeWarning * 1440 ))
    local belowThreshold=""

    if (( upTimeMin < allowedUptimeMinutes )); then
        excessiveUptimeWarningMessage=""
    fi

    if [[ "${freePercentage}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        belowThreshold=$(echo "${freePercentage} < ${minimumDiskFreePercentage}" | bc)
        [[ "${belowThreshold}" -ne 1 ]] && diskSpaceWarningMessage=""
    else
        warning "freePercentage '${freePercentage}' is not numeric; suppressing disk-space warning."
        diskSpaceWarningMessage=""
    fi
}

function computeUpdateStagingMessage() {
    if [[ "${hideStagedInfo}" == "YES" ]]; then
        updateReadyMessage=""
        return
    fi

    case "${updateStagingStatus}" in
        "Fully staged")
            updateReadyMessage="${stagedUpdateMessage}"
            ;;
        "Partially staged")
            updateReadyMessage="${partiallyStagedUpdateMessage}"
            ;;
        "Pending download"|"Not detected")
            updateReadyMessage="${pendingDownloadMessage}"
            ;;
        *)
            updateReadyMessage=""
            ;;
    esac
}

function computeDeadlineEnforcementMessage() {
    local markdownColorMinimumVersion="3.0.0.4928"
    local deadlineDisplay="${ddmEnforcedInstallDateRelativeHumanReadable:-${ddmEnforcedInstallDateHumanReadable}}"
    local baseDeadlineEnforcementMessage=""
    local deadlineTemplateVariable="deadlineEnforcementMessageAbsolute"

    deadlineDisplay="$(trimSurroundingWhitespace "${deadlineDisplay}")"

    if [[ "${deadlineDisplay}" != "${ddmEnforcedInstallDateHumanReadable}" ]]; then
        deadlineTemplateVariable="deadlineEnforcementMessageRelative"
    fi

    baseDeadlineEnforcementMessage="${(P)deadlineTemplateVariable}"
    baseDeadlineEnforcementMessage=${baseDeadlineEnforcementMessage//\{deadlineDisplay\}/${deadlineDisplay}}
    baseDeadlineEnforcementMessage=${baseDeadlineEnforcementMessage//\{titleMessageUpdateOrUpgrade:l\}/${titleMessageUpdateOrUpgrade:l}}
    baseDeadlineEnforcementMessage=${baseDeadlineEnforcementMessage//\{titleMessageUpdateOrUpgrade\}/${titleMessageUpdateOrUpgrade}}

    dialogVersion="$(${dialogBinary} -v 2>/dev/null)"

    if [[ -n "${dialogVersion}" ]] && is-at-least "${markdownColorMinimumVersion}" "${dialogVersion}"; then
        dialogSupportsMarkdownColor="YES"
        deadlineEnforcementMessage=":red[${baseDeadlineEnforcementMessage}]"
    else
        dialogSupportsMarkdownColor="NO"
        deadlineEnforcementMessage="${baseDeadlineEnforcementMessage}"
    fi
}

function computeInfoboxHighlights() {
    infoboxDeadlineDisplay="${ddmVersionStringDeadlineHumanReadable}"
    infoboxDaysRemainingDisplay="${ddmVersionStringDaysRemaining}"
    infoboxLastRestartDisplay="${uptimeHumanReadable}"

    infoboxDeadlineDisplay="$(trimSurroundingWhitespace "${infoboxDeadlineDisplay}")"

    if [[ "${dialogSupportsMarkdownColor}" != "YES" ]]; then
        return
    fi

    if (( upTimeMin >= (daysOfExcessiveUptimeWarning * 1440) )); then
        infoboxLastRestartDisplay=":red[${infoboxLastRestartDisplay}]"
    fi
}

function buildPlaceholderMap() {
    declare -gA PLACEHOLDER_MAP=(
        [weekday]="$(localizedWeekdayName "${dialogLanguage}")"
        [userfirstname]="${loggedInUserFirstname}"
        [loggedInUserFirstname]="${loggedInUserFirstname}"
        [userfullname]="${userfullname}"
        [username]="${username}"
        [computername]="${computername}"
        [serialnumber]="${serialnumber}"
        [osversion]="${osversion}"
        [ddmVersionString]="${ddmVersionString}"
        [ddmEnforcedInstallDateHumanReadable]="${ddmEnforcedInstallDateHumanReadable}"
        [ddmEnforcedInstallDateRelativeHumanReadable]="${ddmEnforcedInstallDateRelativeHumanReadable}"
        [installedmacOSVersion]="${installedmacOSVersion}"
        [ddmVersionStringDeadlineHumanReadable]="${ddmVersionStringDeadlineHumanReadable}"
        [ddmVersionStringDaysRemaining]="${ddmVersionStringDaysRemaining}"
        [infoboxDeadlineDisplay]="${infoboxDeadlineDisplay}"
        [infoboxDaysRemainingDisplay]="${infoboxDaysRemainingDisplay}"
        [infoboxLastRestartDisplay]="${infoboxLastRestartDisplay}"
        [titleMessageUpdateOrUpgrade]="${titleMessageUpdateOrUpgrade}"
        [uptimeHumanReadable]="${uptimeHumanReadable}"
        [excessiveUptimeWarningMessage]="${excessiveUptimeWarningMessage}"
        [updateReadyMessage]="${updateReadyMessage}"
        [diskSpaceHumanReadable]="${diskSpaceHumanReadable}"
        [diskSpaceWarningMessage]="${diskSpaceWarningMessage}"
        [softwareUpdateButtonText]="${softwareUpdateButtonText}"
        [infoboxLabelCurrent]="${infoboxLabelCurrent}"
        [infoboxLabelRequired]="${infoboxLabelRequired}"
        [infoboxLabelDeadline]="${infoboxLabelDeadline}"
        [infoboxLabelDaysRemaining]="${infoboxLabelDaysRemaining}"
        [infoboxLabelLastRestart]="${infoboxLabelLastRestart}"
        [infoboxLabelFreeDiskSpace]="${infoboxLabelFreeDiskSpace}"
        [deadlineEnforcementMessage]="${deadlineEnforcementMessage}"
        [button1text]="${button1text}"
        [button2text]="${button2text}"
        [supportTeamName]="${supportTeamName}"
        [supportTeamPhone]="${supportTeamPhone}"
        [supportTeamEmail]="${supportTeamEmail}"
        [supportTeamWebsite]="${supportTeamWebsite}"
        [supportKBURL]="${supportKBURL}"
        [supportKB]="${supportKB}"
        [supportAssistanceMessage]="${supportAssistanceMessage}"
        [infobuttonaction]="${infobuttonaction}"
        [dialogVersion]="${dialogVersion}"
        [scriptVersion]="${scriptVersion}"
    )
}

function replacePlaceholders() {
    local targetVariable="${1}"
    local value="${(P)targetVariable}"
    local previousValue=""
    local maxPasses=5
    local pass=0

    while (( pass < maxPasses )); do
        previousValue="${value}"

        for placeholder replaceValue in "${(@kv)PLACEHOLDER_MAP}"; do
            value=${value//\{${placeholder}\}/${replaceValue}}
            value=${value//\{${placeholder}:l\}/${replaceValue:l}}
        done

        (( pass++ ))
        [[ "${value}" == "${previousValue}" ]] && break
    done

    printf -v "${targetVariable}" '%s' "${value}"
}

function applyHideRules() {
    case "${infobuttontext}" in
        "hide")
            infobuttontext=""
            ;;
    esac

    case "${helpimage}" in
        "hide")
            helpimage=""
            ;;
    esac

    case "${hideSecondaryButton}" in
        "YES")
            button2text=""
            ;;
    esac
}

function updateRequiredVariables() {
    dialogBinary="/usr/local/bin/dialog"
    [[ ! -x "${dialogBinary}" ]] && fatal "swiftDialog not found at '${dialogBinary}'."

    action="x-apple.systempreferences:com.apple.preferences.softwareupdate"
    downloadBrandingAssets
    applyLocalizedDialogText
    applyLocalizedUpdateVocabulary
    refreshLocalizedRuntimeFacts
    computeDynamicWarnings
    computeUpdateStagingMessage
    computeDeadlineEnforcementMessage
    computeInfoboxHighlights

    if [[ "${infobuttontext}" == "hide" ]]; then
        supportAssistanceMessage=""
    fi

    buildPlaceholderMap

    local textFields=(
        "title" "button1text" "button2text" "infobuttontext"
        "infobox" "helpmessage" "helpimage"
        "excessiveUptimeWarningMessage" "diskSpaceWarningMessage"
        "message" "supportAssistanceMessage"
    )

    for field in "${textFields[@]}"; do
        replacePlaceholders "${field}"
    done

    applyHideRules
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Debug Output
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function printResolvedPreferenceSummary() {
    preFlight "Preference domain: ${preferenceDomain}"
    preFlight "Managed preferences: ${managedPreferencesPlist}.plist (${foundManagedPreferences})"
    preFlight "Local preferences: ${localPreferencesPlist}.plist (${foundLocalPreferences})"
    preFlight "Resolved language: ${dialogLanguage}"
    preFlight "Detected appearance: ${requestedAppearanceMode}"
    preFlight "Title: ${title}"
    preFlight "Primary button: ${button1text}"
    preFlight "Secondary button: ${button2text:-<hidden>}"
    preFlight "Info button: ${infobuttontext:-<hidden>}"
    preFlight "Overlay icon source: ${overlayicon}"
    preFlight "Main icon source: ${icon}"
    preFlight "Help image: ${helpimage}"
    preFlight "Infobox: ${infobox}"
    preFlight "Message: ${message}"
}

function printDialogArguments() {
    local arg=""

    preFlight "swiftDialog arguments:"
    for arg in "${dialogArgs[@]}"; do
        echo "  ${arg}"
    done
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Button Actions
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function openDialogAction() {
    local targetAction="${1}"
    local actionLabel="${2}"

    if [[ -z "${targetAction}" ]]; then
        warning "No action configured for '${actionLabel}'."
        return 1
    fi

    if open "${targetAction}"; then
        info "Opened ${actionLabel}: ${targetAction}"
        return 0
    fi

    warning "Failed to open ${actionLabel}: ${targetAction}"
    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Display Reminder Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function displayReminderDialog() {
    dialogArgs=(
        --title "${title}"
        --message "${message}"
        --icon "${icon}"
        --iconsize 250
        --overlayicon "${overlayicon}"
        --infobox "${infobox}"
        --button1text "${button1text}"
        --messagefont "size=14"
        --quitkey "k"
        --width 800
        --height 650
        "${blurscreen}"
    )

    [[ -n "${button2text}" ]] && dialogArgs+=(--button2text "${button2text}")
    [[ "${hideSecondaryButton}" == "DISABLED" ]] && dialogArgs+=(--button2disabled)
    [[ -n "${infobuttontext}" ]] && dialogArgs+=(--infobuttontext "${infobuttontext}")
    [[ -n "${helpmessage}" ]] && dialogArgs+=(--helpmessage "${helpmessage}")
    [[ -n "${helpimage}" ]] && dialogArgs+=(--helpimage "${helpimage}")

    printDialogArguments

    "${dialogBinary}" "${dialogArgs[@]}"
    returncode=$?
    info "swiftDialog return code: ${returncode}"

    case ${returncode} in
        0)
            notice "${loggedInUser} clicked ${button1text}"
            openDialogAction "${action}" "System Settings Software Update pane"
            ;;
        2)
            notice "${loggedInUser} clicked ${button2text}"
            info "Preview dismissed via secondary button."
            ;;
        3)
            notice "${loggedInUser} clicked ${infobuttontext}"
            openDialogAction "${infobuttonaction}" "${infobuttontext:-Info button action}"
            ;;
        *)
            info "No post-dialog action for return code ${returncode}."
            ;;
    esac
}



####################################################################################################
#
# Program
#
####################################################################################################

preFlight "\n\n###\n# ${humanReadableScriptName} (${scriptVersion})\n# http://snelson.us/ddm\n###\n"
preFlight "Initiating …"

if ! loadPreferenceOverrides; then
    echo
    echo "No managed or local preferences were found for '${preferenceDomain}'."
    echo
    echo "Expected one of:"
    echo "  ${managedPreferencesPlist}.plist"
    echo "  ${localPreferencesPlist}.plist"
    echo
    echo "Install your Configuration Profile or local plist, then re-run:"
    echo "  zsh Resources/reminderDialogPreferenceTest.zsh"
    echo
    echo "Alternatively, you can copy the 'sample.plist' to the appropriate location:"
    echo "  cp -v Resources/sample.plist /Library/Preferences/org.churchofjesuschrist.dorm.plist"
    echo "  zsh Resources/reminderDialogPreferenceTest.zsh"
    echo
    echo
    exit 0
fi

resolveEffectiveUserContext
resolveDialogLanguage
initializeLocalizedRuntimeFields
prepareDemoRuntimeState

# -------------------------------------------------------------------------
# Real dialog-display logic begins here; all DDM enforcement logic is
# intentionally omitted in this preview script.
# -------------------------------------------------------------------------

updateRequiredVariables
printResolvedPreferenceSummary
displayReminderDialog

exit 0
