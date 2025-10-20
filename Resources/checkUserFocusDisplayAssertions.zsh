#!/bin/zsh --no-rcs 
# shellcheck shell=bash

####################################################################################################
#
# Check User Focus and Display Assertions
# http://snelson.us/ddm-os-reminder
#
# Works as expected via:
# - Terminal
# - Jamf Pro Policy
# 
# Fails via:
# - LaunchDaemon
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

scriptName="checkUserFocusDisplayAssertions"
scriptVersion="0.0.1"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Logged-in User Variables
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

loggedInUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ { print $3 }' )



###################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Check User Focus and Display Assertions (thanks, @techtrekkie!)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function checkUserFocusDisplayAssertions() {

    echo "Checking User's Focus Status …"
    focusResponse=$( plutil -extract data.0.storeAssertionRecords.0.assertionDetails.assertionDetailsModeIdentifier raw -o - "/Users/${loggedInUser}/Library/DoNotDisturb/DB/Assertions.json" | grep -ic 'com.apple.' )
    echo "focusResponse: ${focusResponse}"
    if [[ "${focusResponse}" -gt 0 ]]; then
        userFocusActive="TRUE"
    else
        userFocusActive="FALSE"
    fi
    echo "${loggedInUser}'s Focus Status is ${userFocusActive}."

    printf "\n---\n\n"

    echo "Checking User's Display Sleep Assertions …"
    local previousIFS
    previousIFS="${IFS}"; IFS=$'\n'
    local displayAssertionsArray
    displayAssertionsArray=( $(pmset -g assertions | awk '/NoDisplaySleepAssertion | PreventUserIdleDisplaySleep/ && match($0,/\(.+\)/) && ! /coreaudiod/ {gsub(/^\ +/,"",$0); print};') )
    # echo "displayAssertionsArray:\n${displayAssertionsArray[*]}"
    if [[ -n "${displayAssertionsArray[*]}" ]]; then
        userDisplayAssertions="TRUE"
        for displayAssertion in "${displayAssertionsArray[@]}"; do
            echo "Found the following Display Sleep Assertion(s): $(echo "${displayAssertion}" | awk -F ':' '{print $1;}')"
        done
    else
        userDisplayAssertions="FALSE"
    fi
    echo "${loggedInUser}'s Display Sleep Assertion is ${userDisplayAssertions}."
    IFS="${previousIFS}"

    printf "\n\n\n"

}



####################################################################################################
#
# Program
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Name and Version
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

printf "\n\n########\n"
printf "#\n# ${scriptName} (${scriptVersion})\n#\n"
printf "########\n\n"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Confirm the currently logged-in user is "available" to be reminded
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

checkUserFocusDisplayAssertions