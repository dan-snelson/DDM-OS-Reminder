#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Jamf-getDDMstatusFromCSV.zsh
#
# https://snelson.us/2026/01/ddm-status-from-csv-0-0-6/
#
# Inspired by:
#   - @ScottEKendall
#
#####################################################################################################
#
# Usage:
#
# zsh Jamf-getDDMstatusFromCSV.zsh --help
#
####################################################################################################
#
# HISTORY
#
# Version 1.0.0, 06-Feb-2026, Dan K. Snelson (@dan-snelson)
# - First "official" release
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

[[ -o interactive ]] && setopt monitor

# Script Version
scriptVersion="1.0.0"

# Elapsed Time
SECONDS="0"

# Script Name (for help display)
scriptName=$(basename "${0}")

# Client-side Log (will be updated after outputDir is set)
scriptLog=""

# CSV Output (will be updated after outputDir is set)
csvOutput=""

# CSV format tracking
csvFormat="single"
csvDelimiter=""
csvDelimiterLabel="none"

# Divider Line
dividerLine="\n--------------------------------------------------------------------------------------------------------|\n"

# Any Colour You Like
red=$'\e[1;31m'
green=$'\e[1;32m'
yellow=$'\e[1;33m'
blue=$'\e[1;34m'
cyan=$'\e[1;36m'
resetColor=$'\e[0m'

# Token management variables
tokenObtainedTime=0
tokenRefreshInterval=240  # Refresh every 4 minutes (before 5-minute OAuth expiration)

# Parallel processing variables (inspired by @ScottEKendall)
parallelProcessing="false"          # Enable parallel processing for faster execution
maxParallelJobs=10                  # Number of concurrent background jobs (default: 10)
export parallelProcessing


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Initialize variables
apiUrl=""
apiUser=""
apiPassword=""
filename=""
outputDir="$HOME/Desktop"           # Default output directory
noOpen="false"                      # Skip opening log/CSV files

# Debug Mode [ true | false ]
debugMode="false"                    # Set to "true" to enable debug logging

# Summary Statistics Counters
ddmEnabledCount=0
ddmDisabledCount=0
failedBlueprintsCount=0
pendingUpdatesCount=0
errorCount=0
notFoundCount=0

# Parallel processing job tracking
declare -a jobPids=()

# Script Display Name (for help and headers)
scriptDisplayName="Jamf Pro: Get DDM Status from CSV"

# Organization Script Name (for logging)
organizationScriptName="DDM-CSV"



####################################################################################################
#
# Functions
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Cleanup on Exit
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function cleanup() {
    if [[ "${debugMode}" == "true" ]]; then
        debug "Cleanup function called"
    fi

    # Clean up temporary files
    if [[ -n "${processedFilename}" ]] && [[ "${processedFilename}" != "${filename}" ]] && [[ -f "${processedFilename}" ]]; then
        rm -f "${processedFilename}" 2>/dev/null
        if [[ "${debugMode}" == "true" ]]; then
            debug "Removed temporary file: ${processedFilename}"
        fi
    fi

    # Remove any other temp files matching pattern
    if [[ -n "${filename}" ]] && [[ -f "${filename}" ]]; then
        rm -f "${filename}.jssids.tmp" 2>/dev/null
    fi
    
    # Clean up parallel processing temp directory if it exists
    if [[ -n "${tempDir}" ]] && [[ -d "${tempDir}" ]]; then
        rm -rf "${tempDir}" 2>/dev/null
        if [[ "${debugMode}" == "true" ]]; then
            debug "Removed temporary directory: ${tempDir}"
        fi
    fi
    
    # Clean up token lock file if it exists
    if [[ -n "${tokenLockFile}" ]] && [[ -d "${tokenLockFile}" ]]; then
        rmdir "${tokenLockFile}" 2>/dev/null
    fi
}

function interrupt_handler() {
    printf "\n\n${yellow}âš ${resetColor} Script interrupted by user. Cleaning up...${resetColor}\n\n"
    
    # Kill all background jobs spawned by this script
    if [[ "${parallelProcessing}" == "true" ]]; then
        local backgroundJobPids=$(jobs -p 2>/dev/null)
        if [[ -n "${backgroundJobPids}" ]]; then
            if [[ "${debugMode}" == "true" ]]; then
                debug "Killing background jobs: ${backgroundJobPids}"
            fi
            echo "${backgroundJobPids}" | xargs kill 2>/dev/null
            # Give jobs a moment to terminate gracefully
            sleep 0.5
            # Force kill any remaining jobs
            echo "${backgroundJobPids}" | xargs kill -9 2>/dev/null
        fi
        
        if [[ ${#jobPids[@]} -gt 0 ]]; then
            if [[ "${debugMode}" == "true" ]]; then
                debug "Killing tracked background jobs: ${jobPids[*]}"
            fi
            for pid in "${jobPids[@]}"; do
                kill "${pid}" 2>/dev/null
            done
            sleep 0.5
            for pid in "${jobPids[@]}"; do
                kill -9 "${pid}" 2>/dev/null
            done
        fi
    fi
    
    cleanup
    invalidateBearerToken 2>/dev/null
    
    updateScriptLog "[INTERRUPTED]     Script terminated by user"
    printf "\n${yellow}Cleanup complete. Exiting.${resetColor}\n\n"
    exit 130
}

# Set traps separately for clearer signal handling
trap cleanup EXIT
trap interrupt_handler INT TERM



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    if [[ -n "${scriptLog}" ]]; then
        echo "${organizationScriptName} ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" >> "${scriptLog}"
    fi
}

function preFlight()    { updateScriptLog "[PRE-FLIGHT]      ${1}"; }
function logComment()   { updateScriptLog "                  ${1}"; }
function notice()       { updateScriptLog "[NOTICE]          ${1}"; }
function info()         { updateScriptLog "[INFO]            ${1}"; }
function debug()        { updateScriptLog "[DEBUG]           ${1}"; }
function errorOut()     { updateScriptLog "[ERROR]           ${1}"; }
function error()        { updateScriptLog "[ERROR]           ${1}"; let errorCount++; }
function warning()      { updateScriptLog "[WARNING]         ${1}"; let errorCount++; }
function fatal()        { updateScriptLog "[FATAL ERROR]     ${1}"; exit 1; }
function quitOut()      { updateScriptLog "[QUIT]            ${1}"; }



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Exit with logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function die() {
    updateScriptLog "ERROR: ${1}"
    updateScriptLog "\n\nExiting script.\n\n"
    exit 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Display Help
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function displayHelp() {
    echo "
${scriptDisplayName} (${scriptVersion})
by Dan K. Snelson (@dan-snelson)
https://snelson.us/2026/01/ddm-status-from-csv-0-0-6/

    Usage:
        zsh ${scriptName} [OPTIONS] [apiURL] [apiUsername] [apiPassword] [csvFilename]
        zsh ${scriptName} --serial SERIALNUMBER [OPTIONS]

    Options:
        -s, --serial SN       Look up a single computer by Serial Number (Terminal output only)
        -l, --lane [LANE]     Select lane: dev, stage, or prod (prompts if omitted)
        -d, --debug           Enable debug mode with verbose logging
        --output-dir PATH     Specify output directory (default: ~/Desktop)
        --parallel            Enable parallel processing for faster execution (per-record details go to log)
        --max-jobs N          Set maximum parallel jobs (default: 10, requires --parallel)
        --no-open             Do not open the log and CSV output files
        -h, --help            Display this help information

    CSV Format Requirements:
        Single-column:    One Computer ID per line (no header required)
                          123
                          456
                          789
        
        Multi-column:     Must include 'JSS Computer ID', 'Jamf Pro Computer ID', or 'Computer ID' header
                          Computer Name,JSS Computer ID,Serial Number
                          Mac1,123,C02ABC
                          Mac2,456,C02DEF
        
    Notes:
        • For CSVs with quoted newlines, ruby (if available) is used for reliable parsing.
        • Without ruby, multiline CSV fields may be misread.

    Examples:
        # CSV batch processing with lane
        zsh ${scriptName} --lane stage computers.csv
        
        # Full credentials (flags are position-independent)
        zsh ${scriptName} https://yourserver.jamfcloud.com apiUser apiPassword computers.csv
        zsh ${scriptName} --debug https://yourserver.jamfcloud.com apiUser apiPassword computers.csv
        zsh ${scriptName} https://yourserver.jamfcloud.com apiUser apiPassword --debug computers.csv
        
        # Single serial number lookup
        zsh ${scriptName} --serial C02ABC123DEF --lane prod
        
        # Interactive mode (prompts for missing parameters)
        zsh ${scriptName}

    "
    exit 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Lane Selection
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function laneSelection() {

    local lane="${1:-}"

    # If lane was provided as parameter, use it directly
    if [[ -n "${lane}" ]]; then
        info "Lane specified via command line: ${lane}"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Direct lane selection: ${lane}"
        fi
    else
        # Prompt user for lane selection
    echo "Please select a lane:

[d] Development
[s] Stage  
[p] Production
[x] Exit"

    SECONDS="0"

    printf "\n> "
    read -k 1 lane
    printf "\n"
    info "Please select a lane: ${lane}"

    info "Elapsed Time: ${SECONDS} seconds"
    logComment ""
    fi

    case "${lane}" in
        
    d|D|dev|development )

        info "Development Lane"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Selected: Development Lane"
        fi
        apiUrl=""
        apiUser=""
        apiPassword=""
        ;;

    s|S|stage )

        info "Stage Lane"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Selected: Stage Lane"
        fi
        apiUrl=""
        apiUser=""
        apiPassword=""
        ;;

    p|P|prod|production )

        info "Production Lane"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Selected: Production Lane"
        fi
        apiUrl=""
        apiUser=""
        apiPassword=""
        ;;

    x|X)

        quitOut "Exiting. Goodbye!"
        printf "\n\nExiting. Goodbye!\n\n"
        exit 0
        ;;

    *)

        error "Did not recognize response: ${lane}; exiting."
        printf "\n${red}ERROR:${resetColor} Did not recognize response: ${lane}; exiting."
        exit 1
        ;;

    esac

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Prompt user for API URL
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function promptAPIurl() {

    SECONDS="0"

    if [[ -z "${apiUrl}" ]]; then

        notice "API URL is blank; attempt to read from JAMF plist ..."

        if [[ -e "/Library/Preferences/com.jamfsoftware.jamf.plist" ]]; then
            
            apiUrl=$( /usr/bin/defaults read "/Library/Preferences/com.jamfsoftware.jamf.plist" jss_url 2>/dev/null | sed 's|/$||' )
            local defaultsExitCode=$?
            
            if [[ ${defaultsExitCode} -ne 0 ]] || [[ -z "${apiUrl}" ]] || [[ "${apiUrl}" != http* ]]; then
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Unable to read valid API URL from JAMF plist (exit: ${defaultsExitCode}, value: '${apiUrl}')"
                fi
                info "Unable to read a valid API URL from JAMF plist; prompting user ..."
                apiUrl=""
            else
                printf "\nThe API URL has been read from the Jamf preferences: ${apiUrl}\n"
                printf "Press ENTER to use this URL, or type a different URL: "
                read userInput
                
                if [[ -n "${userInput}" ]]; then
                    apiUrl="${userInput}"
                    # Remove quotes if user added them
                    apiUrl="${apiUrl//\"/}"
                    apiUrl="${apiUrl//\'/}"
                    if [[ "${debugMode}" == "true" ]]; then
                        debug "Raw URL input: ${apiUrl}"
                    fi
                    apiUrl=$( echo "${apiUrl}" | sed 's|/$||' )
                    if [[ "${debugMode}" == "true" ]]; then
                        debug "URL after trailing slash removal: ${apiUrl}"
                    fi
                    info "User entered API URL: ${apiUrl}"
                else
                    info "Using URL from JAMF plist: ${apiUrl}"
                fi
                printf "${green}✓${resetColor} API URL set to: ${apiUrl}\n"
            fi

        fi

        if [[ -z "${apiUrl}" ]]; then

            info "No API URL is specified in the script; prompt user ..."
            
            while [[ -z "${apiUrl}" ]]; do
                printf "\nPlease enter the API URL (e.g., https://yourserver.jamfcloud.com): "
                read apiUrl
                if [[ -n "${apiUrl}" ]]; then
                    apiUrl=$( echo "${apiUrl}" | sed 's|/$||' )
                    info "User entered API URL: ${apiUrl}"
                    printf "${green}✓${resetColor} API URL set to: ${apiUrl}\n"
                fi
            done

        fi

    fi

    apiUrl=$( echo "${apiUrl}" | sed 's|/$||' )

    info "Using the API URL of: ${apiUrl}"
    printf "\n${green}✓${resetColor} Using the API URL of: ${apiUrl}\n"

    info "Elapsed Time: ${SECONDS} seconds"
    info ""

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Prompt user for API Username
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function promptAPIusername() {

    SECONDS="0"

    if [[ -z "${apiUser}" ]]; then
        notice "No API Username (or Client ID) has been supplied."
        
        while [[ -z "${apiUser}" ]]; do
            printf "\nPlease enter the API Username (or Client ID): "
            read apiUser
            if [[ -n "${apiUser}" ]]; then
                # Remove quotes if user added them
                apiUser="${apiUser//\"/}"
                apiUser="${apiUser//\'/}"
                info "User entered API Username (or Client ID): ${apiUser}"
                printf "${green}✓${resetColor} API Username (or Client ID) set\n"
            fi
        done

    fi

    local maskedUser=$(maskCredential "${apiUser}")
    if [[ "${debugMode}" == "true" ]]; then
        debug "Credential length: ${#apiUser} characters (OAuth detection threshold: 30)"
    fi
    info "Using the API Username (or Client ID) of: ${maskedUser}"
    printf "${green}✓${resetColor} Using the API Username (or Client ID) of: ${maskedUser}\n"

    info "Elapsed Time: ${SECONDS} seconds"
    info ""

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Prompt user for API Password
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function promptAPIpassword() {

    SECONDS="0"

    if [[ -z "${apiPassword}" ]]; then
        notice "No API Password (or Client Secret) has been supplied."
        
        while [[ -z "${apiPassword}" ]]; do
            printf "\nPlease enter the API Password (or Client Secret): "
            read -s apiPassword
            printf "\n"
            if [[ -n "${apiPassword}" ]]; then
                # Remove quotes if user added them
                apiPassword="${apiPassword//\"/}"
                apiPassword="${apiPassword//\'/}"
                info "User entered API Password (or Client Secret)"
                printf "${green}✓${resetColor} API Password (or Client Secret) set\n"
            fi
        done

    fi

    if [[ "${debugMode}" == "true" ]]; then
        local maskedPassword=$(maskCredential "${apiPassword}")
        debug "Displaying API Password (or Client Secret) ..."
        debug "Using the API Password (or Client Secret) of: ${maskedPassword}"
        printf "${green}DEBUG MODE ENABLED:${resetColor} Displaying API Password (or Client Secret) ...\n"
        printf "${green}✓${resetColor} Using the API Password (or Client Secret) of: ${maskedPassword}\n"
    else
        printf "${green}✓${resetColor} Using the supplied API password (or Client Secret)\n"
    fi

    info "Elapsed Time: ${SECONDS} seconds"
    info ""

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Prompt user for CSV Filename
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function promptCSVfilename() {

    SECONDS="0"

    if [[ -z "${filename}" ]]; then
        info "No CSV filename has been supplied."
        
        while [[ ! -f "${filename}" ]]; do
            printf "\nPlease enter the CSV filename (or drag-and-drop the file): "
            read filename
            
            if [[ -n "${filename}" ]]; then
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Raw filename input: ${filename}"
                fi
                # Remove quotes if user drag-and-dropped
                filename="${filename//\'/}"
                filename="${filename//\"/}"
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Filename after quote removal: ${filename}"
                fi
                
                # Verify file exists
                if [[ ! -f "${filename}" ]]; then
                    error "The specified file '${filename}' does not exist."
                    printf "${red}ERROR:${resetColor} The specified file '${filename}' does not exist. Please try again.\n"
                    filename=""  # Reset to loop again
                else
                    info "User entered CSV filename: ${filename}"
                fi
            fi
        done

    else
        # Verify file exists (for non-interactive mode)
        if [[ ! -f "${filename}" ]]; then
            error "The specified file '${filename}' does not exist."
            printf "\n${red}ERROR:${resetColor} The specified file '${filename}' does not exist.\n\n"
            exit 1
        fi
    fi

    info "Using CSV filename: ${filename}"
    printf "${green}✓${resetColor} Using CSV filename: ${filename}\n"

    info "Elapsed Time: ${SECONDS} seconds"
    info ""

}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Ensure required tools exist
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function preflightTools() {
    local requiredTools=("curl" "plutil" "sed" "awk" "printf" "open" "jq")
    for tool in "${requiredTools[@]}"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            die "Required tool '${tool}' not found in PATH."
        fi
    done
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Obtain Jamf Pro Bearer Token via Basic Authentication or OAuth
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getBearerToken() {
    local tokenJson
    
    # Detect authentication method based on credential length
    # OAuth client IDs are typically longer than 30 characters
    if [[ ${#apiUser} -gt 30 ]]; then
        info "Detected OAuth credentials; using OAuth authentication …"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Authentication method: OAuth (credential length: ${#apiUser})"
            debug "OAuth endpoint: ${apiUrl}/api/oauth/token"
        fi
        
        # OAuth token request
        tokenJson=$(curl -X POST --silent \
            --url "${apiUrl}/api/oauth/token" \
            --header 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode "client_id=${apiUser}" \
            --data-urlencode "client_secret=${apiPassword}" \
            --data-urlencode 'grant_type=client_credentials')
    else
        info "Using basic authentication …"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Authentication method: Basic Auth"
            debug "Auth endpoint: ${apiUrl}/api/v1/auth/token"
        fi
        
        # Basic authentication token request
        tokenJson=$(curl -X POST --silent -u "${apiUser}:${apiPassword}" "${apiUrl}/api/v1/auth/token")
    fi

    # Basic sanity check on JSON
    if [[ -z "${tokenJson}" ]]; then
        error "Jamf Pro auth returned an empty response; check URL and network."
        if [[ "${debugMode}" == "true" ]]; then
            debug "API URL used: ${apiUrl}"
            debug "Response was completely empty"
        fi
        die "ERROR: Jamf Pro auth returned an empty response; check URL and network."
    fi

    if [[ "${debugMode}" == "true" ]]; then
        debug "Token response: ${tokenJson}"
    fi
    
    # Check for error in response
    if [[ "${tokenJson}" == *"error"* ]]; then
        error "Token response contains an error"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Full error response: ${tokenJson}"
        fi
        printf "\n${red}ERROR:${resetColor} Authentication failed. Response contains error:\n${tokenJson}\n\n"
        die "Unable to authenticate with Jamf Pro. Check credentials and URL."
    fi

    # Extract token with plutil (handles both access_token and token fields)
    if command -v plutil >/dev/null 2>&1; then
        # Try OAuth token field first
        apiBearerToken=$(printf "%s" "${tokenJson}" | plutil -extract access_token raw - 2>/dev/null)
        # Fall back to basic auth token field
        if [[ -z "${apiBearerToken}" ]] || [[ "${apiBearerToken}" == "null" ]]; then
            apiBearerToken=$(printf "%s" "${tokenJson}" | plutil -extract token raw - 2>/dev/null)
        fi
    else
        # Fallback parsing for OAuth
        apiBearerToken=$(printf "%s" "${tokenJson}" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        # Fall back to basic auth
        if [[ -z "${apiBearerToken}" ]]; then
            apiBearerToken=$(printf "%s" "${tokenJson}" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
        fi
    fi

    if [[ -z "${apiBearerToken}" ]]; then
        error "Failed to extract bearer token from response"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Token extraction failed. Response was: ${tokenJson}"
        fi
        printf "\n${red}ERROR:${resetColor} Unable to extract bearer token from response.\n"
        printf "This could indicate:"
        printf "\n  • Invalid credentials"
        printf "\n  • Incorrect URL"
        printf "\n  • API permissions issue\n\n"
        die "Unable to obtain Bearer Token; double-check API credentials and URL."
    fi

    info "Obtained Bearer Token; proceeding …"

    # Record when the token was obtained
    tokenObtainedTime=$(date +%s)

    if [[ "${debugMode}" == "true" ]]; then
        local maskedToken=$(maskCredential "${apiBearerToken}")
        debug "apiBearerToken: ${maskedToken}"
        debug "Token obtained at: ${tokenObtainedTime}"
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Refresh Jamf Pro Bearer Token via keep-alive
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function refreshBearerToken() {
    info "Refreshing expired Bearer Token …"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Token refresh triggered; attempting keep-alive at: ${apiUrl}/api/v1/auth/keep-alive"
    fi

    local refreshJson
    refreshJson=$(curl --silent -X POST \
        -H "Authorization: Bearer ${apiBearerToken}" \
        "${apiUrl}/api/v1/auth/keep-alive")

    if [[ -z "${refreshJson}" ]] || [[ "${refreshJson}" == *"error"* ]]; then
        warning "keep-alive failed or returned error; attempting to get a new token."
        
        # Fall back to getting a completely new token
        getBearerToken
        
        if [[ -n "${apiBearerToken}" ]]; then
            info "Successfully obtained new Bearer Token after keep-alive failure."
            return 0
        else
            error "Failed to obtain new token after keep-alive failure."
        return 1
        fi
    fi

    if command -v plutil >/dev/null 2>&1; then
        apiBearerToken=$(printf "%s" "${refreshJson}" | plutil -extract token raw - 2>/dev/null)
    else
        apiBearerToken=$(printf "%s" "${refreshJson}" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    fi

    if [[ -z "${apiBearerToken}" ]]; then
        warning "Failed to parse refreshed token; attempting to get a new token."
        
        # Fall back to getting a completely new token
        getBearerToken
        
        if [[ -n "${apiBearerToken}" ]]; then
            info "Successfully obtained new Bearer Token after parse failure."
            return 0
        else
            error "Failed to obtain new token after parse failure."
        return 1
        fi
    fi

    info "Successfully refreshed Bearer Token via keep-alive."

    # Update token timestamp after successful refresh
    tokenObtainedTime=$(date +%s)

    if [[ "${debugMode}" == "true" ]]; then
        local maskedToken=$(maskCredential "${apiBearerToken}")
        debug "Refreshed apiBearerToken: ${maskedToken}"
        debug "Token refreshed at: ${tokenObtainedTime}"
    fi

    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Invalidate Bearer Token
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function checkAndRefreshToken() {
    local currentTime=$(date +%s)
    local tokenAge=$((currentTime - tokenObtainedTime))
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Token age: ${tokenAge} seconds (refresh interval: ${tokenRefreshInterval})"
    fi
    
    # Refresh token if it's older than the refresh interval
    if [[ ${tokenAge} -ge ${tokenRefreshInterval} ]]; then
        if [[ "${debugMode}" == "true" ]]; then
            debug "Token age (${tokenAge}s) exceeds refresh interval (${tokenRefreshInterval}s); refreshing ..."
        fi
        refreshBearerToken
        return $?
    fi
    
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Invalidate Bearer Token
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function invalidateBearerToken() {
    info "Invalidating Bearer Token …"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Calling invalidation endpoint: ${apiUrl}/api/v1/auth/invalidate-token"
    fi
    curl --silent -X POST \
        -H "Authorization: Bearer ${apiBearerToken}" \
        "${apiUrl}/api/v1/auth/invalidate-token" >/dev/null 2>&1
    apiBearerToken=""
    if [[ "${debugMode}" == "true" ]]; then
        debug "Bearer token cleared from memory"
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Sanitize data for CSV output
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function sanitizeForCsv() {
    local data="${1}"
    # Normalize for CSV safety (preserve content while avoiding malformed rows)
    data="${data//$'\r'/ }"
    data="${data//$'\n'/ }"
    data="${data//\"/\"\"}"
    printf "%s" "${data}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Mask credentials for display
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function maskCredential() {
    local credential="${1}"
    if [[ -z "${credential}" ]] || [[ ${#credential} -lt 7 ]]; then
        echo "***"
    else
        echo "${credential:0:3}$(printf '%*s' $((${#credential}-4)) '' | tr ' ' '*')${credential: -3}"
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Validate CSV format (single column or multi-column with JSS Computer ID)
# 
# IMPORTANT: CSV Format Requirements
# 
# This script accepts two CSV formats:
# 
# 1. Single-column CSV (no header required):
#    123
#    456
#    789
# 
# 2. Multi-column CSV (MUST include 'JSS Computer ID' or 'Jamf Pro Computer ID' header):
#    Computer Name,JSS Computer ID,Serial Number,OS Version
#    Mac1,123,C02ABC,14.5
#    Mac2,456,C02DEF,14.6
# 
# When exporting from Jamf Pro:
# - Include the "Jamf Pro Computer ID" column in your export
# - The column header must be either: JSS Computer ID or Jamf Pro Computer ID
# - Other columns are optional and will be ignored
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function validateCsvFormat() {
    local csvFile="${1}"
    
    # Read first line to check for headers
    local firstLine=$(head -n 1 "${csvFile}" | tr -d '\r')
    local firstLineLower="${firstLine:l}"
    local delimiter=""
    local delimiterLabel="none"
    local hasIdHeader="false"
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "CSV first line: ${firstLine}" >&2
    fi
    
    # Determine delimiter for multi-column CSVs
    if [[ "${firstLine}" == *","* ]]; then
        delimiter=","
        delimiterLabel="comma"
    elif [[ "${firstLine}" == *$'\t'* ]]; then
        delimiter=$'\t'
        delimiterLabel="tab"
    elif [[ "${firstLine}" == *";"* ]]; then
        delimiter=";"
        delimiterLabel="semicolon"
    fi
    
    if [[ "${firstLineLower}" == *"jss computer id"* ]] || [[ "${firstLineLower}" == *"jamf pro computer id"* ]] || [[ "${firstLineLower}" == *"computer id"* ]]; then
        hasIdHeader="true"
    fi
    
    # Multi-column CSV validation
    if [[ -n "${delimiter}" ]]; then
        csvFormat="multi"
        csvDelimiter="${delimiter}"
        csvDelimiterLabel="${delimiterLabel}"
        
        if [[ "${hasIdHeader}" == "true" ]]; then
            info "Detected multi-column CSV with computer ID header; will extract ID column" >&2
            return 0
        fi
        
        # Multi-column but no recognized computer ID header
        local columnCount=""
        local headers="${firstLine}"
        
        case "${delimiter}" in
            ",")
                columnCount=$(printf "%s" "${firstLine}" | awk -F',' '{print NF}')
                headers=$(printf "%s" "${firstLine}" | sed 's/,/, /g')
                ;;
            $'\t')
                columnCount=$(printf "%s" "${firstLine}" | awk -F'\t' '{print NF}')
                headers=$(printf "%s" "${firstLine}" | tr '\t' ',' | sed 's/,/, /g')
                ;;
            ";")
                columnCount=$(printf "%s" "${firstLine}" | awk -F';' '{print NF}')
                headers=$(printf "%s" "${firstLine}" | sed 's/;/; /g')
                ;;
        esac
        
        if [[ "${debugMode}" == "true" ]]; then
            debug "Detected ${columnCount} columns without required computer ID header" >&2
            debug "Found headers: ${headers}" >&2
        fi
        error "Invalid CSV format detected: File contains ${columnCount} columns without a computer ID header" >&2
        printf "\n${red}ERROR:${resetColor} Invalid CSV format detected\n" >&2
        printf "\n${cyan}What was found:${resetColor}" >&2
        printf "\n  • ${columnCount} columns" >&2
        printf "\n  • Headers: ${headers}" >&2
        printf "\n\n${cyan}What is required:${resetColor}" >&2
        printf "\n  • A single-column CSV with Jamf Pro Computer IDs" >&2
        printf "\n  • A multi-column CSV with a 'JSS Computer ID' or 'Jamf Pro Computer ID' header column" >&2
        printf "\n\nPlease export a valid format from Jamf Pro and try again.\n\n" >&2
        return 1
    fi
    
    csvFormat="single"
    csvDelimiter=""
    csvDelimiterLabel="none"
    
    # Single column format is valid
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# CSV Sanity Check (multi-column only)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function csvSanityCheck() {
    local csvFile="${1}"
    local delimiter="${csvDelimiter}"
    
    if [[ "${csvFormat}" != "multi" ]]; then
        return 0
    fi
    
    if ! command -v ruby >/dev/null 2>&1; then
        warning "Ruby not found; skipping CSV sanity check (multiline fields may be misread)"
        return 0
    fi
    
    local sanityResults
    sanityResults=$(/usr/bin/ruby -rcsv -e '
csv_path = ARGV[0]
col_sep = ARGV[1]
col_sep = "," if col_sep.nil? || col_sep.empty?

header_candidates = ["jss computer id", "jamf pro computer id", "computer id"]

csv = CSV.open(csv_path, "r:BOM|UTF-8", headers: true, col_sep: col_sep)
first_row = csv.shift
exit 1 if first_row.nil?

headers = first_row.headers || []
normalized_headers = headers.map { |h| h.to_s.sub(/\A\xEF\xBB\xBF/, "").strip.gsub(/\A"|"\z/, "").downcase }

column_index = nil
header_candidates.each do |candidate|
  idx = normalized_headers.index(candidate)
  if idx
    column_index = idx
    break
  end
end
exit 2 if column_index.nil?

header_count = headers.length
mismatch_count = 0
empty_id_count = 0
total_rows = 0

total_rows += 1
mismatch_count += 1 if first_row.size != header_count
value = first_row[column_index].to_s.strip.gsub(/\A"|"\z/, "")
empty_id_count += 1 if value.empty?

csv.each do |row|
  total_rows += 1
  mismatch_count += 1 if row.size != header_count
  value = row[column_index].to_s.strip.gsub(/\A"|"\z/, "")
  empty_id_count += 1 if value.empty?
end

puts [total_rows, header_count, mismatch_count, empty_id_count].join("|")
csv.close
' "${csvFile}" "${delimiter}")
    
    local sanityExitCode=$?
    if [[ ${sanityExitCode} -ne 0 ]]; then
        warning "CSV sanity check failed (exit: ${sanityExitCode}); continuing"
        return 0
    fi
    
    local totalRows=""
    local headerCount=""
    local mismatchCount=""
    local emptyIdCount=""
    IFS='|' read -r totalRows headerCount mismatchCount emptyIdCount <<< "${sanityResults}"
    
    if [[ -z "${totalRows}" ]] || [[ -z "${headerCount}" ]]; then
        warning "CSV sanity check returned unexpected output; continuing"
        return 0
    fi
    
    if [[ "${mismatchCount}" -gt 0 ]]; then
        warning "CSV sanity check: ${mismatchCount} rows have ${headerCount} mismatch (out of ${totalRows})"
    fi
    
    if [[ "${emptyIdCount}" -gt 0 ]]; then
        warning "CSV sanity check: ${emptyIdCount} rows have empty Computer IDs (out of ${totalRows})"
    fi
    
    if [[ "${mismatchCount}" -eq 0 ]] && [[ "${emptyIdCount}" -eq 0 ]]; then
        info "CSV sanity check passed (${totalRows} rows, ${headerCount} columns)"
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Extract JSS Computer ID column from CSV with headers
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function extractJssIdColumn() {
    local csvFile="${1}"
    local tempFile="${csvFile}.jssids.tmp"
    local extractExitCode=1
    
    # Read first line to check for header
    local firstLine=$(head -n 1 "${csvFile}" | tr -d '\r')
    local firstLineLower="${firstLine:l}"
    local delimiter="${csvDelimiter}"
    local hasIdHeader="false"
    
    if [[ -z "${delimiter}" ]]; then
        if [[ "${firstLine}" == *","* ]]; then
            delimiter=","
        elif [[ "${firstLine}" == *$'\t'* ]]; then
            delimiter=$'\t'
        elif [[ "${firstLine}" == *";"* ]]; then
            delimiter=";"
        fi
    fi
    
    if [[ "${firstLineLower}" == *"jss computer id"* ]] || [[ "${firstLineLower}" == *"jamf pro computer id"* ]] || [[ "${firstLineLower}" == *"computer id"* ]]; then
        hasIdHeader="true"
    fi
    
    # Check if first line contains a Computer ID header
    if [[ "${hasIdHeader}" == "true" ]]; then
        info "Detected CSV with computer ID header; extracting IDs …" >&2
        
        # Determine if this is multi-column CSV
        if [[ -n "${delimiter}" ]]; then
            # Multi-column CSV - parse with a CSV-aware parser if available
            if command -v ruby >/dev/null 2>&1; then
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Using ruby CSV parser for reliable extraction" >&2
                fi
                
                /usr/bin/ruby -rcsv -e '
csv_path = ARGV[0]
out_path = ARGV[1]
col_sep = ARGV[2]
col_sep = "," if col_sep.nil? || col_sep.empty?

header_candidates = ["jss computer id", "jamf pro computer id", "computer id"]

csv = CSV.open(csv_path, "r:BOM|UTF-8", headers: true, col_sep: col_sep)
first_row = csv.shift
exit 1 if first_row.nil?

headers = (first_row.headers || []).map { |h| h.to_s.sub(/\A\xEF\xBB\xBF/, "").strip.gsub(/\A"|"\z/, "").downcase }

column_index = nil
header_candidates.each do |candidate|
  idx = headers.index(candidate)
  if idx
    column_index = idx
    break
  end
end

exit 2 if column_index.nil?

File.open(out_path, "w") do |out|
  value = first_row[column_index].to_s.strip.gsub(/\A"|"\z/, "")
  out.puts(value) if value =~ /\A\d+\z/

  csv.each do |row|
    value = row[column_index].to_s.strip.gsub(/\A"|"\z/, "")
    out.puts(value) if value =~ /\A\d+\z/
  end
end

csv.close
' "${csvFile}" "${tempFile}" "${delimiter}"
                extractExitCode=$?
                if [[ ${extractExitCode} -ne 0 ]]; then
                    error "Ruby CSV parsing failed (exit: ${extractExitCode})" >&2
                    return 1
                fi
            else
                info "ruby not found; falling back to awk parsing (multiline fields may be misread)" >&2
                
                # Convert header line to array and find column index
                local columnIndex=0
                local currentIndex=1
                local -a headers
                local IFS="${delimiter}"
                read -r -A headers <<< "${firstLine}"
                
                for header in "${headers[@]}"; do
                    # Clean up header (remove quotes and whitespace)
                    header=$(printf "%s" "${header}" | sed 's/^[[:space:]]*"\{0,1\}//;s/"\{0,1\}[[:space:]]*$//')
                    local headerLower="${header:l}"
                    if [[ "${debugMode}" == "true" ]]; then
                        debug "Column ${currentIndex}: '${header}'" >&2
                    fi
                    if [[ "${headerLower}" == "jss computer id" ]] || [[ "${headerLower}" == "jamf pro computer id" ]] || [[ "${headerLower}" == "computer id" ]]; then
                        columnIndex=${currentIndex}
                        info "Found computer ID header in column ${columnIndex}" >&2
                        break
                    fi
                    (( currentIndex++ ))
                done
                
                if [[ ${columnIndex} -le 0 ]]; then
                    error "Failed to locate a computer ID column in CSV header" >&2
                    return 1
                fi
                
                # Extract the specific column (skip header, extract column by index)
                # Set LC_ALL=C to handle multibyte characters in other columns
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Extracting column ${columnIndex} using awk with LC_ALL=C" >&2
                fi
                
                local awkDelimiter="${delimiter}"
                case "${delimiter}" in
                    $'\t') awkDelimiter='\t' ;;
                esac
                
                tail -n +2 "${csvFile}" | LC_ALL=C awk -F"${awkDelimiter}" -v col="${columnIndex}" '{
                    # Remove quotes and whitespace from the field
                    gsub(/^[[:space:]]*"*|"*[[:space:]]*$/, "", $col);
                    if ($col ~ /^[0-9]+$/) print $col
                }' > "${tempFile}"
                extractExitCode=$?
            fi
        else
            # Single-column CSV with header - just skip the header
            tail -n +2 "${csvFile}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk '/^[0-9]+$/ {print; }' > "${tempFile}"
            extractExitCode=$?
        fi
        
        if [[ ${extractExitCode} -eq 0 ]] && [[ -f "${tempFile}" ]]; then
            # Count non-empty lines more reliably
            local extractedCount=$(grep -c . "${tempFile}" 2>/dev/null || echo "0")
            info "Extracted ${extractedCount} JSS Computer IDs from CSV" >&2
            if [[ "${debugMode}" == "true" ]]; then
                debug "Sample extracted IDs (first 5): $(head -n 5 "${tempFile}" | tr '\n' ',' | sed 's/,$//')" >&2
            fi
            echo "${tempFile}"
            return 0
        else
            error "Failed to extract JSS Computer IDs" >&2
            return 1
        fi
    else
        # No header detected, assume simple format
        info "No headers detected; assuming simple ID/Serial format" >&2
        echo "${csvFile}"
        return 0
    fi
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get computer information by JSS Computer ID
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getComputerById() {
    local computerId="${1}"
    local rawResponse
    local responseWithCode
    local httpStatus
    local computerInfo
    local attempt=1
    local maxAttempts=3
    local delay=2
    
    # Validate that identifier is numeric
    if [[ ! "${computerId}" =~ ^[0-9]+$ ]]; then
        if [[ "${debugMode}" == "true" ]]; then
            debug "Invalid Computer ID: '${computerId}' (must be numeric)" >&2
        fi
        return 1
    fi
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Looking up computer by ID: ${computerId}" >&2
        debug "API endpoint: ${apiUrl}/api/v1/computers-inventory-detail/${computerId}" >&2
    fi
    
    while [[ ${attempt} -le ${maxAttempts} ]]; do
        # Check and refresh token if needed before API call
        checkAndRefreshToken
        
        responseWithCode=$(
            curl -H "Authorization: Bearer ${apiBearerToken}" \
                 -H "Accept: application/json" \
                 --max-time 30 \
                 -sfk -w "%{http_code}" \
                 "${apiUrl}/api/v1/computers-inventory-detail/${computerId}?section=GENERAL&section=HARDWARE&section=OPERATING_SYSTEM" \
                 -X GET 2>/dev/null
        )
        
        httpStatus="${responseWithCode: -3}"
        rawResponse="${responseWithCode%???}"
        
        if [[ "${debugMode}" == "true" ]]; then
            local responseSize=${#rawResponse}
            debug "Computer detail HTTP status: ${httpStatus}" >&2
            debug "Raw API response size: ${responseSize} bytes" >&2
        fi
        
        if [[ "${httpStatus}" == "200" ]]; then
            # Extract only the fields we need using jq on the raw response
            # This filters out extension attributes and other bloat before we store it
            computerInfo=$(printf "%s" "${rawResponse}" | jq -c '{id: .id, general: {name: .general.name, managementId: .general.managementId, declarativeDeviceManagementEnabled: .general.declarativeDeviceManagementEnabled, lastContactTime: .general.lastContactTime}, hardware: {serialNumber: .hardware.serialNumber, modelIdentifier: .hardware.modelIdentifier}, operatingSystem: {version: .operatingSystem.version}}' 2>/dev/null)
            
            if [[ -n "${computerInfo}" ]] && [[ "${computerInfo}" != "null" ]] && [[ "${computerInfo}" != *"jq: parse error"* ]]; then
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Successfully retrieved and filtered computer data for ID ${computerId}" >&2
                    local filteredSize=${#computerInfo}
                    debug "Filtered data size: ${filteredSize} bytes (reduced by $((responseSize - filteredSize)) bytes)" >&2
                fi
                echo "${computerInfo}"
                return 0
            fi
            
            if [[ "${debugMode}" == "true" ]]; then
                debug "Failed to parse JSON for Computer ID ${computerId}" >&2
            fi
            return 1
        fi
        
        if [[ "${httpStatus}" == "401" ]]; then
            info "Token expired during computer lookup; refreshing …" >&2
            if refreshBearerToken; then
                (( attempt++ ))
                continue
            fi
            return 1
        fi
        
        if [[ "${httpStatus}" == "404" ]]; then
            if [[ "${debugMode}" == "true" ]]; then
                debug "Computer ID ${computerId} not found (HTTP 404)" >&2
            fi
            return 2
        fi
        
        if [[ "${httpStatus}" == "429" ]] || [[ "${httpStatus}" =~ ^5 ]]; then
            if [[ ${attempt} -lt ${maxAttempts} ]]; then
                warning "Computer lookup failed with HTTP ${httpStatus}; retrying in ${delay} seconds (attempt ${attempt}/${maxAttempts})" >&2
                sleep ${delay}
                delay=$((delay * 2))
                (( attempt++ ))
                continue
            fi
        fi
        
        if [[ "${debugMode}" == "true" ]]; then
            debug "Computer ID ${computerId} not found or API error (HTTP ${httpStatus})" >&2
        fi
        return 1
    done
    
    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get computer ID by Serial Number
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getComputerIdBySerialNumber() {
    local serialNumber="${1}"
    local rawResponse
    local responseWithCode
    local httpStatus
    local computerId
    local attempt=1
    local maxAttempts=3
    local delay=2
    
    if [[ -z "${serialNumber}" ]]; then
        if [[ "${debugMode}" == "true" ]]; then
            debug "Serial Number is required" >&2
        fi
        return 1
    fi
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Looking up computer by Serial Number: ${serialNumber}" >&2
        debug "API endpoint: ${apiUrl}/api/v1/computers-inventory" >&2
    fi
    
    while [[ ${attempt} -le ${maxAttempts} ]]; do
        # Check and refresh token if needed before API call
        checkAndRefreshToken
        
        # Use Modern API with filter to find computer by serial number
        responseWithCode=$(
            curl -H "Authorization: Bearer ${apiBearerToken}" \
                 -H "Accept: application/json" \
                 --max-time 30 \
                 -sfk -w "%{http_code}" \
                 "${apiUrl}/api/v1/computers-inventory?section=GENERAL&page=0&page-size=1&filter=hardware.serialNumber%3D%3D%22${serialNumber}%22" \
                 -X GET 2>/dev/null
        )
        
        httpStatus="${responseWithCode: -3}"
        rawResponse="${responseWithCode%???}"
        
        if [[ "${debugMode}" == "true" ]]; then
            local responseSize=${#rawResponse}
            debug "Computer lookup HTTP status: ${httpStatus}" >&2
            debug "Raw API response size: ${responseSize} bytes" >&2
        fi
        
        if [[ "${httpStatus}" == "200" ]]; then
            # Check if we got results
            local totalCount=$(printf "%s" "${rawResponse}" | jq -r '.totalCount // 0' 2>/dev/null)
            
            if [[ "${totalCount}" -eq 0 ]]; then
                if [[ "${debugMode}" == "true" ]]; then
                    debug "No computer found with Serial Number: ${serialNumber}" >&2
                fi
                return 2
            fi
            
            # Extract the computer ID from the first result
            computerId=$(printf "%s" "${rawResponse}" | jq -r '.results[0].id // empty' 2>/dev/null)
            
            if [[ -n "${computerId}" ]] && [[ "${computerId}" != "null" ]]; then
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Successfully resolved Serial Number ${serialNumber} to Computer ID ${computerId}" >&2
                fi
                echo "${computerId}"
                return 0
            fi
            
            if [[ "${debugMode}" == "true" ]]; then
                debug "Failed to resolve Serial Number ${serialNumber} to Computer ID" >&2
            fi
            return 1
        fi
        
        if [[ "${httpStatus}" == "401" ]]; then
            info "Token expired during serial lookup; refreshing …" >&2
            if refreshBearerToken; then
                (( attempt++ ))
                continue
            fi
            return 1
        fi
        
        if [[ "${httpStatus}" == "429" ]] || [[ "${httpStatus}" =~ ^5 ]]; then
            if [[ ${attempt} -lt ${maxAttempts} ]]; then
                warning "Serial lookup failed with HTTP ${httpStatus}; retrying in ${delay} seconds (attempt ${attempt}/${maxAttempts})" >&2
                sleep ${delay}
                delay=$((delay * 2))
                (( attempt++ ))
                continue
            fi
        fi
        
        if [[ "${debugMode}" == "true" ]]; then
            debug "Failed to resolve Serial Number ${serialNumber} to Computer ID (HTTP ${httpStatus})" >&2
        fi
        return 1
    done
    
    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Retry Logic with Exponential Backoff
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function retryWithBackoff() {
    local maxAttempts=3
    local attempt=1
    local delay=2
    local exitCode
    
    while [[ ${attempt} -le ${maxAttempts} ]]; do
        if [[ "${debugMode}" == "true" ]]; then
            debug "Attempt ${attempt} of ${maxAttempts}" >&2
        fi
        
        # Execute the command passed as arguments
        "$@"
        exitCode=$?
        
        if [[ ${exitCode} -eq 0 ]]; then
            return 0
        fi
        
        if [[ ${attempt} -lt ${maxAttempts} ]]; then
            if [[ "${debugMode}" == "true" ]]; then
                debug "Attempt ${attempt} failed with exit code ${exitCode}. Retrying in ${delay} seconds..." >&2
            fi
            info "API call failed. Retrying in ${delay} seconds (attempt ${attempt}/${maxAttempts})..." >&2
            sleep ${delay}
            delay=$((delay * 2))  # Exponential backoff
        fi
        
        (( attempt++ ))
    done
    
    error "All ${maxAttempts} attempts failed" >&2
    return ${exitCode}
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get DDM status items for a management ID
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getDdmStatusItems() {
    local managementId="${1}"
    local ddmStatusAndCode
    local httpStatus
    local ddmStatus
    local attempt=1
    local maxAttempts=3
    local delay=2
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Calling DDM status endpoint for Management ID: ${managementId}" >&2
        debug "API endpoint: ${apiUrl}/api/v1/ddm/${managementId}/status-items" >&2
    fi
    
    while [[ ${attempt} -le ${maxAttempts} ]]; do
        # Check and refresh token if needed before API call
        checkAndRefreshToken
        
        ddmStatusAndCode=$(
            curl -H "Authorization: Bearer ${apiBearerToken}" \
                 -H "Accept: application/json" \
                 --max-time 30 \
                 -sfk -w "%{http_code}" \
                 "${apiUrl}/api/v1/ddm/${managementId}/status-items" \
                 -X GET 2>/dev/null
        )
        
        httpStatus="${ddmStatusAndCode: -3}"
        ddmStatus="${ddmStatusAndCode%???}"
        
        if [[ "${debugMode}" == "true" ]]; then
            debug "DDM status HTTP response: ${httpStatus}" >&2
            if [[ "${httpStatus}" == "200" ]]; then
                local statusItemCount=$(printf "%s" "${ddmStatus}" | grep -o '"key":' | wc -l | tr -d ' ')
                debug "DDM status items count: ${statusItemCount}" >&2
            fi
        fi
        
        if [[ "${httpStatus}" == "200" ]]; then
            echo "${ddmStatus}"
            return 0
        fi
        
        # Handle 404 - no status items available yet (not an error)
        if [[ "${httpStatus}" == "404" ]]; then
            if [[ "${debugMode}" == "true" ]]; then
                debug "No DDM status items available (HTTP 404) for Management ID: ${managementId}" >&2
            fi
            return 2  # Special return code for "no data available"
        fi
        
        # Handle 401 with token refresh
        if [[ "${httpStatus}" == "401" ]]; then
            info "Token expired during DDM status retrieval; refreshing …" >&2
            if refreshBearerToken; then
                info "Token refreshed successfully. Retrying DDM status retrieval for Management ID ${managementId} …" >&2
                (( attempt++ ))
                continue
            else
                error "Failed to refresh token during DDM status retrieval for Management ID ${managementId}" >&2
                return 1
            fi
        fi
        
        if [[ "${httpStatus}" == "429" ]] || [[ "${httpStatus}" =~ ^5 ]]; then
            if [[ ${attempt} -lt ${maxAttempts} ]]; then
                warning "DDM status retrieval failed with HTTP ${httpStatus}; retrying in ${delay} seconds (attempt ${attempt}/${maxAttempts})" >&2
                sleep ${delay}
                delay=$((delay * 2))
                (( attempt++ ))
                continue
            fi
        fi
        
        if [[ "${debugMode}" == "true" ]]; then
            debug "DDM status retrieval failed with HTTP ${httpStatus} for Management ID: ${managementId}" >&2
        fi
        return 1
    done
    
    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse active blueprints from DDM status items
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseActiveBlueprints() {
    local ddmStatus="${1}"
    local activeBlueprints=""
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Parsing DDM status for active blueprints..." >&2
    fi
    
    # Parse through status items looking for management.declarations.activations key
    local index=0
    while [[ ${index} -lt 200 ]]; do  # Reasonable upper limit
        local key=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.key raw - 2>/dev/null)
        
        if [[ -z "${key}" ]] || [[ "${key}" == "null" ]]; then
            if [[ "${debugMode}" == "true" ]]; then
                debug "Parsed ${index} status items for active blueprints" >&2
            fi
            break
        fi
        
        # Look for the activations key which contains blueprint identifiers
        if [[ "${key}" == "management.declarations.activations" ]]; then
            local value=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.value raw - 2>/dev/null)
            
            if [[ -n "${value}" ]] && [[ "${value}" != "null" ]]; then
                # Extract just the identifier values from the blueprint objects
                # Format: {active=true,identifier=ID,valid=valid,server-token=TOKEN}
                activeBlueprints=$(printf "%s" "${value}" | grep -oE 'identifier=[^,}]+' | sed 's/identifier=//' | tr '\n' ';' | sed 's/;$//')
            fi
            break
        fi
        
        (( index++ ))
    done
    
    echo "${activeBlueprints}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse failed blueprints from DDM status items (excludes software update errors)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseFailedBlueprints() {
    local ddmStatus="${1}"
    local failedBlueprints=""
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Parsing DDM status for failed blueprints..." >&2
    fi
    
    # Parse through status items looking for blueprint/declaration errors
    local index=0
    while [[ ${index} -lt 200 ]]; do  # Reasonable upper limit
        local key=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.key raw - 2>/dev/null)
        
        if [[ -z "${key}" ]] || [[ "${key}" == "null" ]]; then
            break
        fi
        
        # Look for error, failure, or rejected declaration keys (but exclude software update errors)
        if [[ "${key}" != softwareupdate.* ]] && ([[ "${key}" == *"error"* ]] || [[ "${key}" == *"failed"* ]] || [[ "${key}" == *"failure"* ]] || [[ "${key}" == *"rejected"* ]]); then
            if [[ "${debugMode}" == "true" ]]; then
                debug "Found error key: ${key}" >&2
            fi
            local value=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.value raw - 2>/dev/null)
            
            if [[ -n "${value}" ]] && [[ "${value}" != "null" ]] && [[ "${value}" != "" ]] && [[ "${value}" != "0" ]]; then
                # Try to extract blueprint identifier from key
                local blueprintId=$(echo "${key}" | sed 's/.*declaration\.\([^.]*\).*/\1/')
                if [[ -n "${blueprintId}" ]] && [[ "${blueprintId}" != "${key}" ]]; then
                    if [[ -z "${failedBlueprints}" ]]; then
                        failedBlueprints="${blueprintId}: ${value}"
                    else
                        failedBlueprints="${failedBlueprints}; ${blueprintId}: ${value}"
                    fi
                else
                    # Include non-blueprint errors
                    if [[ -z "${failedBlueprints}" ]]; then
                        failedBlueprints="${key}: ${value}"
                    else
                        failedBlueprints="${failedBlueprints}; ${key}: ${value}"
                    fi
                fi
            fi
        fi
        
        (( index++ ))
    done
    
    echo "${failedBlueprints}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse software update errors from DDM status items
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parseSoftwareUpdateErrors() {
    local ddmStatus="${1}"
    local updateErrors=""
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Parsing DDM status for software update errors..." >&2
    fi
    
    # Parse through status items looking for software update errors
    local index=0
    while [[ ${index} -lt 200 ]]; do  # Reasonable upper limit
        local key=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.key raw - 2>/dev/null)
        
        if [[ -z "${key}" ]] || [[ "${key}" == "null" ]]; then
            break
        fi
        
        # Look specifically for software update failure keys
        if [[ "${key}" == softwareupdate.failure-* ]]; then
            if [[ "${debugMode}" == "true" ]]; then
                debug "Found software update error key: ${key}" >&2
            fi
            local value=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.value raw - 2>/dev/null)
            
            if [[ -n "${value}" ]] && [[ "${value}" != "null" ]] && [[ "${value}" != "" ]] && [[ "${value}" != "0" ]]; then
                if [[ -z "${updateErrors}" ]]; then
                    updateErrors="${key}: ${value}"
                else
                    updateErrors="${updateErrors}; ${key}: ${value}"
                fi
            fi
        fi
        
        (( index++ ))
    done
    
    echo "${updateErrors}"
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Parse pending software updates from DDM status items
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function parsePendingSoftwareUpdates() {
    local ddmStatus="${1}"
    local buildNumber=""
    local osVersion=""
    local deadline=""
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Parsing DDM status for pending software updates..." >&2
    fi
    
    # Parse through status items looking for specific software update keys
    local index=0
    while [[ ${index} -lt 200 ]]; do  # Reasonable upper limit
        local key=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.key raw - 2>/dev/null)
        
        if [[ -z "${key}" ]] || [[ "${key}" == "null" ]]; then
            break
        fi
        
        # Extract specific software update information
        if [[ "${key}" == "softwareupdate.pending-version.build-version" ]]; then
            buildNumber=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.value raw - 2>/dev/null)
            if [[ "${debugMode}" == "true" ]]; then
                debug "Found pending build version: ${buildNumber}" >&2
            fi
        elif [[ "${key}" == "softwareupdate.pending-version.os-version" ]]; then
            osVersion=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.value raw - 2>/dev/null)
            if [[ "${debugMode}" == "true" ]]; then
                debug "Found pending OS version: ${osVersion}" >&2
            fi
        elif [[ "${key}" == "softwareupdate.install-deadline" ]]; then
            deadline=$(printf "%s" "${ddmStatus}" | plutil -extract statusItems.${index}.value raw - 2>/dev/null)
            if [[ "${debugMode}" == "true" ]]; then
                debug "Found install deadline: ${deadline}" >&2
            fi
        fi
        
        (( index++ ))
    done
    
    # Construct output with available information
    local pendingUpdates=""
    if [[ -n "${buildNumber}" ]] && [[ "${buildNumber}" != "null" ]]; then
        pendingUpdates="${buildNumber}"
    fi
    if [[ -n "${osVersion}" ]] && [[ "${osVersion}" != "null" ]]; then
        if [[ -n "${pendingUpdates}" ]]; then
            pendingUpdates="${pendingUpdates}; ${osVersion}"
        else
            pendingUpdates="${osVersion}"
        fi
    fi
    if [[ -n "${deadline}" ]] && [[ "${deadline}" != "null" ]]; then
        if [[ -n "${pendingUpdates}" ]]; then
            pendingUpdates="${pendingUpdates}; ${deadline}"
        else
            pendingUpdates="${deadline}"
        fi
    fi
    
    echo "${pendingUpdates}"
}



####################################################################################################
#
# Pre-flight Checks
#
####################################################################################################

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Process Command-line Arguments
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

laneSelectionRequested="no"
specifiedLane=""
singleLookupMode="no"
lookupSerialNumber=""

# Array to collect positional parameters
declare -a positionalArgs=()

# Single-pass argument parsing with position-independent flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            displayHelp
            ;;
        --debug|-d)
            debugMode="true"
            shift
            ;;
        --lane|-l)
            laneSelectionRequested="yes"
            shift
            # Check if next argument is a valid lane name (not a flag)
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                case "$1" in
                    dev|development|d|D|stage|s|S|prod|production|p|P)
                        specifiedLane="$1"
                        shift
                        ;;
                esac
            fi
            ;;
        --serial|-s)
            singleLookupMode="yes"
            shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                lookupSerialNumber="$1"
                shift
            else
                die "Error: --serial requires a serial number argument"
            fi
            ;;
        --output-dir)
            shift
            if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^- ]]; then
                outputDir="$1"
                shift
            else
                die "Error: --output-dir requires a path argument"
            fi
            ;;
        --parallel)
            parallelProcessing="true"
            shift
            ;;
        --max-jobs)
            shift
            if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                maxParallelJobs="$1"
                shift
            else
                die "Error: --max-jobs requires a numeric argument"
            fi
            ;;
        --no-open)
            noOpen="true"
            shift
            ;;
        -*)
            # Unknown flag - fail fast
            die "Error: Unknown flag '$1'. Use --help for usage information."
            ;;
        *)
            # Collect positional arguments
            positionalArgs+=("$1")
            shift
            ;;
    esac
done

# Validate parallel processing settings
if [[ "${maxParallelJobs}" != "10" ]] && [[ "${parallelProcessing}" != "true" ]]; then
    warning "--max-jobs specified without --parallel flag; parallel processing will not be enabled"
fi

# Assign positional parameters from collected array
# Order: apiUrl apiUser apiPassword filename
if [[ ${#positionalArgs[@]} -ge 1 ]]; then
    apiUrl="${positionalArgs[1]}"
fi
if [[ ${#positionalArgs[@]} -ge 2 ]]; then
    apiUser="${positionalArgs[2]}"
fi
if [[ ${#positionalArgs[@]} -ge 3 ]]; then
    apiPassword="${positionalArgs[3]}"
fi
if [[ ${#positionalArgs[@]} -ge 4 ]]; then
    filename="${positionalArgs[4]}"
fi

if [[ "${debugMode}" == "true" ]]; then
    debug "Collected ${#positionalArgs[@]} positional parameters"
    debug "Lane selection: ${laneSelectionRequested}, Single lookup: ${singleLookupMode}"
    debug "Parameters: apiUrl=${apiUrl:-empty}, apiUser=${apiUser:-empty}, filename=${filename:-empty}"
fi

# Initialize output paths now that outputDir is set
scriptLog="${outputDir}/DDM_Status_Report.log"
csvOutput="${outputDir}/DDM_Status_Report_$(date +%Y-%m-%d-%H%M%S).csv"

# Create output directory if it doesn't exist
if [[ ! -d "${outputDir}" ]]; then
    mkdir -p "${outputDir}" 2>/dev/null || die "Failed to create output directory: ${outputDir}"
fi


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ! -f "${scriptLog}" ]]; then
    touch "${scriptLog}" || {
        echo "ERROR: Unable to create log file at ${scriptLog}"
        exit 1
    }
fi

printf "${dividerLine}"
printf "\n###\n"
printf "# ${scriptDisplayName} (${yellow}${scriptVersion}${resetColor})\n"
printf "###\n"
updateScriptLog "\n\n###\n# ${scriptDisplayName} (${scriptVersion})\n###\n"
preFlight "Initiating …"

if [[ "${debugMode}" == "true" ]]; then
    debug "Debug Mode Enabled"
    printf "\n${green}DEBUG MODE ENABLED${resetColor}\n"
fi

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Prompt for help if no parameters provided
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Check if no positional parameters were provided (all empty)
if [[ -z "${apiUrl}" ]] && [[ -z "${apiUser}" ]] && [[ -z "${apiPassword}" ]] && [[ -z "${filename}" ]] && [[ "${laneSelectionRequested}" == "no" ]]; then
    echo "
No parameters provided.

Would you like to:

[h] Display help information
[c] Continue with interactive mode
[x] Exit"

    printf "\n> "
    read -k 1 initialChoice
    printf "\n"

    case "${initialChoice}" in
        h|H)
            displayHelp
            ;;
        c|C)
            echo ""
            # Continue with interactive mode
            ;;
        x|X)
            echo ""
            echo "Exiting. Goodbye!"
            echo ""
            exit 0
            ;;
        *)
            echo ""
            echo "${red}ERROR:${resetColor} Did not recognize response: ${initialChoice}; exiting."
            echo ""
            exit 1
            ;;
    esac
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Tools
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

preflightTools



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: API Credentials
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

printf "${dividerLine}"
printf "\n###\n"
printf "# Step 1: API Connection Settings\n"
printf "###\n"

# Check if explicit credentials were provided via positional parameters
explicitCredentialsProvided="no"
if [[ -n "${apiUrl}" ]] && [[ -n "${apiUser}" ]] && [[ -n "${apiPassword}" ]]; then
    explicitCredentialsProvided="yes"
fi

# Check if lane selection was requested
if [[ "${laneSelectionRequested}" == "yes" ]]; then
    # If explicit credentials were already provided, warn and use explicit credentials
    if [[ "${explicitCredentialsProvided}" == "yes" ]]; then
        printf "\n${yellow}⚠${resetColor} Lane selection (-l/--lane) specified but explicit credentials were also provided.\n"
        printf "${yellow}⚠${resetColor} Using explicit credentials instead of lane configuration.\n"
        if [[ "${debugMode}" == "true" ]]; then
            debug "Skipping lane selection; using explicit credentials (URL: ${apiUrl})"
        fi
    else
        # No explicit credentials, use lane selection
        if [[ -n "${specifiedLane}" ]]; then
            info "Lane selection requested with specified lane: ${specifiedLane}"
        else
            info "Lane selection requested; prompting user ..."
        fi
        laneSelection "${specifiedLane}"
        printf "\n${green}✓${resetColor} Lane credentials configured\n"
    fi
fi

# Prompt for missing API credentials
promptAPIurl
promptAPIusername
promptAPIpassword

if [[ -z "${apiUrl}" ]] || [[ -z "${apiUser}" ]] || [[ -z "${apiPassword}" ]]; then
    die "Unable to determine API credentials (URL/User/Password)."
else
    info "API credentials available; proceeding to validation …"
fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Bearer Token
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

printf "${dividerLine}"
printf "\n###\n"
printf "# Step 2: Obtain Bearer Token\n"
printf "###\n"

getBearerToken

printf "\n${green}✓${resetColor} Bearer Token obtained successfully\n"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Validate CSV filename (skip in single lookup mode)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${singleLookupMode}" != "yes" ]]; then

    printf "${dividerLine}"
    printf "\n###\n"
    printf "# Step 3: Validate CSV Input File\n"
    printf "###\n"
    printf "\n"

    # Prompt for CSV filename if not provided
    promptCSVfilename

    if [[ -z "${filename}" ]]; then
        die "A list of Jamf Pro Computer IDs was NOT specified."
    elif [[ ! -f "${filename}" ]]; then
        die "The specified file '${filename}' does not exist."
    else
        filenameNumberOfLines=$(awk 'END { print NR }' "${filename}")
        info "The filename '${filename}' contains ${filenameNumberOfLines} lines; proceeding …"
        printf "${green}✓${resetColor} CSV file contains ${filenameNumberOfLines} lines\n"
        
        # Validate CSV format (single or multi-column with Computer ID header)
        if ! validateCsvFormat "${filename}"; then
            die "CSV format validation failed. Please provide a valid CSV file with computer IDs."
        fi
        if [[ "${csvFormat}" == "multi" ]]; then
            printf "${green}✓${resetColor} CSV format validated (multi-column; delimiter: ${csvDelimiterLabel})\n"
        else
            printf "${green}✓${resetColor} CSV format validated (single column)\n"
        fi

        # Optional sanity check for multi-column CSVs
        csvSanityCheck "${filename}"
        
        # Extract JSS Computer ID column if CSV has headers
        processedFilename=$(extractJssIdColumn "${filename}")
        if [[ $? -ne 0 ]]; then
            die "Failed to process CSV file."
        fi
        
        # Update line count for processed file
        processedNumberOfLines=$(awk 'END { print NR }' "${processedFilename}")
        
        if [[ "${processedFilename}" != "${filename}" ]]; then
            info "Processing ${processedNumberOfLines} extracted JSS Computer IDs …"
            printf "${green}✓${resetColor} Extracted ${processedNumberOfLines} JSS Computer IDs from CSV\n"
            filenameNumberOfLines="${processedNumberOfLines}"
        fi
    fi

else

    # Single lookup mode: Validate serial number was provided
    if [[ -z "${lookupSerialNumber}" ]]; then
        die "Serial Number is required when using --serial flag."
    fi
    
    printf "${dividerLine}"
    printf "\n###\n"
    printf "# Step 3: Single Lookup Mode\n"
    printf "###\n"
    printf "\n"
    
    info "Single lookup mode enabled for Serial Number: ${lookupSerialNumber}"
    printf "${green}✓${resetColor} Single lookup mode: Serial Number ${lookupSerialNumber}\n"

fi



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Pre-flight Check: Initialize CSV Output (skip in single lookup mode)
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${singleLookupMode}" != "yes" ]]; then

    printf "${dividerLine}"
    printf "\n###\n"
    printf "# Step 4: Initialize CSV Output\n"
    printf "###\n"
    printf "\n"

    info "Initializing CSV output: ${csvOutput}"
    printf "${green}✓${resetColor} CSV output file: ${csvOutput}\n"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Creating CSV with header row"
    fi
    echo "Jamf Pro Computer ID,Jamf Pro Link,Name,Serial Number,Last Inventory Update,Current OS,Pending Updates,Model,Management ID,DDM Enabled,Active Blueprints,Failed Blueprints,Software Update Errors" > "${csvOutput}"
    if [[ "${debugMode}" == "true" ]]; then
        debug "CSV file created successfully at: ${csvOutput}"
    fi

fi



####################################################################################################
#
# Program
#
####################################################################################################

printf "${dividerLine}"
printf "\n###\n"
printf "# Step 5: Processing Computers\n"
printf "###\n"
printf "\n"



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Single Lookup Mode
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ "${singleLookupMode}" == "yes" ]]; then

    info "Looking up Serial Number: ${lookupSerialNumber}"
    printf "Looking up Serial Number: ${lookupSerialNumber} …\n\n"
    
    # Resolve Serial Number to Computer ID
    info "Resolving Serial Number to Computer ID …"
    computerId=$(retryWithBackoff getComputerIdBySerialNumber "${lookupSerialNumber}")
    
    if [[ $? -ne 0 ]] || [[ -z "${computerId}" ]]; then
        printf "${red}✗${resetColor} Serial Number '${lookupSerialNumber}' not found in Jamf Pro\n\n"
        error "Serial Number '${lookupSerialNumber}' not found in Jamf Pro"
        invalidateBearerToken
        printf "${dividerLine}\n\n"
        exit 1
    fi
    
    info "Resolved Serial Number ${lookupSerialNumber} to Computer ID ${computerId}"
    printf "${green}✓${resetColor} Resolved to Computer ID: ${computerId}\n\n"
    
    # Retrieve computer information
    info "Retrieving computer information for Computer ID ${computerId} …"
    computerInfoRaw=$(retryWithBackoff getComputerById "${computerId}")
    
    if [[ $? -ne 0 ]] || [[ -z "${computerInfoRaw}" ]]; then
        printf "${red}✗${resetColor} Failed to retrieve computer information\n\n"
        error "Failed to retrieve computer information for Computer ID ${computerId}"
        invalidateBearerToken
        printf "${dividerLine}\n\n"
        exit 1
    fi
    
    # Parse computer information
    computerName=$(printf "%s" "${computerInfoRaw}" | jq -r '.general.name // "Unknown"')
    computerSerialNumber=$(printf "%s" "${computerInfoRaw}" | jq -r '.hardware.serialNumber // "Unknown"')
    computerLastContactTime=$(printf "%s" "${computerInfoRaw}" | jq -r '.general.lastContactTime // "Unknown"')
    computerOsVersion=$(printf "%s" "${computerInfoRaw}" | jq -r '.operatingSystem.version // "Unknown"')
    computerModelIdentifier=$(printf "%s" "${computerInfoRaw}" | jq -r '.hardware.modelIdentifier // "Unknown"')
    managementId=$(printf "%s" "${computerInfoRaw}" | jq -r '.general.managementId // "Unknown"')
    ddmEnabled=$(printf "%s" "${computerInfoRaw}" | jq -r '.general.declarativeDeviceManagementEnabled // false')
    
    # Display computer information
    printf "${cyan}Computer Information:${resetColor}\n"
    printf "  • Name: ${computerName}\n"
    printf "  • Serial Number: ${computerSerialNumber}\n"
    printf "  • Computer ID: ${computerId}\n"
    printf "  • Management ID: ${managementId}\n"
    printf "  • Last Contact: ${computerLastContactTime}\n"
    printf "  • Current OS: ${computerOsVersion}\n"
    printf "  • Model: ${computerModelIdentifier}\n"
    printf "  • DDM Enabled: ${ddmEnabled}\n\n"
    
    info "Computer Name: ${computerName}"
    info "Serial Number: ${computerSerialNumber}"
    info "Computer ID: ${computerId}"
    info "Management ID: ${managementId}"
    info "DDM Enabled: ${ddmEnabled}"
    
    # Check DDM status if enabled
    if [[ "${ddmEnabled}" == "true" ]]; then
        
        info "DDM is enabled; retrieving DDM status items …"
        printf "${cyan}DDM Status:${resetColor}\n"
        
        # Get DDM status items
        ddmStatusRaw=$(retryWithBackoff getDdmStatusItems "${managementId}")
        
        if [[ $? -eq 0 ]] && [[ -n "${ddmStatusRaw}" ]]; then
            
            # Parse DDM status
            activeBlueprints=$(parseActiveBlueprints "${ddmStatusRaw}")
            failedBlueprints=$(parseFailedBlueprints "${ddmStatusRaw}")
            softwareUpdateErrors=$(parseSoftwareUpdateErrors "${ddmStatusRaw}")
            pendingUpdates=$(parsePendingSoftwareUpdates "${ddmStatusRaw}")
            
            printf "  • Active Blueprints: ${activeBlueprints:-None}\n"
            printf "  • Failed Blueprints: ${failedBlueprints:-None}\n"
            printf "  • Software Update Errors: ${softwareUpdateErrors:-None}\n"
            printf "  • Pending Updates: ${pendingUpdates:-None}\n\n"
            
            info "Active Blueprints: ${activeBlueprints:-None}"
            info "Failed Blueprints: ${failedBlueprints:-None}"
            info "Software Update Errors: ${softwareUpdateErrors:-None}"
            info "Pending Updates: ${pendingUpdates:-None}"
            
        else
            printf "  ${yellow}⚠${resetColor} No DDM status items available or API error\n\n"
            info "No DDM status items available for Management ID ${managementId}"
        fi
        
    else
        printf "${yellow}⚠${resetColor} DDM is not enabled for this computer\n\n"
        info "DDM is not enabled for this computer"
    fi
    
    # Construct Jamf Pro hyperlink
    jamfProLink="${apiUrl}/computers.html?id=${computerId}&o=r"
    printf "${cyan}Jamf Pro Link:${resetColor}\n"
    printf "  ${jamfProLink}\n\n"
    info "Jamf Pro Link: ${jamfProLink}"
    
    # Cleanup and exit
    printf "${green}✓${resetColor} Single lookup complete\n\n"
    info "Single lookup complete"
    
    invalidateBearerToken
    
    printf "${dividerLine}\n\n"
    exit 0

fi


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# CSV Batch Processing Mode
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

info "\n\nProcessing computers …\n"
printf "Processing ${filenameNumberOfLines} computers …\n\n"

# Display processing mode
if [[ "${parallelProcessing}" == "true" ]]; then
    info "Parallel processing enabled with ${maxParallelJobs} concurrent jobs"
    printf "${cyan}⚡ Parallel processing: ${maxParallelJobs} concurrent jobs${resetColor}\n\n"
fi



####################################################################################################
#
# Process Computer Function (for parallel or sequential execution)
#
####################################################################################################

processComputer() {
    local identifier="$1"
    local recordNumber="$2"
    local totalRecords="$3"
    local tempCsvFile="$4"
    
    local recordStartTime="${SECONDS}"
    
    # Strip CR and BOM (in case of UTF-8 BOM in the file)
    identifier=$(printf "%s" "${identifier}" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
    
    # Skip blank lines
    if [[ -z "${identifier}" ]]; then
        return 0
    fi
    
    local progressPercent=$((recordNumber * 100 / totalRecords))
    info "\n\n\nRecord ${recordNumber} of ${totalRecords} (${progressPercent}%): Identifier: ${identifier}"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Processing record ${recordNumber}: Starting timer for identifier '${identifier}'"
    fi
    printf "${blue}[ ${recordNumber}/${totalRecords} (${progressPercent}%%) ]${resetColor} Processing Jamf Pro Computer ID: ${identifier} …\n"
    
    ################################################################################################
    # Retrieve computer information by JSS Computer ID
    ################################################################################################
    
    computerInfoRaw=$(getComputerById "${identifier}")
    
    if [[ $? -ne 0 ]] || [[ -z "${computerInfoRaw}" ]]; then
        error "Computer '${identifier}' not found in Jamf Pro; skipping …"
        printf "  ${red}✗${resetColor} Computer not found in Jamf Pro\n"
        # Write "Not Found" row to temp CSV
        echo "\"${identifier}\",\"\",\"Not Found\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"" >> "${tempCsvFile}"
        local recordTime=$((SECONDS - recordStartTime))
        info "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((recordTime/3600)) $((recordTime%3600/60)) $((recordTime%60)))"
        return 1
    fi
    
    # Extract all fields from the retrieved computer data
    # Parse the filtered JSON with jq
    fieldData=$(printf "%s" "${computerInfoRaw}" | jq -r '[.id // "", .general.name // "", .hardware.serialNumber // "", .general.managementId // "", .general.declarativeDeviceManagementEnabled // "", .operatingSystem.version // "", .hardware.modelIdentifier // "", .general.lastContactTime // ""] | join("|")' 2>/dev/null)
    
    if [[ -z "${fieldData}" ]] || [[ "${fieldData}" == "|||||||" ]]; then
        error "Failed to parse JSON for identifier: ${identifier}"
        printf "${red}✗${resetColor} Failed to parse computer data for: ${identifier}\n\n"
        echo "\"${identifier}\",\"${apiUrl}/computers.html?id=${identifier}&o=r\",\"Parse Error\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"" >> "${tempCsvFile}"
        local recordTime=$((SECONDS - recordStartTime))
        info "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((recordTime/3600)) $((recordTime%3600/60)) $((recordTime%60)))"
        return 1
    fi
    
    # Parse the pipe-separated values
    IFS='|' read -r computerId computerName computerSerialNumber managementId ddmEnabled currentOsVersion modelIdentifier lastContactTime <<< "${fieldData}"
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Extracted values - ID: '${computerId}' Name: '${computerName}' Serial: '${computerSerialNumber}' MgmtID: '${managementId}' DDM: '${ddmEnabled}' OS: '${currentOsVersion}' Model: '${modelIdentifier}' LastContact: '${lastContactTime}'"
        printf "${cyan}[DEBUG]${resetColor} Extracted values:\n"
        printf "  - ID: '${computerId}'\n"
        printf "  - Name: '${computerName}'\n"
        printf "  - Serial: '${computerSerialNumber}'\n"
        printf "  - Management ID: '${managementId}'\n"
        printf "  - DDM Enabled: '${ddmEnabled}'\n"
        printf "  - OS Version: '${currentOsVersion}'\n"
        printf "  - Model: '${modelIdentifier}'\n"
        printf "  - Last Inventory Update: '${lastContactTime}'\n\n"
    fi
    
    # Normalize DDM enabled value
    if [[ "${ddmEnabled}" != "true" ]]; then
        ddmEnabled="false"
    fi
    
    info "Computer Information:"
    info "• ID: ${computerId}"
    info "• Name: ${computerName}"
    info "• Serial Number: ${computerSerialNumber}"
    info "• Model: ${modelIdentifier}"
    info "• Management ID: ${managementId}"
    info "• DDM Enabled: ${ddmEnabled}"
    info "• Current OS: ${currentOsVersion}"
    info "• Last Inventory Update: ${lastContactTime}"
    
    printf "  ${green}✓${resetColor} ${computerName} (${computerSerialNumber}) - DDM: ${ddmEnabled}\n"
    
    # Initialize DDM data variables
    local activeBlueprints=""
    local failedBlueprints=""
    local softwareUpdateErrors=""
    local pendingUpdates=""
    
    ################################################################################################
    # Retrieve DDM Status (only if DDM is enabled)
    ################################################################################################
    
    if [[ "${ddmEnabled}" == "true" ]]; then
        
        info "Retrieving DDM status items …"
        printf "  ${cyan}→${resetColor} Retrieving DDM status items …\n"
        
        ddmStatus=$(getDdmStatusItems "${managementId}")
        ddmStatusResult=$?
        
        if [[ ${ddmStatusResult} -eq 0 ]] && [[ -n "${ddmStatus}" ]]; then
            
            if [[ "${debugMode}" == "true" ]]; then
                debug "DDM status retrieved successfully"
                printf "  ${cyan}[DEBUG]${resetColor} DDM status retrieved successfully\n"
            fi
            
            # Parse DDM data
            activeBlueprints=$(parseActiveBlueprints "${ddmStatus}")
            failedBlueprints=$(parseFailedBlueprints "${ddmStatus}")
            softwareUpdateErrors=$(parseSoftwareUpdateErrors "${ddmStatus}")
            pendingUpdates=$(parsePendingSoftwareUpdates "${ddmStatus}")
            
            info "DDM Status:"
            info "• Active Blueprints: ${activeBlueprints:-None}"
            info "• Failed Blueprints: ${failedBlueprints:-None}"
            info "• Software Update Errors: ${softwareUpdateErrors:-None}"
            info "• Pending Updates: ${pendingUpdates:-None}"
            
            if [[ "${debugMode}" == "true" ]]; then
                printf "  ${cyan}→${resetColor} Active: ${activeBlueprints:-None}\n"
                printf "  ${cyan}→${resetColor} Failed: ${failedBlueprints:-None}\n"
                printf "  ${cyan}→${resetColor} SW Errors: ${softwareUpdateErrors:-None}\n"
                printf "  ${cyan}→${resetColor} Pending: ${pendingUpdates:-None}\n"
            fi
            
        elif [[ ${ddmStatusResult} -eq 2 ]]; then
            # HTTP 404 - no status items available yet
            info "No DDM status items available (device hasn't reported status yet)"
            printf "  ${yellow}⚠${resetColor} No DDM status items available yet\n"
            activeBlueprints="No status items"
            failedBlueprints="No status items"
            softwareUpdateErrors="No status items"
            pendingUpdates="No status items"
        else
            warning "Unable to retrieve DDM status for Management ID: ${managementId}"
            printf "  ${yellow}⚠${resetColor} Unable to retrieve DDM status\n"
            activeBlueprints="API Error"
            failedBlueprints="API Error"
            softwareUpdateErrors="API Error"
            pendingUpdates="API Error"
        fi
        
    else
        warning "DDM is not enabled for this computer; skipping DDM status retrieval."
        activeBlueprints="DDM Disabled"
        failedBlueprints="DDM Disabled"
        softwareUpdateErrors="DDM Disabled"
        pendingUpdates="DDM Disabled"
    fi
    
    ################################################################################################
    # Write to temp CSV
    ################################################################################################
    
    # Sanitize data for CSV
    csvIdentifier=$(sanitizeForCsv "${identifier}")
    csvComputerName=$(sanitizeForCsv "${computerName}")
    csvSerialNumber=$(sanitizeForCsv "${computerSerialNumber}")
    csvModelIdentifier=$(sanitizeForCsv "${modelIdentifier}")
    csvManagementId=$(sanitizeForCsv "${managementId}")
    csvDdmEnabled=$(sanitizeForCsv "${ddmEnabled}")
    csvCurrentOsVersion=$(sanitizeForCsv "${currentOsVersion}")
    csvLastContactTime=$(sanitizeForCsv "${lastContactTime}")
    csvActiveBlueprints=$(sanitizeForCsv "${activeBlueprints}")
    csvFailedBlueprints=$(sanitizeForCsv "${failedBlueprints}")
    csvSoftwareUpdateErrors=$(sanitizeForCsv "${softwareUpdateErrors}")
    csvPendingUpdates=$(sanitizeForCsv "${pendingUpdates}")
    
    # Construct Jamf Pro hyperlink
    jamfProLink=""
    if [[ -n "${computerId}" ]] && [[ "${computerId}" != "null" ]]; then
        jamfProLink="${apiUrl}/computers.html?id=${computerId}&o=r"
    fi
    
    echo "\"${csvIdentifier}\",\"${jamfProLink}\",\"${csvComputerName}\",\"${csvSerialNumber}\",\"${csvLastContactTime}\",\"${csvCurrentOsVersion}\",\"${csvPendingUpdates}\",\"${csvModelIdentifier}\",\"${csvManagementId}\",\"${csvDdmEnabled}\",\"${csvActiveBlueprints}\",\"${csvFailedBlueprints}\",\"${csvSoftwareUpdateErrors}\"" >> "${tempCsvFile}"
    
    local recordTime=$((SECONDS - recordStartTime))
    local recordTimeFormatted=$(printf '%dh:%dm:%ds' $((recordTime/3600)) $((recordTime%3600/60)) $((recordTime%60)))
    info "Elapsed Time: ${recordTimeFormatted}"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Record ${recordNumber} processed in ${recordTime} seconds"
    fi
    
    # Add visual separation between records
    if [[ ${recordNumber} -lt ${totalRecords} ]]; then
        printf "\n${blue}---${resetColor}\n\n"
    fi
    
    return 0
}


####################################################################################################
#
# Parallel Job Management Functions
#
####################################################################################################

# Wait for background jobs to complete, with optional maximum job limit
waitForJobs() {
    local maxJobs="${1:-0}"  # 0 means wait for all jobs
    
    while true; do
        local runningJobs=$(jobs -r | wc -l | tr -d ' ')
        
        if [[ ${maxJobs} -eq 0 ]]; then
            # Wait for all jobs to complete
            if [[ ${runningJobs} -eq 0 ]]; then
                break
            fi
        else
            # Wait until we're below the max job limit
            if [[ ${runningJobs} -lt ${maxJobs} ]]; then
                break
            fi
        fi
        
        sleep 0.1
    done
}


function pruneJobPids() {
    local -a alivePids=()
    
    for pid in "${jobPids[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            alivePids+=("${pid}")
        fi
    done
    
    jobPids=("${alivePids[@]}")
}


function waitForAvailableJobSlot() {
    local maxJobs="${1}"
    
    while true; do
        pruneJobPids
        
        if [[ ${#jobPids[@]} -lt ${maxJobs} ]]; then
            break
        fi
        
        sleep 0.1
    done
}


function waitForAllJobPids() {
    pruneJobPids
    
    for pid in "${jobPids[@]}"; do
        wait "${pid}" 2>/dev/null
    done
    
    jobPids=()
}



####################################################################################################
#
# Main Processing Loop
#
####################################################################################################

counter="0"

if [[ "${parallelProcessing}" == "true" ]]; then
    
    ################################################################################################
    # PARALLEL PROCESSING MODE
    ################################################################################################
    
    info "Starting parallel processing with ${maxParallelJobs} concurrent jobs"
    parallelStartTime="${SECONDS}"
    
    # Create temporary directory for parallel job results
    tempDir=$(mktemp -d "${TMPDIR:-/tmp}/jamf-ddm-parallel.XXXXXX")
    
    # Read all identifiers into array
    declare -a identifiers
    while IFS= read -r identifier; do
        identifier=$(printf "%s" "${identifier}" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
        if [[ -n "${identifier}" ]]; then
            identifiers+=("${identifier}")
        fi
    done < "${processedFilename}"
    
    totalRecords="${#identifiers[@]}"
    info "Processing ${totalRecords} computers in parallel mode"
    if [[ "${debugMode}" == "true" ]]; then
        printf "${cyan}[DEBUG]${resetColor} Parallel mode: per-record details are written to the log\n"
    fi
    
    # Process each computer in parallel
    for identifier in "${identifiers[@]}"; do
        (( counter++ ))
        
        # Wait if we've reached the max parallel jobs
        waitForAvailableJobSlot "${maxParallelJobs}"
        
        local progressPercent=$((counter * 100 / totalRecords))
        printf "${blue}[ ${counter}/${totalRecords} (${progressPercent}%%) ]${resetColor} Processing Jamf Pro Computer ID: ${identifier} …\n"
        
        # Launch background job with its own temp files
        tempCsvFile="${tempDir}/result_${counter}.csv"
        tempLogFile="${tempDir}/log_${counter}.txt"

        (
            scriptLog="${tempLogFile}"
            processComputer "${identifier}" "${counter}" "${totalRecords}" "${tempCsvFile}"
        ) > "${tempLogFile}" 2>&1 &
        
        jobPids+=("$!")
        
        if [[ "${debugMode}" == "true" ]]; then
            debug "Launched background job ${counter} (PID: $!) for identifier: ${identifier}"
        fi
    done
    
    # Wait for all remaining jobs to complete
    info "Waiting for all parallel jobs to complete …"
    waitForAllJobPids
    
    # Parallel diagnostics (before merge)
    resultFileCount=$(find "${tempDir}" -maxdepth 1 -name 'result_*.csv' 2>/dev/null | wc -l | tr -d ' ')
    logFileCount=$(find "${tempDir}" -maxdepth 1 -name 'log_*.txt' 2>/dev/null | wc -l | tr -d ' ')
    info "Parallel diagnostics: total=${totalRecords}, maxJobs=${maxParallelJobs}, resultFiles=${resultFileCount}, logFiles=${logFileCount}"
    if [[ "${debugMode}" == "true" ]]; then
        printf "${cyan}[DEBUG]${resetColor} Parallel diagnostics: total=${totalRecords}, maxJobs=${maxParallelJobs}, resultFiles=${resultFileCount}, logFiles=${logFileCount}\n"
    fi
    if [[ "${resultFileCount}" != "${totalRecords}" ]]; then
        warning "Parallel diagnostics: expected ${totalRecords} result files; found ${resultFileCount}"
        if [[ "${debugMode}" == "true" ]]; then
            printf "${yellow}⚠${resetColor} Parallel diagnostics: expected ${totalRecords} result files; found ${resultFileCount}\n"
        fi
    fi
    
    info "All parallel jobs completed. Merging results …"
    
    # Merge CSV files
    for ((i=1; i<=totalRecords; i++)); do
        tempCsvFile="${tempDir}/result_${i}.csv"
        if [[ -f "${tempCsvFile}" ]]; then
            cat "${tempCsvFile}" >> "${csvOutput}"
        fi
    done
    
    # Merge per-job log files in order
    for ((i=1; i<=totalRecords; i++)); do
        tempLogFile="${tempDir}/log_${i}.txt"
        if [[ -f "${tempLogFile}" ]]; then
            /usr/bin/sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' "${tempLogFile}" >> "${scriptLog}"
            rm "${tempLogFile}"
        fi
    done
    
    parallelElapsed=$((SECONDS - parallelStartTime))
    parallelElapsedFormatted=$(printf '%dh:%dm:%ds' $((parallelElapsed/3600)) $((parallelElapsed%3600/60)) $((parallelElapsed%60)))
    info "Results merged successfully (parallel elapsed: ${parallelElapsedFormatted})"
    if [[ "${debugMode}" == "true" ]]; then
        printf "${cyan}[DEBUG]${resetColor} Parallel elapsed time: ${parallelElapsedFormatted}\n"
    fi

else
    
    ################################################################################################
    # SEQUENTIAL PROCESSING MODE
    ################################################################################################
    
    # Process each line in the CSV as a Jamf Pro Computer ID
    while IFS= read -r identifier; do
        
        # Strip CR and BOM (in case of UTF-8 BOM in the file)
        identifier=$(printf "%s" "${identifier}" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')
        
        # Skip blank lines
        if [[ -z "${identifier}" ]]; then
            continue
        fi
        
        (( counter++ ))
        
        # Process computer and write directly to main CSV
        processComputer "${identifier}" "${counter}" "${filenameNumberOfLines}" "${csvOutput}"
        
    done < "${processedFilename}"
    
fi


####################################################################################################
#
# Calculate Statistics from CSV
#
####################################################################################################

info "Calculating statistics from results …"

# Count various conditions from the CSV (skip header line)
if command -v ruby >/dev/null 2>&1; then
    statsResults=$(/usr/bin/ruby -rcsv -e '
csv_path = ARGV[0]

counts = {
  ddm_enabled: 0,
  ddm_disabled: 0,
  failed_blueprints: 0,
  pending_updates: 0,
  api_errors: 0,
  not_found: 0
}

CSV.foreach(csv_path, headers: true) do |row|
  ddm = row["DDM Enabled"].to_s
  if ddm == "true"
    counts[:ddm_enabled] += 1
  elsif ddm == "false" || ddm == "DDM Disabled"
    counts[:ddm_disabled] += 1
  end

  failed = row["Failed Blueprints"].to_s
  if !failed.empty? && failed != "None" && failed != "DDM Disabled" && failed != "No status items" && failed != "API Error"
    counts[:failed_blueprints] += 1
  end

  pending = row["Pending Updates"].to_s
  if !pending.empty? && pending != "None" && pending != "DDM Disabled" && pending != "No status items" && pending != "API Error"
    counts[:pending_updates] += 1
  end

  if row.fields.any? { |v| v.to_s.include?("API Error") }
    counts[:api_errors] += 1
  end

  if row.fields.any? { |v| v.to_s == "Not Found" }
    counts[:not_found] += 1
  end
end

puts [
  counts[:ddm_enabled],
  counts[:ddm_disabled],
  counts[:failed_blueprints],
  counts[:pending_updates],
  counts[:api_errors],
  counts[:not_found]
].join("|")
' "${csvOutput}")
    
    IFS='|' read -r ddmEnabledCount ddmDisabledCount failedBlueprintsCount pendingUpdatesCount errorCount notFoundCount <<< "${statsResults}"
else
    warning "Ruby not found; statistics may be inaccurate"
    ddmEnabledCount=0
    ddmDisabledCount=0
    failedBlueprintsCount=0
    pendingUpdatesCount=0
    errorCount=0
    notFoundCount=0
fi

# Ensure counts are valid numbers
ddmEnabledCount=${ddmEnabledCount:-0}
ddmDisabledCount=${ddmDisabledCount:-0}
failedBlueprintsCount=${failedBlueprintsCount:-0}
pendingUpdatesCount=${pendingUpdatesCount:-0}
errorCount=${errorCount:-0}
notFoundCount=${notFoundCount:-0}

if [[ "${debugMode}" == "true" ]]; then
    debug "Statistics calculated:"
    debug "  DDM Enabled: ${ddmEnabledCount}"
    debug "  DDM Disabled: ${ddmDisabledCount}"
    debug "  Failed Blueprints: ${failedBlueprintsCount}"
    debug "  Pending Updates: ${pendingUpdatesCount}"
    debug "  API Errors: ${errorCount}"
    debug "  Not Found: ${notFoundCount}"
fi



####################################################################################################
#
# Cleanup and Exit
#
####################################################################################################

printf "${dividerLine}"
printf "\n###\n"
printf "# Complete\n"
printf "###\n"
printf "\n"

info "\n\n\nProcessing complete!"
info "Processed ${counter} records."
info "CSV output saved to: ${csvOutput}"
info "CSV rows: ${counter} (extracted IDs: ${filenameNumberOfLines:-0})"

printf "${green}✓${resetColor} Processing complete!\n"
printf "${green}✓${resetColor} Processed ${counter} records\n"
if [[ -n "${filenameNumberOfLines}" ]]; then
    printf "${cyan}CSV rows:${resetColor} ${counter} (extracted IDs: ${filenameNumberOfLines})\n"
fi

# Display summary statistics
printf "${cyan}\nSummary Statistics:${resetColor}\n"
printf "  • DDM Enabled: ${ddmEnabledCount}\n"
printf "  • DDM Disabled: ${ddmDisabledCount}\n"
printf "  • Computers with Failed Blueprints: ${failedBlueprintsCount}\n"
printf "  • Computers with Pending Updates: ${pendingUpdatesCount}\n"
printf "  • API Errors: ${errorCount}\n"
printf "  • Not Found: ${notFoundCount}\n"
printf "  • Total Elapsed Time: $(printf '%dh:%dm:%ds' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))\n\n"

info "\nSummary Statistics:"
info "  DDM Enabled: ${ddmEnabledCount}"
info "  DDM Disabled: ${ddmDisabledCount}"
info "  Computers with Failed Blueprints: ${failedBlueprintsCount}"
info "  Computers with Pending Updates: ${pendingUpdatesCount}"
info "  API Errors: ${errorCount}"
info "  Not Found: ${notFoundCount}"
info "  CSV rows: ${counter} (extracted IDs: ${filenameNumberOfLines:-0})"
info "  Total Elapsed Time: $(printf '%dh:%dm:%ds' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"

printf "${green}✓${resetColor} CSV output saved to: ${csvOutput}\n\n"

# Invalidate Bearer Token
invalidateBearerToken

# Clean up temporary file if created
if [[ "${processedFilename}" != "${filename}" ]] && [[ -f "${processedFilename}" ]]; then
    if [[ "${debugMode}" == "true" ]]; then
        debug "Removing temporary file: ${processedFilename}"
    fi
    rm -f "${processedFilename}"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Cleaned up temporary file: ${processedFilename}"
    fi
fi

# Open log and CSV files (single lookup mode exits early, so this is only for batch mode)
if [[ "${noOpen}" == "true" ]]; then
    info "Skipping auto-open of log and CSV files (--no-open specified)"
    printf "Skipping auto-open of log and CSV files (--no-open specified)\n\n"
else
    info "\n\nOpening log and CSV files …\n\n"
    printf "Opening log and CSV files …\n\n"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Opening log file: ${scriptLog}"
        debug "Opening CSV file: ${csvOutput}"
    fi
    open "${scriptLog}" >/dev/null 2>&1 &!
    open "${csvOutput}" >/dev/null 2>&1 &!
fi

printf "${dividerLine}\n\n"

exit 0
