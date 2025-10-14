#!/bin/zsh --no-rcs 
# shellcheck shell=bash

####################################################################################################
#
# DDM OS Reminder
# https://snelson.us/ddm-os-reminder
#
# A swiftDialog and LaunchDaemon pair for "set-it-and-forget-it" end-user messaging for
# DDM-required macOS updates
#
# While Apple's Declarative Device Management (DDM) provides Mac Admins a powerful method to enforce
# macOS updates, its built-in notification tends to be too subtle for most Mac Admins.
#
# DDM OS Reminder evaluates the most recent `EnforcedInstallDate` entry in `/var/log/install.log`,
# then leverages a swiftDialog and LaunchDaemon pair to dynamically deliver a more prominent
# end-user message of when the user's Mac needs to be updated to comply with DDM-configured OS
# version requirements.
#
####################################################################################################
#
# HISTORY
#
#   Version 1.0.0, 14-Oct-2025, Dan K. Snelson (@dan-snelson)
#   - First "official" release
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="1.0.0"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Jamf Pro Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Parameter 4: Configuration Files to Reset (i.e., None (blank) | All | LaunchDaemon | Script | Uninstall )
resetConfiguration="${4:-"All"}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Organization Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Organization's Reverse Domain Name Notation (i.e., com.company.division)
reverseDomainNameNotation="org.churchofjesuschrist"

# Script Human-readabale Name
humanReadableScriptName="DDM OS Reminder"

# Organization's Script Name
organizationScriptName="dor "

# Organization's Directory (i.e., where your client-side scripts reside)
organizationDirectory="/Library/Management/org.churchofjesuschrist"

# LaunchDaemon Name & Path
launchDaemonName="${reverseDomainNameNotation}.${organizationScriptName}.plist"
launchDaemonPath="/Library/LaunchDaemons/${launchDaemonName}"



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
# Reset Configuration
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function resetConfiguration() {

    notice "Reset Configuration: ${1}"

    # Ensure the directory exists
    mkdir -p "${organizationDirectory}/${reverseDomainNameNotation}"

    # Secure ownership
    chown -R root:wheel "${organizationDirectory}"

    # Remove any ACLs that could leave it effectively writable
    chmod -N "${organizationDirectory}" 2>/dev/null || true
    chmod -N "${organizationDirectory}/${reverseDomainNameNotation}" 2>/dev/null || true

    # Secure directory permissions (no world-writable bits)
    chmod 755 "${organizationDirectory}"
    chmod 755 "${organizationDirectory}/${reverseDomainNameNotation}"

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



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# CREATE DDM OS REMINDER SCRIPT
#
#   The following function creates the client-side DDM OS Reminder script, which dynamically
#   generates the end-user message.
#
#   Copy-pasta your organization's customized "DDM-OS-Reminder End-user Message.zsh" script between
#   the "cat <<ENDOFSCRIPT" and "ENDOFSCRIPT" lines below, making sure to leave a full return
#   at the end of the content before the "ENDOFSCRIPT" line.
#
#   NOTE: You'll most likely want to modify the `updateScriptLog` function in the copied script to
#   comment out (or remove) the "| tee -a "${scriptLog}" portion of the line to avoid duplicate
#   entries in the log file.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

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
# A swiftDialog and LaunchDaemon pair for "set-it-and-forget-it" end-user notifications
# for DDM-required macOS updates
#
# https://github.com/dan-snelson/DDM-OS-Reminder
#
####################################################################################################
#
# HISTORY
#
# Version 1.0.0, 14-Oct-2025, Dan K. Snelson (@dan-snelson)
#   - First "official" release (thanks for the testing and feedback, @TechTrekkie!)
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="1.0.0"

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

# Organization's Days Before Deadline Blur Screen 
daysBeforeDeadlineBlurscreen="3"



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
# Installed OS vs. DDM-enforced OS Comparison
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function installedOSvsDDMenforcedOS() {

    # Installed OS Version
    installedOSVersion=$(sw_vers -productVersion)
    notice "Installed OS Version: $installedOSVersion"

    # DDM-enforced OS Version
    ddmEnforcedInstallDateRaw=$( grep EnforcedInstallDate /var/log/install.log | tail -n 1 )
    if [[ -n "$ddmEnforcedInstallDateRaw" ]]; then
        
        # DDM-enforced Install Date
        tmp=${ddmEnforcedInstallDateRaw##*|EnforcedInstallDate:}
        ddmEnforcedInstallDate=${tmp%%|*}
        
        # DDM-enforced Version
        tmp=${ddmEnforcedInstallDateRaw##*|VersionString:}
        ddmVersionString=${tmp%%|*}

        ddmEnforcedInstallDateHumanReadable=$(date -jf "%Y-%m-%dT%H" "$ddmEnforcedInstallDate" "+%a, %d-%b-%Y, %-l %p" 2>/dev/null)
        ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable/ AM/ a.m.}
        ddmEnforcedInstallDateHumanReadable=${ddmEnforcedInstallDateHumanReadable/ PM/ p.m.}

        ddmVersionStringDeadline=${ddmEnforcedInstallDate%%T*}
        deadlineEpoch=$(date -jf "%Y-%m-%d" "$ddmVersionStringDeadline" "+%s" 2>/dev/null)
        ddmVersionStringDaysRemaining=$(( (deadlineEpoch - $(date "+%s")) / 86400 ))

        if [[ "${ddmVersionStringDaysRemaining}" -le "${daysBeforeDeadlineBlurscreen}" ]]; then
            blurscreen="--blurscreen"
        else
            blurscreen="--noblurscreen"
        fi

    fi

    # Version Comparison Result
    if [[ -z "$ddmEnforcedInstallDate" ]]; then
        # No DDM-enforced macOS version found.
        versionComparisonResult="Not Found"
    elif is-at-least "${ddmVersionString}" "${installedOSVersion}"; then
        # macOS is up-to-date
        versionComparisonResult="Up-to-date"
        info "DDM-enforced OS Version: $ddmVersionString"
    else
        # macOS update required
        versionComparisonResult="Update Required"
        info "DDM-enforced OS Version: $ddmVersionString"
        info "DDM-enforced OS Version Deadline: $ddmVersionStringDeadline"
    fi

    notice "$versionComparisonResult"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Update Required Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateRequiredVariables() {

    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Organization's Branding Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    # Organization's Icon URL
    organizationIconURL="https://ics.services.jamfcloud.com/icon/hash_4555d9dc8fecb4e2678faffa8bdcf43cba110e81950e07a4ce3695ec2d5579ee"

    # Download the icon from ${organizationIconURL}
    if [[ -n "${organizationIconURL}" ]]; then
        notice "Downloading icon from '${organizationIconURL}' …"
        curl -o "/var/tmp/icon.png" "${organizationIconURL}" --silent --show-error --fail
        if [[ "$?" -ne 0 ]]; then
            error "Failed to download the icon from '${organizationIconURL}'."
            icon="/System/Library/CoreServices/Finder.app"
        else
            icon="/var/tmp/icon.png"
        fi
    fi



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # swiftDialog Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    # swiftDialog Binary Path
    dialogBinary="/usr/local/bin/dialog"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # IT Support Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    supportTeamName="IT Support"
    supportTeamPhone="+1 (801) 555-1212"
    supportTeamEmail="rescue@domain.org"
    supportTeamWebsite="https://support.domain.org"
    supportTeamHyperlink="[${supportTeamWebsite}](${supportTeamWebsite})"
    supportKB="KB8675309"
    infobuttonaction="https://servicenow.domain.org/support?id=kb_article_view&sysparm_article=${supportKB}"
    supportKBURL="[${supportKB}](${infobuttonaction})"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Title, Message and  Button Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    title="macOS Update Required"
    button1text="Open Software Update"
    button2text="Remind Me Later"
    message="**A required macOS update is now available**<br><br>Please update to **${ddmVersionString}** to ensure your Mac remains secure and compliant with organizational policies.<br><br>To perform the update now, click **${button1text}**, review the on-screen instructions, then click **Restart Now**.<br><br>If you are unable to perform this update now, click **${button2text}** to be reminded again later.<br><br>However, your device **will automatically restart and update** on **${ddmEnforcedInstallDateHumanReadable}** if you have not updated before the deadline.<br><br>For assistance, please contact **${supportTeamName}** by clicking the (?) button in the bottom, right-hand corner."
    infobuttontext="${supportKB}"
    action="x-apple.systempreferences:com.apple.preferences.softwareupdate"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Infobox Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    infobox="**Current:** ${installedOSVersion}<br><br>**Required:** ${ddmVersionString}<br><br>**Deadline:** ${ddmEnforcedInstallDateHumanReadable}<br><br>**Day(s) Remaining:** ${ddmVersionStringDaysRemaining}"



    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Help Message Variables
    # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

    helpmessage="For assistance, please contact: **${supportTeamName}**<br>- **Telephone:** ${supportTeamPhone}<br>- **Email:** ${supportTeamEmail}<br>- **Website:** ${supportTeamWebsite}<br>- **Knowledge Base Article:** ${supportKBURL}<br><br>**User Information:**<br>- **Full Name:** {userfullname}<br>- **User Name:** {username}<br><br>**Computer Information:**<br>- **Computer Name:** {computername}<br>- **Serial Number:** {serialnumber}<br>- **macOS:** {osversion}<br><br>**Script Information:**<br>- **Dialog:** $(/usr/local/bin/dialog -v)<br>- **Script:** ${scriptVersion}<br>"

    helpimage="qr=${infobuttonaction}"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Display Dialog Window
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function displayDialogWindow() {

    notice "Display Dialog Window"

    ${dialogBinary} \
        --title "${title}" \
        --message "${message}" \
        --icon "${icon}" \
        --iconsize 250 \
        --infobox "${infobox}" \
        --button1text "${button1text}" \
        --button2text "${button2text}" \
        --infobuttontext "${infobuttontext}" \
        --infobuttonaction "${infobuttonaction}" \
        --messagefont "size=14" \
        --helpmessage "${helpmessage}" \
        --helpimage "${helpimage}" \
        --width 750 \
        --height 600 \
        "${blurscreen}" \
        --ontop

    returncode=$?
    info "Return Code: ${returncode}"

    case ${returncode} in

        0)  ## Process exit code 0 scenario here
            notice "User clicked ${button1text}"
            if [[ -n "${action}" ]]; then
                su \- "$(stat -f%Su /dev/console)" -c "open \"${action}\""
            fi
            quitScript "0"
            ;;

        2)  ## Process exit code 2 scenario here
            notice "User clicked ${button2text}"
            quitScript "0"
            ;;

        3)  ## Process exit code 3 scenario here
            notice "User clicked ${infobuttontext}"
            ;;

        4)  ## Process exit code 4 scenario here
            notice "User allowed timer to expire"
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

    quitOut "Shine on, you crazy diamond!"

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

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})\n# https://snelson.us\n####\n"
preFlight "Initiating …"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(id -u) -ne 0 ]]; then
    fatal "This script must be run as root; exiting."
fi



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
# If Update Required, Display Dialog Window
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${versionComparisonResult}" == "Update Required" ]]; then

    # Randomly pause script during its launch hours of 8 a.m. and 4 p.m.; Login pause of 30-90 seconds
    currentHour=$(( $(date +%H) ))
    currentMinute=$(( $(date +%M) ))

    if (( currentHour == 8 || currentHour == 16 )) && (( currentMinute == 0 )); then
        notice "Daily Trigger Pause: Random 0 to 20 minutes"
        sleepSeconds=$(( RANDOM % 1200 ))
    else
        notice "Login Trigger Pause: Random 30 to 90 seconds"
        sleepSeconds=$(( 30 + RANDOM % 61 ))
    fi

    info "Pausing for ${sleepSeconds} seconds …"
    sleep "${sleepSeconds}"

    # Initialize Update Required Variables
    updateRequiredVariables

    # Create Main Dialog Window
    displayDialogWindow

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# No Update Required; Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

exit 0

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
    <string>${launchDaemonName}</string>
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

    logComment "Loading '${launchDaemonName}' …"
    launchctl bootstrap system "${launchDaemonPath}"
    launchctl start "${launchDaemonPath}"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LaunchDaemon Status
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function launchDaemonStatus() {

    notice "LaunchDaemon Status"
    
    launchDaemonStatus=$( launchctl list | grep "${launchDaemonName}" )

    if [[ -n "${launchDaemonStatus}" ]]; then
        logComment "${launchDaemonStatus}"
    else
        logComment "${launchDaemonName} is NOT loaded"
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
        fatal "Unable to create specified scriptLog '${scriptLog}'; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    # preFlight "Specified scriptLog '${scriptLog}' exists; writing log entries to it"
fi




# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})\n# https://snelson.us\n#\n# Reset Configuration: ${resetConfiguration}\n###\n"
preFlight "Initiating …"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Confirm script is running as root
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ $(id -u) -ne 0 ]]; then
    fatal "This script must be run as root; exiting."
fi



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
# Reset Configuration
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

resetConfiguration "${resetConfiguration}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Validation / Creation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "*** VALIDATING SCRIPT ***"

if [[ -f "${organizationDirectory}/${organizationScriptName}.zsh" ]]; then

    logComment "${humanReadableScriptName} script '"${organizationDirectory}/${organizationScriptName}.zsh"' exists"

else

    createDDMOSReminderScript

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LaunchDaemon Validation / Creation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "*** VALIDATING LAUNCHAGENT ***"

logComment "Checking for LaunchDaemon '${launchDaemonPath}' …"

if [[ -f "${launchDaemonPath}" ]]; then

    logComment "LaunchDaemon '${launchDaemonPath}' exists"

    launchDaemonStatus

    if [[ -n "${launchDaemonStatus}" ]]; then

        logComment "${launchDaemonName} IS loaded"

    else

        logComment "Loading '${launchDaemonName}' …"
        launchctl asuser $(id -u) bootstrap gui/$(id -u) "${launchDaemonPath}"
        launchDaemonStatus

    fi

else

    createLaunchDaemon

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Status Checks
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "*** STATUS CHECKS ***"

logComment "I/O pause …"
sleep 1.3

launchDaemonStatus



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

exit 0