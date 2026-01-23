#!/bin/zsh --no-rcs
# shellcheck shell=bash

####################################################################################################
#
# Jamf-getDDMstatusFromCSV.zsh
#
# https://snelson.us
#
# Inspired by:
#   - @ScottEKendall
#
#####################################################################################################
#
# Usage:
#   Method 1 - With all parameters:
#     zsh script.zsh "https://yourserver.jamfcloud.com" "apiUser" "apiPassword" "computers.csv"
#
#   Method 2 - With lane selection:
#     zsh script.zsh --lane
#     (Will prompt to select Development, Stage, or Production environment)
#
#   Method 3 - Interactive mode (will prompt for missing parameters):
#     zsh script.zsh
#
#   Optional Flags:
#     --help      Display help information
#     --lane      Prompt for lane selection (Dev/Stage/Prod)
#     --debug     Enable debug mode with verbose logging
#
####################################################################################################
#
# HISTORY
#
# Version 0.0.1, 22-Jan-2026, Dan K. Snelson (@dan-snelson)
# - Original version
#
# Version 0.0.2, 22-Jan-2026, Dan K. Snelson (@dan-snelson)
# - Integrated features from policy-editor-lite-2.0.3.bash:
#   • Added lane selection function for Development/Stage/Production environments
#   • Added interactive prompts for missing API credentials (URL, Username, Password)
#   • Added interactive prompt for missing CSV filename
#   • Added color-coded output for better visibility
#   • Added --help flag with usage instructions
#   • Added --lane flag for lane selection
#   • Added --debug flag for enhanced debugging
#   • Enhanced logging with Mac Health Check-style logging functions
#   • Improved user experience with step-by-step progress indicators
#   • Help displays automatically when no parameters are provided
#
# Version 0.0.3, 22-Jan-2026, Dan K. Snelson (@dan-snelson)
# - Enhanced token refresh mechanism:
#   • Added fallback to getBearerToken if keep-alive refresh fails
#   • Improved error handling in token refresh scenarios
#   • Better handling of completely expired tokens during long-running operations
#
# Version 0.0.4, 23-Jan-2026, Dan K. Snelson (@dan-snelson)
# - Updated usage instructions (removed redundant Method 4)
# - Masked credentials in debug logs for improved security
# - Added CSV format validation (single or multi-column with "JSS Computer ID" header)
# - Enhanced multi-column CSV support for Jamf Pro exports
# - Fixed zsh array syntax and multibyte character handling (LC_ALL=C)
# - Standardized date format to YYYY-MM-DD-HHMMSS
# - Standardized DEBUG format to [DEBUG] throughout
# - Added comprehensive DEBUG logging for authentication, CSV processing, API calls, and DDM parsing
# - Fixed formatting consistency (single line return after step headers)
# - Added --output-dir flag to specify custom output directory
# - Added CSV encoding validation with warnings for unusual encodings
# - Added retry logic with exponential backoff for API failures
# - Enhanced CSV validation error messages to show what was found vs. expected
# - Added trap to cleanup temporary files on interrupt/exit
# - Added summary statistics showing DDM enabled/disabled, failed blueprints, pending updates, errors, not found
# - Improved progress tracking with elapsed time display for each computer
# - Optimized log format for improved readability (compact prefix)
#
# Version 0.0.5, 23-Jan-2026, Dan K. Snelson (@dan-snelson)
# - Added ability to lookup a single Serial Number via command-line argument
#
####################################################################################################



####################################################################################################
#
# Global Variables
#
####################################################################################################

export PATH=/usr/bin:/bin:/usr/sbin:/sbin

# Script Version
scriptVersion="0.0.5"

# Script Name (for help display)
scriptName=$(basename "${0}")

# Client-side Log (will be updated after outputDir is set)
scriptLog=""

# CSV Output (will be updated after outputDir is set)
csvOutput=""

# Divider Line
dividerLine="\n--------------------------------------------------------------------------------------------------------|\n"

# Any Colour You Like
red=$'\e[1;31m'
green=$'\e[1;32m'
yellow=$'\e[1;33m'
blue=$'\e[1;34m'
cyan=$'\e[1;36m'
resetColor=$'\e[0m'



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Script Parameters
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

# Initialize variables
apiUrl=""
apiUser=""
apiPassword=""
filename=""
outputDir="$HOME/Desktop"           # Default output directory

# Debug Mode [ true | false ]
debugMode="false"                    # Set to "true" to enable debug logging

# Summary Statistics Counters
ddmEnabledCount=0
ddmDisabledCount=0
failedBlueprintsCount=0
pendingUpdatesCount=0
errorCount=0
notFoundCount=0

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
}

# Set trap to cleanup on exit or interrupt
trap cleanup EXIT INT TERM



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Client-side Logging
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function updateScriptLog() {
    echo "${organizationScriptName} ($scriptVersion): $( date +%Y-%m-%d\ %H:%M:%S ) - ${1}" >> "${scriptLog}"
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

    Usage:
    zsh ${scriptName} [apiUrl] [apiUser] [apiPassword] [csvFilename] [--lane] [--debug] [--help]
    zsh ${scriptName} --serial SERIALNUMBER [--lane] [--debug]

    Method 1 - With all parameters:
        zsh ${scriptName} \"https://yourserver.jamfcloud.com\" \"apiUser\" \"apiPassword\" \"computers.csv\"

    Method 2 - With lane selection (interactive):
        zsh ${scriptName} --lane
        (Will prompt to select Development, Stage, or Production environment)

    Method 3 - With direct lane specification:
        zsh ${scriptName} --lane stage
        zsh ${scriptName} --lane dev
        zsh ${scriptName} --lane prod

    Method 4 - Interactive mode (will prompt for missing parameters):
        zsh ${scriptName}

    Method 5 - Single Serial Number lookup:
        zsh ${scriptName} --serial C02ABC123DEF
        zsh ${scriptName} -s C02ABC123DEF --lane stage

    Optional Flags:
        --serial, -s SN       Look up a single computer by Serial Number (terminal output only)
        --lane, -l [LANE]     Select lane: dev/development, stage, prod/production (prompts if omitted)
        --debug, -d           Enable debug mode with verbose logging
        --output-dir PATH     Specify output directory (default: ~/Desktop)
        --help, -h            Display this help information

    Examples:
        zsh ${scriptName} https://yourserver.jamfcloud.com apiUser apiPassword computers.csv
        zsh ${scriptName} --serial C02ABC123DEF --lane stage
        zsh ${scriptName} -s C02ABC123DEF -l prod -d
        zsh ${scriptName} -l stage
        zsh ${scriptName} --lane
        zsh ${scriptName} -h
        zsh ${scriptName} --debug

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
            
            apiUrl=$( /usr/bin/defaults read "/Library/Preferences/com.jamfsoftware.jamf.plist" jss_url 2>&1 | sed 's|/$||' )
            
            echo "
The API URL has been read from the Jamf preferences.

Use this URL? ${apiUrl}

[y] Yes - Use the URL presented above
[n] No - Enter the API URL at the next prompt
[x] Exit"

            printf "\n> "
            read -k 1 urlResponse
            printf "\n"
            info "Use this URL: ${apiUrl}? ${urlResponse}"

            case "${urlResponse}" in

                y|Y)
                    info "Using URL from JAMF plist: ${apiUrl}"
                    printf "\n\n${green}✓${resetColor} Using URL from JAMF plist: ${apiUrl}\n"
                    ;;

                n|N)
                    apiUrl=""
                    printf "\nPlease enter the API URL (e.g., https://yourserver.jamfcloud.com): "
                    read apiUrl
                    printf "\n"
                    if [[ "${debugMode}" == "true" ]]; then
                        debug "Raw URL input: ${apiUrl}"
                    fi
                    apiUrl=$( echo "${apiUrl}" | sed 's|/$||' )
                    if [[ "${debugMode}" == "true" ]]; then
                        debug "URL after trailing slash removal: ${apiUrl}"
                    fi
                    info "User entered API URL: ${apiUrl}"
                    printf "${green}✓${resetColor} API URL set to: ${apiUrl}\n"
                    ;;

                x|X)
                    quitOut "Exiting. Goodbye!"
                    printf "\n\nExiting. Goodbye!\n\n"
                    exit 0
                    ;;

                *)
                    error "Did not recognize response: ${urlResponse}; exiting."
                    printf "\n${red}ERROR:${resetColor} Did not recognize response: ${urlResponse}; exiting.\n\n"
                    exit 1
                    ;;

            esac

        else

            info "No API URL is specified in the script; prompt user ..."

            echo "
No API URL is specified in the script. Enter it now?

[y] Yes - Enter the URL at the next prompt
[n] No - Exit the script"

            printf "\n> "
            read -k 1 urlResponse
            printf "\n"

            case "${urlResponse}" in

                y|Y)
                    printf "\nPlease enter the API URL (e.g., https://yourserver.jamfcloud.com): "
                    read apiUrl
                    printf "\n"
                    apiUrl=$( echo "${apiUrl}" | sed 's|/$||' )
                    info "User entered API URL: ${apiUrl}"
                    printf "${green}✓${resetColor} API URL set to: ${apiUrl}\n"
                    ;;

                n|N)
                    quitOut "Exiting. Goodbye!"
                    printf "\n\nExiting. Goodbye!\n\n"
                    exit 0
                    ;;

                *)
                    error "Did not recognize response: ${urlResponse}; exiting."
                    printf "\n${red}ERROR:${resetColor} Did not recognize response: ${urlResponse}; exiting.\n\n"
                    exit 1
                    ;;

            esac
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
        notice "No API Username (or Client ID) has been supplied. Enter it now?"
        printf "\n\nNo API Username (or Client ID) has been supplied. Enter it now?

[y] Yes - Enter the Username (or Client ID) at the next prompt
[n] No - Exit
"

        printf "\n> "
        read -k 1 apiUsernameResponse
        printf "\n"

        case "${apiUsernameResponse}" in

            y|Y)
                printf "\nPlease enter the API Username (or Client ID): "
                read apiUser
                printf "\n"
                info "User entered API Username (or Client ID): ${apiUser}"
                printf "${green}✓${resetColor} API Username (or Client ID) set\n"
                ;;

            n|N)
                quitOut "Exiting. Goodbye!"
                printf "\n\nExiting. Goodbye!\n\n"
                exit 0
                ;;

            *)
                error "Did not recognize response: ${apiUsernameResponse}; exiting."
                printf "\n${red}ERROR:${resetColor} Did not recognize response: ${apiUsernameResponse}; exiting.\n\n"
                exit 1
                ;;

        esac

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
        notice "No API Password (or Client Secret) has been supplied. Enter it now?"
        printf "\n\nNo API Password (or Client Secret) has been supplied. Enter it now?

[y] Yes - Enter the password (or Client Secret) at the next prompt
[n] No - Exit
"

        printf "\n> "
        read -k 1 apiPasswordEntryResponse
        printf "\n"

        case "${apiPasswordEntryResponse}" in

            y|Y)
                printf "\nPlease enter the API Password (or Client Secret): "
                read -s apiPassword
                printf "\n"
                info "User entered API Password (or Client Secret)"
                printf "${green}✓${resetColor} API Password (or Client Secret) set\n"
                ;;

            n|N)
                quitOut "Exiting. Goodbye!"
                printf "\n\nExiting. Goodbye!\n\n"
                exit 0
                ;;

            *)
                error "Did not recognize response: ${apiPasswordEntryResponse}; exiting."
                printf "\n${red}ERROR:${resetColor} Did not recognize response: ${apiPasswordEntryResponse}; exiting.\n\n"
                exit 1
                ;;

        esac

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
        info "No CSV filename has been supplied. Enter it now?"
        printf "\n\nNo CSV filename has been supplied. Enter it now?

[y] Yes - Enter the filename at the next prompt
[n] No - Exit
"

        printf "\n> "
        read -k 1 csvFilenameResponse
        printf "\n"

        case "${csvFilenameResponse}" in

            y|Y)
                printf "\nPlease enter the CSV filename (or drag-and-drop the file): "
                read filename
                printf "\n"
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Raw filename input: ${filename}"
                fi
                # Remove quotes if user drag-and-dropped
                filename="${filename//\'/}"
                filename="${filename//\"/}"
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Filename after quote removal: ${filename}"
                fi
                info "User entered CSV filename: ${filename}"
                ;;

            n|N)
                quitOut "Exiting. Goodbye!"
                printf "\n\nExiting. Goodbye!\n\n"
                exit 0
                ;;

            *)
                error "Did not recognize response: ${csvFilenameResponse}; exiting."
                printf "\n${red}ERROR:${resetColor} Did not recognize response: ${csvFilenameResponse}; exiting.\n\n"
                exit 1
                ;;

        esac

    fi

    # Verify file exists
    if [[ ! -f "${filename}" ]]; then
        error "The specified file '${filename}' does not exist."
        printf "\n${red}ERROR:${resetColor} The specified file '${filename}' does not exist.\n\n"
        exit 1
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
        die "Jamf Pro auth returned an empty response; check URL and network."
    fi

    if [[ "${debugMode}" == "true" ]]; then
        debug "Token response: ${tokenJson}"
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

    if [[ -z "${apiBearerToken}" ]] || [[ "${tokenJson}" == *"error"* ]]; then
        die "Unable to obtain Bearer Token; double-check API credentials and URL."
    fi

    info "Obtained Bearer Token; proceeding …"

    if [[ "${debugMode}" == "true" ]]; then
        local maskedToken=$(maskCredential "${apiBearerToken}")
        debug "apiBearerToken: ${maskedToken}"
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

    if [[ "${debugMode}" == "true" ]]; then
        local maskedToken=$(maskCredential "${apiBearerToken}")
        debug "Refreshed apiBearerToken: ${maskedToken}"
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
    # Replace commas with semicolons for CSV safety
    printf "%s" "${data}" | sed 's/,/;/g'
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
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function validateCsvFormat() {
    local csvFile="${1}"
    
    # Read first line to check for headers
    local firstLine=$(head -n 1 "${csvFile}" | tr -d '\r')
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "CSV first line: ${firstLine}" >&2
    fi
    
    # If first line contains commas (multi-column CSV)
    if [[ "${firstLine}" == *","* ]]; then
        # Check if it has a "JSS Computer ID" column
        if [[ "${firstLine}" == *"JSS Computer ID"* ]]; then
            info "Detected multi-column CSV with 'JSS Computer ID' header; will extract ID column" >&2
            return 0
        else
            # Multi-column but no JSS Computer ID header
            local columnCount=$(( $(echo "${firstLine}" | grep -o ',' | wc -l) + 1 ))
            local headers=$(echo "${firstLine}" | sed 's/,/, /g')
            if [[ "${debugMode}" == "true" ]]; then
                debug "Detected ${columnCount} columns without required 'JSS Computer ID' header" >&2
                debug "Found headers: ${headers}" >&2
            fi
            error "Invalid CSV format detected: File contains ${columnCount} columns without 'JSS Computer ID' header" >&2
            printf "\n${red}ERROR:${resetColor} Invalid CSV format detected\n" >&2
            printf "\n${cyan}What was found:${resetColor}" >&2
            printf "\n  • ${columnCount} columns" >&2
            printf "\n  • Headers: ${headers}" >&2
            printf "\n\n${cyan}What is required:${resetColor}" >&2
            printf "\n  • A single-column CSV with Jamf Pro Computer IDs" >&2
            printf "\n  • A multi-column CSV with a 'JSS Computer ID' header column" >&2
            printf "\n\nPlease export a valid format from Jamf Pro and try again.\n\n" >&2
            return 1
        fi
    fi
    
    # Single column format is valid
    return 0
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Extract JSS Computer ID column from CSV with headers
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function extractJssIdColumn() {
    local csvFile="${1}"
    local tempFile="${csvFile}.jssids.tmp"
    
    # Read first line to check for header
    local firstLine=$(head -n 1 "${csvFile}" | tr -d '\r')
    
    # Check if first line contains "JSS Computer ID" header
    if [[ "${firstLine}" == *"JSS Computer ID"* ]]; then
        info "Detected CSV with 'JSS Computer ID' header; extracting IDs …" >&2
        
        # Determine if this is multi-column CSV
        if [[ "${firstLine}" == *","* ]]; then
            # Multi-column CSV - find the column index for "JSS Computer ID"
            info "Multi-column CSV detected; locating 'JSS Computer ID' column …" >&2
            
            # Convert header line to array and find column index
            local columnIndex=1
            local currentIndex=1
            local -a headers
            IFS=',' read -A headers <<< "${firstLine}"
            
            for header in "${headers[@]}"; do
                # Clean up header (remove quotes and whitespace)
                header=$(echo "${header}" | sed 's/^[[:space:]]*"\{0,1\}//;s/"\{0,1\}[[:space:]]*$//')
                if [[ "${debugMode}" == "true" ]]; then
                    debug "Column ${currentIndex}: '${header}'" >&2
                fi
                if [[ "${header}" == "JSS Computer ID" ]]; then
                    columnIndex=${currentIndex}
                    info "Found 'JSS Computer ID' in column ${columnIndex}" >&2
                    break
                fi
                (( currentIndex++ ))
            done
            
            # Extract the specific column (skip header, extract column by index)
            # Set LC_ALL=C to handle multibyte characters in other columns
            if [[ "${debugMode}" == "true" ]]; then
                debug "Extracting column ${columnIndex} using awk with LC_ALL=C" >&2
            fi
            tail -n +2 "${csvFile}" | LC_ALL=C awk -F',' -v col="${columnIndex}" '{
                # Remove quotes and whitespace from the field
                gsub(/^[[:space:]]*"*|"*[[:space:]]*$/, "", $col);
                if (length($col) > 0) print $col
            }' > "${tempFile}"
            
        else
            # Single-column CSV with header - just skip the header
            tail -n +2 "${csvFile}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | awk '/./ {print; }' > "${tempFile}"
        fi
        
        if [[ $? -eq 0 ]] && [[ -f "${tempFile}" ]]; then
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
    local computerInfo
    
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
    
    # Get raw JSON and extract only the fields we need immediately
    # This avoids storing the full response with extension attributes
    rawResponse=$(
        curl -H "Authorization: Bearer ${apiBearerToken}" \
             -H "Accept: application/json" \
             -sfk \
             "${apiUrl}/api/v1/computers-inventory-detail/${computerId}?section=GENERAL&section=HARDWARE&section=OPERATING_SYSTEM" \
             -X GET 2>/dev/null
    )
    
    if [[ "${debugMode}" == "true" ]]; then
        local responseSize=${#rawResponse}
        debug "Raw API response size: ${responseSize} bytes" >&2
    fi
    
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
    
    # Not found or error
    if [[ "${debugMode}" == "true" ]]; then
        debug "Computer ID ${computerId} not found or API error" >&2
    fi
    return 1
}



# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Get computer ID by Serial Number
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

function getComputerIdBySerialNumber() {
    local serialNumber="${1}"
    local rawResponse
    local computerId
    
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
    
    # Use Modern API with filter to find computer by serial number
    rawResponse=$(
        curl -H "Authorization: Bearer ${apiBearerToken}" \
             -H "Accept: application/json" \
             -sfk \
             "${apiUrl}/api/v1/computers-inventory?section=GENERAL&page=0&page-size=1&filter=hardware.serialNumber%3D%3D%22${serialNumber}%22" \
             -X GET 2>/dev/null
    )
    
    if [[ "${debugMode}" == "true" ]]; then
        local responseSize=${#rawResponse}
        debug "Raw API response size: ${responseSize} bytes" >&2
    fi
    
    # Check if we got results
    local totalCount=$(printf "%s" "${rawResponse}" | jq -r '.totalCount // 0' 2>/dev/null)
    
    if [[ "${totalCount}" -eq 0 ]]; then
        if [[ "${debugMode}" == "true" ]]; then
            debug "No computer found with Serial Number: ${serialNumber}" >&2
        fi
        return 1
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
    
    # Not found or error
    if [[ "${debugMode}" == "true" ]]; then
        debug "Failed to resolve Serial Number ${serialNumber} to Computer ID" >&2
    fi
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
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "Calling DDM status endpoint for Management ID: ${managementId}" >&2
        debug "API endpoint: ${apiUrl}/api/v1/ddm/${managementId}/status-items" >&2
    fi
    
    ddmStatusAndCode=$(
        curl -H "Authorization: Bearer ${apiBearerToken}" \
             -H "Accept: application/json" \
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
    
    # Handle 401 with token refresh
    if [[ "${httpStatus}" == "401" ]]; then
        info "Token expired during DDM status retrieval; refreshing …" >&2
        if refreshBearerToken; then
            info "Token refreshed successfully. Retrying DDM status retrieval for Management ID ${managementId} …" >&2
            ddmStatusAndCode=$(
                curl -H "Authorization: Bearer ${apiBearerToken}" \
                     -H "Accept: application/json" \
                     -sfk -w "%{http_code}" \
                     "${apiUrl}/api/v1/ddm/${managementId}/status-items" \
                     -X GET 2>/dev/null
            )
            httpStatus="${ddmStatusAndCode: -3}"
            ddmStatus="${ddmStatusAndCode%???}"
        else
            error "Failed to refresh token during DDM status retrieval for Management ID ${managementId}" >&2
            return 1
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
    
    if [[ "${debugMode}" == "true" ]]; then
        debug "DDM status retrieval failed with HTTP ${httpStatus} for Management ID: ${managementId}" >&2
    fi
    
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

# Process flags first
while test $# -gt 0; do
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
            # Check if next argument is a valid lane name (not a flag or file)
            if [[ $# -gt 0 ]] && [[ "$1" != -* ]]; then
                case "$1" in
                    dev|development|d|D|stage|s|S|prod|production|p|P)
                        specifiedLane="$1"
            shift
                        ;;
                    *)
                        # Not a valid lane name, don't consume it
                        ;;
                esac
            fi
            ;;
        --serial|-s)
            singleLookupMode="yes"
            shift
            lookupSerialNumber="$1"
            shift
            ;;
        --output-dir)
            shift
            outputDir="$1"
            shift
            ;;
        -*)
            # Unknown flag
            shift
            ;;
        *)
            # Not a flag, stop processing
            break
            ;;
    esac
done

# Now capture remaining positional parameters (only used in CSV batch mode)
apiUrl="${1:-}"
apiUser="${2:-}"
apiPassword="${3:-}"
filename="${4:-}"

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

# Check if lane selection was requested
if [[ "${laneSelectionRequested}" == "yes" ]]; then
    if [[ -n "${specifiedLane}" ]]; then
        info "Lane selection requested with specified lane: ${specifiedLane}"
    else
        info "Lane selection requested; prompting user ..."
    fi
    laneSelection "${specifiedLane}"
    printf "\n${green}✓${resetColor} Lane credentials configured\n"
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
        
        # Validate CSV encoding
        validateCsvEncoding "${filename}"
        
        # Validate CSV format (single column only)
        if ! validateCsvFormat "${filename}"; then
            die "CSV format validation failed. Please provide a single-column CSV file."
        fi
        printf "${green}✓${resetColor} CSV format validated (single column)\n"
        
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

counter="0"

# Process each line in the CSV as a Jamf Pro Computer ID
while IFS= read -r identifier; do

    SECONDS="0"

    # Strip CR and BOM (in case of UTF-8 BOM in the file)
    identifier=$(printf "%s" "${identifier}" | tr -d '\r' | sed 's/^\xEF\xBB\xBF//')

    # Skip blank lines
    if [[ -z "${identifier}" ]]; then
        continue
    fi

    (( counter++ ))
    progressPercent=$((counter * 100 / filenameNumberOfLines))
    info "\n\n\nRecord ${counter} of ${filenameNumberOfLines} (${progressPercent}%): Identifier: ${identifier}"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Processing record ${counter}: Starting timer for identifier '${identifier}'"
    fi
    printf "${blue}[ ${counter}/${filenameNumberOfLines} (${progressPercent}%%) ]${resetColor} Processing Jamf Pro Computer ID: ${identifier} …\n"

    ################################################################################################
    # Retrieve computer information by JSS Computer ID
    ################################################################################################

    computerInfoRaw=$(getComputerById "${identifier}")
    
    if [[ $? -ne 0 ]] || [[ -z "${computerInfoRaw}" ]]; then
        error "Computer '${identifier}' not found in Jamf Pro; skipping …"
        printf "  ${red}✗${resetColor} Computer not found in Jamf Pro\n"
        # Write "Not Found" row to CSV
        echo "\"${identifier}\",\"\",\"Not Found\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"" >> "${csvOutput}"
        (( notFoundCount++ ))
        info "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"
        continue
    fi

    # Extract all fields from the retrieved computer data
    # Parse the filtered JSON with jq
    fieldData=$(printf "%s" "${computerInfoRaw}" | jq -r '[.id // "", .general.name // "", .hardware.serialNumber // "", .general.managementId // "", .general.declarativeDeviceManagementEnabled // "", .operatingSystem.version // "", .hardware.modelIdentifier // "", .general.lastContactTime // ""] | join("|")' 2>/dev/null)
    
    if [[ -z "${fieldData}" ]] || [[ "${fieldData}" == "|||||||" ]]; then
        error "Failed to parse JSON for identifier: ${identifier}"
        printf "${red}✗${resetColor} Failed to parse computer data for: ${identifier}\n\n"
        echo "\"${identifier}\",\"${apiUrl}/computers.html?id=${identifier}&o=r\",\"Parse Error\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\",\"\"" >> "${csvOutput}"
        info "Elapsed Time: $(printf '%dh:%dm:%ds\n' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))"
        continue
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
        (( ddmDisabledCount++ ))
    else
        (( ddmEnabledCount++ ))
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
    activeBlueprints=""
    failedBlueprints=""
    softwareUpdateErrors=""
    pendingUpdates=""

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
            
            # Update counters
            if [[ -n "${failedBlueprints}" ]] && [[ "${failedBlueprints}" != "None" ]] && [[ "${failedBlueprints}" != "" ]]; then
                (( failedBlueprintsCount++ ))
            fi
            if [[ -n "${pendingUpdates}" ]] && [[ "${pendingUpdates}" != "None" ]] && [[ "${pendingUpdates}" != "" ]]; then
                (( pendingUpdatesCount++ ))
            fi
            
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
            (( errorCount++ ))
        fi
        
    else
        warning "DDM is not enabled for this computer; skipping DDM status retrieval."
        activeBlueprints="DDM Disabled"
        failedBlueprints="DDM Disabled"
        softwareUpdateErrors="DDM Disabled"
        pendingUpdates="DDM Disabled"
    fi

    ################################################################################################
    # Write to CSV
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

    echo "\"${csvIdentifier}\",\"${jamfProLink}\",\"${csvComputerName}\",\"${csvSerialNumber}\",\"${csvLastContactTime}\",\"${csvCurrentOsVersion}\",\"${csvPendingUpdates}\",\"${csvModelIdentifier}\",\"${csvManagementId}\",\"${csvDdmEnabled}\",\"${csvActiveBlueprints}\",\"${csvFailedBlueprints}\",\"${csvSoftwareUpdateErrors}\"" >> "${csvOutput}"

    local recordTime=$(printf '%dh:%dm:%ds' $((SECONDS/3600)) $((SECONDS%3600/60)) $((SECONDS%60)))
    info "Elapsed Time: ${recordTime}"
    if [[ "${debugMode}" == "true" ]]; then
        debug "Record ${counter} processed in ${SECONDS} seconds"
    fi
    
    # Add visual separation between records (except after last record)
    if [[ ${counter} -lt ${filenameNumberOfLines} ]]; then
        printf "\n${blue}---${resetColor}\n\n"
    fi

done < "${processedFilename}"



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

printf "${green}✓${resetColor} Processing complete!\n"
printf "${green}✓${resetColor} Processed ${counter} records\n"

# Display summary statistics
printf "${cyan}\nSummary Statistics:${resetColor}\n"
printf "  • DDM Enabled: ${ddmEnabledCount}\n"
printf "  • DDM Disabled: ${ddmDisabledCount}\n"
printf "  • Computers with Failed Blueprints: ${failedBlueprintsCount}\n"
printf "  • Computers with Pending Updates: ${pendingUpdatesCount}\n"
printf "  • API Errors: ${errorCount}\n"
printf "  • Not Found: ${notFoundCount}\n\n"

info "\nSummary Statistics:"
info "  DDM Enabled: ${ddmEnabledCount}"
info "  DDM Disabled: ${ddmDisabledCount}"
info "  Computers with Failed Blueprints: ${failedBlueprintsCount}"
info "  Computers with Pending Updates: ${pendingUpdatesCount}"
info "  API Errors: ${errorCount}"
info "  Not Found: ${notFoundCount}"

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
info "\n\nOpening log and CSV files …\n\n"
printf "Opening log and CSV files …\n\n"
if [[ "${debugMode}" == "true" ]]; then
    debug "Opening log file: ${scriptLog}"
    debug "Opening CSV file: ${csvOutput}"
fi
open "${scriptLog}" >/dev/null 2>&1 &
open "${csvOutput}" >/dev/null 2>&1 &

printf "${dividerLine}\n\n"

exit 0
