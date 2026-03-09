#!/bin/zsh

# Extension Attribute: Volume Owners
# Returns all users who are Volume Owners

# Check if we're on macOS 10.13+ (APFS required)
osVersion=$(/usr/bin/sw_vers -productVersion)
osMajorVersion=$(echo "${osVersion}" | /usr/bin/awk -F '.' '{print $1}')

if [[ "${osMajorVersion}" -lt 10 ]] || [[ "${osMajorVersion}" -eq 10 && $(echo "${osVersion}" | /usr/bin/awk -F '.' '{print $2}') -lt 13 ]]; then
    echo "<result>N/A (Pre-APFS)</result>"
    exit 0
fi

# Get list of Volume Owner UUIDs
volumeOwners=$(/usr/sbin/diskutil apfs listUsers / 2>/dev/null | /usr/bin/awk '/\+-- [0-9A-Fa-f-]+$/ {print $2}')

if [[ -z "${volumeOwners}" ]]; then
    echo "<result>Unable to determine</result>"
    exit 0
fi

# Array to store Volume Owner usernames
volumeOwnerUsers=()

# Resolve each APFS Volume Owner UUID to a local username
for ownerUUID in ${(f)volumeOwners}; do
    ownerUser=$(/usr/bin/dscl . -search /Users GeneratedUID "${ownerUUID}" 2>/dev/null | /usr/bin/awk 'NR==1 {print $1}')

    if [[ -n "${ownerUser}" ]] && (( ${volumeOwnerUsers[(Ie)${ownerUser}]} == 0 )); then
        volumeOwnerUsers+=("${ownerUser}")
    fi
done

# Output results
if [[ ${#volumeOwnerUsers[@]} -eq 0 ]]; then
    echo "<result>No Volume Owners</result>"
else
    # Join array elements with commas
    echo "<result>${(j:,:)volumeOwnerUsers}</result>"
fi

exit 0
