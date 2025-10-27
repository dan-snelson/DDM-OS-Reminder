#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Automatically assemble the final DDM OS Reminder script by embedding the
# customized end-user message into ddmOSReminder.zsh by executing:
#
# zsh Resources/assembleDDMOSReminder.zsh
#
# Expected directory layout:
#   DDM-OS-Reminder/
#     ddmOSReminder.zsh
#     DDM-OS-Reminder End-user Message.zsh
#     Resources/assembleDDMOSReminder.zsh
#
# http://snelson.us/ddm-os-reminder
#
####################################################################################################

set -euo pipefail



####################################################################################################
#
# Variables
#
####################################################################################################

scriptDir="$(cd "$(dirname "${0}")" && pwd)"            # Resources/
parentDir="$(dirname "${scriptDir}")"                   # DDM-OS-Reminder/
baseScript="${parentDir}/ddmOSReminder.zsh"
messageScript="${parentDir}/DDM-OS-Reminder End-user Message.zsh"
timestamp="$(date '+%Y-%m-%d-%H%M%S')"
outputScript="${scriptDir}/ddmOSReminder.Assembled.${timestamp}.zsh"
tmpScript="${outputScript}.tmp"



####################################################################################################
#
# Program
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Display Header
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

echo "🧩 Assembling DDM OS Reminder"
echo "Resources dir:   ${scriptDir}"
echo "Base script:     ${baseScript}"
echo "Message script:  ${messageScript}"
echo "Output script:   ${outputScript}"
echo



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate Input Files
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

[[ -f "${baseScript}" ]]    || { echo "❌ Base script not found: ${baseScript}"; exit 1; }
[[ -f "${messageScript}" ]] || { echo "❌ Message script not found: ${messageScript}"; exit 1; }



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Insert End-user Message (with updateScriptLog patch)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

echo "🔧 Inserting end-user message …"

# Create a temp copy of the message with logging pipe commented out
patchedMessage=$(mktemp)
sed 's/| tee -a "\${scriptLog}"/# | tee -a "\${scriptLog}"/' "${messageScript}" > "${patchedMessage}"

{
    inBlock=false
    while IFS= read -r line; do
        if [[ $line == "cat <<'ENDOFSCRIPT'"* ]]; then
            echo "$line"
            cat "${patchedMessage}"
            inBlock=true
            continue
        fi
        if [[ $line == "ENDOFSCRIPT" ]]; then
            inBlock=false
        fi
        if [[ $inBlock == false ]]; then
            echo "$line"
        fi
    done < "${baseScript}"
} > "${tmpScript}"

rm -f "${patchedMessage}"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Verify Output and Permissions
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if grep -q "ENDOFSCRIPT" "${tmpScript}"; then
    mv "${tmpScript}" "${outputScript}"
    chmod +x "${outputScript}"
    echo "✅ Assembly complete [${timestamp}]"
    echo "   → ${outputScript}"
else
    echo "❌ Assembly failed — missing ENDOFSCRIPT markers."
    exit 1
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Syntax Check
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if zsh -n "${outputScript}" >/dev/null 2>&1; then
    echo "✅ Syntax check passed."
else
    echo "⚠️  Warning: syntax check failed!"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

echo "🏁 Done."
