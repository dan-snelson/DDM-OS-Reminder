---
name: Bug Report
about: Submit a bug report for DDM OS Reminder (after using the snippet below and having reviewed open swiftDialog issues)
title: 'Bug Report: [short description]'
labels: bug
assignees: 'dan-snelson'

---

> Before submitting a bug report, please [download a fresh copy of the `main` branch](https://github.com/dan-snelson/DDM-OS-Reminder/archive/main.zip) and confirm you can replicate the unexpected behavior. (You're also invited to discuss via the [Mac Admins Slack](https://www.macadmins.org/), [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) Channel.)
> 
> If you’re able to replicate the unexpected behavior on-demand, please complete the remainder of this template to aid in troubleshooting:
> 
> 1. In a **new**, _elevated_ Terminal window, execute the following command, substituting your organization's **Reverse Domain Name Notation**:
```zsh
zsh -c 'PS4=" → "; zsh -x "$1"' -- /Library/Management/org.churchofjesuschrist/dor.zsh
```
> 2. After the script has completed and the failure has occurred, while still in Terminal, select: **Shell > Export Text As…** to save the output to a text file
> 3. Attach the sanitized output file to your issue report
> 4. Please also provide the output of the following command, substituting your organization's **Reverse Domain Name Notation**:
```zsh
plutil -p /Library/LaunchDaemons/org.churchofjesuschrist.dor.plist
```
> 
> 
> **Optional:** Review [open swiftDialog issues](https://github.com/swiftDialog/swiftDialog/issues).

---

**Describe the Bug**
A clear, concise description of the bug.

**To Reproduce**
 - Please describe how the script was executed (i.e., via macOS Terminal, via an MDM policy, etc.).
 
**Expected Behavior**
A clear, concise description of what you expected to happen.

**Code / Log Output**
Please include both your client-side `scriptLog` and `/var/log/install.log` as a compressed archive (i.e., a `.zip` or `.tar.gz` file). If pasting output, please use a code block — triple backticks — at the start and end.

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Environment (please complete the following information):**
 - OS version (i.e., 26.2)
 - swiftDialog version (i.e., 3.0.0)
 - Script version (i.e., 2.5.0b1) - please upgrade to the [latest version](https://github.com/dan-snelson/DDM-OS-Reminder/releases) before submitting a bug report.

**Additional context**
Add any other context about the problem here.
