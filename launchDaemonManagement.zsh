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
# Version 2.1.0b11, 12-Dec-2025, Dan K. Snelson (@dan-snelson)
#   - Added ability to use `titleMessageUpdateOrUpgrade:l` (Pull Request #26; thanks, @maxsundellacne!)
#   - Added logic to hide `button2` based on `DaysBeforeDeadlineHidingButton2` (Pull Request #27; thanks, @maxsundellacne!)
#   - Refactored `resetConfiguration` function to avoid errors when attempting to `chmod` non-existent files
#   - Added warning for excessive uptime (configurable via `DaysOfExcessiveUptimeWarning` variable; Feature Request #28)
#   - Added logic for when the reminder dialog is re-displayed after clicking the `infobutton` (based on if we're already hiding the secondary button; #31)
#   - Streamline Deployment & Documentation (Feature Request #35)
#   - Addressed Bugs #34 (thanks, @TechTrekkie!) and #36 (I. Blame. AI.)
#   - Refactored `assemble.zsh` (thanks for the feedback, @Andrew!)
#   - Added warning for low disk space (configurable via `minimumDiskFreePercentage` variable; Feature Request #39. (Thanks for the suggestion, @prgsenright!)
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="2.1.0b11"

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

# Organization's Reverse Domain Name Notation (i.e., com.company.division)
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
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# CREATE DDM OS REMINDER SCRIPT
#
#   The following function creates the client-side DDM OS Reminder script, which dynamically
#   generates the end-user message.
#
#   Either copy-pasta your organization's customized "DDM-OS-Reminder End-user Message.zsh"
#   script between the "cat <<ENDOFSCRIPT" and "ENDOFSCRIPT" lines below — making sure to leave
#   a full return at the end of the content before the "ENDOFSCRIPT" line — or use the new
#   `Resources/assembleDDMOSReminder.zsh` script to automatically assemble your organization's
#   customized script:
#
#       cd Resources
#       zsh assembleDDMOSReminder.zsh
#
#   NOTE: With manual assembly, you'll most likely want to modify the `updateScriptLog` function
#   in the copied script to comment out (or remove) the "| tee -a "${scriptLog}" portion of the line
#   to avoid duplicate entries in the log file.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

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
        fatal "Unable to create specified scriptLog '${scriptLog}'; exiting.\n\n(Is this script running as 'root' ?)"
    fi
else
    # preFlight "Specified scriptLog '${scriptLog}' exists; writing log entries to it"
fi




# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Logging Preamble
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})\n# http://snelson.us/ddm\n#\n# Reset Configuration: ${resetConfiguration}\n###\n"
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
        osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "DDM OS Reminder Error" buttons {"Close"} with icon caution'
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

exit 0
