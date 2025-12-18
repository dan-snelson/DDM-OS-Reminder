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
scriptVersion="2.2.0b13"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Load is-at-least for version comparison
autoload -Uz is-at-least



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Script Human-readable Name
humanReadableScriptName="DDM OS Reminder End-user Message"

# Organization’s reverse domain (used for plist domains)
reverseDomainNameNotation="org.churchofjesuschrist"

# Organization’s Script Name
organizationScriptName="dorm"

# Preference plist domains
preferenceDomain="${reverseDomainNameNotation}.${organizationScriptName}"
managedPreferencesPlist="/Library/Managed Preferences/${preferenceDomain}"
localPreferencesPlist="/Library/Preferences/${preferenceDomain}"

# Organization’s number of days before deadline to starting displaying reminders
daysBeforeDeadlineDisplayReminder="60"

# Organization’s number of days before deadline to enable swiftDialog’s blurscreen
daysBeforeDeadlineBlurscreen="45"

# Organization’s number of days before deadline to hide the secondary button
daysBeforeDeadlineHidingButton2="21"

# Organization’s number of days of excessive uptime before warning the user
daysOfExcessiveUptimeWarning="0"

# Organization’s minimum percentage of free disk space required for update
minimumDiskFreePercentage="99"

# Organization’s Meeting Delay (in minutes) 
meetingDelay="75"

# Track whether the secondary button should be hidden (computed at runtime)
hideSecondaryButton="NO"

# Date format for deadlines (used with date -jf)
dateFormatDeadlineHumanReadable="+%a, %d-%b-%Y, %-l:%M %p"

# Swap main icon and overlay icon (set to YES, true, or 1 to enable)
swapOverlayAndLogo="NO"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Uptime Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

lastBootTime=$( sysctl kern.boottime | awk -F'[ |,]' '{print $5}' )
currentTime=$( date +"%s" )
upTimeRaw=$((currentTime-lastBootTime))
upTimeMin=$((upTimeRaw/60))
upTimeHours=$((upTimeMin/60))
uptimeDays=$( uptime | awk '{ print $4 }' | sed 's/,//g' )
uptimeNumber=$( uptime | awk '{ print $3 }' | sed 's/,//g' )

if [[ "${uptimeDays}" = "day"* ]]; then
    if [[ "${uptimeNumber}" -gt 1 ]]; then
        uptimeHumanReadable="${uptimeNumber} days"
    else
        uptimeHumanReadable="${uptimeNumber} day"
    fi
elif [[ "${uptimeDays}" == "mins"* ]]; then
    uptimeHumanReadable="${uptimeNumber} mins"
else
    uptimeHumanReadable="${uptimeNumber} (HH:MM)"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Free Disk Space Variables (inspired by Mac Health Check)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

freeSpace=$(diskutil info / | awk -F ': ' '/Free Space|Available Space|Container Free Space/ {print $2}' | awk -F '(' '{print $1}' | xargs)
diskBytes=$(diskutil info / | awk -F '[()]' '/Total Space/ {print $2}' | awk '{print $1}')
freeBytes=$(diskutil info / | awk -F '[()]' '/Free Space|Available Space|Container Free Space/ {print $2}' | awk '{print $1}')

if [[ -n "${diskBytes}" && -n "${freeBytes}" ]]; then
    freePercentage=$(echo "scale=2; (${freeBytes} * 100) / ${diskBytes}" | bc)
else
    freePercentage=""  # fallback
fi

diskSpaceHumanReadable="${freeSpace} (${freePercentage}% available)"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Preference Configuration Map
# - Format: key|type|defaultValue
# - Types: string, numeric, boolean
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

declare -A preferenceConfiguration=(
    # Logging and Timing
    ["scriptLog"]="string|/var/log/org.churchofjesuschrist.log"
    ["daysBeforeDeadlineDisplayReminder"]="numeric|60"
    ["daysBeforeDeadlineBlurscreen"]="numeric|45"
    ["daysBeforeDeadlineHidingButton2"]="numeric|21"
    ["daysOfExcessiveUptimeWarning"]="numeric|0"
    ["meetingDelay"]="numeric|75"
    ["minimumDiskFreePercentage"]="numeric|99"
    
    # Branding
    ["organizationOverlayiconURL"]="string|https://usw2.ics.services.jamfcloud.com/icon/hash_4804203ac36cbd7c83607487f4719bd4707f2e283500f54428153af17da082e2"
    ["swapOverlayAndLogo"]="boolean|NO"
    ["dateFormatDeadlineHumanReadable"]="string|+%a, %d-%b-%Y, %-l:%M %p"
    
    # Support Team
    ["supportTeamName"]="string|IT Support"
    ["supportTeamPhone"]="string|+1 (801) 555-1212"
    ["supportTeamEmail"]="string|rescue@domain.org"
    ["supportTeamWebsite"]="string|https://support.domain.org"
    ["supportKB"]="string|108382"
    ["infobuttonaction"]="string|https://support.apple.com/108382"
    ["supportKBURL"]="string|[108382](https://support.apple.com/108382)"
    
    # UI Text
    ["title"]="string|macOS {titleMessageUpdateOrUpgrade} Required"
    ["button1text"]="string|Open Software Update"
    ["button2text"]="string|Remind Me Later"
    ["infobuttontext"]="string|108382"
    ["excessiveUptimeWarningMessage"]="string|<br><br>**Note:** Your Mac has been powered-on for **{uptimeHumanReadable}**. For more reliable results, please manually restart your Mac before proceeding."
    ["diskSpaceWarningMessage"]="string|<br><br>**Note:** Your Mac has only **{diskSpaceHumanReadable}**, which may prevent this macOS {titleMessageUpdateOrUpgrade:l}."
    
    # Update Staging Messages
    ["stagedUpdateMessage"]="string|<br><br>**Good news!** The macOS {ddmVersionString} update has already been downloaded to your Mac and is ready to install. Installation will proceed quickly when you click **{button1text}**."
    ["partiallyStagedUpdateMessage"]="string|<br><br>Your Mac has begun downloading and preparing required macOS update components. Installation will be quicker once all assets have finished staging."
    ["pendingDownloadMessage"]="string|"
    ["hideStagedInfo"]="boolean|NO"
    
    # Complex UI Text
    ["message"]="string|**A required macOS {titleMessageUpdateOrUpgrade:l} is now available**<br><br>Happy {weekday}, {loggedInUserFirstname}!<br><br>Please {titleMessageUpdateOrUpgrade:l} to macOS **{ddmVersionString}** to ensure your Mac remains secure and compliant with organizational policies.{updateReadyMessage}<br><br>To perform the {titleMessageUpdateOrUpgrade:l} now, click **{button1text}**, review the on-screen instructions, then click **{softwareUpdateButtonText}**.<br><br>If you are unable to perform this {titleMessageUpdateOrUpgrade:l} now, click **{button2text}** to be reminded again later.<br><br>However, your device **will automatically restart and {titleMessageUpdateOrUpgrade:l}** on **{ddmEnforcedInstallDateHumanReadable}** if you have not {titleMessageUpdateOrUpgrade:l}d before the deadline.{excessiveUptimeWarningMessage}{diskSpaceWarningMessage}<br><br>For assistance, please contact **{supportTeamName}** by clicking the (?) button in the bottom, right-hand corner."
    ["infobox"]="string|**Current:** macOS {installedmacOSVersion}<br><br>**Required:** macOS {ddmVersionString}<br><br>**Deadline:** {ddmVersionStringDeadlineHumanReadable}<br><br>**Day(s) Remaining:** {ddmVersionStringDaysRemaining}<br><br>**Last Restart:** {uptimeHumanReadable}<br><br>**Free Disk Space:** {diskSpaceHumanReadable}"
    ["helpmessage"]="string|For assistance, please contact: **{supportTeamName}**<br>- **Telephone:** {supportTeamPhone}<br>- **Email:** {supportTeamEmail}<br>- **Website:** {supportTeamWebsite}<br>- **Knowledge Base Article:** {supportKBURL}<br><br>**User Information:**<br>- **Full Name:** {userfullname}<br>- **User Name:** {username}<br><br>**Computer Information:**<br>- **Computer Name:** {computername}<br>- **Serial Number:** {serialnumber}<br>- **macOS:** {osversion}<br><br>**Script Information:**<br>- **Dialog:** {dialogVersion}<br>- **Script:** {scriptVersion}<br>"
    ["helpimage"]="string|qr={infobuttonaction}"
)

    # Map of preference keys to their plist key names (for keys that differ)
    declare -A plistKeyMap=(
    ["scriptLog"]="ScriptLog"
    ["daysBeforeDeadlineDisplayReminder"]="DaysBeforeDeadlineDisplayReminder"
    ["daysBeforeDeadlineBlurscreen"]="DaysBeforeDeadlineBlurscreen"
    ["daysBeforeDeadlineHidingButton2"]="DaysBeforeDeadlineHidingButton2"
    ["daysOfExcessiveUptimeWarning"]="DaysOfExcessiveUptimeWarning"
    ["meetingDelay"]="MeetingDelay"
    ["minimumDiskFreePercentage"]="MinimumDiskFreePercentage"
    ["organizationOverlayiconURL"]="OrganizationOverlayIconURL"
    ["swapOverlayAndLogo"]="SwapOverlayAndLogo"
    ["dateFormatDeadlineHumanReadable"]="DateFormatDeadlineHumanReadable"
    ["supportTeamName"]="SupportTeamName"
    ["supportTeamPhone"]="SupportTeamPhone"
    ["supportTeamEmail"]="SupportTeamEmail"
    ["supportTeamWebsite"]="SupportTeamWebsite"
    ["supportKB"]="SupportKB"
    ["infobuttonaction"]="InfoButtonAction"
    ["supportKBURL"]="SupportKBURL"
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

function setBooleanPreferenceValue() {
    local targetVariable="${1}"
    local managedValue="${2}"
    local localValue="${3}"
    local defaultValue="${4}"
    local chosenValue="${defaultValue}"
    
    # Managed takes precedence
    if [[ -n "${managedValue}" ]]; then
        chosenValue=$(normalizeBooleanValue "${managedValue}")
    elif [[ -n "${localValue}" ]]; then
        chosenValue=$(normalizeBooleanValue "${localValue}")
    fi
    
    printf -v "${targetVariable}" '%s' "${chosenValue}"
}

function normalizeBooleanValue() {
    local value="${1}"
    case "${value:l}" in
        1|true|yes) echo "YES" ;;
        0|false|no) echo "NO" ;;
        *) echo "NO" ;;
    esac
}

function replacePlaceholders() {
    local targetVariable="${1}"
    local value="${(P)targetVariable}"
    
    # Placeholder map
    local -A placeholders=(
        [weekday]="$( date +'%A' )"
        [userfirstname]="${loggedInUserFirstname}"
        [loggedInUserFirstname]="${loggedInUserFirstname}"
        [ddmVersionString]="${ddmVersionString}"
        [ddmEnforcedInstallDateHumanReadable]="${ddmEnforcedInstallDateHumanReadable}"
        [installedmacOSVersion]="${installedmacOSVersion}"
        [ddmVersionStringDeadlineHumanReadable]="${ddmVersionStringDeadlineHumanReadable}"
        [ddmVersionStringDaysRemaining]="${ddmVersionStringDaysRemaining}"
        [titleMessageUpdateOrUpgrade]="${titleMessageUpdateOrUpgrade}"
        [uptimeHumanReadable]="${uptimeHumanReadable}"
        [excessiveUptimeWarningMessage]="${excessiveUptimeWarningMessage}"
        [updateReadyMessage]="${updateReadyMessage}"
        [diskSpaceHumanReadable]="${diskSpaceHumanReadable}"
        [diskSpaceWarningMessage]="${diskSpaceWarningMessage}"
        [softwareUpdateButtonText]="${softwareUpdateButtonText}"
        [button1text]="${button1text}"
        [button2text]="${button2text}"
        [supportTeamName]="${supportTeamName}"
        [supportTeamPhone]="${supportTeamPhone}"
        [supportTeamEmail]="${supportTeamEmail}"
        [supportTeamWebsite]="${supportTeamWebsite}"
        [supportKBURL]="${supportKBURL}"
        [supportKB]="${supportKB}"
        [infobuttonaction]="${infobuttonaction}"
        [dialogVersion]="$(/usr/local/bin/dialog -v 2>/dev/null)"
        [scriptVersion]="${scriptVersion}"
    )

    # Replace all placeholders (both escaped and unescaped variants)
    for placeholder replaceValue in "${(@kv)placeholders}"; do
        value=${value//\{${placeholder}\}/${replaceValue}}
        value=${value//\{${placeholder}:l\}/${replaceValue:l}}
        value=${value//"{"${placeholder}"}"/${replaceValue}}
        value=${value//"{"${placeholder}:l"}"/${replaceValue:l}}
    done
    
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

    # Hide secondary button based on computed deadline window flag
    if [[ "${hideSecondaryButton}" == "YES" ]]; then
        button2text=""
    fi
}

function loadDefaultPreferences() {
    for prefKey in "${(@k)preferenceConfiguration}"; do
        local prefConfig="${preferenceConfiguration[$prefKey]}"
        local defaultValue="${prefConfig#*|}"
        printf -v "${prefKey}" '%s' "${defaultValue}"
    done
}

function loadPreferenceOverrides() {
    
    # Check if managed preferences exist
    local hasManagedPrefs=false
    if [[ -f ${managedPreferencesPlist}.plist ]]; then
        hasManagedPrefs=true
        preFlight "Reading preference overrides from '${managedPreferencesPlist}.plist'"
    fi
    
    # Check if local preferences exist
    local hasLocalPrefs=false
    if [[ -f ${localPreferencesPlist}.plist ]]; then
        hasLocalPrefs=true
        preFlight "Reading preference overrides from '${localPreferencesPlist}.plist'"
    fi
    
    if [[ "${hasManagedPrefs}" == "false" && "${hasLocalPrefs}" == "false" ]]; then
        preFlight "No client-side preferences found; using script-defined defaults"
        loadDefaultPreferences
        return
    fi
    
    # Load all preferences using the configuration map
    for prefKey in "${(@k)preferenceConfiguration}"; do
        local prefConfig="${preferenceConfiguration[$prefKey]}"
        local prefType="${prefConfig%%|*}"
        local defaultValue="${prefConfig#*|}"
        local plistKey="${plistKeyMap[$prefKey]:-$prefKey}"
        
        # Read managed value
        local managedValue=""
        if [[ "${hasManagedPrefs}" == "true" ]]; then
            managedValue=$(defaults read "${managedPreferencesPlist}" "${plistKey}" 2>/dev/null)
        fi
        
        # Read local value
        local localValue=""
        if [[ "${hasLocalPrefs}" == "true" ]]; then
            localValue=$(defaults read "${localPreferencesPlist}" "${plistKey}" 2>/dev/null)
        fi
        
        # Apply the preference based on type
        case "${prefType}" in
            numeric)
                setNumericPreferenceValue "${prefKey}" "${managedValue}" "${localValue}" "${defaultValue}"
                ;;
            boolean)
                setBooleanPreferenceValue "${prefKey}" "${managedValue}" "${localValue}" "${defaultValue}"
                ;;
            string|*)
                setPreferenceValue "${prefKey}" "${managedValue}" "${localValue}" "${defaultValue}"
                ;;
        esac
    done
    
    # Special handling for date format
    [[ "${dateFormatDeadlineHumanReadable}" != +* ]] && dateFormatDeadlineHumanReadable="+${dateFormatDeadlineHumanReadable}"
    
    preFlight "Preferences loaded"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Current Logged-in User
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function currentLoggedInUser() {
    loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    preFlight "Current Logged-in User: ${loggedInUser}"
}




# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Detect Staged macOS Updates
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function detectStagedUpdate() {

    local stagedUpdateSize="0"
    local stagedUpdateLocation="Not detected"
    local stagedUpdateStatus="Pending download"
    
    # Check for APFS snapshots indicating staged updates
    local updateSnapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c "com.apple.os.update")
    
    if [[ ${updateSnapshots} -gt 0 ]]; then
        info "Found ${updateSnapshots} update snapshot(s)"
        stagedUpdateStatus="Partially staged"
    fi
    
    # Identify Preboot UUID directory
    local systemVolumeUUID
    systemVolumeUUID=$(
        ls -1 /System/Volumes/Preboot 2>/dev/null \
        | grep -E '^[A-F0-9]{8}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{12}$' \
        | head -1
    )

    if [[ -z "${systemVolumeUUID}" ]]; then
        info "No Preboot UUID directory found; staging cannot be evaluated."
        updateStagingStatus="Pending download"
        return
    fi

    local prebootPath="/System/Volumes/Preboot/${systemVolumeUUID}"
    info "Using Preboot UUID directory: ${prebootPath}"

    if [[ -n "${systemVolumeUUID}" ]]; then
        local prebootPath="/System/Volumes/Preboot/${systemVolumeUUID}"

        # Diagnostic Logging (Preboot visibility)
        info "Analyzing Preboot path: ${prebootPath}"

        if [[ ! -d "${prebootPath}" ]]; then
            info "Preboot path does not exist or is not a directory."
        else
            info "Listing contents of Preboot UUID directory:"
            ls -l "${prebootPath}" 2>/dev/null | sed 's/^/    /' || info "Unable to list Preboot contents"

            # Check for expected staging directories
            if [[ ! -d "${prebootPath}/cryptex1" ]]; then
                info "No 'cryptex1' directory present (normal until staging begins)"
            fi
            if [[ ! -d "${prebootPath}/restore-staged" ]]; then
                info "No 'restore-staged' directory present (normal until later staging phase)"
            fi
        fi

        # Check cryptex1 for staged update content
        if [[ -d "${prebootPath}/cryptex1" ]]; then
            local cryptexSize=$(sudo du -sk "${prebootPath}/cryptex1" 2>/dev/null | awk '{print $1}')
            
            # Typical cryptex1 is < 1GB; if > 1GB, staging is very likely underway
            if [[ -n "${cryptexSize}" ]] && [[ ${cryptexSize} -gt 1048576 ]]; then
                stagedUpdateSize=$(echo "scale=2; ${cryptexSize} / 1048576" | bc)
                stagedUpdateLocation="${prebootPath}/cryptex1"
                stagedUpdateStatus="Fully staged"
                info "Staged update detected: ${stagedUpdateSize} GB in cryptex1"
            fi
        fi
        
        # Check restore-staged directory (optional supplemental assets)
        if [[ -d "${prebootPath}/restore-staged" ]]; then
            local restoreSize=$(sudo du -sk "${prebootPath}/restore-staged" 2>/dev/null | awk '{print $1}')
            if [[ -n "${restoreSize}" ]] && [[ ${restoreSize} -gt 102400 ]]; then
                local restoreSizeGB=$(echo "scale=2; ${restoreSize} / 1048576" | bc)
                info "Additional staged content: ${restoreSizeGB} GB in restore-staged"
            fi
        fi
        
        # Check total Preboot volume usage
        local totalPrebootSize=$(sudo du -sk "${prebootPath}" 2>/dev/null | awk '{print $1}')
        if [[ -n "${totalPrebootSize}" ]]; then
            local prebootGB=$(echo "scale=2; ${totalPrebootSize} / 1048576" | bc)
            
            # Typical Preboot is 1–3 GB; if > 8 GB, major update assets are staged
            if (( $(echo "${prebootGB} > 8" | bc -l) )); then
                if [[ "${stagedUpdateStatus}" != "Fully staged" ]]; then
                    stagedUpdateSize="${prebootGB}"
                    stagedUpdateLocation="${prebootPath}"
                    stagedUpdateStatus="Fully staged"
                    info "Large Preboot volume detected: ${prebootGB} GB total (threshold 8 GB)"
                fi
            fi
        fi
    fi
    
    # Export variables for use in dialog
    updateStagedSize="${stagedUpdateSize}"
    updateStagedLocation="${stagedUpdateLocation}"
    updateStagingStatus="${stagedUpdateStatus}"
    
    notice "Update Staging Status: ${stagedUpdateStatus}"
    if [[ "${stagedUpdateStatus}" == "Fully staged" ]]; then
        notice "Update Size: ${stagedUpdateSize} GB"
        notice "Location: ${stagedUpdateLocation}"
    fi

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

        # Read Apple’s internal padded enforcement date from install.log
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

    # Blurscreen logic and secondary button hiding (based on precise timestamp comparison)
    nowEpoch=$(date +%s)
    secondsUntilDeadline=$(( deadlineEpoch - nowEpoch ))
    blurThresholdSeconds=$(( daysBeforeDeadlineBlurscreen * 86400 ))
    hideButton2ThresholdSeconds=$(( daysBeforeDeadlineHidingButton2 * 86400 ))
    ddmVersionStringDaysRemaining=$(( (secondsUntilDeadline + 43200) / 86400 )) # Round to nearest whole day
    if (( secondsUntilDeadline <= blurThresholdSeconds )); then
        blurscreen="--blurscreen"
    else
        blurscreen="--noblurscreen"
    fi
    if (( secondsUntilDeadline <= hideButton2ThresholdSeconds )); then
        hideSecondaryButton="YES"
    else
        hideSecondaryButton="NO"
    fi

    # Version Comparison: Check if system meets DDM requirement
    if is-at-least "$ddmVersionString" "$installedmacOSVersion"; then

        versionComparisonResult="Up-to-date"
        info "DDM-enforced OS Version: $ddmVersionString"

    else

        versionComparisonResult="Update Required"

        # Detect staged updates
        if [[ "${hideStagedInfo}" == "YES" ]]; then
            notice "Skipping check for staged macOS updates. (The variable 'hideStagedInfo' is set to '${hideStagedInfo}'.)"
        else
            notice "Checking for staged macOS updates …"
            detectStagedUpdate
        fi

        # Determine if an "Update" or an "Upgrade" is needed
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
# Check User’s Display Sleep Assertions (thanks, @techtrekkie!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function checkUserDisplaySleepAssertions() {

    notice "Check ${loggedInUser}’s Display Sleep Assertions"

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
            info "${loggedInUser}’s Display Sleep Assertion has ended after $(( checkCount * intervalMinutes )) minute(s)."
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

function downloadBrandingAssets() {
    # Download overlay icon
    if [[ -n "${organizationOverlayiconURL}" ]]; then
        if curl -o "/var/tmp/overlayicon.png" "${organizationOverlayiconURL}" --silent --show-error --fail; then
            overlayicon="/var/tmp/overlayicon.png"
        else
            error "Failed to download overlayicon from '${organizationOverlayiconURL}'"
            overlayicon="/System/Library/CoreServices/Finder.app"
        fi
    else
        overlayicon="/System/Library/CoreServices/Finder.app"
    fi
    
    # Download macOS icon based on version
    local majorDDM="${ddmVersionString%%.*}"
    case ${majorDDM} in
        14) macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_eecee9688d1bc0426083d427d80c9ad48fa118b71d8d4962061d4de8d45747e7" ;;
        15) macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_0968afcd54ff99edd98ec6d9a418a5ab0c851576b687756dc3004ec52bac704e" ;;
        26) macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_7320c100c9ca155dc388e143dbc05620907e2d17d6bf74a8fb6d6278ece2c2b4" ;;
        *)  macOSIconURL="https://ics.services.jamfcloud.com/icon/hash_4555d9dc8fecb4e2678faffa8bdcf43cba110e81950e07a4ce3695ec2d5579ee" ;;
    esac
    
    if curl -o "/var/tmp/icon.png" "${macOSIconURL}" --silent --show-error --fail; then
        icon="/var/tmp/icon.png"
    else
        error "Failed to download icon from '${macOSIconURL}'"
        icon="/System/Library/CoreServices/Finder.app"
    fi
    
    # Swap icons if requested
    if [[ "${swapOverlayAndLogo}" == "YES" ]]; then
        local tmp="$icon"
        icon="$overlayicon"
        overlayicon="$tmp"
    fi
}

function computeDynamicWarnings() {
    # Excessive uptime warning
    local allowedUptimeMinutes=$(( daysOfExcessiveUptimeWarning * 1440 ))
    if (( upTimeMin < allowedUptimeMinutes )); then
        excessiveUptimeWarningMessage=""
    fi
    
    # Disk Space Warning
    if [[ -n "${freePercentage}" ]]; then
        local belowThreshold=$(echo "${freePercentage} < ${minimumDiskFreePercentage}" | bc)
        if [[ "${belowThreshold}" -ne 1 ]]; then
            diskSpaceWarningMessage=""
        fi
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

function updateRequiredVariables() {
    # Download branding assets
    downloadBrandingAssets
    
    # Set swiftDialog binary path
    dialogBinary="/usr/local/bin/dialog"
    
    # Set default action
    action="x-apple.systempreferences:com.apple.preferences.softwareupdate"
    
    # Compute dynamic values that depend on runtime state
    computeDynamicWarnings
    computeUpdateStagingMessage
    
    # Replace all placeholders in text fields
    local textFields=("title" "button1text" "button2text" "infobuttontext" "message" 
                      "infobox" "helpmessage" "helpimage" "excessiveUptimeWarningMessage" 
                      "diskSpaceWarningMessage")
    
    for field in "${textFields[@]}"; do
        replacePlaceholders "${field}"
    done
    
    # Apply visibility rules
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
        --messagefont "size=14"
        --width 800
        --height 625
        "${blurscreen}"
        "${additionalDialogOptions[@]}"
    )

    [[ -n "${button2text}" ]] && dialogArgs+=(--button2text "${button2text}")
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

            # Only re-display the reminder dialog when we are within the "hide secondary button" window (i.e., close to the deadline)
            if [[ "${hideSecondaryButton}" == "YES" ]]; then
                info "Within ${daysBeforeDeadlineHidingButton2} day(s) of deadline; waiting 61 seconds before re-showing dialog …"
                sleep 61
                displayReminderDialog --ontop --moveable
            else
                info "Deadline is more than ${daysBeforeDeadlineHidingButton2} day(s) away; not re-showing dialog after ${loggedInUser} clicked ${infobuttontext}."
            fi
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



####################################################################################################
#
# Apply Preference Overrides
#
####################################################################################################

loadPreferenceOverrides



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
    demoDeadlineOffsetDays=-3   # positive → future deadline; negative → past due
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
    deadlineEpoch=$(date -jf "%Y-%m-%dT%H:%M:%S" "${ddmVersionStringDeadline}" "+%s" 2>/dev/null)
    nowEpoch=$(date +%s)
    secondsUntilDeadline=$(( deadlineEpoch - nowEpoch ))
    blurThresholdSeconds=$(( daysBeforeDeadlineBlurscreen * 86400 ))
    hideButton2ThresholdSeconds=$(( daysBeforeDeadlineHidingButton2 * 86400 ))
    ddmVersionStringDaysRemaining=$(( (secondsUntilDeadline + 43200) / 86400 )) # Round to nearest whole day
    if (( secondsUntilDeadline <= blurThresholdSeconds )); then
        blurscreen="--blurscreen"
    else
        blurscreen="--noblurscreen"
    fi
    if (( secondsUntilDeadline <= hideButton2ThresholdSeconds )); then
        hideSecondaryButton="YES"
    else
        hideSecondaryButton="NO"
    fi
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

    # Simulate the update as already being fully staged in demo mode
    updateStagingStatus="Fully staged"

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

    # -------------------------------------------------------------------------
    # Skip reminder dialog if we're outside the defined window (thanks for the suggestion, @kristian!)
    # -------------------------------------------------------------------------

    if (( ddmVersionStringDaysRemaining > daysBeforeDeadlineDisplayReminder )); then
        quitOut "Deadline still ${ddmVersionStringDaysRemaining} days away; skipping reminder until within ${daysBeforeDeadlineDisplayReminder}-day window."
        quitScript "0"
    else
        notice "Within ${daysBeforeDeadlineDisplayReminder}-day reminder window; proceeding …"
    fi



    # -------------------------------------------------------------------------
    # Quiet period: skip dialog if shown recently
    # -------------------------------------------------------------------------

    quietPeriodSeconds=4560     # 76 minutes (60 minutes + margin)

    lastDialog=$( grep "Display Reminder Dialog" "${scriptLog}" | tail -1 | awk '{print $3" "$4}' )

    if [[ -n "${lastDialog}" ]]; then
        lastEpoch=$( date -j -f "%Y-%m-%d %H:%M:%S" "${lastDialog}" +"%s" 2>/dev/null )
        delta=$(( nowEpoch - lastEpoch ))
        if (( delta < quietPeriodSeconds )); then
            minutesAgo=$(( delta / 60 ))
            quitOut "Reminder dialog last displayed ${minutesAgo} minute(s) ago; exiting quietly."
            quitScript "0"
        fi
    else
        notice "Reminder dialog hasn't been shown within last $(( quietPeriodSeconds / 60 )) minutes; proceeding …"
    fi



    # -------------------------------------------------------------------------
    # Confirm the currently logged-in user is “available” to be reminded
    # -------------------------------------------------------------------------

    if [[ "${ddmVersionStringDaysRemaining}" -gt 1 ]]; then
        if checkUserDisplaySleepAssertions; then
            notice "No active Display Sleep Assertions detected; proceeding …"
        else
            quitOut "Presentation still active after ${meetingDelay} minutes; exiting quietly."
            quitScript "0"
        fi
    else
        info "Deadline is within 24 hours; ignoring ${loggedInUser}’s Display Sleep Assertions; proceeding …"
    fi


    # -------------------------------------------------------------------------
    # Random pause depending on launch context (hourly vs login)
    # -------------------------------------------------------------------------

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



    # -------------------------------------------------------------------------
    # Continue with normal processing
    # -------------------------------------------------------------------------

    updateRequiredVariables
    displayReminderDialog --ontop

else

    notice "Version Comparison Result: ${versionComparisonResult}"

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

quitScript "0"
