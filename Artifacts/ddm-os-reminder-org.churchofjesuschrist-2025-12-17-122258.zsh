#!/bin/zsh --no-rcs 
# shellcheck shell=bash

####################################################################################################
#
# DDM OS Reminder
# https://snelson.us/ddm
#
# Mac Admins’ new favorite, MDM-agnostic, “set-it-and-forget-it” end-user messaging for Apple’s
# Declarative Device Management-enforced macOS update deadlines.
#
# While Apple's Declarative Device Management (DDM) provides Mac Admins a powerful method to enforce
# macOS updates, its built-in notification tends to be too subtle for most Mac Admins.
#
# DDM OS Reminder evaluates the most recent `EnforcedInstallDate` and `setPastDuePaddedEnforcementDate`
# entries in `/var/log/install.log`, then leverages a swiftDialog-enabled script and LaunchDaemon pair
# to dynamically deliver a more prominent end-user message of when the user’s Mac needs to be updated
# to comply with DDM-enforced macOS update deadlines.
#
####################################################################################################
#
# HISTORY
#
# Version 2.2.0b11, 17-Dec-2025, Dan K. Snelson (@dan-snelson)
#   - Addressed Feature Request: Intelligently display reminder dialog after rebooting #42
#   - Added instructions for monitoring the client-side log
#   - `assemble.zsh` now outputs to `Artifacts/` (instead of `Resources/`)
#   - Updated `Resources/sample.plist` to address Feature Request #43
#   - Harmonized Organization Variables between `launchDaemonManagement.zsh` and `reminderDialog.zsh`
#   - Added Detection for staged macOS updates (Addresses Feature Request #49)
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="2.2.0b11"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Minimum Required Version of swiftDialog
swiftDialogMinimumRequiredVersion="2.5.6.4805"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# MDM Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Parameter 4: Configuration Files to Reset (i.e., None (blank) | All | LaunchDaemon | Script | Uninstall )
resetConfiguration="${4:-"All"}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Organization's Reverse Domain Name Notation (i.e., com.company.division; used for plist domains)
reverseDomainNameNotation="org.churchofjesuschrist"

# Script Human-readabale Name
humanReadableScriptName="DDM OS Reminder"

# Organization's Script Name
organizationScriptName="dor"

# Organization's Directory (i.e., where your client-side scripts reside)
organizationDirectory="/Library/Management/${reverseDomainNameNotation}"

# LaunchDaemon Name & Path
launchDaemonLabel="${reverseDomainNameNotation}.${organizationScriptName}"
launchDaemonPath="/Library/LaunchDaemons/${launchDaemonLabel}.plist"



####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo "${organizationScriptName}  ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" | tee -a "${scriptLog}"
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
# Reset Configuration
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function resetConfiguration() {

    notice "Reset Configuration: ${1}"

    # Ensure the directory exists
    mkdir -p "${organizationDirectory}"

    # Secure ownership
    chown -R root:wheel "${organizationDirectory}"

    # Secure directory permissions (no world-writable bits)
    [[ -d "${organizationDirectory}" ]] && chmod 755 "${organizationDirectory}"
    [[ -d "${organizationDirectory}/${reverseDomainNameNotation}" ]] && chmod 755 "${organizationDirectory}/${reverseDomainNameNotation}"

    case ${1} in

        "All" )

            info "Reset All Configuration Files … "

            # Reset LaunchDaemon
            info "Reset LaunchDaemon … "
            launchDaemonStatus
            if [[ -n "${launchDaemonStatus}" ]]; then
                logComment "Unload '${launchDaemonPath}' … "
                launchctl bootout system "${launchDaemonPath}"
                launchDaemonStatus
            fi
            logComment "Removing '${launchDaemonPath}' … "
            rm -f "${launchDaemonPath}" 2>&1
            logComment "Removed '${launchDaemonPath}'"

            # Reset Script
            info "Reset Script … "
            logComment "Removing '${organizationDirectory}/${organizationScriptName}.zsh' … "
            rm -f "${organizationDirectory}/${organizationScriptName}.zsh"
            logComment "Removed '${organizationDirectory}/${organizationScriptName}.zsh' "
            ;;

        "LaunchDaemon" )

            info "Reset LaunchDaemon … "
            launchDaemonStatus
            if [[ -n "${launchDaemonStatus}" ]]; then
                logComment "Unload '${launchDaemonPath}' … "
                launchctl bootout system "${launchDaemonPath}"
                launchDaemonStatus
            fi
            logComment "Removing '${launchDaemonPath}' … "
            rm -f "${launchDaemonPath}" 2>&1
            logComment "Removed '${launchDaemonPath}'"
            ;;

        "Script" )

            info "Reset Script … "
            logComment "Removing '${organizationDirectory}/${organizationScriptName}.zsh' … "
            rm -f "${organizationDirectory}/${organizationScriptName}.zsh"
            logComment "Removed '${organizationDirectory}/${organizationScriptName}.zsh' "
            ;;

        "Uninstall" )

            warning "*** UNINSTALLING ${humanReadableScriptName} ***"

            # Uninstall LaunchDaemon
            info "Uninstall LaunchDaemon … "
            launchDaemonStatus
            if [[ -n "${launchDaemonStatus}" ]]; then
                logComment "Unload '${launchDaemonPath}' … "
                launchctl bootout system "${launchDaemonPath}"
                launchDaemonStatus
            fi
            logComment "Removing '${launchDaemonPath}' … "
            rm -f "${launchDaemonPath}" 2>&1
            logComment "Removed '${launchDaemonPath}'"

            # Uninstall Script
            info "Uninstall Script … "
            logComment "Removing '${organizationDirectory}/${organizationScriptName}.zsh' … "
            rm -f "${organizationDirectory}/${organizationScriptName}.zsh"
            logComment "Removed '${organizationDirectory}/${organizationScriptName}.zsh' "

            # Remove legacy nested directory if it exists and is empty (pre-v1.3.0 cleanup)
            if [[ -d "${organizationDirectory}/${reverseDomainNameNotation}" ]]; then
                if [[ -z "$(ls -A "${organizationDirectory}/${reverseDomainNameNotation}")" ]]; then
                    logComment "Removing legacy nested directory: ${organizationDirectory}/${reverseDomainNameNotation}"
                    rmdir "${organizationDirectory}/${reverseDomainNameNotation}"
                    logComment "Removed legacy nested directory"
                else
                    logComment "Legacy nested directory not empty; leaving intact: ${organizationDirectory}/${reverseDomainNameNotation}"
                fi
            fi

            # Remove organization directory if empty
            if [[ -d "${organizationDirectory}" ]]; then
                if [[ -z "$(ls -A "${organizationDirectory}")" ]]; then
                    logComment "Removing empty organization directory: ${organizationDirectory}"
                    rmdir "${organizationDirectory}"
                    logComment "Removed empty organization directory"
                else
                    logComment "Organization directory not empty; other management files may still exist — leaving intact: ${organizationDirectory}"
                fi
            fi

            # Exit
            logComment "Uninstalled all ${humanReadableScriptName} configuration files"
            notice "Thanks for trying ${humanReadableScriptName}!"
            exit 0
            ;;
            
        * )

            warning "None of the expected reset options was entered; don't reset anything"
            ;;

    esac

}

function createDDMOSReminderScript() {

    notice "Create '${humanReadableScriptName}' script: ${organizationDirectory}/${organizationScriptName}.zsh"

(
cat <<'ENDOFSCRIPT'
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
scriptVersion="2.2.0b11"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Load is-at-least for version comparison
autoload -Uz is-at-least



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Script Human-readable Name
humanReadableScriptName="DDM OS Reminder End-user Message"

# Organization's reverse domain (used for plist domains)
reverseDomainNameNotation="org.churchofjesuschrist"

# Organization's Script Name
organizationScriptName="dorm"

# Preference plist domains
preferenceDomain="${reverseDomainNameNotation}.${organizationScriptName}"
managedPreferencesPlist="/Library/Managed Preferences/${preferenceDomain}"
localPreferencesPlist="/Library/Preferences/${preferenceDomain}"

# Organization's number of days before deadline to starting displaying reminders
daysBeforeDeadlineDisplayReminder="60"

# Organization's number of days before deadline to enable swiftDialog's blurscreen
daysBeforeDeadlineBlurscreen="45"

# Organization's number of days before deadline to hide the secondary button
daysBeforeDeadlineHidingButton2="21"

# Organization's number of days of excessive uptime before warning the user
daysOfExcessiveUptimeWarning="0"

# Organization's minimum percentage of free disk space required for update
minimumDiskFreePercentage="99"

# Organization's Meeting Delay (in minutes) 
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



####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo "${organizationScriptName} ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" # | tee -a "${scriptLog}"
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

    # Handle both {placeholder} from plist and \{placeholder\} from inline defaults
    value=${value//\{weekday\}/$( date +'%A' )}
    value=${value//'{weekday}'/$( date +'%A' )}
    value=${value//\{userfirstname\}/${loggedInUserFirstname}}
    value=${value//'{userfirstname}'/${loggedInUserFirstname}}
    value=${value//\{loggedInUserFirstname\}/${loggedInUserFirstname}}
    value=${value//'{loggedInUserFirstname}'/${loggedInUserFirstname}}
    value=${value//\{ddmVersionString\}/${ddmVersionString}}
    value=${value//'{ddmVersionString}'/${ddmVersionString}}
    value=${value//\{ddmEnforcedInstallDateHumanReadable\}/${ddmEnforcedInstallDateHumanReadable}}
    value=${value//'{ddmEnforcedInstallDateHumanReadable}'/${ddmEnforcedInstallDateHumanReadable}}
    value=${value//\{installedmacOSVersion\}/${installedmacOSVersion}}
    value=${value//'{installedmacOSVersion}'/${installedmacOSVersion}}
    value=${value//\{ddmVersionStringDeadlineHumanReadable\}/${ddmVersionStringDeadlineHumanReadable}}
    value=${value//'{ddmVersionStringDeadlineHumanReadable}'/${ddmVersionStringDeadlineHumanReadable}}
    value=${value//\{ddmVersionStringDaysRemaining\}/${ddmVersionStringDaysRemaining}}
    value=${value//'{ddmVersionStringDaysRemaining}'/${ddmVersionStringDaysRemaining}}
    value=${value//\{titleMessageUpdateOrUpgrade\}/${titleMessageUpdateOrUpgrade}}
    value=${value//'{titleMessageUpdateOrUpgrade}'/${titleMessageUpdateOrUpgrade}}
    value=${value//\{titleMessageUpdateOrUpgrade:l\}/${titleMessageUpdateOrUpgrade:l}}
    value=${value//'{titleMessageUpdateOrUpgrade:l}'/${titleMessageUpdateOrUpgrade:l}}
    value=${value//\{uptimeHumanReadable\}/${uptimeHumanReadable}}
    value=${value//'{uptimeHumanReadable}'/${uptimeHumanReadable}}
    value=${value//\{excessiveUptimeWarningMessage\}/${excessiveUptimeWarningMessage}}
    value=${value//'{excessiveUptimeWarningMessage}'/${excessiveUptimeWarningMessage}}
    value=${value//\{updateReadyMessage\}/${updateReadyMessage}}
    value=${value//'{updateReadyMessage}'/${updateReadyMessage}}
    value=${value//\{diskSpaceHumanReadable\}/${diskSpaceHumanReadable}}
    value=${value//'{diskSpaceHumanReadable}'/${diskSpaceHumanReadable}}
    value=${value//\{diskSpaceWarningMessage\}/${diskSpaceWarningMessage}}
    value=${value//'{diskSpaceWarningMessage}'/${diskSpaceWarningMessage}}
    value=${value//\{softwareUpdateButtonText\}/${softwareUpdateButtonText}}
    value=${value//'{softwareUpdateButtonText}'/${softwareUpdateButtonText}}
    value=${value//\{button1text\}/${button1text}}
    value=${value//'{button1text}'/${button1text}}
    value=${value//\{button2text\}/${button2text}}
    value=${value//'{button2text}'/${button2text}}
    value=${value//\{supportTeamName\}/${supportTeamName}}
    value=${value//'{supportTeamName}'/${supportTeamName}}
    value=${value//\{supportTeamPhone\}/${supportTeamPhone}}
    value=${value//'{supportTeamPhone}'/${supportTeamPhone}}
    value=${value//\{supportTeamEmail\}/${supportTeamEmail}}
    value=${value//'{supportTeamEmail}'/${supportTeamEmail}}
    value=${value//\{supportTeamWebsite\}/${supportTeamWebsite}}
    value=${value//'{supportTeamWebsite}'/${supportTeamWebsite}}
    value=${value//\{supportKBURL\}/${supportKBURL}}
    value=${value//'{supportKBURL}'/${supportKBURL}}
    value=${value//\{supportKB\}/${supportKB}}
    value=${value//'{supportKB}'/${supportKB}}
    value=${value//\{infobuttonaction\}/${infobuttonaction}}
    value=${value//'{infobuttonaction}'/${infobuttonaction}}
    value=${value//\{dialogVersion\}/$(/usr/local/bin/dialog -v 2>/dev/null)}
    value=${value//'{dialogVersion}'/$(/usr/local/bin/dialog -v 2>/dev/null)}
    value=${value//\{scriptVersion\}/${scriptVersion}}
    value=${value//'{scriptVersion}'/${scriptVersion}}

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

function loadPreferenceOverrides() {
    if [[ -f ${managedPreferencesPlist}.plist ]]; then
        scriptLog_managed=$(defaults read "${managedPreferencesPlist}" ScriptLog 2> /dev/null)
        daysBeforeDeadlineDisplayReminder_managed=$(defaults read "${managedPreferencesPlist}" DaysBeforeDeadlineDisplayReminder 2> /dev/null)
        daysBeforeDeadlineBlurscreen_managed=$(defaults read "${managedPreferencesPlist}" DaysBeforeDeadlineBlurscreen 2> /dev/null)
        daysBeforeDeadlineHidingButton2_managed=$(defaults read "${managedPreferencesPlist}" DaysBeforeDeadlineHidingButton2 2> /dev/null)
        daysOfExcessiveUptimeWarning_managed=$(defaults read "${managedPreferencesPlist}" DaysOfExcessiveUptimeWarning 2> /dev/null)
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
        excessiveUptimeWarningMessage_managed=$(defaults read "${managedPreferencesPlist}" ExcessiveUptimeWarningMessage 2> /dev/null)
        minimumDiskFreePercentage_managed=$(defaults read "${managedPreferencesPlist}" MinimumDiskFreePercentage 2> /dev/null)
        diskSpaceWarningMessage_managed=$(defaults read "${managedPreferencesPlist}" DiskSpaceWarningMessage 2> /dev/null)
        message_managed=$(defaults read "${managedPreferencesPlist}" Message 2> /dev/null)
        infobuttontext_managed=$(defaults read "${managedPreferencesPlist}" InfoButtonText 2> /dev/null)
        infobox_managed=$(defaults read "${managedPreferencesPlist}" InfoBox 2> /dev/null)
        helpmessage_managed=$(defaults read "${managedPreferencesPlist}" HelpMessage 2> /dev/null)
        helpimage_managed=$(defaults read "${managedPreferencesPlist}" HelpImage 2> /dev/null)
        stagedUpdateMessage_managed=$(defaults read "${managedPreferencesPlist}" StagedUpdateMessage 2>/dev/null)
        partiallyStagedUpdateMessage_managed=$(defaults read "${managedPreferencesPlist}" PartiallyStagedUpdateMessage 2>/dev/null)
        pendingDownloadMessage_managed=$(defaults read "${managedPreferencesPlist}" PendingDownloadMessage 2>/dev/null)
        hideStagedInfo_managed=$(defaults read "${managedPreferencesPlist}" HideStagedUpdateInfo 2>/dev/null)
    fi

    if [[ -f ${localPreferencesPlist}.plist ]]; then
        scriptLog_local=$(defaults read "${localPreferencesPlist}" ScriptLog 2> /dev/null)
        daysBeforeDeadlineDisplayReminder_local=$(defaults read "${localPreferencesPlist}" DaysBeforeDeadlineDisplayReminder 2> /dev/null)
        daysBeforeDeadlineBlurscreen_local=$(defaults read "${localPreferencesPlist}" DaysBeforeDeadlineBlurscreen 2> /dev/null)
        daysBeforeDeadlineHidingButton2_local=$(defaults read "${localPreferencesPlist}" DaysBeforeDeadlineHidingButton2 2> /dev/null)
        daysOfExcessiveUptimeWarning_local=$(defaults read "${localPreferencesPlist}" DaysOfExcessiveUptimeWarning 2> /dev/null)
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
        excessiveUptimeWarningMessage_local=$(defaults read "${localPreferencesPlist}" ExcessiveUptimeWarningMessage 2> /dev/null)
        minimumDiskFreePercentage_local=$(defaults read "${localPreferencesPlist}" MinimumDiskFreePercentage 2> /dev/null)
        diskSpaceWarningMessage_local=$(defaults read "${localPreferencesPlist}" DiskSpaceWarningMessage 2> /dev/null)
        message_local=$(defaults read "${localPreferencesPlist}" Message 2> /dev/null)
        infobuttontext_local=$(defaults read "${localPreferencesPlist}" InfoButtonText 2> /dev/null)
        infobox_local=$(defaults read "${localPreferencesPlist}" InfoBox 2> /dev/null)
        helpmessage_local=$(defaults read "${localPreferencesPlist}" HelpMessage 2> /dev/null)
        helpimage_local=$(defaults read "${localPreferencesPlist}" HelpImage 2> /dev/null)
        stagedUpdateMessage_local=$(defaults read "${localPreferencesPlist}" StagedUpdateMessage 2>/dev/null)
        partiallyStagedUpdateMessage_local=$(defaults read "${localPreferencesPlist}" PartiallyStagedUpdateMessage 2>/dev/null)
        pendingDownloadMessage_local=$(defaults read "${localPreferencesPlist}" PendingDownloadMessage 2>/dev/null)
        hideStagedInfo_local=$(defaults read "${localPreferencesPlist}" HideStagedUpdateInfo 2>/dev/null)
    fi
    setPreferenceValue "scriptLog" "${scriptLog_managed}" "${scriptLog_local}" "${scriptLog}"
    setNumericPreferenceValue "daysBeforeDeadlineDisplayReminder" "${daysBeforeDeadlineDisplayReminder_managed}" "${daysBeforeDeadlineDisplayReminder_local}" "${daysBeforeDeadlineDisplayReminder}"
    setNumericPreferenceValue "daysBeforeDeadlineBlurscreen" "${daysBeforeDeadlineBlurscreen_managed}" "${daysBeforeDeadlineBlurscreen_local}" "${daysBeforeDeadlineBlurscreen}"
    setNumericPreferenceValue "daysBeforeDeadlineHidingButton2" "${daysBeforeDeadlineHidingButton2_managed}" "${daysBeforeDeadlineHidingButton2_local}" "${daysBeforeDeadlineHidingButton2}"
    setNumericPreferenceValue "daysOfExcessiveUptimeWarning" "${daysOfExcessiveUptimeWarning_managed}" "${daysOfExcessiveUptimeWarning_local}" "${daysOfExcessiveUptimeWarning}"
    setNumericPreferenceValue "meetingDelay" "${meetingDelay_managed}" "${meetingDelay_local}" "${meetingDelay}"
    setNumericPreferenceValue "minimumDiskFreePercentage" "${minimumDiskFreePercentage_managed}" "${minimumDiskFreePercentage_local}" "${minimumDiskFreePercentage}"
    setPreferenceValue "diskSpaceWarningMessage" "${diskSpaceWarningMessage_managed}" "${diskSpaceWarningMessage_local}" "${diskSpaceWarningMessage}"
    setPreferenceValue "swapOverlayAndLogo" "${swapOverlayAndLogo_managed}" "${swapOverlayAndLogo_local}" "${swapOverlayAndLogo}"
    setPreferenceValue "hideStagedInfo" "${hideStagedInfo_managed}" "${hideStagedInfo_local}" "NO"
    setPreferenceValue "dateFormatDeadlineHumanReadable" "${dateFormatDeadlineHumanReadable_managed}" "${dateFormatDeadlineHumanReadable_local}" "${dateFormatDeadlineHumanReadable}"
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

    # Version Comparison for pending DDM-enforced update
    if is-at-least "$ddmVersionString" "$installedmacOSVersion"; then

        versionComparisonResult="Up-to-date"
        info "DDM-enforced OS Version: $ddmVersionString"

    else

        versionComparisonResult="Update Required"

        # Detect staged updates
        detectStagedUpdate

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
    local defaultOverlayiconURL="${organizationOverlayiconURL:-"https://usw2.ics.services.jamfcloud.com/icon/hash_4804203ac36cbd7c83607487f4719bd4707f2e283500f54428153af17da082e2"}"
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

    local defaultSupportKB="${supportKB:-"108382"}"
    setPreferenceValue "supportKB" "${supportKB_managed}" "${supportKB_local}" "${defaultSupportKB}"

    local defaultInfobuttonaction="https://support.apple.com/${supportKB}"
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

    # Excessive Uptime Warning
    local defaultExcessiveUptimeWarningMessage="${excessiveUptimeWarningMessage:-"<br><br>**Note:** Your Mac has been powered-on for **${uptimeHumanReadable}**. For more reliable results, please manually restart your Mac before proceeding."}"
    setPreferenceValue "excessiveUptimeWarningMessage" "${excessiveUptimeWarningMessage_managed}" "${excessiveUptimeWarningMessage_local}" "${defaultExcessiveUptimeWarningMessage}"
    replacePlaceholders "excessiveUptimeWarningMessage"

    local allowedUptimeMinutes=$(( daysOfExcessiveUptimeWarning * 1440 ))
    if (( upTimeMin < allowedUptimeMinutes )); then
        unset "excessiveUptimeWarningMessage"
    fi

    # Disk Space Warning
    if [[ -n "${freePercentage}" ]]; then
        belowThreshold=$(echo "${freePercentage} < ${minimumDiskFreePercentage}" | bc)
        if [[ "${belowThreshold}" -eq 1 ]]; then
            diskSpaceWarningMessage="<br><br>**Note:** Your Mac has only **${diskSpaceHumanReadable}**, which may prevent this macOS ${titleMessageUpdateOrUpgrade:l}."
        else
            unset "diskSpaceWarningMessage"
        fi
    fi

    # Staged Update Messaging
    local defaultStagedUpdateMessage="<br><br>**Good news!** The macOS ${ddmVersionString} update has already been downloaded to your Mac and is ready to install. Installation will proceed quickly when you click **${button1text}**."
    local defaultPartiallyStagedUpdateMessage="<br><br>Your Mac has begun downloading and preparing required macOS update components. Installation will be quicker once all assets have finished staging."
    local defaultPendingDownloadMessage=""

    # Load preferences (manager > local > default)
    setPreferenceValue "stagedUpdateMessage" "${stagedUpdateMessage_managed}" "${stagedUpdateMessage_local}" "${defaultStagedUpdateMessage}"
    setPreferenceValue "partiallyStagedUpdateMessage" "${partiallyStagedUpdateMessage_managed}" "${partiallyStagedUpdateMessage_local}" "${defaultPartiallyStagedUpdateMessage}"
    setPreferenceValue "pendingDownloadMessage" "${pendingDownloadMessage_managed}" "${pendingDownloadMessage_local}" "${defaultPendingDownloadMessage}"

    # Honor HideStagedUpdateInfo flag
    if [[ "${hideStagedInfo}" == "1" ]]; then
        updateReadyMessage=""
    else
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
    fi

    local defaultMessage="**A required macOS ${titleMessageUpdateOrUpgrade:l} is now available**<br><br>Happy $( date +'%A' ), ${loggedInUserFirstname}!<br><br>Please ${titleMessageUpdateOrUpgrade:l} to macOS **${ddmVersionString}** to ensure your Mac remains secure and compliant with organizational policies.${updateReadyMessage}<br><br>To perform the ${titleMessageUpdateOrUpgrade:l} now, click **${button1text}**, review the on-screen instructions, then click **${softwareUpdateButtonText}**.<br><br>If you are unable to perform this ${titleMessageUpdateOrUpgrade:l} now, click **${button2text}** to be reminded again later.<br><br>However, your device **will automatically restart and ${titleMessageUpdateOrUpgrade:l}** on **${ddmEnforcedInstallDateHumanReadable}** if you have not ${titleMessageUpdateOrUpgrade:l}d before the deadline.${excessiveUptimeWarningMessage}${diskSpaceWarningMessage}<br><br>For assistance, please contact **${supportTeamName}** by clicking the (?) button in the bottom, right-hand corner."
    if [[ -n "${updateReadyMessage}" && "${message}" == *"{updateReadyMessage}"* ]]; then
        message=${message//\{updateReadyMessage\}/${updateReadyMessage}}
    fi
    setPreferenceValue "message" "${message_managed}" "${message_local}" "${defaultMessage}"
    replacePlaceholders "message"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Infobox Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    local defaultInfobox="**Current:** macOS ${installedmacOSVersion}<br><br>**Required:** macOS ${ddmVersionString}<br><br>**Deadline:** ${ddmVersionStringDeadlineHumanReadable}<br><br>**Day(s) Remaining:** ${ddmVersionStringDaysRemaining}<br><br>**Last Restart:** ${uptimeHumanReadable}<br><br>**Free Disk Space:** ${diskSpaceHumanReadable}"
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
        --messagefont "size=14"
        --width 800
        --height 600
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
        info "Deadline is within 24 hours; ignoring ${loggedInUser}'s Display Sleep Assertions; proceeding …"
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

ENDOFSCRIPT
) > "${organizationDirectory}/${organizationScriptName}.zsh"

    logComment "${humanReadableScriptName} script created"

    logComment "Setting permissions …"
    chown root:wheel "${organizationDirectory}/${organizationScriptName}.zsh"
    chmod 755 "${organizationDirectory}/${organizationScriptName}.zsh"
    chmod +x "${organizationDirectory}/${organizationScriptName}.zsh"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# CREATE LAUNCHDAEMON
#
#   The following function creates the LaunchDaemon which executes the previously created
#   client-side DDM OS Reminder script.
#
#   We've elected to prompt our users twice a day (8 a.m. and 4 p.m.) to ensure they see the message.
#
#   NOTE: Leave a full return at the end of the content before the "ENDOFLAUNCHDAEMON" line.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function createLaunchDaemon() {

    notice "Create LaunchDaemon"

    logComment "Creating '${launchDaemonPath}' …"

(
cat <<ENDOFLAUNCHDAEMON
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${launchDaemonLabel}</string>
    <key>UserName</key>
    <string>root</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>${organizationDirectory}/${organizationScriptName}.zsh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin</string>
    </dict>
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Hour</key>
            <integer>8</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>16</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
    </array>
    <key>StandardErrorPath</key>
    <string>${scriptLog}</string>
    <key>StandardOutPath</key>
    <string>${scriptLog}</string>
</dict>
</plist>

ENDOFLAUNCHDAEMON
)  > "${launchDaemonPath}"

    logComment "Setting permissions for '${launchDaemonPath}' …"
    chmod 644 "${launchDaemonPath}"
    chown root:wheel "${launchDaemonPath}"

    logComment "Loading '${launchDaemonLabel}' …"
    launchctl bootstrap system "${launchDaemonPath}"
    launchctl start "${launchDaemonPath}"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LaunchDaemon Status
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function launchDaemonStatus() {

    notice "LaunchDaemon Status"
    
    launchDaemonStatus=$( launchctl list | grep "${launchDaemonLabel}" )

    if [[ -n "${launchDaemonStatus}" ]]; then
        logComment "${launchDaemonStatus}"
    else
        logComment "${launchDaemonLabel} is NOT loaded"
    fi

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
        fatal "Unable to create specified scriptLog '${scriptLog}'; exiting.

(Is this script running as 'root' ?)"
    fi
else
    # preFlight "Specified scriptLog '${scriptLog}' exists; writing log entries to it"
fi




# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "

###
# $humanReadableScriptName (${scriptVersion})
# http://snelson.us/ddm
#
# Reset Configuration: ${resetConfiguration}
###
"
preFlight "Initiating …"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(id -u) -ne 0 ]]; then
    fatal "This script must be run as root; exiting."
fi


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate / install swiftDialog (Thanks big bunches, @acodega!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function dialogInstall() {

    # Get the URL of the latest PKG From the Dialog GitHub repo
    dialogURL=$(curl -L --silent --fail "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    preFlight "Installing swiftDialog..."

    # Create temporary working directory
    workDirectory=$( basename "$0" )
    tempDirectory=$( mktemp -d "/private/tmp/$workDirectory.XXXXXX" )

    # Download the installer package
    curl --location --silent "$dialogURL" -o "$tempDirectory/Dialog.pkg"

    # Verify the download
    teamID=$(spctl -a -vv -t install "$tempDirectory/Dialog.pkg" 2>&1 | awk '/origin=/ {print $NF }' | tr -d '()')

    # Install the package if Team ID validates
    if [[ "$expectedDialogTeamID" == "$teamID" ]]; then

        installer -pkg "$tempDirectory/Dialog.pkg" -target /
        sleep 2
        dialogVersion=$( /usr/local/bin/dialog --version )
        preFlight "swiftDialog version ${dialogVersion} installed; proceeding..."

    else

        # Display a so-called "simple" dialog if Team ID fails to validate
        osascript -e 'display dialog "Please advise your Support Representative of the following error:• Dialog Team ID verification failed" with title "DDM OS Reminder Error" buttons {"Close"} with icon caution'
        exit "1"

    fi

    # Remove the temporary working directory when done
    rm -Rf "$tempDirectory"

}



function dialogCheck() {

    # Check for Dialog and install if not found
    if [ ! -x "/Library/Application Support/Dialog/Dialog.app" ]; then

        preFlight "swiftDialog not found. Installing..."
        dialogInstall

    else

        dialogVersion=$(/usr/local/bin/dialog --version)
        if [[ "${dialogVersion}" < "${swiftDialogMinimumRequiredVersion}" ]]; then
            
            preFlight "swiftDialog version ${dialogVersion} found but swiftDialog ${swiftDialogMinimumRequiredVersion} or newer is required; updating..."
            dialogInstall
            
        else

            preFlight "swiftDialog version ${dialogVersion} found; proceeding..."

        fi
    
    fi

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Complete
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "Complete!"



####################################################################################################
#
# Program
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate / install swiftDialog
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

dialogCheck



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Reset Configuration
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

resetConfiguration "${resetConfiguration}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Validation / Creation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "Validating Script"

if [[ -f "${organizationDirectory}/${organizationScriptName}.zsh" ]]; then

    logComment "${humanReadableScriptName} script '"${organizationDirectory}/${organizationScriptName}.zsh"' exists"

else

    createDDMOSReminderScript

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LaunchDaemon Validation / Creation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "Validating LaunchDaemon"

logComment "Checking for LaunchDaemon '${launchDaemonPath}' …"

if [[ -f "${launchDaemonPath}" ]]; then

    logComment "LaunchDaemon '${launchDaemonPath}' exists"

    launchDaemonStatus

    if [[ -n "${launchDaemonStatus}" ]]; then

        logComment "${launchDaemonLabel} IS loaded"

    else

        logComment "Loading '${launchDaemonLabel}' …"
        launchctl asuser $(id -u) bootstrap gui/$(id -u) "${launchDaemonPath}"
        launchDaemonStatus

    fi

else

    createLaunchDaemon

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Status Checks
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "Status Checks"

logComment "I/O pause …"
sleep 1.3

launchDaemonStatus



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

quitOut "Completed ${reverseDomainNameNotation}.${organizationScriptName} LaunchDaemon"
quitOut "Monitor the client-side log via:"
quitOut "tail -f ${scriptLog}"

exit 0
