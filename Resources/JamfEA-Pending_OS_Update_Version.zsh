#!/bin/zsh --no-rcs
# EA: DDM Pending OS Update Version
# Version: 3.3.0b5
# Reports a pending DDM-enforced macOS update version when install.log state is trustworthy.
# Created by: @robjschroeder 10.10.2025
# Hardened to fail closed on conflicting or invalid DDM declaration state

# Safety: don't use -e or pipefail in Jamf EA context
set -u

# Internal fixture-testing hooks for local validation only.
# These are not supported admin-facing settings.
installLogPath="${installLogPathOverride:-/var/log/install.log}"
ddmResolverLookbackLines="${ddmResolverLookbackLinesOverride:-4000}"
currentVersion="${currentVersionOverride:-$(/usr/bin/sw_vers -productVersion 2>/dev/null || true)}"
currentBuild="${currentBuildOverride:-$(/usr/bin/sw_vers -buildVersion 2>/dev/null || true)}"

ddmResolverStatus=""
ddmResolverFailureMarker=""
ddmResolverConflictSummary=""
ddmResolverSource=""
ddmDeclarationLogTimestamp=""
ddmEnforcedInstallDate=""
ddmVersionString=""
ddmBuildVersionString=""
ddmLogTimestampRegex='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}(:[0-9]{2})?$'
typeset -ga ddmRecentInstallLogWindow=()
typeset -gA ddmTimestampEpochCache=()
typeset -gA ddmInvalidCandidateContexts=()

# Load is-at-least for version comparison
autoload -Uz is-at-least



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Utilities
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function emitResult() {
    echo "<result>${1}</result>"
    exit 0
}

function emitNoneResult() {
    emitResult "None"
}

function currentMacSatisfiesCandidate() {
    if ! isValidDDMVersionString "${ddmVersionString}"; then
        return 1
    fi

    if [[ -n "${currentBuild}" && -n "${ddmBuildVersionString}" && "${ddmBuildVersionString}" != "(null)" && "${currentBuild}" == "${ddmBuildVersionString}" ]]; then
        return 0
    fi

    if [[ -n "${currentVersion}" ]] && isValidDDMVersionString "${currentVersion}" && is-at-least "${ddmVersionString}" "${currentVersion}"; then
        return 0
    fi

    return 1
}

function tailRecentInstallLogWindow() {
    if [[ ! -r "${installLogPath}" ]]; then
        ddmRecentInstallLogWindow=()
        return 1
    fi

    ddmRecentInstallLogWindow=( ${(f)"$(tail -n "${ddmResolverLookbackLines}" "${installLogPath}" 2>/dev/null)"} )

    if [[ ${#ddmRecentInstallLogWindow[@]} -eq 0 ]]; then
        return 1
    fi

    return 0
}

function isValidDDMVersionString() {
    local value="${1}"
    local ddmVersionRegex='^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$'

    if [[ -z "${value}" ]]; then
        return 1
    fi

    if [[ "${value}" =~ ${ddmVersionRegex} ]]; then
        return 0
    fi

    return 1
}

function extractDDMLogTimestamp() {
    local logLine="${1}"
    local dateToken="${logLine%% *}"
    local remainder="${logLine#* }"
    local timeToken=""

    parsedDDMLogTimestamp=""

    if [[ "${remainder}" == "${logLine}" ]]; then
        return 1
    fi

    timeToken="${remainder%% *}"
    parsedDDMLogTimestamp="${dateToken} ${timeToken}"

    if [[ ! "${parsedDDMLogTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
        parsedDDMLogTimestamp=""
        return 1
    fi

    return 0
}

function ddmDaysFromCivil() {
    local year="${1}"
    local month="${2}"
    local day="${3}"
    local monthAdjustment=9
    local era=0
    local yearOfEra=0
    local dayOfYear=0
    local dayOfEra=0

    if (( month <= 2 )); then
        (( year-- ))
    fi

    if (( month > 2 )); then
        monthAdjustment=-3
    fi

    if (( year >= 0 )); then
        (( era = year / 400 ))
    else
        (( era = (year - 399) / 400 ))
    fi

    (( yearOfEra = year - (era * 400) ))
    (( dayOfYear = ((153 * (month + monthAdjustment)) + 2) / 5 + day - 1 ))
    (( dayOfEra = (yearOfEra * 365) + (yearOfEra / 4) - (yearOfEra / 100) + dayOfYear ))

    ddmDaysFromCivilResult=$(( (era * 146097) + dayOfEra - 719468 ))
    return 0
}

function ddmLogTimestampToEpoch() {
    local rawTimestamp="${1}"
    local dateToken="${rawTimestamp%% *}"
    local timeAndOffset="${rawTimestamp#* }"
    local timeToken="${timeAndOffset[1,8]}"
    local offsetToken="${timeAndOffset[9,-1]}"
    local year=0
    local month=0
    local day=0
    local hour=0
    local minute=0
    local second=0
    local offsetSign=""
    local offsetHours=0
    local offsetMinutes=0
    local totalOffsetMinutes=0
    local days=0
    local parsedEpoch=""

    parsedDDMLogTimestampEpoch=""

    if [[ -n "${ddmTimestampEpochCache[${rawTimestamp}]:-}" ]]; then
        parsedDDMLogTimestampEpoch="${ddmTimestampEpochCache[${rawTimestamp}]}"
        return 0
    fi

    case "${offsetToken}" in
        [+-][0-9][0-9])
            offsetSign="${offsetToken[1,1]}"
            offsetHours=$(( 10#${offsetToken[2,3]} ))
            offsetMinutes=0
            ;;
        [+-][0-9][0-9]:[0-9][0-9])
            offsetSign="${offsetToken[1,1]}"
            offsetHours=$(( 10#${offsetToken[2,3]} ))
            offsetMinutes=$(( 10#${offsetToken[5,6]} ))
            ;;
        *)
            return 1
            ;;
    esac

    year=$(( 10#${dateToken[1,4]} ))
    month=$(( 10#${dateToken[6,7]} ))
    day=$(( 10#${dateToken[9,10]} ))
    hour=$(( 10#${timeToken[1,2]} ))
    minute=$(( 10#${timeToken[4,5]} ))
    second=$(( 10#${timeToken[7,8]} ))

    if ! ddmDaysFromCivil "${year}" "${month}" "${day}"; then
        return 1
    fi
    days="${ddmDaysFromCivilResult}"

    totalOffsetMinutes=$(( (offsetHours * 60) + offsetMinutes ))
    if [[ "${offsetSign}" == "-" ]]; then
        totalOffsetMinutes=$(( -totalOffsetMinutes ))
    fi

    parsedEpoch=$(( (days * 86400) + (hour * 3600) + (minute * 60) + second - (totalOffsetMinutes * 60) ))
    ddmTimestampEpochCache[${rawTimestamp}]="${parsedEpoch}"
    parsedDDMLogTimestampEpoch="${parsedEpoch}"
    return 0
}

function parseDDMDeclarationFieldsFromText() {
    local declarationText="${1}"

    if [[ "${declarationText}" != *"|EnforcedInstallDate:"* || "${declarationText}" != *"|VersionString:"* || "${declarationText}" != *"|BuildVersionString:"* ]]; then
        return 1
    fi

    parsedDDMEnforcedInstallDate="${${declarationText##*|EnforcedInstallDate:}%%|*}"
    parsedDDMVersionString="${${declarationText##*|VersionString:}%%|*}"
    parsedDDMBuildVersionString="${${declarationText##*|BuildVersionString:}%%|*}"

    if [[ -z "${parsedDDMEnforcedInstallDate}" || -z "${parsedDDMVersionString}" || -z "${parsedDDMBuildVersionString}" ]]; then
        return 1
    fi

    return 0
}

function parseDDMDeclarationFromLine() {
    local logLine="${1}"

    parsedDDMSourceType=""
    parsedDDMLogTimestamp=""
    parsedDDMEnforcedInstallDate=""
    parsedDDMVersionString=""
    parsedDDMBuildVersionString=""
    parsedDDMRawLine="${logLine}"

    if [[ "${logLine}" == *"declarationFromKeys]: Found currently applicable declaration"* ]]; then
        parsedDDMSourceType="currentApplicableDeclaration"
    elif [[ "${logLine}" == *"declarationFromKeys]: Falling back to default applicable declaration"* ]]; then
        parsedDDMSourceType="defaultApplicableDeclaration"
    elif [[ "${logLine}" == *"Found DDM enforced install ("* ]]; then
        parsedDDMSourceType="foundDdmEnforcedInstall"
    elif [[ "${logLine}" == *"EnforcedInstallDate:"* && "${logLine}" == *"softwareupdated["* ]]; then
        parsedDDMSourceType="genericEnforcedInstallDate"
    else
        return 1
    fi

    if ! extractDDMLogTimestamp "${logLine}"; then
        return 1
    fi

    if ! parseDDMDeclarationFieldsFromText "${logLine}"; then
        return 1
    fi

    return 0
}

function noteInvalidDDMDeclarationFromLine() {
    local logLine="${1}"
    local candidateSignature=""

    if [[ "${logLine}" != *"Failed to add declaration:"* || "${logLine}" != *"Invalid declaration:"* ]]; then
        return 1
    fi

    if ! extractDDMLogTimestamp "${logLine}"; then
        return 1
    fi

    if ! parseDDMDeclarationFieldsFromText "${logLine}"; then
        return 1
    fi

    candidateSignature="${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}"
    ddmInvalidCandidateContexts[${candidateSignature}]="${logLine}"

    return 0
}

function ddmSourcePriority() {
    local sourceType="${1}"

    case "${sourceType}" in
        currentApplicableDeclaration)
            echo "4"
            ;;
        defaultApplicableDeclaration)
            echo "3"
            ;;
        foundDdmEnforcedInstall)
            echo "2"
            ;;
        genericEnforcedInstallDate)
            echo "1"
            ;;
        *)
            echo "0"
            ;;
    esac
}

function parseDDMDescriptorVersionFromLine() {
    local logLine="${1}"
    local descriptorText=""
    local descriptorToken=""
    local -a descriptorTokens=( )

    parsedDDMDescriptorVersion=""

    if [[ "${logLine}" != *"PrimaryDescriptor:"* || "${logLine}" == *"PrimaryDescriptor: (null)"* || "${logLine}" != *"SU:"* ]]; then
        return 1
    fi

    descriptorText="${logLine##* SU:}"
    descriptorTokens=( ${=descriptorText} )

    for descriptorToken in "${descriptorTokens[@]}"; do
        if isValidDDMVersionString "${descriptorToken}"; then
            parsedDDMDescriptorVersion="${descriptorToken}"
            break
        fi
    done

    if [[ -z "${parsedDDMDescriptorVersion}" ]]; then
        return 1
    fi

    return 0
}

function candidateHasNoMatchScanFailure() {
    local candidateVersion="${1}"
    local declarationEpoch="${2}"
    local lineIndex=0
    local currentLine=""
    local lineTimestamp=""
    local lineEpoch=""
    local segmentActive="NO"

    ddmResolverFailureMarker=""

    for (( lineIndex = 1; lineIndex <= ${#ddmRecentInstallLogWindow[@]}; lineIndex++ )); do
        currentLine="${ddmRecentInstallLogWindow[$lineIndex]}"

        if [[ "${currentLine}" == *"requestedPMV="* ]]; then
            if ! extractDDMLogTimestamp "${currentLine}"; then
                continue
            fi
            lineTimestamp="${parsedDDMLogTimestamp}"

            if ! ddmLogTimestampToEpoch "${lineTimestamp}"; then
                continue
            fi
            lineEpoch="${parsedDDMLogTimestampEpoch}"

            if (( lineEpoch < declarationEpoch )); then
                continue
            fi

            if [[ "${currentLine}" == *"requestedPMV=${candidateVersion},"* || "${currentLine}" == *"requestedPMV=${candidateVersion})"* ]]; then
                segmentActive="YES"
            else
                segmentActive="NO"
            fi
            continue
        fi

        if [[ "${segmentActive}" != "YES" ]]; then
            continue
        fi

        if [[ "${currentLine}" != *"MADownloadNoMatchFound"* && "${currentLine}" != *"pallasNoPMVMatchFound=true"* && "${currentLine}" != *"No available updates found. Please try again later."* ]]; then
            continue
        fi

        if ! extractDDMLogTimestamp "${currentLine}"; then
            continue
        fi
        lineTimestamp="${parsedDDMLogTimestamp}"

        if ! ddmLogTimestampToEpoch "${lineTimestamp}"; then
            continue
        fi
        lineEpoch="${parsedDDMLogTimestampEpoch}"

        if (( lineEpoch < declarationEpoch )); then
            continue
        fi

        if [[ "${currentLine}" == *"MADownloadNoMatchFound"* ]]; then
            ddmResolverFailureMarker="MADownloadNoMatchFound"
            return 0
        fi

        if [[ "${currentLine}" == *"pallasNoPMVMatchFound=true"* ]]; then
            ddmResolverFailureMarker="pallasNoPMVMatchFound=true"
            return 0
        fi

        if [[ "${currentLine}" == *"No available updates found. Please try again later."* ]]; then
            ddmResolverFailureMarker="No available updates found. Please try again later."
            return 0
        fi
    done

    return 1
}

function candidateHasConflictingEvidence() {
    local candidateSignature="${1}"
    local candidateVersion="${2}"
    local firstDeclarationEpoch="${3}"
    local declarationEpoch="${4}"
    local lineIndex=0
    local currentLine=""
    local lineTimestamp=""
    local lineEpoch=""
    local parsedSignature=""
    local noUpdatesEpoch=""

    ddmResolverConflictSummary=""

    for (( lineIndex = 1; lineIndex <= ${#ddmRecentInstallLogWindow[@]}; lineIndex++ )); do
        currentLine="${ddmRecentInstallLogWindow[$lineIndex]}"

        if [[ "${currentLine}" != *"EnforcedInstallDate:"* && "${currentLine}" != *"PrimaryDescriptor:"* && "${currentLine}" != *"No updates found for DDM to enforce"* ]]; then
            continue
        fi

        if ! extractDDMLogTimestamp "${currentLine}"; then
            continue
        fi
        lineTimestamp="${parsedDDMLogTimestamp}"

        if ! ddmLogTimestampToEpoch "${lineTimestamp}"; then
            continue
        fi
        lineEpoch="${parsedDDMLogTimestampEpoch}"

        if (( lineEpoch < firstDeclarationEpoch )); then
            continue
        fi

        if [[ "${currentLine}" == *"EnforcedInstallDate:"* ]] && parseDDMDeclarationFromLine "${currentLine}"; then
            parsedSignature="${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}"

            if (( ${+ddmInvalidCandidateContexts[${parsedSignature}]} )); then
                continue
            fi

            if [[ -n "${noUpdatesEpoch}" ]]; then
                if [[ "${parsedSignature}" == "${candidateSignature}" ]]; then
                    if (( lineEpoch >= noUpdatesEpoch )); then
                        ddmResolverConflictSummary="Declaration persisted after 'No updates found for DDM to enforce'"
                        return 0
                    fi
                fi
            fi

            if (( lineEpoch < declarationEpoch )); then
                continue
            fi

            if [[ "${parsedSignature}" != "${candidateSignature}" ]]; then
                ddmResolverConflictSummary="Conflicting declaration: ${parsedDDMVersionString} | ${parsedDDMEnforcedInstallDate} | ${parsedDDMBuildVersionString} | ${parsedDDMSourceType}"
                return 0
            fi
        fi

        if (( lineEpoch < declarationEpoch )); then
            if [[ "${currentLine}" == *"No updates found for DDM to enforce"* ]]; then
                noUpdatesEpoch="${lineEpoch}"
            fi
            continue
        fi

        if parseDDMDescriptorVersionFromLine "${currentLine}"; then
            if [[ "${parsedDDMDescriptorVersion}" != "${candidateVersion}" ]]; then
                ddmResolverConflictSummary="Available descriptor ${parsedDDMDescriptorVersion} disagrees with DDM declaration ${candidateVersion}"
                return 0
            fi
        fi

        if [[ "${currentLine}" == *"No updates found for DDM to enforce"* ]]; then
            noUpdatesEpoch="${lineEpoch}"
        fi
    done

    return 1
}

function resolveDDMEnforcementFromInstallLog() {
    local line=""
    local candidateKey=""
    local candidateSignature=""
    local latestTimestamp=""
    local index=0
    local latestIndex=0
    local distinctCandidateCount=0
    local highestPriority=0
    local currentPriority=0
    local candidateEpoch=""
    local latestEpoch=0

    local -a candidateSourceTypes=()
    local -a candidateFirstTimestamps=()
    local -a candidateFirstEpochs=()
    local -a candidateTimestamps=()
    local -a candidateEpochs=()
    local -a candidateEnforcedDates=()
    local -a candidateVersions=()
    local -a candidateBuilds=()
    local -a candidateRawLines=()
    local -a filteredIndexes=()
    typeset -A seenCandidateIndexes=()

    ddmResolverStatus=""
    ddmResolverFailureMarker=""
    ddmResolverConflictSummary=""
    ddmResolverSource=""
    ddmDeclarationLogTimestamp=""
    ddmEnforcedInstallDate=""
    ddmVersionString=""
    ddmBuildVersionString=""
    ddmTimestampEpochCache=()
    ddmInvalidCandidateContexts=()

    if ! tailRecentInstallLogWindow; then
        ddmResolverStatus="missing"
        return 1
    fi

    for line in "${ddmRecentInstallLogWindow[@]}"; do
        noteInvalidDDMDeclarationFromLine "${line}" >/dev/null
    done

    for line in "${ddmRecentInstallLogWindow[@]}"; do
        if ! parseDDMDeclarationFromLine "${line}"; then
            continue
        fi

        if ! ddmLogTimestampToEpoch "${parsedDDMLogTimestamp}"; then
            continue
        fi
        candidateEpoch="${parsedDDMLogTimestampEpoch}"

        candidateSignature="${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}"
        if (( ${+ddmInvalidCandidateContexts[${candidateSignature}]} )); then
            continue
        fi

        candidateKey="${parsedDDMSourceType}|${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}"

        if (( ${+seenCandidateIndexes[${candidateKey}]} )); then
            index="${seenCandidateIndexes[${candidateKey}]}"
            if (( candidateEpoch > candidateEpochs[$index] )); then
                candidateTimestamps[$index]="${parsedDDMLogTimestamp}"
                candidateEpochs[$index]="${candidateEpoch}"
                candidateRawLines[$index]="${parsedDDMRawLine}"
            fi
            continue
        fi

        candidateSourceTypes+=( "${parsedDDMSourceType}" )
        candidateFirstTimestamps+=( "${parsedDDMLogTimestamp}" )
        candidateFirstEpochs+=( "${candidateEpoch}" )
        candidateTimestamps+=( "${parsedDDMLogTimestamp}" )
        candidateEpochs+=( "${candidateEpoch}" )
        candidateEnforcedDates+=( "${parsedDDMEnforcedInstallDate}" )
        candidateVersions+=( "${parsedDDMVersionString}" )
        candidateBuilds+=( "${parsedDDMBuildVersionString}" )
        candidateRawLines+=( "${parsedDDMRawLine}" )
        seenCandidateIndexes[${candidateKey}]="${#candidateSourceTypes[@]}"
    done

    if [[ ${#candidateSourceTypes[@]} -eq 0 ]]; then
        ddmResolverStatus="missing"
        return 1
    fi

    latestTimestamp="${candidateTimestamps[1]}"
    latestEpoch="${candidateEpochs[1]}"
    for (( index = 2; index <= ${#candidateTimestamps[@]}; index++ )); do
        if (( candidateEpochs[$index] > latestEpoch )); then
            latestTimestamp="${candidateTimestamps[$index]}"
            latestEpoch="${candidateEpochs[$index]}"
        fi
    done

    for (( index = 1; index <= ${#candidateSourceTypes[@]}; index++ )); do
        if (( candidateEpochs[$index] == latestEpoch )); then
            filteredIndexes+=( "${index}" )
        fi
    done

    highestPriority=0
    for index in "${filteredIndexes[@]}"; do
        currentPriority="$(ddmSourcePriority "${candidateSourceTypes[$index]}")"
        if (( currentPriority > highestPriority )); then
            highestPriority="${currentPriority}"
        fi
    done

    filteredIndexes=( )
    for (( index = 1; index <= ${#candidateSourceTypes[@]}; index++ )); do
        if (( candidateEpochs[$index] == latestEpoch )); then
            currentPriority="$(ddmSourcePriority "${candidateSourceTypes[$index]}")"
            if (( currentPriority == highestPriority )); then
                filteredIndexes+=( "${index}" )
            fi
        fi
    done

    distinctCandidateCount="${#filteredIndexes[@]}"
    if (( distinctCandidateCount != 1 )); then
        ddmResolverStatus="conflict"
        return 1
    fi

    latestIndex="${filteredIndexes[1]}"
    ddmResolverSource="${candidateSourceTypes[$latestIndex]}"
    ddmDeclarationLogTimestamp="${candidateTimestamps[$latestIndex]}"
    ddmEnforcedInstallDate="${candidateEnforcedDates[$latestIndex]}"
    ddmVersionString="${candidateVersions[$latestIndex]}"
    ddmBuildVersionString="${candidateBuilds[$latestIndex]}"
    candidateSignature="${ddmEnforcedInstallDate}|${ddmVersionString}|${ddmBuildVersionString}"

    if ! isValidDDMVersionString "${ddmVersionString}"; then
        ddmResolverStatus="invalidVersion"
        return 1
    fi

    if candidateHasConflictingEvidence "${candidateSignature}" "${ddmVersionString}" "${candidateFirstEpochs[$latestIndex]}" "${candidateEpochs[$latestIndex]}"; then
        ddmResolverStatus="conflict"
        return 1
    fi

    if candidateHasNoMatchScanFailure "${ddmVersionString}" "${candidateEpochs[$latestIndex]}"; then
        ddmResolverStatus="noMatch"
        return 1
    fi

    ddmResolverStatus="resolved"
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Extension Attribute Result
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

resolveDDMEnforcementFromInstallLog

if [[ -n "${ddmVersionString}" ]] && currentMacSatisfiesCandidate; then
    emitNoneResult
fi

case "${ddmResolverStatus}" in
    resolved)
        ;;
    conflict|noMatch|missing|invalidVersion)
        emitResult "${ddmResolverStatus}"
        ;;
    *)
        emitResult "missing"
        ;;
esac

echo "<result>${ddmVersionString}</result>"
