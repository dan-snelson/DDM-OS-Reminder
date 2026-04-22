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
# DDM OS Reminder evaluates recent DDM declaration state in `/var/log/install.log`, prefers the most
# authoritative declaration entries, safely handles padded enforcement dates, and leverages a
# swiftDialog-enabled script and LaunchDaemon pair to dynamically deliver a more prominent end-user
# message of when the user’s Mac needs to be updated to comply with DDM-enforced macOS update deadlines.
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="3.2.0b2"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Minimum Required Version of swiftDialog
swiftDialogMinimumRequiredVersion="2.5.6.4805"

# Load is-at-least for version comparison
autoload -Uz is-at-least



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# MDM Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Parameter 4: Configuration Files to Reset (i.e., None (blank) | All | LaunchDaemon | Script | Uninstall )
resetConfiguration="${4:-"All"}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Organization’s Script Human-readable Name
humanReadableScriptName="DDM OS Reminder"

# Organization’s Reverse Domain Name Notation (i.e., com.company.division; used for plist domains)
reverseDomainNameNotation="org.churchofjesuschrist"

# Organization’s Script Name
organizationScriptName="dor"

# Organization’s Directory (i.e., where your client-side scripts reside)
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
            if [[ -n "${launchDaemonStatusResult}" ]]; then
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
            if [[ -n "${launchDaemonStatusResult}" ]]; then
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
            if [[ -n "${launchDaemonStatusResult}" ]]; then
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
scriptVersion="3.2.0b2"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Install.log parsing
# `installLogPathOverride` is an internal fixture-testing hook for local validation only.
# It is not a supported admin preference or deployment setting.
installLogPath="${installLogPathOverride:-/var/log/install.log}"
ddmResolverLookbackLines=4000
ddmResolverStatus=""
ddmResolverReason=""
ddmResolverSource=""
ddmResolverSuppressionType=""
ddmDeclarationLogTimestamp=""
ddmDeclarationRawLine=""
ddmBuildVersionString=""
ddmResolvedPaddedEpoch=""
ddmResolvedPaddedRawLine=""
ddmResolverFailureMarker=""
ddmResolverConflictSummary=""
ddmLogTimestampRegex='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}$'
typeset -ga ddmRecentInstallLogWindow=()

# Load is-at-least for version comparison
autoload -Uz is-at-least



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Organization’s Script Human-readable Name
humanReadableScriptName="DDM OS Reminder End-user Message"

# Organization’s Reverse Domain Name Notation (i.e., com.company.division; used for plist domains)
reverseDomainNameNotation="org.churchofjesuschrist"

# Organization’s Script Name
organizationScriptName="dorm"

# Preference plist domains
preferenceDomain="${reverseDomainNameNotation}.${organizationScriptName}"
managedPreferencesPlist="/Library/Managed Preferences/${preferenceDomain}"
localPreferencesPlist="/Library/Preferences/${preferenceDomain}"

# Disable button2 (instead of hiding it when approaching deadline)
# Set to "YES" to disable button2 (shows greyed out), "NO" to hide it (previous behavior)
disableButton2InsteadOfHide="YES"

# NOTE: All configurable preferences (days to deadline, blurscreen threshold, disk
# space, meeting delay, format strings, icons, etc.) are now defined in the
# preferenceConfiguration map below and loaded via loadPreferenceOverrides()
# to support managed and local plist overrides.

# Past Deadline runtime state
pastDeadlineForceTimerSeconds=60
pastDeadlineRedisplayDelaySeconds=5
pastDeadlineRestartEffective="Off"
pastDeadlineRestartMinimumUptimeMinutes=75
pastDeadlineRestartSuppressedForUptime="NO"
dialogLanguage="en"
declare -A preferenceExplicitlySet=()



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Uptime Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

lastBootTime=$( sysctl kern.boottime | awk -F'[ |,]' '{print $5}' )
currentTime=$( date +"%s" )
upTimeRaw=$((currentTime-lastBootTime))
upTimeMin=$((upTimeRaw/60))
upTimeDays=$((upTimeMin / 1440))
upTimeHoursRemainder=$(((upTimeMin % 1440) / 60))
upTimeMinutesRemainder=$((upTimeMin % 60))
uptimeHumanReadable=""

if [[ "${upTimeDays}" -gt 0 ]]; then
    if [[ "${upTimeDays}" -eq 1 ]]; then
        uptimeHumanReadable="1 day"
    else
        uptimeHumanReadable="${upTimeDays} days"
    fi
fi

if [[ "${upTimeHoursRemainder}" -gt 0 ]]; then
    if [[ -n "${uptimeHumanReadable}" ]]; then
        uptimeHumanReadable="${uptimeHumanReadable}, "
    fi

    if [[ "${upTimeHoursRemainder}" -eq 1 ]]; then
        uptimeHumanReadable="${uptimeHumanReadable}1 hour"
    else
        uptimeHumanReadable="${uptimeHumanReadable}${upTimeHoursRemainder} hours"
    fi
fi

if [[ "${upTimeMinutesRemainder}" -gt 0 ]]; then
    if [[ -n "${uptimeHumanReadable}" ]]; then
        uptimeHumanReadable="${uptimeHumanReadable}, "
    fi

    if [[ "${upTimeMinutesRemainder}" -eq 1 ]]; then
        uptimeHumanReadable="${uptimeHumanReadable}1 minute"
    else
        uptimeHumanReadable="${uptimeHumanReadable}${upTimeMinutesRemainder} minutes"
    fi
fi

if [[ -z "${uptimeHumanReadable}" ]]; then
    uptimeHumanReadable="less than 1 minute"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Free Disk Space Variables (inspired by Mac Health Check)
# Prefer Finder-aligned available capacity when JXA returns sane values (thanks, @huexley!);
# fall back to diskutil when the Foundation query is unavailable or reports 0.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

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



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Preference Configuration Map
# - Format: key|type|defaultValue
# - Types: string, numeric, boolean
# - String values can contain URLs, text, markdown, or placeholders like {ddmVersionString}
# - Numeric values are integers 0-999 (days, minutes, percentages, etc.)
# - Boolean values accept: 1/true/yes/YES → "YES"; 0/false/no/NO → "NO"
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

declare -A preferenceConfiguration=(
    # Logging and Timing
    ["scriptLog"]="string|/var/log/org.churchofjesuschrist.log"
    ["daysBeforeDeadlineDisplayReminder"]="numeric|60"
    ["daysBeforeDeadlineBlurscreen"]="numeric|45"
    ["daysBeforeDeadlineHidingButton2"]="numeric|21"
    ["daysOfExcessiveUptimeWarning"]="numeric|0"
    ["daysPastDeadlineRestartWorkflow"]="numeric|2"
    ["pastDeadlineRestartBehavior"]="string|Off"
    ["meetingDelay"]="numeric|75"
    ["acceptableAssertionApplicationNames"]="string|MSTeams zoom.us Webex"
    ["minimumDiskFreePercentage"]="numeric|99"
    
    # Branding
    ["organizationOverlayiconURL"]="string|https://use2.ics.services.jamfcloud.com/icon/hash_2d64ce7f0042ad68234a2515211adb067ad6714703dd8ebd6f33c1ab30354b1d"
    ["organizationOverlayiconURLdark"]="string|https://use2.ics.services.jamfcloud.com/icon/hash_d3a3bc5e06d2db5f9697f9b4fa095bfecb2dc0d22c71aadea525eb38ff981d39"
    ["swapOverlayAndLogo"]="boolean|NO"
    ["dateFormatDeadlineHumanReadable"]="string|+%a, %d-%b-%Y, %-l:%M %p"
    
    # Support Team
    ["supportTeamName"]="string|IT Support"
    ["supportTeamPhone"]="string|+1 (801) 555-1212"
    ["supportTeamEmail"]="string|rescue@domain.org"
    ["supportTeamWebsite"]="string|https://support.domain.org"
    ["supportKB"]="string|Update macOS on Mac"
    ["infobuttonaction"]="string|https://support.apple.com/108382"
    ["supportKBURL"]="string|[Update macOS on Mac](https://support.apple.com/108382)"
    ["supportAssistanceMessage"]="string|<br><br>For assistance, please contact **{supportTeamName}** by clicking the (?) button in the bottom, right-hand corner."
    
    # Localization
    ["languageOverride"]="string|auto"
    
    # UI Text
    ["title"]="string|macOS {titleMessageUpdateOrUpgrade} Required"
    ["button1text"]="string|Open Software Update"
    ["button2text"]="string|Remind Me Later"
    ["infobuttontext"]="string|Update macOS on Mac"
    ["excessiveUptimeWarningMessage"]="string|<br><br>**Note:** Your Mac has been powered-on for **{uptimeHumanReadable}**. For more reliable results, please manually restart your Mac before proceeding."
    ["diskSpaceWarningMessage"]="string|<br><br>**Note:** Your Mac has only **{diskSpaceHumanReadable}**, which may prevent this macOS {titleMessageUpdateOrUpgrade:l}."
    
    # Update Staging Messages
    ["stagedUpdateMessage"]="string|<br><br>**Good news!** The macOS {ddmVersionString} update has already been downloaded to your Mac and is ready to install. Installation will proceed quickly when you click **{button1text}**."
    ["partiallyStagedUpdateMessage"]="string|<br><br>Your Mac has begun downloading and preparing required macOS update components. Installation will be quicker once all assets have finished staging."
    ["pendingDownloadMessage"]="string|<br><br>Your Mac will begin downloading the update shortly."
    ["hideStagedInfo"]="boolean|NO"

    # Dynamic Localization Primitives
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
    ["pastDeadlinePromptTitle"]="string|Restart Your Mac"
    ["pastDeadlinePromptMessage"]="string|**Please restart your Mac now**<br><br>Happy {weekday}, {loggedInUserFirstname}!<br><br>Your Mac is past the **{ddmVersionStringDeadlineHumanReadable}** deadline to {titleMessageUpdateOrUpgrade:l} to macOS {ddmVersionString}.<br><br>Click **{button1text}** to restart now to help complete the required {titleMessageUpdateOrUpgrade:l}.<br><br>(This reminder will persist until your Mac has been restarted.)"
    ["pastDeadlineForceTitle"]="string|Your Mac is restarting"
    ["pastDeadlineForceMessage"]="string|**Your Mac will restart when the timer below expires.**<br><br>Happy {weekday}, {loggedInUserFirstname}!<br><br>Your Mac is past the **{ddmVersionStringDeadlineHumanReadable}** deadline to install macOS {ddmVersionString} and needs to be restarted to help the {titleMessageUpdateOrUpgrade:l} process to complete, or you can click **{button1text}**.<br><br>(This reminder will persist until your Mac has been restarted.)"
    
    # Complex UI Text
    ["message"]="string|**A required macOS {titleMessageUpdateOrUpgrade:l} is now available**<br><br>Happy {weekday}, {loggedInUserFirstname}!<br><br>Please {titleMessageUpdateOrUpgrade:l} to macOS **{ddmVersionString}** to ensure your Mac remains secure and compliant with organizational policies.{updateReadyMessage}<br><br>To perform the {titleMessageUpdateOrUpgrade:l} now, click **{button1text}**, review the on-screen instructions, then click **{softwareUpdateButtonText}**.<br><br>If you are unable to perform this {titleMessageUpdateOrUpgrade:l} now, click **{button2text}** to be reminded again later (which is disabled when the deadline is imminent).<br><br>{deadlineEnforcementMessage}{excessiveUptimeWarningMessage}{diskSpaceWarningMessage}{supportAssistanceMessage}"
    ["infobox"]="string|**{infoboxLabelCurrent}:** macOS {installedmacOSVersion}<br><br>**{infoboxLabelRequired}:** macOS {ddmVersionString}<br><br>**{infoboxLabelDeadline}:** {infoboxDeadlineDisplay}<br><br>**{infoboxLabelDaysRemaining}:** {infoboxDaysRemainingDisplay}<br><br>**{infoboxLabelLastRestart}:** {infoboxLastRestartDisplay}<br><br>**{infoboxLabelFreeDiskSpace}:** {diskSpaceHumanReadable}"
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
    ["daysPastDeadlineRestartWorkflow"]="DaysPastDeadlineRestartWorkflow"
    ["pastDeadlineRestartBehavior"]="PastDeadlineRestartBehavior"
    ["meetingDelay"]="MeetingDelay"
    ["acceptableAssertionApplicationNames"]="AcceptableAssertionApplicationNames"
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
    ["languageOverride"]="LanguageOverride"
    ["supportAssistanceMessage"]="SupportAssistanceMessage"
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
    ["pastDeadlinePromptTitle"]="PastDeadlinePromptTitle"
    ["pastDeadlinePromptMessage"]="PastDeadlinePromptMessage"
    ["pastDeadlineForceTitle"]="PastDeadlineForceTitle"
    ["pastDeadlineForceMessage"]="PastDeadlineForceMessage"
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
# Client-side Logging (any formatting changes must also be reflected in "Quiet period")
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo "${organizationScriptName} ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" # | tee -a "${scriptLog}"
}

function preFlight()    { updateScriptLog "[PRE-FLIGHT]      ${1}"; }
function notice()       { updateScriptLog "[NOTICE]          ${1}"; }
function info()         { updateScriptLog "[INFO]            ${1}"; }
function error()        { updateScriptLog "[ERROR]           ${1}"; let errorCount++; }
function warning()      { updateScriptLog "[WARNING]         ${1}"; let errorCount++; }
function fatal()        { updateScriptLog "[FATAL ERROR]     ${1}"; exit 1; }
function quitOut()      { updateScriptLog "[QUIT]            ${1}"; }



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# DDM Version Validation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function isValidDDMVersionString() {
    local value="${1}"
    local ddmVersionRegex='^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$'

    if [[ -z "${value}" ]]; then
        return 1
    fi

    if [[ "${value}" =~ ${ddmVersionRegex} ]]; then
        return 0
    fi

    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Deadline Display Formatting
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function localeForDialogLanguageCode() {
    local languageCode="${1:l}"
    local discoveredLocale=""

    # Prefer an installed locale that matches the requested language code so
    # new plist-only translations can localize weekdays and %a/%b dates too.
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

function formatDeadlineFromISO8601() {
    local sourceTimestamp="${1}"
    local requestedFormat="${2}"
    local formattedDeadline=""

    formattedDeadline=$(formatDateWithDialogLocale "%Y-%m-%dT%H:%M:%S" "${sourceTimestamp}" "${requestedFormat}")
    if [[ -z "${formattedDeadline}" ]]; then
        formattedDeadline=$(formatDateWithDialogLocale "%Y-%m-%dT%H:%M:%S" "${sourceTimestamp}" "+%a, %d-%b-%Y, %-l:%M %p")
    fi

    formattedDeadline="$(trimSurroundingWhitespace "${formattedDeadline}")"
    echo "${formattedDeadline}"
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

    timeHumanReadable=$( formatDateWithDialogLocale "%s" "${targetEpoch}" "+%-l:%M %p" )
    if [[ -z "${timeHumanReadable}" ]]; then
        return 1
    fi

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

    if [[ -n "${targetEpoch}" ]] && [[ "${targetEpoch}" =~ ^[0-9]+$ ]]; then
        targetDate=$( date -jf "%s" "${targetEpoch}" "+%Y-%m-%d" 2>/dev/null )
        todayDate=$( date "+%Y-%m-%d" )
        tomorrowDate=$( date -v+1d "+%Y-%m-%d" )
        targetTime=$( formatTimeHumanReadableFromEpoch "${targetEpoch}" 2>/dev/null )

        if [[ -n "${targetDate}" ]] && [[ -n "${targetTime}" ]]; then
            if [[ "${targetDate}" == "${todayDate}" ]]; then
                relativeDeadlineHumanReadable="${relativeDeadlineToday}, ${targetTime}"
            elif [[ "${targetDate}" == "${tomorrowDate}" ]]; then
                relativeDeadlineHumanReadable="${relativeDeadlineTomorrow}, ${targetTime}"
            fi
        fi
    fi

    if [[ -z "${relativeDeadlineHumanReadable}" ]]; then
        relativeDeadlineHumanReadable="${absoluteFallback}"
    fi

    relativeDeadlineHumanReadable="$(trimSurroundingWhitespace "${relativeDeadlineHumanReadable}")"
    echo "${relativeDeadlineHumanReadable}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Preference Loading and Management
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

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
        *)      echo "Off" ;;
    esac
}

function setPreferenceValue() {
    local targetVariable="${1}"
    local managedValue="${2}"
    local managedKeyExists="${3}"
    local localValue="${4}"
    local localKeyExists="${5}"
    local defaultValue="${6}"
    local chosenValue=""

    if [[ "${managedKeyExists}" == "true" ]]; then
        chosenValue="${managedValue}"
        preferenceExplicitlySet["${targetVariable}"]="true"
    elif [[ "${localKeyExists}" == "true" ]]; then
        chosenValue="${localValue}"
        preferenceExplicitlySet["${targetVariable}"]="true"
    else
        chosenValue="${defaultValue}"
        unset "preferenceExplicitlySet[${targetVariable}]"
    fi

    printf -v "${targetVariable}" '%s' "${chosenValue}"
}

function setAllowlistPreferenceValue() {
    local targetVariable="${1}"
    local managedValue="${2}"
    local managedKeyExists="${3}"
    local localValue="${4}"
    local localKeyExists="${5}"
    local defaultValue="${6}"
    local chosenValue="${defaultValue}"

    # Preserve intentional empty-string overrides for this specific key.
    if [[ "${managedKeyExists}" == "true" ]]; then
        chosenValue="${managedValue}"
    elif [[ "${localKeyExists}" == "true" ]]; then
        chosenValue="${localValue}"
    fi

    printf -v "${targetVariable}" '%s' "${chosenValue}"
}

function setNumericPreferenceValue() {
    local targetVariable="${1}"
    local managedValue="${2}"
    local localValue="${3}"
    local defaultValue="${4}"
    local candidate=""

    if [[ "${managedValue}" =~ ^[0-9]+$ ]] && (( managedValue >= 0 && managedValue <= 999 )); then
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
    local normalized=""

    # Managed takes precedence
    if [[ -n "${managedValue}" ]]; then
        normalized=$(normalizeBooleanValue "${managedValue}")
        [[ -n "${normalized}" ]] && chosenValue="${normalized}"
    elif [[ -n "${localValue}" ]]; then
        normalized=$(normalizeBooleanValue "${localValue}")
        [[ -n "${normalized}" ]] && chosenValue="${normalized}"
    fi

    printf -v "${targetVariable}" '%s' "${chosenValue}"
}

function loadDefaultPreferences() {
    preferenceExplicitlySet=()

    for prefKey in "${(@k)preferenceConfiguration}"; do
        local prefConfig="${preferenceConfiguration[$prefKey]}"
        local defaultValue="${prefConfig#*|}"
        printf -v "${prefKey}" '%s' "${defaultValue}"
    done
}

function isKnownPreferencePlistKey() {
    internalPreferenceKeyForPlistKey "${1}" >/dev/null 2>&1
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

function loadDynamicLocalizedPreferenceOverridesFromPlist() {
    local plistPath="${1}"
    local rawKey=""
    local plistKeys=()

    while IFS= read -r rawKey; do
        [[ -n "${rawKey}" ]] && plistKeys+=("${rawKey}")
    done < <(/usr/libexec/PlistBuddy -c "Print" "${plistPath}" 2>/dev/null | awk '
        /^    / && /Localized_/ {
            key=$0
            sub(/^    /, "", key)
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

        if isKnownPreferencePlistKey "${rawKey}"; then
            continue
        fi

        if internalBase="$(internalPreferenceKeyForPlistKey "${baseRaw}")"; then
            :
        else
            internalBase="${baseRaw:0:1:l}${baseRaw:1}"
        fi
        internalSuffix="$(languageSuffixForCode "${codePart}")"
        internalKey="${internalBase}Localized${internalSuffix}"
        dynamicValue=$(/usr/libexec/PlistBuddy -c "Print :${rawKey}" "${plistPath}" 2>/dev/null)

        printf -v "${internalKey}" '%s' "${dynamicValue}"
        preferenceExplicitlySet["${internalKey}"]="true"
    done
}

function loadPreferenceOverrides() {
    preferenceExplicitlySet=()
    
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
        local managedKeyExists="false"
        if [[ "${hasManagedPrefs}" == "true" ]]; then
            if /usr/libexec/PlistBuddy -c "Print :${plistKey}" "${managedPreferencesPlist}.plist" >/dev/null 2>&1; then
                managedKeyExists="true"
                managedValue=$(/usr/libexec/PlistBuddy -c "Print :${plistKey}" "${managedPreferencesPlist}.plist" 2>/dev/null)
            fi
        fi
        
        # Read local value
        local localValue=""
        local localKeyExists="false"
        if [[ "${hasLocalPrefs}" == "true" ]]; then
            if /usr/libexec/PlistBuddy -c "Print :${plistKey}" "${localPreferencesPlist}.plist" >/dev/null 2>&1; then
                localKeyExists="true"
                localValue=$(/usr/libexec/PlistBuddy -c "Print :${plistKey}" "${localPreferencesPlist}.plist" 2>/dev/null)
            fi
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
                if [[ "${prefKey}" == "acceptableAssertionApplicationNames" ]]; then
                    setAllowlistPreferenceValue "${prefKey}" "${managedValue}" "${managedKeyExists}" "${localValue}" "${localKeyExists}" "${defaultValue}"
                else
                    setPreferenceValue "${prefKey}" "${managedValue}" "${managedKeyExists}" "${localValue}" "${localKeyExists}" "${defaultValue}"
                fi
                ;;
        esac
    done

    if [[ "${hasLocalPrefs}" == "true" ]]; then
        loadDynamicLocalizedPreferenceOverridesFromPlist "${localPreferencesPlist}.plist"
    fi

    if [[ "${hasManagedPrefs}" == "true" ]]; then
        loadDynamicLocalizedPreferenceOverridesFromPlist "${managedPreferencesPlist}.plist"
    fi

    # Special handling for date format
    [[ "${dateFormatDeadlineHumanReadable}" != +* ]] && dateFormatDeadlineHumanReadable="+${dateFormatDeadlineHumanReadable}"

    preFlight "Preferences loaded"

}

function validatePreferenceLoad() {
    # Verify critical preferences loaded correctly
    local criticalVars=("scriptLog" "daysBeforeDeadlineDisplayReminder" "supportTeamName")
    for var in "${criticalVars[@]}"; do
        if [[ -z "${(P)var}" ]]; then
            warning "Critical preference '${var}' is empty; using default"
        fi
    done

    local originalPastDeadlineRestartBehavior="${pastDeadlineRestartBehavior}"
    local normalizedPastDeadlineRestartBehavior="${originalPastDeadlineRestartBehavior//[[:space:]]/}"
    pastDeadlineRestartBehavior=$(normalizePastDeadlineRestartBehaviorValue "${originalPastDeadlineRestartBehavior}")

    case "${normalizedPastDeadlineRestartBehavior:l}" in
        off|prompt|force)
            ;;
        *)
            warning "Invalid pastDeadlineRestartBehavior value '${originalPastDeadlineRestartBehavior}'; defaulting to '${pastDeadlineRestartBehavior}'. Valid values: Off, Prompt, Force."
            ;;
    esac
}

function buildPlaceholderMap() {
    declare -gA PLACEHOLDER_MAP=(
        [weekday]="$(localizedWeekdayName "${dialogLanguage}")"
        [userfirstname]="${loggedInUserFirstname}"
        [loggedInUserFirstname]="${loggedInUserFirstname}"
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

    # Resolve nested placeholders: run multiple passes until stable
    local maxPasses=5
    local pass=0
    local previousValue

    while (( pass < maxPasses )); do
        previousValue="${value}"

        for placeholder replaceValue in "${(@kv)PLACEHOLDER_MAP}"; do
            value=${value//\{${placeholder}\}/${replaceValue}}
            value=${value//\{${placeholder}:l\}/${replaceValue:l}}
        done

        ((pass++))

        # Stop if nothing changed in this pass
        [[ "${value}" == "${previousValue}" ]] && break
    done

    printf -v "${targetVariable}" '%s' "${value}"
}

function setHideSecondaryButtonState() {
    local secondsUntilDeadlineValue="${1}"
    local hideThresholdSecondsValue="${2}"

    if (( secondsUntilDeadlineValue > hideThresholdSecondsValue )); then
        hideSecondaryButton="NO"
        return
    fi

    case "${disableButton2InsteadOfHide}" in
        "YES")
            hideSecondaryButton="DISABLED"
            ;;
        *)
            hideSecondaryButton="YES"
            ;;
    esac
}

function applyHideRules() {
    # Hide info button explicitly
    case "${infobuttontext}" in
        "hide")
            infobuttontext=""
            ;;
    esac

    # Hide help image (QR) if requested
    case "${helpimage}" in
        "hide")
            helpimage=""
            ;;
    esac

    # Handle secondary button based on computed deadline window flag
    # hideSecondaryButton can be: "NO" (show), "YES" (hide), or "DISABLED" (greyed out)
    case "${hideSecondaryButton}" in
        "YES")
            button2text=""
            ;;
    esac
    # Note: DISABLED state is handled in displayReminderDialog() via --button2disabled flag
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
    if [[ -f "${managedPreferencesPlist}.plist" ]]; then
        if /usr/libexec/PlistBuddy -c "Print :${sentinelKey}" "${managedPreferencesPlist}.plist" >/dev/null 2>&1; then
            echo "${languageCode}"
            return
        fi
    fi

    if [[ -f "${localPreferencesPlist}.plist" ]]; then
        if /usr/libexec/PlistBuddy -c "Print :${sentinelKey}" "${localPreferencesPlist}.plist" >/dev/null 2>&1; then
            echo "${languageCode}"
            return
        fi
    fi

    echo "en"
}

function detectLoggedInUserLanguageCode() {
    local globalPreferencesPath="${loggedInUserHomeDirectory}/Library/Preferences/.GlobalPreferences.plist"
    local detectedLanguage=""

    if [[ -z "${loggedInUserHomeDirectory}" ]]; then
        globalPreferencesPath="/Users/${loggedInUser}/Library/Preferences/.GlobalPreferences.plist"
    fi

    if [[ -r "${globalPreferencesPath}" ]]; then
        detectedLanguage=$(/usr/libexec/PlistBuddy -c "Print :AppleLanguages:0" "${globalPreferencesPath}" 2>/dev/null)
    fi

    echo "${detectedLanguage}"
}

function languageSuffixForCode() {
    local code="${1:l}"

    [[ -z "${code}" || "${code}" == "en" ]] && echo "En" && return

    echo "${(C)code}"
}

function localizedWeekdayName() {
    local languageCode="${1}"
    local localeForWeekday=""
    local localizedWeekday=""

    localeForWeekday="$(localeForDialogLanguageCode "${languageCode}")"
    if [[ -n "${localeForWeekday}" ]]; then
        localizedWeekday=$(LC_TIME="${localeForWeekday}" date "+%A" 2>/dev/null)
    fi

    if [[ -z "${localizedWeekday}" ]]; then
        localizedWeekday=$(date "+%A")
    fi

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

function initializeLocalizedRuntimeFields() {
    local runtimeField
    local runtimeFields=("relativeDeadlineToday" "relativeDeadlineTomorrow")

    for runtimeField in "${runtimeFields[@]}"; do
        applyLocalizedFieldValue "${runtimeField}" "${dialogLanguage}"
    done
}

function applyLocalizedFieldValue() {
    local baseVariable="${1}"
    local languageCode="${2}"
    local localizedSuffix
    localizedSuffix="$(languageSuffixForCode "${languageCode}")"
    local localizedVariable="${baseVariable}Localized${localizedSuffix}"
    local localizedValue="${(P)localizedVariable}"

    if [[ "${preferenceExplicitlySet[${localizedVariable}]}" == "true" ]]; then
        printf -v "${baseVariable}" '%s' "${localizedValue}"
        return
    fi

    if [[ "${preferenceExplicitlySet[${baseVariable}]}" == "true" ]]; then
        return
    fi

    if [[ -n "${localizedValue}" ]]; then
        printf -v "${baseVariable}" '%s' "${localizedValue}"
    fi
}

function applyLocalizedDialogText() {
    local localizedField
    local localizedFields=("title" "button1text" "button2text" "infobuttontext"
                        "message" "helpmessage"
                        "excessiveUptimeWarningMessage" "diskSpaceWarningMessage"
                        "stagedUpdateMessage" "partiallyStagedUpdateMessage" "pendingDownloadMessage"
                        "supportAssistanceMessage"
                        "updateWord" "upgradeWord"
                        "softwareUpdateButtonTextUpdate" "softwareUpdateButtonTextUpgrade" "restartNowButtonText"
                        "infoboxLabelCurrent" "infoboxLabelRequired" "infoboxLabelDeadline"
                        "infoboxLabelDaysRemaining" "infoboxLabelLastRestart" "infoboxLabelFreeDiskSpace"
                        "deadlineEnforcementMessageAbsolute" "deadlineEnforcementMessageRelative"
                        "pastDeadlinePromptTitle" "pastDeadlinePromptMessage"
                        "pastDeadlineForceTitle" "pastDeadlineForceMessage")

    resolveDialogLanguage

    for localizedField in "${localizedFields[@]}"; do
        applyLocalizedFieldValue "${localizedField}" "${dialogLanguage}"
    done
}

function applyLocalizedUpdateVocabulary() {
    local mode="${updateOrUpgradeMode:l}"
    [[ "${mode}" != "upgrade" ]] && mode="update"

    if [[ "${mode}" == "upgrade" ]]; then
        titleMessageUpdateOrUpgrade="${upgradeWord}"
        softwareUpdateButtonText="${softwareUpdateButtonTextUpgrade}"
    else
        titleMessageUpdateOrUpgrade="${updateWord}"
        softwareUpdateButtonText="${softwareUpdateButtonTextUpdate}"
    fi
}

function applyLocalizedInfoboxLabels() {
    return
}

function updateRequiredVariables() {
    downloadBrandingAssets
    dialogBinary="/usr/local/bin/dialog"
    if [[ ! -x "${dialogBinary}" ]]; then
        fatal "swiftDialog not found at '${dialogBinary}'; are downloads from GitHub blocked on this Mac?"
    fi

    action="x-apple.systempreferences:com.apple.preferences.softwareupdate"
    applyLocalizedDialogText
    applyLocalizedUpdateVocabulary
    refreshLocalizedRuntimeFacts
    applyLocalizedInfoboxLabels
    
    computeDynamicWarnings
    computeUpdateStagingMessage
    computeDeadlineEnforcementMessage
    computeInfoboxHighlights
    applyPastDeadlineDialogOverrides

    if [[ "${infobuttontext}" == "hide" ]]; then
        supportAssistanceMessage=""
    fi

    buildPlaceholderMap
    
    local textFields=("title" "button1text" "button2text" "infobuttontext"
                    "infobox" "helpmessage" "helpimage"
                    "excessiveUptimeWarningMessage" "diskSpaceWarningMessage"
                    "message")
    
    for field in "${textFields[@]}"; do
        replacePlaceholders "${field}"
    done
    
    applyHideRules
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Current Logged-in User
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function currentLoggedInUser() {
    loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
    preFlight "Current Logged-in User: ${loggedInUser}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Read Staged macOS Version from cryptex1 Metadata
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function readStagedMacOSVersion() {

    local basePath="${1}"
    local candidatePath=""
    local stagedVersion=""
    local stagedBuild=""
    local cryptexBasePath=""
    local -a candidatePlists=()

    stagedProposedVersion=""
    stagedProposedBuild=""

    if [[ -z "${basePath}" ]]; then
        return 1
    fi

    cryptexBasePath="${basePath}"
    if [[ "${cryptexBasePath:t}" != "cryptex1" ]]; then
        cryptexBasePath="${basePath}/cryptex1"
    fi

    candidatePlists+=("${cryptexBasePath}/proposed/SystemVersion.plist")
    candidatePlists+=("${cryptexBasePath}/proposed/BuildManifest.plist")

    for candidatePath in "${candidatePlists[@]}"; do
        if [[ ! -f "${candidatePath}" ]]; then
            continue
        fi

        stagedVersion=$( /usr/libexec/PlistBuddy -c "Print :ProductVersion" "${candidatePath}" 2>/dev/null )
        stagedBuild=$( /usr/libexec/PlistBuddy -c "Print :ProductBuildVersion" "${candidatePath}" 2>/dev/null )

        # Some staged plists can fail PlistBuddy parsing; fall back to plutil output parsing.
        if [[ -z "${stagedVersion}" ]]; then
            local plistDump=""
            plistDump=$( /usr/bin/plutil -p "${candidatePath}" 2>/dev/null )

            if [[ -n "${plistDump}" ]]; then
                stagedVersion=$( echo "${plistDump}" | awk -F'=> ' '/"ProductVersion"/ { gsub(/[",]/, "", $2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' )
                stagedBuild=$( echo "${plistDump}" | awk -F'=> ' '/"ProductBuildVersion"/ { gsub(/[",]/, "", $2); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' )
            fi
        fi

        if isValidDDMVersionString "${stagedVersion}"; then
            stagedProposedVersion="${stagedVersion}"
            stagedProposedBuild="${stagedBuild}"
            notice "Detected staged proposed macOS version ${stagedProposedVersion}${stagedProposedBuild:+ (${stagedProposedBuild})} from ${candidatePath}."
            return 0
        fi
    done

    return 1

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
    
    if [[ "${updateSnapshots}" -gt 0 ]]; then
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
        local cryptexSize=$(du -sk "${prebootPath}/cryptex1" 2>/dev/null | awk '{print $1}')
        
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
        local restoreSize=$(du -sk "${prebootPath}/restore-staged" 2>/dev/null | awk '{print $1}')
        if [[ -n "${restoreSize}" ]] && [[ ${restoreSize} -gt 102400 ]]; then
            local restoreSizeGB=$(echo "scale=2; ${restoreSize} / 1048576" | bc)
            info "Additional staged content: ${restoreSizeGB} GB in restore-staged"
        fi
    fi
    
    # Check total Preboot volume usage
    local totalPrebootSize=$(du -sk "${prebootPath}" 2>/dev/null | awk '{print $1}')
    if [[ -n "${totalPrebootSize}" ]]; then
        local prebootGB=$(echo "scale=2; ${totalPrebootSize} / 1048576" | bc)
        
        # Typical Preboot is 1–3 GB; if > 8 GB, major update assets are staged
        if [[ $(echo "${prebootGB} > 8" | bc) -eq 1 ]]; then
            if [[ "${stagedUpdateStatus}" != "Fully staged" ]]; then
                stagedUpdateSize="${prebootGB}"
                stagedUpdateLocation="${prebootPath}"
                stagedUpdateStatus="Fully staged"
                info "Large Preboot volume detected: ${prebootGB} GB total (threshold 8 GB)"
            fi
        fi
    fi
    
    # Attempt to surface staged target version/build metadata when update assets are present.
    if [[ "${stagedUpdateStatus}" == "Partially staged" || "${stagedUpdateStatus}" == "Fully staged" ]]; then
        local stagedMetadataPath="${stagedUpdateLocation}"
        if [[ "${stagedMetadataPath}" == "Not detected" ]]; then
            stagedMetadataPath="${prebootPath}"
        fi
        if readStagedMacOSVersion "${stagedMetadataPath}"; then
            if isValidDDMVersionString "${ddmVersionString}"; then
                if is-at-least "${ddmVersionString}" "${stagedProposedVersion}" && is-at-least "${stagedProposedVersion}" "${ddmVersionString}"; then
                    notice "Staged proposed macOS version ${stagedProposedVersion} matches DDM-enforced version ${ddmVersionString}."
                else
                    warning "Staged proposed macOS version ${stagedProposedVersion} does not match DDM-enforced version ${ddmVersionString}; treating staged status as Pending download."
                    stagedUpdateStatus="Pending download"
                    stagedUpdateSize="0"
                    stagedUpdateLocation="Not detected"
                fi
            fi
        else
            info "No staged proposed macOS version metadata detected."

            # Missing proposed metadata means we cannot trust staged-state attribution.
            # Normalize to pending so reminder flow can proceed without a false quiet exit.
            notice "Staged proposed metadata unavailable; treating staged update status as Pending download."
            stagedUpdateStatus="Pending download"
            stagedUpdateSize="0"
            stagedUpdateLocation="Not detected"
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

function tailRecentInstallLogWindow() {
    if [[ ! -r "${installLogPath}" ]]; then
        ddmRecentInstallLogWindow=()
        return 1
    fi

    ddmRecentInstallLogWindow=( ${(f)"$(tail -n "${ddmResolverLookbackLines}" "${installLogPath}" 2>/dev/null)"} )

    if [[ ${#ddmRecentInstallLogWindow[@]} -eq 0 ]]; then
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
    parsedDDMRawLine="${logLine}"

    if [[ "${logLine}" == *"declarationFromKeys]: Found currently applicable declaration"* ]]; then
        parsedDDMSourceType="currentApplicableDeclaration"
    elif [[ "${logLine}" == *"declarationFromKeys]: Falling back to default applicable declaration"* ]]; then
        parsedDDMSourceType="defaultApplicableDeclaration"
    elif [[ "${logLine}" == *"Found DDM enforced install ("* ]]; then
        parsedDDMSourceType="foundDdmEnforcedInstall"
    elif [[ "${logLine}" == *"EnforcedInstallDate:"* ]]; then
        parsedDDMSourceType="genericEnforcedInstallDate"
    else
        return 1
    fi

    parsedDDMLogTimestamp="${logLine[1,22]}"
    parsedDDMEnforcedInstallDate="${${logLine##*|EnforcedInstallDate:}%%|*}"
    parsedDDMVersionString="${${logLine##*|VersionString:}%%|*}"
    parsedDDMBuildVersionString="${${logLine##*|BuildVersionString:}%%|*}"

    if [[ ! "${parsedDDMLogTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
        return 1
    fi

    if [[ -z "${parsedDDMEnforcedInstallDate}" || -z "${parsedDDMVersionString}" || -z "${parsedDDMBuildVersionString}" ]]; then
        return 1
    fi

    return 0
}

function ddmSourcePriority() {
    local sourceType="${1}"

    case "${sourceType}" in
        currentApplicableDeclaration)
            echo "4"
            ;;
        defaultApplicableDeclaration)
            echo "3"
            ;;
        foundDdmEnforcedInstall)
            echo "2"
            ;;
        genericEnforcedInstallDate)
            echo "1"
            ;;
        *)
            echo "0"
            ;;
    esac
}

function parseDDMDescriptorVersionFromLine() {
    local logLine="${1}"
    local descriptorText=""
    local descriptorToken=""
    local -a descriptorTokens=( )

    parsedDDMDescriptorVersion=""

    if [[ "${logLine}" != *"PrimaryDescriptor:"* || "${logLine}" == *"PrimaryDescriptor: (null)"* || "${logLine}" != *"SU:"* ]]; then
        return 1
    fi

    descriptorText="${logLine##* SU:}"
    descriptorTokens=( ${=descriptorText} )

    for descriptorToken in "${descriptorTokens[@]}"; do
        if isValidDDMVersionString "${descriptorToken}"; then
            parsedDDMDescriptorVersion="${descriptorToken}"
            break
        fi
    done

    if [[ -z "${parsedDDMDescriptorVersion}" ]]; then
        return 1
    fi

    return 0
}

function candidateHasNoMatchScanFailure() {
    local candidateVersion="${1}"
    local declarationTimestamp="${2}"
    local lineIndex=0
    local currentLine=""
    local lineTimestamp=""
    local segmentActive="NO"

    ddmResolverFailureMarker=""

    for (( lineIndex = 1; lineIndex <= ${#ddmRecentInstallLogWindow[@]}; lineIndex++ )); do
        currentLine="${ddmRecentInstallLogWindow[$lineIndex]}"
        lineTimestamp="${currentLine[1,22]}"

        if [[ ! "${lineTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
            continue
        fi

        if [[ "${lineTimestamp}" < "${declarationTimestamp}" ]]; then
            continue
        fi

        if [[ "${currentLine}" == *"requestedPMV="* ]]; then
            if [[ "${currentLine}" == *"requestedPMV=${candidateVersion},"* || "${currentLine}" == *"requestedPMV=${candidateVersion})"* ]]; then
                segmentActive="YES"
            else
                segmentActive="NO"
            fi
            continue
        fi

        if [[ "${segmentActive}" != "YES" ]]; then
            continue
        fi

        if [[ "${currentLine}" == *"MADownloadNoMatchFound"* ]]; then
            ddmResolverFailureMarker="MADownloadNoMatchFound"
            return 0
        fi

        if [[ "${currentLine}" == *"pallasNoPMVMatchFound=true"* ]]; then
            ddmResolverFailureMarker="pallasNoPMVMatchFound=true"
            return 0
        fi

        if [[ "${currentLine}" == *"No available updates found. Please try again later."* ]]; then
            ddmResolverFailureMarker="No available updates found. Please try again later."
            return 0
        fi
    done

    return 1
}

function candidateHasConflictingEvidence() {
    local candidateSignature="${1}"
    local candidateVersion="${2}"
    local firstDeclarationTimestamp="${3}"
    local declarationTimestamp="${4}"
    local lineIndex=0
    local currentLine=""
    local lineTimestamp=""
    local noUpdatesTimestamp=""

    ddmResolverConflictSummary=""

    for (( lineIndex = 1; lineIndex <= ${#ddmRecentInstallLogWindow[@]}; lineIndex++ )); do
        currentLine="${ddmRecentInstallLogWindow[$lineIndex]}"
        lineTimestamp="${currentLine[1,22]}"

        if [[ ! "${lineTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
            continue
        fi

        if [[ "${lineTimestamp}" < "${firstDeclarationTimestamp}" ]]; then
            continue
        fi

        if [[ "${currentLine}" == *"EnforcedInstallDate:"* ]] && parseDDMDeclarationFromLine "${currentLine}"; then
            if [[ -n "${noUpdatesTimestamp}" ]]; then
                if [[ "${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}" == "${candidateSignature}" ]]; then
                    if [[ "${lineTimestamp}" > "${noUpdatesTimestamp}" || "${lineTimestamp}" == "${noUpdatesTimestamp}" ]]; then
                        ddmResolverConflictSummary="Declaration persisted after 'No updates found for DDM to enforce'"
                        return 0
                    fi
                fi
            fi

            if [[ "${lineTimestamp}" < "${declarationTimestamp}" ]]; then
                continue
            fi

            if [[ "${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}" != "${candidateSignature}" ]]; then
                ddmResolverConflictSummary="Conflicting declaration: ${parsedDDMVersionString} | ${parsedDDMEnforcedInstallDate} | ${parsedDDMBuildVersionString} | ${parsedDDMSourceType}"
                return 0
            fi
        fi

        if [[ "${lineTimestamp}" < "${declarationTimestamp}" ]]; then
            if [[ "${currentLine}" == *"No updates found for DDM to enforce"* ]]; then
                noUpdatesTimestamp="${lineTimestamp}"
            fi
            continue
        fi

        if parseDDMDescriptorVersionFromLine "${currentLine}"; then
            if [[ "${parsedDDMDescriptorVersion}" != "${candidateVersion}" ]]; then
                ddmResolverConflictSummary="Available descriptor ${parsedDDMDescriptorVersion} disagrees with DDM declaration ${candidateVersion}"
                return 0
            fi
        fi

        if [[ "${currentLine}" == *"No updates found for DDM to enforce"* ]]; then
            noUpdatesTimestamp="${lineTimestamp}"
        fi
    done

    return 1
}

function resolveDDMEnforcementFromInstallLog() {
    local line=""
    local candidateKey=""
    local candidateSignature=""
    local latestTimestamp=""
    local latestInvalidContext=""
    local index=0
    local latestIndex=0
    local candidateSummary=""
    local distinctCandidateCount=0
    local highestPriority=0
    local currentPriority=0

    local -a candidateSourceTypes=()
    local -a candidateFirstTimestamps=()
    local -a candidateTimestamps=()
    local -a candidateEnforcedDates=()
    local -a candidateVersions=()
    local -a candidateBuilds=()
    local -a candidateRawLines=()
    local -a filteredIndexes=()
    typeset -A seenCandidateIndexes=()

    ddmResolverStatus=""
    ddmResolverReason=""
    ddmResolverSource=""
    ddmResolverSuppressionType=""
    ddmDeclarationLogTimestamp=""
    ddmDeclarationRawLine=""
    ddmBuildVersionString=""
    ddmResolverFailureMarker=""
    ddmResolverConflictSummary=""

    if ! tailRecentInstallLogWindow; then
        ddmResolverStatus="missing"
        ddmResolverSuppressionType="missing"
        ddmResolverReason="No readable install.log window available"
        return 1
    fi

    for line in "${ddmRecentInstallLogWindow[@]}"; do
        if ! parseDDMDeclarationFromLine "${line}"; then
            continue
        fi

        candidateKey="${parsedDDMSourceType}|${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}"

        if (( ${+seenCandidateIndexes[${candidateKey}]} )); then
            index="${seenCandidateIndexes[${candidateKey}]}"
            if [[ "${parsedDDMLogTimestamp}" > "${candidateTimestamps[$index]}" ]]; then
                candidateTimestamps[$index]="${parsedDDMLogTimestamp}"
                candidateRawLines[$index]="${parsedDDMRawLine}"
            fi
            continue
        fi

        candidateSourceTypes+=( "${parsedDDMSourceType}" )
        candidateFirstTimestamps+=( "${parsedDDMLogTimestamp}" )
        candidateTimestamps+=( "${parsedDDMLogTimestamp}" )
        candidateEnforcedDates+=( "${parsedDDMEnforcedInstallDate}" )
        candidateVersions+=( "${parsedDDMVersionString}" )
        candidateBuilds+=( "${parsedDDMBuildVersionString}" )
        candidateRawLines+=( "${parsedDDMRawLine}" )
        seenCandidateIndexes[${candidateKey}]="${#candidateSourceTypes[@]}"
    done

    if [[ ${#candidateSourceTypes[@]} -eq 0 ]]; then
        ddmResolverStatus="missing"
        ddmResolverSuppressionType="missing"
        ddmResolverReason="No DDM declaration candidates found in install.log"
        return 1
    fi

    latestTimestamp="${candidateTimestamps[1]}"
    for (( index = 2; index <= ${#candidateTimestamps[@]}; index++ )); do
        if [[ "${candidateTimestamps[$index]}" > "${latestTimestamp}" ]]; then
            latestTimestamp="${candidateTimestamps[$index]}"
        fi
    done

    for (( index = 1; index <= ${#candidateSourceTypes[@]}; index++ )); do
        if [[ "${candidateTimestamps[$index]}" == "${latestTimestamp}" ]]; then
            filteredIndexes+=( "${index}" )
        fi
    done

    highestPriority=0
    for index in "${filteredIndexes[@]}"; do
        currentPriority="$(ddmSourcePriority "${candidateSourceTypes[$index]}")"
        if (( currentPriority > highestPriority )); then
            highestPriority="${currentPriority}"
        fi
    done

    filteredIndexes=( )
    for (( index = 1; index <= ${#candidateSourceTypes[@]}; index++ )); do
        if [[ "${candidateTimestamps[$index]}" == "${latestTimestamp}" ]]; then
            currentPriority="$(ddmSourcePriority "${candidateSourceTypes[$index]}")"
            if (( currentPriority == highestPriority )); then
                filteredIndexes+=( "${index}" )
            fi
        fi
    done

    distinctCandidateCount="${#filteredIndexes[@]}"
    if (( distinctCandidateCount != 1 )); then
        ddmResolverStatus="conflict"
        ddmResolverSuppressionType="conflict"
        ddmResolverReason="Conflicting DDM declarations detected in install.log"
        warning "${ddmResolverReason}"

        for index in "${filteredIndexes[@]}"; do
            candidateSummary="${candidateVersions[$index]} | ${candidateEnforcedDates[$index]} | ${candidateBuilds[$index]} | ${candidateSourceTypes[$index]} | ${candidateTimestamps[$index]}"
            warning "Conflicting candidate: ${candidateSummary}"
        done

        for (( index = ${#ddmRecentInstallLogWindow[@]}; index >= 1; index-- )); do
            if [[ "${ddmRecentInstallLogWindow[$index]}" =~ Removed\ [0-9]+\ invalid\ declarations ]]; then
                latestInvalidContext="${ddmRecentInstallLogWindow[$index]}"
                break
            fi
        done

        if [[ -n "${latestInvalidContext}" ]]; then
            info "Resolver context: ${latestInvalidContext}"
        fi

        return 1
    fi

    latestIndex="${filteredIndexes[1]}"
    ddmResolverSource="${candidateSourceTypes[$latestIndex]}"
    ddmDeclarationLogTimestamp="${candidateTimestamps[$latestIndex]}"
    ddmDeclarationRawLine="${candidateRawLines[$latestIndex]}"
    ddmEnforcedInstallDate="${candidateEnforcedDates[$latestIndex]}"
    ddmVersionString="${candidateVersions[$latestIndex]}"
    ddmBuildVersionString="${candidateBuilds[$latestIndex]}"
    candidateSignature="${ddmEnforcedInstallDate}|${ddmVersionString}|${ddmBuildVersionString}"

    if ! isValidDDMVersionString "${ddmVersionString}"; then
        ddmResolverStatus="invalidVersion"
        ddmResolverSuppressionType="invalidVersion"
        ddmResolverReason="Invalid DDM version string detected in resolved declaration"
        warning "${ddmResolverReason}: ${ddmVersionString}"
        quitOut "${ddmResolverReason}; exiting quietly."
        return 1
    fi

    if candidateHasConflictingEvidence "${candidateSignature}" "${ddmVersionString}" "${candidateFirstTimestamps[$latestIndex]}" "${ddmDeclarationLogTimestamp}"; then
        ddmResolverStatus="conflict"
        ddmResolverSuppressionType="conflict"
        ddmResolverReason="Conflicting DDM state detected in install.log"
        warning "${ddmResolverReason}: ${ddmResolverConflictSummary}"

        for (( index = ${#ddmRecentInstallLogWindow[@]}; index >= 1; index-- )); do
            if [[ "${ddmRecentInstallLogWindow[$index]}" =~ Removed\ [0-9]+\ invalid\ declarations ]]; then
                latestInvalidContext="${ddmRecentInstallLogWindow[$index]}"
                break
            fi
        done

        if [[ -n "${latestInvalidContext}" ]]; then
            info "Resolver context: ${latestInvalidContext}"
        fi

        return 1
    fi

    if candidateHasNoMatchScanFailure "${ddmVersionString}" "${ddmDeclarationLogTimestamp}"; then
        ddmResolverStatus="noMatch"
        ddmResolverSuppressionType="noMatch"
        ddmResolverReason="Chosen DDM declaration does not map to an available update"
        warning "${ddmResolverReason}: ${ddmVersionString} (${ddmResolverFailureMarker})"

        for (( index = ${#ddmRecentInstallLogWindow[@]}; index >= 1; index-- )); do
            if [[ "${ddmRecentInstallLogWindow[$index]}" =~ Removed\ [0-9]+\ invalid\ declarations ]]; then
                latestInvalidContext="${ddmRecentInstallLogWindow[$index]}"
                break
            fi
        done

        if [[ -n "${latestInvalidContext}" ]]; then
            info "Resolver context: ${latestInvalidContext}"
        fi

        return 1
    fi

    ddmResolverStatus="resolved"
    ddmResolverSuppressionType=""
    notice "Resolved DDM declaration source: ${ddmResolverSource}"
    notice "Resolved DDM declaration version: ${ddmVersionString}"
    notice "Resolved DDM declaration enforcement date: ${ddmEnforcedInstallDate}"

    return 0
}

function resolvePaddedEnforcementDateForCandidate() {
    local maxWaitSeconds=300
    local checkIntervalSeconds=10
    local elapsedSeconds=0
    local line=""
    local lineTimestamp=""
    local latestPaddedLine=""
    local latestPaddedDateRaw=""
    local paddedEpoch=""
    local nowEpoch=""
    local conflictDetected="NO"
    local conflictSummary=""

    ddmResolvedPaddedEpoch=""
    ddmResolvedPaddedRawLine=""

    while (( elapsedSeconds < maxWaitSeconds )); do
        tailRecentInstallLogWindow
        latestPaddedLine=""
        latestPaddedDateRaw=""
        paddedEpoch=""
        conflictDetected="NO"
        conflictSummary=""

        for line in "${ddmRecentInstallLogWindow[@]}"; do
            lineTimestamp=$(echo "${line}" | sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}).*/\1/')

            if [[ -z "${lineTimestamp}" || "${lineTimestamp}" == "${line}" ]]; then
                continue
            fi

            if [[ "${lineTimestamp}" < "${ddmDeclarationLogTimestamp}" ]]; then
                continue
            fi

            if [[ "${line}" == *"EnforcedInstallDate:"* ]] && parseDDMDeclarationFromLine "${line}"; then
                if [[ "${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}" != "${ddmEnforcedInstallDate}|${ddmVersionString}|${ddmBuildVersionString}" ]]; then
                    conflictDetected="YES"
                    conflictSummary="${parsedDDMVersionString} | ${parsedDDMEnforcedInstallDate} | ${parsedDDMBuildVersionString} | ${parsedDDMSourceType}"
                    break
                fi
            fi

            if [[ "${line}" == *"setPastDuePaddedEnforcementDate is set: "* ]]; then
                latestPaddedLine="${line}"
            fi
        done

        if [[ "${conflictDetected}" == "YES" ]]; then
            warning "Rejected padded enforcement date because a later conflicting declaration was detected: ${conflictSummary}"
            return 1
        fi

        if [[ -n "${latestPaddedLine}" ]]; then
            latestPaddedDateRaw="${latestPaddedLine#*setPastDuePaddedEnforcementDate is set: }"
            paddedEpoch=$( date -jf "%a %b %d %H:%M:%S %Y" "${latestPaddedDateRaw}" "+%s" 2>/dev/null )

            if [[ -z "${paddedEpoch}" ]]; then
                warning "Unable to parse setPastDuePaddedEnforcementDate: ${latestPaddedDateRaw}"
                return 1
            fi

            nowEpoch=$(date +%s)
            if (( paddedEpoch > nowEpoch )); then
                ddmResolvedPaddedEpoch="${paddedEpoch}"
                ddmResolvedPaddedRawLine="${latestPaddedLine}"
                notice "Accepted padded enforcement date from install.log: ${latestPaddedDateRaw}"
                return 0
            fi

            warning "Found setPastDuePaddedEnforcementDate after resolved declaration, but it is already in the past: ${latestPaddedDateRaw}"
        else
            if (( elapsedSeconds == 0 )); then
                notice "No safe setPastDuePaddedEnforcementDate found after resolved declaration; waiting up to 5 minutes …"
            fi
        fi

        sleep "${checkIntervalSeconds}"
        elapsedSeconds=$(( elapsedSeconds + checkIntervalSeconds ))

        if (( elapsedSeconds < maxWaitSeconds )); then
            info "Retrying padded-date resolution (elapsed: ${elapsedSeconds}s / ${maxWaitSeconds}s) …"
        fi
    done

    warning "Timed out waiting for a safe setPastDuePaddedEnforcementDate after ${maxWaitSeconds} seconds"
    return 1
}

function currentMacSatisfiesResolvedDeclaration() {
    if ! isValidDDMVersionString "${ddmVersionString}"; then
        return 1
    fi

    if [[ -n "${installedmacOSBuild}" && -n "${ddmBuildVersionString}" && "${ddmBuildVersionString}" != "(null)" && "${installedmacOSBuild}" == "${ddmBuildVersionString}" ]]; then
        return 0
    fi

    if [[ -n "${installedmacOSVersion}" ]] && isValidDDMVersionString "${installedmacOSVersion}" && is-at-least "${ddmVersionString}" "${installedmacOSVersion}"; then
        return 0
    fi

    return 1
}

installedOSvsDDMenforcedOS() {

    # Installed macOS Version
    installedmacOSVersion=$( sw_vers -productVersion )
    installedmacOSBuild=$( sw_vers -buildVersion )
    notice "Installed macOS Version: ${installedmacOSVersion}"
    notice "Installed macOS Build: ${installedmacOSBuild}"

    # DDM-enforced macOS Version
    resolveDDMEnforcementFromInstallLog
    if [[ -n "${ddmVersionString}" ]] && currentMacSatisfiesResolvedDeclaration; then
        versionComparisonResult="Up-to-date"
        notice "Installed macOS already satisfies DDM declaration ${ddmVersionString}${ddmResolverStatus:+ despite resolver state ${ddmResolverStatus}}."
        return
    fi

    case "${ddmResolverStatus}" in
        missing)
            versionComparisonResult="No DDM enforcement log entry found; please confirm this Mac is in-scope for DDM-enforced updates."
            return
            ;;
        conflict|noMatch|invalidVersion)
            versionComparisonResult="DDM enforcement state unresolved; suppressing reminder dialog."
            warning "Resolver suppression summary: ${ddmResolverSuppressionType:-${ddmResolverStatus:-unknown}} | ${ddmResolverReason}"
            quitOut "${ddmResolverReason}; exiting quietly."
            return
            ;;
    esac

    ddmLogEntry="${ddmDeclarationRawLine}"
    if [[ -z "${ddmLogEntry}" ]]; then
        versionComparisonResult="No DDM enforcement log entry found; please confirm this Mac is in-scope for DDM-enforced updates."
        return
    fi

    # Parse enforced date and version
    if ! isValidDDMVersionString "${ddmVersionString}"; then
        warning "Invalid DDM-enforced OS Version format. Log entry: ${ddmLogEntry}"
        warning "Invalid DDM-enforced OS Version: ${ddmVersionString}"
        versionComparisonResult="Invalid DDM version string; suppressing reminder dialog."
        quitOut "Invalid DDM version string; exiting quietly."
        return
    fi

    # DDM-enforced Deadline
    ddmVersionStringDeadline="${ddmEnforcedInstallDate%%T*}"
    deadlineEpoch=$( date -jf "%Y-%m-%dT%H:%M:%S" "$ddmEnforcedInstallDate" "+%s" 2>/dev/null )
    if [[ -z "${deadlineEpoch}" ]] || ! [[ "${deadlineEpoch}" =~ ^[0-9]+$ ]]; then
        fatal "Unable to parse DDM enforcement deadline: ${ddmEnforcedInstallDate}"
    fi
    ddmEnforcedInstallDateEpoch="${deadlineEpoch}"
    ddmVersionStringDeadlineHumanReadable=$( formatDeadlineFromISO8601 "${ddmEnforcedInstallDate}" "${dateFormatDeadlineHumanReadable}" )
    ddmVersionStringDeadlineHumanReadable=${ddmVersionStringDeadlineHumanReadable// AM/ a.m.}
    ddmVersionStringDeadlineHumanReadable=${ddmVersionStringDeadlineHumanReadable// PM/ p.m.}

    # DDM-enforced Install Date
    if (( deadlineEpoch <= $(date +%s) )); then

        # Enforcement deadline passed
        notice "DDM enforcement deadline has passed; evaluating post-deadline enforcement …"

        if resolvePaddedEnforcementDateForCandidate; then
            ddmEnforcedInstallDateHumanReadable=$( formatDeadlineFromEpoch "${ddmResolvedPaddedEpoch}" "${dateFormatDeadlineHumanReadable}" )
            ddmEnforcedInstallDateEpoch="${ddmResolvedPaddedEpoch}"
            info "Effective enforcement source: setPastDuePaddedEnforcementDate"
        else
            ddmEnforcedInstallDateHumanReadable="${ddmVersionStringDeadlineHumanReadable}"
            ddmEnforcedInstallDateEpoch="${deadlineEpoch}"
            warning "Safe padded enforcement date unavailable; continuing with declared enforcement date ${ddmVersionStringDeadlineHumanReadable}"
            info "Effective enforcement source: EnforcedInstallDate"
        fi

    else

        # Deadline still in the future
        ddmEnforcedInstallDateHumanReadable="$ddmVersionStringDeadlineHumanReadable"
        ddmEnforcedInstallDateEpoch="${deadlineEpoch}"

    fi

    # Normalize AM/PM formatting
    ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable// AM/ a.m.}
    ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable// PM/ p.m.}
    ddmEnforcedInstallDateRelativeHumanReadable=$( formatRelativeDeadlineHumanReadable "${ddmEnforcedInstallDateEpoch}" "${ddmEnforcedInstallDateHumanReadable}" )
    if [[ -z "${ddmEnforcedInstallDateRelativeHumanReadable}" ]]; then
        ddmEnforcedInstallDateRelativeHumanReadable="${ddmEnforcedInstallDateHumanReadable}"
    fi
    if [[ "${ddmEnforcedInstallDateRelativeHumanReadable}" != "${ddmEnforcedInstallDateHumanReadable}" ]]; then
        notice "Relative deadline rendering applied: ${ddmEnforcedInstallDateRelativeHumanReadable}"
    fi

    # Blurscreen logic and secondary button hiding (based on precise timestamp comparison)
    nowEpoch=$(date +%s)
    effectiveDeadlineEpoch="${ddmEnforcedInstallDateEpoch}"
    if [[ -z "${effectiveDeadlineEpoch}" || ! "${effectiveDeadlineEpoch}" =~ ^[0-9]+$ ]]; then
        effectiveDeadlineEpoch="${deadlineEpoch}"
    fi
    secondsUntilDeadline=$(( effectiveDeadlineEpoch - nowEpoch ))
    blurThresholdSeconds=$(( daysBeforeDeadlineBlurscreen * 86400 ))
    hideButton2ThresholdSeconds=$(( daysBeforeDeadlineHidingButton2 * 86400 ))
    ddmVersionStringDaysRemaining=$(( (secondsUntilDeadline + 43200) / 86400 )) # Round to nearest whole day
    if (( secondsUntilDeadline <= blurThresholdSeconds )); then
        blurscreen="--blurscreen"
    else
        blurscreen="--noblurscreen"
    fi
    setHideSecondaryButtonState "${secondsUntilDeadline}" "${hideButton2ThresholdSeconds}"

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
            updateOrUpgradeMode="upgrade"
        else
            updateOrUpgradeMode="update"
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
    local userDisplaySleepAssertions="FALSE"

    if (( maxChecks <= 0 )); then
        info "Meeting delay is set to ${meetingDelay} minute(s); skipping Display Sleep Assertion retry loop."
        return 0
    fi

    # Plist-sourced meeting-app allowlist (space-delimited string → array)
    local -a acceptableApps=( ${(s: :)acceptableAssertionApplicationNames} )
    if [[ ${#acceptableApps} -gt 0 ]]; then
        info "Acceptable assertion application names (allowlist): ${acceptableAssertionApplicationNames}"
    fi

    while (( checkCount < maxChecks )); do
        local previousIFS="${IFS}"
        IFS=$'\n'

        local displayAssertionsArray
        displayAssertionsArray=( $(pmset -g assertions | awk '/NoDisplaySleepAssertion | PreventUserIdleDisplaySleep/ && match($0,/\(.+\)/) && ! /coreaudiod/ {gsub(/^\ +/,"",$0); print};') )

        # Layer 2: keep only assertions from allowlisted meeting/presentation apps
        if [[ ${#acceptableApps} -gt 0 ]]; then
            local -a filteredAssertions=()
            local hadAssertionsBeforeFiltering=false
            [[ ${#displayAssertionsArray} -gt 0 ]] && hadAssertionsBeforeFiltering=true
            
            for displayAssertion in "${displayAssertionsArray[@]}"; do
                local isAllowlisted=false
                for app in "${acceptableApps[@]}"; do
                    if echo "${displayAssertion}" | grep -qiF "${app}"; then
                        isAllowlisted=true
                        info "Assertion line matches allowlist entry '${app}'; deferring."
                        break
                    fi
                done
                [[ "${isAllowlisted}" == "true" ]] && filteredAssertions+=( "${displayAssertion}" )
            done
            
            # Troubleshooting tip when allowlist is populated but no assertions matched
            if [[ "${hadAssertionsBeforeFiltering}" == "true" ]] && [[ ${#filteredAssertions} -eq 0 ]] && [[ ${#displayAssertionsArray} -gt 0 ]]; then
                info "Assertions detected but none matched allowlist entries; proceeding. To verify exact app names, run: pmset -g assertions | grep -E 'NoDisplaySleepAssertion|PreventUserIdleDisplaySleep'"
            fi
            
            displayAssertionsArray=( "${filteredAssertions[@]}" )
        fi

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
        return 0  # Proceed after full delay
    fi

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Required Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function detectDarkMode() {
    local interfaceStyle
    local globalPreferencesPath="${loggedInUserHomeDirectory}/Library/Preferences/.GlobalPreferences.plist"
    
    if [[ -z "${loggedInUserHomeDirectory}" ]]; then
        globalPreferencesPath="/Users/${loggedInUser}/Library/Preferences/.GlobalPreferences.plist"
    fi
    
    interfaceStyle=$( defaults read "${globalPreferencesPath}" AppleInterfaceStyle 2>/dev/null )
    if [[ "${interfaceStyle}" == "Dark" ]]; then
        echo "Dark"
    else
        echo "Light"
    fi
}

function downloadBrandingAssets() {
    # Detect dark mode and choose appropriate icon URL
    local appearanceMode=$(detectDarkMode)
    local overlayIconURL="${organizationOverlayiconURL}"
    
    if [[ "${appearanceMode}" == "Dark" && -n "${organizationOverlayiconURLdark}" ]]; then
        notice "Dark mode detected; using dark mode overlay icon"
        overlayIconURL="${organizationOverlayiconURLdark}"
    else
        if [[ "${appearanceMode}" == "Dark" ]]; then
            notice "Dark mode detected but no dark mode icon URL configured; using standard overlay icon"
        else
            notice "Light mode detected; using standard overlay icon"
        fi
    fi
    
    # Download overlay icon
    if [[ -n "${overlayIconURL}" ]]; then
        notice "Processing overlay icon from '${overlayIconURL}'"
        
        # Check if it's a local file path (file or directory/bundle)
        if [[ -e "${overlayIconURL}" ]]; then
            info "Overlay icon is a local path; using directly"
            overlayicon="${overlayIconURL}"
            info "Successfully configured overlay icon"
        
        # Check if it's a file:// URI
        elif [[ "${overlayIconURL}" =~ ^file:// ]]; then
            info "Overlay icon is a file:// URI; converting to path"
            local filePath="${overlayIconURL#file://}"
            if [[ -e "${filePath}" ]]; then
                overlayicon="${filePath}"
                info "Successfully configured overlay icon from file:// URI"
            else
                error "Path not found: '${filePath}' (from URI '${overlayIconURL}')"
                overlayicon="/System/Library/CoreServices/Finder.app"
            fi
        
        # Assume it's a remote URL
        else
            info "Overlay icon appears to be a remote URL; downloading with curl"
            if curl -o "/var/tmp/overlayicon.png" "${overlayIconURL}" --silent --show-error --fail --max-time 10; then
                overlayicon="/var/tmp/overlayicon.png"
                info "Successfully downloaded overlay icon"
            else
                error "Failed to download overlay icon from '${overlayIconURL}'"
                overlayicon="/System/Library/CoreServices/Finder.app"
            fi
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

    # When restart workflow is suppressed for low uptime, avoid contradictory restart-oriented uptime warnings.
    if [[ "${pastDeadlineRestartSuppressedForUptime}" == "YES" ]]; then
        excessiveUptimeWarningMessage=""
    fi
    
    # Disk Space Warning
    if [[ "${freePercentage}" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        local belowThreshold=$(echo "${freePercentage} < ${minimumDiskFreePercentage}" | bc)
        [[ "${belowThreshold}" -ne 1 ]] && diskSpaceWarningMessage=""
    else
        warning "freePercentage '${freePercentage}' is not numeric; suppressing disk-space warning logic."
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
    baseDeadlineEnforcementMessage=${baseDeadlineEnforcementMessage//\$\{titleMessageUpdateOrUpgrade:l\}/${titleMessageUpdateOrUpgrade:l}}
    baseDeadlineEnforcementMessage=${baseDeadlineEnforcementMessage//\$\{titleMessageUpdateOrUpgrade\}/${titleMessageUpdateOrUpgrade}}
    baseDeadlineEnforcementMessage=${baseDeadlineEnforcementMessage//\{titleMessageUpdateOrUpgrade:l\}/${titleMessageUpdateOrUpgrade:l}}
    baseDeadlineEnforcementMessage=${baseDeadlineEnforcementMessage//\{titleMessageUpdateOrUpgrade\}/${titleMessageUpdateOrUpgrade}}

    dialogVersion="$(${dialogBinary} -v 2>/dev/null)"

    if [[ -n "${dialogVersion}" ]] && is-at-least "${markdownColorMinimumVersion}" "${dialogVersion}"; then
        dialogSupportsMarkdownColor="YES"
        deadlineEnforcementMessage=":red[${baseDeadlineEnforcementMessage}]"
        info "swiftDialog ${dialogVersion} supports markdown color; rendering enforcement sentence in red."
    else
        dialogSupportsMarkdownColor="NO"
        deadlineEnforcementMessage="${baseDeadlineEnforcementMessage}"
        info "swiftDialog ${dialogVersion:-Unknown} does not support markdown color; rendering enforcement sentence without color."
    fi
}

function computeInfoboxHighlights() {
    infoboxDeadlineDisplay="${ddmVersionStringDeadlineHumanReadable}"
    infoboxDaysRemainingDisplay="${ddmVersionStringDaysRemaining}"
    infoboxLastRestartDisplay="${uptimeHumanReadable}"
    local infoboxDeadlineEpoch="${ddmEnforcedInstallDateEpoch:-${deadlineEpoch}}"

    infoboxDeadlineDisplay="$(trimSurroundingWhitespace "${infoboxDeadlineDisplay}")"

    if [[ "${dialogSupportsMarkdownColor}" != "YES" ]]; then
        return
    fi

    if [[ -n "${infoboxDeadlineEpoch}" && "${infoboxDeadlineEpoch}" =~ ^[0-9]+$ ]] && (( infoboxDeadlineEpoch <= $(date +%s) )); then
        infoboxDeadlineDisplay=":red[${infoboxDeadlineDisplay}]"
    fi

    if [[ "${ddmVersionStringDaysRemaining}" =~ ^-?[0-9]+$ ]] && (( ddmVersionStringDaysRemaining <= 0 )); then
        infoboxDaysRemainingDisplay=":red[${infoboxDaysRemainingDisplay}]"
    fi

    if [[ "${pastDeadlineRestartSuppressedForUptime}" != "YES" ]] && (( upTimeMin >= (daysOfExcessiveUptimeWarning * 1440) )); then
        infoboxLastRestartDisplay=":red[${infoboxLastRestartDisplay}]"
    fi
}

function evaluatePastDeadlineState() {
    local nowEpochValue=$(date +%s)
    local daysPastDdmDeadline=0
    local isPastDdmDeadline="NO"
    local isPastDeadlineRestartThresholdMet="NO"
    local isPastDeadlineUptimeThresholdMet="NO"
    local isPastDeadlineEligible="NO"
    local deadlineReferenceEpoch="${ddmEnforcedInstallDateEpoch:-${deadlineEpoch}}"

    pastDeadlineRestartSuppressedForUptime="NO"

    if [[ -n "${deadlineReferenceEpoch}" && "${deadlineReferenceEpoch}" =~ ^[0-9]+$ ]] && (( deadlineReferenceEpoch <= nowEpochValue )); then
        isPastDdmDeadline="YES"
        daysPastDdmDeadline=$(( (nowEpochValue - deadlineReferenceEpoch) / 86400 ))
    fi

    if (( daysPastDdmDeadline >= daysPastDeadlineRestartWorkflow )); then
        isPastDeadlineRestartThresholdMet="YES"
    fi

    if (( upTimeMin >= pastDeadlineRestartMinimumUptimeMinutes )); then
        isPastDeadlineUptimeThresholdMet="YES"
    fi

    if [[ "${versionComparisonResult}" == "Update Required" && "${isPastDdmDeadline}" == "YES" && "${isPastDeadlineRestartThresholdMet}" == "YES" && "${pastDeadlineRestartBehavior}" != "Off" && "${isPastDeadlineUptimeThresholdMet}" == "YES" ]]; then
        isPastDeadlineEligible="YES"
    fi

    if [[ "${isPastDeadlineEligible}" == "YES" ]]; then
        pastDeadlineRestartEffective="${pastDeadlineRestartBehavior}"
        notice "Past Deadline mode '${pastDeadlineRestartEffective}' enabled (${daysPastDdmDeadline} day(s) past DDM deadline; threshold ${daysPastDeadlineRestartWorkflow} day(s); uptime ${upTimeMin} minute(s), minimum ${pastDeadlineRestartMinimumUptimeMinutes} minute(s))."
    else
        pastDeadlineRestartEffective="Off"
        if [[ "${versionComparisonResult}" == "Update Required" && "${isPastDdmDeadline}" == "YES" && "${isPastDeadlineRestartThresholdMet}" == "YES" && "${pastDeadlineRestartBehavior}" != "Off" && "${isPastDeadlineUptimeThresholdMet}" != "YES" ]]; then
            pastDeadlineRestartSuppressedForUptime="YES"
            notice "Past Deadline mode '${pastDeadlineRestartBehavior}' suppressed: uptime ${upTimeMin} minute(s) is below minimum ${pastDeadlineRestartMinimumUptimeMinutes} minute(s); continuing update/upgrade workflow."
        fi
    fi
}

function isPastDeadlineForceMode() {
    [[ "${pastDeadlineRestartEffective}" == "Force" ]]
}

function applyPastDeadlineDialogOverrides() {
    if [[ "${pastDeadlineRestartEffective}" == "Off" ]]; then
        return
    fi

    action="restartConfirm"
    button2text=""
    infobuttontext=""
    # helpmessage=""
    # helpimage=""
    hideSecondaryButton="YES"

    if isPastDeadlineForceMode; then
        softwareUpdateButtonText="${restartNowButtonText}"
        button1text="${restartNowButtonText}"
        title="${pastDeadlineForceTitle}"
        message="${pastDeadlineForceMessage}"
    else
        softwareUpdateButtonText="${restartNowButtonText}"
        button1text="${restartNowButtonText}"
        title="${pastDeadlinePromptTitle}"
        message="${pastDeadlinePromptMessage}"
    fi

    # Restart-focused dialog mode intentionally suppresses extra warning blocks.
    excessiveUptimeWarningMessage=""
    diskSpaceWarningMessage=""
    updateReadyMessage=""
    deadlineEnforcementMessage=""
}

function executeRestartAction() {
    local restartMode="${1:-Restart Confirm}"
    local restartCommand=""

    case "${restartMode}" in
        "Restart")
            restartCommand="sleep 1 && shutdown -r now &"
            if /bin/zsh -c "${restartCommand}"; then
                notice "Restart command '${restartMode}' sent as root: ${restartCommand}"
                return 0
            fi
            warning "Failed to invoke restart command '${restartMode}' as root: ${restartCommand}"
            return 1
            ;;
        "Restart Confirm"|*)
            restartCommand="/usr/bin/osascript -e 'tell app \"loginwindow\" to «event aevtrrst»'"
            ;;
    esac

    if /usr/bin/su - "${loggedInUser}" -c "${restartCommand}"; then
        notice "Restart command '${restartMode}' sent for ${loggedInUser}."
        return 0
    fi

    warning "Failed to invoke restart command '${restartMode}' for ${loggedInUser}."
    return 1
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
        --quitkey "k"
        --width 800
        --height 650
        "${blurscreen}"
        "${additionalDialogOptions[@]}"
    )

    [[ -n "${button2text}" ]] && dialogArgs+=(--button2text "${button2text}")
    [[ "${hideSecondaryButton}" == "DISABLED" ]] && dialogArgs+=(--button2disabled)
    [[ -n "${infobuttontext}" ]] && dialogArgs+=(--infobuttontext "${infobuttontext}")
    [[ -n "${helpmessage}" ]] && dialogArgs+=(--helpmessage "${helpmessage}")
    [[ -n "${helpimage}" ]] && dialogArgs+=(--helpimage "${helpimage}")

    ${dialogBinary} "${dialogArgs[@]}"

    returncode=$?
    info "Return Code: ${returncode}"

    if isPastDeadlineForceMode; then
        while true; do
            case ${returncode} in
                0)
                    notice "${loggedInUser} clicked ${button1text}"
                    if executeRestartAction "Restart"; then
                        quitScript "0"
                    fi
                    ;;
                4)
                    notice "User allowed timer to expire; forcing restart."
                    if executeRestartAction "Restart"; then
                        quitScript "0"
                    fi
                    ;;
                *)
                    warning "Force mode active; return code '${returncode}' does not permit dismissal. Re-displaying restart dialog."
                    ;;
            esac

            sleep "${pastDeadlineRedisplayDelaySeconds}"
            ${dialogBinary} "${dialogArgs[@]}"
            returncode=$?
            info "Return Code: ${returncode}"
        done
    fi

    case ${returncode} in

    0)  ## Process exit code 0 scenario here
        notice "${loggedInUser} clicked ${button1text}"
        case "${action}" in
            "restartConfirm")
                if executeRestartAction "Restart Confirm"; then
                    quitScript "0"
                else
                    quitScript "1"
                fi
                ;;
            *"systempreferences"*)
                launchctl asuser "${loggedInUserID}" su - "${loggedInUser}" -c "open '$action'"
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
                ;;
            *)
                launchctl asuser "${loggedInUserID}" su - "${loggedInUser}" -c "open '$action'"
                ;;
        esac
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
            case "${hideSecondaryButton}" in
                "YES"|"DISABLED")
                    info "Within ${daysBeforeDeadlineHidingButton2} day(s) of deadline; waiting 61 seconds before re-showing dialog …"
                    sleep 61
                    blurscreen="--noblurscreen"
                    displayReminderDialog --ontop --moveable
                    ;;
                *)
                    info "Deadline is more than ${daysBeforeDeadlineHidingButton2} day(s) away; not re-showing dialog after ${loggedInUser} clicked ${infobuttontext}."
                    ;;
            esac
            ;;

        4)  ## Process exit code 4 scenario here
            notice "User allowed timer to expire"
            quitScript "0"
            ;;

        9)  ## Process exit code 9 scenario here
            warning "swiftDialog exited with code 9; confirm your .plist or .mobileconfig is installed:"
            info "Expected managedPreferencesPlist: ${managedPreferencesPlist}"
            info "Expected localPreferencesPlist: ${localPreferencesPlist}"
            quitScript "${returncode}"
            ;;

        10) ## Process exit code 10 scenario here
            notice "User quit the dialog with keyboard shortcut"
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

function displayReminderDialogForMode() {
    if isPastDeadlineForceMode; then
        displayReminderDialog --ontop --timer "${pastDeadlineForceTimerSeconds}"
    else
        displayReminderDialog --ontop
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Quit Script (thanks, @bartreadon!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function quitScript() {

    quitOut "Exiting …"

    # Remove downloaded icons (only those created in /var/tmp, not original paths)
    for img in "${icon}" "${overlayicon}"; do
        if [[ "${img}" == /var/tmp/* ]] && [[ -e "${img}" ]]; then
            rm -rf "${img}"
        fi
    done

    # Remove default dialog.log
    rm -f /var/tmp/dialog.log

    quitOut "When the sun beats down and I lie on the bench …"

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
    if [[ -f "${scriptLog}" ]]; then
        logSize=$(stat -f%z "${scriptLog}" 2>/dev/null || echo "0")
        maxLogSize=$((10 * 1024 * 1024))  # 10MB
        
        if (( logSize > maxLogSize )); then
            preFlight "Log file exceeds ${maxLogSize} bytes; rotating"
            mv "${scriptLog}" "${scriptLog}.${currentTime}.old"
            touch "${scriptLog}"
            preFlight "Log file rotated; previous log saved as ${scriptLog}.${currentTime}.old"
        fi
    fi
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})\n# http://snelson.us/ddm\n###\n"
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

maxWait=120  # 2 minutes
counter=0
until [[ -n "${loggedInUser}" && "${loggedInUser}" != "loginwindow" ]]; do
    if [[ "${counter}" -ge "${maxWait}" ]]; then
        fatal "No valid user logged in after ${maxWait} seconds; exiting."
    fi
    sleep 1
    ((counter++))
    currentLoggedInUser
    preFlight "Logged-in User Counter: ${counter}"
done

loggedInUserFullname=$( id -F "${loggedInUser}" )
loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}' )
loggedInUserID=$( id -u "${loggedInUser}" )
loggedInUserHomeDirectory=$( dscl . read "/Users/${loggedInUser}" NFSHomeDirectory | awk -F ' ' '{print $2}' )
preFlight "Current Logged-in User First Name (ID): ${loggedInUserFirstname} (${loggedInUserID})"



####################################################################################################
#
# Apply / Validate Preference Overrides
#
####################################################################################################

loadPreferenceOverrides

validatePreferenceLoad
resolveDialogLanguage
initializeLocalizedRuntimeFields



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
evaluatePastDeadlineState



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# If Update Required, Display Dialog Window (respecting Display Reminder threshold)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${versionComparisonResult}" == "Update Required" ]]; then

    # -------------------------------------------------------------------------
    # Deadline window and periodic reminder logic (thanks for the suggestion, @kristian!)
    # -------------------------------------------------------------------------

    quietPeriodSeconds=4560     # 76 minutes (60 minutes + margin)
    periodicReminderDays=28     # 28 days
    periodicReminderSeconds=$(( periodicReminderDays * 86400 ))

    # Look for the most recent user interaction by Return Code
    # Return Code 0: User clicked Button 1 (Open Software Update)
    # Return Code 2: User clicked Button 2 (Remind Me Later)
    # Return Code 3: User clicked Info Button
    # Return Code 4: User allowed timer to expire
    # Return Code 10: User quit dialog with keyboard shortcut
    # These are the events that indicate the user consciously dismissed / acknowledged the dialog

    lastInteractionLineWithNumber=$(grep -n -E '\[INFO\].*Return Code: (0|2|3|4|10)' "${scriptLog}" | tail -1)
    lastInteractionLineNumber=$(echo "${lastInteractionLineWithNumber}" | cut -d: -f1)
    lastInteractionLine=$(echo "${lastInteractionLineWithNumber}" | cut -d: -f2-)
    lastInteraction=$(echo "${lastInteractionLine}" | sed -E 's/^[^:]+: ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/')

    # Ignore restart-mode interactions so a post-reboot update/upgrade reminder is not suppressed.
    if [[ -n "${lastInteraction}" && -n "${lastInteractionLineNumber}" ]]; then
        restartRelatedPattern="forcing restart|Restart command 'Restart( Confirm)?'|Failed to invoke restart command 'Restart( Confirm)?'"
        restartRelatedAtLastInteraction=$(awk -v startLine="${lastInteractionLineNumber}" -v restartPattern="${restartRelatedPattern}" '
            NR <= startLine { next }
            /\[INFO\].*Return Code: (0|2|3|4|10)/ { exit }
            $0 ~ restartPattern { print; exit }
        ' "${scriptLog}")
        if [[ -n "${restartRelatedAtLastInteraction}" ]]; then
            notice "Most recent interaction was restart-related; excluding it from quiet-period suppression."
            lastInteraction=""
        fi
    fi

    if (( ddmVersionStringDaysRemaining > daysBeforeDeadlineDisplayReminder )); then
        # Outside the deadline window; check if we should display initial/periodic reminder
        
        if [[ -z "${lastInteraction}" ]]; then
            # No interaction history; display the initial reminder dialog
            notice "No reminder interaction history found; displaying initial reminder dialog"
        else
            # Validate the extracted timestamp matches expected format
            if [[ "${lastInteraction}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                nowEpoch=$(date +%s)
                lastEpoch=$( date -j -f "%Y-%m-%d %H:%M:%S" "${lastInteraction}" +"%s" 2>/dev/null )
                if [[ -n "${lastEpoch}" ]]; then
                    delta=$(( nowEpoch - lastEpoch ))
                    if (( delta >= periodicReminderSeconds )); then
                        # Last interaction was 28+ days ago; display periodic reminder
                        daysAgo=$(( delta / 86400 ))
                        notice "Last reminder interaction was ${daysAgo} day(s) ago; displaying periodic reminder dialog"
                    else
                        # Last interaction was within 28 days; skip
                        daysAgo=$(( delta / 86400 ))
                        quitOut "Deadline still ${ddmVersionStringDaysRemaining} days away and last reminder was ${daysAgo} day(s) ago; exiting quietly."
                        quitScript "0"
                    fi
                else
                    info "Could not parse last interaction timestamp; proceeding with display"
                fi
            else
                info "Last interaction timestamp format invalid; proceeding with display"
            fi
        fi
    else
        notice "Within ${daysBeforeDeadlineDisplayReminder}-day reminder window; proceeding …"
    fi

    # -------------------------------------------------------------------------
    # Short quiet period: skip dialog if user interacted very recently
    # -------------------------------------------------------------------------

    if isPastDeadlineForceMode; then
        notice "Past Deadline Force mode active; bypassing quiet-period suppression."
    else
        if [[ -n "${lastInteraction}" ]]; then
            # Validate the extracted timestamp matches expected format
            if [[ "${lastInteraction}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                nowEpoch=$(date +%s)
                lastEpoch=$( date -j -f "%Y-%m-%d %H:%M:%S" "${lastInteraction}" +"%s" 2>/dev/null )
                if [[ -n "${lastEpoch}" ]]; then
                    delta=$(( nowEpoch - lastEpoch ))
                    if (( delta < quietPeriodSeconds )); then
                        minutesAgo=$(( delta / 60 ))
                        quitOut "User last interacted with reminder dialog ${minutesAgo} minute(s) ago; exiting quietly."
                        quitScript "0"
                    fi
                fi
            fi
        fi
    fi



    # -------------------------------------------------------------------------
    # Confirm the currently logged-in user is “available” to be reminded
    # -------------------------------------------------------------------------

    if isPastDeadlineForceMode; then
        notice "Past Deadline Force mode active; bypassing meeting-delay checks."
    else
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

    # Skip sleep pause for beta / RC builds
    if [[ "${scriptVersion}" =~ [a-zA-Z] ]]; then
        notice "Beta / RC build detected (${scriptVersion}); skipping pause"
    else
        info "Pausing for ${humanReadablePause} …"
        sleep "${sleepSeconds}"
    fi



    # -------------------------------------------------------------------------
    # Continue with normal processing
    # -------------------------------------------------------------------------

    updateRequiredVariables
    displayReminderDialogForMode

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
#   The following function creates the LaunchDaemon which executes the previously created,
#   client-side "reminderDialog.zsh" script.
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
    
    launchDaemonStatusResult=$( launchctl list | grep "${launchDaemonLabel}" )

    if [[ -n "${launchDaemonStatusResult}" ]]; then
        logComment "${launchDaemonStatusResult}"
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
    if [[ -f "${scriptLog}" ]]; then
        logSize=$(stat -f%z "${scriptLog}" 2>/dev/null || echo "0")
        maxLogSize=$((10 * 1024 * 1024))  # 10MB
        
        if (( logSize > maxLogSize )); then
            currentTime=$(date '+%Y-%m-%d-%H%M%S')
            preFlight "Log file exceeds ${maxLogSize} bytes; rotating"
            mv "${scriptLog}" "${scriptLog}.${currentTime}.old"
            touch "${scriptLog}"
            preFlight "Log file rotated; previous log saved as ${scriptLog}.${currentTime}.old"
        fi
    fi
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
    dialogURL=$(curl -L --silent --fail --connect-timeout 10 --max-time 30 \
        "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" \
        | awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }")
    
    # Validate URL was retrieved
    if [[ -z "${dialogURL}" ]]; then
        fatal "Failed to retrieve swiftDialog download URL from GitHub API"
    fi
    
    # Validate URL format
    if [[ ! "${dialogURL}" =~ ^https://github\.com/ ]]; then
        fatal "Invalid swiftDialog URL format: ${dialogURL}"
    fi

    # Expected Team ID of the downloaded PKG
    expectedDialogTeamID="PWA5E9TQ59"

    preFlight "Installing swiftDialog from ${dialogURL}..."

    # Create temporary working directory
    workDirectory=$( basename "$0" )
    tempDirectory=$( mktemp -d "/private/tmp/$workDirectory.XXXXXX" )

    # Download the installer package with timeouts
    if ! curl --location --silent --fail --connect-timeout 10 --max-time 60 \
             "$dialogURL" -o "$tempDirectory/Dialog.pkg"; then
        rm -Rf "$tempDirectory"
        fatal "Failed to download swiftDialog package"
    fi

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
    if [[ ! -x "/Library/Application Support/Dialog/Dialog.app" ]]; then

        preFlight "swiftDialog not found; installing …"
        dialogInstall
        if [[ ! -x "/usr/local/bin/dialog" ]]; then
            fatal "swiftDialog still not found; are downloads from GitHub blocked on this Mac?"
        fi

    else

        dialogVersion=$(/usr/local/bin/dialog --version)
        if ! is-at-least "${swiftDialogMinimumRequiredVersion}" "${dialogVersion}"; then
            
            preFlight "swiftDialog version ${dialogVersion} found but swiftDialog ${swiftDialogMinimumRequiredVersion} or newer is required; updating …"
            dialogInstall
            if [[ ! -x "/usr/local/bin/dialog" ]]; then
                fatal "Unable to update swiftDialog; are downloads from GitHub blocked on this Mac?"
            fi

        else

            preFlight "swiftDialog version ${dialogVersion} found; proceeding …"

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

if [[ "${resetConfiguration}" != "Uninstall" ]]; then
    dialogCheck
fi



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

    if [[ -n "${launchDaemonStatusResult}" ]]; then

        logComment "${launchDaemonLabel} IS loaded"

    else

        logComment "Loading '${launchDaemonLabel}' …"
        launchctl bootstrap system "${launchDaemonPath}"
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
