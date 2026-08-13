#!/bin/zsh --no-rcs

# EA: DDM OS Reminder Next Scheduled Reminder
# Version: 4.1.0
# Reports the local date and time stored in dor-state.plist for the next daemon reminder.

# Safety: don't use -e or pipefail in Jamf EA context
set -u

# Change this value to match the RDNN used when assembling DDM OS Reminder.
# Internal overrides support local fixture testing only.
reverseDomainNameNotation="${reverseDomainNameNotationOverride:-org.churchofjesuschrist}"
plistBuddyPath="/usr/libexec/PlistBuddy"
dorStatePlistPath="${dorStatePlistPathOverride:-/Library/Management/${reverseDomainNameNotation}/dor-state.plist}"

# Jamf Pro Date data type sentinel values for non-date scheduler states.
# 2000-01-01 00:00:00 = daemon-driven reminders disabled (FALSE)
# 2000-01-01 00:00:01 = state plist missing or unreadable
# 2000-01-01 00:00:02 = NextScheduledReminder unset or empty
# 2000-01-01 00:00:03 = corrupt plist or invalid timestamp
nextReminderDateCodeDisabled="2000-01-01 00:00:00"
nextReminderDateCodeMissing="2000-01-01 00:00:01"
nextReminderDateCodeUnset="2000-01-01 00:00:02"
nextReminderDateCodeInvalid="2000-01-01 00:00:03"
nextReminderTimestampRegex='^[0-9]{4}-[0-9]{2}-[0-9]{2}:[0-9]{2}:[0-9]{2}:[0-9]{2}$'



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Utilities
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function emitResult() {
    echo "<result>${1}</result>"
    exit 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Extension Attribute Result
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -x "${plistBuddyPath}" || ! -r "${dorStatePlistPath}" ]]; then
    emitResult "${nextReminderDateCodeMissing}"
fi

if ! "${plistBuddyPath}" -c "Print" "${dorStatePlistPath}" >/dev/null 2>&1; then
    emitResult "${nextReminderDateCodeInvalid}"
fi

nextScheduledReminder="$("${plistBuddyPath}" -c "Print :NextScheduledReminder" "${dorStatePlistPath}" 2>/dev/null)"
stateReadStatus="${?}"

if (( stateReadStatus != 0 )) || [[ -z "${nextScheduledReminder}" ]]; then
    emitResult "${nextReminderDateCodeUnset}"
fi

if [[ "${nextScheduledReminder:l}" == "false" ]]; then
    emitResult "${nextReminderDateCodeDisabled}"
fi

if [[ ! "${nextScheduledReminder}" =~ ${nextReminderTimestampRegex} ]]; then
    emitResult "${nextReminderDateCodeInvalid}"
fi

normalizedNextScheduledReminder="$(
    /bin/date -j -f "%Y-%m-%d:%H:%M:%S" "${nextScheduledReminder}" "+%Y-%m-%d:%H:%M:%S" 2>/dev/null
)"

if [[ -z "${normalizedNextScheduledReminder}" || "${normalizedNextScheduledReminder}" != "${nextScheduledReminder}" ]]; then
    emitResult "${nextReminderDateCodeInvalid}"
fi

formattedNextScheduledReminder="${normalizedNextScheduledReminder[1,10]} ${normalizedNextScheduledReminder[12,-1]}"
emitResult "${formattedNextScheduledReminder}"
