#!/bin/zsh --no-rcs
# EA: DDM Pending OS Update Date
# Version: 3.1.0b8
# Reports a pending DDM-enforced macOS update date when install.log state is trustworthy.
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

# Jamf Pro Date data type sentinel values for non-date resolver states.
# 2000-01-01 00:00:00 = None / no pending update / already compliant
# 2000-01-01 00:00:01 = conflict
# 2000-01-01 00:00:02 = noMatch
# 2000-01-01 00:00:03 = missing
# 2000-01-01 00:00:04 = invalidVersion
# 2000-01-01 00:00:05 = unexpected resolver fallback
ddmDateCodeNone="2000-01-01 00:00:00"
ddmDateCodeConflict="2000-01-01 00:00:01"
ddmDateCodeNoMatch="2000-01-01 00:00:02"
ddmDateCodeMissing="2000-01-01 00:00:03"
ddmDateCodeInvalidVersion="2000-01-01 00:00:04"
ddmDateCodeUnexpected="2000-01-01 00:00:05"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Utilities
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function emitResult() {
    echo "<result>${1}</result>"
    exit 0
}

function emitNoneResult() {
    emitResult "${ddmDateCodeNone}"
}

function emitResolverStatusDateCode() {
    local resolverStatus="${1}"

    case "${resolverStatus}" in
        conflict)
            emitResult "${ddmDateCodeConflict}"
            ;;
        noMatch)
            emitResult "${ddmDateCodeNoMatch}"
            ;;
        missing)
            emitResult "${ddmDateCodeMissing}"
            ;;
        invalidVersion)
            emitResult "${ddmDateCodeInvalidVersion}"
            ;;
        None)
            emitResult "${ddmDateCodeNone}"
            ;;
        *)
            emitResult "${ddmDateCodeUnexpected}"
            ;;
    esac
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

function resolvePaddedEnforcementDateForCandidate() {
    local declarationTimestamp="${1}"
    local declarationSignature="${2}"
    local paddedDateRaw=""
    local paddedEpoch=""
    local nowEpoch=""

    paddedDateRaw="$(
        /usr/bin/tail -n "${ddmResolverLookbackLines}" "${installLogPath}" 2>/dev/null | /usr/bin/awk -v chosenTimestamp="${declarationTimestamp}" -v chosenSignature="${declarationSignature}" '
            function extractField(line, field,    needle, rest, pos) {
                needle = "|" field ":"
                pos = index(line, needle)
                if (!pos) {
                    return ""
                }

                rest = substr(line, pos + length(needle))
                pos = index(rest, "|")
                if (pos) {
                    return substr(rest, 1, pos - 1)
                }

                return rest
            }

            {
                logTimestamp = substr($0, 1, 22)
                if (logTimestamp !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}$/) {
                    next
                }

                if (logTimestamp < chosenTimestamp) {
                    next
                }

                if (index($0, "EnforcedInstallDate:")) {
                    enforcedInstallDate = extractField($0, "EnforcedInstallDate")
                    versionString = extractField($0, "VersionString")
                    buildVersionString = extractField($0, "BuildVersionString")

                    if (enforcedInstallDate != "" && versionString != "" && buildVersionString != "") {
                        if (enforcedInstallDate "|" versionString "|" buildVersionString != chosenSignature) {
                            conflictDetected = 1
                        }
                    }
                }

                if (index($0, "setPastDuePaddedEnforcementDate is set: ")) {
                    paddedDateRaw = substr($0, index($0, "setPastDuePaddedEnforcementDate is set: ") + 39)
                }
            }

            END {
                if (!conflictDetected && paddedDateRaw != "") {
                    print paddedDateRaw
                }
            }
        '
    )"

    if [[ -z "${paddedDateRaw}" ]]; then
        return 1
    fi

    paddedEpoch="$(
        /bin/date -jf "%a %b %d %H:%M:%S %Y" "${paddedDateRaw}" "+%s" 2>/dev/null \
        || echo ""
    )"
    nowEpoch="$(/bin/date +%s)"

    if [[ -z "${paddedEpoch}" || ! "${paddedEpoch}" =~ ^[0-9]+$ ]] || (( paddedEpoch <= nowEpoch )); then
        return 1
    fi

    printf '%s\n' "${paddedDateRaw}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Extension Attribute Result
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

resolveDDMEnforcementFromInstallLog

case "${ddmResolverStatus}" in
    resolved)
        ;;
    conflict|noMatch|missing|invalidVersion)
        emitResolverStatusDateCode "${ddmResolverStatus}"
        ;;
    *)
        emitResolverStatusDateCode "missing"
        ;;
esac

if [[ -n "${currentBuild}" && -n "${ddmBuildVersionString}" && "${ddmBuildVersionString}" != "(null)" && "${currentBuild}" == "${ddmBuildVersionString}" ]]; then
    emitNoneResult
fi

formattedDate=""
paddedDateRaw="$(resolvePaddedEnforcementDateForCandidate "${ddmDeclarationLogTimestamp}" "${ddmEnforcedInstallDate}|${ddmVersionString}|${ddmBuildVersionString}")"

if [[ -n "${paddedDateRaw}" ]]; then
    formattedDate="$(
        /bin/date -jf "%a %b %d %H:%M:%S %Y" "${paddedDateRaw}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
        || echo ""
    )"
fi

if [[ -z "${formattedDate}" ]]; then
    formattedDate="$(
        /bin/date -jf "%Y-%m-%dT%H:%M:%S" "${ddmEnforcedInstallDate%Z}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null \
        || echo "${ddmEnforcedInstallDate}"
    )"
fi

echo "<result>${formattedDate}</result>"
