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

scriptVersion="2.3.0b8"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/../reminderDialog.zsh"

[[ -f "$SOURCE_SCRIPT" ]] || { echo "ERROR: Cannot find reminderDialog.zsh at ${SOURCE_SCRIPT}"; exit 1; }

reverseDomainNameNotation=$(awk -F'"' '/^reverseDomainNameNotation=/{print $2}' "$SOURCE_SCRIPT")
organizationScriptName=$(awk -F'"' '/^organizationScriptName=/{print $2}' "$SOURCE_SCRIPT")
datestamp=$(date '+%Y-%m-%d-%H%M%S')

# ─────────────────────────────────────────────────────────────
# Safety check for default reverseDomainNameNotation
# IMPORTANT: You must customize reminderDialog.zsh BEFORE running this script.
# Change reverseDomainNameNotation from "org.churchofjesuschrist" to your organization's value.
# ─────────────────────────────────────────────────────────────
if [[ "$reverseDomainNameNotation" == "org.churchofjesuschrist" ]]; then
    echo "ERROR: Please customize 'reminderDialog.zsh' before executing this script."
    echo "       Change reverseDomainNameNotation to your organization's value (e.g., us.snelson)."
    echo "       Then run this script again to generate configs from your customized values."
    exit 1
fi

# Target Output Files
OUTPUT_PLIST_FILE="${SCRIPT_DIR}/${reverseDomainNameNotation}.${organizationScriptName}-${datestamp}.plist"
# OUTPUT_MOBILECONFIG_FILE="${SCRIPT_DIR}/${reverseDomainNameNotation}.${organizationScriptName}-${datestamp}.mobileconfig"
OUTPUT_MOBILECONFIG_FILE="${SCRIPT_DIR}/DDM OS Reminder-${datestamp}-unsigned.mobileconfig"

# Generate UUIDs for the profile and the ManagedClient payload
PROFILE_UUID="$(uuidgen | tr '[:lower:]' '[:upper:]')"
MANAGEDCLIENT_PAYLOAD_UUID="$(uuidgen | tr '[:lower:]' '[:upper:]')"

echo "Generating default plist → $OUTPUT_PLIST_FILE"

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
    if [[ $line =~ '"[^|]+\|([^"]+)"' ]]; then
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
meetingDelay=$(extract_from_preference_map meetingDelay)
dateFormatDeadlineHumanReadable=$(extract_from_preference_map dateFormatDeadlineHumanReadable)
swapOverlayAndLogo_raw=$(extract_from_preference_map swapOverlayAndLogo)
minimumDiskFreePercentage=$(extract_from_preference_map minimumDiskFreePercentage)

case "${swapOverlayAndLogo_raw:u}" in
    YES|TRUE|1) swapOverlayAndLogo_xml="<true/>" ;;
    *)          swapOverlayAndLogo_xml="<false/>" ;;
esac

# ─────────────────────────────────────────────────────────────
# Extract all values from preferenceConfiguration map
# ─────────────────────────────────────────────────────────────
defaultTitle=$(extract_from_preference_map title)
defaultExcessiveUptimeWarningMessage=$(extract_from_preference_map excessiveUptimeWarningMessage)
defaultDiskSpaceWarningMessage=$(extract_from_preference_map diskSpaceWarningMessage)
defaultMessage=$(extract_from_preference_map message)
defaultInfobox=$(extract_from_preference_map infobox)
defaultHelpmessage=$(extract_from_preference_map helpmessage)
defaultHelpimage=$(extract_from_preference_map helpimage)
defaultStagedUpdateMessage=$(extract_from_preference_map stagedUpdateMessage)
defaultPartiallyStagedUpdateMessage=$(extract_from_preference_map partiallyStagedUpdateMessage)
defaultPendingDownloadMessage=$(extract_from_preference_map pendingDownloadMessage)
defaultButton1text=$(extract_from_preference_map button1text)
defaultButton2text=$(extract_from_preference_map button2text)
defaultInfobuttontext=$(extract_from_preference_map infobuttontext)
defaultOverlayiconURL=$(extract_from_preference_map organizationOverlayiconURL)
defaultSupportTeamName=$(extract_from_preference_map supportTeamName)
defaultSupportTeamPhone=$(extract_from_preference_map supportTeamPhone)
defaultSupportTeamEmail=$(extract_from_preference_map supportTeamEmail)
defaultSupportTeamWebsite=$(extract_from_preference_map supportTeamWebsite)
defaultSupportKB=$(extract_from_preference_map supportKB)
defaultInfobuttonaction=$(extract_from_preference_map infobuttonaction)
defaultSupportKBURL=$(extract_from_preference_map supportKBURL)

# Resolve Info button-related defaults to concrete values,
# mirroring runtime behavior in reminderDialog.zsh
supportKB="$defaultSupportKB"
eval "resolvedInfobuttonaction=\"${defaultInfobuttonaction}\""
infobuttonaction="$resolvedInfobuttonaction"
eval "resolvedSupportKBURL=\"${defaultSupportKBURL}\""
resolvedInfobuttontext="$defaultSupportKB"

# ---------------------------------------------------------------------
# Process strings
# ---------------------------------------------------------------------
title_xml=$(process "$defaultTitle")
excessiveUptimeWarningMessage_xml=$(process "$defaultExcessiveUptimeWarningMessage")
diskSpaceWarningMessage_xml=$(process "$defaultDiskSpaceWarningMessage")
stagedUpdateMessage_xml=$(process "${defaultStagedUpdateMessage}")
partiallyStagedUpdateMessage_xml=$(process "${defaultPartiallyStagedUpdateMessage}")
pendingDownloadMessage_xml=$(process "${defaultPendingDownloadMessage}")
message_xml=$(process "$defaultMessage")
infobox_xml=$(process "$defaultInfobox")
helpmessage_xml=$(process "$defaultHelpmessage")
helpimage_xml=$(process "$defaultHelpimage")
button1text_xml=$(process "$defaultButton1text")
button2text_xml=$(process "$defaultButton2text")

# Info button pieces use resolved defaults (already evaluated)
infobuttontext_xml=$(printf "%s" "$resolvedInfobuttontext" | xml_escape)

overlayicon_xml=$(process "$defaultOverlayiconURL")
supportTeamName_xml=$(process "$defaultSupportTeamName")
supportTeamPhone_xml=$(process "$defaultSupportTeamPhone")
supportTeamEmail_xml=$(process "$defaultSupportTeamEmail")
supportTeamWebsite_xml=$(process "$defaultSupportTeamWebsite")
supportKB_xml=$(process "$defaultSupportKB")

infobuttonaction_xml=$(printf "%s" "$resolvedInfobuttonaction" | xml_escape)
supportKBURL_xml=$(printf "%s" "$resolvedSupportKBURL" | xml_escape)

scriptLog_xml=$(echo "$scriptLog" | xml_escape)
dateFormat_xml=$(echo "$dateFormatDeadlineHumanReadable" | xml_escape)

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
    <key>MeetingDelay</key>
    <integer>${meetingDelay}</integer>
    <key>MinimumDiskFreePercentage</key>
    <integer>${minimumDiskFreePercentage}</integer>

    <!-- Branding -->
    <key>OrganizationOverlayIconURL</key>
    <string>${overlayicon_xml}</string>
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

    <!-- Dialog text -->
    <key>Title</key>
    <string>${title_xml}</string>
    <key>Button1Text</key>
    <string>${button1text_xml}</string>
    <key>Button2Text</key>
    <string>${button2text_xml}</string>
    <key>InfoButtonText</key>
    <string>${infobuttontext_xml}</string>
    <key>ExcessiveUptimeWarningMessage</key>
    <string>${excessiveUptimeWarningMessage_xml}</string>
    <key>DiskSpaceWarningMessage</key>
    <string>${diskSpaceWarningMessage_xml}</string>
    <key>StagedUpdateMessage</key>
    <string>${stagedUpdateMessage_xml}</string>
    <key>PartiallyStagedUpdateMessage</key>
    <string>${partiallyStagedUpdateMessage_xml}</string>
    <key>PendingDownloadMessage</key>
    <string>${pendingDownloadMessage_xml}</string>
    <key>HideStagedUpdateInfo</key>
    <false/>
    <key>Message</key>
    <string>${message_xml}</string>

    <!-- Infobox -->
    <key>InfoBox</key>
    <string>${infobox_xml}</string>

    <!-- Help section -->
    <key>HelpMessage</key>
    <string>${helpmessage_xml}</string>
    <key>HelpImage</key>
    <string>${helpimage_xml}</string>
</dict>
</plist>
EOF

echo "SUCCESS! plist generated:"
echo "   → $OUTPUT_PLIST_FILE"

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
                                <key>MeetingDelay</key>
                                <integer>${meetingDelay}</integer>
                                <key>MinimumDiskFreePercentage</key>
                                <integer>${minimumDiskFreePercentage}</integer>                                <key>OrganizationOverlayIconURL</key>
                                <string>${overlayicon_xml}</string>
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
                                <key>Title</key>
                                <string>${title_xml}</string>
                                <key>Button1Text</key>
                                <string>${button1text_xml}</string>
                                <key>Button2Text</key>
                                <string>${button2text_xml}</string>
                                <key>InfoButtonText</key>
                                <string>${infobuttontext_xml}</string>
                                <key>ExcessiveUptimeWarningMessage</key>
                                <string>${excessiveUptimeWarningMessage_xml}</string>
                                <key>DiskSpaceWarningMessage</key>
                                <string>${diskSpaceWarningMessage_xml}</string>
                                <key>StagedUpdateMessage</key>
                                <string>${stagedUpdateMessage_xml}</string>
                                <key>PartiallyStagedUpdateMessage</key>
                                <string>${partiallyStagedUpdateMessage_xml}</string>
                                <key>PendingDownloadMessage</key>
                                <string>${pendingDownloadMessage_xml}</string>
                                <key>HideStagedUpdateInfo</key>
                                <false/>
                                <key>Message</key>
                                <string>${message_xml}</string>
                                <key>InfoBox</key>
                                <string>${infobox_xml}</string>
                                <key>HelpMessage</key>
                                <string>${helpmessage_xml}</string>
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

echo "SUCCESS! mobileconfig generated:"
echo "   → ${OUTPUT_MOBILECONFIG_FILE}"
