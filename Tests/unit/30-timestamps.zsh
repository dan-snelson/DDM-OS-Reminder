#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: epochFromISO8601Timestamp (reminderDialog.zsh) and the fallback date checks in
# launchDaemonManagement.zsh (#182, calendar range checks)
#
####################################################################################################

# Expected epochs are computed from UTC wall time, independent of the code under test
function utcEpoch() {
    date -u -j -f '%Y-%m-%dT%H:%M:%S' "${1}" '+%s'
}

function loadRdTimestampFunctions() {
    loadRuntimeFunctions || return 1
}

function rdEpoch() {
    epochFromISO8601Timestamp "${1}" 2>/dev/null
}

# LDM functions are loaded in a subshell so their isValidCivilDate cannot shadow RD's
function ldmEpoch() {
    (
        loadDeploymentFunctions >/dev/null 2>&1 || exit 2
        isValidFallbackEnforcementDate "${1}" || exit 1
        fallbackEnforcementEpoch "${1}"
    )
}

function assertTimestampEpoch() {
    local label="${1}"
    local timestamp="${2}"
    local expectedEpoch="${3}"

    assertEquals "RD epochFromISO8601Timestamp '${timestamp}' (${label}, TZ=${TZ})" "${expectedEpoch}" "$(rdEpoch "${timestamp}")"
    assertEquals "LDM fallbackEnforcementEpoch '${timestamp}' (${label}, TZ=${TZ})" "${expectedEpoch}" "$(ldmEpoch "${timestamp}")"
}

function assertTimestampRejected() {
    local timestamp="${1}"
    local rdOutput=""
    local rdStatus=0
    local ldmStatus=0

    rdOutput="$(epochFromISO8601Timestamp "${timestamp}" 2>/dev/null)"
    rdStatus=$?
    if (( rdStatus == 0 )) || [[ -n "${rdOutput}" ]]; then
        recordFailure "RD epochFromISO8601Timestamp accepted impossible '${timestamp}' (status ${rdStatus}, epoch '${rdOutput}')"
    fi

    ( loadDeploymentFunctions >/dev/null 2>&1 && isValidFallbackEnforcementDate "${timestamp}" )
    ldmStatus=$?
    if (( ldmStatus == 0 )); then
        recordFailure "LDM isValidFallbackEnforcementDate accepted impossible '${timestamp}'"
    fi
}

function testUtcAndOffsetForms() {
    loadRdTimestampFunctions || return 0

    assertTimestampEpoch "Z" "2026-11-02T22:00:00Z" "$(utcEpoch 2026-11-02T22:00:00)"
    assertTimestampEpoch "-05:00" "2026-11-02T17:00:00-05:00" "$(utcEpoch 2026-11-02T22:00:00)"
    assertTimestampEpoch "+05:30" "2026-11-03T03:30:00+05:30" "$(utcEpoch 2026-11-02T22:00:00)"
    assertTimestampEpoch "leap day" "2028-02-29T12:00:00Z" "$(utcEpoch 2028-02-29T12:00:00)"
}

function testZonelessIsDeviceLocal() {
    loadRdTimestampFunctions || return 0

    # 2026-12-01 is EST (-05:00) in New York and IST (+05:30) in Kolkata
    export TZ="America/New_York"
    assertTimestampEpoch "zone-less, New York" "2026-12-01T10:00:00" "$(utcEpoch 2026-12-01T15:00:00)"
    export TZ="Asia/Kolkata"
    assertTimestampEpoch "zone-less, Kolkata" "2026-12-01T10:00:00" "$(utcEpoch 2026-12-01T04:30:00)"
    export TZ="America/New_York"
}

function testImpossibleTimestampsRejected() {
    local timestamp=""

    loadRdTimestampFunctions || return 0

    for TZ in "America/New_York" "Asia/Kolkata"; do
        export TZ
        for timestamp in \
            "2026-02-30T10:00:00" \
            "2026-02-30T10:00:00Z" \
            "2027-02-29T10:00:00" \
            "2026-04-31T10:00:00-04:00" \
            "2026-11-02T24:00:00" \
            "2026-11-02T24:00:00Z" \
            "2026-11-02T10:60:00" \
            "2026-11-02T10:00:00+24:00" \
            "2026-13-01T10:00:00"; do
            assertTimestampRejected "${timestamp}"
        done
    done
    export TZ="America/New_York"
}

function testSpringForwardGap() {
    loadRdTimestampFunctions || return 0

    # 2026-03-08 02:30 does not exist in New York; it moves forward one hour to 03:30 EDT (07:30Z)
    export TZ="America/New_York"
    assertTimestampEpoch "spring-forward gap" "2026-03-08T02:30:00" "$(utcEpoch 2026-03-08T07:30:00)"
}

function testRdAndLdmAgree() {
    local timestamp=""
    local rdResult=""
    local ldmResult=""

    loadRdTimestampFunctions || return 0

    for TZ in "America/New_York" "Asia/Kolkata"; do
        export TZ
        for timestamp in \
            "2026-11-02T22:00:00Z" \
            "2026-11-02T17:00:00-05:00" \
            "2026-11-03T03:30:00+05:30" \
            "2026-12-01T10:00:00" \
            "2026-07-01T09:15:00" \
            "2026-03-08T02:30:00" \
            "2026-02-30T10:00:00" \
            "2026-11-02T24:00:00" \
            "2026-11-02T10:00:00+24:00"; do
            rdResult="$(rdEpoch "${timestamp}")"
            ldmResult="$(ldmEpoch "${timestamp}")"
            assertEquals "RD and LDM agree on '${timestamp}' (TZ=${TZ})" "${rdResult:-rejected}" "${ldmResult:-rejected}"
        done
    done
    export TZ="America/New_York"
}

registerTest "Z and ±HH:MM offsets (RD and LDM)" testUtcAndOffsetForms
registerTest "zone-less timestamps are device-local in New York and Kolkata" testZonelessIsDeviceLocal
registerTest "2026-02-30, T24:00:00, +24:00 and other impossible values are rejected" testImpossibleTimestampsRejected
registerTest "local time in a spring-forward gap moves +1h" testSpringForwardGap
registerTest "RD and LDM give the same result for every case" testRdAndLdmAgree
