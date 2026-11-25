#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Unit: preference reads and the reload when a plist changes mid-load (#177)
#
####################################################################################################

function writePreferencePlist() {
    local plistPath="${1}"
    local keyValue=""
    shift

    mkdir -p "${plistPath:h}"
    rm -f "${plistPath}"
    /usr/bin/plutil -create xml1 "${plistPath}"
    for keyValue in "$@"; do
        /usr/bin/plutil -insert "${keyValue%%=*}" -string "${keyValue#*=}" "${plistPath}"
    done
}

# Replace preferencePlistFingerprint so the managed plist "changes" once during the load.
# The counter lives in a file because callers use command substitution (subshells).
# mode "rewrite": second managed call removes Title from the managed plist (a stale value must not survive)
# mode "vanish":  first managed call deletes the managed plist
function stubPreferenceFingerprintChangeOnce() {
    stubFingerprintMode="${1}"
    stubFingerprintCounter="${testDir}/fingerprint.counter"
    print 0 > "${stubFingerprintCounter}"

    function preferencePlistFingerprint() {
        local plistPath="${1}"
        local callCount=0

        if [[ "${plistPath}" != "${managedPreferencesPlist}.plist" ]]; then
            [[ -f "${plistPath}" ]] || return 0
            stat -f '%i:%m:%z' "${plistPath}" 2>/dev/null
            return 0
        fi

        callCount=$(( $(< "${stubFingerprintCounter}") + 1 ))
        print "${callCount}" > "${stubFingerprintCounter}"

        case "${stubFingerprintMode}:${callCount}" in
            vanish:1 )
                rm -f "${plistPath}"
                print "managed-before"
                return 0
                ;;
            rewrite:1 )
                print "managed-before"
                return 0
                ;;
            rewrite:2 )
                /usr/bin/plutil -remove Title "${plistPath}" >/dev/null 2>&1
                ;;
        esac

        [[ -f "${plistPath}" ]] || return 0
        print "managed-after"
    }
}

function testReadPreferencePlistValueStatuses() {
    local readStatus=0
    local plistPath=""

    loadRuntimeFunctions || return 0
    plistPath="${localPreferencesPlist}.plist"
    writePreferencePlist "${plistPath}" "Title=Local Title"

    readPreferencePlistValue "${plistPath}" "Title"
    readStatus=$?
    assertExit "present key returns 0" "0" "${readStatus}"
    assertEquals "present key value" "Local Title" "${preferencePlistReadValue}"

    readPreferencePlistValue "${plistPath}" "Message"
    readStatus=$?
    assertExit "absent key returns 1" "1" "${readStatus}"
    assertEquals "absent key value is empty" "" "${preferencePlistReadValue}"
    assertEquals "absent key does not mark the read disturbed" "false" "${preferencePlistReadDisturbed}"

    readPreferencePlistValue "${testDir}/missing.plist" "Title"
    readStatus=$?
    assertExit "missing plist returns 2" "2" "${readStatus}"
    assertEquals "missing plist value is empty (never PlistBuddy's 'File Doesn't Exist' text)" "" "${preferencePlistReadValue}"
    assertEquals "missing plist marks the read disturbed" "true" "${preferencePlistReadDisturbed}"
    assertFileAbsent "PlistBuddy did not create the missing plist" "${testDir}/missing.plist"
}

function testPreferencePrecedence() {
    loadRuntimeFunctions || return 0
    writePreferencePlist "${managedPreferencesPlist}.plist" "Title=Managed Title" "QuietPeriodMinutes=5"
    writePreferencePlist "${localPreferencesPlist}.plist" "Title=Local Title" "SupportTeamName=Local Support" "QuietPeriodMinutes=9"

    loadPreferenceOverrides > /dev/null

    assertEquals "managed wins over local (Title)" "Managed Title" "${title}"
    assertEquals "managed numeric wins over local (QuietPeriodMinutes)" "5" "${quietPeriodMinutes}"
    assertEquals "local wins over default (SupportTeamName)" "Local Support" "${supportTeamName}"
    assertEquals "default when neither sets Button1Text" "Open Software Update" "${button1text}"
    assertEquals "preferenceExplicitlySet[\"title\"] (quoted key)" "true" "${preferenceExplicitlySet["title"]}"
    assertEquals "preferenceExplicitlySet[\"button1text\"] unset" "" "${preferenceExplicitlySet["button1text"]}"
    assertNotContains "no reload warning without a change" "Preference plist changed or became unreadable during load" "${scriptLog}"
    assertContains "Preferences loaded" "Preferences loaded" "${scriptLog}"
}

function testPreferenceReloadAfterChange() {
    loadRuntimeFunctions || return 0
    writePreferencePlist "${managedPreferencesPlist}.plist" "Title=Managed Title" "SupportTeamName=Managed Support"
    writePreferencePlist "${localPreferencesPlist}.plist" "Title=Local Title" "SupportTeamName=Local Support" "Button2Text=Local Later"
    stubPreferenceFingerprintChangeOnce rewrite

    loadPreferenceOverrides > /dev/null

    assertContains "reload WARNING" "[WARNING]         Preference plist changed or became unreadable during load; waiting up to 10 seconds and reloading once." "${scriptLog}"
    assertEquals "managed still wins over local after reload (SupportTeamName)" "Managed Support" "${supportTeamName}"
    assertEquals "no stale managed Title after reload; local wins" "Local Title" "${title}"
    assertEquals "local wins over default after reload (Button2Text)" "Local Later" "${button2text}"
    assertEquals "default after reload (Button1Text)" "Open Software Update" "${button1text}"
    assertEquals "preferenceExplicitlySet[\"supportTeamName\"] after reload" "true" "${preferenceExplicitlySet["supportTeamName"]}"
    assertNotContains "no second WARNING when the reload succeeds" "missing after reload" "${scriptLog}"
}

function testPreferenceReloadManagedMissing() {
    loadRuntimeFunctions || return 0
    writePreferencePlist "${managedPreferencesPlist}.plist" "Title=Managed Title"
    writePreferencePlist "${localPreferencesPlist}.plist" "SupportTeamName=Local Support"
    stubPreferenceFingerprintChangeOnce vanish

    # The vanished managed plist never stabilizes, so this waits the full 10 seconds
    loadPreferenceOverrides > /dev/null

    assertContains "first WARNING" "Preference plist changed or became unreadable during load" "${scriptLog}"
    assertContains "second WARNING (managed missing after reload)" "[WARNING]         Managed preferences '${managedPreferencesPlist}.plist' missing after reload; using local preferences and script-defined defaults." "${scriptLog}"
    assertEquals "default Title after the managed plist vanished" "macOS {titleMessageUpdateOrUpgrade} Required" "${title}"
    assertEquals "local value still applies" "Local Support" "${supportTeamName}"
    assertEquals "preferenceExplicitlySet[\"title\"] cleared" "" "${preferenceExplicitlySet["title"]}"
}

registerTest "readPreferencePlistValue returns 0/1/2 and never stores PlistBuddy error text" testReadPreferencePlistValueStatuses
registerTest "managed wins over local, local wins over defaults" testPreferencePrecedence
registerTest "plist changed mid-load: WARNING, reload, no stale values" testPreferenceReloadAfterChange
registerTest "managed plist missing after reload: second WARNING and default fallback (waits 10 s)" testPreferenceReloadManagedMissing
