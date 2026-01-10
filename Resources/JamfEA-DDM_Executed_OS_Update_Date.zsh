#!/bin/zsh --no-rcs

# EA: DDM Executed OS Update Date (log-based)
# Reports when the CURRENT OS version/build first appeared in /var/log/install.log.
#
# Version: 2.3.0rc1
# Date: 10-Jan-2026

# Safety: don't use -e or pipefail in Jamf EA context
set -u

DAYS_LOOKBACK="${DAYS_LOOKBACK:-30}"
startDate="$(/bin/date -v-"$DAYS_LOOKBACK"d +%Y-%m-%d)"

currentVersion="$(/usr/bin/sw_vers -productVersion 2>/dev/null || true)"
currentBuild="$(/usr/bin/sw_vers -buildVersion 2>/dev/null || true)"

if [[ -z "$currentVersion" || -z "$currentBuild" ]]; then
  echo "<result>Unknown</result>"
  exit 0
fi

logWindow="$(
  /usr/bin/awk -v date="$startDate" '$1 >= date' /var/log/install.log 2>/dev/null
)"

# 1) Strongest: explicit “Previous System Version … Current System Version …”
executedLine="$(
  echo "$logWindow" |
  /usr/bin/grep -E "Previous System Version.*Current System Version : ${currentVersion} \\(${currentBuild}\\)" |
  /usr/bin/tail -n 1
)"

# 2) Next best: “Starting with build X (Y)”
if [[ -z "$executedLine" ]]; then
  executedLine="$(
    echo "$logWindow" |
    /usr/bin/grep -F "softwareupdated: Starting with build ${currentVersion} (${currentBuild})" |
    /usr/bin/tail -n 1
  )"
fi

# 3) Fallback: “Fire periodic check after upgrade to …”
if [[ -z "$executedLine" ]]; then
  executedLine="$(
    echo "$logWindow" |
    /usr/bin/grep -F "after upgrade to ${currentVersion} (${currentBuild})" |
    /usr/bin/tail -n 1
  )"
fi

# 4) Last resort: post-logout “Applied MSU update” (does not encode version/build)
if [[ -z "$executedLine" ]]; then
  executedLine="$(
    echo "$logWindow" |
    /usr/bin/grep -F "SUOSUPostLogoutInstallOperation: Applied MSU update" |
    /usr/bin/tail -n 1
  )"
fi

if [[ -z "$executedLine" ]]; then
  echo "<result>None</result>"
  exit 0
fi

# Timestamp is the first two fields: YYYY-MM-DD and HH:MM:SS-## (strip TZ suffix)
rawDate="$(
  echo "$executedLine" |
  /usr/bin/awk '{print $1" "$2}' |
  /usr/bin/sed -E 's/([0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/'
)"

echo "<result>${rawDate}</result>"
exit 0
