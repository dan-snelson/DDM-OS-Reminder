#!/bin/zsh --no-rcs
# shellcheck shell=bash
#
# createPlist.zsh — Generate .plist and .mobileconfig from reminderDialog.zsh
#
# NOTE: This script is OPTIONAL since assemble.zsh already generates configuration files.
# Use this only if you need to regenerate configs without running the full assembly process.
#
# This script extracts default values from the original reminderDialog.zsh file
# and generates corresponding .plist and .mobileconfig files.

set -euo pipefail

scriptVersion="3.1.0b2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/../reminderDialog.zsh"

[[ -f "$SOURCE_SCRIPT" ]] || { echo "ERROR: Cannot find reminderDialog.zsh at ${SOURCE_SCRIPT}"; exit 1; }

testingMode="no"
if [[ "${1:-}" == "--testing" ]]; then
    testingMode="yes"
    shift
fi

reverseDomainNameNotation=$(awk -F'"' '/^reverseDomainNameNotation=/{print $2}' "$SOURCE_SCRIPT")
organizationScriptName=$(awk -F'"' '/^organizationScriptName=/{print $2}' "$SOURCE_SCRIPT")
datestamp=$(date '+%Y-%m-%d-%H%M%S')

# ─────────────────────────────────────────────────────────────
# Safety check for default reverseDomainNameNotation
# IMPORTANT: You must customize reminderDialog.zsh BEFORE running this script.
# Change reverseDomainNameNotation from "org.churchofjesuschrist" to your organization's value.
# ─────────────────────────────────────────────────────────────
if [[ "$reverseDomainNameNotation" == "org.churchofjesuschrist" ]] && [[ "${testingMode}" != "yes" ]]; then
    echo "ERROR: Please customize 'reminderDialog.zsh' before executing this script."
    echo "       Change reverseDomainNameNotation to your organization's value (e.g., us.snelson)."
    echo "       Then run this script again to generate configs from your customized values."
    exit 1
fi

# Target Output Files
OUTPUT_PLIST_FILE="${SCRIPT_DIR}/${reverseDomainNameNotation}.${organizationScriptName}-${datestamp}.plist"
OUTPUT_MOBILECONFIG_FILE="${SCRIPT_DIR}/${reverseDomainNameNotation}.${organizationScriptName}-${datestamp}-unsigned.mobileconfig"

# Generate UUIDs for the profile and the ManagedClient payload
PROFILE_UUID="$(uuidgen | tr '[:lower:]' '[:upper:]')"
MANAGEDCLIENT_PAYLOAD_UUID="$(uuidgen | tr '[:lower:]' '[:upper:]')"

echo "Extracting preference values from ${SOURCE_SCRIPT#${SCRIPT_DIR}/} → $OUTPUT_PLIST_FILE"

# ─────────────────────────────────────────────────────────────
# Extract value from preferenceConfiguration map (v2.3.0+ format)
# Format: ["key"]="type|defaultValue"
# ─────────────────────────────────────────────────────────────
extract_from_preference_map() {
    local key=$1
    local line
    
    # Search for the key in the preferenceConfiguration map (contains "|" separator)
    line=$(grep -m1 "\[\"${key}\"\]=\"[^|]*|" "$SOURCE_SCRIPT") || {
        echo "ERROR: Missing key '${key}' in preferenceConfiguration map" >&2
        exit 1
    }

    # Extract the value after the pipe: ["key"]="type|value"
    if [[ $line =~ '"[^|]+\|([^"]*)"' ]]; then
        echo "${match[1]}"
    else
        echo "ERROR: Cannot extract value for ${key}" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------
# Safe placeholder normalization
# ---------------------------------------------------------------------
normalize_placeholders() {
    perl -pe '
        # $( date +%A ) -> {weekday}
        s/\$\(\s*date\s+\+["'"'"']?%A["'"'"']?\s*\)/{weekday}/g;

        # $(/usr/local/bin/dialog -v) -> {dialogVersion}
        s/\$\(\/usr\/local\/bin\/dialog\s+-[^\s]+[^\)]*\)/{dialogVersion}/g;

        # ${var} -> {var}
        s/\$\{([^}]+)\}/{${1}}/g;
    '
}

xml_escape() {
    sed -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&apos;/g"
}

process() { echo "$1" | normalize_placeholders | xml_escape; }

# ─────────────────────────────────────────────────────────────
# Extract globals (still use awk for non-map variables)
# ─────────────────────────────────────────────────────────────
scriptVersion=$(awk -F'"' '/^scriptVersion=/{print $2}' "$SOURCE_SCRIPT")

# Extract from preferenceConfiguration map
scriptLog=$(extract_from_preference_map scriptLog)
daysBeforeDeadlineDisplayReminder=$(extract_from_preference_map daysBeforeDeadlineDisplayReminder)
daysBeforeDeadlineBlurscreen=$(extract_from_preference_map daysBeforeDeadlineBlurscreen)
daysBeforeDeadlineHidingButton2=$(extract_from_preference_map daysBeforeDeadlineHidingButton2)
daysOfExcessiveUptimeWarning=$(extract_from_preference_map daysOfExcessiveUptimeWarning)
daysPastDeadlineRestartWorkflow=$(extract_from_preference_map daysPastDeadlineRestartWorkflow)
pastDeadlineRestartBehavior=$(extract_from_preference_map pastDeadlineRestartBehavior)
meetingDelay=$(extract_from_preference_map meetingDelay)
acceptableAssertionApplicationNames=$(extract_from_preference_map acceptableAssertionApplicationNames)
dateFormatDeadlineHumanReadable=$(extract_from_preference_map dateFormatDeadlineHumanReadable)
swapOverlayAndLogo_raw=$(extract_from_preference_map swapOverlayAndLogo)
hideStagedInfo_raw=$(extract_from_preference_map hideStagedInfo)
minimumDiskFreePercentage=$(extract_from_preference_map minimumDiskFreePercentage)
languageOverride=$(extract_from_preference_map languageOverride)

case "${swapOverlayAndLogo_raw:u}" in
    YES|TRUE|1) swapOverlayAndLogo_xml="<true/>" ;;
    *)          swapOverlayAndLogo_xml="<false/>" ;;
esac

case "${hideStagedInfo_raw:u}" in
    YES|TRUE|1) hideStagedInfo_xml="<true/>" ;;
    *)          hideStagedInfo_xml="<false/>" ;;
esac

# ─────────────────────────────────────────────────────────────
# Extract all values from preferenceConfiguration map
# ─────────────────────────────────────────────────────────────
defaultTitle=$(extract_from_preference_map title)
defaultExcessiveUptimeWarningMessage=$(extract_from_preference_map excessiveUptimeWarningMessage)
defaultExcessiveUptimeWarningMessageLocalizedEn=$(extract_from_preference_map excessiveUptimeWarningMessageLocalizedEn)
defaultExcessiveUptimeWarningMessageLocalizedDe=$(extract_from_preference_map excessiveUptimeWarningMessageLocalizedDe)
defaultExcessiveUptimeWarningMessageLocalizedFr=$(extract_from_preference_map excessiveUptimeWarningMessageLocalizedFr)
defaultExcessiveUptimeWarningMessageLocalizedEs=$(extract_from_preference_map excessiveUptimeWarningMessageLocalizedEs)
defaultExcessiveUptimeWarningMessageLocalizedPt=$(extract_from_preference_map excessiveUptimeWarningMessageLocalizedPt)
defaultExcessiveUptimeWarningMessageLocalizedJa=$(extract_from_preference_map excessiveUptimeWarningMessageLocalizedJa)
defaultExcessiveUptimeWarningMessageLocalizedNl=$(extract_from_preference_map excessiveUptimeWarningMessageLocalizedNl)
defaultDiskSpaceWarningMessage=$(extract_from_preference_map diskSpaceWarningMessage)
defaultDiskSpaceWarningMessageLocalizedEn=$(extract_from_preference_map diskSpaceWarningMessageLocalizedEn)
defaultDiskSpaceWarningMessageLocalizedDe=$(extract_from_preference_map diskSpaceWarningMessageLocalizedDe)
defaultDiskSpaceWarningMessageLocalizedFr=$(extract_from_preference_map diskSpaceWarningMessageLocalizedFr)
defaultDiskSpaceWarningMessageLocalizedEs=$(extract_from_preference_map diskSpaceWarningMessageLocalizedEs)
defaultDiskSpaceWarningMessageLocalizedPt=$(extract_from_preference_map diskSpaceWarningMessageLocalizedPt)
defaultDiskSpaceWarningMessageLocalizedJa=$(extract_from_preference_map diskSpaceWarningMessageLocalizedJa)
defaultDiskSpaceWarningMessageLocalizedNl=$(extract_from_preference_map diskSpaceWarningMessageLocalizedNl)
defaultMessage=$(extract_from_preference_map message)
defaultInfobox=$(extract_from_preference_map infobox)
defaultHelpmessage=$(extract_from_preference_map helpmessage)
defaultHelpimage=$(extract_from_preference_map helpimage)
defaultStagedUpdateMessage=$(extract_from_preference_map stagedUpdateMessage)
defaultStagedUpdateMessageLocalizedEn=$(extract_from_preference_map stagedUpdateMessageLocalizedEn)
defaultStagedUpdateMessageLocalizedDe=$(extract_from_preference_map stagedUpdateMessageLocalizedDe)
defaultStagedUpdateMessageLocalizedFr=$(extract_from_preference_map stagedUpdateMessageLocalizedFr)
defaultStagedUpdateMessageLocalizedEs=$(extract_from_preference_map stagedUpdateMessageLocalizedEs)
defaultStagedUpdateMessageLocalizedPt=$(extract_from_preference_map stagedUpdateMessageLocalizedPt)
defaultStagedUpdateMessageLocalizedJa=$(extract_from_preference_map stagedUpdateMessageLocalizedJa)
defaultStagedUpdateMessageLocalizedNl=$(extract_from_preference_map stagedUpdateMessageLocalizedNl)
defaultPartiallyStagedUpdateMessage=$(extract_from_preference_map partiallyStagedUpdateMessage)
defaultPartiallyStagedUpdateMessageLocalizedEn=$(extract_from_preference_map partiallyStagedUpdateMessageLocalizedEn)
defaultPartiallyStagedUpdateMessageLocalizedDe=$(extract_from_preference_map partiallyStagedUpdateMessageLocalizedDe)
defaultPartiallyStagedUpdateMessageLocalizedFr=$(extract_from_preference_map partiallyStagedUpdateMessageLocalizedFr)
defaultPartiallyStagedUpdateMessageLocalizedEs=$(extract_from_preference_map partiallyStagedUpdateMessageLocalizedEs)
defaultPartiallyStagedUpdateMessageLocalizedPt=$(extract_from_preference_map partiallyStagedUpdateMessageLocalizedPt)
defaultPartiallyStagedUpdateMessageLocalizedJa=$(extract_from_preference_map partiallyStagedUpdateMessageLocalizedJa)
defaultPartiallyStagedUpdateMessageLocalizedNl=$(extract_from_preference_map partiallyStagedUpdateMessageLocalizedNl)
defaultPendingDownloadMessage=$(extract_from_preference_map pendingDownloadMessage)
defaultPendingDownloadMessageLocalizedEn=$(extract_from_preference_map pendingDownloadMessageLocalizedEn)
defaultPendingDownloadMessageLocalizedDe=$(extract_from_preference_map pendingDownloadMessageLocalizedDe)
defaultPendingDownloadMessageLocalizedFr=$(extract_from_preference_map pendingDownloadMessageLocalizedFr)
defaultPendingDownloadMessageLocalizedEs=$(extract_from_preference_map pendingDownloadMessageLocalizedEs)
defaultPendingDownloadMessageLocalizedPt=$(extract_from_preference_map pendingDownloadMessageLocalizedPt)
defaultPendingDownloadMessageLocalizedJa=$(extract_from_preference_map pendingDownloadMessageLocalizedJa)
defaultPendingDownloadMessageLocalizedNl=$(extract_from_preference_map pendingDownloadMessageLocalizedNl)
defaultButton1text=$(extract_from_preference_map button1text)
defaultButton2text=$(extract_from_preference_map button2text)
defaultInfobuttontext=$(extract_from_preference_map infobuttontext)
defaultTitleLocalizedEn=$(extract_from_preference_map titleLocalizedEn)
defaultTitleLocalizedDe=$(extract_from_preference_map titleLocalizedDe)
defaultTitleLocalizedFr=$(extract_from_preference_map titleLocalizedFr)
defaultTitleLocalizedEs=$(extract_from_preference_map titleLocalizedEs)
defaultTitleLocalizedPt=$(extract_from_preference_map titleLocalizedPt)
defaultTitleLocalizedJa=$(extract_from_preference_map titleLocalizedJa)
defaultTitleLocalizedNl=$(extract_from_preference_map titleLocalizedNl)
defaultButton1textLocalizedEn=$(extract_from_preference_map button1textLocalizedEn)
defaultButton1textLocalizedDe=$(extract_from_preference_map button1textLocalizedDe)
defaultButton1textLocalizedFr=$(extract_from_preference_map button1textLocalizedFr)
defaultButton1textLocalizedEs=$(extract_from_preference_map button1textLocalizedEs)
defaultButton1textLocalizedPt=$(extract_from_preference_map button1textLocalizedPt)
defaultButton1textLocalizedJa=$(extract_from_preference_map button1textLocalizedJa)
defaultButton1textLocalizedNl=$(extract_from_preference_map button1textLocalizedNl)
defaultButton2textLocalizedEn=$(extract_from_preference_map button2textLocalizedEn)
defaultButton2textLocalizedDe=$(extract_from_preference_map button2textLocalizedDe)
defaultButton2textLocalizedFr=$(extract_from_preference_map button2textLocalizedFr)
defaultButton2textLocalizedEs=$(extract_from_preference_map button2textLocalizedEs)
defaultButton2textLocalizedPt=$(extract_from_preference_map button2textLocalizedPt)
defaultButton2textLocalizedJa=$(extract_from_preference_map button2textLocalizedJa)
defaultButton2textLocalizedNl=$(extract_from_preference_map button2textLocalizedNl)
defaultInfobuttontextLocalizedEn=$(extract_from_preference_map infobuttontextLocalizedEn)
defaultInfobuttontextLocalizedDe=$(extract_from_preference_map infobuttontextLocalizedDe)
defaultInfobuttontextLocalizedFr=$(extract_from_preference_map infobuttontextLocalizedFr)
defaultInfobuttontextLocalizedEs=$(extract_from_preference_map infobuttontextLocalizedEs)
defaultInfobuttontextLocalizedPt=$(extract_from_preference_map infobuttontextLocalizedPt)
defaultInfobuttontextLocalizedJa=$(extract_from_preference_map infobuttontextLocalizedJa)
defaultInfobuttontextLocalizedNl=$(extract_from_preference_map infobuttontextLocalizedNl)
defaultOverlayiconURL=$(extract_from_preference_map organizationOverlayiconURL)
defaultOverlayiconURLdark=$(extract_from_preference_map organizationOverlayiconURLdark)
defaultSupportTeamName=$(extract_from_preference_map supportTeamName)
defaultSupportTeamPhone=$(extract_from_preference_map supportTeamPhone)
defaultSupportTeamEmail=$(extract_from_preference_map supportTeamEmail)
defaultSupportTeamWebsite=$(extract_from_preference_map supportTeamWebsite)
defaultSupportKB=$(extract_from_preference_map supportKB)
defaultInfobuttonaction=$(extract_from_preference_map infobuttonaction)
defaultSupportKBURL=$(extract_from_preference_map supportKBURL)
defaultSupportAssistanceMessage=$(extract_from_preference_map supportAssistanceMessage)
defaultSupportAssistanceMessageLocalizedEn=$(extract_from_preference_map supportAssistanceMessageLocalizedEn)
defaultSupportAssistanceMessageLocalizedDe=$(extract_from_preference_map supportAssistanceMessageLocalizedDe)
defaultSupportAssistanceMessageLocalizedFr=$(extract_from_preference_map supportAssistanceMessageLocalizedFr)
defaultSupportAssistanceMessageLocalizedEs=$(extract_from_preference_map supportAssistanceMessageLocalizedEs)
defaultSupportAssistanceMessageLocalizedPt=$(extract_from_preference_map supportAssistanceMessageLocalizedPt)
defaultSupportAssistanceMessageLocalizedJa=$(extract_from_preference_map supportAssistanceMessageLocalizedJa)
defaultSupportAssistanceMessageLocalizedNl=$(extract_from_preference_map supportAssistanceMessageLocalizedNl)
defaultMessageLocalizedEn=$(extract_from_preference_map messageLocalizedEn)
defaultMessageLocalizedDe=$(extract_from_preference_map messageLocalizedDe)
defaultMessageLocalizedFr=$(extract_from_preference_map messageLocalizedFr)
defaultMessageLocalizedEs=$(extract_from_preference_map messageLocalizedEs)
defaultMessageLocalizedPt=$(extract_from_preference_map messageLocalizedPt)
defaultMessageLocalizedJa=$(extract_from_preference_map messageLocalizedJa)
defaultMessageLocalizedNl=$(extract_from_preference_map messageLocalizedNl)
defaultHelpmessageLocalizedEn=$(extract_from_preference_map helpmessageLocalizedEn)
defaultHelpmessageLocalizedDe=$(extract_from_preference_map helpmessageLocalizedDe)
defaultHelpmessageLocalizedFr=$(extract_from_preference_map helpmessageLocalizedFr)
defaultHelpmessageLocalizedEs=$(extract_from_preference_map helpmessageLocalizedEs)
defaultHelpmessageLocalizedPt=$(extract_from_preference_map helpmessageLocalizedPt)
defaultHelpmessageLocalizedJa=$(extract_from_preference_map helpmessageLocalizedJa)
defaultHelpmessageLocalizedNl=$(extract_from_preference_map helpmessageLocalizedNl)
defaultRelativeDeadlineToday=$(extract_from_preference_map relativeDeadlineToday)
defaultRelativeDeadlineTodayLocalizedEn=$(extract_from_preference_map relativeDeadlineTodayLocalizedEn)
defaultRelativeDeadlineTodayLocalizedDe=$(extract_from_preference_map relativeDeadlineTodayLocalizedDe)
defaultRelativeDeadlineTodayLocalizedFr=$(extract_from_preference_map relativeDeadlineTodayLocalizedFr)
defaultRelativeDeadlineTodayLocalizedEs=$(extract_from_preference_map relativeDeadlineTodayLocalizedEs)
defaultRelativeDeadlineTodayLocalizedPt=$(extract_from_preference_map relativeDeadlineTodayLocalizedPt)
defaultRelativeDeadlineTodayLocalizedJa=$(extract_from_preference_map relativeDeadlineTodayLocalizedJa)
defaultRelativeDeadlineTodayLocalizedNl=$(extract_from_preference_map relativeDeadlineTodayLocalizedNl)
defaultRelativeDeadlineTomorrow=$(extract_from_preference_map relativeDeadlineTomorrow)
defaultRelativeDeadlineTomorrowLocalizedEn=$(extract_from_preference_map relativeDeadlineTomorrowLocalizedEn)
defaultRelativeDeadlineTomorrowLocalizedDe=$(extract_from_preference_map relativeDeadlineTomorrowLocalizedDe)
defaultRelativeDeadlineTomorrowLocalizedFr=$(extract_from_preference_map relativeDeadlineTomorrowLocalizedFr)
defaultRelativeDeadlineTomorrowLocalizedEs=$(extract_from_preference_map relativeDeadlineTomorrowLocalizedEs)
defaultRelativeDeadlineTomorrowLocalizedPt=$(extract_from_preference_map relativeDeadlineTomorrowLocalizedPt)
defaultRelativeDeadlineTomorrowLocalizedJa=$(extract_from_preference_map relativeDeadlineTomorrowLocalizedJa)
defaultRelativeDeadlineTomorrowLocalizedNl=$(extract_from_preference_map relativeDeadlineTomorrowLocalizedNl)
defaultUpdateWord=$(extract_from_preference_map updateWord)
defaultUpdateWordLocalizedEn=$(extract_from_preference_map updateWordLocalizedEn)
defaultUpdateWordLocalizedDe=$(extract_from_preference_map updateWordLocalizedDe)
defaultUpdateWordLocalizedFr=$(extract_from_preference_map updateWordLocalizedFr)
defaultUpdateWordLocalizedEs=$(extract_from_preference_map updateWordLocalizedEs)
defaultUpdateWordLocalizedPt=$(extract_from_preference_map updateWordLocalizedPt)
defaultUpdateWordLocalizedJa=$(extract_from_preference_map updateWordLocalizedJa)
defaultUpdateWordLocalizedNl=$(extract_from_preference_map updateWordLocalizedNl)
defaultUpgradeWord=$(extract_from_preference_map upgradeWord)
defaultUpgradeWordLocalizedEn=$(extract_from_preference_map upgradeWordLocalizedEn)
defaultUpgradeWordLocalizedDe=$(extract_from_preference_map upgradeWordLocalizedDe)
defaultUpgradeWordLocalizedFr=$(extract_from_preference_map upgradeWordLocalizedFr)
defaultUpgradeWordLocalizedEs=$(extract_from_preference_map upgradeWordLocalizedEs)
defaultUpgradeWordLocalizedPt=$(extract_from_preference_map upgradeWordLocalizedPt)
defaultUpgradeWordLocalizedJa=$(extract_from_preference_map upgradeWordLocalizedJa)
defaultUpgradeWordLocalizedNl=$(extract_from_preference_map upgradeWordLocalizedNl)
defaultSoftwareUpdateButtonTextUpdate=$(extract_from_preference_map softwareUpdateButtonTextUpdate)
defaultSoftwareUpdateButtonTextUpdateLocalizedEn=$(extract_from_preference_map softwareUpdateButtonTextUpdateLocalizedEn)
defaultSoftwareUpdateButtonTextUpdateLocalizedDe=$(extract_from_preference_map softwareUpdateButtonTextUpdateLocalizedDe)
defaultSoftwareUpdateButtonTextUpdateLocalizedFr=$(extract_from_preference_map softwareUpdateButtonTextUpdateLocalizedFr)
defaultSoftwareUpdateButtonTextUpdateLocalizedEs=$(extract_from_preference_map softwareUpdateButtonTextUpdateLocalizedEs)
defaultSoftwareUpdateButtonTextUpdateLocalizedPt=$(extract_from_preference_map softwareUpdateButtonTextUpdateLocalizedPt)
defaultSoftwareUpdateButtonTextUpdateLocalizedJa=$(extract_from_preference_map softwareUpdateButtonTextUpdateLocalizedJa)
defaultSoftwareUpdateButtonTextUpdateLocalizedNl=$(extract_from_preference_map softwareUpdateButtonTextUpdateLocalizedNl)
defaultSoftwareUpdateButtonTextUpgrade=$(extract_from_preference_map softwareUpdateButtonTextUpgrade)
defaultSoftwareUpdateButtonTextUpgradeLocalizedEn=$(extract_from_preference_map softwareUpdateButtonTextUpgradeLocalizedEn)
defaultSoftwareUpdateButtonTextUpgradeLocalizedDe=$(extract_from_preference_map softwareUpdateButtonTextUpgradeLocalizedDe)
defaultSoftwareUpdateButtonTextUpgradeLocalizedFr=$(extract_from_preference_map softwareUpdateButtonTextUpgradeLocalizedFr)
defaultSoftwareUpdateButtonTextUpgradeLocalizedEs=$(extract_from_preference_map softwareUpdateButtonTextUpgradeLocalizedEs)
defaultSoftwareUpdateButtonTextUpgradeLocalizedPt=$(extract_from_preference_map softwareUpdateButtonTextUpgradeLocalizedPt)
defaultSoftwareUpdateButtonTextUpgradeLocalizedJa=$(extract_from_preference_map softwareUpdateButtonTextUpgradeLocalizedJa)
defaultSoftwareUpdateButtonTextUpgradeLocalizedNl=$(extract_from_preference_map softwareUpdateButtonTextUpgradeLocalizedNl)
defaultRestartNowButtonText=$(extract_from_preference_map restartNowButtonText)
defaultRestartNowButtonTextLocalizedEn=$(extract_from_preference_map restartNowButtonTextLocalizedEn)
defaultRestartNowButtonTextLocalizedDe=$(extract_from_preference_map restartNowButtonTextLocalizedDe)
defaultRestartNowButtonTextLocalizedFr=$(extract_from_preference_map restartNowButtonTextLocalizedFr)
defaultRestartNowButtonTextLocalizedEs=$(extract_from_preference_map restartNowButtonTextLocalizedEs)
defaultRestartNowButtonTextLocalizedPt=$(extract_from_preference_map restartNowButtonTextLocalizedPt)
defaultRestartNowButtonTextLocalizedJa=$(extract_from_preference_map restartNowButtonTextLocalizedJa)
defaultRestartNowButtonTextLocalizedNl=$(extract_from_preference_map restartNowButtonTextLocalizedNl)
defaultInfoboxLabelCurrent=$(extract_from_preference_map infoboxLabelCurrent)
defaultInfoboxLabelCurrentLocalizedEn=$(extract_from_preference_map infoboxLabelCurrentLocalizedEn)
defaultInfoboxLabelCurrentLocalizedDe=$(extract_from_preference_map infoboxLabelCurrentLocalizedDe)
defaultInfoboxLabelCurrentLocalizedFr=$(extract_from_preference_map infoboxLabelCurrentLocalizedFr)
defaultInfoboxLabelCurrentLocalizedEs=$(extract_from_preference_map infoboxLabelCurrentLocalizedEs)
defaultInfoboxLabelCurrentLocalizedPt=$(extract_from_preference_map infoboxLabelCurrentLocalizedPt)
defaultInfoboxLabelCurrentLocalizedJa=$(extract_from_preference_map infoboxLabelCurrentLocalizedJa)
defaultInfoboxLabelCurrentLocalizedNl=$(extract_from_preference_map infoboxLabelCurrentLocalizedNl)
defaultInfoboxLabelRequired=$(extract_from_preference_map infoboxLabelRequired)
defaultInfoboxLabelRequiredLocalizedEn=$(extract_from_preference_map infoboxLabelRequiredLocalizedEn)
defaultInfoboxLabelRequiredLocalizedDe=$(extract_from_preference_map infoboxLabelRequiredLocalizedDe)
defaultInfoboxLabelRequiredLocalizedFr=$(extract_from_preference_map infoboxLabelRequiredLocalizedFr)
defaultInfoboxLabelRequiredLocalizedEs=$(extract_from_preference_map infoboxLabelRequiredLocalizedEs)
defaultInfoboxLabelRequiredLocalizedPt=$(extract_from_preference_map infoboxLabelRequiredLocalizedPt)
defaultInfoboxLabelRequiredLocalizedJa=$(extract_from_preference_map infoboxLabelRequiredLocalizedJa)
defaultInfoboxLabelRequiredLocalizedNl=$(extract_from_preference_map infoboxLabelRequiredLocalizedNl)
defaultInfoboxLabelDeadline=$(extract_from_preference_map infoboxLabelDeadline)
defaultInfoboxLabelDeadlineLocalizedEn=$(extract_from_preference_map infoboxLabelDeadlineLocalizedEn)
defaultInfoboxLabelDeadlineLocalizedDe=$(extract_from_preference_map infoboxLabelDeadlineLocalizedDe)
defaultInfoboxLabelDeadlineLocalizedFr=$(extract_from_preference_map infoboxLabelDeadlineLocalizedFr)
defaultInfoboxLabelDeadlineLocalizedEs=$(extract_from_preference_map infoboxLabelDeadlineLocalizedEs)
defaultInfoboxLabelDeadlineLocalizedPt=$(extract_from_preference_map infoboxLabelDeadlineLocalizedPt)
defaultInfoboxLabelDeadlineLocalizedJa=$(extract_from_preference_map infoboxLabelDeadlineLocalizedJa)
defaultInfoboxLabelDeadlineLocalizedNl=$(extract_from_preference_map infoboxLabelDeadlineLocalizedNl)
defaultInfoboxLabelDaysRemaining=$(extract_from_preference_map infoboxLabelDaysRemaining)
defaultInfoboxLabelDaysRemainingLocalizedEn=$(extract_from_preference_map infoboxLabelDaysRemainingLocalizedEn)
defaultInfoboxLabelDaysRemainingLocalizedDe=$(extract_from_preference_map infoboxLabelDaysRemainingLocalizedDe)
defaultInfoboxLabelDaysRemainingLocalizedFr=$(extract_from_preference_map infoboxLabelDaysRemainingLocalizedFr)
defaultInfoboxLabelDaysRemainingLocalizedEs=$(extract_from_preference_map infoboxLabelDaysRemainingLocalizedEs)
defaultInfoboxLabelDaysRemainingLocalizedPt=$(extract_from_preference_map infoboxLabelDaysRemainingLocalizedPt)
defaultInfoboxLabelDaysRemainingLocalizedJa=$(extract_from_preference_map infoboxLabelDaysRemainingLocalizedJa)
defaultInfoboxLabelDaysRemainingLocalizedNl=$(extract_from_preference_map infoboxLabelDaysRemainingLocalizedNl)
defaultInfoboxLabelLastRestart=$(extract_from_preference_map infoboxLabelLastRestart)
defaultInfoboxLabelLastRestartLocalizedEn=$(extract_from_preference_map infoboxLabelLastRestartLocalizedEn)
defaultInfoboxLabelLastRestartLocalizedDe=$(extract_from_preference_map infoboxLabelLastRestartLocalizedDe)
defaultInfoboxLabelLastRestartLocalizedFr=$(extract_from_preference_map infoboxLabelLastRestartLocalizedFr)
defaultInfoboxLabelLastRestartLocalizedEs=$(extract_from_preference_map infoboxLabelLastRestartLocalizedEs)
defaultInfoboxLabelLastRestartLocalizedPt=$(extract_from_preference_map infoboxLabelLastRestartLocalizedPt)
defaultInfoboxLabelLastRestartLocalizedJa=$(extract_from_preference_map infoboxLabelLastRestartLocalizedJa)
defaultInfoboxLabelLastRestartLocalizedNl=$(extract_from_preference_map infoboxLabelLastRestartLocalizedNl)
defaultInfoboxLabelFreeDiskSpace=$(extract_from_preference_map infoboxLabelFreeDiskSpace)
defaultInfoboxLabelFreeDiskSpaceLocalizedEn=$(extract_from_preference_map infoboxLabelFreeDiskSpaceLocalizedEn)
defaultInfoboxLabelFreeDiskSpaceLocalizedDe=$(extract_from_preference_map infoboxLabelFreeDiskSpaceLocalizedDe)
defaultInfoboxLabelFreeDiskSpaceLocalizedFr=$(extract_from_preference_map infoboxLabelFreeDiskSpaceLocalizedFr)
defaultInfoboxLabelFreeDiskSpaceLocalizedEs=$(extract_from_preference_map infoboxLabelFreeDiskSpaceLocalizedEs)
defaultInfoboxLabelFreeDiskSpaceLocalizedPt=$(extract_from_preference_map infoboxLabelFreeDiskSpaceLocalizedPt)
defaultInfoboxLabelFreeDiskSpaceLocalizedJa=$(extract_from_preference_map infoboxLabelFreeDiskSpaceLocalizedJa)
defaultInfoboxLabelFreeDiskSpaceLocalizedNl=$(extract_from_preference_map infoboxLabelFreeDiskSpaceLocalizedNl)
defaultDeadlineEnforcementMessageAbsolute=$(extract_from_preference_map deadlineEnforcementMessageAbsolute)
defaultDeadlineEnforcementMessageAbsoluteLocalizedEn=$(extract_from_preference_map deadlineEnforcementMessageAbsoluteLocalizedEn)
defaultDeadlineEnforcementMessageAbsoluteLocalizedDe=$(extract_from_preference_map deadlineEnforcementMessageAbsoluteLocalizedDe)
defaultDeadlineEnforcementMessageAbsoluteLocalizedFr=$(extract_from_preference_map deadlineEnforcementMessageAbsoluteLocalizedFr)
defaultDeadlineEnforcementMessageAbsoluteLocalizedEs=$(extract_from_preference_map deadlineEnforcementMessageAbsoluteLocalizedEs)
defaultDeadlineEnforcementMessageAbsoluteLocalizedPt=$(extract_from_preference_map deadlineEnforcementMessageAbsoluteLocalizedPt)
defaultDeadlineEnforcementMessageAbsoluteLocalizedJa=$(extract_from_preference_map deadlineEnforcementMessageAbsoluteLocalizedJa)
defaultDeadlineEnforcementMessageAbsoluteLocalizedNl=$(extract_from_preference_map deadlineEnforcementMessageAbsoluteLocalizedNl)
defaultDeadlineEnforcementMessageRelative=$(extract_from_preference_map deadlineEnforcementMessageRelative)
defaultDeadlineEnforcementMessageRelativeLocalizedEn=$(extract_from_preference_map deadlineEnforcementMessageRelativeLocalizedEn)
defaultDeadlineEnforcementMessageRelativeLocalizedDe=$(extract_from_preference_map deadlineEnforcementMessageRelativeLocalizedDe)
defaultDeadlineEnforcementMessageRelativeLocalizedFr=$(extract_from_preference_map deadlineEnforcementMessageRelativeLocalizedFr)
defaultDeadlineEnforcementMessageRelativeLocalizedEs=$(extract_from_preference_map deadlineEnforcementMessageRelativeLocalizedEs)
defaultDeadlineEnforcementMessageRelativeLocalizedPt=$(extract_from_preference_map deadlineEnforcementMessageRelativeLocalizedPt)
defaultDeadlineEnforcementMessageRelativeLocalizedJa=$(extract_from_preference_map deadlineEnforcementMessageRelativeLocalizedJa)
defaultDeadlineEnforcementMessageRelativeLocalizedNl=$(extract_from_preference_map deadlineEnforcementMessageRelativeLocalizedNl)
defaultPastDeadlinePromptTitle=$(extract_from_preference_map pastDeadlinePromptTitle)
defaultPastDeadlinePromptTitleLocalizedEn=$(extract_from_preference_map pastDeadlinePromptTitleLocalizedEn)
defaultPastDeadlinePromptTitleLocalizedDe=$(extract_from_preference_map pastDeadlinePromptTitleLocalizedDe)
defaultPastDeadlinePromptTitleLocalizedFr=$(extract_from_preference_map pastDeadlinePromptTitleLocalizedFr)
defaultPastDeadlinePromptTitleLocalizedEs=$(extract_from_preference_map pastDeadlinePromptTitleLocalizedEs)
defaultPastDeadlinePromptTitleLocalizedPt=$(extract_from_preference_map pastDeadlinePromptTitleLocalizedPt)
defaultPastDeadlinePromptTitleLocalizedJa=$(extract_from_preference_map pastDeadlinePromptTitleLocalizedJa)
defaultPastDeadlinePromptTitleLocalizedNl=$(extract_from_preference_map pastDeadlinePromptTitleLocalizedNl)
defaultPastDeadlinePromptMessage=$(extract_from_preference_map pastDeadlinePromptMessage)
defaultPastDeadlinePromptMessageLocalizedEn=$(extract_from_preference_map pastDeadlinePromptMessageLocalizedEn)
defaultPastDeadlinePromptMessageLocalizedDe=$(extract_from_preference_map pastDeadlinePromptMessageLocalizedDe)
defaultPastDeadlinePromptMessageLocalizedFr=$(extract_from_preference_map pastDeadlinePromptMessageLocalizedFr)
defaultPastDeadlinePromptMessageLocalizedEs=$(extract_from_preference_map pastDeadlinePromptMessageLocalizedEs)
defaultPastDeadlinePromptMessageLocalizedPt=$(extract_from_preference_map pastDeadlinePromptMessageLocalizedPt)
defaultPastDeadlinePromptMessageLocalizedJa=$(extract_from_preference_map pastDeadlinePromptMessageLocalizedJa)
defaultPastDeadlinePromptMessageLocalizedNl=$(extract_from_preference_map pastDeadlinePromptMessageLocalizedNl)
defaultPastDeadlineForceTitle=$(extract_from_preference_map pastDeadlineForceTitle)
defaultPastDeadlineForceTitleLocalizedEn=$(extract_from_preference_map pastDeadlineForceTitleLocalizedEn)
defaultPastDeadlineForceTitleLocalizedDe=$(extract_from_preference_map pastDeadlineForceTitleLocalizedDe)
defaultPastDeadlineForceTitleLocalizedFr=$(extract_from_preference_map pastDeadlineForceTitleLocalizedFr)
defaultPastDeadlineForceTitleLocalizedEs=$(extract_from_preference_map pastDeadlineForceTitleLocalizedEs)
defaultPastDeadlineForceTitleLocalizedPt=$(extract_from_preference_map pastDeadlineForceTitleLocalizedPt)
defaultPastDeadlineForceTitleLocalizedJa=$(extract_from_preference_map pastDeadlineForceTitleLocalizedJa)
defaultPastDeadlineForceTitleLocalizedNl=$(extract_from_preference_map pastDeadlineForceTitleLocalizedNl)
defaultPastDeadlineForceMessage=$(extract_from_preference_map pastDeadlineForceMessage)
defaultPastDeadlineForceMessageLocalizedEn=$(extract_from_preference_map pastDeadlineForceMessageLocalizedEn)
defaultPastDeadlineForceMessageLocalizedDe=$(extract_from_preference_map pastDeadlineForceMessageLocalizedDe)
defaultPastDeadlineForceMessageLocalizedFr=$(extract_from_preference_map pastDeadlineForceMessageLocalizedFr)
defaultPastDeadlineForceMessageLocalizedEs=$(extract_from_preference_map pastDeadlineForceMessageLocalizedEs)
defaultPastDeadlineForceMessageLocalizedPt=$(extract_from_preference_map pastDeadlineForceMessageLocalizedPt)
defaultPastDeadlineForceMessageLocalizedJa=$(extract_from_preference_map pastDeadlineForceMessageLocalizedJa)
defaultPastDeadlineForceMessageLocalizedNl=$(extract_from_preference_map pastDeadlineForceMessageLocalizedNl)

# Resolve Info button-related defaults to concrete values,
# mirroring runtime behavior in reminderDialog.zsh
supportKB="$defaultSupportKB"
eval "resolvedInfobuttonaction=\"${defaultInfobuttonaction}\""
infobuttonaction="$resolvedInfobuttonaction"
eval "resolvedSupportKBURL=\"${defaultSupportKBURL}\""
resolvedInfobuttontext="$defaultInfobuttontext"

# ---------------------------------------------------------------------
# Process strings
# ---------------------------------------------------------------------
title_xml=$(process "$defaultTitle")
excessiveUptimeWarningMessage_xml=$(process "$defaultExcessiveUptimeWarningMessage")
excessiveUptimeWarningMessageLocalizedEn_xml=$(process "$defaultExcessiveUptimeWarningMessageLocalizedEn")
excessiveUptimeWarningMessageLocalizedDe_xml=$(process "$defaultExcessiveUptimeWarningMessageLocalizedDe")
excessiveUptimeWarningMessageLocalizedFr_xml=$(process "$defaultExcessiveUptimeWarningMessageLocalizedFr")
excessiveUptimeWarningMessageLocalizedEs_xml=$(process "$defaultExcessiveUptimeWarningMessageLocalizedEs")
excessiveUptimeWarningMessageLocalizedPt_xml=$(process "$defaultExcessiveUptimeWarningMessageLocalizedPt")
excessiveUptimeWarningMessageLocalizedJa_xml=$(process "$defaultExcessiveUptimeWarningMessageLocalizedJa")
excessiveUptimeWarningMessageLocalizedNl_xml=$(process "$defaultExcessiveUptimeWarningMessageLocalizedNl")
diskSpaceWarningMessage_xml=$(process "$defaultDiskSpaceWarningMessage")
diskSpaceWarningMessageLocalizedEn_xml=$(process "$defaultDiskSpaceWarningMessageLocalizedEn")
diskSpaceWarningMessageLocalizedDe_xml=$(process "$defaultDiskSpaceWarningMessageLocalizedDe")
diskSpaceWarningMessageLocalizedFr_xml=$(process "$defaultDiskSpaceWarningMessageLocalizedFr")
diskSpaceWarningMessageLocalizedEs_xml=$(process "$defaultDiskSpaceWarningMessageLocalizedEs")
diskSpaceWarningMessageLocalizedPt_xml=$(process "$defaultDiskSpaceWarningMessageLocalizedPt")
diskSpaceWarningMessageLocalizedJa_xml=$(process "$defaultDiskSpaceWarningMessageLocalizedJa")
diskSpaceWarningMessageLocalizedNl_xml=$(process "$defaultDiskSpaceWarningMessageLocalizedNl")
stagedUpdateMessage_xml=$(process "${defaultStagedUpdateMessage}")
stagedUpdateMessageLocalizedEn_xml=$(process "${defaultStagedUpdateMessageLocalizedEn}")
stagedUpdateMessageLocalizedDe_xml=$(process "${defaultStagedUpdateMessageLocalizedDe}")
stagedUpdateMessageLocalizedFr_xml=$(process "${defaultStagedUpdateMessageLocalizedFr}")
stagedUpdateMessageLocalizedEs_xml=$(process "${defaultStagedUpdateMessageLocalizedEs}")
stagedUpdateMessageLocalizedPt_xml=$(process "${defaultStagedUpdateMessageLocalizedPt}")
stagedUpdateMessageLocalizedJa_xml=$(process "${defaultStagedUpdateMessageLocalizedJa}")
stagedUpdateMessageLocalizedNl_xml=$(process "${defaultStagedUpdateMessageLocalizedNl}")
partiallyStagedUpdateMessage_xml=$(process "${defaultPartiallyStagedUpdateMessage}")
partiallyStagedUpdateMessageLocalizedEn_xml=$(process "${defaultPartiallyStagedUpdateMessageLocalizedEn}")
partiallyStagedUpdateMessageLocalizedDe_xml=$(process "${defaultPartiallyStagedUpdateMessageLocalizedDe}")
partiallyStagedUpdateMessageLocalizedFr_xml=$(process "${defaultPartiallyStagedUpdateMessageLocalizedFr}")
partiallyStagedUpdateMessageLocalizedEs_xml=$(process "${defaultPartiallyStagedUpdateMessageLocalizedEs}")
partiallyStagedUpdateMessageLocalizedPt_xml=$(process "${defaultPartiallyStagedUpdateMessageLocalizedPt}")
partiallyStagedUpdateMessageLocalizedJa_xml=$(process "${defaultPartiallyStagedUpdateMessageLocalizedJa}")
partiallyStagedUpdateMessageLocalizedNl_xml=$(process "${defaultPartiallyStagedUpdateMessageLocalizedNl}")
pendingDownloadMessage_xml=$(process "${defaultPendingDownloadMessage}")
pendingDownloadMessageLocalizedEn_xml=$(process "${defaultPendingDownloadMessageLocalizedEn}")
pendingDownloadMessageLocalizedDe_xml=$(process "${defaultPendingDownloadMessageLocalizedDe}")
pendingDownloadMessageLocalizedFr_xml=$(process "${defaultPendingDownloadMessageLocalizedFr}")
pendingDownloadMessageLocalizedEs_xml=$(process "${defaultPendingDownloadMessageLocalizedEs}")
pendingDownloadMessageLocalizedPt_xml=$(process "${defaultPendingDownloadMessageLocalizedPt}")
pendingDownloadMessageLocalizedJa_xml=$(process "${defaultPendingDownloadMessageLocalizedJa}")
pendingDownloadMessageLocalizedNl_xml=$(process "${defaultPendingDownloadMessageLocalizedNl}")
message_xml=$(process "$defaultMessage")
infobox_xml=$(process "$defaultInfobox")
helpmessage_xml=$(process "$defaultHelpmessage")
helpimage_xml=$(process "$defaultHelpimage")
button1text_xml=$(process "$defaultButton1text")
button2text_xml=$(process "$defaultButton2text")
titleLocalizedEn_xml=$(process "$defaultTitleLocalizedEn")
titleLocalizedDe_xml=$(process "$defaultTitleLocalizedDe")
titleLocalizedFr_xml=$(process "$defaultTitleLocalizedFr")
titleLocalizedEs_xml=$(process "$defaultTitleLocalizedEs")
titleLocalizedPt_xml=$(process "$defaultTitleLocalizedPt")
titleLocalizedJa_xml=$(process "$defaultTitleLocalizedJa")
titleLocalizedNl_xml=$(process "$defaultTitleLocalizedNl")
button1textLocalizedEn_xml=$(process "$defaultButton1textLocalizedEn")
button1textLocalizedDe_xml=$(process "$defaultButton1textLocalizedDe")
button1textLocalizedFr_xml=$(process "$defaultButton1textLocalizedFr")
button1textLocalizedEs_xml=$(process "$defaultButton1textLocalizedEs")
button1textLocalizedPt_xml=$(process "$defaultButton1textLocalizedPt")
button1textLocalizedJa_xml=$(process "$defaultButton1textLocalizedJa")
button1textLocalizedNl_xml=$(process "$defaultButton1textLocalizedNl")
button2textLocalizedEn_xml=$(process "$defaultButton2textLocalizedEn")
button2textLocalizedDe_xml=$(process "$defaultButton2textLocalizedDe")
button2textLocalizedFr_xml=$(process "$defaultButton2textLocalizedFr")
button2textLocalizedEs_xml=$(process "$defaultButton2textLocalizedEs")
button2textLocalizedPt_xml=$(process "$defaultButton2textLocalizedPt")
button2textLocalizedJa_xml=$(process "$defaultButton2textLocalizedJa")
button2textLocalizedNl_xml=$(process "$defaultButton2textLocalizedNl")
infobuttontextLocalizedEn_xml=$(process "$defaultInfobuttontextLocalizedEn")
infobuttontextLocalizedDe_xml=$(process "$defaultInfobuttontextLocalizedDe")
infobuttontextLocalizedFr_xml=$(process "$defaultInfobuttontextLocalizedFr")
infobuttontextLocalizedEs_xml=$(process "$defaultInfobuttontextLocalizedEs")
infobuttontextLocalizedPt_xml=$(process "$defaultInfobuttontextLocalizedPt")
infobuttontextLocalizedJa_xml=$(process "$defaultInfobuttontextLocalizedJa")
infobuttontextLocalizedNl_xml=$(process "$defaultInfobuttontextLocalizedNl")
messageLocalizedEn_xml=$(process "$defaultMessageLocalizedEn")
messageLocalizedDe_xml=$(process "$defaultMessageLocalizedDe")
messageLocalizedFr_xml=$(process "$defaultMessageLocalizedFr")
messageLocalizedEs_xml=$(process "$defaultMessageLocalizedEs")
messageLocalizedPt_xml=$(process "$defaultMessageLocalizedPt")
messageLocalizedJa_xml=$(process "$defaultMessageLocalizedJa")
messageLocalizedNl_xml=$(process "$defaultMessageLocalizedNl")
helpmessageLocalizedEn_xml=$(process "$defaultHelpmessageLocalizedEn")
helpmessageLocalizedDe_xml=$(process "$defaultHelpmessageLocalizedDe")
helpmessageLocalizedFr_xml=$(process "$defaultHelpmessageLocalizedFr")
helpmessageLocalizedEs_xml=$(process "$defaultHelpmessageLocalizedEs")
helpmessageLocalizedPt_xml=$(process "$defaultHelpmessageLocalizedPt")
helpmessageLocalizedJa_xml=$(process "$defaultHelpmessageLocalizedJa")
helpmessageLocalizedNl_xml=$(process "$defaultHelpmessageLocalizedNl")

# Info button pieces use resolved defaults (already evaluated)
infobuttontext_xml=$(process "$resolvedInfobuttontext")

overlayicon_xml=$(process "$defaultOverlayiconURL")
overlayiconDark_xml=$(process "$defaultOverlayiconURLdark")
acceptableAssertionApplicationNames_xml=$(process "$acceptableAssertionApplicationNames")
supportTeamName_xml=$(process "$defaultSupportTeamName")
supportTeamPhone_xml=$(process "$defaultSupportTeamPhone")
supportTeamEmail_xml=$(process "$defaultSupportTeamEmail")
supportTeamWebsite_xml=$(process "$defaultSupportTeamWebsite")
supportKB_xml=$(process "$defaultSupportKB")
supportAssistanceMessage_xml=$(process "$defaultSupportAssistanceMessage")
supportAssistanceMessageLocalizedEn_xml=$(process "$defaultSupportAssistanceMessageLocalizedEn")
supportAssistanceMessageLocalizedDe_xml=$(process "$defaultSupportAssistanceMessageLocalizedDe")
supportAssistanceMessageLocalizedFr_xml=$(process "$defaultSupportAssistanceMessageLocalizedFr")
supportAssistanceMessageLocalizedEs_xml=$(process "$defaultSupportAssistanceMessageLocalizedEs")
supportAssistanceMessageLocalizedPt_xml=$(process "$defaultSupportAssistanceMessageLocalizedPt")
supportAssistanceMessageLocalizedJa_xml=$(process "$defaultSupportAssistanceMessageLocalizedJa")
supportAssistanceMessageLocalizedNl_xml=$(process "$defaultSupportAssistanceMessageLocalizedNl")
relativeDeadlineToday_xml=$(process "$defaultRelativeDeadlineToday")
relativeDeadlineTodayLocalizedEn_xml=$(process "$defaultRelativeDeadlineTodayLocalizedEn")
relativeDeadlineTodayLocalizedDe_xml=$(process "$defaultRelativeDeadlineTodayLocalizedDe")
relativeDeadlineTodayLocalizedFr_xml=$(process "$defaultRelativeDeadlineTodayLocalizedFr")
relativeDeadlineTodayLocalizedEs_xml=$(process "$defaultRelativeDeadlineTodayLocalizedEs")
relativeDeadlineTodayLocalizedPt_xml=$(process "$defaultRelativeDeadlineTodayLocalizedPt")
relativeDeadlineTodayLocalizedJa_xml=$(process "$defaultRelativeDeadlineTodayLocalizedJa")
relativeDeadlineTodayLocalizedNl_xml=$(process "$defaultRelativeDeadlineTodayLocalizedNl")
relativeDeadlineTomorrow_xml=$(process "$defaultRelativeDeadlineTomorrow")
relativeDeadlineTomorrowLocalizedEn_xml=$(process "$defaultRelativeDeadlineTomorrowLocalizedEn")
relativeDeadlineTomorrowLocalizedDe_xml=$(process "$defaultRelativeDeadlineTomorrowLocalizedDe")
relativeDeadlineTomorrowLocalizedFr_xml=$(process "$defaultRelativeDeadlineTomorrowLocalizedFr")
relativeDeadlineTomorrowLocalizedEs_xml=$(process "$defaultRelativeDeadlineTomorrowLocalizedEs")
relativeDeadlineTomorrowLocalizedPt_xml=$(process "$defaultRelativeDeadlineTomorrowLocalizedPt")
relativeDeadlineTomorrowLocalizedJa_xml=$(process "$defaultRelativeDeadlineTomorrowLocalizedJa")
relativeDeadlineTomorrowLocalizedNl_xml=$(process "$defaultRelativeDeadlineTomorrowLocalizedNl")
updateWord_xml=$(process "$defaultUpdateWord")
updateWordLocalizedEn_xml=$(process "$defaultUpdateWordLocalizedEn")
updateWordLocalizedDe_xml=$(process "$defaultUpdateWordLocalizedDe")
updateWordLocalizedFr_xml=$(process "$defaultUpdateWordLocalizedFr")
updateWordLocalizedEs_xml=$(process "$defaultUpdateWordLocalizedEs")
updateWordLocalizedPt_xml=$(process "$defaultUpdateWordLocalizedPt")
updateWordLocalizedJa_xml=$(process "$defaultUpdateWordLocalizedJa")
updateWordLocalizedNl_xml=$(process "$defaultUpdateWordLocalizedNl")
upgradeWord_xml=$(process "$defaultUpgradeWord")
upgradeWordLocalizedEn_xml=$(process "$defaultUpgradeWordLocalizedEn")
upgradeWordLocalizedDe_xml=$(process "$defaultUpgradeWordLocalizedDe")
upgradeWordLocalizedFr_xml=$(process "$defaultUpgradeWordLocalizedFr")
upgradeWordLocalizedEs_xml=$(process "$defaultUpgradeWordLocalizedEs")
upgradeWordLocalizedPt_xml=$(process "$defaultUpgradeWordLocalizedPt")
upgradeWordLocalizedJa_xml=$(process "$defaultUpgradeWordLocalizedJa")
upgradeWordLocalizedNl_xml=$(process "$defaultUpgradeWordLocalizedNl")
softwareUpdateButtonTextUpdate_xml=$(process "$defaultSoftwareUpdateButtonTextUpdate")
softwareUpdateButtonTextUpdateLocalizedEn_xml=$(process "$defaultSoftwareUpdateButtonTextUpdateLocalizedEn")
softwareUpdateButtonTextUpdateLocalizedDe_xml=$(process "$defaultSoftwareUpdateButtonTextUpdateLocalizedDe")
softwareUpdateButtonTextUpdateLocalizedFr_xml=$(process "$defaultSoftwareUpdateButtonTextUpdateLocalizedFr")
softwareUpdateButtonTextUpdateLocalizedEs_xml=$(process "$defaultSoftwareUpdateButtonTextUpdateLocalizedEs")
softwareUpdateButtonTextUpdateLocalizedPt_xml=$(process "$defaultSoftwareUpdateButtonTextUpdateLocalizedPt")
softwareUpdateButtonTextUpdateLocalizedJa_xml=$(process "$defaultSoftwareUpdateButtonTextUpdateLocalizedJa")
softwareUpdateButtonTextUpdateLocalizedNl_xml=$(process "$defaultSoftwareUpdateButtonTextUpdateLocalizedNl")
softwareUpdateButtonTextUpgrade_xml=$(process "$defaultSoftwareUpdateButtonTextUpgrade")
softwareUpdateButtonTextUpgradeLocalizedEn_xml=$(process "$defaultSoftwareUpdateButtonTextUpgradeLocalizedEn")
softwareUpdateButtonTextUpgradeLocalizedDe_xml=$(process "$defaultSoftwareUpdateButtonTextUpgradeLocalizedDe")
softwareUpdateButtonTextUpgradeLocalizedFr_xml=$(process "$defaultSoftwareUpdateButtonTextUpgradeLocalizedFr")
softwareUpdateButtonTextUpgradeLocalizedEs_xml=$(process "$defaultSoftwareUpdateButtonTextUpgradeLocalizedEs")
softwareUpdateButtonTextUpgradeLocalizedPt_xml=$(process "$defaultSoftwareUpdateButtonTextUpgradeLocalizedPt")
softwareUpdateButtonTextUpgradeLocalizedJa_xml=$(process "$defaultSoftwareUpdateButtonTextUpgradeLocalizedJa")
softwareUpdateButtonTextUpgradeLocalizedNl_xml=$(process "$defaultSoftwareUpdateButtonTextUpgradeLocalizedNl")
restartNowButtonText_xml=$(process "$defaultRestartNowButtonText")
restartNowButtonTextLocalizedEn_xml=$(process "$defaultRestartNowButtonTextLocalizedEn")
restartNowButtonTextLocalizedDe_xml=$(process "$defaultRestartNowButtonTextLocalizedDe")
restartNowButtonTextLocalizedFr_xml=$(process "$defaultRestartNowButtonTextLocalizedFr")
restartNowButtonTextLocalizedEs_xml=$(process "$defaultRestartNowButtonTextLocalizedEs")
restartNowButtonTextLocalizedPt_xml=$(process "$defaultRestartNowButtonTextLocalizedPt")
restartNowButtonTextLocalizedJa_xml=$(process "$defaultRestartNowButtonTextLocalizedJa")
restartNowButtonTextLocalizedNl_xml=$(process "$defaultRestartNowButtonTextLocalizedNl")
infoboxLabelCurrent_xml=$(process "$defaultInfoboxLabelCurrent")
infoboxLabelCurrentLocalizedEn_xml=$(process "$defaultInfoboxLabelCurrentLocalizedEn")
infoboxLabelCurrentLocalizedDe_xml=$(process "$defaultInfoboxLabelCurrentLocalizedDe")
infoboxLabelCurrentLocalizedFr_xml=$(process "$defaultInfoboxLabelCurrentLocalizedFr")
infoboxLabelCurrentLocalizedEs_xml=$(process "$defaultInfoboxLabelCurrentLocalizedEs")
infoboxLabelCurrentLocalizedPt_xml=$(process "$defaultInfoboxLabelCurrentLocalizedPt")
infoboxLabelCurrentLocalizedJa_xml=$(process "$defaultInfoboxLabelCurrentLocalizedJa")
infoboxLabelCurrentLocalizedNl_xml=$(process "$defaultInfoboxLabelCurrentLocalizedNl")
infoboxLabelRequired_xml=$(process "$defaultInfoboxLabelRequired")
infoboxLabelRequiredLocalizedEn_xml=$(process "$defaultInfoboxLabelRequiredLocalizedEn")
infoboxLabelRequiredLocalizedDe_xml=$(process "$defaultInfoboxLabelRequiredLocalizedDe")
infoboxLabelRequiredLocalizedFr_xml=$(process "$defaultInfoboxLabelRequiredLocalizedFr")
infoboxLabelRequiredLocalizedEs_xml=$(process "$defaultInfoboxLabelRequiredLocalizedEs")
infoboxLabelRequiredLocalizedPt_xml=$(process "$defaultInfoboxLabelRequiredLocalizedPt")
infoboxLabelRequiredLocalizedJa_xml=$(process "$defaultInfoboxLabelRequiredLocalizedJa")
infoboxLabelRequiredLocalizedNl_xml=$(process "$defaultInfoboxLabelRequiredLocalizedNl")
infoboxLabelDeadline_xml=$(process "$defaultInfoboxLabelDeadline")
infoboxLabelDeadlineLocalizedEn_xml=$(process "$defaultInfoboxLabelDeadlineLocalizedEn")
infoboxLabelDeadlineLocalizedDe_xml=$(process "$defaultInfoboxLabelDeadlineLocalizedDe")
infoboxLabelDeadlineLocalizedFr_xml=$(process "$defaultInfoboxLabelDeadlineLocalizedFr")
infoboxLabelDeadlineLocalizedEs_xml=$(process "$defaultInfoboxLabelDeadlineLocalizedEs")
infoboxLabelDeadlineLocalizedPt_xml=$(process "$defaultInfoboxLabelDeadlineLocalizedPt")
infoboxLabelDeadlineLocalizedJa_xml=$(process "$defaultInfoboxLabelDeadlineLocalizedJa")
infoboxLabelDeadlineLocalizedNl_xml=$(process "$defaultInfoboxLabelDeadlineLocalizedNl")
infoboxLabelDaysRemaining_xml=$(process "$defaultInfoboxLabelDaysRemaining")
infoboxLabelDaysRemainingLocalizedEn_xml=$(process "$defaultInfoboxLabelDaysRemainingLocalizedEn")
infoboxLabelDaysRemainingLocalizedDe_xml=$(process "$defaultInfoboxLabelDaysRemainingLocalizedDe")
infoboxLabelDaysRemainingLocalizedFr_xml=$(process "$defaultInfoboxLabelDaysRemainingLocalizedFr")
infoboxLabelDaysRemainingLocalizedEs_xml=$(process "$defaultInfoboxLabelDaysRemainingLocalizedEs")
infoboxLabelDaysRemainingLocalizedPt_xml=$(process "$defaultInfoboxLabelDaysRemainingLocalizedPt")
infoboxLabelDaysRemainingLocalizedJa_xml=$(process "$defaultInfoboxLabelDaysRemainingLocalizedJa")
infoboxLabelDaysRemainingLocalizedNl_xml=$(process "$defaultInfoboxLabelDaysRemainingLocalizedNl")
infoboxLabelLastRestart_xml=$(process "$defaultInfoboxLabelLastRestart")
infoboxLabelLastRestartLocalizedEn_xml=$(process "$defaultInfoboxLabelLastRestartLocalizedEn")
infoboxLabelLastRestartLocalizedDe_xml=$(process "$defaultInfoboxLabelLastRestartLocalizedDe")
infoboxLabelLastRestartLocalizedFr_xml=$(process "$defaultInfoboxLabelLastRestartLocalizedFr")
infoboxLabelLastRestartLocalizedEs_xml=$(process "$defaultInfoboxLabelLastRestartLocalizedEs")
infoboxLabelLastRestartLocalizedPt_xml=$(process "$defaultInfoboxLabelLastRestartLocalizedPt")
infoboxLabelLastRestartLocalizedJa_xml=$(process "$defaultInfoboxLabelLastRestartLocalizedJa")
infoboxLabelLastRestartLocalizedNl_xml=$(process "$defaultInfoboxLabelLastRestartLocalizedNl")
infoboxLabelFreeDiskSpace_xml=$(process "$defaultInfoboxLabelFreeDiskSpace")
infoboxLabelFreeDiskSpaceLocalizedEn_xml=$(process "$defaultInfoboxLabelFreeDiskSpaceLocalizedEn")
infoboxLabelFreeDiskSpaceLocalizedDe_xml=$(process "$defaultInfoboxLabelFreeDiskSpaceLocalizedDe")
infoboxLabelFreeDiskSpaceLocalizedFr_xml=$(process "$defaultInfoboxLabelFreeDiskSpaceLocalizedFr")
infoboxLabelFreeDiskSpaceLocalizedEs_xml=$(process "$defaultInfoboxLabelFreeDiskSpaceLocalizedEs")
infoboxLabelFreeDiskSpaceLocalizedPt_xml=$(process "$defaultInfoboxLabelFreeDiskSpaceLocalizedPt")
infoboxLabelFreeDiskSpaceLocalizedJa_xml=$(process "$defaultInfoboxLabelFreeDiskSpaceLocalizedJa")
infoboxLabelFreeDiskSpaceLocalizedNl_xml=$(process "$defaultInfoboxLabelFreeDiskSpaceLocalizedNl")
deadlineEnforcementMessageAbsolute_xml=$(process "$defaultDeadlineEnforcementMessageAbsolute")
deadlineEnforcementMessageAbsoluteLocalizedEn_xml=$(process "$defaultDeadlineEnforcementMessageAbsoluteLocalizedEn")
deadlineEnforcementMessageAbsoluteLocalizedDe_xml=$(process "$defaultDeadlineEnforcementMessageAbsoluteLocalizedDe")
deadlineEnforcementMessageAbsoluteLocalizedFr_xml=$(process "$defaultDeadlineEnforcementMessageAbsoluteLocalizedFr")
deadlineEnforcementMessageAbsoluteLocalizedEs_xml=$(process "$defaultDeadlineEnforcementMessageAbsoluteLocalizedEs")
deadlineEnforcementMessageAbsoluteLocalizedPt_xml=$(process "$defaultDeadlineEnforcementMessageAbsoluteLocalizedPt")
deadlineEnforcementMessageAbsoluteLocalizedJa_xml=$(process "$defaultDeadlineEnforcementMessageAbsoluteLocalizedJa")
deadlineEnforcementMessageAbsoluteLocalizedNl_xml=$(process "$defaultDeadlineEnforcementMessageAbsoluteLocalizedNl")
deadlineEnforcementMessageRelative_xml=$(process "$defaultDeadlineEnforcementMessageRelative")
deadlineEnforcementMessageRelativeLocalizedEn_xml=$(process "$defaultDeadlineEnforcementMessageRelativeLocalizedEn")
deadlineEnforcementMessageRelativeLocalizedDe_xml=$(process "$defaultDeadlineEnforcementMessageRelativeLocalizedDe")
deadlineEnforcementMessageRelativeLocalizedFr_xml=$(process "$defaultDeadlineEnforcementMessageRelativeLocalizedFr")
deadlineEnforcementMessageRelativeLocalizedEs_xml=$(process "$defaultDeadlineEnforcementMessageRelativeLocalizedEs")
deadlineEnforcementMessageRelativeLocalizedPt_xml=$(process "$defaultDeadlineEnforcementMessageRelativeLocalizedPt")
deadlineEnforcementMessageRelativeLocalizedJa_xml=$(process "$defaultDeadlineEnforcementMessageRelativeLocalizedJa")
deadlineEnforcementMessageRelativeLocalizedNl_xml=$(process "$defaultDeadlineEnforcementMessageRelativeLocalizedNl")
pastDeadlinePromptTitle_xml=$(process "$defaultPastDeadlinePromptTitle")
pastDeadlinePromptTitleLocalizedEn_xml=$(process "$defaultPastDeadlinePromptTitleLocalizedEn")
pastDeadlinePromptTitleLocalizedDe_xml=$(process "$defaultPastDeadlinePromptTitleLocalizedDe")
pastDeadlinePromptTitleLocalizedFr_xml=$(process "$defaultPastDeadlinePromptTitleLocalizedFr")
pastDeadlinePromptTitleLocalizedEs_xml=$(process "$defaultPastDeadlinePromptTitleLocalizedEs")
pastDeadlinePromptTitleLocalizedPt_xml=$(process "$defaultPastDeadlinePromptTitleLocalizedPt")
pastDeadlinePromptTitleLocalizedJa_xml=$(process "$defaultPastDeadlinePromptTitleLocalizedJa")
pastDeadlinePromptTitleLocalizedNl_xml=$(process "$defaultPastDeadlinePromptTitleLocalizedNl")
pastDeadlinePromptMessage_xml=$(process "$defaultPastDeadlinePromptMessage")
pastDeadlinePromptMessageLocalizedEn_xml=$(process "$defaultPastDeadlinePromptMessageLocalizedEn")
pastDeadlinePromptMessageLocalizedDe_xml=$(process "$defaultPastDeadlinePromptMessageLocalizedDe")
pastDeadlinePromptMessageLocalizedFr_xml=$(process "$defaultPastDeadlinePromptMessageLocalizedFr")
pastDeadlinePromptMessageLocalizedEs_xml=$(process "$defaultPastDeadlinePromptMessageLocalizedEs")
pastDeadlinePromptMessageLocalizedPt_xml=$(process "$defaultPastDeadlinePromptMessageLocalizedPt")
pastDeadlinePromptMessageLocalizedJa_xml=$(process "$defaultPastDeadlinePromptMessageLocalizedJa")
pastDeadlinePromptMessageLocalizedNl_xml=$(process "$defaultPastDeadlinePromptMessageLocalizedNl")
pastDeadlineForceTitle_xml=$(process "$defaultPastDeadlineForceTitle")
pastDeadlineForceTitleLocalizedEn_xml=$(process "$defaultPastDeadlineForceTitleLocalizedEn")
pastDeadlineForceTitleLocalizedDe_xml=$(process "$defaultPastDeadlineForceTitleLocalizedDe")
pastDeadlineForceTitleLocalizedFr_xml=$(process "$defaultPastDeadlineForceTitleLocalizedFr")
pastDeadlineForceTitleLocalizedEs_xml=$(process "$defaultPastDeadlineForceTitleLocalizedEs")
pastDeadlineForceTitleLocalizedPt_xml=$(process "$defaultPastDeadlineForceTitleLocalizedPt")
pastDeadlineForceTitleLocalizedJa_xml=$(process "$defaultPastDeadlineForceTitleLocalizedJa")
pastDeadlineForceTitleLocalizedNl_xml=$(process "$defaultPastDeadlineForceTitleLocalizedNl")
pastDeadlineForceMessage_xml=$(process "$defaultPastDeadlineForceMessage")
pastDeadlineForceMessageLocalizedEn_xml=$(process "$defaultPastDeadlineForceMessageLocalizedEn")
pastDeadlineForceMessageLocalizedDe_xml=$(process "$defaultPastDeadlineForceMessageLocalizedDe")
pastDeadlineForceMessageLocalizedFr_xml=$(process "$defaultPastDeadlineForceMessageLocalizedFr")
pastDeadlineForceMessageLocalizedEs_xml=$(process "$defaultPastDeadlineForceMessageLocalizedEs")
pastDeadlineForceMessageLocalizedPt_xml=$(process "$defaultPastDeadlineForceMessageLocalizedPt")
pastDeadlineForceMessageLocalizedJa_xml=$(process "$defaultPastDeadlineForceMessageLocalizedJa")
pastDeadlineForceMessageLocalizedNl_xml=$(process "$defaultPastDeadlineForceMessageLocalizedNl")

infobuttonaction_xml=$(printf "%s" "$resolvedInfobuttonaction" | xml_escape)
supportKBURL_xml=$(printf "%s" "$resolvedSupportKBURL" | xml_escape)

scriptLog_xml=$(echo "$scriptLog" | xml_escape)
pastDeadlineRestartBehavior_xml=$(echo "$pastDeadlineRestartBehavior" | xml_escape)
dateFormat_xml=$(echo "$dateFormatDeadlineHumanReadable" | xml_escape)
languageOverride_xml=$(echo "$languageOverride" | xml_escape)

# ─────────────────────────────────────────────────────────────
# Generate plist
# ─────────────────────────────────────────────────────────────
cat > "$OUTPUT_PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>

    <!-- Preferences Domain: ${reverseDomainNameNotation}.${organizationScriptName} -->
    <!-- Version: ${scriptVersion} -->
    <!-- Generated on: ${datestamp} -->

    <!-- Logging -->
    <key>ScriptLog</key>
    <string>${scriptLog_xml}</string>

    <!-- Reminder timing -->
    <key>DaysBeforeDeadlineDisplayReminder</key>
    <integer>${daysBeforeDeadlineDisplayReminder}</integer>
    <key>DaysBeforeDeadlineBlurscreen</key>
    <integer>${daysBeforeDeadlineBlurscreen}</integer>
    <key>DaysBeforeDeadlineHidingButton2</key>
    <integer>${daysBeforeDeadlineHidingButton2}</integer>
    <key>DaysOfExcessiveUptimeWarning</key>
    <integer>${daysOfExcessiveUptimeWarning}</integer>
    <!-- Past-deadline restart behavior:
         Off | Prompt | Force -->
    <key>PastDeadlineRestartBehavior</key>
    <string>${pastDeadlineRestartBehavior_xml}</string>
    <key>DaysPastDeadlineRestartWorkflow</key>
    <integer>${daysPastDeadlineRestartWorkflow}</integer>
    <key>MeetingDelay</key>
    <integer>${meetingDelay}</integer>
    <key>AcceptableAssertionApplicationNames</key>
    <string>${acceptableAssertionApplicationNames_xml}</string>
    <key>MinimumDiskFreePercentage</key>
    <integer>${minimumDiskFreePercentage}</integer>

    <!-- Branding -->
    <key>OrganizationOverlayIconURL</key>
    <string>${overlayicon_xml}</string>
    <key>OrganizationOverlayIconURLdark</key>
    <string>${overlayiconDark_xml}</string>
    <key>SwapOverlayAndLogo</key>
    ${swapOverlayAndLogo_xml}
    <key>DateFormatDeadlineHumanReadable</key>
    <string>${dateFormat_xml}</string>

    <!-- Support block -->
    <key>SupportTeamName</key>
    <string>${supportTeamName_xml}</string>
    <key>SupportTeamPhone</key>
    <string>${supportTeamPhone_xml}</string>
    <key>SupportTeamEmail</key>
    <string>${supportTeamEmail_xml}</string>
    <key>SupportTeamWebsite</key>
    <string>${supportTeamWebsite_xml}</string>
    <key>SupportKB</key>
    <string>${supportKB_xml}</string>
    <key>InfoButtonAction</key>
    <string>${infobuttonaction_xml}</string>
    <key>SupportKBURL</key>
    <string>${supportKBURL_xml}</string>
    <key>SupportAssistanceMessage</key>
    <string>${supportAssistanceMessage_xml}</string>
    <key>SupportAssistanceMessageLocalized_en</key>
    <string>${supportAssistanceMessageLocalizedEn_xml}</string>
    <key>SupportAssistanceMessageLocalized_de</key>
    <string>${supportAssistanceMessageLocalizedDe_xml}</string>
    <key>SupportAssistanceMessageLocalized_fr</key>
    <string>${supportAssistanceMessageLocalizedFr_xml}</string>
    <key>SupportAssistanceMessageLocalized_es</key>
    <string>${supportAssistanceMessageLocalizedEs_xml}</string>
    <key>SupportAssistanceMessageLocalized_pt</key>
    <string>${supportAssistanceMessageLocalizedPt_xml}</string>
    <key>SupportAssistanceMessageLocalized_ja</key>
    <string>${supportAssistanceMessageLocalizedJa_xml}</string>
    <key>SupportAssistanceMessageLocalized_nl</key>
    <string>${supportAssistanceMessageLocalizedNl_xml}</string>

    <!-- Localization -->
    <key>LanguageOverride</key>
    <string>${languageOverride_xml}</string>

    <!-- Dialog text -->
    <key>Title</key>
    <string>${title_xml}</string>
    <key>TitleLocalized_en</key>
    <string>${titleLocalizedEn_xml}</string>
    <key>TitleLocalized_de</key>
    <string>${titleLocalizedDe_xml}</string>
    <key>TitleLocalized_fr</key>
    <string>${titleLocalizedFr_xml}</string>
    <key>TitleLocalized_es</key>
    <string>${titleLocalizedEs_xml}</string>
    <key>TitleLocalized_pt</key>
    <string>${titleLocalizedPt_xml}</string>
    <key>TitleLocalized_ja</key>
    <string>${titleLocalizedJa_xml}</string>
    <key>TitleLocalized_nl</key>
    <string>${titleLocalizedNl_xml}</string>
    <key>Button1Text</key>
    <string>${button1text_xml}</string>
    <key>Button1TextLocalized_en</key>
    <string>${button1textLocalizedEn_xml}</string>
    <key>Button1TextLocalized_de</key>
    <string>${button1textLocalizedDe_xml}</string>
    <key>Button1TextLocalized_fr</key>
    <string>${button1textLocalizedFr_xml}</string>
    <key>Button1TextLocalized_es</key>
    <string>${button1textLocalizedEs_xml}</string>
    <key>Button1TextLocalized_pt</key>
    <string>${button1textLocalizedPt_xml}</string>
    <key>Button1TextLocalized_ja</key>
    <string>${button1textLocalizedJa_xml}</string>
    <key>Button1TextLocalized_nl</key>
    <string>${button1textLocalizedNl_xml}</string>
    <key>Button2Text</key>
    <string>${button2text_xml}</string>
    <key>Button2TextLocalized_en</key>
    <string>${button2textLocalizedEn_xml}</string>
    <key>Button2TextLocalized_de</key>
    <string>${button2textLocalizedDe_xml}</string>
    <key>Button2TextLocalized_fr</key>
    <string>${button2textLocalizedFr_xml}</string>
    <key>Button2TextLocalized_es</key>
    <string>${button2textLocalizedEs_xml}</string>
    <key>Button2TextLocalized_pt</key>
    <string>${button2textLocalizedPt_xml}</string>
    <key>Button2TextLocalized_ja</key>
    <string>${button2textLocalizedJa_xml}</string>
    <key>Button2TextLocalized_nl</key>
    <string>${button2textLocalizedNl_xml}</string>
    <key>InfoButtonText</key>
    <string>${infobuttontext_xml}</string>
    <key>InfoButtonTextLocalized_en</key>
    <string>${infobuttontextLocalizedEn_xml}</string>
    <key>InfoButtonTextLocalized_de</key>
    <string>${infobuttontextLocalizedDe_xml}</string>
    <key>InfoButtonTextLocalized_fr</key>
    <string>${infobuttontextLocalizedFr_xml}</string>
    <key>InfoButtonTextLocalized_es</key>
    <string>${infobuttontextLocalizedEs_xml}</string>
    <key>InfoButtonTextLocalized_pt</key>
    <string>${infobuttontextLocalizedPt_xml}</string>
    <key>InfoButtonTextLocalized_ja</key>
    <string>${infobuttontextLocalizedJa_xml}</string>
    <key>InfoButtonTextLocalized_nl</key>
    <string>${infobuttontextLocalizedNl_xml}</string>
    <key>ExcessiveUptimeWarningMessage</key>
    <string>${excessiveUptimeWarningMessage_xml}</string>
    <key>ExcessiveUptimeWarningMessageLocalized_en</key>
    <string>${excessiveUptimeWarningMessageLocalizedEn_xml}</string>
    <key>ExcessiveUptimeWarningMessageLocalized_de</key>
    <string>${excessiveUptimeWarningMessageLocalizedDe_xml}</string>
    <key>ExcessiveUptimeWarningMessageLocalized_fr</key>
    <string>${excessiveUptimeWarningMessageLocalizedFr_xml}</string>
    <key>ExcessiveUptimeWarningMessageLocalized_es</key>
    <string>${excessiveUptimeWarningMessageLocalizedEs_xml}</string>
    <key>ExcessiveUptimeWarningMessageLocalized_pt</key>
    <string>${excessiveUptimeWarningMessageLocalizedPt_xml}</string>
    <key>ExcessiveUptimeWarningMessageLocalized_ja</key>
    <string>${excessiveUptimeWarningMessageLocalizedJa_xml}</string>
    <key>ExcessiveUptimeWarningMessageLocalized_nl</key>
    <string>${excessiveUptimeWarningMessageLocalizedNl_xml}</string>
    <key>DiskSpaceWarningMessage</key>
    <string>${diskSpaceWarningMessage_xml}</string>
    <key>DiskSpaceWarningMessageLocalized_en</key>
    <string>${diskSpaceWarningMessageLocalizedEn_xml}</string>
    <key>DiskSpaceWarningMessageLocalized_de</key>
    <string>${diskSpaceWarningMessageLocalizedDe_xml}</string>
    <key>DiskSpaceWarningMessageLocalized_fr</key>
    <string>${diskSpaceWarningMessageLocalizedFr_xml}</string>
    <key>DiskSpaceWarningMessageLocalized_es</key>
    <string>${diskSpaceWarningMessageLocalizedEs_xml}</string>
    <key>DiskSpaceWarningMessageLocalized_pt</key>
    <string>${diskSpaceWarningMessageLocalizedPt_xml}</string>
    <key>DiskSpaceWarningMessageLocalized_ja</key>
    <string>${diskSpaceWarningMessageLocalizedJa_xml}</string>
    <key>DiskSpaceWarningMessageLocalized_nl</key>
    <string>${diskSpaceWarningMessageLocalizedNl_xml}</string>
    <key>StagedUpdateMessage</key>
    <string>${stagedUpdateMessage_xml}</string>
    <key>StagedUpdateMessageLocalized_en</key>
    <string>${stagedUpdateMessageLocalizedEn_xml}</string>
    <key>StagedUpdateMessageLocalized_de</key>
    <string>${stagedUpdateMessageLocalizedDe_xml}</string>
    <key>StagedUpdateMessageLocalized_fr</key>
    <string>${stagedUpdateMessageLocalizedFr_xml}</string>
    <key>StagedUpdateMessageLocalized_es</key>
    <string>${stagedUpdateMessageLocalizedEs_xml}</string>
    <key>StagedUpdateMessageLocalized_pt</key>
    <string>${stagedUpdateMessageLocalizedPt_xml}</string>
    <key>StagedUpdateMessageLocalized_ja</key>
    <string>${stagedUpdateMessageLocalizedJa_xml}</string>
    <key>StagedUpdateMessageLocalized_nl</key>
    <string>${stagedUpdateMessageLocalizedNl_xml}</string>
    <key>PartiallyStagedUpdateMessage</key>
    <string>${partiallyStagedUpdateMessage_xml}</string>
    <key>PartiallyStagedUpdateMessageLocalized_en</key>
    <string>${partiallyStagedUpdateMessageLocalizedEn_xml}</string>
    <key>PartiallyStagedUpdateMessageLocalized_de</key>
    <string>${partiallyStagedUpdateMessageLocalizedDe_xml}</string>
    <key>PartiallyStagedUpdateMessageLocalized_fr</key>
    <string>${partiallyStagedUpdateMessageLocalizedFr_xml}</string>
    <key>PartiallyStagedUpdateMessageLocalized_es</key>
    <string>${partiallyStagedUpdateMessageLocalizedEs_xml}</string>
    <key>PartiallyStagedUpdateMessageLocalized_pt</key>
    <string>${partiallyStagedUpdateMessageLocalizedPt_xml}</string>
    <key>PartiallyStagedUpdateMessageLocalized_ja</key>
    <string>${partiallyStagedUpdateMessageLocalizedJa_xml}</string>
    <key>PartiallyStagedUpdateMessageLocalized_nl</key>
    <string>${partiallyStagedUpdateMessageLocalizedNl_xml}</string>
    <key>PendingDownloadMessage</key>
    <string>${pendingDownloadMessage_xml}</string>
    <key>PendingDownloadMessageLocalized_en</key>
    <string>${pendingDownloadMessageLocalizedEn_xml}</string>
    <key>PendingDownloadMessageLocalized_de</key>
    <string>${pendingDownloadMessageLocalizedDe_xml}</string>
    <key>PendingDownloadMessageLocalized_fr</key>
    <string>${pendingDownloadMessageLocalizedFr_xml}</string>
    <key>PendingDownloadMessageLocalized_es</key>
    <string>${pendingDownloadMessageLocalizedEs_xml}</string>
    <key>PendingDownloadMessageLocalized_pt</key>
    <string>${pendingDownloadMessageLocalizedPt_xml}</string>
    <key>PendingDownloadMessageLocalized_ja</key>
    <string>${pendingDownloadMessageLocalizedJa_xml}</string>
    <key>PendingDownloadMessageLocalized_nl</key>
    <string>${pendingDownloadMessageLocalizedNl_xml}</string>
    <key>HideStagedUpdateInfo</key>
    ${hideStagedInfo_xml}
    <key>RelativeDeadlineToday</key>
    <string>${relativeDeadlineToday_xml}</string>
    <key>RelativeDeadlineTodayLocalized_en</key>
    <string>${relativeDeadlineTodayLocalizedEn_xml}</string>
    <key>RelativeDeadlineTodayLocalized_de</key>
    <string>${relativeDeadlineTodayLocalizedDe_xml}</string>
    <key>RelativeDeadlineTodayLocalized_fr</key>
    <string>${relativeDeadlineTodayLocalizedFr_xml}</string>
    <key>RelativeDeadlineTodayLocalized_es</key>
    <string>${relativeDeadlineTodayLocalizedEs_xml}</string>
    <key>RelativeDeadlineTodayLocalized_pt</key>
    <string>${relativeDeadlineTodayLocalizedPt_xml}</string>
    <key>RelativeDeadlineTodayLocalized_ja</key>
    <string>${relativeDeadlineTodayLocalizedJa_xml}</string>
    <key>RelativeDeadlineTodayLocalized_nl</key>
    <string>${relativeDeadlineTodayLocalizedNl_xml}</string>
    <key>RelativeDeadlineTomorrow</key>
    <string>${relativeDeadlineTomorrow_xml}</string>
    <key>RelativeDeadlineTomorrowLocalized_en</key>
    <string>${relativeDeadlineTomorrowLocalizedEn_xml}</string>
    <key>RelativeDeadlineTomorrowLocalized_de</key>
    <string>${relativeDeadlineTomorrowLocalizedDe_xml}</string>
    <key>RelativeDeadlineTomorrowLocalized_fr</key>
    <string>${relativeDeadlineTomorrowLocalizedFr_xml}</string>
    <key>RelativeDeadlineTomorrowLocalized_es</key>
    <string>${relativeDeadlineTomorrowLocalizedEs_xml}</string>
    <key>RelativeDeadlineTomorrowLocalized_pt</key>
    <string>${relativeDeadlineTomorrowLocalizedPt_xml}</string>
    <key>RelativeDeadlineTomorrowLocalized_ja</key>
    <string>${relativeDeadlineTomorrowLocalizedJa_xml}</string>
    <key>RelativeDeadlineTomorrowLocalized_nl</key>
    <string>${relativeDeadlineTomorrowLocalizedNl_xml}</string>
    <key>UpdateWord</key>
    <string>${updateWord_xml}</string>
    <key>UpdateWordLocalized_en</key>
    <string>${updateWordLocalizedEn_xml}</string>
    <key>UpdateWordLocalized_de</key>
    <string>${updateWordLocalizedDe_xml}</string>
    <key>UpdateWordLocalized_fr</key>
    <string>${updateWordLocalizedFr_xml}</string>
    <key>UpdateWordLocalized_es</key>
    <string>${updateWordLocalizedEs_xml}</string>
    <key>UpdateWordLocalized_pt</key>
    <string>${updateWordLocalizedPt_xml}</string>
    <key>UpdateWordLocalized_ja</key>
    <string>${updateWordLocalizedJa_xml}</string>
    <key>UpdateWordLocalized_nl</key>
    <string>${updateWordLocalizedNl_xml}</string>
    <key>UpgradeWord</key>
    <string>${upgradeWord_xml}</string>
    <key>UpgradeWordLocalized_en</key>
    <string>${upgradeWordLocalizedEn_xml}</string>
    <key>UpgradeWordLocalized_de</key>
    <string>${upgradeWordLocalizedDe_xml}</string>
    <key>UpgradeWordLocalized_fr</key>
    <string>${upgradeWordLocalizedFr_xml}</string>
    <key>UpgradeWordLocalized_es</key>
    <string>${upgradeWordLocalizedEs_xml}</string>
    <key>UpgradeWordLocalized_pt</key>
    <string>${upgradeWordLocalizedPt_xml}</string>
    <key>UpgradeWordLocalized_ja</key>
    <string>${upgradeWordLocalizedJa_xml}</string>
    <key>UpgradeWordLocalized_nl</key>
    <string>${upgradeWordLocalizedNl_xml}</string>
    <key>SoftwareUpdateButtonTextUpdate</key>
    <string>${softwareUpdateButtonTextUpdate_xml}</string>
    <key>SoftwareUpdateButtonTextUpdateLocalized_en</key>
    <string>${softwareUpdateButtonTextUpdateLocalizedEn_xml}</string>
    <key>SoftwareUpdateButtonTextUpdateLocalized_de</key>
    <string>${softwareUpdateButtonTextUpdateLocalizedDe_xml}</string>
    <key>SoftwareUpdateButtonTextUpdateLocalized_fr</key>
    <string>${softwareUpdateButtonTextUpdateLocalizedFr_xml}</string>
    <key>SoftwareUpdateButtonTextUpdateLocalized_es</key>
    <string>${softwareUpdateButtonTextUpdateLocalizedEs_xml}</string>
    <key>SoftwareUpdateButtonTextUpdateLocalized_pt</key>
    <string>${softwareUpdateButtonTextUpdateLocalizedPt_xml}</string>
    <key>SoftwareUpdateButtonTextUpdateLocalized_ja</key>
    <string>${softwareUpdateButtonTextUpdateLocalizedJa_xml}</string>
    <key>SoftwareUpdateButtonTextUpdateLocalized_nl</key>
    <string>${softwareUpdateButtonTextUpdateLocalizedNl_xml}</string>
    <key>SoftwareUpdateButtonTextUpgrade</key>
    <string>${softwareUpdateButtonTextUpgrade_xml}</string>
    <key>SoftwareUpdateButtonTextUpgradeLocalized_en</key>
    <string>${softwareUpdateButtonTextUpgradeLocalizedEn_xml}</string>
    <key>SoftwareUpdateButtonTextUpgradeLocalized_de</key>
    <string>${softwareUpdateButtonTextUpgradeLocalizedDe_xml}</string>
    <key>SoftwareUpdateButtonTextUpgradeLocalized_fr</key>
    <string>${softwareUpdateButtonTextUpgradeLocalizedFr_xml}</string>
    <key>SoftwareUpdateButtonTextUpgradeLocalized_es</key>
    <string>${softwareUpdateButtonTextUpgradeLocalizedEs_xml}</string>
    <key>SoftwareUpdateButtonTextUpgradeLocalized_pt</key>
    <string>${softwareUpdateButtonTextUpgradeLocalizedPt_xml}</string>
    <key>SoftwareUpdateButtonTextUpgradeLocalized_ja</key>
    <string>${softwareUpdateButtonTextUpgradeLocalizedJa_xml}</string>
    <key>SoftwareUpdateButtonTextUpgradeLocalized_nl</key>
    <string>${softwareUpdateButtonTextUpgradeLocalizedNl_xml}</string>
    <key>RestartNowButtonText</key>
    <string>${restartNowButtonText_xml}</string>
    <key>RestartNowButtonTextLocalized_en</key>
    <string>${restartNowButtonTextLocalizedEn_xml}</string>
    <key>RestartNowButtonTextLocalized_de</key>
    <string>${restartNowButtonTextLocalizedDe_xml}</string>
    <key>RestartNowButtonTextLocalized_fr</key>
    <string>${restartNowButtonTextLocalizedFr_xml}</string>
    <key>RestartNowButtonTextLocalized_es</key>
    <string>${restartNowButtonTextLocalizedEs_xml}</string>
    <key>RestartNowButtonTextLocalized_pt</key>
    <string>${restartNowButtonTextLocalizedPt_xml}</string>
    <key>RestartNowButtonTextLocalized_ja</key>
    <string>${restartNowButtonTextLocalizedJa_xml}</string>
    <key>RestartNowButtonTextLocalized_nl</key>
    <string>${restartNowButtonTextLocalizedNl_xml}</string>
    <key>InfoboxLabelCurrent</key>
    <string>${infoboxLabelCurrent_xml}</string>
    <key>InfoboxLabelCurrentLocalized_en</key>
    <string>${infoboxLabelCurrentLocalizedEn_xml}</string>
    <key>InfoboxLabelCurrentLocalized_de</key>
    <string>${infoboxLabelCurrentLocalizedDe_xml}</string>
    <key>InfoboxLabelCurrentLocalized_fr</key>
    <string>${infoboxLabelCurrentLocalizedFr_xml}</string>
    <key>InfoboxLabelCurrentLocalized_es</key>
    <string>${infoboxLabelCurrentLocalizedEs_xml}</string>
    <key>InfoboxLabelCurrentLocalized_pt</key>
    <string>${infoboxLabelCurrentLocalizedPt_xml}</string>
    <key>InfoboxLabelCurrentLocalized_ja</key>
    <string>${infoboxLabelCurrentLocalizedJa_xml}</string>
    <key>InfoboxLabelCurrentLocalized_nl</key>
    <string>${infoboxLabelCurrentLocalizedNl_xml}</string>
    <key>InfoboxLabelRequired</key>
    <string>${infoboxLabelRequired_xml}</string>
    <key>InfoboxLabelRequiredLocalized_en</key>
    <string>${infoboxLabelRequiredLocalizedEn_xml}</string>
    <key>InfoboxLabelRequiredLocalized_de</key>
    <string>${infoboxLabelRequiredLocalizedDe_xml}</string>
    <key>InfoboxLabelRequiredLocalized_fr</key>
    <string>${infoboxLabelRequiredLocalizedFr_xml}</string>
    <key>InfoboxLabelRequiredLocalized_es</key>
    <string>${infoboxLabelRequiredLocalizedEs_xml}</string>
    <key>InfoboxLabelRequiredLocalized_pt</key>
    <string>${infoboxLabelRequiredLocalizedPt_xml}</string>
    <key>InfoboxLabelRequiredLocalized_ja</key>
    <string>${infoboxLabelRequiredLocalizedJa_xml}</string>
    <key>InfoboxLabelRequiredLocalized_nl</key>
    <string>${infoboxLabelRequiredLocalizedNl_xml}</string>
    <key>InfoboxLabelDeadline</key>
    <string>${infoboxLabelDeadline_xml}</string>
    <key>InfoboxLabelDeadlineLocalized_en</key>
    <string>${infoboxLabelDeadlineLocalizedEn_xml}</string>
    <key>InfoboxLabelDeadlineLocalized_de</key>
    <string>${infoboxLabelDeadlineLocalizedDe_xml}</string>
    <key>InfoboxLabelDeadlineLocalized_fr</key>
    <string>${infoboxLabelDeadlineLocalizedFr_xml}</string>
    <key>InfoboxLabelDeadlineLocalized_es</key>
    <string>${infoboxLabelDeadlineLocalizedEs_xml}</string>
    <key>InfoboxLabelDeadlineLocalized_pt</key>
    <string>${infoboxLabelDeadlineLocalizedPt_xml}</string>
    <key>InfoboxLabelDeadlineLocalized_ja</key>
    <string>${infoboxLabelDeadlineLocalizedJa_xml}</string>
    <key>InfoboxLabelDeadlineLocalized_nl</key>
    <string>${infoboxLabelDeadlineLocalizedNl_xml}</string>
    <key>InfoboxLabelDaysRemaining</key>
    <string>${infoboxLabelDaysRemaining_xml}</string>
    <key>InfoboxLabelDaysRemainingLocalized_en</key>
    <string>${infoboxLabelDaysRemainingLocalizedEn_xml}</string>
    <key>InfoboxLabelDaysRemainingLocalized_de</key>
    <string>${infoboxLabelDaysRemainingLocalizedDe_xml}</string>
    <key>InfoboxLabelDaysRemainingLocalized_fr</key>
    <string>${infoboxLabelDaysRemainingLocalizedFr_xml}</string>
    <key>InfoboxLabelDaysRemainingLocalized_es</key>
    <string>${infoboxLabelDaysRemainingLocalizedEs_xml}</string>
    <key>InfoboxLabelDaysRemainingLocalized_pt</key>
    <string>${infoboxLabelDaysRemainingLocalizedPt_xml}</string>
    <key>InfoboxLabelDaysRemainingLocalized_ja</key>
    <string>${infoboxLabelDaysRemainingLocalizedJa_xml}</string>
    <key>InfoboxLabelDaysRemainingLocalized_nl</key>
    <string>${infoboxLabelDaysRemainingLocalizedNl_xml}</string>
    <key>InfoboxLabelLastRestart</key>
    <string>${infoboxLabelLastRestart_xml}</string>
    <key>InfoboxLabelLastRestartLocalized_en</key>
    <string>${infoboxLabelLastRestartLocalizedEn_xml}</string>
    <key>InfoboxLabelLastRestartLocalized_de</key>
    <string>${infoboxLabelLastRestartLocalizedDe_xml}</string>
    <key>InfoboxLabelLastRestartLocalized_fr</key>
    <string>${infoboxLabelLastRestartLocalizedFr_xml}</string>
    <key>InfoboxLabelLastRestartLocalized_es</key>
    <string>${infoboxLabelLastRestartLocalizedEs_xml}</string>
    <key>InfoboxLabelLastRestartLocalized_pt</key>
    <string>${infoboxLabelLastRestartLocalizedPt_xml}</string>
    <key>InfoboxLabelLastRestartLocalized_ja</key>
    <string>${infoboxLabelLastRestartLocalizedJa_xml}</string>
    <key>InfoboxLabelLastRestartLocalized_nl</key>
    <string>${infoboxLabelLastRestartLocalizedNl_xml}</string>
    <key>InfoboxLabelFreeDiskSpace</key>
    <string>${infoboxLabelFreeDiskSpace_xml}</string>
    <key>InfoboxLabelFreeDiskSpaceLocalized_en</key>
    <string>${infoboxLabelFreeDiskSpaceLocalizedEn_xml}</string>
    <key>InfoboxLabelFreeDiskSpaceLocalized_de</key>
    <string>${infoboxLabelFreeDiskSpaceLocalizedDe_xml}</string>
    <key>InfoboxLabelFreeDiskSpaceLocalized_fr</key>
    <string>${infoboxLabelFreeDiskSpaceLocalizedFr_xml}</string>
    <key>InfoboxLabelFreeDiskSpaceLocalized_es</key>
    <string>${infoboxLabelFreeDiskSpaceLocalizedEs_xml}</string>
    <key>InfoboxLabelFreeDiskSpaceLocalized_pt</key>
    <string>${infoboxLabelFreeDiskSpaceLocalizedPt_xml}</string>
    <key>InfoboxLabelFreeDiskSpaceLocalized_ja</key>
    <string>${infoboxLabelFreeDiskSpaceLocalizedJa_xml}</string>
    <key>InfoboxLabelFreeDiskSpaceLocalized_nl</key>
    <string>${infoboxLabelFreeDiskSpaceLocalizedNl_xml}</string>
    <key>DeadlineEnforcementMessageAbsolute</key>
    <string>${deadlineEnforcementMessageAbsolute_xml}</string>
    <key>DeadlineEnforcementMessageAbsoluteLocalized_en</key>
    <string>${deadlineEnforcementMessageAbsoluteLocalizedEn_xml}</string>
    <key>DeadlineEnforcementMessageAbsoluteLocalized_de</key>
    <string>${deadlineEnforcementMessageAbsoluteLocalizedDe_xml}</string>
    <key>DeadlineEnforcementMessageAbsoluteLocalized_fr</key>
    <string>${deadlineEnforcementMessageAbsoluteLocalizedFr_xml}</string>
    <key>DeadlineEnforcementMessageAbsoluteLocalized_es</key>
    <string>${deadlineEnforcementMessageAbsoluteLocalizedEs_xml}</string>
    <key>DeadlineEnforcementMessageAbsoluteLocalized_pt</key>
    <string>${deadlineEnforcementMessageAbsoluteLocalizedPt_xml}</string>
    <key>DeadlineEnforcementMessageAbsoluteLocalized_ja</key>
    <string>${deadlineEnforcementMessageAbsoluteLocalizedJa_xml}</string>
    <key>DeadlineEnforcementMessageAbsoluteLocalized_nl</key>
    <string>${deadlineEnforcementMessageAbsoluteLocalizedNl_xml}</string>
    <key>DeadlineEnforcementMessageRelative</key>
    <string>${deadlineEnforcementMessageRelative_xml}</string>
    <key>DeadlineEnforcementMessageRelativeLocalized_en</key>
    <string>${deadlineEnforcementMessageRelativeLocalizedEn_xml}</string>
    <key>DeadlineEnforcementMessageRelativeLocalized_de</key>
    <string>${deadlineEnforcementMessageRelativeLocalizedDe_xml}</string>
    <key>DeadlineEnforcementMessageRelativeLocalized_fr</key>
    <string>${deadlineEnforcementMessageRelativeLocalizedFr_xml}</string>
    <key>DeadlineEnforcementMessageRelativeLocalized_es</key>
    <string>${deadlineEnforcementMessageRelativeLocalizedEs_xml}</string>
    <key>DeadlineEnforcementMessageRelativeLocalized_pt</key>
    <string>${deadlineEnforcementMessageRelativeLocalizedPt_xml}</string>
    <key>DeadlineEnforcementMessageRelativeLocalized_ja</key>
    <string>${deadlineEnforcementMessageRelativeLocalizedJa_xml}</string>
    <key>DeadlineEnforcementMessageRelativeLocalized_nl</key>
    <string>${deadlineEnforcementMessageRelativeLocalizedNl_xml}</string>
    <key>PastDeadlinePromptTitle</key>
    <string>${pastDeadlinePromptTitle_xml}</string>
    <key>PastDeadlinePromptTitleLocalized_en</key>
    <string>${pastDeadlinePromptTitleLocalizedEn_xml}</string>
    <key>PastDeadlinePromptTitleLocalized_de</key>
    <string>${pastDeadlinePromptTitleLocalizedDe_xml}</string>
    <key>PastDeadlinePromptTitleLocalized_fr</key>
    <string>${pastDeadlinePromptTitleLocalizedFr_xml}</string>
    <key>PastDeadlinePromptTitleLocalized_es</key>
    <string>${pastDeadlinePromptTitleLocalizedEs_xml}</string>
    <key>PastDeadlinePromptTitleLocalized_pt</key>
    <string>${pastDeadlinePromptTitleLocalizedPt_xml}</string>
    <key>PastDeadlinePromptTitleLocalized_ja</key>
    <string>${pastDeadlinePromptTitleLocalizedJa_xml}</string>
    <key>PastDeadlinePromptTitleLocalized_nl</key>
    <string>${pastDeadlinePromptTitleLocalizedNl_xml}</string>
    <key>PastDeadlinePromptMessage</key>
    <string>${pastDeadlinePromptMessage_xml}</string>
    <key>PastDeadlinePromptMessageLocalized_en</key>
    <string>${pastDeadlinePromptMessageLocalizedEn_xml}</string>
    <key>PastDeadlinePromptMessageLocalized_de</key>
    <string>${pastDeadlinePromptMessageLocalizedDe_xml}</string>
    <key>PastDeadlinePromptMessageLocalized_fr</key>
    <string>${pastDeadlinePromptMessageLocalizedFr_xml}</string>
    <key>PastDeadlinePromptMessageLocalized_es</key>
    <string>${pastDeadlinePromptMessageLocalizedEs_xml}</string>
    <key>PastDeadlinePromptMessageLocalized_pt</key>
    <string>${pastDeadlinePromptMessageLocalizedPt_xml}</string>
    <key>PastDeadlinePromptMessageLocalized_ja</key>
    <string>${pastDeadlinePromptMessageLocalizedJa_xml}</string>
    <key>PastDeadlinePromptMessageLocalized_nl</key>
    <string>${pastDeadlinePromptMessageLocalizedNl_xml}</string>
    <key>PastDeadlineForceTitle</key>
    <string>${pastDeadlineForceTitle_xml}</string>
    <key>PastDeadlineForceTitleLocalized_en</key>
    <string>${pastDeadlineForceTitleLocalizedEn_xml}</string>
    <key>PastDeadlineForceTitleLocalized_de</key>
    <string>${pastDeadlineForceTitleLocalizedDe_xml}</string>
    <key>PastDeadlineForceTitleLocalized_fr</key>
    <string>${pastDeadlineForceTitleLocalizedFr_xml}</string>
    <key>PastDeadlineForceTitleLocalized_es</key>
    <string>${pastDeadlineForceTitleLocalizedEs_xml}</string>
    <key>PastDeadlineForceTitleLocalized_pt</key>
    <string>${pastDeadlineForceTitleLocalizedPt_xml}</string>
    <key>PastDeadlineForceTitleLocalized_ja</key>
    <string>${pastDeadlineForceTitleLocalizedJa_xml}</string>
    <key>PastDeadlineForceTitleLocalized_nl</key>
    <string>${pastDeadlineForceTitleLocalizedNl_xml}</string>
    <key>PastDeadlineForceMessage</key>
    <string>${pastDeadlineForceMessage_xml}</string>
    <key>PastDeadlineForceMessageLocalized_en</key>
    <string>${pastDeadlineForceMessageLocalizedEn_xml}</string>
    <key>PastDeadlineForceMessageLocalized_de</key>
    <string>${pastDeadlineForceMessageLocalizedDe_xml}</string>
    <key>PastDeadlineForceMessageLocalized_fr</key>
    <string>${pastDeadlineForceMessageLocalizedFr_xml}</string>
    <key>PastDeadlineForceMessageLocalized_es</key>
    <string>${pastDeadlineForceMessageLocalizedEs_xml}</string>
    <key>PastDeadlineForceMessageLocalized_pt</key>
    <string>${pastDeadlineForceMessageLocalizedPt_xml}</string>
    <key>PastDeadlineForceMessageLocalized_ja</key>
    <string>${pastDeadlineForceMessageLocalizedJa_xml}</string>
    <key>PastDeadlineForceMessageLocalized_nl</key>
    <string>${pastDeadlineForceMessageLocalizedNl_xml}</string>
    <key>Message</key>
    <string>${message_xml}</string>
    <key>MessageLocalized_en</key>
    <string>${messageLocalizedEn_xml}</string>
    <key>MessageLocalized_de</key>
    <string>${messageLocalizedDe_xml}</string>
    <key>MessageLocalized_fr</key>
    <string>${messageLocalizedFr_xml}</string>
    <key>MessageLocalized_es</key>
    <string>${messageLocalizedEs_xml}</string>
    <key>MessageLocalized_pt</key>
    <string>${messageLocalizedPt_xml}</string>
    <key>MessageLocalized_ja</key>
    <string>${messageLocalizedJa_xml}</string>
    <key>MessageLocalized_nl</key>
    <string>${messageLocalizedNl_xml}</string>

    <!-- Infobox -->
    <key>InfoBox</key>
    <string>${infobox_xml}</string>

    <!-- Help section -->
    <key>HelpMessage</key>
    <string>${helpmessage_xml}</string>
    <key>HelpMessageLocalized_en</key>
    <string>${helpmessageLocalizedEn_xml}</string>
    <key>HelpMessageLocalized_de</key>
    <string>${helpmessageLocalizedDe_xml}</string>
    <key>HelpMessageLocalized_fr</key>
    <string>${helpmessageLocalizedFr_xml}</string>
    <key>HelpMessageLocalized_es</key>
    <string>${helpmessageLocalizedEs_xml}</string>
    <key>HelpMessageLocalized_pt</key>
    <string>${helpmessageLocalizedPt_xml}</string>
    <key>HelpMessageLocalized_ja</key>
    <string>${helpmessageLocalizedJa_xml}</string>
    <key>HelpMessageLocalized_nl</key>
    <string>${helpmessageLocalizedNl_xml}</string>
    <key>HelpImage</key>
    <string>${helpimage_xml}</string>
</dict>
</plist>
EOF

echo "SUCCESS! .plist generated:"
echo "   → $OUTPUT_PLIST_FILE"
echo ""
echo "Extracting preference values from ${SOURCE_SCRIPT#${SCRIPT_DIR}/} → $OUTPUT_MOBILECONFIG_FILE"

# ─────────────────────────────────────────────────────────────
# Generate mobileconfig
# ─────────────────────────────────────────────────────────────
cat <<EOF > "${OUTPUT_MOBILECONFIG_FILE}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadContent</key>
            <dict>
                <key>${reverseDomainNameNotation}.${organizationScriptName}</key>
                <dict>
                    <key>Forced</key>
                    <array>
                        <dict>
                            <key>mcx_preference_settings</key>
                            <dict>
                                <key>ScriptLog</key>
                                <string>${scriptLog_xml}</string>
                                <key>DaysBeforeDeadlineDisplayReminder</key>
                                <integer>${daysBeforeDeadlineDisplayReminder}</integer>
                                <key>DaysBeforeDeadlineBlurscreen</key>
                                <integer>${daysBeforeDeadlineBlurscreen}</integer>
                                <key>DaysBeforeDeadlineHidingButton2</key>
                                <integer>${daysBeforeDeadlineHidingButton2}</integer>
                                <key>DaysOfExcessiveUptimeWarning</key>
                                <integer>${daysOfExcessiveUptimeWarning}</integer>
                                <key>PastDeadlineRestartBehavior</key>
                                <string>${pastDeadlineRestartBehavior_xml}</string>
                                <key>DaysPastDeadlineRestartWorkflow</key>
                                <integer>${daysPastDeadlineRestartWorkflow}</integer>
                                <key>MeetingDelay</key>
                                <integer>${meetingDelay}</integer>
                                <key>AcceptableAssertionApplicationNames</key>
                                <string>${acceptableAssertionApplicationNames_xml}</string>
                                <key>MinimumDiskFreePercentage</key>
                                <integer>${minimumDiskFreePercentage}</integer>
                                <key>OrganizationOverlayIconURL</key>
                                <string>${overlayicon_xml}</string>
                                <key>OrganizationOverlayIconURLdark</key>
                                <string>${overlayiconDark_xml}</string>
                                <key>SwapOverlayAndLogo</key>
                                ${swapOverlayAndLogo_xml}
                                <key>DateFormatDeadlineHumanReadable</key>
                                <string>${dateFormat_xml}</string>
                                <key>SupportTeamName</key>
                                <string>${supportTeamName_xml}</string>
                                <key>SupportTeamPhone</key>
                                <string>${supportTeamPhone_xml}</string>
                                <key>SupportTeamEmail</key>
                                <string>${supportTeamEmail_xml}</string>
                                <key>SupportTeamWebsite</key>
                                <string>${supportTeamWebsite_xml}</string>
                                <key>SupportKB</key>
                                <string>${supportKB_xml}</string>
                                <key>InfoButtonAction</key>
                                <string>${infobuttonaction_xml}</string>
                                <key>SupportKBURL</key>
                                <string>${supportKBURL_xml}</string>
                                <key>SupportAssistanceMessage</key>
                                <string>${supportAssistanceMessage_xml}</string>
                                <key>SupportAssistanceMessageLocalized_en</key>
                                <string>${supportAssistanceMessageLocalizedEn_xml}</string>
                                <key>SupportAssistanceMessageLocalized_de</key>
                                <string>${supportAssistanceMessageLocalizedDe_xml}</string>
                                <key>SupportAssistanceMessageLocalized_fr</key>
                                <string>${supportAssistanceMessageLocalizedFr_xml}</string>
                                <key>SupportAssistanceMessageLocalized_es</key>
                                <string>${supportAssistanceMessageLocalizedEs_xml}</string>
                                <key>SupportAssistanceMessageLocalized_pt</key>
                                <string>${supportAssistanceMessageLocalizedPt_xml}</string>
                                <key>SupportAssistanceMessageLocalized_ja</key>
                                <string>${supportAssistanceMessageLocalizedJa_xml}</string>
                                <key>SupportAssistanceMessageLocalized_nl</key>
                                <string>${supportAssistanceMessageLocalizedNl_xml}</string>
                                <key>LanguageOverride</key>
                                <string>${languageOverride_xml}</string>
                                <key>Title</key>
                                <string>${title_xml}</string>
                                <key>TitleLocalized_en</key>
                                <string>${titleLocalizedEn_xml}</string>
                                <key>TitleLocalized_de</key>
                                <string>${titleLocalizedDe_xml}</string>
                                <key>TitleLocalized_fr</key>
                                <string>${titleLocalizedFr_xml}</string>
                                <key>TitleLocalized_es</key>
                                <string>${titleLocalizedEs_xml}</string>
                                <key>TitleLocalized_pt</key>
                                <string>${titleLocalizedPt_xml}</string>
                                <key>TitleLocalized_ja</key>
                                <string>${titleLocalizedJa_xml}</string>
                                <key>TitleLocalized_nl</key>
                                <string>${titleLocalizedNl_xml}</string>
                                <key>Button1Text</key>
                                <string>${button1text_xml}</string>
                                <key>Button1TextLocalized_en</key>
                                <string>${button1textLocalizedEn_xml}</string>
                                <key>Button1TextLocalized_de</key>
                                <string>${button1textLocalizedDe_xml}</string>
                                <key>Button1TextLocalized_fr</key>
                                <string>${button1textLocalizedFr_xml}</string>
                                <key>Button1TextLocalized_es</key>
                                <string>${button1textLocalizedEs_xml}</string>
                                <key>Button1TextLocalized_pt</key>
                                <string>${button1textLocalizedPt_xml}</string>
                                <key>Button1TextLocalized_ja</key>
                                <string>${button1textLocalizedJa_xml}</string>
                                <key>Button1TextLocalized_nl</key>
                                <string>${button1textLocalizedNl_xml}</string>
                                <key>Button2Text</key>
                                <string>${button2text_xml}</string>
                                <key>Button2TextLocalized_en</key>
                                <string>${button2textLocalizedEn_xml}</string>
                                <key>Button2TextLocalized_de</key>
                                <string>${button2textLocalizedDe_xml}</string>
                                <key>Button2TextLocalized_fr</key>
                                <string>${button2textLocalizedFr_xml}</string>
                                <key>Button2TextLocalized_es</key>
                                <string>${button2textLocalizedEs_xml}</string>
                                <key>Button2TextLocalized_pt</key>
                                <string>${button2textLocalizedPt_xml}</string>
                                <key>Button2TextLocalized_ja</key>
                                <string>${button2textLocalizedJa_xml}</string>
                                <key>Button2TextLocalized_nl</key>
                                <string>${button2textLocalizedNl_xml}</string>
                                <key>InfoButtonText</key>
                                <string>${infobuttontext_xml}</string>
                                <key>InfoButtonTextLocalized_en</key>
                                <string>${infobuttontextLocalizedEn_xml}</string>
                                <key>InfoButtonTextLocalized_de</key>
                                <string>${infobuttontextLocalizedDe_xml}</string>
                                <key>InfoButtonTextLocalized_fr</key>
                                <string>${infobuttontextLocalizedFr_xml}</string>
                                <key>InfoButtonTextLocalized_es</key>
                                <string>${infobuttontextLocalizedEs_xml}</string>
                                <key>InfoButtonTextLocalized_pt</key>
                                <string>${infobuttontextLocalizedPt_xml}</string>
                                <key>InfoButtonTextLocalized_ja</key>
                                <string>${infobuttontextLocalizedJa_xml}</string>
                                <key>InfoButtonTextLocalized_nl</key>
                                <string>${infobuttontextLocalizedNl_xml}</string>
                                <key>ExcessiveUptimeWarningMessage</key>
                                <string>${excessiveUptimeWarningMessage_xml}</string>
                                <key>ExcessiveUptimeWarningMessageLocalized_en</key>
                                <string>${excessiveUptimeWarningMessageLocalizedEn_xml}</string>
                                <key>ExcessiveUptimeWarningMessageLocalized_de</key>
                                <string>${excessiveUptimeWarningMessageLocalizedDe_xml}</string>
                                <key>ExcessiveUptimeWarningMessageLocalized_fr</key>
                                <string>${excessiveUptimeWarningMessageLocalizedFr_xml}</string>
                                <key>ExcessiveUptimeWarningMessageLocalized_es</key>
                                <string>${excessiveUptimeWarningMessageLocalizedEs_xml}</string>
                                <key>ExcessiveUptimeWarningMessageLocalized_pt</key>
                                <string>${excessiveUptimeWarningMessageLocalizedPt_xml}</string>
                                <key>ExcessiveUptimeWarningMessageLocalized_ja</key>
                                <string>${excessiveUptimeWarningMessageLocalizedJa_xml}</string>
                                <key>ExcessiveUptimeWarningMessageLocalized_nl</key>
                                <string>${excessiveUptimeWarningMessageLocalizedNl_xml}</string>
                                <key>DiskSpaceWarningMessage</key>
                                <string>${diskSpaceWarningMessage_xml}</string>
                                <key>DiskSpaceWarningMessageLocalized_en</key>
                                <string>${diskSpaceWarningMessageLocalizedEn_xml}</string>
                                <key>DiskSpaceWarningMessageLocalized_de</key>
                                <string>${diskSpaceWarningMessageLocalizedDe_xml}</string>
                                <key>DiskSpaceWarningMessageLocalized_fr</key>
                                <string>${diskSpaceWarningMessageLocalizedFr_xml}</string>
                                <key>DiskSpaceWarningMessageLocalized_es</key>
                                <string>${diskSpaceWarningMessageLocalizedEs_xml}</string>
                                <key>DiskSpaceWarningMessageLocalized_pt</key>
                                <string>${diskSpaceWarningMessageLocalizedPt_xml}</string>
                                <key>DiskSpaceWarningMessageLocalized_ja</key>
                                <string>${diskSpaceWarningMessageLocalizedJa_xml}</string>
                                <key>DiskSpaceWarningMessageLocalized_nl</key>
                                <string>${diskSpaceWarningMessageLocalizedNl_xml}</string>
                                <key>StagedUpdateMessage</key>
                                <string>${stagedUpdateMessage_xml}</string>
                                <key>StagedUpdateMessageLocalized_en</key>
                                <string>${stagedUpdateMessageLocalizedEn_xml}</string>
                                <key>StagedUpdateMessageLocalized_de</key>
                                <string>${stagedUpdateMessageLocalizedDe_xml}</string>
                                <key>StagedUpdateMessageLocalized_fr</key>
                                <string>${stagedUpdateMessageLocalizedFr_xml}</string>
                                <key>StagedUpdateMessageLocalized_es</key>
                                <string>${stagedUpdateMessageLocalizedEs_xml}</string>
                                <key>StagedUpdateMessageLocalized_pt</key>
                                <string>${stagedUpdateMessageLocalizedPt_xml}</string>
                                <key>StagedUpdateMessageLocalized_ja</key>
                                <string>${stagedUpdateMessageLocalizedJa_xml}</string>
                                <key>StagedUpdateMessageLocalized_nl</key>
                                <string>${stagedUpdateMessageLocalizedNl_xml}</string>
                                <key>PartiallyStagedUpdateMessage</key>
                                <string>${partiallyStagedUpdateMessage_xml}</string>
                                <key>PartiallyStagedUpdateMessageLocalized_en</key>
                                <string>${partiallyStagedUpdateMessageLocalizedEn_xml}</string>
                                <key>PartiallyStagedUpdateMessageLocalized_de</key>
                                <string>${partiallyStagedUpdateMessageLocalizedDe_xml}</string>
                                <key>PartiallyStagedUpdateMessageLocalized_fr</key>
                                <string>${partiallyStagedUpdateMessageLocalizedFr_xml}</string>
                                <key>PartiallyStagedUpdateMessageLocalized_es</key>
                                <string>${partiallyStagedUpdateMessageLocalizedEs_xml}</string>
                                <key>PartiallyStagedUpdateMessageLocalized_pt</key>
                                <string>${partiallyStagedUpdateMessageLocalizedPt_xml}</string>
                                <key>PartiallyStagedUpdateMessageLocalized_ja</key>
                                <string>${partiallyStagedUpdateMessageLocalizedJa_xml}</string>
                                <key>PartiallyStagedUpdateMessageLocalized_nl</key>
                                <string>${partiallyStagedUpdateMessageLocalizedNl_xml}</string>
                                <key>PendingDownloadMessage</key>
                                <string>${pendingDownloadMessage_xml}</string>
                                <key>PendingDownloadMessageLocalized_en</key>
                                <string>${pendingDownloadMessageLocalizedEn_xml}</string>
                                <key>PendingDownloadMessageLocalized_de</key>
                                <string>${pendingDownloadMessageLocalizedDe_xml}</string>
                                <key>PendingDownloadMessageLocalized_fr</key>
                                <string>${pendingDownloadMessageLocalizedFr_xml}</string>
                                <key>PendingDownloadMessageLocalized_es</key>
                                <string>${pendingDownloadMessageLocalizedEs_xml}</string>
                                <key>PendingDownloadMessageLocalized_pt</key>
                                <string>${pendingDownloadMessageLocalizedPt_xml}</string>
                                <key>PendingDownloadMessageLocalized_ja</key>
                                <string>${pendingDownloadMessageLocalizedJa_xml}</string>
                                <key>PendingDownloadMessageLocalized_nl</key>
                                <string>${pendingDownloadMessageLocalizedNl_xml}</string>
                                <key>HideStagedUpdateInfo</key>
                                ${hideStagedInfo_xml}
                                <key>RelativeDeadlineToday</key>
                                <string>${relativeDeadlineToday_xml}</string>
                                <key>RelativeDeadlineTodayLocalized_en</key>
                                <string>${relativeDeadlineTodayLocalizedEn_xml}</string>
                                <key>RelativeDeadlineTodayLocalized_de</key>
                                <string>${relativeDeadlineTodayLocalizedDe_xml}</string>
                                <key>RelativeDeadlineTodayLocalized_fr</key>
                                <string>${relativeDeadlineTodayLocalizedFr_xml}</string>
                                <key>RelativeDeadlineTodayLocalized_es</key>
                                <string>${relativeDeadlineTodayLocalizedEs_xml}</string>
                                <key>RelativeDeadlineTodayLocalized_pt</key>
                                <string>${relativeDeadlineTodayLocalizedPt_xml}</string>
                                <key>RelativeDeadlineTodayLocalized_ja</key>
                                <string>${relativeDeadlineTodayLocalizedJa_xml}</string>
                                <key>RelativeDeadlineTodayLocalized_nl</key>
                                <string>${relativeDeadlineTodayLocalizedNl_xml}</string>
                                <key>RelativeDeadlineTomorrow</key>
                                <string>${relativeDeadlineTomorrow_xml}</string>
                                <key>RelativeDeadlineTomorrowLocalized_en</key>
                                <string>${relativeDeadlineTomorrowLocalizedEn_xml}</string>
                                <key>RelativeDeadlineTomorrowLocalized_de</key>
                                <string>${relativeDeadlineTomorrowLocalizedDe_xml}</string>
                                <key>RelativeDeadlineTomorrowLocalized_fr</key>
                                <string>${relativeDeadlineTomorrowLocalizedFr_xml}</string>
                                <key>RelativeDeadlineTomorrowLocalized_es</key>
                                <string>${relativeDeadlineTomorrowLocalizedEs_xml}</string>
                                <key>RelativeDeadlineTomorrowLocalized_pt</key>
                                <string>${relativeDeadlineTomorrowLocalizedPt_xml}</string>
                                <key>RelativeDeadlineTomorrowLocalized_ja</key>
                                <string>${relativeDeadlineTomorrowLocalizedJa_xml}</string>
                                <key>RelativeDeadlineTomorrowLocalized_nl</key>
                                <string>${relativeDeadlineTomorrowLocalizedNl_xml}</string>
                                <key>UpdateWord</key>
                                <string>${updateWord_xml}</string>
                                <key>UpdateWordLocalized_en</key>
                                <string>${updateWordLocalizedEn_xml}</string>
                                <key>UpdateWordLocalized_de</key>
                                <string>${updateWordLocalizedDe_xml}</string>
                                <key>UpdateWordLocalized_fr</key>
                                <string>${updateWordLocalizedFr_xml}</string>
                                <key>UpdateWordLocalized_es</key>
                                <string>${updateWordLocalizedEs_xml}</string>
                                <key>UpdateWordLocalized_pt</key>
                                <string>${updateWordLocalizedPt_xml}</string>
                                <key>UpdateWordLocalized_ja</key>
                                <string>${updateWordLocalizedJa_xml}</string>
                                <key>UpdateWordLocalized_nl</key>
                                <string>${updateWordLocalizedNl_xml}</string>
                                <key>UpgradeWord</key>
                                <string>${upgradeWord_xml}</string>
                                <key>UpgradeWordLocalized_en</key>
                                <string>${upgradeWordLocalizedEn_xml}</string>
                                <key>UpgradeWordLocalized_de</key>
                                <string>${upgradeWordLocalizedDe_xml}</string>
                                <key>UpgradeWordLocalized_fr</key>
                                <string>${upgradeWordLocalizedFr_xml}</string>
                                <key>UpgradeWordLocalized_es</key>
                                <string>${upgradeWordLocalizedEs_xml}</string>
                                <key>UpgradeWordLocalized_pt</key>
                                <string>${upgradeWordLocalizedPt_xml}</string>
                                <key>UpgradeWordLocalized_ja</key>
                                <string>${upgradeWordLocalizedJa_xml}</string>
                                <key>UpgradeWordLocalized_nl</key>
                                <string>${upgradeWordLocalizedNl_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdate</key>
                                <string>${softwareUpdateButtonTextUpdate_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdateLocalized_en</key>
                                <string>${softwareUpdateButtonTextUpdateLocalizedEn_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdateLocalized_de</key>
                                <string>${softwareUpdateButtonTextUpdateLocalizedDe_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdateLocalized_fr</key>
                                <string>${softwareUpdateButtonTextUpdateLocalizedFr_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdateLocalized_es</key>
                                <string>${softwareUpdateButtonTextUpdateLocalizedEs_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdateLocalized_pt</key>
                                <string>${softwareUpdateButtonTextUpdateLocalizedPt_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdateLocalized_ja</key>
                                <string>${softwareUpdateButtonTextUpdateLocalizedJa_xml}</string>
                                <key>SoftwareUpdateButtonTextUpdateLocalized_nl</key>
                                <string>${softwareUpdateButtonTextUpdateLocalizedNl_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgrade</key>
                                <string>${softwareUpdateButtonTextUpgrade_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgradeLocalized_en</key>
                                <string>${softwareUpdateButtonTextUpgradeLocalizedEn_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgradeLocalized_de</key>
                                <string>${softwareUpdateButtonTextUpgradeLocalizedDe_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgradeLocalized_fr</key>
                                <string>${softwareUpdateButtonTextUpgradeLocalizedFr_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgradeLocalized_es</key>
                                <string>${softwareUpdateButtonTextUpgradeLocalizedEs_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgradeLocalized_pt</key>
                                <string>${softwareUpdateButtonTextUpgradeLocalizedPt_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgradeLocalized_ja</key>
                                <string>${softwareUpdateButtonTextUpgradeLocalizedJa_xml}</string>
                                <key>SoftwareUpdateButtonTextUpgradeLocalized_nl</key>
                                <string>${softwareUpdateButtonTextUpgradeLocalizedNl_xml}</string>
                                <key>RestartNowButtonText</key>
                                <string>${restartNowButtonText_xml}</string>
                                <key>RestartNowButtonTextLocalized_en</key>
                                <string>${restartNowButtonTextLocalizedEn_xml}</string>
                                <key>RestartNowButtonTextLocalized_de</key>
                                <string>${restartNowButtonTextLocalizedDe_xml}</string>
                                <key>RestartNowButtonTextLocalized_fr</key>
                                <string>${restartNowButtonTextLocalizedFr_xml}</string>
                                <key>RestartNowButtonTextLocalized_es</key>
                                <string>${restartNowButtonTextLocalizedEs_xml}</string>
                                <key>RestartNowButtonTextLocalized_pt</key>
                                <string>${restartNowButtonTextLocalizedPt_xml}</string>
                                <key>RestartNowButtonTextLocalized_ja</key>
                                <string>${restartNowButtonTextLocalizedJa_xml}</string>
                                <key>RestartNowButtonTextLocalized_nl</key>
                                <string>${restartNowButtonTextLocalizedNl_xml}</string>
                                <key>InfoboxLabelCurrent</key>
                                <string>${infoboxLabelCurrent_xml}</string>
                                <key>InfoboxLabelCurrentLocalized_en</key>
                                <string>${infoboxLabelCurrentLocalizedEn_xml}</string>
                                <key>InfoboxLabelCurrentLocalized_de</key>
                                <string>${infoboxLabelCurrentLocalizedDe_xml}</string>
                                <key>InfoboxLabelCurrentLocalized_fr</key>
                                <string>${infoboxLabelCurrentLocalizedFr_xml}</string>
                                <key>InfoboxLabelCurrentLocalized_es</key>
                                <string>${infoboxLabelCurrentLocalizedEs_xml}</string>
                                <key>InfoboxLabelCurrentLocalized_pt</key>
                                <string>${infoboxLabelCurrentLocalizedPt_xml}</string>
                                <key>InfoboxLabelCurrentLocalized_ja</key>
                                <string>${infoboxLabelCurrentLocalizedJa_xml}</string>
                                <key>InfoboxLabelCurrentLocalized_nl</key>
                                <string>${infoboxLabelCurrentLocalizedNl_xml}</string>
                                <key>InfoboxLabelRequired</key>
                                <string>${infoboxLabelRequired_xml}</string>
                                <key>InfoboxLabelRequiredLocalized_en</key>
                                <string>${infoboxLabelRequiredLocalizedEn_xml}</string>
                                <key>InfoboxLabelRequiredLocalized_de</key>
                                <string>${infoboxLabelRequiredLocalizedDe_xml}</string>
                                <key>InfoboxLabelRequiredLocalized_fr</key>
                                <string>${infoboxLabelRequiredLocalizedFr_xml}</string>
                                <key>InfoboxLabelRequiredLocalized_es</key>
                                <string>${infoboxLabelRequiredLocalizedEs_xml}</string>
                                <key>InfoboxLabelRequiredLocalized_pt</key>
                                <string>${infoboxLabelRequiredLocalizedPt_xml}</string>
                                <key>InfoboxLabelRequiredLocalized_ja</key>
                                <string>${infoboxLabelRequiredLocalizedJa_xml}</string>
                                <key>InfoboxLabelRequiredLocalized_nl</key>
                                <string>${infoboxLabelRequiredLocalizedNl_xml}</string>
                                <key>InfoboxLabelDeadline</key>
                                <string>${infoboxLabelDeadline_xml}</string>
                                <key>InfoboxLabelDeadlineLocalized_en</key>
                                <string>${infoboxLabelDeadlineLocalizedEn_xml}</string>
                                <key>InfoboxLabelDeadlineLocalized_de</key>
                                <string>${infoboxLabelDeadlineLocalizedDe_xml}</string>
                                <key>InfoboxLabelDeadlineLocalized_fr</key>
                                <string>${infoboxLabelDeadlineLocalizedFr_xml}</string>
                                <key>InfoboxLabelDeadlineLocalized_es</key>
                                <string>${infoboxLabelDeadlineLocalizedEs_xml}</string>
                                <key>InfoboxLabelDeadlineLocalized_pt</key>
                                <string>${infoboxLabelDeadlineLocalizedPt_xml}</string>
                                <key>InfoboxLabelDeadlineLocalized_ja</key>
                                <string>${infoboxLabelDeadlineLocalizedJa_xml}</string>
                                <key>InfoboxLabelDeadlineLocalized_nl</key>
                                <string>${infoboxLabelDeadlineLocalizedNl_xml}</string>
                                <key>InfoboxLabelDaysRemaining</key>
                                <string>${infoboxLabelDaysRemaining_xml}</string>
                                <key>InfoboxLabelDaysRemainingLocalized_en</key>
                                <string>${infoboxLabelDaysRemainingLocalizedEn_xml}</string>
                                <key>InfoboxLabelDaysRemainingLocalized_de</key>
                                <string>${infoboxLabelDaysRemainingLocalizedDe_xml}</string>
                                <key>InfoboxLabelDaysRemainingLocalized_fr</key>
                                <string>${infoboxLabelDaysRemainingLocalizedFr_xml}</string>
                                <key>InfoboxLabelDaysRemainingLocalized_es</key>
                                <string>${infoboxLabelDaysRemainingLocalizedEs_xml}</string>
                                <key>InfoboxLabelDaysRemainingLocalized_pt</key>
                                <string>${infoboxLabelDaysRemainingLocalizedPt_xml}</string>
                                <key>InfoboxLabelDaysRemainingLocalized_ja</key>
                                <string>${infoboxLabelDaysRemainingLocalizedJa_xml}</string>
                                <key>InfoboxLabelDaysRemainingLocalized_nl</key>
                                <string>${infoboxLabelDaysRemainingLocalizedNl_xml}</string>
                                <key>InfoboxLabelLastRestart</key>
                                <string>${infoboxLabelLastRestart_xml}</string>
                                <key>InfoboxLabelLastRestartLocalized_en</key>
                                <string>${infoboxLabelLastRestartLocalizedEn_xml}</string>
                                <key>InfoboxLabelLastRestartLocalized_de</key>
                                <string>${infoboxLabelLastRestartLocalizedDe_xml}</string>
                                <key>InfoboxLabelLastRestartLocalized_fr</key>
                                <string>${infoboxLabelLastRestartLocalizedFr_xml}</string>
                                <key>InfoboxLabelLastRestartLocalized_es</key>
                                <string>${infoboxLabelLastRestartLocalizedEs_xml}</string>
                                <key>InfoboxLabelLastRestartLocalized_pt</key>
                                <string>${infoboxLabelLastRestartLocalizedPt_xml}</string>
                                <key>InfoboxLabelLastRestartLocalized_ja</key>
                                <string>${infoboxLabelLastRestartLocalizedJa_xml}</string>
                                <key>InfoboxLabelLastRestartLocalized_nl</key>
                                <string>${infoboxLabelLastRestartLocalizedNl_xml}</string>
                                <key>InfoboxLabelFreeDiskSpace</key>
                                <string>${infoboxLabelFreeDiskSpace_xml}</string>
                                <key>InfoboxLabelFreeDiskSpaceLocalized_en</key>
                                <string>${infoboxLabelFreeDiskSpaceLocalizedEn_xml}</string>
                                <key>InfoboxLabelFreeDiskSpaceLocalized_de</key>
                                <string>${infoboxLabelFreeDiskSpaceLocalizedDe_xml}</string>
                                <key>InfoboxLabelFreeDiskSpaceLocalized_fr</key>
                                <string>${infoboxLabelFreeDiskSpaceLocalizedFr_xml}</string>
                                <key>InfoboxLabelFreeDiskSpaceLocalized_es</key>
                                <string>${infoboxLabelFreeDiskSpaceLocalizedEs_xml}</string>
                                <key>InfoboxLabelFreeDiskSpaceLocalized_pt</key>
                                <string>${infoboxLabelFreeDiskSpaceLocalizedPt_xml}</string>
                                <key>InfoboxLabelFreeDiskSpaceLocalized_ja</key>
                                <string>${infoboxLabelFreeDiskSpaceLocalizedJa_xml}</string>
                                <key>InfoboxLabelFreeDiskSpaceLocalized_nl</key>
                                <string>${infoboxLabelFreeDiskSpaceLocalizedNl_xml}</string>
                                <key>DeadlineEnforcementMessageAbsolute</key>
                                <string>${deadlineEnforcementMessageAbsolute_xml}</string>
                                <key>DeadlineEnforcementMessageAbsoluteLocalized_en</key>
                                <string>${deadlineEnforcementMessageAbsoluteLocalizedEn_xml}</string>
                                <key>DeadlineEnforcementMessageAbsoluteLocalized_de</key>
                                <string>${deadlineEnforcementMessageAbsoluteLocalizedDe_xml}</string>
                                <key>DeadlineEnforcementMessageAbsoluteLocalized_fr</key>
                                <string>${deadlineEnforcementMessageAbsoluteLocalizedFr_xml}</string>
                                <key>DeadlineEnforcementMessageAbsoluteLocalized_es</key>
                                <string>${deadlineEnforcementMessageAbsoluteLocalizedEs_xml}</string>
                                <key>DeadlineEnforcementMessageAbsoluteLocalized_pt</key>
                                <string>${deadlineEnforcementMessageAbsoluteLocalizedPt_xml}</string>
                                <key>DeadlineEnforcementMessageAbsoluteLocalized_ja</key>
                                <string>${deadlineEnforcementMessageAbsoluteLocalizedJa_xml}</string>
                                <key>DeadlineEnforcementMessageAbsoluteLocalized_nl</key>
                                <string>${deadlineEnforcementMessageAbsoluteLocalizedNl_xml}</string>
                                <key>DeadlineEnforcementMessageRelative</key>
                                <string>${deadlineEnforcementMessageRelative_xml}</string>
                                <key>DeadlineEnforcementMessageRelativeLocalized_en</key>
                                <string>${deadlineEnforcementMessageRelativeLocalizedEn_xml}</string>
                                <key>DeadlineEnforcementMessageRelativeLocalized_de</key>
                                <string>${deadlineEnforcementMessageRelativeLocalizedDe_xml}</string>
                                <key>DeadlineEnforcementMessageRelativeLocalized_fr</key>
                                <string>${deadlineEnforcementMessageRelativeLocalizedFr_xml}</string>
                                <key>DeadlineEnforcementMessageRelativeLocalized_es</key>
                                <string>${deadlineEnforcementMessageRelativeLocalizedEs_xml}</string>
                                <key>DeadlineEnforcementMessageRelativeLocalized_pt</key>
                                <string>${deadlineEnforcementMessageRelativeLocalizedPt_xml}</string>
                                <key>DeadlineEnforcementMessageRelativeLocalized_ja</key>
                                <string>${deadlineEnforcementMessageRelativeLocalizedJa_xml}</string>
                                <key>DeadlineEnforcementMessageRelativeLocalized_nl</key>
                                <string>${deadlineEnforcementMessageRelativeLocalizedNl_xml}</string>
                                <key>PastDeadlinePromptTitle</key>
                                <string>${pastDeadlinePromptTitle_xml}</string>
                                <key>PastDeadlinePromptTitleLocalized_en</key>
                                <string>${pastDeadlinePromptTitleLocalizedEn_xml}</string>
                                <key>PastDeadlinePromptTitleLocalized_de</key>
                                <string>${pastDeadlinePromptTitleLocalizedDe_xml}</string>
                                <key>PastDeadlinePromptTitleLocalized_fr</key>
                                <string>${pastDeadlinePromptTitleLocalizedFr_xml}</string>
                                <key>PastDeadlinePromptTitleLocalized_es</key>
                                <string>${pastDeadlinePromptTitleLocalizedEs_xml}</string>
                                <key>PastDeadlinePromptTitleLocalized_pt</key>
                                <string>${pastDeadlinePromptTitleLocalizedPt_xml}</string>
                                <key>PastDeadlinePromptTitleLocalized_ja</key>
                                <string>${pastDeadlinePromptTitleLocalizedJa_xml}</string>
                                <key>PastDeadlinePromptTitleLocalized_nl</key>
                                <string>${pastDeadlinePromptTitleLocalizedNl_xml}</string>
                                <key>PastDeadlinePromptMessage</key>
                                <string>${pastDeadlinePromptMessage_xml}</string>
                                <key>PastDeadlinePromptMessageLocalized_en</key>
                                <string>${pastDeadlinePromptMessageLocalizedEn_xml}</string>
                                <key>PastDeadlinePromptMessageLocalized_de</key>
                                <string>${pastDeadlinePromptMessageLocalizedDe_xml}</string>
                                <key>PastDeadlinePromptMessageLocalized_fr</key>
                                <string>${pastDeadlinePromptMessageLocalizedFr_xml}</string>
                                <key>PastDeadlinePromptMessageLocalized_es</key>
                                <string>${pastDeadlinePromptMessageLocalizedEs_xml}</string>
                                <key>PastDeadlinePromptMessageLocalized_pt</key>
                                <string>${pastDeadlinePromptMessageLocalizedPt_xml}</string>
                                <key>PastDeadlinePromptMessageLocalized_ja</key>
                                <string>${pastDeadlinePromptMessageLocalizedJa_xml}</string>
                                <key>PastDeadlinePromptMessageLocalized_nl</key>
                                <string>${pastDeadlinePromptMessageLocalizedNl_xml}</string>
                                <key>PastDeadlineForceTitle</key>
                                <string>${pastDeadlineForceTitle_xml}</string>
                                <key>PastDeadlineForceTitleLocalized_en</key>
                                <string>${pastDeadlineForceTitleLocalizedEn_xml}</string>
                                <key>PastDeadlineForceTitleLocalized_de</key>
                                <string>${pastDeadlineForceTitleLocalizedDe_xml}</string>
                                <key>PastDeadlineForceTitleLocalized_fr</key>
                                <string>${pastDeadlineForceTitleLocalizedFr_xml}</string>
                                <key>PastDeadlineForceTitleLocalized_es</key>
                                <string>${pastDeadlineForceTitleLocalizedEs_xml}</string>
                                <key>PastDeadlineForceTitleLocalized_pt</key>
                                <string>${pastDeadlineForceTitleLocalizedPt_xml}</string>
                                <key>PastDeadlineForceTitleLocalized_ja</key>
                                <string>${pastDeadlineForceTitleLocalizedJa_xml}</string>
                                <key>PastDeadlineForceTitleLocalized_nl</key>
                                <string>${pastDeadlineForceTitleLocalizedNl_xml}</string>
                                <key>PastDeadlineForceMessage</key>
                                <string>${pastDeadlineForceMessage_xml}</string>
                                <key>PastDeadlineForceMessageLocalized_en</key>
                                <string>${pastDeadlineForceMessageLocalizedEn_xml}</string>
                                <key>PastDeadlineForceMessageLocalized_de</key>
                                <string>${pastDeadlineForceMessageLocalizedDe_xml}</string>
                                <key>PastDeadlineForceMessageLocalized_fr</key>
                                <string>${pastDeadlineForceMessageLocalizedFr_xml}</string>
                                <key>PastDeadlineForceMessageLocalized_es</key>
                                <string>${pastDeadlineForceMessageLocalizedEs_xml}</string>
                                <key>PastDeadlineForceMessageLocalized_pt</key>
                                <string>${pastDeadlineForceMessageLocalizedPt_xml}</string>
                                <key>PastDeadlineForceMessageLocalized_ja</key>
                                <string>${pastDeadlineForceMessageLocalizedJa_xml}</string>
                                <key>PastDeadlineForceMessageLocalized_nl</key>
                                <string>${pastDeadlineForceMessageLocalizedNl_xml}</string>
                                <key>Message</key>
                                <string>${message_xml}</string>
                                <key>MessageLocalized_en</key>
                                <string>${messageLocalizedEn_xml}</string>
                                <key>MessageLocalized_de</key>
                                <string>${messageLocalizedDe_xml}</string>
                                <key>MessageLocalized_fr</key>
                                <string>${messageLocalizedFr_xml}</string>
                                <key>MessageLocalized_es</key>
                                <string>${messageLocalizedEs_xml}</string>
                                <key>MessageLocalized_pt</key>
                                <string>${messageLocalizedPt_xml}</string>
                                <key>MessageLocalized_ja</key>
                                <string>${messageLocalizedJa_xml}</string>
                                <key>MessageLocalized_nl</key>
                                <string>${messageLocalizedNl_xml}</string>
                                <key>InfoBox</key>
                                <string>${infobox_xml}</string>
                                <key>HelpMessage</key>
                                <string>${helpmessage_xml}</string>
                                <key>HelpMessageLocalized_en</key>
                                <string>${helpmessageLocalizedEn_xml}</string>
                                <key>HelpMessageLocalized_de</key>
                                <string>${helpmessageLocalizedDe_xml}</string>
                                <key>HelpMessageLocalized_fr</key>
                                <string>${helpmessageLocalizedFr_xml}</string>
                                <key>HelpMessageLocalized_es</key>
                                <string>${helpmessageLocalizedEs_xml}</string>
                                <key>HelpMessageLocalized_pt</key>
                                <string>${helpmessageLocalizedPt_xml}</string>
                                <key>HelpMessageLocalized_ja</key>
                                <string>${helpmessageLocalizedJa_xml}</string>
                                <key>HelpMessageLocalized_nl</key>
                                <string>${helpmessageLocalizedNl_xml}</string>
                                <key>HelpImage</key>
                                <string>${helpimage_xml}</string>
                            </dict>
                        </dict>
                    </array>
                </dict>
            </dict>
            <key>PayloadDisplayName</key>
            <string>Custom Settings</string>
            <key>PayloadIdentifier</key>
            <string>${MANAGEDCLIENT_PAYLOAD_UUID}</string>
            <key>PayloadOrganization</key>
            <string>${organizationScriptName}</string>
            <key>PayloadType</key>
            <string>com.apple.ManagedClient.preferences</string>
            <key>PayloadUUID</key>
            <string>${MANAGEDCLIENT_PAYLOAD_UUID}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>
    <key>PayloadDescription</key>
    <string>DDM OS Reminder default configuration</string>
    <key>PayloadDisplayName</key>
    <string>DDM OS Reminder (${scriptVersion})</string>
    <key>PayloadEnabled</key>
    <true/>
    <key>PayloadIdentifier</key>
    <string>${PROFILE_UUID}</string>
    <key>PayloadOrganization</key>
    <string>${organizationScriptName}</string>
    <key>PayloadRemovalDisallowed</key>
    <true/>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>${PROFILE_UUID}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
EOF

echo "SUCCESS! .mobileconfig generated:"
echo "   → ${OUTPUT_MOBILECONFIG_FILE}"
