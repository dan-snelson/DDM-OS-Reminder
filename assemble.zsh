#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Automatically assemble the final DDM OS Reminder script by embedding the
# customized end-user message (reminderDialog.zsh) into launchDaemonManagement.zsh by executing:
#
# zsh assemble.zsh --help
#
# Common usage examples:
#   zsh assemble.zsh us.snelson --lane prod
#   zsh assemble.zsh us.snelson --lane prod --interactive
#   zsh assemble.zsh /path/to/previous-config.plist
#
# Expected directory layout:
#   DDM-OS-Reminder/
#     assemble.zsh
#     launchDaemonManagement.zsh
#     reminderDialog.zsh
#     Resources/sample.plist
#
# Output:
#     Artifacts/ddm-os-reminder-<reverseDomainNameNotation>-<timestamp>[-dev|-test|-prod].zsh
#     Artifacts/<reverseDomainNameNotation>.<organizationScriptName>-<timestamp>[-dev|-test|-prod].plist
#     Artifacts/<reverseDomainNameNotation>.<organizationScriptName>-<timestamp>[-dev|-test|-prod]-unsigned.mobileconfig
#
# http://snelson.us/ddm
#
####################################################################################################



####################################################################################################
# Global Variables
####################################################################################################

set -euo pipefail
autoload -Uz is-at-least
scriptVersion="3.0.0b4"
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
resolvedScriptLogPath=""

# Deployment mode (dev, test, prod)
deploymentMode="prod"  # default to production mode
modeSuffix=""
interactiveMode=false
priorPlistPath=""
priorPlistImported=false
priorPlistPrompted=false
rdnnInferredFromPriorPlist=false
modeInferredFromPriorPlist=false
interactiveConfigurationHeaderShown=false

placeholderMarker="Assembled"
legacyPlaceholderMarker="Sample"

# IT Support, Branding & Restart Policy (interactive prompts)
supportTeamName=""
supportTeamPhone=""
supportTeamEmail=""
supportTeamWebsite=""
supportKB=""
infoButtonAction=""
supportKBURL=""
infoButtonText=""
enableKnowledgeBase="true"
organizationOverlayIconURL=""
organizationOverlayIconURLdark=""
swapOverlayAndLogo=""
pastDeadlineRestartBehavior=""
daysPastDeadlineRestartWorkflow=""



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
# Usage: zsh assemble.zsh [RDNN|prior-plist] [--lane dev|test|prod] [--interactive] [--help]
skipRDNNPrompt=false
skipModePrompt=false

function normalizePathInput() {
  local rawValue="${1}"

  if (( ${#rawValue} >= 2 )); then
    if [[ "${rawValue[1]}" == "'" && "${rawValue[-1]}" == "'" ]]; then
      rawValue="${rawValue[2,-2]}"
    elif [[ "${rawValue[1]}" == "\"" && "${rawValue[-1]}" == "\"" ]]; then
      rawValue="${rawValue[2,-2]}"
    fi
  fi

  echo "${rawValue}"
}

function isPriorPlistArgument() {
  local candidateValue="${1}"

  [[ "${candidateValue:l}" == *.plist ]]
}

function validatePriorPlistPath() {
  local candidatePath="${1}"
  local preferencesDomainComment=""
  local versionComment=""
  local versionCore=""
  local scriptLogValue=""
  local requiredKey=""
  local -a missingRequiredKeys

  if [[ ! -e "${candidatePath}" ]]; then
    echo "❌ Prior plist not found: ${candidatePath}" >&2
    return 1
  fi

  if [[ ! -r "${candidatePath}" ]]; then
    echo "❌ Prior plist is not readable: ${candidatePath}" >&2
    return 1
  fi

  if ! /usr/bin/plutil -lint "${candidatePath}" >/dev/null 2>&1; then
    echo "❌ Prior plist is invalid: ${candidatePath}" >&2
    return 1
  fi

  for requiredKey in ScriptLog SupportTeamName SupportKBURL InfoButtonText Message HelpMessage; do
    if ! /usr/libexec/PlistBuddy -c "Print :${requiredKey}" "${candidatePath}" >/dev/null 2>&1; then
      missingRequiredKeys+=("${requiredKey}")
    fi
  done

  if (( ${#missingRequiredKeys[@]} > 0 )); then
    echo "❌ Prior plist does not appear to be a DDM OS Reminder plist; missing required keys: ${(j:, :)missingRequiredKeys}" >&2
    return 1
  fi

  scriptLogValue="$(
    /usr/libexec/PlistBuddy -c "Print :ScriptLog" "${candidatePath}" 2>/dev/null || true
  )"

  if [[ -z "${scriptLogValue}" || "${scriptLogValue:t}" != *.log ]]; then
    echo "❌ Prior plist does not contain a valid DDM OS Reminder ScriptLog path" >&2
    return 1
  fi

  preferencesDomainComment="$(
    /usr/bin/sed -n 's#^[[:space:]]*<!--[[:space:]]*Preferences Domain:[[:space:]]*\(.*\)[[:space:]]*-->[[:space:]]*$#\1#p' "${candidatePath}" \
      | /usr/bin/head -n 1
  )"
  preferencesDomainComment="$(
    printf "%s\n" "${preferencesDomainComment}" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
  )"

  if [[ -n "${preferencesDomainComment}" && "${preferencesDomainComment}" != *".${currentOrgScriptName_reminder}" ]]; then
    echo "❌ Prior plist metadata does not match a DDM OS Reminder preferences domain: ${preferencesDomainComment}" >&2
    return 1
  fi

  versionComment="$(
    /usr/bin/sed -n 's#^[[:space:]]*<!--[[:space:]]*Version:[[:space:]]*\(.*\)[[:space:]]*-->[[:space:]]*$#\1#p' "${candidatePath}" \
      | /usr/bin/head -n 1
  )"
  versionComment="$(
    printf "%s\n" "${versionComment}" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
  )"

  if [[ -z "${versionComment}" ]]; then
    echo "⚠️  Prior plist is missing version metadata; continuing with documented 2.2.0+ compatibility on a best-effort basis" >&2
    echo "${candidatePath}"
    return 0
  fi

  versionCore="$(
    printf "%s\n" "${versionComment}" | /usr/bin/sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p'
  )"

  if [[ -z "${versionCore}" ]]; then
    echo "⚠️  Prior plist version metadata is not recognized ('${versionComment}'); continuing with best-effort import" >&2
    echo "${candidatePath}"
    return 0
  fi

  if ! is-at-least 2.2.0 "${versionCore}"; then
    echo "⚠️  Prior plist version '${versionComment}' predates the documented 2.2.0+ compatibility baseline; continuing with best-effort import" >&2
  fi

  echo "${candidatePath}"
}

function inferRDNNFromPriorPlist() {
  local plistPath="${1}"
  local importedScriptLog=""
  local inferredRDNN=""
  local plistFilename=""

  importedScriptLog="$(
    /usr/libexec/PlistBuddy -c "Print :ScriptLog" "${plistPath}" 2>/dev/null || true
  )"

  if [[ -n "${importedScriptLog}" && "${importedScriptLog:t}" == *.log ]]; then
    inferredRDNN="${${importedScriptLog:t}%.log}"
  fi

  if [[ -z "${inferredRDNN}" ]]; then
    plistFilename="${plistPath:t}"
    if [[ "${plistFilename}" == *".${currentOrgScriptName_reminder}-"* ]]; then
      inferredRDNN="${plistFilename%%.${currentOrgScriptName_reminder}-*}"
    fi
  fi

  if [[ -n "${inferredRDNN}" ]] && [[ "${inferredRDNN}" =~ ^[A-Za-z0-9.-]+$ ]]; then
    echo "${inferredRDNN}"
  fi
}

function inferDeploymentModeFromPriorPlist() {
  local plistFilename="${1:t:l}"

  case "${plistFilename}" in
    *-dev.plist)  echo "dev" ;;
    *-test.plist) echo "test" ;;
    *-prod.plist) echo "prod" ;;
  esac
}

function showInteractiveConfigurationHeader() {
  if [[ "${interactiveConfigurationHeaderShown}" == true ]]; then
    return
  fi

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Interactive Configuration"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  interactiveConfigurationHeaderShown=true
}

function applyPriorPlistSelections() {
  local plistPath="${1}"
  local inferredRDNN=""
  local inferredDeploymentMode=""

  priorPlistPath="${plistPath}"
  priorPlistImported=true

  echo
  echo "ℹ️  Importing supported values from: ${priorPlistPath}"

  if [[ -z "${newRDNN}" || "${rdnnInferredFromPriorPlist}" == true ]]; then
    inferredRDNN="$(inferRDNNFromPriorPlist "${priorPlistPath}")"
    if [[ -n "${inferredRDNN}" ]]; then
      echo "🔎 Inferred RDNN from prior plist: '${inferredRDNN}'"
      newRDNN="${inferredRDNN}"
      skipRDNNPrompt=true
      rdnnInferredFromPriorPlist=true
    fi
  fi

  if [[ "${skipModePrompt}" == false ]]; then
    inferredDeploymentMode="$(inferDeploymentModeFromPriorPlist "${priorPlistPath}")"
    if [[ -n "${inferredDeploymentMode}" ]]; then
      deploymentMode="${inferredDeploymentMode}"
      skipModePrompt=true
      modeInferredFromPriorPlist=true
      echo "🔎 Inferred deployment mode from prior plist: '${deploymentMode}'"
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h)
      echo
      echo "Usage:"
      echo "  zsh assemble.zsh [RDNN|prior-plist] [--lane dev|test|prod] [--interactive] [--help]"
      echo
      echo "Options:"
      echo "  --lane <dev|test|prod>       Select deployment mode"
      echo "  --interactive                Prompt for optional prior .plist import, IT support, branding and restart policy values"
      echo "  prior-plist                  Auto-enables interactive mode and infers RDNN and deployment mode from the provided .plist"
      echo "  --help, -h                   Show this help"
      echo
      exit 0
      ;;
    --interactive)
      interactiveMode=true
      shift
      ;;
    --lane)
      if [[ -n "${2:-}" ]] && [[ "${2}" =~ ^(dev|test|prod)$ ]]; then
        deploymentMode="${2}"
        skipModePrompt=true
        modeInferredFromPriorPlist=false
        shift 2
      else
        echo "⚠️  Invalid lane: '${2:-}'. Valid options: dev, test, prod"
        echo "    Defaulting to interactive prompt."
        shift
      fi
      ;;
    -*)
      echo "⚠️  Unknown flag: ${1}"
      shift
      ;;
    *)
      positionalArgument="$(normalizePathInput "${1}")"

      if [[ -z "${priorPlistPath}" ]] && isPriorPlistArgument "${positionalArgument}"; then
        priorPlistPath="$(validatePriorPlistPath "${positionalArgument}")" || exit 1
        interactiveMode=true
        priorPlistPrompted=true

        echo "📥 Prior plist provided via command-line argument: '${priorPlistPath}'"
        applyPriorPlistSelections "${priorPlistPath}"
      elif [[ -z "${newRDNN}" || "${rdnnInferredFromPriorPlist}" == true ]]; then
        echo "📥 RDNN provided via command-line argument: '${positionalArgument}'"
        newRDNN="${positionalArgument}"
        skipRDNNPrompt=true
        rdnnInferredFromPriorPlist=false
      fi
      shift
      ;;
  esac
done



####################################################################################################
# Optional Interactive Prompts (IT Support, Branding & Restart Policy)
####################################################################################################

function rdnnToDomain() {
  local rdnnValue="${1}"
  local -a parts reversed
  local domainValue=""

  parts=(${(s:.:)rdnnValue})

  if (( ${#parts[@]} == 0 )); then
    echo ""
    return
  fi

  for (( i=${#parts[@]}; i>=1; i-- )); do
    reversed+=("${parts[i]}")
  done

  domainValue="${(j:.:)reversed}"
  echo "${domainValue}"
}

function promptWithDefault() {
  local promptText="${1}"
  local defaultValue="${2}"
  local variableName="${3}"
  local inputValue=""

  read -r "?${promptText} [${defaultValue}] (or ‘X’ to exit): " inputValue

  if [[ "${inputValue}" == [Xx] ]]; then
    echo "Exiting at user request."
    exit 0
  fi

  if [[ -z "${inputValue}" ]]; then
    inputValue="${defaultValue}"
  fi

  typeset -g "${variableName}=${inputValue}"
}

function normalizeBoolean() {
  local value="${1}"

  case "${value:l}" in
    1|true|yes|y) echo "true" ;;
    0|false|no|n) echo "false" ;;
    *)            echo "" ;;
  esac
}

function normalizePastDeadlineRestartBehavior() {
  local value="${1}"
  local normalizedValue="${value//[[:space:]]/}"

  case "${normalizedValue:l}" in
    off)    echo "Off" ;;
    prompt|p) echo "Prompt" ;;
    force|f)  echo "Force" ;;
    *)      echo "" ;;
  esac
}

function escapeSedReplacement() {
  local escapedValue="${1}"

  escapedValue="${escapedValue//\\/\\\\}"
  escapedValue="${escapedValue//&/\\&}"
  escapedValue="${escapedValue//|/\\|}"

  echo "${escapedValue}"
}

function promptForPriorPlistImport() {
  local candidatePath=""
  local validatedPath=""

  priorPlistPrompted=true
  showInteractiveConfigurationHeader

  while true; do
    read -r "?Drag-and-drop an earlier DOR .plist to import [Return to skip] (or ‘X’ to exit): " candidatePath

    if [[ "${candidatePath}" == [Xx] ]]; then
      echo "Exiting at user request."
      exit 0
    fi

    candidatePath="$(normalizePathInput "${candidatePath}")"

    if [[ -z "${candidatePath}" ]]; then
      priorPlistPath=""
      priorPlistImported=false
      return
    fi

    if ! validatedPath="$(validatePriorPlistPath "${candidatePath}")"; then
      continue
    fi

    applyPriorPlistSelections "${validatedPath}"
    return
  done
}

function emitSupportedPlistPreferenceTypes() {
  if [[ ! -x /usr/bin/perl ]]; then
    echo "❌ /usr/bin/perl is required to inspect supported preference types during plist import" >&2
    return 1
  fi

  /usr/bin/perl -ne '
    if (/^declare -A preferenceConfiguration=\(/) { $section = "pref"; next }
    if (/^declare -A plistKeyMap=\(/) { $section = "map"; next }
    if (/^\)$/) { $section = ""; next }

    if ($section eq "pref" && /^\s*\["([^"]+)"\]="([^|"]+)\|/) {
      $preferenceTypeByConfigKey{$1} = $2;
      next;
    }

    if ($section eq "map" && /^\s*\["([^"]+)"\]="([^"]+)"/) {
      $plistKeyByConfigKey{$1} = $2;
      next;
    }

    END {
      for my $configKey (sort keys %preferenceTypeByConfigKey) {
        my $plistKey = exists $plistKeyByConfigKey{$configKey}
          ? $plistKeyByConfigKey{$configKey}
          : $configKey;
        print "$plistKey|$preferenceTypeByConfigKey{$configKey}\n";
      }
    }
  ' "${messageScript}"
}

function extractPlistKeys() {
  local plistPath="${1}"

  sed -n 's/^[[:space:]]*<key>\([^<]*\)<\/key>[[:space:]]*$/\1/p' "${plistPath}"
}

function writePreferenceOverride() {
  local plistPath="${1}"
  local plistKey="${2}"
  local preferenceType="${3}"
  local preferenceValue="${4}"
  local normalizedBoolean=""

  case "${preferenceType}" in
    numeric)
      if [[ "${preferenceValue}" == <-> ]]; then
        /usr/bin/plutil -replace "${plistKey}" -integer "${preferenceValue}" "${plistPath}"
      else
        echo "    ⚠️  Skipping invalid integer value '${preferenceValue}' for ${plistKey}"
      fi
      ;;
    boolean)
      normalizedBoolean="$(normalizeBoolean "${preferenceValue}")"
      if [[ -n "${normalizedBoolean}" ]]; then
        /usr/bin/plutil -replace "${plistKey}" -bool "${normalizedBoolean}" "${plistPath}"
      else
        echo "    ⚠️  Skipping invalid boolean value '${preferenceValue}' for ${plistKey}"
      fi
      ;;
    string|*)
      /usr/bin/plutil -replace "${plistKey}" -string "${preferenceValue}" "${plistPath}"
      ;;
  esac
}

function preferenceTypeForPlistKey() {
  local targetKey="${1}"
  shift

  local preferenceLine=""
  local candidateKey=""
  local candidateType=""

  for preferenceLine in "$@"; do
    candidateKey="${preferenceLine%%|*}"
    candidateType="${preferenceLine#*|}"

    if [[ "${candidateKey}" == "${targetKey}" ]]; then
      echo "${candidateType}"
      return 0
    fi
  done

  return 1
}

function applyImportedPreferences() {
  local sourcePlist="${1}"
  local targetPlist="${2}"
  local importedKey=""
  local importedValue=""
  local preferenceType=""
  local preferenceLine=""
  local candidateKey=""
  local -a supportedPreferenceLines
  local -A unsupportedImportedKeySet
  local -a unsupportedImportedKeys

  supportedPreferenceLines=("${(@f)$(emitSupportedPlistPreferenceTypes)}")

  while IFS= read -r importedKey; do
    [[ -z "${importedKey}" ]] && continue
    if ! preferenceType="$(preferenceTypeForPlistKey "${importedKey}" "${supportedPreferenceLines[@]}")"; then
      unsupportedImportedKeySet["${importedKey}"]=1
    fi
  done < <(extractPlistKeys "${sourcePlist}")

  if (( ${#unsupportedImportedKeySet[@]} > 0 )); then
    unsupportedImportedKeys=("${(@ok)unsupportedImportedKeySet}")
    echo "    ⚠️  Ignoring unsupported imported keys: ${(j:, :)unsupportedImportedKeys}"
  fi

  for preferenceLine in "${supportedPreferenceLines[@]}"; do
    candidateKey="${preferenceLine%%|*}"
    preferenceType="${preferenceLine#*|}"
    importedKey="${candidateKey}"

    if ! /usr/libexec/PlistBuddy -c "Print :${importedKey}" "${sourcePlist}" >/dev/null 2>&1; then
      continue
    fi

    importedValue="$(
      /usr/libexec/PlistBuddy -c "Print :${importedKey}" "${sourcePlist}" 2>/dev/null
    )"

    if [[ "${importedKey}" == "ScriptLog" ]]; then
      if [[ "${importedValue:t}" == "${newRDNN}.log" ]]; then
        resolvedScriptLogPath="${importedValue}"
        echo "    ℹ️  Preserving imported ScriptLog: ${resolvedScriptLogPath}"
      else
        echo "    ⚠️  Imported ScriptLog basename '${importedValue:t}' does not match '${newRDNN}.log'; using ${resolvedScriptLogPath}"
      fi
      continue
    fi

    writePreferenceOverride "${targetPlist}" "${importedKey}" "${preferenceType}" "${importedValue}"
  done

  /usr/bin/plutil -replace ScriptLog -string "${resolvedScriptLogPath}" "${targetPlist}"
}

if [[ "${interactiveMode}" == true && "${priorPlistPrompted}" == false ]]; then
  promptForPriorPlistImport
fi

# Prompt ONLY if not provided via argument or inferred from a prior plist
if [[ "${skipRDNNPrompt}" == false ]]; then
  if [[ -n "${currentRDNN}" ]]; then
    read -r "?Enter Your Organization’s Reverse Domain Name Notation [${currentRDNN}] (or ‘X’ to exit): " userRDNN

    if [[ "${userRDNN}" == [Xx] ]]; then
      echo "Exiting at user request."
      exit 0
    fi

    newRDNN="${userRDNN:-${currentRDNN}}"
  else
    read -r "?Enter Your Organization’s Reverse Domain Name Notation (or ‘X’ to exit): " newRDNN

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
resolvedScriptLogPath="/var/log/${newRDNN}.log"

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Using '${newRDNN}' as the Reverse Domain Name Notation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

if [[ "${interactiveMode}" == true ]]; then
  derivedDomain="$(rdnnToDomain "${newRDNN}")"
  if [[ -z "${derivedDomain}" ]]; then
    derivedDomain="company.com"
  fi

  if [[ "${priorPlistPrompted}" == false ]]; then
    promptForPriorPlistImport
  fi

  if [[ "${priorPlistImported}" == true ]]; then
    echo ""
    echo "ℹ️  Prior plist supplied; skipping IT support, branding and restart policy prompts."
    echo ""
  else

    showInteractiveConfigurationHeader
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "IT Support, Branding & Restart Policy (Interactive)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    defaultSupportTeamName="IT Support"
    defaultSupportTeamPhone="+1 (801) 555-1212"
    defaultSupportTeamEmail="rescue@${derivedDomain}"
    defaultSupportTeamWebsite="https://support.${derivedDomain}"
    defaultEnableKnowledgeBase="YES"
    defaultSupportKB="Update macOS on Mac"
    defaultInfoButtonAction="${defaultSupportTeamWebsite}"
    defaultSupportKBURL="[Update macOS on Mac](${defaultInfoButtonAction})"
    defaultOrganizationOverlayIconURL="https://use2.ics.services.jamfcloud.com/icon/hash_2d64ce7f0042ad68234a2515211adb067ad6714703dd8ebd6f33c1ab30354b1d"
    defaultOrganizationOverlayIconURLdark="https://use2.ics.services.jamfcloud.com/icon/hash_d3a3bc5e06d2db5f9697f9b4fa095bfecb2dc0d22c71aadea525eb38ff981d39"
    defaultSwapOverlayAndLogo="NO"
    defaultPastDeadlineRestartBehavior="Off"
    defaultDaysPastDeadlineRestartWorkflow="2"

    promptWithDefault "Support Team Name" "${defaultSupportTeamName}" "supportTeamName"
    promptWithDefault "Support Team Phone" "${defaultSupportTeamPhone}" "supportTeamPhone"
    promptWithDefault "Support Team Email" "${defaultSupportTeamEmail}" "supportTeamEmail"
    promptWithDefault "Support Team Website" "${defaultSupportTeamWebsite}" "supportTeamWebsite"
    promptWithDefault "Knowledge Base ('YES' to specify; 'NO' to hide)" "${defaultEnableKnowledgeBase}" "enableKnowledgeBase"
    enableKnowledgeBase="$(normalizeBoolean "${enableKnowledgeBase}")"
    if [[ -z "${enableKnowledgeBase}" ]]; then
      echo "⚠️  Invalid input for Knowledge Base prompt; defaulting to ${defaultEnableKnowledgeBase}"
      enableKnowledgeBase="$(normalizeBoolean "${defaultEnableKnowledgeBase}")"
    fi

    if [[ "${enableKnowledgeBase}" == "true" ]]; then
      promptWithDefault "Support KB Title" "${defaultSupportKB}" "supportKB"

      supportKbSlug="${supportKB// /-}"
      defaultInfoButtonAction="${supportTeamWebsite}/${supportKbSlug}"
      promptWithDefault "Info Button Action" "${defaultInfoButtonAction}" "infoButtonAction"

      defaultSupportKBURL="[${supportKB}](${infoButtonAction})"
      promptWithDefault "Support KB Markdown Link" "${defaultSupportKBURL}" "supportKBURL"

      infoButtonText="${supportKB}"
    else
      supportKB=""
      infoButtonAction=""
      supportKBURL=""
      infoButtonText="hide"
      echo ""
      echo "ℹ️  Knowledge Base features disabled; hiding 'infobutton', KB row in 'helpmessage' and QR help image."
      echo ""
    fi

    promptWithDefault "Overlay Icon URL (Light)" "${defaultOrganizationOverlayIconURL}" "organizationOverlayIconURL"
    promptWithDefault "Overlay Icon URL (Dark)" "${defaultOrganizationOverlayIconURLdark}" "organizationOverlayIconURLdark"

    promptWithDefault "Swap Overlay and Logo (YES/NO)" "${defaultSwapOverlayAndLogo}" "swapOverlayAndLogo"
    swapOverlayAndLogo="$(normalizeBoolean "${swapOverlayAndLogo}")"
    if [[ -z "${swapOverlayAndLogo}" ]]; then
      echo "⚠️  Invalid input for SwapOverlayAndLogo; defaulting to ${defaultSwapOverlayAndLogo}"
      swapOverlayAndLogo="$(normalizeBoolean "${defaultSwapOverlayAndLogo}")"
    fi

    while true; do
      promptWithDefault "Past-deadline Restart Behavior (Off / [P]rompt / [F]orce)" "${defaultPastDeadlineRestartBehavior}" "pastDeadlineRestartBehavior"
      normalizedPastDeadlineRestartBehavior="$(normalizePastDeadlineRestartBehavior "${pastDeadlineRestartBehavior}")"
      if [[ -n "${normalizedPastDeadlineRestartBehavior}" ]]; then
        pastDeadlineRestartBehavior="${normalizedPastDeadlineRestartBehavior}"
        break
      fi
      echo "⚠️  Invalid input for PastDeadlineRestartBehavior; valid values: Off, Prompt (or P), Force (or F)."
    done

    if [[ "${pastDeadlineRestartBehavior}" != "Off" ]]; then
      while true; do
        promptWithDefault "Days Past Deadline Before Restart Workflow (0-999)" "${defaultDaysPastDeadlineRestartWorkflow}" "daysPastDeadlineRestartWorkflow"
        if [[ "${daysPastDeadlineRestartWorkflow}" == <-> ]] && (( daysPastDeadlineRestartWorkflow >= 0 && daysPastDeadlineRestartWorkflow <= 999 )); then
          break
        fi
        echo "⚠️  Invalid input for DaysPastDeadlineRestartWorkflow; enter an integer from 0 to 999."
      done
    fi
  fi
fi



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
  echo "  1) Development - Keep placeholder text for local testing"
  echo "  2) Testing     - Replace placeholder text with 'TEST' for staging"
  echo "  3) Production  - Remove placeholder text for clean deployment"
  echo
  echo "  [Press ‘X’ to exit]"
  echo
  read -r "?Enter mode [1/2/3]: " modeChoice

  case "${modeChoice}" in
    1) deploymentMode="dev" ;;
    2) deploymentMode="test" ;;
    3)
      deploymentMode="prod"
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
    modeSuffix="-prod"
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

  # Replace placeholder text based on deployment mode
  case "${deploymentMode}" in
    dev)
      echo "    ℹ️  Development mode: replacing legacy 'Sample' → '${placeholderMarker}'"
      sed -i.bak \
        -e "s/${legacyPlaceholderMarker}/${placeholderMarker}/gI" \
        "${plistOutput}"
      ;;
    test)
      echo "    🧪 Testing mode: replacing placeholder text → 'TEST'"
      sed -i.bak \
        -e "s/${placeholderMarker}/TEST/gI" \
        -e "s/${legacyPlaceholderMarker}/TEST/gI" \
        "${plistOutput}"
      ;;
    prod)
      echo "    🔓 Production mode: removing placeholder text for clean deployment"
      # Remove "<marker> " (with trailing space), then standalone marker
      sed -i.bak -E \
        -e "s/${placeholderMarker}[[:space:]]+//gI" \
        -e "s/${placeholderMarker}//gI" \
        -e "s/${legacyPlaceholderMarker}[[:space:]]+//gI" \
        -e "s/${legacyPlaceholderMarker}//gI" \
        "${plistOutput}"
      ;;
  esac

  # Update XML comments
  sed -i '' \
    -e "s|<!-- Preferences Domain: .* -->|<!-- Preferences Domain: ${newRDNN}.${newOrgScriptName} -->|" \
    -e "s|<!-- Version: .* -->|<!-- Version: ${scriptVersion} -->|" \
    -e "s|<!-- Generated on: .* -->|<!-- Generated on: ${timestamp} -->|" \
    "${plistOutput}"

  if [[ "${interactiveMode}" == true ]]; then
    if [[ "${priorPlistImported}" == true ]]; then
      echo "    🔧 Importing supported values from prior plist …"
      applyImportedPreferences "${priorPlistPath}" "${plistOutput}"
    else
      echo "    🔧 Applying IT support, branding and restart policy values …"
      /usr/bin/plutil -replace SupportTeamName -string "${supportTeamName}" "${plistOutput}"
      /usr/bin/plutil -replace SupportTeamPhone -string "${supportTeamPhone}" "${plistOutput}"
      /usr/bin/plutil -replace SupportTeamEmail -string "${supportTeamEmail}" "${plistOutput}"
      /usr/bin/plutil -replace SupportTeamWebsite -string "${supportTeamWebsite}" "${plistOutput}"
      /usr/bin/plutil -replace SupportKB -string "${supportKB}" "${plistOutput}"
      /usr/bin/plutil -replace InfoButtonAction -string "${infoButtonAction}" "${plistOutput}"
      /usr/bin/plutil -replace SupportKBURL -string "${supportKBURL}" "${plistOutput}"
      /usr/bin/plutil -replace InfoButtonText -string "${infoButtonText}" "${plistOutput}"
      /usr/bin/plutil -replace OrganizationOverlayIconURL -string "${organizationOverlayIconURL}" "${plistOutput}"
      /usr/bin/plutil -replace OrganizationOverlayIconURLdark -string "${organizationOverlayIconURLdark}" "${plistOutput}"
      /usr/bin/plutil -replace SwapOverlayAndLogo -bool "${swapOverlayAndLogo}" "${plistOutput}"
      /usr/bin/plutil -replace PastDeadlineRestartBehavior -string "${pastDeadlineRestartBehavior}" "${plistOutput}"

      if [[ "${pastDeadlineRestartBehavior}" != "Off" ]]; then
        /usr/bin/plutil -replace DaysPastDeadlineRestartWorkflow -integer "${daysPastDeadlineRestartWorkflow}" "${plistOutput}"
      fi

      if [[ "${enableKnowledgeBase}" != "true" ]]; then
        /usr/bin/plutil -replace HelpImage -string "hide" "${plistOutput}"
        /usr/bin/plutil -replace SupportAssistanceMessage -string "" "${plistOutput}"

        currentHelpMessage="$(/usr/bin/plutil -extract HelpMessage raw -o - "${plistOutput}" 2>/dev/null || true)"
        if [[ -n "${currentHelpMessage}" ]]; then
          updatedHelpMessage="$(printf "%s" "${currentHelpMessage}" | /usr/bin/sed 's#<br>- \*\*Knowledge Base Article:\*\* {supportKBURL}##g')"
          /usr/bin/plutil -replace HelpMessage -string "${updatedHelpMessage}" "${plistOutput}"
        fi

        messageWithKbHidden="$(/usr/bin/plutil -extract Message raw -o - "${plistOutput}" 2>/dev/null || true)"
        if [[ "${messageWithKbHidden}" == *"(?) button"* ]]; then
          echo "    ⚠️  Message still references '(?) button' while Knowledge Base is disabled."
        fi
      fi
    fi
  fi

  /usr/bin/plutil -replace ScriptLog -string "${resolvedScriptLogPath}" "${plistOutput}"

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

# Replace only the Client-side Log definition
escapedScriptLogPath="$(escapeSedReplacement "${resolvedScriptLogPath}")"
sed -i.bak \
  -e "s|^scriptLog=\"[^\"]*\"|scriptLog=\"${escapedScriptLogPath}\"|" \
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
    echo "    - Legacy 'Sample' placeholders replaced with '${placeholderMarker}'"
    echo "    - Safe to deploy for local validation"
    echo "    - NOT suitable for production use"
    ;;
  test)
    echo "  Testing Artifacts Generated:"
    echo "    - All placeholder text replaced with 'TEST'"
    echo "    - Suitable for staging/QA environments"
    echo "    - NOT suitable for production use"
    ;;
  prod)
    echo "  Production Artifacts Generated:"
    echo "    - All placeholder text removed (clean output)"
    if [[ "${interactiveMode}" == true ]]; then
      if [[ "${priorPlistImported}" == true ]]; then
        echo "    - Supported configuration values imported from prior plist"
        echo "    - Prior plist: ${priorPlistPath}"
        echo "    - ScriptLog resolved to '${resolvedScriptLogPath}'"
      else
        echo "    - IT support, branding and restart policy values applied from prompts"
        echo "    - Past-deadline restart policy set to '${pastDeadlineRestartBehavior}'"
        if [[ "${pastDeadlineRestartBehavior}" != "Off" ]]; then
          echo "    - Restart workflow begins ${daysPastDeadlineRestartWorkflow} day(s) past deadline"
        fi
        if [[ "${enableKnowledgeBase}" != "true" ]]; then
          echo "    - Knowledge Base surfaces hidden (Info button, KB row in help, QR help image)"
        fi
      fi
    else
      echo "    - Ensure you've customized values before deployment"
      echo "      (re-run with --interactive or update source defaults)"
    fi
    echo
    echo "  Recommended review items:"
    echo "    - Support team name, phone, email, website"
    if [[ "${priorPlistImported}" == true ]]; then
      echo "    - Imported ScriptLog path and any carried-forward KB/help visibility"
    elif [[ "${interactiveMode}" == true && "${enableKnowledgeBase}" != "true" ]]; then
      echo "    - Verify KB surfaces are hidden (Info button + KB row + QR help image)"
    else
      echo "    - Support KB title/link and Info button URL"
    fi
    echo "    - Organization overlay icon URLs"
    echo "    - Button labels and dialog messages"
    echo
    echo "  Files to review:"
    echo "    - ${plistOutput#$projectDir/}"
    echo "    - ${mobileconfigOutput#$projectDir/}"
    ;;
esac

echo
echo "==============================================================="
echo
exit 0
