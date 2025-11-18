#!/bin/zsh

# Author: Bart Reardon
# Date: 2023-11-23
# https://github.com/bartreardon/macscripts/blob/master/create_self_extracting_script.sh
#
# Updated by: Dan K. Snelson
# For DDM OS Reminder
# Date: 11-Nov-2025
#
# Script for creating a self-extracting base64 encoded file
# Automatically uses the newest ddmOSReminder.Assembled.* file
# in the current directory.

SCRIPT_NAME=$(basename "$0")
datestamp=$( date '+%Y-%m-%d-%H%M%S' )

echo "🔍 Searching for the newest ddmOSReminder.Assembled.* file..."

# Find the newest matching file in the current directory
latest_file=$(ls -t ddmOSReminder.Assembled.* 2>/dev/null | head -n 1)

# Validate presence
if [[ -z "$latest_file" ]]; then
    echo "❌ Error: No file matching 'ddmOSReminder.Assembled.*' found in the current directory."
    exit 1
fi

echo "📦 Found: ${latest_file}"

# Derive output file path
output_file="./${latest_file}_self-extracting-${datestamp}.sh"

# Encode file to base64
echo "⚙️  Encoding '${latest_file}' ..."
base64_string=$(base64 -i "${latest_file}")

# Create the self-extracting script
cat <<EOF > "${output_file}"
#!/bin/sh
base64_string='$base64_string'
target_path="/var/tmp/${latest_file}"
echo "\$base64_string" | base64 -d > "\${target_path}"
echo "File '\${target_path}' has been created."
chmod u+x "\${target_path}"
zsh "\${target_path}"
EOF

chmod u+x "${output_file}"

echo ""
echo "✅ Self-extracting script created:"
echo "   ${output_file}"
echo ""
echo "When run, it will extract to /var/tmp/${latest_file} and execute automatically."
