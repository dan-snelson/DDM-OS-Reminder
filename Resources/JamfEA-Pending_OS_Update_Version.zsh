#!/bin/zsh --no-rcs
# EA: DDM Pending OS Update Version
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



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Utilities
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function emitNoneResult() {
    echo "<result>None</result>"
    exit 0
}

function resolveDDMEnforcementFromInstallLog() {
    if [[ ! -r "${installLogPath}" ]]; then
        return 1
    fi

    /usr/bin/tail -n "${ddmResolverLookbackLines}" "${installLogPath}" 2>/dev/null | /usr/bin/awk '
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

        function extractRequestedVersion(line,    pos, rest) {
            pos = index(line, "requestedPMV=")
            if (!pos) {
                return ""
            }

            rest = substr(line, pos + 13)
            if (match(rest, /^[0-9]+\.[0-9]+(\.[0-9]+)?/)) {
                return substr(rest, RSTART, RLENGTH)
            }

            return ""
        }

        {
            if (index($0, "requestedPMV=")) {
                activeRequestedVersion = extractRequestedVersion($0)
                next
            }

            if (activeRequestedVersion != "" && (index($0, "MADownloadNoMatchFound") || index($0, "pallasNoPMVMatchFound=true") || index($0, "No available updates found. Please try again later."))) {
                noMatchVersion[activeRequestedVersion] = 1
            }

            sourceType = ""
            sourcePriority = 0

            if (index($0, "declarationFromKeys]: Falling back to default applicable declaration")) {
                sourceType = "defaultApplicableDeclaration"
                sourcePriority = 3
            } else if (index($0, "Found DDM enforced install (")) {
                sourceType = "foundDdmEnforcedInstall"
                sourcePriority = 2
            } else if (index($0, "EnforcedInstallDate:")) {
                sourceType = "genericEnforcedInstallDate"
                sourcePriority = 1
            } else {
                next
            }

            logTimestamp = substr($0, 1, 22)
            if (logTimestamp !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}$/) {
                next
            }

            enforcedInstallDate = extractField($0, "EnforcedInstallDate")
            versionString = extractField($0, "VersionString")
            buildVersionString = extractField($0, "BuildVersionString")

            if (enforcedInstallDate == "" || versionString == "" || buildVersionString == "") {
                next
            }

            candidateKey = sourceType SUBSEP enforcedInstallDate SUBSEP versionString SUBSEP buildVersionString
            if (!(candidateKey in candidateTimestamp) || logTimestamp > candidateTimestamp[candidateKey]) {
                candidateTimestamp[candidateKey] = logTimestamp
                candidateSourceType[candidateKey] = sourceType
                candidateEnforcedInstallDate[candidateKey] = enforcedInstallDate
                candidateVersionString[candidateKey] = versionString
                candidateBuildVersionString[candidateKey] = buildVersionString
                candidatePriority[candidateKey] = sourcePriority
            }
        }

        END {
            highestPriority = 0
            for (candidateKey in candidateTimestamp) {
                if (candidatePriority[candidateKey] > highestPriority) {
                    highestPriority = candidatePriority[candidateKey]
                }
            }

            if (highestPriority == 0) {
                exit 20
            }

            filteredCount = 0
            for (candidateKey in candidateTimestamp) {
                if (candidatePriority[candidateKey] == highestPriority) {
                    filteredCount++
                    filteredCandidate[filteredCount] = candidateKey
                }
            }

            if (filteredCount != 1) {
                exit 21
            }

            candidateKey = filteredCandidate[1]
            versionString = candidateVersionString[candidateKey]

            if (versionString !~ /^[0-9]{1,3}\.[0-9]{1,3}(\.[0-9]{1,3})?$/) {
                exit 22
            }

            if (versionString in noMatchVersion) {
                exit 23
            }

            printf "%s\t%s\t%s\t%s\t%s\n", \
                candidateSourceType[candidateKey], \
                candidateTimestamp[candidateKey], \
                candidateEnforcedInstallDate[candidateKey], \
                candidateVersionString[candidateKey], \
                candidateBuildVersionString[candidateKey]
        }
    '
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Extension Attribute Result
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

resolvedCandidate="$(resolveDDMEnforcementFromInstallLog)"
resolverExitCode=$?

if (( resolverExitCode != 0 )) || [[ -z "${resolvedCandidate}" ]]; then
    emitNoneResult
fi

IFS=$'\t' read -r ddmResolverSource ddmDeclarationLogTimestamp ddmEnforcedInstallDate ddmVersionString ddmBuildVersionString <<< "${resolvedCandidate}"

if [[ -n "${currentBuild}" && -n "${ddmBuildVersionString}" && "${ddmBuildVersionString}" != "(null)" && "${currentBuild}" == "${ddmBuildVersionString}" ]]; then
    emitNoneResult
fi

echo "<result>${ddmVersionString}</result>"
