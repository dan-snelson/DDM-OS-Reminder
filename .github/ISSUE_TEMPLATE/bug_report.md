---
name: Bug Report
about: Submit a bug report for DDM OS Reminder (after using the snippet below and having reviewed open swiftDialog issues)
title: 'Bug Report: [short description]'
labels: bug
assignees: 'dan-snelson'

---

> Before submitting a bug report, please [download a fresh copy of the `main` branch](https://github.com/dan-snelson/DDM-OS-Reminder/archive/main.zip) and confirm you can replicate the unexpected behavior.
> 
> If you're able to replicate the unexpected behavior on-demand, please complete the remainder of this template to help us troubleshoot:
> 
> 1. In new, _elevated_ Terminal window, please execute the following command, substituting your organization's **Reverse Domain Name Notation**:
```zsh
PS4='+%3l:%I → ' zsh -x /Library/Management/org.churchofjesuschrist/dor.zsh 2>&1
```
> 2. After the script has completed and the failure has occurred, while still in Terminal, select: **Shell > Export Text As…** to save the output to a text file
> 3. Attach the sanitized output file to your issue report
> 
> 
> Also, please review the [open swiftDialog issues](https://github.com/swiftDialog/swiftDialog/issues) to help determine the source of the issue.
> 
> You're also invited to discuss via the [Mac Admins Slack](https://www.macadmins.org/) (free, registration required) [#ddm-os-reminders Channel](https://slack.com/app_redirect?channel=C09LVE2NVML).

---

**Describe the bug**
A clear, concise description of the bug.

**To Reproduce**
 - Please describe how the script was executed (i.e., via macOS Terminal, via in a Jamf Pro Self Service policy, etc.).
 - Please detail any modififications.
 
**Expected behavior**
A clear, concise description of what you expected to happen.

**Code/log output**
Please supply the full command used, and if applicable, add full output from Terminal. Either upload the log, or paste the output in a code block (triple backticks at the start and end of the code block, please!).

**Screenshots**
If applicable, add screenshots to help explain your problem.

**Environment (please complete the following information):**
 - OS version (i.e., 26.2)
 - swiftDialog version (i.e., 3.0.0)
 - Script version (i.e., 2.0.0) - please upgrade to the latest version before submitting a bug report.

**Additional context**
Add any other context about the problem here.
