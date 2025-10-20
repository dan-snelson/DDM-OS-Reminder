#!/bin/zsh --no-rcs
# EA: DDM Pending OS Update Version
# Reports if a DDM-enforced macOS update is pending, based on /var/log/install.log
# Created by: @robjschroeder 10.10.2025
# Inspired by: @dan-snelson DDM-OS-Reminder

set -euo pipefail

DAYS_LOOKBACK="${DAYS_LOOKBACK:-30}"   # change if you want a different window

# Current OS info
currentBuild="$(/usr/bin/sw_vers -buildVersion 2>/dev/null || true)"

# Pull the most recent DDM enforcement ddmEnforcedOSUpdates from the last N days:
# EnforcedInstallDate, VersionString, BuildVersionString
ddmEnforcedOSUpdates="$(
  /usr/bin/awk -v date="$(/bin/date -v-"$DAYS_LOOKBACK"d +%Y-%m-%d)" '$1 >= date' /var/log/install.log 2>/dev/null \
  | /usr/bin/grep -E 'EnforcedInstallDate:' \
  | /usr/bin/sed -n 's/.*EnforcedInstallDate:\([^|]*\)|VersionString:\([^|]*\)|BuildVersionString:\([^|]*\).*/\1\t\2\t\3/p' \
  | /usr/bin/tail -n 1
)"

if [[ -z "$ddmEnforcedOSUpdates" ]]; then
  echo "<result>None</result>"
  exit 0
fi

IFS=$'\t' read -r ts ver build <<<"$ddmEnforcedOSUpdates"

# Normalize and format the enforced date
# Examples in log look like: 2025-10-12T18:00:00Z
ts="${ts%Z}"
prettyDate="$(
  /bin/date -jf "%Y-%m-%dT%H:%M:%S" "$ts" "+%d-%b-%Y" 2>/dev/null \
  || echo "$ts"
)"

# If the enforced version/build matches the current system, treat as none
# (i.e., plan enforces what we already run)
if [[ -n "$currentBuild" && -n "$build" && "$currentBuild" == "$build" ]]; then
  echo "<result>None</result>"
  exit 0
fi

# Otherwise, pending
echo "<result>${ver}</result>"