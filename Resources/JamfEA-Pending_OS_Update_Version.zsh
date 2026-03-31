#!/bin/zsh --no-rcs
# EA: DDM Pending OS Update Version
# Version: 3.1.0b8
# Reports a pending DDM-enforced macOS update version when install.log state is trustworthy.
# Created by: @robjschroeder 10.10.2025
# Hardened to fail closed on conflicting or invalid DDM declaration state

# Safety: don't use -e or pipefail in Jamf EA context
set -u

# Internal fixture-testing hooks for local validation only.
# These are not supported admin-facing settings.
installLogPath="${installLogPathOverride:-/var/log/install.log}"
ddmResolverLookbackLines="${ddmResolverLookbackLinesOverride:-4000}"

# Current OS info
currentBuild="$(/usr/bin/sw_vers -buildVersion 2>/dev/null || true)"
ddmResolverStatus=""
ddmResolverFailureMarker=""
ddmResolverConflictSummary=""
ddmResolverSource=""
ddmDeclarationLogTimestamp=""
ddmEnforcedInstallDate=""
ddmVersionString=""
ddmBuildVersionString=""
ddmLogTimestampRegex='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}$'
typeset -ga ddmRecentInstallLogWindow=()



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
    elif [[ "${logLine}" == *"EnforcedInstallDate:"* ]]; then
        parsedDDMSourceType="genericEnforcedInstallDate"
    else
        return 1
    fi

    parsedDDMLogTimestamp="${logLine[1,22]}"
    parsedDDMEnforcedInstallDate="${${logLine##*|EnforcedInstallDate:}%%|*}"
    parsedDDMVersionString="${${logLine##*|VersionString:}%%|*}"
    parsedDDMBuildVersionString="${${logLine##*|BuildVersionString:}%%|*}"

    if [[ ! "${parsedDDMLogTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
        return 1
    fi

    if [[ -z "${parsedDDMEnforcedInstallDate}" || -z "${parsedDDMVersionString}" || -z "${parsedDDMBuildVersionString}" ]]; then
        return 1
    fi

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
    local declarationTimestamp="${2}"
    local lineIndex=0
    local currentLine=""
    local lineTimestamp=""
    local segmentActive="NO"

    ddmResolverFailureMarker=""

    for (( lineIndex = 1; lineIndex <= ${#ddmRecentInstallLogWindow[@]}; lineIndex++ )); do
        currentLine="${ddmRecentInstallLogWindow[$lineIndex]}"
        lineTimestamp="${currentLine[1,22]}"

        if [[ ! "${lineTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
            continue
        fi

        if [[ "${lineTimestamp}" < "${declarationTimestamp}" ]]; then
            continue
        fi

        if [[ "${currentLine}" == *"requestedPMV="* ]]; then
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
    local firstDeclarationTimestamp="${3}"
    local declarationTimestamp="${4}"
    local lineIndex=0
    local currentLine=""
    local lineTimestamp=""
    local noUpdatesTimestamp=""

    ddmResolverConflictSummary=""

    for (( lineIndex = 1; lineIndex <= ${#ddmRecentInstallLogWindow[@]}; lineIndex++ )); do
        currentLine="${ddmRecentInstallLogWindow[$lineIndex]}"
        lineTimestamp="${currentLine[1,22]}"

        if [[ ! "${lineTimestamp}" =~ ${ddmLogTimestampRegex} ]]; then
            continue
        fi

        if [[ "${lineTimestamp}" < "${firstDeclarationTimestamp}" ]]; then
            continue
        fi

        if [[ "${currentLine}" == *"EnforcedInstallDate:"* ]] && parseDDMDeclarationFromLine "${currentLine}"; then
            if [[ -n "${noUpdatesTimestamp}" ]]; then
                if [[ "${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}" == "${candidateSignature}" ]]; then
                    if [[ "${lineTimestamp}" > "${noUpdatesTimestamp}" || "${lineTimestamp}" == "${noUpdatesTimestamp}" ]]; then
                        ddmResolverConflictSummary="Declaration persisted after 'No updates found for DDM to enforce'"
                        return 0
                    fi
                fi
            fi

            if [[ "${lineTimestamp}" < "${declarationTimestamp}" ]]; then
                continue
            fi

            if [[ "${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}" != "${candidateSignature}" ]]; then
                ddmResolverConflictSummary="Conflicting declaration: ${parsedDDMVersionString} | ${parsedDDMEnforcedInstallDate} | ${parsedDDMBuildVersionString} | ${parsedDDMSourceType}"
                return 0
            fi
        fi

        if [[ "${lineTimestamp}" < "${declarationTimestamp}" ]]; then
            if [[ "${currentLine}" == *"No updates found for DDM to enforce"* ]]; then
                noUpdatesTimestamp="${lineTimestamp}"
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
            noUpdatesTimestamp="${lineTimestamp}"
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

    local -a candidateSourceTypes=()
    local -a candidateFirstTimestamps=()
    local -a candidateTimestamps=()
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

    if ! tailRecentInstallLogWindow; then
        ddmResolverStatus="missing"
        return 1
    fi

    for line in "${ddmRecentInstallLogWindow[@]}"; do
        if ! parseDDMDeclarationFromLine "${line}"; then
            continue
        fi

        candidateKey="${parsedDDMSourceType}|${parsedDDMEnforcedInstallDate}|${parsedDDMVersionString}|${parsedDDMBuildVersionString}"

        if (( ${+seenCandidateIndexes[${candidateKey}]} )); then
            index="${seenCandidateIndexes[${candidateKey}]}"
            if [[ "${parsedDDMLogTimestamp}" > "${candidateTimestamps[$index]}" ]]; then
                candidateTimestamps[$index]="${parsedDDMLogTimestamp}"
                candidateRawLines[$index]="${parsedDDMRawLine}"
            fi
            continue
        fi

        candidateSourceTypes+=( "${parsedDDMSourceType}" )
        candidateFirstTimestamps+=( "${parsedDDMLogTimestamp}" )
        candidateTimestamps+=( "${parsedDDMLogTimestamp}" )
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
    for (( index = 2; index <= ${#candidateTimestamps[@]}; index++ )); do
        if [[ "${candidateTimestamps[$index]}" > "${latestTimestamp}" ]]; then
            latestTimestamp="${candidateTimestamps[$index]}"
        fi
    done

    for (( index = 1; index <= ${#candidateSourceTypes[@]}; index++ )); do
        if [[ "${candidateTimestamps[$index]}" == "${latestTimestamp}" ]]; then
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
        if [[ "${candidateTimestamps[$index]}" == "${latestTimestamp}" ]]; then
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

    if candidateHasConflictingEvidence "${candidateSignature}" "${ddmVersionString}" "${candidateFirstTimestamps[$latestIndex]}" "${ddmDeclarationLogTimestamp}"; then
        ddmResolverStatus="conflict"
        return 1
    fi

    if candidateHasNoMatchScanFailure "${ddmVersionString}" "${ddmDeclarationLogTimestamp}"; then
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

if [[ -n "${currentBuild}" && -n "${ddmBuildVersionString}" && "${ddmBuildVersionString}" != "(null)" && "${currentBuild}" == "${ddmBuildVersionString}" ]]; then
    emitNoneResult
fi

echo "<result>${ddmVersionString}</result>"
