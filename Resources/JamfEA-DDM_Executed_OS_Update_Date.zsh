#!/bin/zsh --no-rcs
# EA: DDM Executed OS Update Date
# Reports when a DDM-enforced macOS update was executed, based on /var/log/install.log
# Created by: @dan-snelson (inspired by @robjschroeder)
# Example log line:
#   softwareupdated[557]: -[SUOSUManagedServiceDaemon performEnforcementIfNeededWithCompletionBlock:]: Enforcing past-due OS update with install date Thu Nov 13 08:59:56 2025

# Safety: don't use -e or pipefail in Jamf EA context
set -u

DAYS_LOOKBACK="${DAYS_LOOKBACK:-30}"   # Number of days to look back in /var/log/install.log

# Search for most recent enforcement entry within lookback window
enforcementLog="$(
  /usr/bin/awk -v date="$(/bin/date -v-"$DAYS_LOOKBACK"d +%Y-%m-%d)" '$1 >= date' /var/log/install.log 2>/dev/null \
  | /usr/bin/grep 'performEnforcementIfNeededWithCompletionBlock' 2>/dev/null \
  | /usr/bin/tail -n 1 || true
)"

if [[ -z "${enforcementLog}" ]]; then
  echo "<result>None</result>"
  exit 0
fi

# Extract and format enforcement date
executedDateRaw="$(echo "${enforcementLog}" | /usr/bin/sed -E 's/.*install date (.*)$/\1/')"
executedDateFormatted="$(
  /bin/date -jf "%a %b %d %H:%M:%S %Y" "${executedDateRaw}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
  || echo "${executedDateRaw}"
)"

echo "<result>${executedDateFormatted}</result>"
