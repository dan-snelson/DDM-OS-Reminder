#!/bin/zsh --no-rcs
# shellcheck shell=bash
#
# createPlist.zsh — Generate default plist from reminderDialog.zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/../reminderDialog.zsh"

[[ -f "$SOURCE_SCRIPT" ]] || { echo "ERROR: Cannot find reminderDialog.zsh"; exit 1; }

reverseDomainNameNotation=$(awk -F'"' '/^reverseDomainNameNotation=/{print $2}' "$SOURCE_SCRIPT")
organizationScriptName=$(awk -F'"' '/^organizationScriptName=/{print $2}' "$SOURCE_SCRIPT")

datestamp=$(date '+%Y-%m-%d-%H%M%S')
OUTPUT_FILE="${SCRIPT_DIR}/${reverseDomainNameNotation}.${organizationScriptName}-${datestamp}.plist"

echo "Generating default plist → $OUTPUT_FILE"

# ─────────────────────────────────────────────────────────────
# Extract default value
# ─────────────────────────────────────────────────────────────
extract_default() {
    local name=$1
    local line
    line=$(grep -m1 "[[:space:]]*local[[:space:]]\+${name}=" "$SOURCE_SCRIPT") || {
        echo "ERROR: Missing 'local ${name}=' in reminderDialog.zsh" >&2
        exit 1
    }

    # Extract the fallback value inside ${...:-"..." } or plain "value"
    if [[ $line =~ '\$\{[^}]+:-\ ?"([^"]+)"' ]]; then
        echo "${match[1]}"
    elif [[ $line =~ '"([^"]+)"' ]]; then
        echo "${match[1]}"
    else
        echo "ERROR: Cannot extract default for $name" >&2
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

        # ${titleMessageUpdateOrUpgrade:l} -> {titleMessageUpdateOrUpgrade}
        s/\$\{titleMessageUpdateOrUpgrade:l\}/{titleMessageUpdateOrUpgrade}/g;

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
# Extract globals
# ─────────────────────────────────────────────────────────────
scriptLog=$(awk -F'"' '/^scriptLog=/{print $2}' "$SOURCE_SCRIPT")
daysBeforeDeadlineDisplayReminder=$(awk -F'"' '/^daysBeforeDeadlineDisplayReminder=/{print $2}' "$SOURCE_SCRIPT")
daysBeforeDeadlineBlurscreen=$(awk -F'"' '/^daysBeforeDeadlineBlurscreen=/{print $2}' "$SOURCE_SCRIPT")
meetingDelay=$(awk -F'"' '/^meetingDelay=/{print $2}' "$SOURCE_SCRIPT")
dateFormatDeadlineHumanReadable=$(awk -F'"' '/^dateFormatDeadlineHumanReadable=/{print $2}' "$SOURCE_SCRIPT")
swapOverlayAndLogo_raw=$(awk -F'"' '/^swapOverlayAndLogo=/{print $2}' "$SOURCE_SCRIPT")

case "${swapOverlayAndLogo_raw:u}" in
    YES|TRUE|1) swapOverlayAndLogo_xml="<true/>" ;;
    *)          swapOverlayAndLogo_xml="<false/>" ;;
esac

# ─────────────────────────────────────────────────────────────
# Extract all defaults
# ─────────────────────────────────────────────────────────────
defaultTitle=$(extract_default defaultTitle)
defaultMessage=$(extract_default defaultMessage)
defaultInfobox=$(extract_default defaultInfobox)
defaultHelpmessage=$(extract_default defaultHelpmessage)
defaultHelpimage=$(extract_default defaultHelpimage)
defaultButton1text=$(extract_default defaultButton1text)
defaultButton2text=$(extract_default defaultButton2text)
defaultInfobuttontext=$(extract_default defaultInfobuttontext)
defaultOverlayiconURL=$(extract_default defaultOverlayiconURL)
defaultSupportTeamName=$(extract_default defaultSupportTeamName)
defaultSupportTeamPhone=$(extract_default defaultSupportTeamPhone)
defaultSupportTeamEmail=$(extract_default defaultSupportTeamEmail)
defaultSupportTeamWebsite=$(extract_default defaultSupportTeamWebsite)
defaultSupportKB=$(extract_default defaultSupportKB)
defaultInfobuttonaction=$(extract_default defaultInfobuttonaction)
defaultSupportKBURL=$(extract_default defaultSupportKBURL)

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
cat > "$OUTPUT_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Logging -->
	<key>ScriptLog</key>
	<string>${scriptLog_xml}</string>

	<!-- Reminder timing -->
	<key>DaysBeforeDeadlineDisplayReminder</key>
	<integer>${daysBeforeDeadlineDisplayReminder}</integer>
	<key>DaysBeforeDeadlineBlurscreen</key>
	<integer>${daysBeforeDeadlineBlurscreen}</integer>
	<key>MeetingDelay</key>
	<integer>${meetingDelay}</integer>

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
echo "   → $OUTPUT_FILE"