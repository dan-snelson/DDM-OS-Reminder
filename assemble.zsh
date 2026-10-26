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
#   zsh assemble.zsh /path/to/previous-profile.mobileconfig
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
#     Runtime deployment also creates:
#       /Library/Management/<reverseDomainNameNotation>/dor-starter.zsh
#       /Library/Management/<reverseDomainNameNotation>/dor-state.plist
#       /Library/Management/<reverseDomainNameNotation>/dor.pid
#       /Library/Management/<reverseDomainNameNotation>/dor-fallback-declaration.plist (optional)
#
# http://snelson.us/ddm
#
####################################################################################################



####################################################################################################
# Global Variables
####################################################################################################

set -euo pipefail
autoload -Uz is-at-least
scriptVersion="5.3.0b3"
projectDir="$(cd "$(dirname "${0}")" && pwd)"
resourcesDir="${projectDir}/Resources"
artifactsDir="${projectDir}/Artifacts"
baseScript="${projectDir}/launchDaemonManagement.zsh"
messageScript="${projectDir}/reminderDialog.zsh"
plistSample="${resourcesDir}/sample.plist"
localizationHelper="${resourcesDir}/localizationFilter.zsh"
timestamp="$(date '+%Y-%m-%d-%H%M%S')"
outputScript="${artifactsDir}/ddm-os-reminder-assembled-${timestamp}.zsh"
tmpScript="${outputScript}.tmp"

# RDNN / org script name (will be discovered and possibly overridden)
currentRDNN=""
currentOrgScriptName=""
newRDNN=""
newOrgScriptName=""
resolvedScriptLogPath=""
safeScriptLogPathRegex='^/[A-Za-z0-9._/-]+$'

# Deployment mode (dev, test, prod)
deploymentMode="prod"  # default to production mode
modeSuffix=""
interactiveMode=false
priorPlistPath=""
priorPlistImported=false
priorPlistPrompted=false
importedLegacyMinimumDiskFreePercentage=""
importedTemplatesMissingBatteryPlaceholder=""
priorConfigSourcePath=""
priorConfigPlistPath=""
priorConfigLabel="plist"
priorConfigPreferenceDomain=""
priorConfigVersionMetadata=""
priorConfigTempDir=""
rdnnInferredFromPriorPlist=false
modeInferredFromPriorPlist=false
validLaneArgumentProvided=false
nearMissDeploymentModeToken=""
interactiveConfigurationHeaderShown=false

placeholderMarker="Assembled"
legacyPlaceholderMarker="Sample"

# IT Support, Branding & Restart Policy (interactive prompts)
supportTeamName=""
supportTeamPhone=""
hideSupportTeamPhone=""
supportTeamEmail=""
hideSupportTeamEmail=""
supportTeamWebsite=""
hideSupportTeamWebsite=""
supportKB=""
hideSupportKB=""
infoButtonAction=""
supportKBURL=""
infoButtonText=""
enableInfoButton="true"
enableKnowledgeBase="true"
hideSupportAssistanceMessage=""
organizationOverlayIconURL=""
organizationOverlayIconURLdark=""
swapOverlayAndLogo=""
pastDeadlineRestartBehavior=""
daysPastDeadlineRestartWorkflow=""
requestedLocalizationMode="full"
requestedLocalizationLanguages=""
localizationSelectionProvidedViaCLI=false



function printUsage() {
  echo
  echo "Usage:"
  echo "  zsh assemble.zsh [RDNN|prior-plist|prior-mobileconfig] [--lane dev|test|prod] [--interactive] [--minimal|--languages <csv>] [--help]"
  echo
  echo "Options:"
  echo "  --lane <dev|test|prod>       Select deployment mode"
  echo "  --interactive                Prompt for optional prior .plist or .mobileconfig import, IT support, branding, restart policy, and aggressive mode values"
  echo "  --minimal                    Keep base keys plus English localized keys only"
  echo "  --languages <csv>            Keep base keys, English localized keys, and selected language families"
  echo "  prior-plist                  Auto-enables interactive mode and infers RDNN plus deployment mode only when filename ends with -dev.plist, -test.plist or -prod.plist"
  echo "  prior-mobileconfig           Same as prior-plist for an unsigned or signed .mobileconfig; lane suffixes: -<lane>.mobileconfig, -<lane>-unsigned.mobileconfig, -<lane>-signed.mobileconfig"
  echo "  --help, -h                   Show this help"
  echo
}



function cleanupPriorConfigTempDir() {
  if [[ -n "${priorConfigTempDir}" && -d "${priorConfigTempDir}" ]]; then
    rm -rf "${priorConfigTempDir}" 2>/dev/null || true
  fi
}

# Registered at top level; zsh scopes EXIT traps set inside functions to that function
trap cleanupPriorConfigTempDir EXIT
trap 'exit 130' INT
trap 'exit 143' TERM



for argument in "$@"; do
  case "${argument}" in
    --help|-h)
      printUsage
      exit 0
      ;;
  esac
done

# Changed in 5.3.0b3; fail closed on a missing or invalid --lane value so it is never re-parsed as a positional RDNN
for (( argumentIndex=1; argumentIndex <= $#; argumentIndex++ )); do
  if [[ "${@[argumentIndex]}" == "--lane" ]]; then
    laneArgument=""
    if (( argumentIndex < $# )); then
      laneArgument="${@[$((argumentIndex + 1))]}"
    fi
    if [[ ! "${laneArgument}" =~ ^(dev|test|prod)$ ]]; then
      echo "❌ Invalid lane: '${laneArgument}'. Valid options: dev, test, prod"
      exit 1
    fi
    validLaneArgumentProvided=true
  fi
done



####################################################################################################
# Header
####################################################################################################

echo
echo "====================================================================================="
echo "🧩 Assemble DDM OS Reminder (${scriptVersion})"
echo "====================================================================================="
echo
echo "📍 Full Paths:"
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
[[ -f "${localizationHelper}" ]] || { echo "❌ Localization helper not found: ${localizationHelper}"; exit 1; }
[[ -d "${artifactsDir}" ]]  || { echo "⚠️ Artifacts directory missing — creating it."; mkdir -p "${artifactsDir}"; }

source "${localizationHelper}"

baseScriptVersion="$(
  /usr/bin/sed -n 's/^scriptVersion="\([^"]*\)".*/\1/p' "${baseScript}" | /usr/bin/head -n 1
)"
messageScriptVersion="$(
  /usr/bin/sed -n 's/^scriptVersion="\([^"]*\)".*/\1/p' "${messageScript}" | /usr/bin/head -n 1
)"

if [[ -z "${baseScriptVersion}" || -z "${messageScriptVersion}" ]]; then
  echo "❌ Could not read scriptVersion from source scripts."
  echo "    ${baseScript##*/}: ${baseScriptVersion:-<missing>}"
  echo "    ${messageScript##*/}: ${messageScriptVersion:-<missing>}"
  exit 1
fi

if [[ "${baseScriptVersion}" != "${scriptVersion}" || "${messageScriptVersion}" != "${scriptVersion}" ]]; then
  echo "❌ Source scriptVersion mismatch."
  echo "    ${0:t}: ${scriptVersion}"
  echo "    ${baseScript##*/}: ${baseScriptVersion}"
  echo "    ${messageScript##*/}: ${messageScriptVersion}"
  echo "    Align these before assembling so the deployed dor.zsh payload matches the wrapper."
  exit 1
fi



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
# Usage: zsh assemble.zsh [RDNN|prior-plist|prior-mobileconfig] [--lane dev|test|prod] [--interactive] [--help]
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

function isPriorMobileconfigArgument() {
  local candidateValue="${1}"

  [[ "${candidateValue:l}" == *.mobileconfig ]]
}

function isPriorPlistArgument() {
  local candidateValue="${1}"

  [[ "${candidateValue:l}" == *.plist ]] || isPriorMobileconfigArgument "${candidateValue}"
}

function emitTopLevelPlistDictKeys() {
  local xmlPlistPath="${1}"

  # Depth-aware so nested dict keys are never mistaken for top-level keys
  /usr/bin/awk '
    {
      line = $0
      sub(/^[[:space:]]+/, "", line)
    }

    line ~ /^<key>[^<]*<\/key>$/ && depth == 1 {
      key = line
      sub(/^<key>/, "", key)
      sub(/<\/key>$/, "", key)
      print key
      next
    }

    line ~ /^<(dict|array)>/ {
      depth++
      next
    }

    line ~ /^<\/(dict|array)>/ {
      depth--
      next
    }
  ' "${xmlPlistPath}"
}

function ensurePriorConfigTempDir() {
  if [[ -n "${priorConfigTempDir}" && -d "${priorConfigTempDir}" ]]; then
    return 0
  fi

  priorConfigTempDir="$(/usr/bin/mktemp -d -t ddm-os-reminder-assemble)" || {
    priorConfigTempDir=""
    echo "❌ Unable to create a temporary directory for .mobileconfig import" >&2
    return 1
  }
}

function extractPriorMobileconfigPreferences() {
  local candidatePath="${1}"
  local profilePath="${candidatePath}"
  local decodedProfilePath=""
  local extractedPlistPath=""
  local payloadXmlPath=""
  local payloadIndex=0
  local payloadType=""
  local payloadDomain=""
  local candidateEntry=""
  local candidateStyle=""
  local candidateIndex=""
  local candidateDomain=""
  local manageLevel=""
  local selectedManageLevel=""
  local topLevelKey=""
  local payloadDescription=""
  local -a payloadMetadataKeys
  local -a preferenceCandidates
  local -a candidateDomains
  local -a manageLevelsPresent

  if [[ ! -e "${candidatePath}" ]]; then
    echo "❌ Prior mobileconfig not found: ${candidatePath}" >&2
    return 1
  fi

  if [[ ! -r "${candidatePath}" ]]; then
    echo "❌ Prior mobileconfig is not readable: ${candidatePath}" >&2
    return 1
  fi

  ensurePriorConfigTempDir || return 1
  decodedProfilePath="${priorConfigTempDir}/decoded.mobileconfig"
  extractedPlistPath="${priorConfigTempDir}/prior.plist"
  payloadXmlPath="${priorConfigTempDir}/payload.plist"
  rm -f "${decodedProfilePath}" "${extractedPlistPath}" "${payloadXmlPath}" 2>/dev/null || true

  # Signed profiles are CMS envelopes; decode them before reading payloads
  if ! /usr/bin/plutil -lint "${profilePath}" >/dev/null 2>&1; then
    if /usr/bin/security cms -D -i "${candidatePath}" -o "${decodedProfilePath}" >/dev/null 2>&1 \
      && /usr/bin/plutil -lint "${decodedProfilePath}" >/dev/null 2>&1; then
      profilePath="${decodedProfilePath}"
      echo "🔓 Decoded signed mobileconfig: ${candidatePath}" >&2
    else
      echo "❌ Prior mobileconfig is neither a valid property list nor a CMS-signed profile: ${candidatePath}" >&2
      return 1
    fi
  fi

  if ! /usr/libexec/PlistBuddy -c "Print :PayloadContent" "${profilePath}" >/dev/null 2>&1; then
    echo "❌ Prior mobileconfig is not a configuration profile (no PayloadContent): ${candidatePath}" >&2
    return 1
  fi

  while /usr/libexec/PlistBuddy -c "Print :PayloadContent:${payloadIndex}" "${profilePath}" >/dev/null 2>&1; do
    payloadType="$(
      /usr/libexec/PlistBuddy -c "Print :PayloadContent:${payloadIndex}:PayloadType" "${profilePath}" 2>/dev/null || true
    )"

    if [[ "${payloadType}" == "com.apple.ManagedClient.preferences" ]]; then
      if /usr/libexec/PlistBuddy -x -c "Print :PayloadContent:${payloadIndex}:PayloadContent" "${profilePath}" > "${payloadXmlPath}" 2>/dev/null; then
        while IFS= read -r payloadDomain; do
          [[ "${payloadDomain}" == *".${currentOrgScriptName_reminder}" ]] || continue
          preferenceCandidates+=("mcx|${payloadIndex}|${payloadDomain}")
        done < <(emitTopLevelPlistDictKeys "${payloadXmlPath}")
      fi
    elif [[ "${payloadType}" == *".${currentOrgScriptName_reminder}" ]]; then
      # Alternate format (e.g., iMazing Profile Editor): settings live directly in the payload dict
      preferenceCandidates+=("flat|${payloadIndex}|${payloadType}")
    fi

    payloadIndex=$(( payloadIndex + 1 ))
  done

  if (( ${#preferenceCandidates[@]} == 0 )); then
    echo "❌ Prior mobileconfig does not contain a DDM OS Reminder preferences payload (*.${currentOrgScriptName_reminder}): ${candidatePath}" >&2
    return 1
  fi

  if (( ${#preferenceCandidates[@]} > 1 )); then
    for candidateEntry in "${preferenceCandidates[@]}"; do
      candidateDomains+=("${candidateEntry##*|} [${candidateEntry%%|*} payload ${${candidateEntry#*|}%%|*}]")
    done
    echo "❌ Prior mobileconfig contains multiple DDM OS Reminder preferences payloads (${(j:, :)candidateDomains}); export a profile with exactly one: ${candidatePath}" >&2
    return 1
  fi

  candidateEntry="${preferenceCandidates[1]}"
  candidateStyle="${candidateEntry%%|*}"
  candidateIndex="${${candidateEntry#*|}%%|*}"
  candidateDomain="${candidateEntry##*|}"

  if [[ "${candidateStyle}" == "mcx" ]]; then
    for manageLevel in Forced Set-Once Often; do
      if /usr/libexec/PlistBuddy -c "Print :PayloadContent:${candidateIndex}:PayloadContent:${candidateDomain}:${manageLevel}" "${profilePath}" >/dev/null 2>&1; then
        manageLevelsPresent+=("${manageLevel}")
      fi
    done

    if (( ${#manageLevelsPresent[@]} == 0 )); then
      echo "❌ Prior mobileconfig domain '${candidateDomain}' has no Forced, Set-Once or Often settings: ${candidatePath}" >&2
      return 1
    fi

    selectedManageLevel="${manageLevelsPresent[1]}"

    if [[ "${selectedManageLevel}" != "Forced" ]]; then
      echo "⚠️  Prior mobileconfig domain '${candidateDomain}' has no Forced settings; using ${selectedManageLevel} settings" >&2
    elif (( ${#manageLevelsPresent[@]} > 1 )); then
      echo "⚠️  Prior mobileconfig domain '${candidateDomain}' also has ${(j:, :)manageLevelsPresent[2,-1]} settings; importing Forced only" >&2
    fi

    if /usr/libexec/PlistBuddy -c "Print :PayloadContent:${candidateIndex}:PayloadContent:${candidateDomain}:${selectedManageLevel}:1" "${profilePath}" >/dev/null 2>&1; then
      echo "❌ Prior mobileconfig domain '${candidateDomain}' has multiple ${selectedManageLevel} entries; export a profile with exactly one: ${candidatePath}" >&2
      return 1
    fi

    if ! /usr/libexec/PlistBuddy -x -c "Print :PayloadContent:${candidateIndex}:PayloadContent:${candidateDomain}:${selectedManageLevel}:0:mcx_preference_settings" "${profilePath}" > "${extractedPlistPath}" 2>/dev/null; then
      echo "❌ Prior mobileconfig domain '${candidateDomain}' has no ${selectedManageLevel} mcx_preference_settings: ${candidatePath}" >&2
      return 1
    fi
  else
    if ! /usr/libexec/PlistBuddy -x -c "Print :PayloadContent:${candidateIndex}" "${profilePath}" > "${extractedPlistPath}" 2>/dev/null; then
      echo "❌ Unable to read '${candidateDomain}' payload from prior mobileconfig: ${candidatePath}" >&2
      return 1
    fi

    # Strip profile metadata (PayloadType, PayloadUUID, …) so only preference keys remain
    payloadMetadataKeys=("${(@f)$(emitTopLevelPlistDictKeys "${extractedPlistPath}")}")
    for topLevelKey in "${payloadMetadataKeys[@]}"; do
      [[ "${topLevelKey}" == Payload* ]] || continue
      /usr/libexec/PlistBuddy -c "Delete :${topLevelKey}" "${extractedPlistPath}" >/dev/null 2>&1 || true
    done
  fi

  if ! /usr/bin/plutil -lint "${extractedPlistPath}" >/dev/null 2>&1; then
    echo "❌ Preferences extracted from prior mobileconfig are invalid: ${candidatePath}" >&2
    return 1
  fi

  payloadDescription="$(
    /usr/libexec/PlistBuddy -c "Print :PayloadDescription" "${profilePath}" 2>/dev/null || true
  )"
  priorConfigVersionMetadata=""
  if [[ "${payloadDescription}" =~ 'DDM OS Reminder \(([^)]+)\)' ]]; then
    priorConfigVersionMetadata="${match[1]}"
  else
    # Resources/createPlist.zsh carries the version in PayloadDisplayName instead
    payloadDescription="$(
      /usr/libexec/PlistBuddy -c "Print :PayloadDisplayName" "${profilePath}" 2>/dev/null || true
    )"
    if [[ "${payloadDescription}" =~ 'DDM OS Reminder \(([^)]+)\)' ]]; then
      priorConfigVersionMetadata="${match[1]}"
    fi
  fi

  priorConfigPreferenceDomain="${candidateDomain}"
  priorConfigPlistPath="${extractedPlistPath}"
  echo "🧾 Extracted '${candidateDomain}' preferences from prior mobileconfig" >&2
}

function resolvePriorConfiguration() {
  local candidatePath="${1}"

  priorConfigSourcePath="${candidatePath}"
  priorConfigPreferenceDomain=""
  priorConfigVersionMetadata=""

  if isPriorMobileconfigArgument "${candidatePath}"; then
    priorConfigLabel="mobileconfig"
    priorConfigPlistPath=""
    extractPriorMobileconfigPreferences "${candidatePath}"
  else
    priorConfigLabel="plist"
    priorConfigPlistPath="${candidatePath}"
  fi
}

function validatePriorPlistPath() {
  local candidatePath="${1}"
  local preferencesDomainComment=""
  local versionComment=""
  local versionCore=""
  local scriptLogValue=""
  local requiredKey=""
  local -a missingRequiredKeys
  local hasLegacyHelpMessage="false"
  local hasLocalizedHelpMessage="false"

  if [[ ! -e "${candidatePath}" ]]; then
    echo "❌ Prior ${priorConfigLabel} not found: ${candidatePath}" >&2
    return 1
  fi

  if [[ ! -r "${candidatePath}" ]]; then
    echo "❌ Prior ${priorConfigLabel} is not readable: ${candidatePath}" >&2
    return 1
  fi

  if ! /usr/bin/plutil -lint "${candidatePath}" >/dev/null 2>&1; then
    echo "❌ Prior ${priorConfigLabel} is invalid: ${candidatePath}" >&2
    return 1
  fi

  for requiredKey in ScriptLog SupportTeamName SupportKBURL InfoButtonText Message; do
    if ! /usr/libexec/PlistBuddy -c "Print :${requiredKey}" "${candidatePath}" >/dev/null 2>&1; then
      missingRequiredKeys+=("${requiredKey}")
    fi
  done

  if /usr/libexec/PlistBuddy -c "Print :HelpMessage" "${candidatePath}" >/dev/null 2>&1; then
    hasLegacyHelpMessage="true"
  fi

  if /usr/libexec/PlistBuddy -c "Print" "${candidatePath}" 2>/dev/null | /usr/bin/grep -q "^[[:space:]]*HelpMessageLocalized_"; then
    hasLocalizedHelpMessage="true"
  fi

  if [[ "${hasLegacyHelpMessage}" != "true" && "${hasLocalizedHelpMessage}" != "true" ]]; then
    missingRequiredKeys+=("HelpMessage|HelpMessageLocalized_<code>")
  fi

  if (( ${#missingRequiredKeys[@]} > 0 )); then
    if [[ "${priorConfigLabel}" == "mobileconfig" ]]; then
      echo "❌ Prior mobileconfig '${priorConfigPreferenceDomain}' settings are missing required DDM OS Reminder keys: ${(j:, :)missingRequiredKeys} (${priorConfigSourcePath})" >&2
    else
      echo "❌ Prior ${priorConfigLabel} does not appear to be a DDM OS Reminder plist; missing required keys: ${(j:, :)missingRequiredKeys}" >&2
      if /usr/libexec/PlistBuddy -c "Print :PayloadContent" "${candidatePath}" >/dev/null 2>&1; then
        echo "    This file looks like a configuration profile; rename it with a .mobileconfig extension to import it." >&2
      fi
    fi
    return 1
  fi

  scriptLogValue="$(
    /usr/libexec/PlistBuddy -c "Print :ScriptLog" "${candidatePath}" 2>/dev/null || true
  )"

  if [[ -z "${scriptLogValue}" || "${scriptLogValue:t}" != *.log ]]; then
    echo "❌ Prior ${priorConfigLabel} does not contain a valid DDM OS Reminder ScriptLog path" >&2
    return 1
  fi

  if [[ "${priorConfigLabel}" == "mobileconfig" ]]; then
    # Extracted settings carry no XML comments; use metadata read from the profile itself
    preferencesDomainComment="${priorConfigPreferenceDomain}"
  else
    preferencesDomainComment="$(
      /usr/bin/sed -n 's#^[[:space:]]*<!--[[:space:]]*Preferences Domain:[[:space:]]*\(.*\)[[:space:]]*-->[[:space:]]*$#\1#p' "${candidatePath}" \
        | /usr/bin/head -n 1
    )"
    preferencesDomainComment="$(
      printf "%s\n" "${preferencesDomainComment}" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
    )"
  fi

  if [[ -n "${preferencesDomainComment}" && "${preferencesDomainComment}" != *".${currentOrgScriptName_reminder}" ]]; then
    echo "❌ Prior ${priorConfigLabel} metadata does not match a DDM OS Reminder preferences domain: ${preferencesDomainComment}" >&2
    return 1
  fi

  if [[ "${priorConfigLabel}" == "mobileconfig" ]]; then
    versionComment="${priorConfigVersionMetadata}"
  else
    versionComment="$(
      /usr/bin/sed -n 's#^[[:space:]]*<!--[[:space:]]*Version:[[:space:]]*\(.*\)[[:space:]]*-->[[:space:]]*$#\1#p' "${candidatePath}" \
        | /usr/bin/head -n 1
    )"
    versionComment="$(
      printf "%s\n" "${versionComment}" | /usr/bin/sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
    )"
  fi

  if [[ -z "${versionComment}" ]]; then
    echo "⚠️  Prior ${priorConfigLabel} is missing version metadata; continuing with documented 2.2.0+ compatibility on a best-effort basis" >&2
    echo "${candidatePath}"
    return 0
  fi

  versionCore="$(
    printf "%s\n" "${versionComment}" | /usr/bin/sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$/\1/p'
  )"

  if [[ -z "${versionCore}" ]]; then
    echo "⚠️  Prior ${priorConfigLabel} version metadata is not recognized ('${versionComment}'); continuing with best-effort import" >&2
    echo "${candidatePath}"
    return 0
  fi

  if ! is-at-least 2.2.0 "${versionCore}"; then
    echo "⚠️  Prior ${priorConfigLabel} version '${versionComment}' predates the documented 2.2.0+ compatibility baseline; continuing with best-effort import" >&2
  fi

  echo "${candidatePath}"
}

function isSafeScriptLogPath() {
  local candidatePath="${1}"

  # ScriptLog is spliced into generated Zsh source; allow only plain absolute paths
  [[ "${candidatePath}" =~ ${safeScriptLogPathRegex} ]] || return 1
  [[ "${candidatePath}" != *'/../'* && "${candidatePath}" != *'/./'* && "${candidatePath}" != *'//'* ]]
}

function inferRDNNFromPriorPlist() {
  local plistPath="${1}"
  local filenamePath="${2:-${1}}"
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
    plistFilename="${filenamePath:t}"
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
    *-dev.plist|*-dev.mobileconfig|*-dev-unsigned.mobileconfig|*-dev-signed.mobileconfig)     echo "dev" ;;
    *-test.plist|*-test.mobileconfig|*-test-unsigned.mobileconfig|*-test-signed.mobileconfig) echo "test" ;;
    *-prod.plist|*-prod.mobileconfig|*-prod-unsigned.mobileconfig|*-prod-signed.mobileconfig) echo "prod" ;;
  esac
}

function detectNearMissDeploymentModeTokenFromPriorPlist() {
  local plistFilename="${1:t:l}"

  case "${plistFilename}" in
    *-dev-*.plist|*-dev-*.mobileconfig)   echo "dev" ;;
    *-test-*.plist|*-test-*.mobileconfig) echo "test" ;;
    *-prod-*.plist|*-prod-*.mobileconfig) echo "prod" ;;
  esac
}

function showInteractiveConfigurationHeader() {
  if [[ "${interactiveConfigurationHeaderShown}" == true ]]; then
    return
  fi

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🛠️  Interactive Configuration"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo

  interactiveConfigurationHeaderShown=true
}

function applyPriorPlistSelections() {
  local plistPath="${1}"
  local inferredRDNN=""
  local inferredDeploymentMode=""
  local nearMissModeToken=""

  priorPlistPath="${plistPath}"
  priorPlistImported=true
  [[ -n "${priorConfigSourcePath}" ]] || priorConfigSourcePath="${plistPath}"

  echo
  echo "ℹ️  Importing supported values from: ${priorConfigSourcePath}"

  if [[ -z "${newRDNN}" || "${rdnnInferredFromPriorPlist}" == true ]]; then
    inferredRDNN="$(inferRDNNFromPriorPlist "${priorPlistPath}" "${priorConfigSourcePath}")"
    if [[ -n "${inferredRDNN}" ]]; then
      if [[ -n "${priorConfigPreferenceDomain}" && "${priorConfigPreferenceDomain}" != "${inferredRDNN}.${currentOrgScriptName_reminder}" ]]; then
        echo "⚠️  Prior ${priorConfigLabel} domain '${priorConfigPreferenceDomain}' does not match ScriptLog-derived RDNN '${inferredRDNN}'"
        echo "    Verify the RDNN below, or re-run with the intended RDNN as a positional argument."
      fi
      echo "🔎 Inferred RDNN from prior ${priorConfigLabel}: '${inferredRDNN}'"
      newRDNN="${inferredRDNN}"
      skipRDNNPrompt=true
      rdnnInferredFromPriorPlist=true
    fi
  fi

  # Changed in 5.3.0b3; a valid --lane anywhere on the command line wins, so skip filename inference (and its log line) regardless of argument order
  if [[ "${skipModePrompt}" == false && "${validLaneArgumentProvided}" == false ]]; then
    inferredDeploymentMode="$(inferDeploymentModeFromPriorPlist "${priorConfigSourcePath}")"
    if [[ -n "${inferredDeploymentMode}" ]]; then
      deploymentMode="${inferredDeploymentMode}"
      skipModePrompt=true
      modeInferredFromPriorPlist=true
      nearMissDeploymentModeToken=""
      echo "🔎 Inferred deployment mode from prior ${priorConfigLabel}: '${deploymentMode}'"
    else
      nearMissModeToken="$(detectNearMissDeploymentModeTokenFromPriorPlist "${priorConfigSourcePath}")"
      if [[ -n "${nearMissModeToken}" ]]; then
        nearMissDeploymentModeToken="${nearMissModeToken}"
      fi
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --help|-h)
      printUsage
      exit 0
      ;;
    --interactive)
      interactiveMode=true
      shift
      ;;
    --minimal)
      if [[ "${requestedLocalizationMode}" == "subset" ]]; then
        echo "❌ --minimal cannot be combined with --languages."
        exit 1
      fi
      requestedLocalizationMode="minimal"
      requestedLocalizationLanguages=""
      localizationSelectionProvidedViaCLI=true
      shift
      ;;
    --languages)
      if [[ "${requestedLocalizationMode}" == "minimal" ]]; then
        echo "❌ --languages cannot be combined with --minimal."
        exit 1
      fi
      if [[ -n "${2:-}" ]]; then
        requestedLocalizationMode="subset"
        requestedLocalizationLanguages="${2}"
        localizationSelectionProvidedViaCLI=true
        shift 2
      else
        echo "❌ Missing value for --languages. Example: --languages en,fr"
        exit 1
      fi
      ;;
    --lane)
      if [[ -n "${2:-}" ]] && [[ "${2}" =~ ^(dev|test|prod)$ ]]; then
        deploymentMode="${2}"
        skipModePrompt=true
        modeInferredFromPriorPlist=false
        shift 2
      else
        echo "❌ Invalid lane: '${2:-}'. Valid options: dev, test, prod"
        exit 1
      fi
      ;;
    -*)
      echo "⚠️  Unknown flag: ${1}"
      shift
      ;;
    *)
      positionalArgument="$(normalizePathInput "${1}")"

      if [[ -z "${priorPlistPath}" ]] && isPriorPlistArgument "${positionalArgument}"; then
        resolvePriorConfiguration "${positionalArgument}" || exit 1
        priorPlistPath="$(validatePriorPlistPath "${priorConfigPlistPath}")" || exit 1
        interactiveMode=true
        priorPlistPrompted=true

        echo "📥 Prior ${priorConfigLabel} provided via command-line argument: '${priorConfigSourcePath}'"
        applyPriorPlistSelections "${priorPlistPath}"
      elif isPriorPlistArgument "${positionalArgument}"; then
        echo "❌ Only one prior .plist or .mobileconfig may be supplied; extra argument: '${positionalArgument}'"
        exit 1
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
    echo "❎ Exiting at user request."
    exit 0
  fi

  if [[ -z "${inputValue}" ]]; then
    inputValue="${defaultValue}"
  fi

  typeset -g "${variableName}=${inputValue}"
}

function normalizeLocalizationModeSelection() {
  local value="${1}"
  local normalizedValue="${value//[[:space:]]/}"

  case "${normalizedValue:l}" in
    full|f) echo "full" ;;
    minimal|m) echo "minimal" ;;
    selected|select|subset|languages|language|s|l) echo "subset" ;;
    *) echo "" ;;
  esac
}

function localizationModePromptDefault() {
  case "${requestedLocalizationMode}" in
    minimal)
      echo "Minimal"
      ;;
    subset)
      echo "Selected"
      ;;
    *)
      echo "Full"
      ;;
  esac
}

function promptForLocalizationSelection() {
  local localizationModeChoice=""
  local normalizedLocalizationModeChoice=""
  local defaultLocalizationLanguages=""

  showInteractiveConfigurationHeader
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🌐 Localization Artifact Mode"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  while true; do
    promptWithDefault "Localization Output (Full / [M]inimal / [S]elected languages)" "$(localizationModePromptDefault)" "localizationModeChoice"
    normalizedLocalizationModeChoice="$(normalizeLocalizationModeSelection "${localizationModeChoice}")"

    if [[ -n "${normalizedLocalizationModeChoice}" ]]; then
      requestedLocalizationMode="${normalizedLocalizationModeChoice}"
      break
    fi

    echo "⚠️  Invalid localization mode; valid values: Full, Minimal, Selected."
  done

  case "${requestedLocalizationMode}" in
    full|minimal)
      requestedLocalizationLanguages=""
      ;;
    subset)
      defaultLocalizationLanguages="${requestedLocalizationLanguages:-en,fr}"

      while true; do
        promptWithDefault "Languages CSV (for example: en,fr or fr_CA,ja)" "${defaultLocalizationLanguages}" "requestedLocalizationLanguages"

        if configureLocalizationFilter "subset" "${requestedLocalizationLanguages}" >/dev/null 2>&1; then
          requestedLocalizationMode="${localizationFilterMode}"
          requestedLocalizationLanguages="${localizationFilterLanguagesCSV}"
          break
        fi

        echo "⚠️  Invalid language list. Use comma-separated locale codes such as en,fr or fr_CA,ja."
      done
      ;;
  esac

  configureLocalizationFilter "${requestedLocalizationMode}" "${requestedLocalizationLanguages}" >/dev/null 2>&1 || {
    echo "❌ Failed to configure localization filter from interactive input."
    exit 1
  }

  echo
  echo "ℹ️  Localization mode set to: $(localizationFilterSummary)"
  echo
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
    read -r "?Drag-and-drop an earlier DOR .plist or .mobileconfig to import [Return to skip] (or ‘X’ to exit): " candidatePath

    if [[ "${candidatePath}" == [Xx] ]]; then
      echo "❎ Exiting at user request."
      exit 0
    fi

    candidatePath="$(normalizePathInput "${candidatePath}")"

    if [[ -z "${candidatePath}" ]]; then
      priorPlistPath=""
      priorPlistImported=false
      return
    fi

    if ! resolvePriorConfiguration "${candidatePath}"; then
      continue
    fi

    if ! validatedPath="$(validatePriorPlistPath "${priorConfigPlistPath}")"; then
      continue
    fi

    applyPriorPlistSelections "${validatedPath}"
    return
  done
}

function emitSupportedPlistPreferenceTypes() {
  /usr/bin/awk '
    BEGIN {
      section = ""
    }

    /^declare -A preferenceConfiguration=\(/ {
      section = "pref"
      next
    }

    /^declare -A plistKeyMap=\(/ {
      section = "map"
      next
    }

    /^\)$/ {
      section = ""
      next
    }

    section == "pref" {
      line = $0
      if (line ~ /^[[:space:]]*\["[^"]+"\]="[^|"]+\|/) {
        key = line
        sub(/^[[:space:]]*\["/, "", key)
        sub(/"\]=".*$/, "", key)

        preferenceType = line
        sub(/^[[:space:]]*\["[^"]+"\]="/, "", preferenceType)
        sub(/\|.*$/, "", preferenceType)

        preferenceTypeByConfigKey[key] = preferenceType
      }
      next
    }

    section == "map" {
      line = $0
      if (line ~ /^[[:space:]]*\["[^"]+"\]="[^"]+"/) {
        key = line
        sub(/^[[:space:]]*\["/, "", key)
        sub(/"\]=".*$/, "", key)

        plistKey = line
        sub(/^[[:space:]]*\["[^"]+"\]="/, "", plistKey)
        sub(/".*$/, "", plistKey)

        plistKeyByConfigKey[key] = plistKey
      }
      next
    }

    END {
      for (configKey in preferenceTypeByConfigKey) {
        plistKey = (configKey in plistKeyByConfigKey) ? plistKeyByConfigKey[configKey] : configKey
        print plistKey "|" preferenceTypeByConfigKey[configKey]
      }
    }
  ' "${messageScript}" | LC_ALL=C sort
}

function emitPlistEntryTypes() {
  local plistPath="${1}"

  /usr/bin/awk '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }

    BEGIN {
      currentKey = ""
    }

    /^[[:space:]]*<key>[^<]+<\/key>[[:space:]]*$/ {
      currentKey = $0
      sub(/^[[:space:]]*<key>/, "", currentKey)
      sub(/<\/key>[[:space:]]*$/, "", currentKey)
      next
    }

    currentKey != "" {
      line = trim($0)

      if (line == "" || line ~ /^<!--/) {
        next
      }

      if (line ~ /^<string>/) {
        print currentKey "|string"
        currentKey = ""
        next
      }

      if (line ~ /^<integer>/ || line ~ /^<real>/) {
        print currentKey "|numeric"
        currentKey = ""
        next
      }

      if (line ~ /^<(true|false)\/>/) {
        print currentKey "|boolean"
        currentKey = ""
        next
      }

      currentKey = ""
    }
  ' "${plistPath}" | LC_ALL=C sort
}

function extractPlistKeys() {
  local plistPath="${1}"

  sed -n 's/^[[:space:]]*<key>\([^<]*\)<\/key>[[:space:]]*$/\1/p' "${plistPath}"
}

# Added in 5.3.0b3; rewrite only assemble.zsh's own leading lane marker so imported dev / test copy matches the selected lane
function normalizeImportedLaneMarker() {
  local importedValue="${1}"
  local targetLane="${2}"
  local leadingBreaks=""
  local remainder="${importedValue}"
  local candidateMarker=""
  local laneMarker=""

  while [[ "${remainder}" == "<br>"* ]]; do
    leadingBreaks+="<br>"
    remainder="${remainder#<br>}"
  done

  for candidateMarker in "${placeholderMarker}" "${legacyPlaceholderMarker}" "TEST"; do
    if [[ "${remainder}" == "${candidateMarker}" || "${remainder}" == "${candidateMarker}"[[:space:]:\<]* ]]; then
      laneMarker="${candidateMarker}"
      break
    fi
  done

  if [[ -z "${laneMarker}" ]]; then
    printf "%s\n" "${importedValue}"
    return 0
  fi

  remainder="${remainder#${laneMarker}}"

  case "${targetLane}" in
    dev)
      printf "%s\n" "${leadingBreaks}${placeholderMarker}${remainder}"
      ;;
    test)
      printf "%s\n" "${leadingBreaks}TEST${remainder}"
      ;;
    *)
      remainder="${remainder#:}"
      while [[ "${remainder}" == [[:space:]]* ]]; do
        remainder="${remainder#?}"
      done
      printf "%s\n" "${leadingBreaks}${remainder}"
      ;;
  esac
}

function writePreferenceOverride() {
  local plistPath="${1}"
  local plistKey="${2}"
  local preferenceType="${3}"
  local preferenceValue="${4}"
  local normalizedBoolean=""

  case "${preferenceType}" in
    numeric)
      # Match runtime setNumericPreferenceValue, which ignores values outside 0-999
      if [[ "${preferenceValue}" == <-> ]] && (( preferenceValue >= 0 && preferenceValue <= 999 )); then
        /usr/bin/plutil -replace "${plistKey}" -integer "${preferenceValue}" "${plistPath}"
      else
        echo "    ⚠️  Skipping invalid integer value '${preferenceValue}' for ${plistKey} (expected 0-999); keeping sample default"
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

# Added in 5.2.0; report imported admin copy that will never show the low-battery warning, but never rewrite it
function reportImportedTemplatesMissingBatteryPlaceholder() {
  local sourcePlist="${1}"
  local targetPlist="${2}"
  local importedKey=""
  local templateBase=""
  local templateValue=""
  local templateSummary=""
  local -a templateBases=(Message AggressiveModeMessage PreDeadlineThresholdMessage PastDeadlinePromptMessage PastDeadlineForceMessage)
  local -a missingSummaries=()
  local -A missingBaseKeySet
  local -A missingLocalizedCount

  importedTemplatesMissingBatteryPlaceholder=""

  while IFS= read -r importedKey; do
    [[ -z "${importedKey}" ]] && continue
    templateBase="${importedKey%%Localized_*}"
    (( ${templateBases[(Ie)${templateBase}]} )) || continue
    if isLocalizedPlistKey "${importedKey}" && ! shouldKeepLocalizedPlistKey "${importedKey}"; then
      continue
    fi
    templateValue="$(
      /usr/libexec/PlistBuddy -c "Print :${importedKey}" "${targetPlist}" 2>/dev/null || true
    )"
    [[ "${templateValue}" == *"{batteryWarningMessage}"* ]] && continue
    if [[ "${importedKey}" == "${templateBase}" ]]; then
      missingBaseKeySet[${templateBase}]=1
    else
      missingLocalizedCount[${templateBase}]=$(( ${missingLocalizedCount[${templateBase}]:-0} + 1 ))
    fi
  done < <(extractPlistKeys "${sourcePlist}")

  for templateBase in "${templateBases[@]}"; do
    if [[ -n "${missingBaseKeySet[${templateBase}]:-}" ]]; then
      templateSummary="${templateBase}"
      if (( ${missingLocalizedCount[${templateBase}]:-0} > 0 )); then
        templateSummary+=" (+${missingLocalizedCount[${templateBase}]} localized)"
      fi
    elif (( ${missingLocalizedCount[${templateBase}]:-0} > 0 )); then
      templateSummary="${templateBase}Localized_* (${missingLocalizedCount[${templateBase}]})"
    else
      continue
    fi
    missingSummaries+=("${templateSummary}")
  done

  if (( ${#missingSummaries[@]} > 0 )); then
    importedTemplatesMissingBatteryPlaceholder="${(j:, :)missingSummaries}"
    echo "    ℹ️  Imported templates without {batteryWarningMessage}; the low-battery warning will not appear in them until you add it:"
    echo "        ${importedTemplatesMissingBatteryPlaceholder}"
  fi
}

function applyImportedPreferences() {
  local sourcePlist="${1}"
  local targetPlist="${2}"
  local emittedPreferenceTypes=""
  local targetPlistPreferenceTypes=""
  local importedKey=""
  local importedValue=""
  local preferenceType=""
  local preferenceLine=""
  local candidateKey=""
  local -a supportedPreferenceLines
  local -A unsupportedImportedKeySet
  local -a unsupportedImportedKeys
  local -A skippedLocalizedImportedKeySet
  local -a skippedLocalizedImportedKeys
  local resolvedMinimumDiskFreeGB=""
  local importedMinimumDiskFreeGB=""
  local normalizedValue=""
  local normalizedLaneMarkerCount=0

  if ! emittedPreferenceTypes="$(emitSupportedPlistPreferenceTypes)"; then
    echo "    ❌ Failed to determine supported preference types; aborting preference import."
    return 1
  fi

  if [[ -z "${emittedPreferenceTypes}" ]]; then
    echo "    ❌ No supported preference types were returned; aborting preference import."
    return 1
  fi

  if ! targetPlistPreferenceTypes="$(emitPlistEntryTypes "${targetPlist}")"; then
    echo "    ❌ Failed to determine target plist entry types; aborting preference import."
    return 1
  fi

  supportedPreferenceLines=(
    "${(@f)${emittedPreferenceTypes}}"
    "${(@f)${targetPlistPreferenceTypes}}"
  )
  supportedPreferenceLines=("${(@u)supportedPreferenceLines}")

  while IFS= read -r importedKey; do
    [[ -z "${importedKey}" ]] && continue
    if isLocalizedPlistKey "${importedKey}" && ! shouldKeepLocalizedPlistKey "${importedKey}"; then
      skippedLocalizedImportedKeySet["${importedKey}"]=1
      continue
    fi
    # Deprecated in 5.1.0; reported separately with its MinimumDiskFreeGB replacement
    if [[ "${importedKey}" == "MinimumDiskFreePercentage" ]]; then
      importedLegacyMinimumDiskFreePercentage="$(
        /usr/libexec/PlistBuddy -c "Print :MinimumDiskFreePercentage" "${sourcePlist}" 2>/dev/null
      )"
      continue
    fi
    if ! preferenceType="$(preferenceTypeForPlistKey "${importedKey}" "${supportedPreferenceLines[@]}")"; then
      unsupportedImportedKeySet["${importedKey}"]=1
    fi
  done < <(extractPlistKeys "${sourcePlist}")

  if (( ${#unsupportedImportedKeySet[@]} > 0 )); then
    unsupportedImportedKeys=("${(@ok)unsupportedImportedKeySet}")
    echo "    ⚠️  Ignoring unsupported imported keys: ${(j:, :)unsupportedImportedKeys}"
  fi

  if (( ${#skippedLocalizedImportedKeySet[@]} > 0 )); then
    skippedLocalizedImportedKeys=("${(@ok)skippedLocalizedImportedKeySet}")
    if (( ${#skippedLocalizedImportedKeys[@]} <= 5 )); then
      echo "    ℹ️  Skipping ${#skippedLocalizedImportedKeys[@]} imported localized key(s) outside selected artifact mode: ${(j:, :)skippedLocalizedImportedKeys}"
    else
      echo "    ℹ️  Skipping ${#skippedLocalizedImportedKeys[@]} imported localized key(s) outside selected artifact mode (for example: ${(j:, :)skippedLocalizedImportedKeys[1,5]})"
    fi
  fi

  for preferenceLine in "${supportedPreferenceLines[@]}"; do
    candidateKey="${preferenceLine%%|*}"
    preferenceType="${preferenceLine#*|}"
    importedKey="${candidateKey}"

    if isLocalizedPlistKey "${importedKey}" && ! shouldKeepLocalizedPlistKey "${importedKey}"; then
      continue
    fi

    if ! /usr/libexec/PlistBuddy -c "Print :${importedKey}" "${sourcePlist}" >/dev/null 2>&1; then
      continue
    fi

    importedValue="$(
      /usr/libexec/PlistBuddy -c "Print :${importedKey}" "${sourcePlist}" 2>/dev/null
    )"

    if [[ "${importedKey}" == "ScriptLog" ]]; then
      if [[ "${importedValue:t}" == "${newRDNN}.log" ]] && isSafeScriptLogPath "${importedValue}"; then
        resolvedScriptLogPath="${importedValue}"
        echo "    ℹ️  Preserving imported ScriptLog: ${resolvedScriptLogPath}"
      elif [[ "${importedValue:t}" == "${newRDNN}.log" ]]; then
        echo "    ⚠️  Imported ScriptLog '${importedValue}' is not a safe absolute path; using ${resolvedScriptLogPath}"
      else
        echo "    ⚠️  Imported ScriptLog basename '${importedValue:t}' does not match '${newRDNN}.log'; using ${resolvedScriptLogPath}"
      fi
      continue
    fi

    if [[ "${preferenceType}" == "string" ]]; then
      normalizedValue="$(normalizeImportedLaneMarker "${importedValue}" "${deploymentMode}")"
      if [[ "${normalizedValue}" != "${importedValue}" ]]; then
        importedValue="${normalizedValue}"
        normalizedLaneMarkerCount=$(( normalizedLaneMarkerCount + 1 ))
      fi
    fi

    writePreferenceOverride "${targetPlist}" "${importedKey}" "${preferenceType}" "${importedValue}"
  done

  if (( normalizedLaneMarkerCount > 0 )); then
    echo "    🧹 Normalized lane marker in ${normalizedLaneMarkerCount} imported value(s) for '${deploymentMode}' lane"
  fi

  if [[ -n "${importedLegacyMinimumDiskFreePercentage}" ]]; then
    resolvedMinimumDiskFreeGB="$(
      /usr/libexec/PlistBuddy -c "Print :MinimumDiskFreeGB" "${targetPlist}" 2>/dev/null || true
    )"
    if /usr/libexec/PlistBuddy -c "Print :MinimumDiskFreeGB" "${sourcePlist}" >/dev/null 2>&1; then
      importedMinimumDiskFreeGB="$(
        /usr/libexec/PlistBuddy -c "Print :MinimumDiskFreeGB" "${sourcePlist}" 2>/dev/null || true
      )"
      if [[ "${importedMinimumDiskFreeGB}" == "${resolvedMinimumDiskFreeGB}" ]]; then
        echo "    ⚠️  Dropping deprecated MinimumDiskFreePercentage (${importedLegacyMinimumDiskFreePercentage}%); keeping imported MinimumDiskFreeGB (${resolvedMinimumDiskFreeGB} GB)"
      else
        echo "    ⚠️  Dropping deprecated MinimumDiskFreePercentage (${importedLegacyMinimumDiskFreePercentage}%); imported MinimumDiskFreeGB '${importedMinimumDiskFreeGB}' was invalid, using MinimumDiskFreeGB (${resolvedMinimumDiskFreeGB:-unset} GB, sample default)"
        echo "        Low-disk-space warning now uses fixed GB free, not a percentage of disk size; review before deployment"
      fi
    else
      echo "    ⚠️  Replaced deprecated MinimumDiskFreePercentage (${importedLegacyMinimumDiskFreePercentage}%) with MinimumDiskFreeGB (${resolvedMinimumDiskFreeGB:-unset} GB, sample default)"
      echo "        Low-disk-space warning now uses fixed GB free, not a percentage of disk size; review before deployment"
    fi
  fi

  reportImportedTemplatesMissingBatteryPlaceholder "${sourcePlist}" "${targetPlist}"

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
      echo "❎ Exiting at user request."
      exit 0
    fi

    newRDNN="${userRDNN:-${currentRDNN}}"
  else
    read -r "?Enter Your Organization’s Reverse Domain Name Notation (or ‘X’ to exit): " newRDNN

    if [[ "${newRDNN}" == [Xx] ]]; then
      echo "❎ Exiting at user request."
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
echo "🏷️  Using '${newRDNN}' as the Reverse Domain Name Notation"
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
    echo "ℹ️  Prior ${priorConfigLabel} supplied; skipping IT support, branding and restart policy prompts."
    echo ""
  else

    showInteractiveConfigurationHeader
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎛️  IT Support, Branding, Restart & Aggressive Mode Policy (Interactive)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    defaultSupportTeamName="IT Support"
    defaultSupportTeamPhone="+1 (801) 555-1212"
    defaultSupportTeamEmail="rescue@${derivedDomain}"
    defaultSupportTeamWebsite="https://support.${derivedDomain}"
    defaultHideSupportTeamPhone="NO"
    defaultHideSupportTeamEmail="NO"
    defaultHideSupportTeamWebsite="NO"
    defaultHideSupportKB="NO"
    defaultHideSupportAssistanceMessage="NO"
    defaultEnableInfoButton="YES"
    defaultEnableKnowledgeBase="YES"
    defaultSupportKB="Update macOS on Mac"
    defaultInfoButtonAction="${defaultSupportTeamWebsite}"
    defaultInfoButtonText="${defaultSupportKB}"
    defaultSupportKBURL="[Update macOS on Mac](${defaultInfoButtonAction})"
    defaultOrganizationOverlayIconURL="https://usw2.ics.services.jamfcloud.com/icon/hash_2d64ce7f0042ad68234a2515211adb067ad6714703dd8ebd6f33c1ab30354b1d"
    defaultOrganizationOverlayIconURLdark="https://use2.ics.services.jamfcloud.com/icon/hash_d3a3bc5e06d2db5f9697f9b4fa095bfecb2dc0d22c71aadea525eb38ff981d39"
    defaultSwapOverlayAndLogo="NO"
    defaultPastDeadlineRestartBehavior="Off"
    defaultDaysPastDeadlineRestartWorkflow="2"
    defaultAggressiveModePastDeadlineHours="2"
    defaultAggressiveModeFrequencyMinutes="20"

    promptWithDefault "Support Team Name" "${defaultSupportTeamName}" "supportTeamName"
    promptWithDefault "Support Team Phone" "${defaultSupportTeamPhone}" "supportTeamPhone"
    promptWithDefault "Hide Support Team Phone (YES/NO)" "${defaultHideSupportTeamPhone}" "hideSupportTeamPhone"
    promptWithDefault "Support Team Email" "${defaultSupportTeamEmail}" "supportTeamEmail"
    promptWithDefault "Hide Support Team Email (YES/NO)" "${defaultHideSupportTeamEmail}" "hideSupportTeamEmail"
    promptWithDefault "Support Team Website" "${defaultSupportTeamWebsite}" "supportTeamWebsite"
    promptWithDefault "Hide Support Team Website (YES/NO)" "${defaultHideSupportTeamWebsite}" "hideSupportTeamWebsite"
    defaultInfoButtonAction="${supportTeamWebsite}"

    hideSupportTeamPhone="$(normalizeBoolean "${hideSupportTeamPhone}")"
    if [[ -z "${hideSupportTeamPhone}" ]]; then
      echo "⚠️  Invalid input for HideSupportTeamPhone; defaulting to ${defaultHideSupportTeamPhone}"
      hideSupportTeamPhone="$(normalizeBoolean "${defaultHideSupportTeamPhone}")"
    fi

    hideSupportTeamEmail="$(normalizeBoolean "${hideSupportTeamEmail}")"
    if [[ -z "${hideSupportTeamEmail}" ]]; then
      echo "⚠️  Invalid input for HideSupportTeamEmail; defaulting to ${defaultHideSupportTeamEmail}"
      hideSupportTeamEmail="$(normalizeBoolean "${defaultHideSupportTeamEmail}")"
    fi

    hideSupportTeamWebsite="$(normalizeBoolean "${hideSupportTeamWebsite}")"
    if [[ -z "${hideSupportTeamWebsite}" ]]; then
      echo "⚠️  Invalid input for HideSupportTeamWebsite; defaulting to ${defaultHideSupportTeamWebsite}"
      hideSupportTeamWebsite="$(normalizeBoolean "${defaultHideSupportTeamWebsite}")"
    fi

    promptWithDefault "Info Button ('YES' to specify; 'NO' to hide)" "${defaultEnableInfoButton}" "enableInfoButton"
    enableInfoButton="$(normalizeBoolean "${enableInfoButton}")"
    if [[ -z "${enableInfoButton}" ]]; then
      echo "⚠️  Invalid input for Info Button prompt; defaulting to ${defaultEnableInfoButton}"
      enableInfoButton="$(normalizeBoolean "${defaultEnableInfoButton}")"
    fi

    if [[ "${enableInfoButton}" == "true" ]]; then
      promptWithDefault "Info Button Text" "${defaultInfoButtonText}" "infoButtonText"
      promptWithDefault "Info Button Action" "${defaultInfoButtonAction}" "infoButtonAction"

      promptWithDefault "Knowledge Base Row ('YES' to specify; 'NO' to hide)" "${defaultEnableKnowledgeBase}" "enableKnowledgeBase"
      enableKnowledgeBase="$(normalizeBoolean "${enableKnowledgeBase}")"
      if [[ -z "${enableKnowledgeBase}" ]]; then
        echo "⚠️  Invalid input for Knowledge Base prompt; defaulting to ${defaultEnableKnowledgeBase}"
        enableKnowledgeBase="$(normalizeBoolean "${defaultEnableKnowledgeBase}")"
      fi

      if [[ "${enableKnowledgeBase}" == "true" ]]; then
        hideSupportKB="false"
        promptWithDefault "Support KB Title" "${defaultSupportKB}" "supportKB"

        defaultSupportKBURL="[${supportKB}](${infoButtonAction})"
        promptWithDefault "Support KB Markdown Link" "${defaultSupportKBURL}" "supportKBURL"
      else
        hideSupportKB="true"
        supportKB=""
        supportKBURL=""
      fi
    else
      hideSupportKB="true"
      supportKB=""
      infoButtonAction=""
      supportKBURL=""
      infoButtonText="hide"
      defaultHideSupportAssistanceMessage="YES"
      echo ""
      echo "ℹ️  Info button and help image hidden; the (?) help message button remains."
      echo ""
    fi

    promptWithDefault "Hide Support Assistance Message (YES/NO)" "${defaultHideSupportAssistanceMessage}" "hideSupportAssistanceMessage"
    hideSupportAssistanceMessage="$(normalizeBoolean "${hideSupportAssistanceMessage}")"
    if [[ -z "${hideSupportAssistanceMessage}" ]]; then
      echo "⚠️  Invalid input for HideSupportAssistanceMessage; defaulting to ${defaultHideSupportAssistanceMessage}"
      hideSupportAssistanceMessage="$(normalizeBoolean "${defaultHideSupportAssistanceMessage}")"
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

    while true; do
      promptWithDefault "Aggressive Mode Past Deadline Hours (0-999; use 720 to effectively suppress)" "${defaultAggressiveModePastDeadlineHours}" "aggressiveModePastDeadlineHours"
      if [[ "${aggressiveModePastDeadlineHours}" == <-> ]] && (( aggressiveModePastDeadlineHours >= 0 && aggressiveModePastDeadlineHours <= 999 )); then
        break
      fi
      echo "⚠️  Invalid input for AggressiveModePastDeadlineHours; enter an integer from 0 to 999."
    done

    while true; do
      promptWithDefault "Aggressive Mode Frequency Minutes (1-999)" "${defaultAggressiveModeFrequencyMinutes}" "aggressiveModeFrequencyMinutes"
      if [[ "${aggressiveModeFrequencyMinutes}" == <-> ]] && (( aggressiveModeFrequencyMinutes >= 1 && aggressiveModeFrequencyMinutes <= 999 )); then
        break
      fi
      echo "⚠️  Invalid input for AggressiveModeFrequencyMinutes; enter an integer from 1 to 999."
    done

    echo ""
  fi
fi

if [[ "${interactiveMode}" == true && "${localizationSelectionProvidedViaCLI}" == false ]]; then
  promptForLocalizationSelection
fi

if ! configureLocalizationFilter "${requestedLocalizationMode}" "${requestedLocalizationLanguages}"; then
  echo "❌ Invalid localization filter selection."
  exit 1
fi

echo "🌐 Artifact Localization: $(localizationFilterSummary)"
echo



####################################################################################################
# Deployment Mode Selection
####################################################################################################

# Prompt for deployment mode if not specified via CLI
if [[ "${skipModePrompt}" == false ]]; then
  if [[ -n "${nearMissDeploymentModeToken}" ]]; then
    echo
    echo "⚠️  Prior ${priorConfigLabel} filename includes '-${nearMissDeploymentModeToken}-', but deployment mode was not inferred."
    if [[ "${priorConfigLabel}" == "mobileconfig" ]]; then
      echo "    Exact filename suffix required: -<lane>.mobileconfig, -<lane>-unsigned.mobileconfig or -<lane>-signed.mobileconfig"
    else
      echo "    Exact filename suffix required: -dev.plist, -test.plist or -prod.plist"
    fi
    echo "    Re-run with --lane ${nearMissDeploymentModeToken}, or rename prior ${priorConfigLabel} to exact supported suffix."
  fi

  echo
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🚦 Select Deployment Mode:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  echo "  1) 🧪 Development - Keep placeholder text for local testing"
  echo "  2) 🔬 Testing     - Replace placeholder text with 'TEST' for staging"
  echo "  3) 🚀 Production  - Remove placeholder text for clean deployment"
  echo
  echo "  [Press ‘X’ to exit ❎]"
  echo
  while true; do
    if ! read -r "?Specify Deployment Mode [1/2/3]: " modeChoice; then
      echo
      echo "❌ No deployment mode entered; re-run with --lane <dev|test|prod>."
      exit 1
    fi

    case "${modeChoice}" in
      1) deploymentMode="dev" ;;
      2) deploymentMode="test" ;;
      3)
        deploymentMode="prod"
        ;;
      [Xx])
        echo "❎ Exiting at user request."
        exit 0
        ;;
      *)
        # Never fall through to production artifacts on a mistyped selection
        echo "⚠️  Invalid selection '${modeChoice}'. Enter 1, 2, 3, or X."
        continue
        ;;
    esac
    break
  done
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Deployment Mode: ${deploymentMode}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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
/usr/bin/awk '
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
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"

    if [[ $line == "cat <<'ENDOFSCRIPT'"* ]]; then
      printf "%s\n" "$line"
      cat "${patchedMessage}"
      inBlock=true
      continue
    fi

    if [[ $inBlock == false ]]; then
      printf "%s\n" "$line"
    elif [[ $line == "ENDOFSCRIPT" ]]; then
      if [[ -n "$lastMessageTrimmed" ]]; then
        echo ""
      fi
      printf "%s\n" "$line"
      inBlock=false
    fi
  done < "${baseScript}"
} > "${tmpScript}"

embeddedMessage=$(mktemp -t embeddedMessage)
expectedEmbeddedMessage=$(mktemp -t expectedEmbeddedMessage)
cp "${patchedMessage}" "${expectedEmbeddedMessage}"
if [[ -n "${lastMessageTrimmed}" ]]; then
  printf "\n" >> "${expectedEmbeddedMessage}"
fi

/usr/bin/awk '
  $0 == "cat <<\047ENDOFSCRIPT\047" {
    inBlock = 1
    next
  }
  inBlock && $0 == "ENDOFSCRIPT" {
    exit
  }
  inBlock {
    print
  }
' "${tmpScript}" > "${embeddedMessage}"

if ! cmp -s "${expectedEmbeddedMessage}" "${embeddedMessage}"; then
  rm -f "${patchedMessage}" "${expectedEmbeddedMessage}" "${embeddedMessage}" "${tmpScript}"
  echo "❌ Assembly failed — embedded reminder runtime differs from prepared source."
  exit 1
fi

if ! zsh -n "${embeddedMessage}" >/dev/null 2>&1; then
  rm -f "${patchedMessage}" "${expectedEmbeddedMessage}" "${embeddedMessage}" "${tmpScript}"
  echo "❌ Assembly failed — embedded reminder runtime did not pass syntax validation."
  exit 1
fi

rm -f "${patchedMessage}" "${expectedEmbeddedMessage}" "${embeddedMessage}"



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
  echo "    ❌ Syntax check failed!"
  exit 1
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
        -e "s/${placeholderMarker}:?[[:space:]]+//gI" \
        -e "s/${placeholderMarker}//gI" \
        -e "s/${legacyPlaceholderMarker}:?[[:space:]]+//gI" \
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
      echo "    🔧 Importing supported values from prior ${priorConfigLabel} …"
      if ! applyImportedPreferences "${priorPlistPath}" "${plistOutput}"; then
        echo "❌ Failed to import supported values from prior ${priorConfigLabel}."
        exit 1
      fi
    else
      echo "    🔧 Applying IT support, branding, restart and aggressive mode values …"
      /usr/bin/plutil -replace SupportTeamName -string "${supportTeamName}" "${plistOutput}"
      /usr/bin/plutil -replace SupportTeamPhone -string "${supportTeamPhone}" "${plistOutput}"
      /usr/bin/plutil -replace HideSupportTeamPhone -bool "${hideSupportTeamPhone}" "${plistOutput}"
      /usr/bin/plutil -replace SupportTeamEmail -string "${supportTeamEmail}" "${plistOutput}"
      /usr/bin/plutil -replace HideSupportTeamEmail -bool "${hideSupportTeamEmail}" "${plistOutput}"
      /usr/bin/plutil -replace SupportTeamWebsite -string "${supportTeamWebsite}" "${plistOutput}"
      /usr/bin/plutil -replace HideSupportTeamWebsite -bool "${hideSupportTeamWebsite}" "${plistOutput}"
      /usr/bin/plutil -replace SupportKB -string "${supportKB}" "${plistOutput}"
      /usr/bin/plutil -replace HideSupportKB -bool "${hideSupportKB}" "${plistOutput}"
      /usr/bin/plutil -replace InfoButtonAction -string "${infoButtonAction}" "${plistOutput}"
      /usr/bin/plutil -replace SupportKBURL -string "${supportKBURL}" "${plistOutput}"
      /usr/bin/plutil -replace InfoButtonText -string "${infoButtonText}" "${plistOutput}"
      /usr/bin/plutil -replace InfoButtonTextLocalized_en -string "${infoButtonText}" "${plistOutput}"
      /usr/bin/plutil -replace HideSupportAssistanceMessage -bool "${hideSupportAssistanceMessage}" "${plistOutput}"
      /usr/bin/plutil -replace OrganizationOverlayIconURL -string "${organizationOverlayIconURL}" "${plistOutput}"
      /usr/bin/plutil -replace OrganizationOverlayIconURLdark -string "${organizationOverlayIconURLdark}" "${plistOutput}"
      /usr/bin/plutil -replace SwapOverlayAndLogo -bool "${swapOverlayAndLogo}" "${plistOutput}"
      /usr/bin/plutil -replace PastDeadlineRestartBehavior -string "${pastDeadlineRestartBehavior}" "${plistOutput}"
      /usr/bin/plutil -replace AggressiveModePastDeadlineHours -integer "${aggressiveModePastDeadlineHours}" "${plistOutput}"
      /usr/bin/plutil -replace AggressiveModeFrequencyMinutes -integer "${aggressiveModeFrequencyMinutes}" "${plistOutput}"

      if [[ "${pastDeadlineRestartBehavior}" != "Off" ]]; then
        /usr/bin/plutil -replace DaysPastDeadlineRestartWorkflow -integer "${daysPastDeadlineRestartWorkflow}" "${plistOutput}"
      fi

      if [[ "${enableInfoButton}" != "true" ]]; then
        /usr/bin/plutil -replace HelpImage -string "hide" "${plistOutput}"
      fi
    fi
  fi

  /usr/bin/plutil -replace ScriptLog -string "${resolvedScriptLogPath}" "${plistOutput}"

  removedLocalizedKeyCount="$(filterLocalizedKeysInXmlFile "${plistOutput}")" || {
    echo "❌ Failed to filter localized keys in ${plistOutput}."
    exit 1
  }
  if ! /usr/bin/plutil -lint "${plistOutput}" >/dev/null 2>&1; then
    echo "❌ Filtered plist failed validation: ${plistOutput}"
    exit 1
  fi
  if [[ "${removedLocalizedKeyCount}" != "0" ]]; then
    echo "    🌐 Removed ${removedLocalizedKeyCount} localized key(s) from generated plist"
  fi

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
    | sed -e 's/^[[:space:]]*//' -e 's/^/                                /'
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
  echo "❌ Profile syntax check failed: ${mobileconfigOutput}"
  exit 1
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
# Update scriptLog Based on RDNN
####################################################################################################

echo
echo "🔁 Updating scriptLog path based on RDNN …"

if ! isSafeScriptLogPath "${resolvedScriptLogPath}"; then
  echo "❌ Refusing to write unsafe scriptLog path into assembled script: ${resolvedScriptLogPath}"
  exit 1
fi

# Update outer deployment script plus embedded reminder script, but leave the
# dor-starter template placeholder untouched for runtime substitution.
scriptLogUpdateTmp="${outputScript}.scriptlog.tmp"
/usr/bin/awk \
  -v scriptLogReplacement="scriptLog=\"${resolvedScriptLogPath}\"" \
  -v scriptLogPreferenceReplacement="    [\"scriptLog\"]=\"string|${resolvedScriptLogPath}\"" '
  /^function createDorStarterScript\(\)/ {
    reachedDorStarterFunction = 1
  }

  !reachedDorStarterFunction && /^scriptLog="[^"]*"$/ {
    print scriptLogReplacement
    next
  }

  !reachedDorStarterFunction && /^[[:space:]]*\["scriptLog"\]="string\|[^"]*"$/ {
    print scriptLogPreferenceReplacement
    next
  }

  {
    print
  }
' "${outputScript}" > "${scriptLogUpdateTmp}" || {
  echo "❌ Failed to update scriptLog path in assembled script."
  rm -f "${scriptLogUpdateTmp}" 2>/dev/null || true
  exit 1
}

mv "${scriptLogUpdateTmp}" "${outputScript}" || {
  echo "❌ Failed to replace assembled script after scriptLog update."
  rm -f "${scriptLogUpdateTmp}" 2>/dev/null || true
  exit 1
}

if ! zsh -n "${outputScript}" >/dev/null 2>&1; then
  echo "❌ Syntax check failed after scriptLog update!"
  exit 1
fi

chmod +x "${outputScript}" || {
  echo "❌ Failed to restore execute permission on assembled script."
  exit 1
}



####################################################################################################
# Exit
####################################################################################################

echo
echo "🏁 Done."
echo
echo "📦 Deployment Artifacts:"
echo "         Assembled Script: ${newOutputScript#$projectDir/}"
echo "     Organizational Plist: ${plistOutput#$projectDir/}"
echo "    Configuration Profile: ${mobileconfigOutput#$projectDir/}"
echo

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  Important Next Steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

case "${deploymentMode}" in
  dev)
    echo "  🧪 Development Artifacts Generated:"
    echo "    - Legacy 'Sample' placeholders replaced with '${placeholderMarker}'"
    if [[ "${priorPlistImported}" == true ]]; then
      echo "    - Supported configuration values imported from prior ${priorConfigLabel}"
      echo "    - Prior ${priorConfigLabel}: ${priorConfigSourcePath}"
      echo "    - ScriptLog resolved to '${resolvedScriptLogPath}'"
    fi
    echo "    - Safe to deploy for local validation"
    echo "    - NOT suitable for production use"
    ;;
  test)
    echo "  Testing Artifacts Generated:"
    echo "    - All placeholder text replaced with 'TEST'"
    echo "    - Suitable for staging / QA environments"
    echo "    - NOT suitable for production use"
    ;;
  prod)
    echo "  Production Artifacts Generated:"
    echo "    - All placeholder text removed (clean output)"
    echo "    - Localization artifact mode: $(localizationFilterSummary)"
    if [[ "${interactiveMode}" == true ]]; then
      if [[ "${priorPlistImported}" == true ]]; then
        echo "    - Supported configuration values imported from prior ${priorConfigLabel}"
        echo "    - Prior ${priorConfigLabel}: ${priorConfigSourcePath}"
        echo "    - ScriptLog resolved to '${resolvedScriptLogPath}'"
      else
        echo "    - IT support, branding, restart and aggressive mode values applied from prompts"
        echo "    - Past-deadline restart policy set to '${pastDeadlineRestartBehavior}'"
        echo "    - Aggressive mode begins ${aggressiveModePastDeadlineHours} hour(s) past deadline and repeats every ${aggressiveModeFrequencyMinutes} minute(s)"
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
    echo "    - DailyReminderTimes baseline schedule"
    echo "    - AggressiveModePastDeadlineHours and AggressiveModeFrequencyMinutes"
    if [[ -n "${importedLegacyMinimumDiskFreePercentage}" ]]; then
      echo "    - MinimumDiskFreeGB (replaces imported MinimumDiskFreePercentage ${importedLegacyMinimumDiskFreePercentage}%)"
    fi
    if [[ -n "${importedTemplatesMissingBatteryPlaceholder}" ]]; then
      echo "    - Add {batteryWarningMessage} to imported templates: ${importedTemplatesMissingBatteryPlaceholder}"
    fi
    echo "    - Localization key set matches intended artifact mode"
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
echo "====================================================================================="
echo
exit 0
