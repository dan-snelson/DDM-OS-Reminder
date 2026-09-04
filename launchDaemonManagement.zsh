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
scriptVersion="4.2.0b1"

# Client-side Log
scriptLog="/var/log/org.churchofjesuschrist.log"

# Minimum Required Version of swiftDialog
swiftDialogMinimumRequiredVersion="3.1.0.4994"

# Load is-at-least for version comparison
autoload -Uz is-at-least



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# MDM Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Parameter 4: Configuration Files to Reset (i.e., None (blank) | All | LaunchDaemon | Script | Uninstall )
resetConfiguration="${4:-"All"}"

# Parameter 5: Fallback Required macOS Version (i.e., 26.6)
fallbackVersionString="${5:-}"

# Parameter 6: Fallback Enforcement Deadline (i.e., 2026-08-04T22:00:00Z)
fallbackEnforcedInstallDate="${6:-}"



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
dorAggressiveKillSwitchPath="${organizationDirectory}/dor-aggressive-kill"
dorFallbackDeclarationPlistPath="${organizationDirectory}/dor-fallback-declaration.plist"

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
        "${dorAggressiveKillSwitchPath}"
        "${dorFallbackDeclarationPlistPath}"
    )

    stopActiveReminderRuntime

    for runtimeAssetPath in "${runtimeAssetPaths[@]}"; do
        if [[ ! -e "${runtimeAssetPath}" && ! -L "${runtimeAssetPath}" ]]; then
            logComment "Runtime asset not present: '${runtimeAssetPath}'"
            continue
        fi

        logComment "Removing '${runtimeAssetPath}' … "
        if rm -f "${runtimeAssetPath}" 2>/dev/null; then
            logComment "Removed '${runtimeAssetPath}'"
        else
            warning "Failed to remove '${runtimeAssetPath}'"
        fi
    done
}

function collectDescendantPids() {
    local parentPid="${1}"
    local childPid=""
    local -a childPids=()

    childPids=( "${(@f)$(pgrep -P "${parentPid}" 2>/dev/null || true)}" )
    for childPid in "${childPids[@]}"; do
        [[ "${childPid}" =~ ^[0-9]+$ ]] || continue
        collectDescendantPids "${childPid}"
        echo "${childPid}"
    done
}

function stopActiveReminderRuntime() {
    local runtimePid=""
    local runtimeCommand=""
    local currentCommand=""
    local processPid=""
    local processStillRunning="NO"
    local attempt=0
    local -a descendantPids=()
    local -a runtimeProcessPids=()
    local -A runtimeProcessCommands=()

    [[ -f "${dorPidFilePath}" ]] || return 0

    runtimePid="$(head -n 1 "${dorPidFilePath}" 2>/dev/null || true)"
    if [[ ! "${runtimePid}" =~ ^[0-9]+$ ]] || (( runtimePid <= 1 )); then
        warning "Invalid active-runtime PID in '${dorPidFilePath}'; refusing to terminate any process."
        return 0
    fi

    if ! kill -0 "${runtimePid}" >/dev/null 2>&1; then
        logComment "Runtime PID ${runtimePid} is no longer active; stale PID file will be removed."
        return 0
    fi

    runtimeCommand="$(ps -p "${runtimePid}" -o command= 2>/dev/null || true)"
    if [[ "${runtimePid}" == "$$" || "${runtimeCommand}" != *"${dormScriptPath}"* ]]; then
        warning "PID ${runtimePid} does not match deployed DDM OS Reminder runtime '${dormScriptPath}'; refusing to terminate it."
        return 0
    fi

    descendantPids=( "${(@f)$(collectDescendantPids "${runtimePid}")}" )
    runtimeProcessPids=( "${descendantPids[@]}" "${runtimePid}" )
    notice "Stopping active DDM OS Reminder runtime PID ${runtimePid} before replacing runtime assets."

    for processPid in "${runtimeProcessPids[@]}"; do
        [[ "${processPid}" =~ ^[0-9]+$ ]] || continue
        runtimeProcessCommands["${processPid}"]="$(ps -p "${processPid}" -o command= 2>/dev/null || true)"
        kill -TERM "${processPid}" >/dev/null 2>&1 || true
    done

    for (( attempt = 0; attempt < 20; attempt++ )); do
        processStillRunning="NO"
        for processPid in "${runtimeProcessPids[@]}"; do
            [[ "${processPid}" =~ ^[0-9]+$ ]] || continue
            if kill -0 "${processPid}" >/dev/null 2>&1; then
                processStillRunning="YES"
                break
            fi
        done
        [[ "${processStillRunning}" == "NO" ]] && break
        sleep 0.25
    done

    if [[ "${processStillRunning}" == "YES" ]]; then
        for processPid in "${runtimeProcessPids[@]}"; do
            [[ "${processPid}" =~ ^[0-9]+$ ]] || continue
            kill -0 "${processPid}" >/dev/null 2>&1 || continue
            currentCommand="$(ps -p "${processPid}" -o command= 2>/dev/null || true)"
            if [[ -n "${currentCommand}" && "${currentCommand}" == "${runtimeProcessCommands["${processPid}"]:-}" ]]; then
                warning "Owned DDM OS Reminder process PID ${processPid} did not exit after TERM; forcing termination."
                kill -KILL "${processPid}" >/dev/null 2>&1 || true
            else
                warning "Process PID ${processPid} changed after the termination request; refusing forced termination."
            fi
        done
        sleep 0.25
    fi

    notice "Completed active DDM OS Reminder runtime shutdown request for PID ${runtimePid}."
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# MDM Fallback Requirement
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function isValidFallbackVersionString() {
    local value="${1}"
    local versionRegex='^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$'

    [[ -n "${value}" && "${value}" =~ ${versionRegex} ]]
}

function isValidCivilDate() {
    local year="${1}"
    local month="${2}"
    local day="${3}"
    local daysInMonth=31

    (( month >= 1 && month <= 12 && day >= 1 )) || return 1

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

function isValidFallbackEnforcementDate() {
    local value="${1}"
    local timestampRegex='^(([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2}))(Z|[+-]([0-9]{2}):([0-9]{2}))$'
    local year=0
    local month=0
    local day=0
    local hour=0
    local minute=0
    local second=0
    local timezoneSuffix=""
    local offsetHours=0
    local offsetMinutes=0

    [[ "${value}" =~ ${timestampRegex} ]] || return 1

    year=$(( 10#${match[2]} ))
    month=$(( 10#${match[3]} ))
    day=$(( 10#${match[4]} ))
    hour=$(( 10#${match[5]} ))
    minute=$(( 10#${match[6]} ))
    second=$(( 10#${match[7]} ))
    timezoneSuffix="${match[8]}"
    offsetHours=$(( 10#${match[9]:-0} ))
    offsetMinutes=$(( 10#${match[10]:-0} ))

    isValidCivilDate "${year}" "${month}" "${day}" || return 1
    (( hour <= 23 && minute <= 59 && second <= 59 )) || return 1

    if [[ "${timezoneSuffix}" != "Z" ]]; then
        (( offsetHours <= 23 && offsetMinutes <= 59 )) || return 1
    fi

    return 0
}

function removeFallbackDeclarationPlist() {
    local removalReason="${1}"

    if [[ ! -e "${dorFallbackDeclarationPlistPath}" && ! -L "${dorFallbackDeclarationPlistPath}" ]]; then
        logComment "MDM fallback requirement plist not present: '${dorFallbackDeclarationPlistPath}'"
        return 0
    fi

    if rm -f "${dorFallbackDeclarationPlistPath}" 2>/dev/null; then
        notice "Removed MDM fallback requirement plist (${removalReason}): '${dorFallbackDeclarationPlistPath}'"
        return 0
    fi

    warning "Failed to remove MDM fallback requirement plist '${dorFallbackDeclarationPlistPath}'"
    return 1
}

function writeFallbackDeclarationPlist() {
    local temporaryPath=""
    local plistValidationOutput=""
    local plistPermissions=""
    local writeAction="Created"

    [[ -e "${dorFallbackDeclarationPlistPath}" || -L "${dorFallbackDeclarationPlistPath}" ]] && writeAction="Replaced"

    temporaryPath="$(/usr/bin/mktemp "${dorFallbackDeclarationPlistPath}.tmp.XXXXXX" 2>/dev/null)"
    if [[ -z "${temporaryPath}" || ! -f "${temporaryPath}" ]]; then
        fatal "Unable to create temporary MDM fallback requirement plist beside '${dorFallbackDeclarationPlistPath}'."
    fi

    if ! /usr/bin/plutil -create xml1 "${temporaryPath}" \
        || ! /usr/bin/plutil -insert SchemaVersion -integer 1 "${temporaryPath}" \
        || ! /usr/bin/plutil -insert VersionString -string "${fallbackVersionString}" "${temporaryPath}" \
        || ! /usr/bin/plutil -insert BuildVersionString -string "(null)" "${temporaryPath}" \
        || ! /usr/bin/plutil -insert EnforcedInstallDate -string "${fallbackEnforcedInstallDate}" "${temporaryPath}" \
        || ! /usr/bin/plutil -insert Source -string "JamfProScriptParameters" "${temporaryPath}"; then
        rm -f "${temporaryPath}" 2>/dev/null || true
        fatal "Unable to write temporary MDM fallback requirement plist."
    fi

    if ! plistValidationOutput="$(/usr/bin/plutil -lint "${temporaryPath}" 2>&1)"; then
        rm -f "${temporaryPath}" 2>/dev/null || true
        fatal "MDM fallback requirement plist validation failed: ${plistValidationOutput:-no plutil output}"
    fi

    if ! chown root:wheel "${temporaryPath}" || ! chmod 644 "${temporaryPath}"; then
        rm -f "${temporaryPath}" 2>/dev/null || true
        fatal "Unable to secure temporary MDM fallback requirement plist."
    fi

    plistPermissions="$(/usr/bin/stat -f '%Su:%Sg %Lp' "${temporaryPath}" 2>/dev/null)"
    if [[ "${plistPermissions}" != "root:wheel 644" ]]; then
        rm -f "${temporaryPath}" 2>/dev/null || true
        fatal "Unexpected MDM fallback requirement plist ownership or mode '${plistPermissions:-unknown}'; expected 'root:wheel 644'."
    fi

    if ! mv -f "${temporaryPath}" "${dorFallbackDeclarationPlistPath}"; then
        rm -f "${temporaryPath}" 2>/dev/null || true
        fatal "Unable to atomically replace MDM fallback requirement plist '${dorFallbackDeclarationPlistPath}'."
    fi

    notice "${writeAction} MDM fallback requirement plist: '${dorFallbackDeclarationPlistPath}'"
    info "MDM fallback requirement configuration: VersionString=${fallbackVersionString}; EnforcedInstallDate=${fallbackEnforcedInstallDate}; Source=JamfProScriptParameters"
}

function applyFallbackDeclarationParameters() {
    if [[ -z "${fallbackVersionString}" && -z "${fallbackEnforcedInstallDate}" ]]; then
        removeFallbackDeclarationPlist "intentionally disabled by blank Parameters 5 and 6"
        return
    fi

    if [[ -z "${fallbackVersionString}" || -z "${fallbackEnforcedInstallDate}" ]]; then
        warning "Rejected partial MDM fallback requirement; Parameters 5 and 6 must both be populated."
        removeFallbackDeclarationPlist "partial parameter pair rejected"
        return
    fi

    if ! isValidFallbackVersionString "${fallbackVersionString}"; then
        warning "Rejected malformed MDM fallback requirement version from Parameter 5: '${fallbackVersionString}'"
        removeFallbackDeclarationPlist "malformed version rejected"
        return
    fi

    if ! isValidFallbackEnforcementDate "${fallbackEnforcedInstallDate}"; then
        warning "Rejected malformed MDM fallback requirement deadline from Parameter 6: '${fallbackEnforcedInstallDate}'"
        removeFallbackDeclarationPlist "malformed or timezone-free deadline rejected"
        return
    fi

    writeFallbackDeclarationPlist
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

    setopt local_options null_glob

    for candidatePath in "${launchDaemonPath}" /Library/LaunchDaemons/*.dor.plist; do
        [[ -n "${discoveredPaths["${candidatePath}"]:-}" ]] && continue

        if [[ "${candidatePath}" == "${launchDaemonPath}" ]] || isDDMOSReminderLaunchDaemonPlist "${candidatePath}"; then
            discoveredPaths["${candidatePath}"]="YES"
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
        if rm -f "${daemonPath}" 2>/dev/null; then
            logComment "Removed '${daemonPath}'"
        else
            warning "Failed to remove '${daemonPath}'"
        fi
    else
        logComment "LaunchDaemon plist not present: '${daemonPath}'"
    fi
}

function resetLaunchDaemons() {
    local resetAction="${1:-Reset}"
    local daemonPath=""
    local -a daemonPaths=()

    info "${resetAction} LaunchDaemon … "
    launchDaemonStatus || true

    daemonPaths=("${(@f)$(discoverDDMOSReminderLaunchDaemonPaths)}")
    for daemonPath in "${daemonPaths[@]}"; do
        unloadAndRemoveLaunchDaemon "${daemonPath}"
    done

    launchDaemonStatus || true
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

function escapeSedReplacement() {
    local replacementValue="${1}"

    replacementValue="${replacementValue//\\/\\\\}"
    replacementValue="${replacementValue//&/\\&}"
    replacementValue="${replacementValue//|/\\|}"

    print -r -- "${replacementValue}"
}

function createDorStarterScript() {

    local escapedScriptVersion="$(escapeSedReplacement "${scriptVersion}")"
    local escapedScriptLog="$(escapeSedReplacement "${scriptLog}")"
    local escapedMainScriptPath="$(escapeSedReplacement "${dormScriptPath}")"
    local escapedStatePlistPath="$(escapeSedReplacement "${dorStatePlistPath}")"
    local escapedPidFilePath="$(escapeSedReplacement "${dorPidFilePath}")"

    notice "Create 'dor-starter' script: ${dorStarterPath}"

(
cat <<'ENDOFSTARTER'
#!/bin/zsh --no-rcs

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

scriptVersion="__SCRIPT_VERSION__"
scriptLog="__SCRIPT_LOG__"
mainScriptPath="__MAIN_SCRIPT_PATH__"
statePlistPath="__STATE_PLIST_PATH__"
pidFilePath="__PID_FILE_PATH__"
plistBuddyPath="/usr/libexec/PlistBuddy"

function updateScriptLog() {
    echo "dor (${scriptVersion}): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" >> "${scriptLog}"
}

function notice()  { updateScriptLog "[NOTICE]          ${1}"; }
function warning() { updateScriptLog "[WARNING]         ${1}"; }
function error()   { updateScriptLog "[ERROR]           ${1}"; }

function requirePlistBuddy() {
    if [[ ! -x "${plistBuddyPath}" ]]; then
        error "Missing required PlistBuddy binary: ${plistBuddyPath}; scheduler state cannot be trusted."
        exit 1
    fi
}

function createEmptyStatePlist() {
    local createStatus=""

    cat > "${statePlistPath}" <<'ENDOFPLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
ENDOFPLIST
    createStatus="${?}"

    if (( createStatus != 0 )); then
        error "Unable to create scheduler state plist '${statePlistPath}'."
        return 1
    fi

    chown root:wheel "${statePlistPath}" 2>/dev/null || true
    chmod 644 "${statePlistPath}" 2>/dev/null || true

    if ! "${plistBuddyPath}" -c "Print" "${statePlistPath}" >/dev/null 2>&1; then
        error "Created scheduler state plist '${statePlistPath}' is not readable."
        return 1
    fi
}

function ensureStatePlist() {
    local invalidStatePlistPath=""

    mkdir -p "${statePlistPath:h}"
    chown root:wheel "${statePlistPath:h}" 2>/dev/null || true
    chmod 755 "${statePlistPath:h}" 2>/dev/null || true

    if [[ ! -f "${statePlistPath}" ]]; then
        createEmptyStatePlist || return 1
    elif ! "${plistBuddyPath}" -c "Print" "${statePlistPath}" >/dev/null 2>&1; then
        invalidStatePlistPath="${statePlistPath}.invalid.$(date '+%Y%m%d%H%M%S')"
        warning "Unreadable scheduler state plist '${statePlistPath}'; recreating empty state."
        if mv "${statePlistPath}" "${invalidStatePlistPath}" 2>/dev/null; then
            warning "Moved unreadable scheduler state plist to '${invalidStatePlistPath}'."
        else
            warning "Unable to quarantine unreadable scheduler state plist '${statePlistPath}'; replacing in place."
        fi
        createEmptyStatePlist || return 1
    fi

    chown root:wheel "${statePlistPath}" 2>/dev/null || true
    chmod 644 "${statePlistPath}" 2>/dev/null || true

    "${plistBuddyPath}" -c "Print" "${statePlistPath}" >/dev/null 2>&1
}

function writeStateValue() {
    local key="${1}"
    local value="${2}"

    ensureStatePlist || return 1

    if "${plistBuddyPath}" -c "Print :${key}" "${statePlistPath}" >/dev/null 2>&1; then
        if ! "${plistBuddyPath}" -c "Set :${key} ${value}" "${statePlistPath}" >/dev/null 2>&1; then
            error "Unable to set scheduler state key '${key}' in '${statePlistPath}'."
            return 1
        fi
    else
        if ! "${plistBuddyPath}" -c "Add :${key} string ${value}" "${statePlistPath}" >/dev/null 2>&1; then
            error "Unable to add scheduler state key '${key}' in '${statePlistPath}'."
            return 1
        fi
    fi
}

function readStateValue() {
    local key="${1}"

    ensureStatePlist || return 1

    "${plistBuddyPath}" -c "Print :${key}" "${statePlistPath}" 2>/dev/null || true
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

requirePlistBuddy

if [[ -f "${pidFilePath}" ]]; then
    if pgrep -F "${pidFilePath}" >/dev/null 2>&1; then
        exit 0
    fi

    warning "Removing stale PID file '${pidFilePath}'."
    rm -f "${pidFilePath}" 2>/dev/null || true
fi

nextScheduledReminder="$(readStateValue "NextScheduledReminder")"
stateReadStatus="${?}"
if (( stateReadStatus != 0 )); then
    error "Unable to read scheduler state; not launching main script."
    exit 1
fi

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

if ! writeStateValue "DaemonLastTriggered" "$(date '+%Y-%m-%d:%H:%M:%S')"; then
    error "Unable to update scheduler trigger state; not launching main script."
    exit 1
fi

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

    local bootstrapOutput=""
    local kickstartOutput=""
    local launchDaemonPermissions=""
    local launchDaemonTemporaryPath=""
    local plistValidationOutput=""
    local quarantineRemovalOutput=""

    notice "Create LaunchDaemon"

    logComment "Ensuring previous '${launchDaemonLabel}' definition is unloaded …"
    launchctl bootout system "${launchDaemonPath}" >/dev/null 2>&1 || true

    launchDaemonTemporaryPath="$(/usr/bin/mktemp "${launchDaemonPath}.tmp.XXXXXX" 2>/dev/null)"
    if [[ -z "${launchDaemonTemporaryPath}" || ! -f "${launchDaemonTemporaryPath}" ]]; then
        fatal "Unable to create temporary LaunchDaemon plist beside '${launchDaemonPath}'."
    fi

    logComment "Creating temporary LaunchDaemon plist '${launchDaemonTemporaryPath}' …"

    if ! cat > "${launchDaemonTemporaryPath}" <<ENDOFLAUNCHDAEMON
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
    then
        rm -f "${launchDaemonTemporaryPath}" 2>/dev/null || true
        fatal "Unable to write temporary LaunchDaemon plist '${launchDaemonTemporaryPath}'."
    fi

    if ! plistValidationOutput="$(/usr/bin/plutil -lint "${launchDaemonTemporaryPath}" 2>&1)"; then
        plistValidationOutput="${plistValidationOutput//$'\n'/; }"
        rm -f "${launchDaemonTemporaryPath}" 2>/dev/null || true
        fatal "LaunchDaemon plist validation failed: ${plistValidationOutput:-no plutil output}"
    fi
    logComment "${plistValidationOutput}"

    logComment "Setting permissions for temporary LaunchDaemon plist …"
    if ! chown root:wheel "${launchDaemonTemporaryPath}"; then
        rm -f "${launchDaemonTemporaryPath}" 2>/dev/null || true
        fatal "Unable to set root:wheel ownership on '${launchDaemonTemporaryPath}'."
    fi
    if ! chmod 644 "${launchDaemonTemporaryPath}"; then
        rm -f "${launchDaemonTemporaryPath}" 2>/dev/null || true
        fatal "Unable to set mode 0644 on '${launchDaemonTemporaryPath}'."
    fi

    launchDaemonPermissions="$(/usr/bin/stat -f '%Su:%Sg %Lp' "${launchDaemonTemporaryPath}" 2>/dev/null)"
    if [[ "${launchDaemonPermissions}" != "root:wheel 644" ]]; then
        rm -f "${launchDaemonTemporaryPath}" 2>/dev/null || true
        fatal "Unexpected LaunchDaemon ownership or mode '${launchDaemonPermissions:-unknown}'; expected 'root:wheel 644'."
    fi

    logComment "Atomically replacing '${launchDaemonPath}' …"
    if ! mv -f "${launchDaemonTemporaryPath}" "${launchDaemonPath}"; then
        rm -f "${launchDaemonTemporaryPath}" 2>/dev/null || true
        fatal "Unable to atomically replace LaunchDaemon plist '${launchDaemonPath}'."
    fi
    launchDaemonTemporaryPath=""

    if /usr/bin/xattr -p com.apple.quarantine "${launchDaemonPath}" >/dev/null 2>&1; then
        notice "Removing com.apple.quarantine from validated installer-generated LaunchDaemon plist"
        if ! quarantineRemovalOutput="$(/usr/bin/xattr -d com.apple.quarantine "${launchDaemonPath}" 2>&1)"; then
            quarantineRemovalOutput="${quarantineRemovalOutput//$'\n'/; }"
            fatal "Unable to remove com.apple.quarantine from '${launchDaemonPath}': ${quarantineRemovalOutput:-no xattr output}"
        fi
        if /usr/bin/xattr -p com.apple.quarantine "${launchDaemonPath}" >/dev/null 2>&1; then
            fatal "LaunchDaemon plist '${launchDaemonPath}' still carries com.apple.quarantine after targeted removal."
        fi
    else
        logComment "LaunchDaemon plist does not carry com.apple.quarantine"
    fi

    logComment "Loading '${launchDaemonLabel}' …"
    if ! bootstrapOutput="$(launchctl bootstrap system "${launchDaemonPath}" 2>&1)"; then
        bootstrapOutput="${bootstrapOutput//$'\n'/; }"
        fatal "launchctl bootstrap failed for '${launchDaemonLabel}': ${bootstrapOutput:-no launchctl output}"
    fi
    if [[ -n "${bootstrapOutput}" ]]; then
        bootstrapOutput="${bootstrapOutput//$'\n'/; }"
        logComment "launchctl bootstrap: ${bootstrapOutput}"
    fi

    if ! kickstartOutput="$(launchctl kickstart -k "system/${launchDaemonLabel}" 2>&1)"; then
        kickstartOutput="${kickstartOutput//$'\n'/; }"
        if launchctl print "system/${launchDaemonLabel}" >/dev/null 2>&1; then
            warning "launchctl kickstart failed, but '${launchDaemonLabel}' remains loaded: ${kickstartOutput:-no launchctl output}"
        else
            fatal "launchctl kickstart failed and '${launchDaemonLabel}' is not loaded: ${kickstartOutput:-no launchctl output}"
        fi
    fi

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LaunchDaemon Status
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function launchDaemonStatus() {

    local launchDaemonStatusOutput=""

    notice "LaunchDaemon Status"

    if launchDaemonStatusOutput="$(launchctl print "system/${launchDaemonLabel}" 2>&1)"; then
        logComment "${launchDaemonLabel} is loaded"
        return 0
    fi

    launchDaemonStatusOutput="${launchDaemonStatusOutput//$'\n'/; }"
    logComment "${launchDaemonLabel} is NOT loaded: ${launchDaemonStatusOutput:-no launchctl output}"
    return 1

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
# MDM Fallback Requirement Validation / Persistence
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

applyFallbackDeclarationParameters



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

if ! launchDaemonStatus; then
    fatal "LaunchDaemon verification failed for '${launchDaemonLabel}'; deployment did not complete."
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

quitOut "Completed ${reverseDomainNameNotation}.${organizationScriptName} LaunchDaemon"
quitOut "Monitor the client-side log via:"
quitOut "tail -f ${scriptLog}"

exit 0
