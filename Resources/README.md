# DDM OS Reminder

## Scripts

1. [Assemble](#1-assemble)
2. [Create Self-extracting Script](#2-create-self-extracting-script)
3. [Create `.plist`](#3-create-plist)
4. [Extension Attributes](#4-extension-attributes)

---

### 1. Assemble

The [`assemble.zsh`](../assemble.zsh) script creates **combined, deployable** artifacts of your customized scripts:
- `reminderDialog.zsh`
- `launchDaemonManagement.zsh`

**1.1.** Execute the assembly script

```zsh
zsh assemble.zsh
```

The artifacts will be saved as shown below:

```
❯ zsh assemble.zsh

===============================================================
🧩 Assemble DDM OS Reminder (2.2.0rc1)
===============================================================

Full Paths:

        Reminder Dialog: ~/DDM-OS-Reminder/reminderDialog.zsh
LaunchDaemon Management: ~/DDM-OS-Reminder/launchDaemonManagement.zsh
      Working Directory: ~/DDM-OS-Reminder
    Resources Directory: ~/DDM-OS-Reminder/Resources

🔍 Checking Reverse Domain Name Notation …

    Reminder Dialog (reminderDialog.zsh):
        reverseDomainNameNotation = org.churchofjesuschrist
        organizationScriptName    = dorm

    LaunchDaemon Management (launchDaemonManagement.zsh):
        reverseDomainNameNotation = org.churchofjesuschrist
        organizationScriptName    = dor


Enter Your Organization’s Reverse Domain Name Notation [org.churchofjesuschrist] (or 'X' to exit): us.snelson

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Using 'us.snelson' as the Reverse Domain Name Notation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 Inserting reminderDialog.zsh into launchDaemonManagement.zsh  …

✅ Assembly complete [2025-12-13-054323]
   → Resources/ddm-os-reminder-assembled-2025-12-13-054323.zsh

🔁 Updating reverseDomainNameNotation to 'us.snelson' in assembled script …

🔍 Performing syntax check on 'Resources/ddm-os-reminder-assembled-2025-12-13-054323.zsh' …
    ✅ Syntax check passed.

🗂  Generating LaunchDaemon plist …
    🗂  Creating us.snelson.dorm plist from Resources/sample.plist …

    🔧 Updating internal plist content …
   → Resources/us.snelson.dorm-2025-12-13-054323.plist

🧩 Generating Configuration Profile (.mobileconfig) …
   → Resources/us.snelson.dorm-2025-12-13-054323-unsigned.mobileconfig

🔍 Performing syntax check on 'Resources/us.snelson.dorm-2025-12-13-054323-unsigned.mobileconfig' …
    ✅ Profile syntax check passed.

🔁 Renaming assembled script …

🔁 Updating scriptLog path based on RDNN …

🏁 Done.

Deployment Artifacts:
        Assembled Script: Resources/ddm-os-reminder-us.snelson-2025-12-13-054323.zsh
    Organizational Plist: Resources/us.snelson.dorm-2025-12-13-054323.plist
   Configuration Profile: Resources/us.snelson.dorm-2025-12-13-054323-unsigned.mobileconfig

===============================================================
```

**1.2.** Deploy the appropriate artifacts

After carefully reviewing and customizing either the `.plist` or `.mobileconfig`, you can deploy the appropriate artifacts directly to your Macs using your MDM, or proceed to [2. Create Self-extracting Script](#2-create-self-extracting-script) below.

---

### 2. Create Self-extracting

With some MDMs, it’s easier to deploy a **self-extracting script**. After [assembling the script](#1-assemble), run the provided [`createSelfExtracting.zsh`](createSelfExtracting.zsh) script to generate a self-extracting version.

**2.1.** Execute the script (it automatically uses the most recently assembled script):

```zsh
zsh Resources/createSelfExtracting.zsh
```

```
❯ zsh Resources/createSelfExtracting.zsh
🔍 Searching for the newest ddm-os-reminder-assembled-*.zsh file...
📦 Found: ddm-os-reminder-us.snelson-2025-12-13-054323.zsh
⚙️  Encoding 'ddm-os-reminder-us.snelson-2025-12-13-054323.zsh' ...

✅ Self-extracting script created successfully!
   ./ddm-os-reminder-us.snelson-2025-12-13-054323_self-extracting-2025-12-13-054810.sh

When run, it will extract to /var/tmp/ddm-os-reminder-us.snelson-2025-12-13-054323.zsh and execute automatically.
```

**2.2.** The resulting self-extracting script will be created as:

```
Resources/ddm-os-reminder-RDNN-YYYY-MM-DD-HHMMSS_self-extracting-YYYY-MM-DD-HHMMSS.sh
```

**2.3.** Deploy the assembled, self-extracting script

You can deploy the assembled, self-extracting script to your Macs using your MDM of choice. When executed, it extracts the assembled payload to `/var/tmp` and executes it automatically.

---

### 3. Create `.plist` 

If you have modified **both** `reminderDialog.zsh` and `launchDaemonManagement.zsh`, then want to reflect those changes in a new `.plist` and `.mobileconfig`, run the provided [`createPlist.zsh`](createPlist.zsh) script.

```zsh
zsh Resources/createPlist.zsh
```

```
❯ zsh Resources/createPlist.zsh
Generating default plist → ~/DDM-OS-Reminder/Resources/us.snelson.dorm-2025-12-13-055622.plist
SUCCESS! plist generated:
   → ~/DDM-OS-Reminder/Resources/us.snelson.dorm-2025-12-13-055622.plist
SUCCESS! mobileconfig generated:
   → ~/DDM-OS-Reminder/Resources/DDM OS Reminder-2025-12-13-055622-unsigned.mobileconfig
```

Upload the resulting `.plist` or `.mobileconfig` to your MDM of choice.

---

### 4. Extension Attributes

While the following Extension Attributes were created for and tested on **Jamf Pro**, they can likely be adapted for other MDMs.

(For adaptation help, visit the [Mac Admins Slack](https://www.macadmins.org/) `#ddm-os-reminders` channel or open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).)

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