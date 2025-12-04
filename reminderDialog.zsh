#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Declarative Device Management macOS Reminder: End-user Message
#
# http://snelson.us/ddm
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="2.0.0b6-a1"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Load is-at-least for version comparison
autoload -Uz is-at-least



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Script Human-readable Name
humanReadableScriptName="DDM OS Reminder End-user Message"

# Organization's Script Name
organizationScriptName="dorm"

# Organization's reverse domain (used for plist domains)
reverseDomainNameNotation="org.churchofjesuschrist"

# Preference plist domains
preferenceDomain="${reverseDomainNameNotation}.ddmosreminder"
managedPreferencesPlist="/Library/Managed Preferences/${preferenceDomain}"
localPreferencesPlist="/Library/Preferences/${preferenceDomain}"

# Organization's number of days before deadline to starting displaying reminders
daysBeforeDeadlineDisplayReminder="14"

# Organization's number of days before deadline to enable swiftDialog's blurscreen
daysBeforeDeadlineBlurscreen="3"

# Organization's Meeting Delay (in minutes) 
meetingDelay="75"

# Date format for deadlines (used with date -jf)
dateFormatDeadlineHumanReadable="+%a, %d-%b-%Y, %-l:%M %p"

# Swap main icon and overlay icon (YES enable)
swapOverlayAndLogo=NO



####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo "${organizationScriptName} ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
}

function preFlight()    { updateScriptLog "[PRE-FLIGHT]      ${1}"; }
function logComment()   { updateScriptLog "                  ${1}"; }
function notice()       { updateScriptLog "[NOTICE]          ${1}"; }
function info()         { updateScriptLog "[INFO]            ${1}"; }
function errorOut()     { updateScriptLog "[ERROR]           ${1}"; }
function error()        { updateScriptLog "[ERROR]           ${1}"; let errorCount++; }
function warning()      { updateScriptLog "[WARNING]         ${1}"; let errorCount++; }
function fatal()        { updateScriptLog "[FATAL ERROR]     ${1}"; exit 1; }
function quitOut()      { updateScriptLog "[QUIT]            ${1}"; }



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Preference Helpers
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function setPreferenceValue() {

    local targetVariable="${1}"
    local managedValue="${2}"
    local localValue="${3}"
    local defaultValue="${4}"
    local chosenValue=""

    if [[ -n "${managedValue}" ]]; then
        chosenValue="${managedValue}"
    elif [[ -n "${localValue}" ]]; then
        chosenValue="${localValue}"
    else
        chosenValue="${defaultValue}"
    fi

    printf -v "${targetVariable}" '%s' "${chosenValue}"

}

function setNumericPreferenceValue() {

    local targetVariable="${1}"
    local managedValue="${2}"
    local localValue="${3}"
    local defaultValue="${4}"
    local candidate=""

    if [[ -n "${managedValue}" && "${managedValue}" == <-> ]]; then
        candidate="${managedValue}"
    elif [[ -n "${localValue}" && "${localValue}" == <-> ]]; then
        candidate="${localValue}"
    else
        candidate="${defaultValue}"
    fi

    printf -v "${targetVariable}" '%s' "${candidate}"

}

function replacePlaceholders() {

    local targetVariable="${1}"
    local value="${(P)targetVariable}"

    value=${value//\{weekday\}/$( date +'%A' )}
    value=${value//\{userfirstname\}/${loggedInUserFirstname}}
    value=${value//\{ddmVersionString\}/${ddmVersionString}}
    value=${value//\{ddmEnforcedInstallDateHumanReadable\}/${ddmEnforcedInstallDateHumanReadable}}
    value=${value//\{installedmacOSVersion\}/${installedmacOSVersion}}
    value=${value//\{ddmVersionStringDeadlineHumanReadable\}/${ddmVersionStringDeadlineHumanReadable}}
    value=${value//\{ddmVersionStringDaysRemaining\}/${ddmVersionStringDaysRemaining}}
    value=${value//\{supportTeamName\}/${supportTeamName}}
    value=${value//\{supportTeamPhone\}/${supportTeamPhone}}
    value=${value//\{supportTeamEmail\}/${supportTeamEmail}}
    value=${value//\{supportTeamWebsite\}/${supportTeamWebsite}}
    value=${value//\{supportKBURL\}/${supportKBURL}}
    value=${value//\{supportKB\}/${supportKB}}
    value=${value//\{dialogVersion\}/$(/usr/local/bin/dialog -v 2>/dev/null)}
    value=${value//\{scriptVersion\}/${scriptVersion}}

    printf -v "${targetVariable}" '%s' "${value}"

}

function applyHideRules() {

    # Hide info button explicitly
    if [[ "${infobuttontext}" == "hide" ]]; then
        infobuttontext=""
    fi

    # Hide help image (QR) if requested
    if [[ "${helpimage}" == "hide" ]]; then
        helpimage=""
    fi

}

function loadPreferenceOverrides() {

    if [[ -f ${managedPreferencesPlist}.plist ]]; then
        scriptLog_managed=$(defaults read "${managedPreferencesPlist}" ScriptLog 2> /dev/null)
        daysBeforeDeadlineDisplayReminder_managed=$(defaults read "${managedPreferencesPlist}" DaysBeforeDeadlineDisplayReminder 2> /dev/null)
        daysBeforeDeadlineBlurscreen_managed=$(defaults read "${managedPreferencesPlist}" DaysBeforeDeadlineBlurscreen 2> /dev/null)
        meetingDelay_managed=$(defaults read "${managedPreferencesPlist}" MeetingDelay 2> /dev/null)
        organizationOverlayiconURL_managed=$(defaults read "${managedPreferencesPlist}" OrganizationOverlayIconURL 2> /dev/null)
        swapOverlayAndLogo_managed=$(defaults read "${managedPreferencesPlist}" SwapOverlayAndLogo 2> /dev/null)
        dateFormatDeadlineHumanReadable_managed=$(defaults read "${managedPreferencesPlist}" DateFormatDeadlineHumanReadable 2> /dev/null)
        supportTeamName_managed=$(defaults read "${managedPreferencesPlist}" SupportTeamName 2> /dev/null)
        supportTeamPhone_managed=$(defaults read "${managedPreferencesPlist}" SupportTeamPhone 2> /dev/null)
        supportTeamEmail_managed=$(defaults read "${managedPreferencesPlist}" SupportTeamEmail 2> /dev/null)
        supportTeamWebsite_managed=$(defaults read "${managedPreferencesPlist}" SupportTeamWebsite 2> /dev/null)
        supportKB_managed=$(defaults read "${managedPreferencesPlist}" SupportKB 2> /dev/null)
        infobuttonaction_managed=$(defaults read "${managedPreferencesPlist}" InfoButtonAction 2> /dev/null)
        supportKBURL_managed=$(defaults read "${managedPreferencesPlist}" SupportKBURL 2> /dev/null)
        title_managed=$(defaults read "${managedPreferencesPlist}" Title 2> /dev/null)
        button1text_managed=$(defaults read "${managedPreferencesPlist}" Button1Text 2> /dev/null)
        button2text_managed=$(defaults read "${managedPreferencesPlist}" Button2Text 2> /dev/null)
        message_managed=$(defaults read "${managedPreferencesPlist}" Message 2> /dev/null)
        infobuttontext_managed=$(defaults read "${managedPreferencesPlist}" InfoButtonText 2> /dev/null)
        infobox_managed=$(defaults read "${managedPreferencesPlist}" InfoBox 2> /dev/null)
        helpmessage_managed=$(defaults read "${managedPreferencesPlist}" HelpMessage 2> /dev/null)
        helpimage_managed=$(defaults read "${managedPreferencesPlist}" HelpImage 2> /dev/null)
    fi

    if [[ -f ${localPreferencesPlist}.plist ]]; then
        scriptLog_local=$(defaults read "${localPreferencesPlist}" ScriptLog 2> /dev/null)
        daysBeforeDeadlineDisplayReminder_local=$(defaults read "${localPreferencesPlist}" DaysBeforeDeadlineDisplayReminder 2> /dev/null)
        daysBeforeDeadlineBlurscreen_local=$(defaults read "${localPreferencesPlist}" DaysBeforeDeadlineBlurscreen 2> /dev/null)
        meetingDelay_local=$(defaults read "${localPreferencesPlist}" MeetingDelay 2> /dev/null)
        organizationOverlayiconURL_local=$(defaults read "${localPreferencesPlist}" OrganizationOverlayIconURL 2> /dev/null)
        swapOverlayAndLogo_local=$(defaults read "${localPreferencesPlist}" SwapOverlayAndLogo 2> /dev/null)
        dateFormatDeadlineHumanReadable_local=$(defaults read "${localPreferencesPlist}" DateFormatDeadlineHumanReadable 2> /dev/null)
        supportTeamName_local=$(defaults read "${localPreferencesPlist}" SupportTeamName 2> /dev/null)
        supportTeamPhone_local=$(defaults read "${localPreferencesPlist}" SupportTeamPhone 2> /dev/null)
        supportTeamEmail_local=$(defaults read "${localPreferencesPlist}" SupportTeamEmail 2> /dev/null)
        supportTeamWebsite_local=$(defaults read "${localPreferencesPlist}" SupportTeamWebsite 2> /dev/null)
        supportKB_local=$(defaults read "${localPreferencesPlist}" SupportKB 2> /dev/null)
        infobuttonaction_local=$(defaults read "${localPreferencesPlist}" InfoButtonAction 2> /dev/null)
        supportKBURL_local=$(defaults read "${localPreferencesPlist}" SupportKBURL 2> /dev/null)
        title_local=$(defaults read "${localPreferencesPlist}" Title 2> /dev/null)
        button1text_local=$(defaults read "${localPreferencesPlist}" Button1Text 2> /dev/null)
        button2text_local=$(defaults read "${localPreferencesPlist}" Button2Text 2> /dev/null)
        message_local=$(defaults read "${localPreferencesPlist}" Message 2> /dev/null)
        infobuttontext_local=$(defaults read "${localPreferencesPlist}" InfoButtonText 2> /dev/null)
        infobox_local=$(defaults read "${localPreferencesPlist}" InfoBox 2> /dev/null)
        helpmessage_local=$(defaults read "${localPreferencesPlist}" HelpMessage 2> /dev/null)
        helpimage_local=$(defaults read "${localPreferencesPlist}" HelpImage 2> /dev/null)
    fi

    setPreferenceValue "scriptLog" "${scriptLog_managed}" "${scriptLog_local}" "${scriptLog}"
    setNumericPreferenceValue "daysBeforeDeadlineDisplayReminder" "${daysBeforeDeadlineDisplayReminder_managed}" "${daysBeforeDeadlineDisplayReminder_local}" "${daysBeforeDeadlineDisplayReminder}"
    setNumericPreferenceValue "daysBeforeDeadlineBlurscreen" "${daysBeforeDeadlineBlurscreen_managed}" "${daysBeforeDeadlineBlurscreen_local}" "${daysBeforeDeadlineBlurscreen}"
    setNumericPreferenceValue "meetingDelay" "${meetingDelay_managed}" "${meetingDelay_local}" "${meetingDelay}"
    setPreferenceValue "swapOverlayAndLogo" "${swapOverlayAndLogo_managed}" "${swapOverlayAndLogo_local}" "${swapOverlayAndLogo}"
    setPreferenceValue "dateFormatDeadlineHumanReadable" "${dateFormatDeadlineHumanReadable_managed}" "${dateFormatDeadlineHumanReadable_local}" "${dateFormatDeadlineHumanReadable}"
    # Ensure date format starts with '+' as required by `date`
    [[ "${dateFormatDeadlineHumanReadable}" != +* ]] && dateFormatDeadlineHumanReadable="+${dateFormatDeadlineHumanReadable}"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Current Logged-in User
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function currentLoggedInUser() {
    loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    preFlight "Current Logged-in User: ${loggedInUser}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Installed OS vs. DDM-enforced OS Comparison
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

installedOSvsDDMenforcedOS() {

    # Installed macOS Version
    installedmacOSVersion=$( sw_vers -productVersion )
    notice "Installed macOS Version: $installedmacOSVersion"

    # DDM-enforced macOS Version
    ddmLogEntry=$( grep "EnforcedInstallDate" /var/log/install.log | tail -n 1 )
    if [[ -z "$ddmLogEntry" ]]; then
        versionComparisonResult="No DDM enforcement log entry found; please confirm this Mac is in-scope for DDM-enforced updates."
        return
    fi

    # Parse enforced date and version
    ddmEnforcedInstallDate="${${ddmLogEntry##*|EnforcedInstallDate:}%%|*}"
    ddmVersionString="${${ddmLogEntry##*|VersionString:}%%|*}"

    # DDM-enforced Deadline
    ddmVersionStringDeadline="${ddmEnforcedInstallDate%%T*}"
    deadlineEpoch=$( date -jf "%Y-%m-%dT%H:%M:%S" "$ddmEnforcedInstallDate" "+%s" 2>/dev/null )
    ddmVersionStringDeadlineHumanReadable=$( date -jf "%Y-%m-%dT%H:%M:%S" "$ddmEnforcedInstallDate" "${dateFormatDeadlineHumanReadable}" 2>/dev/null )
    # Fallback to default if format fails
    if [[ -z "${ddmVersionStringDeadlineHumanReadable}" ]]; then
        ddmVersionStringDeadlineHumanReadable=$( date -jf "%Y-%m-%dT%H:%M:%S" "$ddmEnforcedInstallDate" "+%a, %d-%b-%Y, %-l:%M %p" 2>/dev/null )
    fi
    ddmVersionStringDeadlineHumanReadable=${ddmVersionStringDeadlineHumanReadable// AM/ a.m.}
    ddmVersionStringDeadlineHumanReadable=${ddmVersionStringDeadlineHumanReadable// PM/ p.m.}

    # DDM-enforced Install Date
    if (( deadlineEpoch <= $(date +%s) )); then

        # Enforcement deadline passed
        notice "DDM enforcement deadline has passed; evaluating post-deadline enforcement …"

        # Read Apple's internal padded enforcement date from install.log
        pastDueDeadline=$(grep "setPastDuePaddedEnforcementDate" /var/log/install.log | tail -n 1)
        if [[ -n "$pastDueDeadline" ]]; then
            paddedDateRaw="${pastDueDeadline#*setPastDuePaddedEnforcementDate is set: }"
            paddedEpoch=$( date -jf "%a %b %d %H:%M:%S %Y" "$paddedDateRaw" "+%s" 2>/dev/null )
            info "Found setPastDuePaddedEnforcementDate: ${paddedDateRaw:-Unparseable}"

            if [[ -n "$paddedEpoch" ]]; then
                ddmEnforcedInstallDateHumanReadable=$( date -jf "%s" "$paddedEpoch" "${dateFormatDeadlineHumanReadable}" 2>/dev/null )
                if [[ -z "${ddmEnforcedInstallDateHumanReadable}" ]]; then
                    ddmEnforcedInstallDateHumanReadable=$( date -jf "%s" "$paddedEpoch" "+%a, %d-%b-%Y, %-l:%M %p" 2>/dev/null )
                fi
                info "Using ${ddmEnforcedInstallDateHumanReadable} for enforced install date"
            else
                warning "Unable to parse padded enforcement date from install.log"
                ddmEnforcedInstallDateHumanReadable="Unavailable"
            fi
        else
            warning "No setPastDuePaddedEnforcementDate found in install.log"
            ddmEnforcedInstallDateHumanReadable="Unavailable"
        fi

        info "Effective enforcement source: setPastDuePaddedEnforcementDate"

    else

        # Deadline still in the future
        ddmEnforcedInstallDateHumanReadable="$ddmVersionStringDeadlineHumanReadable"

    fi

    # Normalize AM/PM formatting
    ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable// AM/ a.m.}
    ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable// PM/ p.m.}

    # Blurscreen logic (based on precise timestamp comparison)
    nowEpoch=$(date +%s)
    secondsUntilDeadline=$(( deadlineEpoch - nowEpoch ))
    blurThresholdSeconds=$(( daysBeforeDeadlineBlurscreen * 86400 ))
    ddmVersionStringDaysRemaining=$(( (secondsUntilDeadline + 43200) / 86400 )) # Round to nearest whole day
    if (( secondsUntilDeadline <= blurThresholdSeconds )); then
        blurscreen="--blurscreen"
    else
        blurscreen="--noblurscreen"
    fi

    # Version Comparison Result
    if is-at-least "$ddmVersionString" "$installedmacOSVersion"; then
        versionComparisonResult="Up-to-date"
        info "DDM-enforced OS Version: $ddmVersionString"
    else
        versionComparisonResult="Update Required"
        info "DDM-enforced OS Version: $ddmVersionString"
        info "DDM-enforced OS Version Deadline: $ddmVersionStringDeadlineHumanReadable"
        majorInstalled="${installedmacOSVersion%%.*}"
        majorDDM="${ddmVersionString%%.*}"
        if [[ "$majorInstalled" != "$majorDDM" ]]; then
            titleMessageUpdateOrUpgrade="Upgrade"
            softwareUpdateButtonText="Upgrade Now"
        else
            titleMessageUpdateOrUpgrade="Update"
            softwareUpdateButtonText="Restart Now"
        fi
    fi

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check User's Display Sleep Assertions (thanks, @techtrekkie!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function checkUserDisplaySleepAssertions() {

    notice "Check ${loggedInUser}'s Display Sleep Assertions"

    local intervalSeconds=300  # Default: 300 seconds (i.e., 5 minutes)
    local intervalMinutes=$(( intervalSeconds / 60 ))
    local maxChecks=$(( meetingDelay * 60 / intervalSeconds ))
    local checkCount=0

    while (( checkCount < maxChecks )); do
        local previousIFS="${IFS}"
        IFS=$'\n'

        local displayAssertionsArray
        displayAssertionsArray=( $(pmset -g assertions | awk '/NoDisplaySleepAssertion | PreventUserIdleDisplaySleep/ && match($0,/\(.+\)/) && ! /coreaudiod/ {gsub(/^\ +/,"",$0); print};') )

        if [[ -n "${displayAssertionsArray[*]}" ]]; then
            userDisplaySleepAssertions="TRUE"
            ((checkCount++))
            for displayAssertion in "${displayAssertionsArray[@]}"; do
                info "Found the following Display Sleep Assertion(s): $(echo "${displayAssertion}" | awk -F ':' '{print $1;}')"
            done
            info "Check ${checkCount} of ${maxChecks}: Display Sleep Assertion still active; pausing reminder. (Will check again in ${intervalMinutes} minute(s).)"
            IFS="${previousIFS}"
            sleep "${intervalSeconds}"
        else
            userDisplaySleepAssertions="FALSE"
            info "${loggedInUser}'s Display Sleep Assertion has ended after $(( checkCount * intervalMinutes )) minute(s)."
            IFS="${previousIFS}"
            return 0  # No active Display Sleep Assertions found
        fi
    done

    if [[ "${userDisplaySleepAssertions}" == "TRUE" ]]; then
        info "Presentation delay limit (${meetingDelay} min) reached after ${maxChecks} checks. Proceeding with reminder."
        return 1  # Presentation still active after full delay
    fi

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Required Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateRequiredVariables() {

    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Organization's Branding Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    # Organization's Overlayicon URL
    local defaultOverlayiconURL="${organizationOverlayiconURL:-""}"
    setPreferenceValue "organizationOverlayiconURL" "${organizationOverlayiconURL_managed}" "${organizationOverlayiconURL_local}" "${defaultOverlayiconURL}"

    # Download the overlayicon from ${organizationOverlayiconURL}
    if [[ -n "${organizationOverlayiconURL}" ]]; then
        # notice "Downloading overlayicon from '${organizationOverlayiconURL}' …"
        curl -o "/var/tmp/overlayicon.png" "${organizationOverlayiconURL}" --silent --show-error --fail
        if [[ "$?" -ne 0 ]]; then
            echo "Error: Failed to download the overlayicon from '${organizationOverlayiconURL}'."
            overlayicon="/System/Library/CoreServices/Finder.app"
        else
            overlayicon="/var/tmp/overlayicon.png"
        fi
    else
        overlayicon="/System/Library/CoreServices/Finder.app"
    fi



    # macOS Installer Icon URL
    majorDDM="${ddmVersionString%%.*}"
    case ${majorDDM} in
        14)  macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_eecee9688d1bc0426083d427d80c9ad48fa118b71d8d4962061d4de8d45747e7" ;;
        15)  macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_0968afcd54ff99edd98ec6d9a418a5ab0c851576b687756dc3004ec52bac704e" ;;
        26)  macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_7320c100c9ca155dc388e143dbc05620907e2d17d6bf74a8fb6d6278ece2c2b4" ;;
        *)   macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_4555d9dc8fecb4e2678faffa8bdcf43cba110e81950e07a4ce3695ec2d5579ee" ;;
    esac

    # Download the icon from ${macOSIconURL}
    if [[ -n "${macOSIconURL}" ]]; then
        # notice "Downloading icon from '${macOSIconURL}' …"
        curl -o "/var/tmp/icon.png" "${macOSIconURL}" --silent --show-error --fail
        if [[ "$?" -ne 0 ]]; then
            error "Failed to download the icon from '${macOSIconURL}'."
            icon="/System/Library/CoreServices/Finder.app"
        else
            icon="/var/tmp/icon.png"
        fi
    fi

    if [[ "${swapOverlayAndLogo}" == "1" || "${swapOverlayAndLogo:l}" == "true" || "${swapOverlayAndLogo:l}" == "yes" ]]; then
        tmp="$icon"
        icon="$overlayicon"
        overlayicon="$tmp"
    fi

    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # swiftDialog Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    # swiftDialog Binary Path
    dialogBinary="/usr/local/bin/dialog"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # IT Support Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    local defaultSupportTeamName="${supportTeamName:-"IT Support"}"
    setPreferenceValue "supportTeamName" "${supportTeamName_managed}" "${supportTeamName_local}" "${defaultSupportTeamName}"

    local defaultSupportTeamPhone="${supportTeamPhone:-"+1 (801) 555-1212"}"
    setPreferenceValue "supportTeamPhone" "${supportTeamPhone_managed}" "${supportTeamPhone_local}" "${defaultSupportTeamPhone}"

    local defaultSupportTeamEmail="${supportTeamEmail:-"rescue@domain.org"}"
    setPreferenceValue "supportTeamEmail" "${supportTeamEmail_managed}" "${supportTeamEmail_local}" "${defaultSupportTeamEmail}"

    local defaultSupportTeamWebsite="${supportTeamWebsite:-"https://support.domain.org"}"
    setPreferenceValue "supportTeamWebsite" "${supportTeamWebsite_managed}" "${supportTeamWebsite_local}" "${defaultSupportTeamWebsite}"

    local defaultSupportKB="${supportKB:-"KB8675309"}"
    setPreferenceValue "supportKB" "${supportKB_managed}" "${supportKB_local}" "${defaultSupportKB}"

    local defaultInfobuttonaction="https://servicenow.domain.org/support?id=kb_article_view&sysparm_article=${supportKB}"
    setPreferenceValue "infobuttonaction" "${infobuttonaction_managed}" "${infobuttonaction_local}" "${defaultInfobuttonaction}"

    local defaultSupportKBURL="[${supportKB}](${infobuttonaction})"
    setPreferenceValue "supportKBURL" "${supportKBURL_managed}" "${supportKBURL_local}" "${defaultSupportKBURL}"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Title, Message and  Button Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    local defaultTitle="macOS ${titleMessageUpdateOrUpgrade} Required"
    setPreferenceValue "title" "${title_managed}" "${title_local}" "${defaultTitle}"
    replacePlaceholders "title"

    local defaultButton1text="${button1text:-"Open Software Update"}"
    setPreferenceValue "button1text" "${button1text_managed}" "${button1text_local}" "${defaultButton1text}"

    local defaultButton2text="${button2text:-"Remind Me Later"}"
    setPreferenceValue "button2text" "${button2text_managed}" "${button2text_local}" "${defaultButton2text}"

    local defaultInfobuttontext="${infobuttontext:-${supportKB}}"
    setPreferenceValue "infobuttontext" "${infobuttontext_managed}" "${infobuttontext_local}" "${defaultInfobuttontext}"

    local defaultAction="${action:-"x-apple.systempreferences:com.apple.preferences.softwareupdate"}"
    printf -v "action" '%s' "${defaultAction}"

    local defaultMessage="**A required macOS ${titleMessageUpdateOrUpgrade:l} is now available**<br>---<br>Happy $( date +'%A' ), ${loggedInUserFirstname}!<br><br>Please ${titleMessageUpdateOrUpgrade:l} to macOS **${ddmVersionString}** to ensure your Mac remains secure and compliant with organizational policies.<br><br>To perform the ${titleMessageUpdateOrUpgrade:l} now, click **${button1text}**, review the on-screen instructions, then click **${softwareUpdateButtonText}**.<br><br>If you are unable to perform this ${titleMessageUpdateOrUpgrade:l} now, click **${button2text}** to be reminded again later.<br><br>However, your device **will automatically restart and ${titleMessageUpdateOrUpgrade:l}** on **${ddmEnforcedInstallDateHumanReadable}** if you have not ${titleMessageUpdateOrUpgrade:l}d before the deadline.<br><br>For assistance, please contact **${supportTeamName}** by clicking the (?) button in the bottom, right-hand corner."
    setPreferenceValue "message" "${message_managed}" "${message_local}" "${defaultMessage}"
    replacePlaceholders "message"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Infobox Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    local defaultInfobox="**Current:** ${installedmacOSVersion}<br><br>**Required:** ${ddmVersionString}<br><br>**Deadline:** ${ddmVersionStringDeadlineHumanReadable}<br><br>**Day(s) Remaining:** ${ddmVersionStringDaysRemaining}"
    setPreferenceValue "infobox" "${infobox_managed}" "${infobox_local}" "${defaultInfobox}"
    replacePlaceholders "infobox"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Help Message Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    local defaultHelpmessage="For assistance, please contact: **${supportTeamName}**<br>- **Telephone:** ${supportTeamPhone}<br>- **Email:** ${supportTeamEmail}<br>- **Website:** ${supportTeamWebsite}<br>- **Knowledge Base Article:** ${supportKBURL}<br><br>**User Information:**<br>- **Full Name:** {userfullname}<br>- **User Name:** {username}<br><br>**Computer Information:**<br>- **Computer Name:** {computername}<br>- **Serial Number:** {serialnumber}<br>- **macOS:** {osversion}<br><br>**Script Information:**<br>- **Dialog:** $(/usr/local/bin/dialog -v)<br>- **Script:** ${scriptVersion}<br>"
    setPreferenceValue "helpmessage" "${helpmessage_managed}" "${helpmessage_local}" "${defaultHelpmessage}"
    replacePlaceholders "helpmessage"
    local defaultHelpimage="qr=${infobuttonaction}"
    setPreferenceValue "helpimage" "${helpimage_managed}" "${helpimage_local}" "${defaultHelpimage}"
    replacePlaceholders "helpimage"

    applyHideRules

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Display Reminder Dialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function displayReminderDialog() {

    additionalDialogOptions=("$@")

    notice "Display Reminder Dialog to ${loggedInUser} with additional options: ${additionalDialogOptions}"

    dialogArgs=(
        --title "${title}"
        --message "${message}"
        --icon "${icon}"
        --iconsize 250
        --overlayicon "${overlayicon}"
        --infobox "${infobox}"
        --button1text "${button1text}"
        --button2text "${button2text}"
        --messagefont "size=14"
        --width 800
        --height 600
        "${blurscreen}"
        "${additionalDialogOptions[@]}"
    )

    [[ -n "${infobuttontext}" ]] && dialogArgs+=(--infobuttontext "${infobuttontext}")
    [[ -n "${helpmessage}" ]] && dialogArgs+=(--helpmessage "${helpmessage}")
    [[ -n "${helpimage}" ]] && dialogArgs+=(--helpimage "${helpimage}")

    ${dialogBinary} "${dialogArgs[@]}"

    returncode=$?
    info "Return Code: ${returncode}"

    case ${returncode} in

    0)  ## Process exit code 0 scenario here
        notice "${loggedInUser} clicked ${button1text}"
        if [[ "${action}" == *"systempreferences"* ]]; then
            su - "$(stat -f%Su /dev/console)" -c "open '${action}'"
            notice "Checking if System Settings is open …"
            until osascript -e 'application "System Settings" is running' >/dev/null 2>&1; do
                info "Pending System Settings launch …"
                sleep 0.5
            done
            info "System Settings is open; Telling System Settings to make a guest appearance …"
            su - "$(stat -f%Su /dev/console)" -c '
            timeout=10
            while ((timeout > 0)); do
                if osascript -e "application \"System Settings\" is running" >/dev/null 2>&1; then
                    if osascript -e "tell application \"System Settings\" to activate" >/dev/null 2>&1; then
                        exit 0
                    fi
                fi
                sleep 0.5
                ((timeout--))
            done
            exit 1
            '
        else
            su - "$(stat -f%Su /dev/console)" -c "open '${action}'"
        fi
        quitScript "0"
        ;;

        2)  ## Process exit code 2 scenario here
            notice "${loggedInUser} clicked ${button2text}"
            quitScript "0"
            ;;

        3)  ## Process exit code 3 scenario here
            notice "${loggedInUser} clicked ${infobuttontext}"
            info "Disabling blurscreen, hiding dialog and opening KB article: ${infobuttontext}"
            echo "blurscreen: disable" >> /var/tmp/dialog.log
            echo "hide:" >> /var/tmp/dialog.log
            su \- "$(stat -f%Su /dev/console)" -c "open '${infobuttonaction}'"
            info "Waiting 61 seconds before re-showing dialog …"
            sleep 61
            displayReminderDialog --ontop --moveable
            ;;

        4)  ## Process exit code 4 scenario here
            notice "User allowed timer to expire"
            quitScript "0"
            ;;

        20) ## Process exit code 20 scenario here
            notice "User had Do Not Disturb enabled"
            quitScript "0"
            ;;

        *)  ## Catch all processing
            notice "Something else happened; Exit code: ${returncode}"
            quitScript "${returncode}"
            ;;

    esac

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Quit Script (thanks, @bartreadon!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function quitScript() {

    quitOut "Exiting …"

    # Remove overlay icon
    if [[ -f "${icon}" ]] && [[ "${icon}" != "/System/Library/CoreServices/Finder.app" ]]; then
        rm -f "${icon}"
    fi

    # Remove default dialog.log
    rm -f /var/tmp/dialog.log

    quitOut "Keep them movin' blades sharp!"

    exit "${1}"

}



####################################################################################################
#
# Apply Preference Overrides
#
####################################################################################################

loadPreferenceOverrides



####################################################################################################
#
# Pre-flight Checks
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${scriptLog}" ]]; then
    touch "${scriptLog}"
    if [[ -f "${scriptLog}" ]]; then
        preFlight "Created specified scriptLog: ${scriptLog}"
    else
        fatal "Unable to create specified scriptLog '${scriptLog}'; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    # preFlight "Specified scriptLog '${scriptLog}' exists; writing log entries to it"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})\n# http://snelson.us/ddm\n####\n"
preFlight "Initiating …"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(id -u) -ne 0 ]]; then
    fatal "This script must be run as root; exiting."
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate Logged-in System Accounts
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "Check for Logged-in System Accounts …"
currentLoggedInUser

counter="1"

until { [[ -n "${loggedInUser}" && "${loggedInUser}" != "loginwindow" ]] || [[ "${counter}" -gt "30" ]]; } ; do

    preFlight "Logged-in User Counter: ${counter}"
    currentLoggedInUser
    sleep 2
    ((counter++))

done

loggedInUserFullname=$( id -F "${loggedInUser}" )
loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}' )
loggedInUserID=$( id -u "${loggedInUser}" )
preFlight "Current Logged-in User First Name (ID): ${loggedInUserFirstname} (${loggedInUserID})"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Complete
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "Complete"



####################################################################################################
#
# Program
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Demo Mode (i.e., zsh ~/Downloads/reminderDialog.zsh demo)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${1}" == "demo" ]]; then

    notice "Demo mode enabled"

    # Installed vs Required Version
    installedmacOSVersion=$( sw_vers -productVersion )
    demoMajorVersion="${installedmacOSVersion%%.*}"
    ddmVersionString="${demoMajorVersion}.99"

    # Days from today to simulate deadline (can be + or -)
    demoDeadlineOffsetDays=7   # positive → future deadline; negative → past due
    if (( demoDeadlineOffsetDays < 0 )); then       # Normalize the offset so “-3” becomes "-3d" and “7” becomes "+7d"
        offsetString="${demoDeadlineOffsetDays}d"   # → "-3d"
        blurscreen="--blurscreen"
    else
        offsetString="+${demoDeadlineOffsetDays}d"  # → "+7d"
        blurscreen="--noblurscreen"
    fi
    ddmEnforcedInstallDate=$(date -v${offsetString} +"%Y-%m-%d")

    ddmVersionStringDeadline="${ddmEnforcedInstallDate}T18:00:00" # add time to satisfy parsing
    ddmEnforcedInstallDateHumanReadable=$(date -jf "%Y-%m-%dT%H:%M:%S" "${ddmVersionStringDeadline}" "${dateFormatDeadlineHumanReadable}")
    if [[ -z "${ddmEnforcedInstallDateHumanReadable}" ]]; then
        ddmEnforcedInstallDateHumanReadable=$(date -jf "%Y-%m-%dT%H:%M:%S" "${ddmVersionStringDeadline}" "+%a, %d-%b-%Y, %-l:%M %p")
    fi
    ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable// AM/ a.m.}
    ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable// PM/ p.m.}
    ddmVersionStringDaysRemaining="${demoDeadlineOffsetDays}"
    ddmVersionStringDeadlineHumanReadable="${ddmEnforcedInstallDateHumanReadable}"

    # Title / update-or-upgrade logic
    # If required major != installed major → upgrade, else update
    if [[ "${demoMajorVersion}" != "${installedmacOSVersion%%.*}" ]]; then
        titleMessageUpdateOrUpgrade="Upgrade"
        softwareUpdateButtonText="Upgrade Now"
    else
        titleMessageUpdateOrUpgrade="Update"
        softwareUpdateButtonText="Restart Now"
    fi

    # Other variables normally generated in installedOSvsDDMenforcedOS
    versionComparisonResult="Update Required"

    # Logged-in user (normally populated earlier)
    loggedInUserFirstname="${loggedInUserFirstname:-Demo}"
    loggedInUser="${loggedInUser:-demo}"

    # Now populate dialog strings using your standard function
    updateRequiredVariables

    # Display reminder dialog
    displayReminderDialog --ontop

    exit 0

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Installed OS vs. DDM-enforced OS Comparison
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

installedOSvsDDMenforcedOS



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# If Update Required, Display Dialog Window (respecting Display Reminder threshold)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${versionComparisonResult}" == "Update Required" ]]; then

    # Skip notifications if we're outside the display reminder window (thanks for the suggestion, @kristian!)
    if (( ddmVersionStringDaysRemaining > daysBeforeDeadlineDisplayReminder )); then
        notice "Deadline still ${ddmVersionStringDaysRemaining} days away; skipping reminder until within ${daysBeforeDeadlineDisplayReminder}-day window."
        quitScript "0"
    else
        notice "Within ${daysBeforeDeadlineDisplayReminder}-day reminder window; proceeding with reminder."
    fi

    # Confirm the currently logged-in user is "available" to be reminded
    # If the deadline is more than 24 hours away, and the user has an active Display Assertion, exit the script
    if [[ "${ddmVersionStringDaysRemaining}" -gt 1 ]]; then
        if checkUserDisplaySleepAssertions; then
            notice "No active Display Sleep Assertions detected; proceeding with reminder."
        else
            notice "Presentation still active after ${meetingDelay} minutes; exiting quietly."
            quitScript "0"
        fi
    else
        info "Deadline is within 24 hours; ignoring ${loggedInUser}'s Display Sleep Assertions."
    fi

    # Randomly pause script during its launch hours of 8 a.m. and 4 p.m.; Login pause of 30 to 90 seconds
    currentHour=$(( $(date +%H) ))
    currentMinute=$(( $(date +%M) ))

    if (( currentHour == 8 || currentHour == 16 )) && (( currentMinute == 0 )); then
        notice "Daily Trigger Pause: Random 0 to 20 minutes"
        sleepSeconds=$(( RANDOM % 1200 ))
    else
        notice "Login Trigger Pause: Random 30 to 90 seconds"
        sleepSeconds=$(( 30 + RANDOM % 61 ))
    fi

    if (( sleepSeconds >= 60 )); then
        (( pauseMinutes = sleepSeconds / 60 ))
        (( pauseSeconds = sleepSeconds % 60 ))
        if (( pauseSeconds == 0 )); then
            humanReadablePause="${pauseMinutes} minute(s)"
        else
            humanReadablePause="${pauseMinutes} minute(s), ${pauseSeconds} second(s)"
        fi
    else
        humanReadablePause="${sleepSeconds} second(s)"
    fi
    info "Pausing for ${humanReadablePause} …"
    sleep "${sleepSeconds}"

    # Update Required Variables
    updateRequiredVariables

    # Display reminder dialog (with blurscreen, depending on proximity to deadline)
    displayReminderDialog --ontop

else

    info "Version Comparison Result: ${versionComparisonResult}"

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

exit 0
