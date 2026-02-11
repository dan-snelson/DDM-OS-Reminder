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
zsh assemble.zsh --help
zsh assemble.zsh us.snelson --lane prod --interactive
```

> **Automation note:** `assemble.zsh` is intentionally interactive by default. For unattended/non-interactive runs, provide both the RDNN argument and `--lane` explicitly.

The artifacts will be saved as shown below:

```
❯ zsh assemble.zsh us.snelson --lane prod --interactive

===============================================================
🧩 Assemble DDM OS Reminder (2.5.0b2)
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


📥 RDNN provided via command-line argument: 'us.snelson'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Using 'us.snelson' as the Reverse Domain Name Notation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IT Support & Branding (Interactive)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Support Team Name [IT Support] (or 'X' to exit):
Support Team Phone [+1 (801) 555-1212] (or 'X' to exit): +1 (937) 681-1122
Support Team Email [rescue@snelson.us] (or 'X' to exit):
Support Team Website [https://support.snelson.us] (or 'X' to exit):
Support KB Title [Update macOS on Mac] (or 'X' to exit): KB8675309
Info Button Action [https://support.snelson.us/KB8675309] (or 'X' to exit):
Support KB Markdown Link [[KB8675309](https://support.snelson.us/KB8675309)] (or 'X' to exit):
Overlay Icon URL (Light) [https://use2.ics.services.jamfcloud.com/icon/hash_2d64ce7f0042ad68234a2515211adb067ad6714703dd8ebd6f33c1ab30354b1d] (or 'X' to exit):
Overlay Icon URL (Dark) [https://use2.ics.services.jamfcloud.com/icon/hash_d3a3bc5e06d2db5f9697f9b4fa095bfecb2dc0d22c71aadea525eb38ff981d39] (or 'X' to exit):
Swap Overlay and Logo (YES/NO) [NO] (or 'X' to exit):

📦 Deployment Mode: prod

🔧 Inserting reminderDialog.zsh into launchDaemonManagement.zsh  …

✅ Assembly complete [2026-02-06-092404]
   → Artifacts/ddm-os-reminder-assembled-2026-02-06-092404.zsh

🔁 Updating reverseDomainNameNotation to 'us.snelson' in assembled script …

🔍 Performing syntax check on 'Artifacts/ddm-os-reminder-assembled-2026-02-06-092404.zsh' …
    ✅ Syntax check passed.

🗂  Generating LaunchDaemon plist …
    🗂  Creating us.snelson.dorm plist from Resources/sample.plist …

    🔧 Updating internal plist content …
    🔓 Production mode: removing placeholder text for clean deployment
    🔧 Applying IT support and branding values …
   → Artifacts/us.snelson.dorm-2026-02-06-092404-prod.plist

🧩 Generating Configuration Profile (.mobileconfig) …
   → Artifacts/us.snelson.dorm-2026-02-06-092404-prod-unsigned.mobileconfig

🔍 Performing syntax check on 'Artifacts/us.snelson.dorm-2026-02-06-092404-prod-unsigned.mobileconfig' …
    ✅ Profile syntax check passed.

🔁 Renaming assembled script …

🔁 Updating scriptLog path based on RDNN …

🏁 Done.

Deployment Artifacts:
        Assembled Script: Artifacts/ddm-os-reminder-us.snelson-2026-02-06-092404-prod.zsh
    Organizational Plist: Artifacts/us.snelson.dorm-2026-02-06-092404-prod.plist
   Configuration Profile: Artifacts/us.snelson.dorm-2026-02-06-092404-prod-unsigned.mobileconfig

===============================================================
```

**1.2.** Deploy the appropriate artifacts

The `assemble.zsh` script creates **all three files you need for deployment**:
- **Assembled script** (for direct execution or self-extracting)
- **`.plist`** (for plist-based preference management)
- **`.mobileconfig`** (for Configuration Profile deployment)

All artifacts are saved to the `Artifacts/` folder and include the lane suffix:
`-dev`, `-test`, or `-prod`.

After carefully reviewing and customizing either the `.plist` or `.mobileconfig`, you can deploy the appropriate artifacts directly to your Macs using your MDM, or proceed to [2. Create Self-extracting Script](#2-create-self-extracting-script) below.

> **Note:** The [Create `.plist`](#3-create-plist-optional) step is now **optional** since `assemble.zsh` already generates both `.plist` and `.mobileconfig` files. Use it only if you need to regenerate configuration files from an already-assembled script.

---

### 2. Create Self-extracting Script

With some MDMs, it's easier to deploy a **self-extracting script**. After [assembling the script](#1-assemble), run the provided [`createSelfExtracting.zsh`](createSelfExtracting.zsh) script to generate a self-extracting version.

This script automatically finds the **newest assembled script** in the `Artifacts/` folder and creates a base64-encoded, self-extracting version.

**2.1.** Execute the script:

```zsh
zsh Resources/createSelfExtracting.zsh
```

```
❯ zsh Resources/createSelfExtracting.zsh
🔍 Searching for the newest ddm-os-reminder-*.zsh file in ~/DDM-OS-Reminder/Artifacts...
📦 Found: ddm-os-reminder-us.snelson-2026-01-08-054323.zsh
⚙️  Encoding 'ddm-os-reminder-us.snelson-2026-01-08-054323.zsh' ...

✅ Self-extracting script created successfully!
   ~/DDM-OS-Reminder/Artifacts/ddm-os-reminder-us.snelson-2026-01-08-054323_self-extracting-2026-01-08-054810.sh

When run, it will extract to /var/tmp/ddm-os-reminder-us.snelson-2026-01-08-054323.zsh and execute automatically.
```

**2.2.** The resulting self-extracting script will be created in the `Artifacts/` folder as:

```
Artifacts/ddm-os-reminder-RDNN-YYYY-MM-DD-HHMMSS_self-extracting-YYYY-MM-DD-HHMMSS.sh
```

**2.3.** Deploy the assembled, self-extracting script

You can deploy the assembled, self-extracting script to your Macs using your MDM of choice. When executed, it extracts the assembled payload to `/var/tmp` and executes it automatically.

---

### 3. Create `.plist` (Optional)

> **Note:** This step is now **optional** since `assemble.zsh` already generates both `.plist` and `.mobileconfig` files in the `Artifacts/` folder.
> 
> **Note:** The ProfileManifests manifest for this project is maintained in the [ProfileManifests repo](https://github.com/ProfileManifests/ProfileManifests/blob/master/Manifests/ManagedPreferencesApplications/org.churchofjesuschrist.dorm.plist) and is not sourced from this directory.

The [`createPlist.zsh`](createPlist.zsh) script extracts default values from the **original** `reminderDialog.zsh` file to generate `.plist` and `.mobileconfig` files.

**Use this only if you need to:**
- Generate configuration files **without** running the full assembly process
- Create standalone configs for testing purposes
- Regenerate configs after modifying `reminderDialog.zsh` directly

**Important:** This script reads from the original source files, not assembled scripts. To get configs with assembly customizations (RDNN updates, etc.), use the output from `assemble.zsh` instead.

```zsh
zsh Resources/createPlist.zsh
```

```
❯ zsh Resources/createPlist.zsh
Generating default plist → ~/DDM-OS-Reminder/Resources/org.churchofjesuschrist.dor-2026-01-08-055622.plist
SUCCESS! plist generated:
   → ~/DDM-OS-Reminder/Resources/org.churchofjesuschrist.dor-2026-01-08-055622.plist
SUCCESS! mobileconfig generated:
   → ~/DDM-OS-Reminder/Resources/DDM OS Reminder-2026-01-08-055622-unsigned.mobileconfig
```

---

### 4. Extension Attributes

While the following Extension Attributes were created for and tested on **Jamf Pro**, they can likely be adapted for other MDMs.

(For adaptation help, visit the [Mac Admins Slack](https://www.macadmins.org/) `#ddm-os-reminders` channel or open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).)

**4.1.** [`JamfEA-DDM-OS-Reminder-User-Clicks.zsh`](JamfEA-DDM-OS-Reminder-User-Clicks.zsh)  
Reports the user’s button clicks from the DDM OS Reminder message.

```
2026-01-08 02:53:37 dan clicked Remind Me Later
2026-01-08 02:55:28 dan clicked Open Software Update
2026-01-08 03:01:11 dan clicked Remind Me Later
2026-01-08 03:11:32 dan clicked Remind Me Later
2026-01-08 03:48:27 dan clicked KB0054571
```

**4.2.** [`JamfEA-Pending_OS_Update_Date.zsh`](JamfEA-Pending_OS_Update_Date.zsh)  
Reports the date of a pending DDM-enforced macOS update.

```
2026-01-17 12:00:00
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
