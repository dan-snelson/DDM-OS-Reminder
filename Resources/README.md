# DDM OS Reminder

## Resources

1. [Assemble](#1-assemble)
2. [Create Self-extracting Script](#2-create-self-extracting-script)
3. [Create `.plist`](#3-create-plist)
4. [Extension Attributes](#4-extension-attributes)

---

### 1. Assemble

The [`assemble.zsh`](../assemble.zsh) script creates a **combined, deployable version** of your customized scripts:
- `reminderDialog.zsh`
- `launchDaemonManagement.zsh`

**1.1.** Execute the assembly script

```zsh
zsh assemble.zsh
```

The output file will be saved as:

```zsh
Resources/ddm-os-reminder-assembled-YYYY-MM-DD-HHMMSS.zsh
```

**1.2.** Deploy the assembled script

You can deploy the assembled script directly to your Macs using your MDM, or proceed to [2. Create Self-extracting Script](#2-create-self-extracting-script) below.

---

### 2. Create Self-extracting Script

With some MDMs, it’s easier to deploy a **single self-extracting script** instead of multiple components.

After [assembling the script](#1-assemble), run the provided [`createSelfExtracting.zsh`](createSelfExtracting.zsh) script to generate a self-extracting version.

**2.1.** Change to the **DDM-OS-Reminder > Resources** directory:

```zsh
cd DDM-OS-Reminder/Resources
```

**2.2.** Execute the script (it automatically uses the most recently assembled script):

```zsh
zsh createSelfExtracting.zsh
```

**2.3.** The resulting self-extracting script will be created as:

```
Resources/ddm-os-reminder-assembled-YYYY-MM-DD-HHMMSS_self-extracting-YYYY-MM-DD-HHMMSS.sh
```

**2.4.** Deploy the assembled, self-extracting script

You can deploy the assembled, self-extracting script to your Macs using your MDM of choice. When executed, it extracts the assembled payload to `/var/tmp` and executes it automatically.

---

### 3. Create `.plist` 

A sample `.plist` — [`org.churchofjesuschrist.dorm.plist`](../org.churchofjesuschrist.dorm.plist) — is provided in the main **DDM-OS-Reminder** directory, which you can directly edit in your preferred code editor.

However, if you modified `reminderDialog.zsh` and want to reflect those changes in a new `.plist`, run the provided [`createPlist.zsh`](createPlist.zsh) script.

```zsh
zsh Resources/createPlist.zsh
```

The resulting `.plist` file will be created as:

```
Resources/${reverseDomainNameNotation}.${organizationScriptName}-${datestamp}.plist"
```

Upload the resulting `.plist` to your MDM of choice, ensuring you specify the same preference domain as configured in `reminderDialog.zsh`.

Using the following example …

```zsh
# Organization's reverse domain (used for plist domains)
reverseDomainNameNotation="org.churchofjesuschrist"

# Organization's Script Name
organizationScriptName="dorm"
```

… the preference domain would be:

```
org.churchofjesuschrist.dorm
```

---

### 4. Extension Attributes

While the following Extension Attributes were created for and tested on **Jamf Pro**, they can likely be adapted for other MDMs.  
(For adaptation help, visit the [Mac Admins Slack](https://www.macadmins.org/) `#ddm-os-reminders` channel  
or open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).)

**4.1.** [`JamfEA-DDM-OS-Reminder-User-Clicks.zsh`](JamfEA-DDM-OS-Reminder-User-Clicks.zsh)  
Reports the user’s button clicks from the DDM OS Reminder message.

```
2025-12-05 02:53:37 dan clicked Remind Me Later
2025-12-05 02:55:28 dan clicked Open Software Update
2025-12-05 03:01:11 dan clicked Remind Me Later
2025-12-05 03:11:32 dan clicked Remind Me Later
2025-12-05 03:48:27 dan clicked KB0054571
```

**4.2.** [`JamfEA-Pending_OS_Update_Date.zsh`](JamfEA-Pending_OS_Update_Date.zsh)  
Reports the date of a pending DDM-enforced macOS update.

```
2025-12-16 12:00:00
```

**4.3.** [`JamfEA-Pending_OS_Update_Version.zsh`](JamfEA-Pending_OS_Update_Version.zsh)  
Reports the version of a pending DDM-enforced macOS update.

```
26.2
```

**4.4.** [`JamfEA-DDM_Executed_OS_Update_Date.zsh`](JamfEA-DDM_Executed_OS_Update_Date.zsh)  
Reports the date when the DDM-enforced macOS update was executed.

```
Thu Nov 13 08:59:56 2025
```