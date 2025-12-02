#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Automatically assemble the final DDM OS Reminder script by embedding the
# customized end-user message (reminderDialog.zsh) into launchDaemonManagment.zsh by executing:
#
#   zsh assemble.zsh
#
# Expected directory layout:
#   DDM-OS-Reminder/
#     assemble.zsh
#     launchDaemonManagment.zsh
#     reminderDialog.zsh
#     Resources/
#
# Output:
#     Resources/ddm-os-reminder-assembled-<timestamp>.zsh
#
# http://snelson.us/ddm-os-reminder
#
####################################################################################################

set -euo pipefail

####################################################################################################
# Variables
####################################################################################################

projectDir="$(cd "$(dirname "${0}")" && pwd)"            # DDM-OS-Reminder/
resourcesDir="${projectDir}/Resources"
baseScript="${projectDir}/launchDaemonManagment.zsh"
messageScript="${projectDir}/reminderDialog.zsh"
timestamp="$(date '+%Y-%m-%d-%H%M%S')"
outputScript="${resourcesDir}/ddm-os-reminder-assembled-${timestamp}.zsh"
tmpScript="${outputScript}.tmp"

####################################################################################################
# Header
####################################################################################################

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧩 Assembling DDM-OS-Reminder"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Working dir:     ${projectDir}"
echo "Resources dir:   ${resourcesDir}"
echo "Base script:     ${baseScript}"
echo "Message script:  ${messageScript}"
echo "Output script:   ${outputScript}"
echo

####################################################################################################
# Validate Input Files
####################################################################################################

[[ -f "${baseScript}" ]]    || { echo "❌ Base script not found: ${baseScript}"; exit 1; }
[[ -f "${messageScript}" ]] || { echo "❌ Message script not found: ${messageScript}"; exit 1; }
[[ -d "${resourcesDir}" ]]  || { echo "⚠️  Resources directory missing — creating it."; mkdir -p "${resourcesDir}"; }

####################################################################################################
# Insert End-user Message (with updateScriptLog patch)
####################################################################################################

echo "🔧 Inserting end-user message …"

patchedMessage=$(mktemp)
# Comment out any lines that append to ${scriptLog}
sed 's/| tee -a "\${scriptLog}"/# | tee -a "\${scriptLog}"/' "${messageScript}" > "${patchedMessage}"

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
  echo "✅ Assembly complete [${timestamp}]"
  echo "   → ${outputScript}"
else
  echo "❌ Assembly failed — missing ENDOFSCRIPT markers."
  exit 1
fi

####################################################################################################
# Syntax Check
####################################################################################################

if zsh -n "${outputScript}" >/dev/null 2>&1; then
  echo "✅ Syntax check passed."
else
  echo "⚠️  Warning: syntax check failed!"
fi

####################################################################################################
# Exit
####################################################################################################

echo "🏁 Done."
