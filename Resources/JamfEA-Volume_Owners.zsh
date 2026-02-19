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
volumeOwners=$(/usr/sbin/diskutil apfs listUsers / 2>/dev/null | /usr/bin/awk '/\+-- [-0-9A-F]+$/ {print $2}')

if [[ -z "$volumeOwners" ]]; then
    echo "<result>Unable to determine</result>"
    exit 0
fi

# Get all non-system users (convert to array)
AllUsers=(${(f)"$(dscl . list /Users | grep -v '^_')"})

# Array to store Volume Owner usernames
VolumeOwnerUsers=()

# Check each user
for EachUser in "${AllUsers[@]}"; do
    userUUID=$(/usr/bin/dscl . -read /Users/"$EachUser" GeneratedUID 2>/dev/null | /usr/bin/awk '{print $2}')
    
    if [[ -n "$userUUID" ]]; then
        # Check if this user's UUID is in the Volume Owner list
        if echo "$volumeOwners" | /usr/bin/grep -q "$userUUID"; then
            VolumeOwnerUsers+=("$EachUser")
        fi
    fi
done

# Output results
if [[ ${#VolumeOwnerUsers[@]} -eq 0 ]]; then
    echo "<result>No Volume Owners</result>"
else
    # Join array elements with commas
    echo "<result>${(j:,:)VolumeOwnerUsers}</result>"
fi

exit 0