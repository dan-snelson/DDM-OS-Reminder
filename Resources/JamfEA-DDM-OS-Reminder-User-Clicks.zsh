#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# DDM OS Reminder: User Clicks
# Reports the user's button clicks for DDM OS Reminder
#
# http://snelson.us/ddm-os-reminder
#
####################################################################################################
#
# Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local:/usr/local/bin

# Script Version
scriptVersion="0.0.1"

# Client-side Log (must match value set in "ddmOSReminder.zsh" script)
scriptLog="/var/log/org.churchofjesuschrist.log"

# Organization's Script Name (must match value set in "ddmOSReminder.zsh" script)
organizationScriptName="dorm"

# Static Row Header text to identify log level (must match value set in "ddmOSReminder.zsh" script)
logRowHeader="NOTICE"

# Static text to identify log entries from this script (must match value set in "ddmOSReminder.zsh" script)
logStaticText="clicked"

# Number of lines to search (from the bottom of the log file)
logLinesToSearch="5"



####################################################################################################
#
# Program
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Match the "$logStaticText" within rows which contain "$logRowHeader" for the "$organizationScriptName"
# for the last "$logLinesToSearch" lines from "$scriptLog"
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

result=$(
  grep -E "$organizationScriptName.*$logStaticText|$logStaticText.*$organizationScriptName" "$scriptLog" 2>/dev/null \
  | tail -n "$logLinesToSearch" \
  | while IFS= read -r line; do
      ts=$(sed -E 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/' <<< "$line")
      msg=$(sed -E "s/.*\[$logRowHeader\][[:space:]]*//" <<< "$line")
      [[ -n "$ts" && -n "$msg" ]] && echo "$ts $msg"
    done
)



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Output the result
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ -z "$result" ]]; then
  result="None"
fi

echo "<result>${result}</result>"
