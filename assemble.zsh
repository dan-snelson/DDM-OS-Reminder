#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Automatically assemble the final DDM OS Reminder script by embedding the
# customized end-user message (reminderDialog.zsh) into launchDaemonManagment.zsh by executing:
#
# zsh assemble.zsh
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
# http://snelson.us/ddm
#
####################################################################################################

set -euo pipefail

####################################################################################################
# Variables
####################################################################################################

projectDir="$(cd "$(dirname "${0}")" && pwd)"
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
