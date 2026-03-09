#!/bin/zsh

# Extension Attribute to determine users' SecureToken status (all local users)

osVersion=$(/usr/bin/sw_vers -productVersion)
osMajorVersion=${osVersion%%.*}
osMinorVersion=${${osVersion#*.}%%.*}

typeset -a secureTokenUsers

if (( osMajorVersion > 10 || (osMajorVersion == 10 && osMinorVersion >= 13) )); then

  while IFS= read -r eachUser; do
    tokenValue=$(/usr/sbin/sysadminctl -secureTokenStatus "${eachUser}" 2>&1)

    if [[ "${tokenValue}" == *"ENABLED"* ]]; then
      secureTokenUsers+=("${eachUser}")
    fi
  done < <(/usr/bin/dscl . -list /Users)

  if (( ${#secureTokenUsers[@]} == 0 )); then
    echo "<result>No Users</result>"
  else
    echo "<result>${(j:,:)secureTokenUsers}</result>"
  fi

else
  echo "<result>N/A (macOS ${osVersion})</result>"
fi

exit 0