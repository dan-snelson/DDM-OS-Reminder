#!/bin/zsh
#
# Author: Bart Reardon
# Date: 2023-11-23
# https://github.com/bartreardon/macscripts/blob/master/create_self_extracting_script.sh
#
# Updated by: Dan K. Snelson
# For DDM OS Reminder v2.0.0+
# Version: 2.4.0
# Date: 02-Oct-2026
#
# Creates a self-extracting, base64-encoded shell script from
# the newest "ddm-os-reminder-*.zsh" file found in the
# Artifacts/ folder (one level up from this script's location).

set -e
setopt +o nomatch  # prevent "no matches found" errors
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARTIFACTS_DIR="${SCRIPT_DIR}/../Artifacts"

SCRIPT_NAME=$(basename "$0")
datestamp=$(date '+%Y-%m-%d-%H%M%S')

echo "🔍 Searching for the newest ddm-os-reminder-*.zsh file in ${ARTIFACTS_DIR}..."

# Find the newest assembled file in the Artifacts directory
latest_file=$(ls -t "${ARTIFACTS_DIR}"/ddm-os-reminder-*.zsh(N) 2>/dev/null | head -n 1)

# Validate presence
if [[ -z "$latest_file" ]]; then
  echo "❌ Error: No file matching 'ddm-os-reminder-*.zsh' found in ${ARTIFACTS_DIR}"
  exit 1
fi

latest_filename="$(basename "${latest_file}")"
echo "📦 Found: ${latest_filename}"

# Derive output file path (write to Artifacts directory)
output_file="${ARTIFACTS_DIR}/${latest_filename%.zsh}_self-extracting-${datestamp}.sh"

# Encode file to base64
echo "⚙️  Encoding '${latest_filename}' ..."
base64_string=$(base64 -i "${latest_file}")

# Create the self-extracting script
cat <<EOF > "${output_file}"
#!/bin/sh
# Auto-generated self-extracting script created on ${datestamp}
# Extracts to a private /var/tmp directory, executes the assembled DDM OS Reminder payload
# with the original MDM script parameters, and removes the payload on exit

base64_string='${base64_string}'
target_dir=\$(/usr/bin/mktemp -d "/var/tmp/ddm-os-reminder.XXXXXX") || exit 1
trap 'rm -rf "\${target_dir}"' EXIT
target_path="\${target_dir}/${latest_filename}"

echo "📦 Extracting to \${target_path}..."
echo "\$base64_string" | base64 -d > "\${target_path}" || exit 1

echo "🛠️  Setting executable permissions..."
chmod 700 "\${target_path}" || exit 1

echo "🚀 Executing DDM OS Reminder..."
zsh "\${target_path}" "\$@"
exit \$?
EOF

chmod u+x "${output_file}"

echo ""
echo "✅ Self-extracting script created successfully!"
echo "   ${output_file}"
echo ""
echo "When run, it will extract to a private /var/tmp/ddm-os-reminder.XXXXXX directory, execute ${latest_filename} with the MDM script parameters, and remove it."
