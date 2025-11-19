# DDM OS Reminder

## Resources

1. [Assemble DDM OS Reminder](#1-assemble-ddm-os-reminder)
2. [Create Self-extracting Script](#2-create-self-extracting-script)
3. [Extension Attributes](#3-extension-attributes)

---

### 1. Assemble DDM OS Reminder

The [`assembleDDMOSReminder.zsh`](assembleDDMOSReminder.zsh) script creates a combinded, deployable version of the customizations you made to:
- [`DDM-OS-Reminder End-user Message.zsh`](../DDM-OS-Reminder%20End-user%20Message.zsh)
- [`ddmOSReminder.zsh`](../ddmOSReminder.zsh)


**1.1.** Create an assembled script by first changing to the **DDM-OS-Reminder > Resources** directory:
```zsh
cd DDM-OS-Reminder/Resources
```
**1.2.** Next, execute the assembly script:
```zsh
zsh assembleDDMOSReminder.zsh
```

**1.3.** Last, you'll deploy the resulting `ddmOSReminder.Assembled.YYYY-MM-DD-HHMMSS.zsh` script to your Macs via your MDM of choice (or, see [2. Create Self-extracting Script](#2-create-self-extracting-script) below.)

---

### 2. Create Self-extracting Script

With some MDMs, it's easier to deploy a self-extracting script.

After [assembling the script](#1-assemble-ddm-os-reminder), create a self-extracting version using the provided [`createSelfExtracting.zsh`](createSelfExtracting.zsh) script.

**2.1.** Change to the **DDM-OS-Reminder > Resources** directory:
```zsh
cd DDM-OS-Reminder/Resources
```

**2.2.** Then, execute the self-extracting creation script (which will automatically encode the most recently created assembled script):
```zsh
zsh createSelfExtracting.zsh
```

**2.3.** You'll deploy the resulting `ddmOSReminder.Assembled.YYYY-MM-DD-HHMMSS.zsh_self-extracting-YYYY-MM-DD-HHMMSS.sh` script to your Macs via your MDM of choice.

---

### 3. Extension Attributes

While the following Extension Attributes were created for and tested on Jamf Pro, they most likely can be adapted to other MDMs. (For adaptation assistance, help is available on the [Mac Admins Slack](https://www.macadmins.org/) [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel, or you can open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).)

**3.1.** [JamfEA-DDM-OS-Reminder-User-Clicks.zsh](JamfEA-DDM-OS-Reminder-User-Clicks.zsh): Reports the user's button clicks for the DDM OS Reminder message.
```
2025-10-23 02:53:37 dan clicked Remind Me Later
2025-10-23 02:55:28 dan clicked Open Software Update
2025-10-23 03:01:11 dan clicked Remind Me Later
2025-10-23 03:11:32 dan clicked Remind Me Later
2025-10-23 03:48:27 dan clicked KB0054571
```

**3.2.** [JamfEA-Pending_OS_Update_Date.zsh](JamfEA-Pending_OS_Update_Date.zsh): Reports the date of a pending DDM-enforced macOS update.
```
2025-10-28 12:00:00
```

**3.3.** [JamfEA-Pending_OS_Update_Version.zsh](JamfEA-Pending_OS_Update_Version.zsh): Reports the version of a pending DDM-enforced macOS update.
```
26.1
```

**3.4.** [JamfEA-DDM_Executed_OS_Update_Date.zsh](JamfEA-DDM_Executed_OS_Update_Date.zsh): Reports the date when the DDM-enforced macOS update was executed.
```
Thu Nov 13 08:59:56 2025
```