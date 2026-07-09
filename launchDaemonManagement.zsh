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
scriptVersion="4.0.0"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Minimum Required Version of swiftDialog
swiftDialogMinimumRequiredVersion="3.0.1.4955"

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
dormScriptPath="${organizationDirectory}/${organizationScriptName}.zsh"
dorStarterPath="${organizationDirectory}/dor-starter.zsh"
dorStatePlistPath="${organizationDirectory}/dor-state.plist"
dorPidFilePath="${organizationDirectory}/dor.pid"

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
# Runtime Asset Cleanup
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function removeDeployedRuntimeAssets() {
    local runtimeAssetPath=""
    local runtimeAssetPaths=(
        "${dormScriptPath}"
        "${dorStarterPath}"
        "${dorStatePlistPath}"
        "${dorPidFilePath}"
    )

    for runtimeAssetPath in "${runtimeAssetPaths[@]}"; do
        logComment "Removing '${runtimeAssetPath}' … "
        rm -f "${runtimeAssetPath}" 2>/dev/null
        logComment "Removed '${runtimeAssetPath}'"
    done
}

function isDDMOSReminderLaunchDaemonPlist() {
    local candidatePath="${1}"
    local candidateLabel=""
    local programArguments=""

    [[ -f "${candidatePath}" ]] || return 1
    [[ "${candidatePath}" == *.dor.plist ]] || return 1
    [[ "${candidatePath}" == "${launchDaemonPath}" ]] && return 0

    candidateLabel="$(/usr/libexec/PlistBuddy -c "Print :Label" "${candidatePath}" 2>/dev/null || true)"
    programArguments="$(/usr/libexec/PlistBuddy -c "Print :ProgramArguments" "${candidatePath}" 2>/dev/null || true)"

    [[ "${candidateLabel}" == *.dor ]] || return 1
    [[ "${programArguments}" == *"/Library/Management/"* ]] || return 1
    if [[ "${programArguments}" == *"/dor-starter.zsh"* || "${programArguments}" == *"/dor.zsh"* ]]; then
        return 0
    fi

    return 1
}

function discoverDDMOSReminderLaunchDaemonPaths() {
    local candidatePath=""
    local -A discoveredPaths=()

    for candidatePath in "${launchDaemonPath}" /Library/LaunchDaemons/*.dor.plist(N); do
        [[ -n "${discoveredPaths[${candidatePath}]:-}" ]] && continue

        if [[ "${candidatePath}" == "${launchDaemonPath}" ]] || isDDMOSReminderLaunchDaemonPlist "${candidatePath}"; then
            discoveredPaths[${candidatePath}]="YES"
            echo "${candidatePath}"
        fi
    done
}

function launchDaemonLabelForPath() {
    local daemonPath="${1}"
    local daemonLabel=""

    if [[ -f "${daemonPath}" ]]; then
        daemonLabel="$(/usr/libexec/PlistBuddy -c "Print :Label" "${daemonPath}" 2>/dev/null || true)"
    fi

    if [[ -z "${daemonLabel}" && "${daemonPath}" == "${launchDaemonPath}" ]]; then
        daemonLabel="${launchDaemonLabel}"
    fi

    if [[ -z "${daemonLabel}" ]]; then
        daemonLabel="${daemonPath:t:r}"
    fi

    echo "${daemonLabel}"
}

function unloadAndRemoveLaunchDaemon() {
    local daemonPath="${1}"
    local daemonLabel=""

    [[ -n "${daemonPath}" ]] || return 0

    daemonLabel="$(launchDaemonLabelForPath "${daemonPath}")"
    if [[ -n "${daemonLabel}" ]]; then
        logComment "Unload LaunchDaemon label '${daemonLabel}' … "
        launchctl bootout "system/${daemonLabel}" >/dev/null 2>&1 || true
    fi

    if [[ -f "${daemonPath}" ]]; then
        logComment "Unload LaunchDaemon plist '${daemonPath}' … "
        launchctl bootout system "${daemonPath}" >/dev/null 2>&1 || true
        logComment "Removing '${daemonPath}' … "
        rm -f "${daemonPath}" 2>&1
        logComment "Removed '${daemonPath}'"
    else
        logComment "LaunchDaemon plist not present: '${daemonPath}'"
    fi
}

function resetLaunchDaemons() {
    local resetAction="${1:-Reset}"
    local daemonPath=""
    local -a daemonPaths=()

    info "${resetAction} LaunchDaemon … "
    launchDaemonStatus

    daemonPaths=("${(@f)$(discoverDDMOSReminderLaunchDaemonPaths)}")
    for daemonPath in "${daemonPaths[@]}"; do
        unloadAndRemoveLaunchDaemon "${daemonPath}"
    done

    launchDaemonStatus
}



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
            resetLaunchDaemons "Reset"

            # Reset Script
            info "Reset Script … "
            removeDeployedRuntimeAssets
            ;;

        "LaunchDaemon" )

            resetLaunchDaemons "Reset"
            ;;

        "Script" )

            info "Reset Script … "
            removeDeployedRuntimeAssets
            ;;

        "Uninstall" )

            warning "*** UNINSTALLING ${humanReadableScriptName} ***"

            # Uninstall LaunchDaemon
            resetLaunchDaemons "Uninstall"

            # Uninstall Script
            info "Uninstall Script … "
            removeDeployedRuntimeAssets

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

    notice "Create '${humanReadableScriptName}' script: ${dormScriptPath}"

(
cat <<'ENDOFSCRIPT'
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
#   AUTOMATED INSTRUCTIONS:
#   To automate the combination of your customized "reminderDialog.zsh" script with this script,
#   please run "zsh assemble.zsh" from the "DDM-OS-Reminder" repository's root directory.
#
#   This will generate the complete client-side script and place it in the "Artifacts/" directory,
#   which you will then deploy with your MDM solution.
#
#   See: https://snelson.us/ddm for detailed information.
#
#   MANUAL INSTRUCTIONS:
#   Replace this entire comment block with your organization’s customized "reminderDialog.zsh" script,
#   being careful to leave a full return at the end of the content before the "ENDOFSCRIPT" line below
#   (and then ask yourself: "Why am I not using the automated instructions above?").
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

ENDOFSCRIPT
) > "${dormScriptPath}"

    logComment "${humanReadableScriptName} script created"

    logComment "Setting permissions …"
    chown root:wheel "${dormScriptPath}"
    chmod 755 "${dormScriptPath}"
    chmod +x "${dormScriptPath}"

}

function createDorStarterScript() {

    local escapedScriptVersion="${scriptVersion//&/\\&}"
    local escapedScriptLog="${scriptLog//&/\\&}"
    local escapedMainScriptPath="${dormScriptPath//&/\\&}"
    local escapedStatePlistPath="${dorStatePlistPath//&/\\&}"
    local escapedPidFilePath="${dorPidFilePath//&/\\&}"

    notice "Create 'dor-starter' script: ${dorStarterPath}"

(
cat <<'ENDOFSTARTER'
#!/bin/zsh --no-rcs
# shellcheck shell=bash

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

scriptVersion="__SCRIPT_VERSION__"
scriptLog="__SCRIPT_LOG__"
mainScriptPath="__MAIN_SCRIPT_PATH__"
statePlistPath="__STATE_PLIST_PATH__"
pidFilePath="__PID_FILE_PATH__"

function updateScriptLog() {
    echo "dor (${scriptVersion}): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" >> "${scriptLog}"
}

function notice()  { updateScriptLog "[NOTICE]          ${1}"; }
function warning() { updateScriptLog "[WARNING]         ${1}"; }
function error()   { updateScriptLog "[ERROR]           ${1}"; }

function ensureStatePlist() {
    mkdir -p "${statePlistPath:h}"
    chown root:wheel "${statePlistPath:h}" 2>/dev/null || true
    chmod 755 "${statePlistPath:h}" 2>/dev/null || true

    if [[ ! -f "${statePlistPath}" ]]; then
        cat > "${statePlistPath}" <<'ENDOFPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
ENDOFPLIST
        chown root:wheel "${statePlistPath}" 2>/dev/null || true
        chmod 644 "${statePlistPath}" 2>/dev/null || true
    fi
}

function writeStateValue() {
    local key="${1}"
    local value="${2}"

    ensureStatePlist

    if /usr/libexec/PlistBuddy -c "Print :${key}" "${statePlistPath}" >/dev/null 2>&1; then
        /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${statePlistPath}" >/dev/null 2>&1
    else
        /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "${statePlistPath}" >/dev/null 2>&1
    fi
}

function readStateValue() {
    local key="${1}"

    [[ -f "${statePlistPath}" ]] || return 0

    /usr/libexec/PlistBuddy -c "Print :${key}" "${statePlistPath}" 2>/dev/null || true
}

function epochFromScheduleTimestamp() {
    local scheduleTimestamp="${1}"
    local scheduleEpoch=""

    scheduleEpoch=$(date -j -f "%Y-%m-%d:%H:%M:%S" "${scheduleTimestamp}" "+%s" 2>/dev/null)
    echo "${scheduleEpoch}"
}

if [[ ! -x "${mainScriptPath}" ]]; then
    error "Missing deployed main script: ${mainScriptPath}"
    exit 1
fi

if [[ -f "${pidFilePath}" ]]; then
    if pgrep -F "${pidFilePath}" >/dev/null 2>&1; then
        exit 0
    fi

    warning "Removing stale PID file '${pidFilePath}'."
    rm -f "${pidFilePath}" 2>/dev/null || true
fi

nextScheduledReminder="$(readStateValue "NextScheduledReminder")"
if [[ "${nextScheduledReminder:l}" == "false" ]]; then
    exit 0
fi

if [[ -n "${nextScheduledReminder}" ]]; then
    nextScheduledReminderEpoch="$(epochFromScheduleTimestamp "${nextScheduledReminder}")"
    if [[ -n "${nextScheduledReminderEpoch}" ]]; then
        nowEpoch="$(date +%s)"
        if (( nextScheduledReminderEpoch > nowEpoch )); then
            exit 0
        fi
    else
        warning "Invalid NextScheduledReminder '${nextScheduledReminder}'; launching main script now."
    fi
fi

writeStateValue "DaemonLastTriggered" "$(date '+%Y-%m-%d:%H:%M:%S')"
notice "Heartbeat launch triggered '${mainScriptPath}'."
DOR_LAUNCH_SOURCE="starter" "${mainScriptPath}" &
disown

exit 0
ENDOFSTARTER
) | sed \
    -e "s|__SCRIPT_VERSION__|${escapedScriptVersion}|g" \
    -e "s|__SCRIPT_LOG__|${escapedScriptLog}|g" \
    -e "s|__MAIN_SCRIPT_PATH__|${escapedMainScriptPath}|g" \
    -e "s|__STATE_PLIST_PATH__|${escapedStatePlistPath}|g" \
    -e "s|__PID_FILE_PATH__|${escapedPidFilePath}|g" \
    > "${dorStarterPath}"

    logComment "dor-starter script created"

    logComment "Setting permissions …"
    chown root:wheel "${dorStarterPath}"
    chmod 755 "${dorStarterPath}"
    chmod +x "${dorStarterPath}"

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
#
# CREATE LAUNCHDAEMON
#
#   The following function creates the LaunchDaemon which executes the lightweight heartbeat
#   starter script. The starter checks runtime scheduling state and only launches the main
#   reminder script when a reminder is due.
#
#   NOTE: Leave a full return at the end of the content before the "ENDOFLAUNCHDAEMON" line.
#
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function createLaunchDaemon() {

    notice "Create LaunchDaemon"

    logComment "Ensuring previous '${launchDaemonLabel}' definition is unloaded …"
    launchctl bootout system "${launchDaemonPath}" >/dev/null 2>&1 || true

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
        <string>${dorStarterPath}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>AbandonProcessGroup</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin</string>
    </dict>
    <key>StartInterval</key>
    <integer>60</integer>
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
    launchctl kickstart -k "system/${launchDaemonLabel}"

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
        fatal "Unable to create specified scriptLog '${scriptLog}'; exiting.\n\n(Is this script running as 'root' ?)"
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
        osascript -e 'display dialog "Please advise your Support Representative of the following error:\r\r• Dialog Team ID verification failed\r\r" with title "DDM OS Reminder Error" buttons {"Close"} with icon caution'
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

notice "Refreshing Script"

if [[ -f "${dormScriptPath}" ]]; then
    logComment "Replacing existing ${humanReadableScriptName} script '${dormScriptPath}'"
fi

createDDMOSReminderScript

notice "Refreshing Starter"

if [[ -f "${dorStarterPath}" ]]; then
    logComment "Replacing existing dor-starter script '${dorStarterPath}'"
fi

createDorStarterScript



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LaunchDaemon Validation / Creation
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

notice "Refreshing LaunchDaemon"

if [[ -f "${launchDaemonPath}" ]]; then
    logComment "Replacing existing LaunchDaemon '${launchDaemonPath}'"
fi

createLaunchDaemon



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
