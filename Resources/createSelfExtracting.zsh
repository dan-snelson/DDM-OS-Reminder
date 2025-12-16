#!/bin/zsh
#
# Author: Bart Reardon
# Date: 2023-11-23
# https://github.com/bartreardon/macscripts/blob/master/create_self_extracting_script.sh
#
# Updated by: Dan K. Snelson
# For DDM OS Reminder v2.0.0+
# Version: 2.2.0b4
# Date: 15-Dec-2025
#
# Creates a self-extracting, base64-encoded shell script from
# the newest "ddm-os-reminder-assembled-*.zsh" file found in
# the same directory as this script (typically ./Resources).

set -e
setopt +o nomatch  # prevent "no matches found" errors
cd "$(dirname "$0")"  # ensure we operate inside the Resources directory

SCRIPT_NAME=$(basename "$0")
datestamp=$(date '+%Y-%m-%d-%H%M%S')

echo "🔍 Searching for the newest ddm-os-reminder-assembled-*.zsh file..."

# Find the newest assembled file in the current directory
latest_file=$(ls -t ddm-os-reminder-*.zsh(N) | head -n 1)

# Validate presence
if [[ -z "$latest_file" ]]; then
  echo "❌ Error: No file matching 'ddm-os-reminder-assembled-*.zsh' found in $(pwd)"
  exit 1
fi

echo "📦 Found: ${latest_file}"

# Derive output file path
output_file="./${latest_file%.zsh}_self-extracting-${datestamp}.sh"

# Encode file to base64
echo "⚙️  Encoding '${latest_file}' ..."
base64_string=$(base64 -i "${latest_file}")

# Create the self-extracting script
cat <<EOF > "${output_file}"
#!/bin/sh
# Auto-generated self-extracting script created on ${datestamp}
# Extracts to /var/tmp and executes the assembled DDM OS Reminder payload

base64_string='${base64_string}'
target_path="/var/tmp/${latest_file}"

echo "📦 Extracting to \${target_path}..."
echo "\$base64_string" | base64 -d > "\${target_path}"

echo "🛠️  Setting executable permissions..."
chmod u+x "\${target_path}"

echo "🚀 Executing DDM OS Reminder..."
zsh "\${target_path}"
EOF

chmod u+x "${output_file}"

echo ""
echo "✅ Self-extracting script created successfully!"
echo "   ${output_file}"
echo ""
echo "When run, it will extract to /var/tmp/${latest_file} and execute automatically."
