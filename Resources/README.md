# DDM OS Reminder

## Resources

1. [Assemble DDM OS Reminder](#1-assemble-ddm-os-reminder)
2. [Create Self-extracting Script](#2-create-self-extracting-script)
3. [Extension Attributes](#3-extension-attributes)

---

### 1. Assemble DDM OS Reminder

The [`assemble.zsh`](assemble.zsh) script creates a **combined, deployable version** of your customized scripts as:
```zsh
Resources/ddm-os-reminder-assembled-2025-11-21-074422.zs
```

**1.1.** Change to the **DDM-OS-Reminder > Resources** directory:

```zsh
cd DDM-OS-Reminder/Resources
```

**1.2.** Execute the assembly script:

```zsh
zsh assemble.zsh
```

**1.3.** The resulting assembled file will be created as:

```
ddm-os-reminder-assembled-YYYY-MM-DD-HHMMSS.zsh
```

You can deploy this file directly to your Macs using your MDM of choice,  
or proceed to [2. Create Self-extracting Script](#2-create-self-extracting-script) below.

---

### 2. Create Self-extracting Script

With some MDMs, it’s easier to deploy a **single self-extracting script** instead of multiple components.

After [assembling the script](#1-assemble-ddm-os-reminder), run the provided [`createSelfExtracting.zsh`](createSelfExtracting.zsh) script to generate a self-extracting version.

**2.1.** Change to the **DDM-OS-Reminder > Resources** directory:

```zsh
cd DDM-OS-Reminder/Resources
```

**2.2.** Execute the script (it automatically uses the most recent assembled file):

```zsh
zsh createSelfExtracting.zsh
```

**2.3.** The resulting self-extracting script will be created as:

```
ddm-os-reminder-assembled-YYYY-MM-DD-HHMMSS_self-extracting-YYYY-MM-DD-HHMMSS.sh
```

You can deploy this file to your Macs using your MDM of choice.  
When executed, it extracts the assembled payload to `/var/tmp` and runs it automatically.

---

### 3. Extension Attributes

While the following Extension Attributes were created for and tested on **Jamf Pro**, they can likely be adapted for other MDMs.  
(For adaptation help, visit the [Mac Admins Slack](https://www.macadmins.org/) `#ddm-os-reminders` channel  
or open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).)

**3.1.** [`JamfEA-DDM-OS-Reminder-User-Clicks.zsh`](JamfEA-DDM-OS-Reminder-User-Clicks.zsh)  
Reports the user’s button clicks from the DDM OS Reminder message.

```
2025-10-23 02:53:37 dan clicked Remind Me Later
2025-10-23 02:55:28 dan clicked Open Software Update
2025-10-23 03:01:11 dan clicked Remind Me Later
2025-10-23 03:11:32 dan clicked Remind Me Later
2025-10-23 03:48:27 dan clicked KB0054571
```

**3.2.** [`JamfEA-Pending_OS_Update_Date.zsh`](JamfEA-Pending_OS_Update_Date.zsh)  
Reports the date of a pending DDM-enforced macOS update.

```
2025-10-28 12:00:00
```

**3.3.** [`JamfEA-Pending_OS_Update_Version.zsh`](JamfEA-Pending_OS_Update_Version.zsh)  
Reports the version of a pending DDM-enforced macOS update.

```
26.1
```

**3.4.** [`JamfEA-DDM_Executed_OS_Update_Date.zsh`](JamfEA-DDM_Executed_OS_Update_Date.zsh)  
Reports the date when the DDM-enforced macOS update was executed.

```
Thu Nov 13 08:59:56 2025
```