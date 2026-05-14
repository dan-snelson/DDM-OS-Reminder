#!/bin/zsh --no-rcs
#
# localizationFilter.zsh — Shared localization-surface filtering helpers
#
# This helper is sourced by artifact-generation scripts to normalize requested
# language codes, decide which `*Localized_<code>` keys should survive, and
# filter generated `.plist` / `.mobileconfig` files without changing the
# surrounding XML structure.

scriptVersion="3.3.0b4"

# Shared localization-filter state used by assemble/createPlist generation paths.
typeset -ga localizationFilterSelectedCodes=()
typeset -ga localizationFilterSelectedCodeComparisons=()
typeset -g localizationFilterMode="full"
typeset -g localizationFilterLanguagesCSV=""

function localizationCodeComparisonValue() {
    local rawValue="${1//-/_}"

    echo "${rawValue:l}"
}

function normalizeLocalizationCode() {
    local rawValue="${1//-/_}"
    local normalizedValue=""
    local part=""
    local -a parts

    rawValue="${rawValue//[[:space:]]/}"
    [[ -z "${rawValue}" ]] && return 1

    parts=(${(s:_:)rawValue})
    (( ${#parts[@]} > 0 )) || return 1

    # Normalize language to lowercase and region-style suffixes (such as CA) to uppercase
    # so one comparison path can handle `fr-ca`, `fr_CA`, and `fr_ca`.
    for (( i=1; i<=${#parts[@]}; i++ )); do
        part="${parts[i]}"

        if (( i == 1 )); then
            [[ "${part}" =~ ^[A-Za-z]{2,3}$ ]] || return 1
            normalizedValue="${part:l}"
        else
            [[ "${part}" =~ ^[A-Za-z0-9]{2,8}$ ]] || return 1

            if [[ "${part}" =~ ^[A-Za-z]{2}$ ]]; then
                normalizedValue+="_${part:u}"
            else
                normalizedValue+="_${part:l}"
            fi
        fi
    done

    echo "${normalizedValue}"
}

function isLocalizedPlistKey() {
    local plistKey="${1}"

    [[ "${plistKey}" == *Localized_* ]]
}

function localizedCodeForPlistKey() {
    local plistKey="${1}"

    [[ "${plistKey}" == *Localized_* ]] || return 1
    echo "${plistKey##*Localized_}"
}

function configureLocalizationFilter() {
    local requestedMode="${1:-full}"
    local requestedLanguages="${2:-}"
    local normalizedCode=""
    local comparisonCode=""
    local rawCode=""
    local selectedCodeComparison=""
    local -a parsedCodes
    local -A seenCodeComparisons

    localizationFilterSelectedCodes=()
    localizationFilterSelectedCodeComparisons=()
    localizationFilterLanguagesCSV=""
    localizationFilterMode="${requestedMode}"

    # `full` and `minimal` ignore explicit language lists. Only `subset` requires one.
    case "${requestedMode}" in
        full)
            [[ -z "${requestedLanguages}" ]] || return 1
            return 0
            ;;
        minimal)
            [[ -z "${requestedLanguages}" ]] || return 1
            return 0
            ;;
        subset)
            [[ -n "${requestedLanguages}" ]] || return 1
            ;;
        *)
            return 1
            ;;
    esac

    parsedCodes=(${(s:,:)requestedLanguages})

    # Keep insertion order for summaries, but collapse duplicates for matching.
    for rawCode in "${parsedCodes[@]}"; do
        normalizedCode="$(normalizeLocalizationCode "${rawCode}")" || return 1
        comparisonCode="$(localizationCodeComparisonValue "${normalizedCode}")"

        if [[ -z "${seenCodeComparisons[${comparisonCode}]:-}" ]]; then
            localizationFilterSelectedCodes+=("${normalizedCode}")
            localizationFilterSelectedCodeComparisons+=("${comparisonCode}")
            seenCodeComparisons[${comparisonCode}]=1
        fi
    done

    (( ${#localizationFilterSelectedCodes[@]} > 0 )) || return 1
    localizationFilterLanguagesCSV="${(j:,:)localizationFilterSelectedCodes}"
}

function shouldKeepLocalizedPlistKey() {
    local plistKey="${1}"
    local localizedCode=""
    local localizedCodeComparison=""
    local selectedCodeComparison=""
    local selectedBaseCode=""

    isLocalizedPlistKey "${plistKey}" || return 0

    case "${localizationFilterMode}" in
        full)
            return 0
            ;;
    esac

    localizedCode="$(localizedCodeForPlistKey "${plistKey}")" || return 0
    localizedCodeComparison="$(localizationCodeComparisonValue "${localizedCode}")"

    # Minimal output keeps only exact `_Localized_en` keys, not English region variants.
    if [[ "${localizationFilterMode}" == "minimal" && "${localizedCodeComparison}" == "en" ]]; then
        return 0
    fi

    if [[ "${localizationFilterMode}" == "minimal" ]]; then
        return 1
    fi

    # Subset output always keeps exact `_Localized_en` keys as baseline English copy.
    if [[ "${localizedCodeComparison}" == "en" ]]; then
        return 0
    fi

    for selectedCodeComparison in "${localizationFilterSelectedCodeComparisons[@]}"; do
        if [[ "${selectedCodeComparison}" == *_* ]]; then
            # Exact locale selection (for example `fr_CA`) also keeps its base-language fallback (`fr`).
            selectedBaseCode="${selectedCodeComparison%%_*}"
            if [[ "${localizedCodeComparison}" == "${selectedCodeComparison}" || "${localizedCodeComparison}" == "${selectedBaseCode}" ]]; then
                return 0
            fi
        else
            # Base-language selection (for example `fr`) keeps that family plus region variants.
            if [[ "${localizedCodeComparison}" == "${selectedCodeComparison}" || "${localizedCodeComparison}" == ${selectedCodeComparison}_* ]]; then
                return 0
            fi
        fi
    done

    return 1
}

function localizationFilterSummary() {
    local code=""
    local -a configuredCodes
    local -a summaryCodes
    local -A seenSummaryCodes

    case "${localizationFilterMode}" in
        full)
            echo "full localization surface"
            ;;
        minimal)
            echo "minimal localization surface (base keys + English localized keys)"
            ;;
        subset)
            configuredCodes=(${(s:,:)localizationFilterLanguagesCSV})

            for code in "en" "${configuredCodes[@]}"; do
                [[ -z "${code}" ]] && continue
                if [[ -z "${seenSummaryCodes[${code}]:-}" ]]; then
                    summaryCodes+=("${code}")
                    seenSummaryCodes[${code}]=1
                fi
            done

            echo "language subset: ${(j:,:)summaryCodes}"
            ;;
        *)
            echo "unknown localization filter mode"
            ;;
    esac
}

function filterLocalizedKeysInXmlFile() {
    local targetFile="${1}"
    local targetDir=""
    local tmpFile=""
    local line=""
    local currentKey=""
    local originalMode=""
    local skipNextValue="false"
    local removedKeyCount=0

    [[ -f "${targetFile}" ]] || return 1

    if [[ "${localizationFilterMode}" == "full" ]]; then
        echo "0"
        return 0
    fi

    # Stream-edit the XML so generated comments, ordering, and non-localized keys stay intact.
    targetDir="${targetFile:h}"
    originalMode="$(stat -f '%Lp' "${targetFile}")" || return 1
    tmpFile="$(mktemp "${targetDir}/localizationFilter.XXXXXX")" || return 1

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${skipNextValue}" == "true" ]]; then
            # After removing a localized <key>, also drop its following value node while tolerating
            # comments/blank lines that may sit between them.
            if [[ "${line}" =~ '^[[:space:]]*$' ]] || [[ "${line}" =~ '^[[:space:]]*<!--' ]]; then
                continue
            fi

            skipNextValue="false"
            continue
        fi

        if [[ "${line}" =~ '<key>([^<]+)</key>' ]]; then
            currentKey="${match[1]}"

            if isLocalizedPlistKey "${currentKey}" && ! shouldKeepLocalizedPlistKey "${currentKey}"; then
                skipNextValue="true"
                (( removedKeyCount++ ))
                continue
            fi
        fi

        printf "%s\n" "${line}" >> "${tmpFile}"
    done < "${targetFile}"

    chmod "${originalMode}" "${tmpFile}" || return 1
    mv "${tmpFile}" "${targetFile}"
    echo "${removedKeyCount}"
}
