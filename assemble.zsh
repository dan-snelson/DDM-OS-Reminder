#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Automatically assemble the final DDM OS Reminder script by embedding the
# customized end-user message (reminderDialog.zsh) into launchDaemonManagement.zsh by executing:
#
# zsh assemble.zsh
#
# Expected directory layout:
#   DDM-OS-Reminder/
#     assemble.zsh
#     launchDaemonManagement.zsh
#     reminderDialog.zsh
#     Resources/
#
# Output:
#     Artifacts/ddm-os-reminder-<reverseDomainNameNotation>-<timestamp>.zsh
#
# http://snelson.us/ddm
#
####################################################################################################



####################################################################################################
# Global Variables
####################################################################################################

set -euo pipefail
scriptVersion="2.4.0rc3"
projectDir="$(cd "$(dirname "${0}")" && pwd)"
resourcesDir="${projectDir}/Resources"
artifactsDir="${projectDir}/Artifacts"
baseScript="${projectDir}/launchDaemonManagement.zsh"
messageScript="${projectDir}/reminderDialog.zsh"
plistSample="${resourcesDir}/sample.plist"
timestamp="$(date '+%Y-%m-%d-%H%M%S')"
outputScript="${artifactsDir}/ddm-os-reminder-assembled-${timestamp}.zsh"
tmpScript="${outputScript}.tmp"

# RDNN / org script name (will be discovered and possibly overridden)
currentRDNN=""
currentOrgScriptName=""
newRDNN=""
newOrgScriptName=""

# Deployment mode (dev, test, prod)
deploymentMode="prod"  # default to production mode
modeSuffix=""
explicitProdMode=false  # track if --prod flag was explicitly used



####################################################################################################
# Header
####################################################################################################

echo
echo "==============================================================="
echo "🧩 Assemble DDM OS Reminder (${scriptVersion})"
echo "==============================================================="
echo
echo "Full Paths:"
echo
echo "        Reminder Dialog: ${messageScript}"
echo "LaunchDaemon Management: ${baseScript}"
echo "      Working Directory: ${projectDir}"
echo "    Resources Directory: ${resourcesDir}"
echo



####################################################################################################
# Validate Input Files
####################################################################################################

[[ -f "${baseScript}" ]]    || { echo "❌ Base script not found: ${baseScript}"; exit 1; }
[[ -f "${messageScript}" ]] || { echo "❌ Message script not found: ${messageScript}"; exit 1; }
[[ -f "${plistSample}" ]]   || { echo "❌ Sample .plist not found: ${plistSample}"; exit 1; }
[[ -d "${artifactsDir}" ]]  || { echo "⚠️ Artifacts directory missing — creating it."; mkdir -p "${artifactsDir}"; }



####################################################################################################
# RDNN Harmonization (no organizationScriptName prompting)
####################################################################################################

echo "🔍 Checking Reverse Domain Name Notation …"

currentRDNN_reminder="$(grep -E '^reverseDomainNameNotation=' "${messageScript}" 2>/dev/null | sed -E 's/^[^=]+="//; s/"$//')"
currentOrgScriptName_reminder="$(grep -E '^organizationScriptName=' "${messageScript}" 2>/dev/null | sed -E 's/^[^=]+="//; s/"$//')"

currentRDNN_base="$(grep -E '^reverseDomainNameNotation=' "${baseScript}" 2>/dev/null | sed -E 's/^[^=]+="//; s/"$//')"
currentOrgScriptName_base="$(grep -E '^organizationScriptName=' "${baseScript}" 2>/dev/null | sed -E 's/^[^=]+="//; s/"$//')"

echo
echo "    Reminder Dialog (reminderDialog.zsh):"
echo "        reverseDomainNameNotation = ${currentRDNN_reminder:-<not found>}"
echo "        organizationScriptName    = ${currentOrgScriptName_reminder:-<not found>}"
echo
echo "    LaunchDaemon Management (launchDaemonManagement.zsh):"
echo "        reverseDomainNameNotation = ${currentRDNN_base:-<not found>}"
echo "        organizationScriptName    = ${currentOrgScriptName_base:-<not found>}"
echo

# --- Reverse Domain Name Notation consistency handling ---
if [[ -z "${currentRDNN_reminder}" || -z "${currentRDNN_base}" ]]; then
  echo "⚠️  Could not detect reverseDomainNameNotation in one or both files."
  echo "    You will be prompted to enter a value manually."
  currentRDNN=""
elif [[ "${currentRDNN_reminder}" != "${currentRDNN_base}" ]]; then
  echo "⚠️  reverseDomainNameNotation values differ."
  echo "    Choose which value to use as the default:"
  echo "      1) ${currentRDNN_reminder}  (from reminderDialog.zsh)"
  echo "      2) ${currentRDNN_base}      (from launchDaemonManagement.zsh)"
  echo "      3) Enter custom value"
  printf "Selection [1/2/3]: "
  read -r choice

  case "${choice}" in
    1) currentRDNN="${currentRDNN_reminder}" ;;
    2) currentRDNN="${currentRDNN_base}" ;;
    3) currentRDNN="" ;;
    *)
      echo "❌ Invalid selection. Exiting."
      exit 1
      ;;
  esac
else
  currentRDNN="${currentRDNN_reminder}"
fi

echo

# Parse command-line arguments
# Usage: zsh assemble.zsh [RDNN] [--mode dev|test|prod] or [--dev|--test|--prod]
skipRDNNPrompt=false
skipModePrompt=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --mode)
      if [[ -n "${2:-}" ]] && [[ "${2}" =~ ^(dev|test|prod)$ ]]; then
        deploymentMode="${2}"
        skipModePrompt=true
        shift 2
      else
        echo "⚠️  Invalid mode: '${2:-}'. Valid options: dev, test, prod"
        echo "    Defaulting to interactive prompt."
        shift
      fi
      ;;
    --dev|--development)
      deploymentMode="dev"
      skipModePrompt=true
      shift
      ;;
    --test|--testing)
      deploymentMode="test"
      skipModePrompt=true
      shift
      ;;
    --prod|--production)
      deploymentMode="prod"
      explicitProdMode=true
      skipModePrompt=true
      shift
      ;;
    -*)
      echo "⚠️  Unknown flag: ${1}"
      shift
      ;;
    *)
      # Non-flag argument assumed to be RDNN
      if [[ -z "${newRDNN}" ]]; then
        echo "📥 RDNN provided via command-line argument: '${1}'"
        newRDNN="${1}"
        skipRDNNPrompt=true
      fi
      shift
      ;;
  esac
done

# Prompt ONLY if not provided via argument
if [[ "${skipRDNNPrompt}" == false ]]; then
  if [[ -n "${currentRDNN}" ]]; then
    read -r "?Enter Your Organization’s Reverse Domain Name Notation [${currentRDNN}] (or 'X' to exit): " userRDNN

    # Allow 'X' to exit
    if [[ "${userRDNN}" == [Xx] ]]; then
      echo "Exiting at user request."
      exit 0
    fi

    newRDNN="${userRDNN:-${currentRDNN}}"
  else
    read -r "?Enter Your Organization’s Reverse Domain Name Notation (or 'X' to exit): " newRDNN

    # Allow 'X' to exit
    if [[ "${newRDNN}" == [Xx] ]]; then
      echo "Exiting at user request."
      exit 0
    fi
  fi
fi

if ! [[ "${newRDNN}" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "❌ Invalid RDNN format."
  exit 1
fi

# Preserve the original organizationScriptName from reminderDialog for plist naming
newOrgScriptName="${currentOrgScriptName_reminder}"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Using '${newRDNN}' as the Reverse Domain Name Notation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo


####################################################################################################
# Deployment Mode Selection
####################################################################################################

# Prompt for deployment mode if not specified via CLI
if [[ "${skipModePrompt}" == false ]]; then
  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Select Deployment Mode:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "  1) Development  - Keep 'assembled' text for local testing"
  echo "  2) Testing      - Replace 'assembled' with 'TEST' for staging"
  echo "  3) Production   - Remove 'Sample' text for clean deployment"
  echo
  echo "  [Press 'X' to exit]"
  echo "  [Use --prod flag for clean output without replacement]"
  echo
  read -r "?Enter mode [1/2/3]: " modeChoice

  case "${modeChoice}" in
    1) deploymentMode="dev" ;;
    2) deploymentMode="test" ;;
    3)
      deploymentMode="prod"
      explicitProdMode=true
      ;;
    [Xx])
      echo "Exiting at user request."
      exit 0
      ;;
    *)
      echo "⚠️  Invalid selection. Defaulting to 'production' mode."
      deploymentMode="prod"
      ;;
  esac
fi

echo
echo "📦 Deployment Mode: ${deploymentMode}"

# Set mode suffix for artifact naming
case "${deploymentMode}" in
  dev)
    modeSuffix="-dev"
    ;;
  test)
    modeSuffix="-test"
    ;;
  prod)
    modeSuffix=""
    ;;
esac

echo



####################################################################################################
# Insert End-user Message
####################################################################################################

echo "🔧 Inserting ${messageScript##*/} into ${baseScript##*/}  …"

# patchedMessage=$(mktemp)
patchedMessage=$(mktemp -t patchedMessage)

# First: comment out any lines that append to ${scriptLog}
sed 's/| tee -a "\${scriptLog}"/# | tee -a "\${scriptLog}"/' "${messageScript}" \
    > "${patchedMessage}.stage1"

# Second: remove the Demo Mode block, including its leading separator
# and trailing blank lines, using awk (BSD-safe)
awk '
{
    line[NR] = $0
}
END {
    n = NR
    start = end = 0

    for (i = 1; i <= n; i++) {
        # Look for the separator line immediately before the Demo Mode header
        if (line[i] ~ /^# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #$/ &&
            line[i+1] ~ /^# Demo Mode \(i.e., zsh .* demo\)/) {

            start = i    # start removal at the separator

            # now find the closing "fi" for the demo block
            for (j = i+1; j <= n; j++) {
                if (line[j] ~ /^fi$/) {
                    end = j
                    # consume any trailing blank lines after fi
                    while (end + 1 <= n && line[end + 1] ~ /^[[:space:]]*$/) {
                        end++
                    }
                    break
                }
            }
            break
        }
    }

    for (i = 1; i <= n; i++) {
        if (start && end && i >= start && i <= end) {
            # skip demo block and its separator / trailing blanks
            continue
        }
        print line[i]
    }
}' "${patchedMessage}.stage1" > "${patchedMessage}"

rm -f "${patchedMessage}.stage1"

lastMessageLine=$(tail -n 1 "${patchedMessage}")
lastMessageTrimmed="${lastMessageLine//[[:space:]]/}"

{
  inBlock=false
  prevLine=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    prevTrimmed="${prevLine//[[:space:]]/}"

    if [[ $line == "cat <<'ENDOFSCRIPT'"* ]]; then
      echo "$line"
      cat "${patchedMessage}"
      inBlock=true
      continue
    fi

    if [[ $inBlock == false ]]; then
      echo "$line"
    elif [[ $line == "ENDOFSCRIPT" ]]; then
      if [[ -n "$lastMessageTrimmed" ]]; then
        echo ""
      fi
      printf "%s\n" "$line"
      inBlock=false
    fi

    prevLine="$line"
  done < "${baseScript}"
} > "${tmpScript}"

rm -f "${patchedMessage}"



####################################################################################################
# Verify Output and Permissions
####################################################################################################

if grep -q "ENDOFSCRIPT" "${tmpScript}"; then
  mv "${tmpScript}" "${outputScript}"
  chmod +x "${outputScript}"
  echo
  echo "✅ Assembly complete [${timestamp}]"
  echo "   → ${outputScript#$projectDir/}"
else
  echo "❌ Assembly failed — missing ENDOFSCRIPT markers."
  exit 1
fi



####################################################################################################
# Update RDNN in Assembled Script
####################################################################################################

echo
echo "🔁 Updating reverseDomainNameNotation to '${newRDNN}' in assembled script …"

sed -i.bak \
  -e "s|^reverseDomainNameNotation=\"[^\"]*\"|reverseDomainNameNotation=\"${newRDNN}\"|" \
  "${outputScript}"

rm -f "${outputScript}.bak" 2>/dev/null || true



####################################################################################################
# Syntax Check
####################################################################################################

echo
echo "🔍 Performing syntax check on '${outputScript#$projectDir/}' …"
if zsh -n "${outputScript}" >/dev/null 2>&1; then
  echo "    ✅ Syntax check passed."
else
  echo "    ⚠️  Warning: syntax check failed!"
fi



####################################################################################################
# Generate Plist Output
####################################################################################################

echo
echo "🗂  Generating LaunchDaemon plist …"
if [[ -f "${plistSample}" ]]; then
  plistOutput="${artifactsDir}/${newRDNN}.${newOrgScriptName}-${timestamp}${modeSuffix}.plist"

  echo "    🗂  Creating ${newRDNN}.${newOrgScriptName} plist from ${plistSample} …"
  cp "${plistSample}" "${plistOutput}"
  echo
  echo "    🔧 Updating internal plist content …"

  # Replace "sample" text based on deployment mode
  case "${deploymentMode}" in
    dev)
      echo "    ℹ️  Development mode: keeping 'sample' text unchanged"
      # No replacement needed
      ;;
    test)
      echo "    🧪 Testing mode: replacing 'sample' → 'TEST'"
      sed -i.bak 's/sample/TEST/gI' "${plistOutput}"
      ;;
    prod)
      if [[ "${explicitProdMode}" == true ]]; then
        echo "    🔓 Production mode (explicit): removing 'sample' text for clean deployment"
        # Remove "sample " (with trailing space), then standalone "sample"
        sed -i.bak -E -e 's/sample[[:space:]]+//gI' -e 's/sample//gI' "${plistOutput}"
      else
        echo "    🔒 Production mode: replacing 'sample' → 'assembled'"
        sed -i.bak 's/sample/assembled/gI' "${plistOutput}"
        echo "    ⚠️  REMINDER: You must customize all 'assembled' values before deployment!"
      fi
      ;;
  esac

  # Update XML comments
  sed -i '' \
    -e "s|<!-- Preferences Domain: .* -->|<!-- Preferences Domain: ${newRDNN}.${newOrgScriptName} -->|" \
    -e "s|<!-- Version: .* -->|<!-- Version: ${scriptVersion} -->|" \
    -e "s|<!-- Generated on: .* -->|<!-- Generated on: ${timestamp} -->|" \
    "${plistOutput}"

  # Update scriptLog
  sed -i '' -e '/<key>ScriptLog<\/key>/{
    N
    s|<key>ScriptLog</key>.*<string>/var/log/org\.churchofjesuschrist\.log</string>|<key>ScriptLog</key>\
    <string>/var/log/'${newRDNN}'.log</string>|
}' "$plistOutput"

  # Cleanup
  rm -f "${plistOutput}.bak" 2>/dev/null || true

  echo "   → ${plistOutput#$projectDir/}"

else
  echo "    ⚠️  ${plistSample} not found; skipping plist generation."
fi



####################################################################################################
# Generate mobileconfig from plist (no comments, no blank lines)
####################################################################################################

echo
echo "🧩 Generating Configuration Profile (.mobileconfig) …"

# Extract ONLY the inner <dict>…</dict> content
innerDict=$(
  sed -n '/<dict>/,/<\/dict>/p' "${plistOutput}" | sed '1d;$d'
)

# Remove XML comments and ALL blank/whitespace-only lines
innerDictCleaned=$(
  printf "%s\n" "$innerDict" \
    | sed 's/<!--.*-->//g' \
    | sed '/^[[:space:]]*$/d'
)

# Indent for embedding
indentedInnerDict=$(
  printf "%s\n" "$innerDictCleaned" \
    | sed 's/^/                                /'
)

# Generate UUIDs
payloadUUID=$(uuidgen)
profileUUID=$(uuidgen)

# Output filename
mobileconfigOutput="${artifactsDir}/${newRDNN}.${newOrgScriptName}-${timestamp}${modeSuffix}-unsigned.mobileconfig"

cat > "${mobileconfigOutput}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadContent</key>
            <dict>
                <key>${newRDNN}.${newOrgScriptName}</key>
                <dict>
                    <key>Forced</key>
                    <array>
                        <dict>
                            <key>mcx_preference_settings</key>
                            <dict>
${indentedInnerDict}
                            </dict>
                        </dict>
                    </array>
                </dict>
            </dict>
            <key>PayloadDisplayName</key>
            <string>Custom Settings</string>
            <key>PayloadIdentifier</key>
            <string>${payloadUUID}</string>
            <key>PayloadOrganization</key>
            <string>${newOrgScriptName}</string>
            <key>PayloadType</key>
            <string>com.apple.ManagedClient.preferences</string>
            <key>PayloadUUID</key>
            <string>${payloadUUID}</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
        </dict>
    </array>

    <key>PayloadDescription</key>
    <string>Configures DDM OS Reminder (${scriptVersion}) to ${newRDNN} standards. Created: ${timestamp}</string>
    <key>PayloadDisplayName</key>
    <string>DDM OS Reminder: ${newRDNN}</string>
    <key>PayloadEnabled</key>
    <true/>
    <key>PayloadIdentifier</key>
    <string>${profileUUID}</string>
    <key>PayloadOrganization</key>
    <string>${newOrgScriptName}</string>
    <key>PayloadRemovalDisallowed</key>
    <true/>
    <key>PayloadScope</key>
    <string>System</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>${profileUUID}</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
</dict>
</plist>
EOF

echo "   → ${mobileconfigOutput#$projectDir/}"



####################################################################################################
# Mobileconfig Syntax Check
####################################################################################################

echo
echo "🔍 Performing syntax check on '${mobileconfigOutput#$projectDir/}' …"
if /usr/bin/plutil -lint "${mobileconfigOutput}" >/dev/null 2>&1; then
  echo "    ✅ Profile syntax check passed."
else
  echo "    ⚠️  Warning: profile syntax check failed!"
fi



####################################################################################################
# Rename Assembled Script to Include RDNN
####################################################################################################

echo
echo "🔁 Renaming assembled script …"
newOutputScript="${artifactsDir}/ddm-os-reminder-${newRDNN}-${timestamp}${modeSuffix}.zsh"
mv "${outputScript}" "${newOutputScript}" || {
  echo "❌ Failed to rename assembled script."
  exit 1
}

# Update variable so subsequent steps (syntax check, etc.) target renamed file
outputScript="${newOutputScript}"



####################################################################################################
# Update scriptLog Based on RDNN (only change requested)
####################################################################################################

echo
echo "🔁 Updating scriptLog path based on RDNN …"

# Extract the first two components of the RDNN
topTwoRDNN="$(printf '%s' "${newRDNN}" | cut -d'.' -f1-2)"

# Replace only the Client-side Log definition
sed -i.bak \
  -e "s|^scriptLog=\"/var/log/.*\"|scriptLog=\"/var/log/${topTwoRDNN}.log\"|" \
  "${outputScript}"

rm -f "${outputScript}.bak" 2>/dev/null || true



####################################################################################################
# Exit
####################################################################################################

echo
echo "🏁 Done."
echo
echo "Deployment Artifacts:"
echo "        Assembled Script: ${newOutputScript#$projectDir/}"
echo "    Organizational Plist: ${plistOutput#$projectDir/}"
echo "   Configuration Profile: ${mobileconfigOutput#$projectDir/}"
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  Important Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

case "${deploymentMode}" in
  dev)
    echo "  Development Artifacts Generated:"
    echo "    - All 'sample' text preserved for testing"
    echo "    - Safe to deploy for local validation"
    echo "    - NOT suitable for production use"
    ;;
  test)
    echo "  Testing Artifacts Generated:"
    echo "    - All 'sample' text replaced with 'TEST'"
    echo "    - Suitable for staging/QA environments"
    echo "    - NOT suitable for production use"
    ;;
  prod)
    if [[ "${explicitProdMode}" == true ]]; then
      echo "  Production Artifacts Generated (Clean):"
      echo "    - All 'sample' text removed (empty strings)"
      echo "    - Ready for deployment with your custom values"
      echo "    - Ensure you've customized the source files before assembly"
    else
      echo "  Production Artifacts Generated:"
      echo "    - All 'sample' text replaced with 'assembled'"
      echo
      echo "  ⚠️  REQUIRED ACTION:"
      echo "    1. Open the generated .plist or .mobileconfig file"
      echo "    2. Search for 'assembled' (case-insensitive)"
      echo "    3. Replace each instance with your organization's values:"
      echo "         - Support team name, phone, email, website"
      echo "         - Button labels and dialog messages"
      echo "    4. Deploy only after ALL 'assembled' values are customized"
      echo
      echo "  Files to review:"
      echo "    - ${plistOutput#$projectDir/}"
      echo "    - ${mobileconfigOutput#$projectDir/}"
    fi
    ;;
esac

echo
echo "==============================================================="
echo
exit 0