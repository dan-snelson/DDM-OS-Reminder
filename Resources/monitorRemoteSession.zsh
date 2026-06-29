#!/bin/zsh --no-rcs

####################################################################################################
#
# Declarative Device Management macOS Reminder: Remote Session Monitor
#
# Purpose:
# - Provide a single remote-Terminal view of the DDM OS Reminder heartbeat daemon,
#   runtime scheduler state, active pid file, matching processes, and recent logs.
#
# Usage:
#   zsh Resources/monitorRemoteSession.zsh
#   zsh Resources/monitorRemoteSession.zsh --rdnn org.churchofjesuschrist
#   zsh Resources/monitorRemoteSession.zsh --rdnn org.churchofjesuschrist --watch 5
#
# Notes:
# - The main reminder process can be short-lived. The best source of truth is the
#   heartbeat LaunchDaemon plus dor-state.plist and the project log.
#
# http://snelson.us/ddm
#
####################################################################################################

set -u



####################################################################################################
#
# Argument Parsing
#
####################################################################################################

cliReverseDomainNameNotation=""
logTailLines="80"
watchIntervalSeconds=""
scriptRelativePath="Resources/monitorRemoteSession.zsh"
defaultUsage="zsh ${scriptRelativePath}"
rdnnUsage="zsh ${scriptRelativePath} --rdnn <your.reverse.domain.name.notation>"

function printUsage() {
    echo "Usage:"
    echo "  ${defaultUsage}"
    echo "  ${rdnnUsage}"
    echo "  ${rdnnUsage} --watch 5"
    echo ""
    echo "Options:"
    echo "  --rdnn <value>      Reverse domain name notation for deployed runtime assets"
    echo "  --watch <seconds>   Refresh continuously at the specified interval"
    echo "  --log-lines <n>     Tail the most recent log lines (default: 80)"
    echo "  --help, -h          Show this help"
}

while [[ "$#" -gt 0 ]]; do
    case "${1}" in
        --help|-h)
            printUsage
            exit 0
            ;;
        --rdnn)
            if [[ -z "${2:-}" ]]; then
                printUsage
                exit 64
            fi
            cliReverseDomainNameNotation="${2}"
            shift 2
            ;;
        --watch)
            if [[ -z "${2:-}" || ! "${2}" =~ ^[0-9]+$ || "${2}" -lt 1 || "${2}" -gt 999 ]]; then
                printUsage
                exit 64
            fi
            watchIntervalSeconds="${2}"
            shift 2
            ;;
        --log-lines)
            if [[ -z "${2:-}" || ! "${2}" =~ ^[0-9]+$ || "${2}" -lt 1 || "${2}" -gt 9999 ]]; then
                printUsage
                exit 64
            fi
            logTailLines="${2}"
            shift 2
            ;;
        *)
            printUsage
            exit 64
            ;;
    esac
done



####################################################################################################
#
# Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local

scriptVersion="1.0.0"
reverseDomainNameNotation="${cliReverseDomainNameNotation:-org.churchofjesuschrist}"
organizationScriptName="dor"
organizationDirectory="/Library/Management/${reverseDomainNameNotation}"
launchDaemonLabel="${reverseDomainNameNotation}.${organizationScriptName}"
launchDaemonPath="/Library/LaunchDaemons/${launchDaemonLabel}.plist"
dorScriptPath="${organizationDirectory}/${organizationScriptName}.zsh"
dorStarterPath="${organizationDirectory}/dor-starter.zsh"
dorStatePlistPath="${organizationDirectory}/dor-state.plist"
dorPidFilePath="${organizationDirectory}/dor.pid"
aggressiveModeKillSwitchPath="${organizationDirectory}/dor-aggressive-kill"
scriptLog="/var/log/${reverseDomainNameNotation}.log"



####################################################################################################
#
# Helpers
#
####################################################################################################

function printSection() {
    local title="${1}"
    echo ""
    echo "== ${title} =="
}

function printKeyValue() {
    local key="${1}"
    local value="${2}"
    printf "%-24s %s\n" "${key}:" "${value}"
}

function readStateValue() {
    local key="${1}"

    [[ -f "${dorStatePlistPath}" ]] || return 1
    /usr/libexec/PlistBuddy -c "Print :${key}" "${dorStatePlistPath}" 2>/dev/null
}

function renderLaunchDaemonStatus() {
    local launchctlOutput=""

    printSection "launchd"
    printKeyValue "Label" "${launchDaemonLabel}"
    printKeyValue "Plist" "${launchDaemonPath}"

    if [[ ! -f "${launchDaemonPath}" ]]; then
        printKeyValue "Status" "LaunchDaemon plist not found"
        return
    fi

    launchctlOutput="$(launchctl print "system/${launchDaemonLabel}" 2>&1)"
    if [[ $? -eq 0 ]]; then
        echo "${launchctlOutput}" | sed -n '1,25p'
    else
        printKeyValue "Status" "launchctl print failed"
        echo "${launchctlOutput}" | sed -n '1,10p'
    fi
}

function renderRuntimePaths() {
    printSection "runtime files"
    printKeyValue "Directory" "${organizationDirectory}"
    printKeyValue "Main script" "$( [[ -f "${dorScriptPath}" ]] && echo "present" || echo "missing" )"
    printKeyValue "Starter" "$( [[ -f "${dorStarterPath}" ]] && echo "present" || echo "missing" )"
    printKeyValue "State plist" "$( [[ -f "${dorStatePlistPath}" ]] && echo "present" || echo "missing" )"
    printKeyValue "PID file" "$( [[ -f "${dorPidFilePath}" ]] && echo "present" || echo "missing" )"
    printKeyValue "Aggressive kill" "$( [[ -e "${aggressiveModeKillSwitchPath}" ]] && echo "present" || echo "absent" )"

    if [[ -d "${organizationDirectory}" ]]; then
        ls -l "${organizationDirectory}"
    fi
}

function renderSchedulerState() {
    local nextScheduledReminder=""
    local daemonLastTriggered=""

    printSection "scheduler state"
    if [[ ! -f "${dorStatePlistPath}" ]]; then
        printKeyValue "State" "dor-state.plist not found"
        return
    fi

    nextScheduledReminder="$(readStateValue "NextScheduledReminder" 2>/dev/null || true)"
    daemonLastTriggered="$(readStateValue "DaemonLastTriggered" 2>/dev/null || true)"

    printKeyValue "NextScheduledReminder" "${nextScheduledReminder:-Unavailable}"
    printKeyValue "DaemonLastTriggered" "${daemonLastTriggered:-Unavailable}"
    echo ""
    /usr/libexec/PlistBuddy -c "Print" "${dorStatePlistPath}" 2>/dev/null || echo "Unable to read ${dorStatePlistPath}"
}

function renderPidStatus() {
    local pidValue=""
    local pidCommand=""

    printSection "pid file"
    if [[ ! -f "${dorPidFilePath}" ]]; then
        printKeyValue "Status" "dor.pid not found"
        return
    fi

    pidValue="$(<"${dorPidFilePath}")"
    printKeyValue "PID" "${pidValue:-Unavailable}"

    if [[ -n "${pidValue}" && "${pidValue}" =~ ^[0-9]+$ ]] && kill -0 "${pidValue}" 2>/dev/null; then
        pidCommand="$(ps -p "${pidValue}" -o command= 2>/dev/null)"
        printKeyValue "Alive" "YES"
        [[ -n "${pidCommand}" ]] && printKeyValue "Command" "${pidCommand}"
    else
        printKeyValue "Alive" "NO"
    fi
}

function renderMatchingProcesses() {
    local processSnapshot=""

    printSection "matching processes"
    processSnapshot="$(ps -ax -o pid,ppid,etime,stat,command 2>/dev/null)" || true

    if [[ -z "${processSnapshot}" ]]; then
        printKeyValue "Status" "unable to read process table in current session"
        return
    fi

    print -r -- "${processSnapshot}" | awk -v rdnn="${reverseDomainNameNotation}" '
        NR == 1 {
            print
            next
        }

        index($0, rdnn) || index($0, "dor-starter.zsh") || index($0, "/Library/Management/") || index($0, "/usr/local/bin/dialog") || index($0, "swiftDialog") {
            print
            found = 1
        }

        END {
            if (found != 1) {
                print "(no matching processes found)"
            }
        }
    '
}

function renderLogTail() {
    printSection "log tail"
    printKeyValue "Log" "${scriptLog}"

    if [[ ! -f "${scriptLog}" ]]; then
        printKeyValue "Status" "log file not found"
        return
    fi

    tail -n "${logTailLines}" "${scriptLog}"
}

function renderSnapshot() {
    clear 2>/dev/null || true
    echo "DDM OS Reminder Remote Session Monitor (${scriptVersion})"
    echo "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printKeyValue "RDNN" "${reverseDomainNameNotation}"
    printKeyValue "Watch interval" "${watchIntervalSeconds:-none}"

    renderLaunchDaemonStatus
    renderRuntimePaths
    renderSchedulerState
    renderPidStatus
    renderMatchingProcesses
    renderLogTail
}



####################################################################################################
#
# Main
#
####################################################################################################

if [[ -n "${watchIntervalSeconds}" ]]; then
    while true; do
        renderSnapshot
        sleep "${watchIntervalSeconds}"
    done
else
    renderSnapshot
fi
