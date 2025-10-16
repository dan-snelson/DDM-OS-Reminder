#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Declarative Device Management macOS Reminder: End-user Message
#
# A swiftDialog and LaunchDaemon pair for “set-it-and-forget-it” end-user messaging of
# Apple’s Declarative Device Management-required macOS updates
#
# http://snelson.us/ddm-os-reminder
#
####################################################################################################
#
# HISTORY
#
# Version 1.1.0, 16-Oct-2025, Dan K. Snelson (@dan-snelson)
#   - Refactored `infobuttonaction` to disable blurscreen (Pull Request #2; thanks, @TechTrekkie!)
#   - Updated `message` to clarify update instructions
#   - Added `checkUserFocusDisplayAssertions` function to avoid interrupting users with Focus modes or Display Sleep Assertions enabled (thanks, @TechTrekkie!)
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="1.1.0b1"

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



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Logged-in User Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )
loggedInUserFullname=$( id -F "${loggedInUser}" )
loggedInUserFirstname=$( echo "$loggedInUserFullname" | sed -E 's/^.*, // ; s/([^ ]*).*/\1/' | sed 's/\(.\{25\}\).*/\1…/' | awk '{print ( $0 == toupper($0) ? toupper(substr($0,1,1))substr(tolower($0),2) : toupper(substr($0,1,1))substr($0,2) )}' )
loggedInUserID=$( id -u "${loggedInUser}" )
loggedInUserHomeDirectory=$( dscl . read "/Users/${loggedInUser}" NFSHomeDirectory | awk -F ' ' '{print $2}' )



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
# Check User Focus and Display Assertions (thanks, @techtrekkie!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function checkUserFocusDisplayAssertions() {

    notice "Check User Focus and Display Assertions"

    # Check for Focus or Do Not Disturb
    focusResponse=$( plutil -extract data.0.storeAssertionRecords.0.assertionDetails.assertionDetailsModeIdentifier raw -o - "/Users/${loggedInUser}/Library/DoNotDisturb/DB/Assertions.json" | grep -ic 'com.apple.' )
    if [[ "${focusResponse}" -gt 0 ]]; then
        userFocusActive="TRUE"
    else
        userFocusActive="FALSE"
    fi
    # info "${loggedInUser}'s Focus or Do Not Disturb is ${userFocusActive}."

    # Check for Display Sleep Assertions
    local previousIFS
    previousIFS="${IFS}"; IFS=$'\n'
    local displayAssertionsArray
    displayAssertionsArray=( $(pmset -g assertions | awk '/NoDisplaySleepAssertion | PreventUserIdleDisplaySleep/ && match($0,/\(.+\)/) && ! /coreaudiod/ {gsub(/^\ +/,"",$0); print};') )
    # info "displayAssertionsArray:\n${displayAssertionsArray[*]}"
    if [[ -n "${displayAssertionsArray[*]}" ]]; then
        userDisplayAssertions="TRUE"
        for displayAssertion in "${displayAssertionsArray[@]}"; do
            # info "Found the following Display Sleep Assertion(s): $(echo "${displayAssertion}" | awk -F ':' '{print $1;}')"
        done
    else
        userDisplayAssertions="FALSE"
    fi
    # info "${loggedInUser}'s Display Sleep Assertion is ${userDisplayAssertions}."
    IFS="${previousIFS}"

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
    message="**A required macOS update is now available**<br>---<br>Happy $( date +'%A' ), ${loggedInUserFirstname}!<br><br>Please update to macOS **${ddmVersionString}** to ensure your Mac remains secure and compliant with organizational policies.<br><br>To perform the update now, click **${button1text}**, review the on-screen instructions, then click **Restart Now**.<br><br>If you are unable to perform this update now, click **${button2text}** to be reminded again later.<br><br>However, your device **will automatically restart and update** on **${ddmEnforcedInstallDateHumanReadable}** if you have not updated before the deadline.<br><br>For assistance, please contact **${supportTeamName}** by clicking the (?) button in the bottom, right-hand corner."
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
                su \- "$(stat -f%Su /dev/console)" -c "open '${action}'"
            fi
            quitScript "0"
            ;;

        2)  ## Process exit code 2 scenario here
            notice "User clicked ${button2text}"
            quitScript "0"
            ;;

        3)  ## Process exit code 3 scenario here
            notice "User clicked ${infobuttontext}"
            echo "blurscreen: disable" >> /var/tmp/dialog.log
            su \- "$(stat -f%Su /dev/console)" -c "open '${infobuttonaction}'"
            quitScript "0"
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

preFlight "\n\n###\n# $humanReadableScriptName (${scriptVersion})\n# http://snelson.us/ddm-os-reminder\n####\n"
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

    # Confirm the currently logged-in user is "available" to be reminded
    checkUserFocusDisplayAssertions
    if [[ "${userFocusActive}" == "TRUE" ]] || [[ "${userDisplayAssertions}" == "TRUE" ]]; then
        info "User has a Focus mode enabled and / or a Display Assertion is active; exiting."
        quitScript "0"
    else
        info "User is 'available.'"
    fi

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
