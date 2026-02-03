# Configuration Reference

Complete reference guide for all configurable preferences in DDM OS Reminder.

## Table of Contents

- [Quick Reference Table](#quick-reference-table)
- [Configuration by Category](#configuration-by-category)
  - [Logging & Infrastructure](#1-logging--infrastructure)
  - [Timing & Thresholds](#2-timing--thresholds)
  - [Branding & Appearance](#3-branding--appearance)
  - [Support Team Information](#4-support-team-information)
  - [Dialog UI Text](#5-dialog-ui-text)
  - [Update Staging Messages](#6-update-staging-messages)
- [Placeholder Reference](#placeholder-reference)
- [Common Configuration Scenarios](#common-configuration-scenarios)
- [Configuration Methods](#configuration-methods)
- [Troubleshooting](#troubleshooting)

---

## Quick Reference Table

| Variable | Plist Key | Type | Default | Category |
|----------|-----------|------|---------|----------|
| scriptLog | ScriptLog | String | `/var/log/org.churchofjesuschrist.log` | Logging |
| daysBeforeDeadlineDisplayReminder | DaysBeforeDeadlineDisplayReminder | Integer | 60 | Timing |
| daysBeforeDeadlineBlurscreen | DaysBeforeDeadlineBlurscreen | Integer | 45 | Timing |
| daysBeforeDeadlineHidingButton2 | DaysBeforeDeadlineHidingButton2 | Integer | 21 | Timing |
| daysOfExcessiveUptimeWarning | DaysOfExcessiveUptimeWarning | Integer | 0 | Timing |
| meetingDelay | MeetingDelay | Integer | 75 | Timing |
| minimumDiskFreePercentage | MinimumDiskFreePercentage | Integer | 99 | Timing |
| organizationOverlayiconURL | OrganizationOverlayIconURL | String | [URL] | Branding |
| organizationOverlayiconURLdark | OrganizationOverlayIconURLdark | String | (empty) | Branding |
| swapOverlayAndLogo | SwapOverlayAndLogo | Boolean | NO | Branding |
| dateFormatDeadlineHumanReadable | DateFormatDeadlineHumanReadable | String | `+%a, %d-%b-%Y, %-l:%M %p` | Branding |
| supportTeamName | SupportTeamName | String | IT Support | Support |
| supportTeamPhone | SupportTeamPhone | String | +1 (801) 555-1212 | Support |
| supportTeamEmail | SupportTeamEmail | String | rescue@domain.org | Support |
| supportTeamWebsite | SupportTeamWebsite | String | https://support.domain.org | Support |
| supportKB | SupportKB | String | Update macOS on Mac | Support |
| infobuttonaction | InfoButtonAction | String | https://support.apple.com/108382 | Support |
| supportKBURL | SupportKBURL | String | [Markdown link] | Support |
| title | Title | String | macOS {placeholder} Required | UI Text |
| button1text | Button1Text | String | Open Software Update | UI Text |
| button2text | Button2Text | String | Remind Me Later | UI Text |
| infobuttontext | InfoButtonText | String | Update macOS on Mac | UI Text |
| excessiveUptimeWarningMessage | ExcessiveUptimeWarningMessage | String | [HTML message] | UI Text |
| diskSpaceWarningMessage | DiskSpaceWarningMessage | String | [HTML message] | UI Text |
| stagedUpdateMessage | StagedUpdateMessage | String | [HTML message] | Staging |
| partiallyStagedUpdateMessage | PartiallyStagedUpdateMessage | String | [HTML message] | Staging |
| pendingDownloadMessage | PendingDownloadMessage | String | [HTML message] | Staging |
| hideStagedInfo | HideStagedUpdateInfo | Boolean | NO | Staging |
| message | Message | String | [Full dialog message] | UI Text |
| infobox | InfoBox | String | [System info display] | UI Text |
| helpmessage | HelpMessage | String | [Support contact info] | UI Text |
| helpimage | HelpImage | String | qr={infobuttonaction} | UI Text |

---

## Configuration by Category

### 1. Logging & Infrastructure

#### scriptLog
**Plist Key**: `ScriptLog`  
**Type**: String  
**Default**: `/var/log/org.churchofjesuschrist.log`

**Description**: Path to the client-side log file where all script activity is recorded.

**Recommendation**: Change to match your organization's RDNN (e.g., `/var/log/com.company.log`)

**Script Default**:
```bash
["scriptLog"]="string|/var/log/org.churchofjesuschrist.log"
```

**Configuration Profile**:
```xml
<key>ScriptLog</key>
<string>/var/log/com.company.log</string>
```

**Local Preference**:
```bash
sudo defaults write /Library/Preferences/org.churchofjesuschrist.dorm \
    ScriptLog -string "/var/log/com.company.log"
```

**Log Rotation**: Automatically rotates when exceeds 10MB

---

### 2. Timing & Thresholds

#### daysBeforeDeadlineDisplayReminder
**Plist Key**: `DaysBeforeDeadlineDisplayReminder`  
**Type**: Integer  
**Default**: 60  
**Valid Range**: 0-999

**Description**: Number of days before the DDM deadline when reminders should start appearing to users.

**Impact**:
- Users see no reminders if outside this window
- Too high = reminder fatigue
- Too low = insufficient warning time

**Recommendations**:
- **Conservative**: 30 days
- **Balanced**: 60 days (default)
- **Aggressive**: 90 days

**Script Default**:
```bash
["daysBeforeDeadlineDisplayReminder"]="numeric|60"
```

**Configuration Profile**:
```xml
<key>DaysBeforeDeadlineDisplayReminder</key>
<integer>60</integer>
```

**Local Preference**:
```bash
sudo defaults write /Library/Preferences/org.churchofjesuschrist.dorm \
    DaysBeforeDeadlineDisplayReminder -int 60
```

**Related**: See [Deadline Timeline](03-deadline-timeline.md) for visual representation

---

#### daysBeforeDeadlineBlurscreen
**Plist Key**: `DaysBeforeDeadlineBlurscreen`  
**Type**: Integer  
**Default**: 45  
**Valid Range**: 0-999

**Description**: Number of days before deadline when the blurscreen effect activates, dimming the desktop background to increase visual urgency.

**Impact**:
- Blurscreen significantly increases user attention
- Creates medium-urgency phase
- Balance between annoying and effective

**Recommendations**:
- **Conservative**: 14 days
- **Balanced**: 45 days (default)
- **Aggressive**: 60 days

**Must Be Less Than**: `daysBeforeDeadlineDisplayReminder`

**Script Default**:
```bash
["daysBeforeDeadlineBlurscreen"]="numeric|45"
```

**Configuration Profile**:
```xml
<key>DaysBeforeDeadlineBlurscreen</key>
<integer>45</integer>
```

**Visual Example**: See [Deadline Timeline Phase 3](03-deadline-timeline.md#phase-3-blurscreen-warnings-escalating-urgency)

---

#### daysBeforeDeadlineHidingButton2
**Plist Key**: `DaysBeforeDeadlineHidingButton2`  
**Type**: Integer  
**Default**: 21  
**Valid Range**: 0-999

**Description**: Number of days before deadline when the "Remind Me Later" button (Button 2) becomes disabled or hidden, forcing users to either update or close the dialog.

**Impact**:
- Removes user's ability to postpone
- Creates high-urgency phase
- Should be close to deadline

**Recommendations**:
- **Conservative**: 7 days
- **Balanced**: 21 days (default)
- **Aggressive**: 30 days

**Must Be Less Than**: `daysBeforeDeadlineBlurscreen`

**Note**: Behavior controlled by hard-coded `disableButton2InsteadOfHide` variable:
- `YES` = Button appears greyed out (disabled)
- `NO` = Button hidden completely

**Script Default**:
```bash
["daysBeforeDeadlineHidingButton2"]="numeric|21"
```

**Configuration Profile**:
```xml
<key>DaysBeforeDeadlineHidingButton2</key>
<integer>21</integer>
```

**Visual Example**: See [Deadline Timeline Phase 4](03-deadline-timeline.md#phase-4-urgentcritical-deadline-imminent)

---

#### daysOfExcessiveUptimeWarning
**Plist Key**: `DaysOfExcessiveUptimeWarning`  
**Type**: Integer  
**Default**: 0 (disabled)  
**Valid Range**: 0-999

**Description**: Number of days without restart that triggers an uptime warning message in the dialog, recommending user restart before updating.

**Impact**:
- Warns users with stale system state
- Improves update reliability
- 0 = feature disabled

**Recommendations**:
- **Disabled**: 0 (default)
- **Moderate**: 7 days
- **Strict**: 3 days

**Script Default**:
```bash
["daysOfExcessiveUptimeWarning"]="numeric|0"
```

**Configuration Profile**:
```xml
<key>DaysOfExcessiveUptimeWarning</key>
<integer>7</integer>
```

**Warning Message Variable**: `excessiveUptimeWarningMessage`

---

#### meetingDelay
**Plist Key**: `MeetingDelay`  
**Type**: Integer  
**Default**: 75  
**Valid Range**: 0-999 (minutes)

**Description**: Number of minutes to delay dialog display when user has active display sleep assertions (detected via `pmset`), typically indicating a video call or presentation.

**Impact**:
- Respects user's focus time
- Prevents interruption during meetings
- Script will retry after delay period

**Recommendations**:
- **Short meetings**: 30-45 minutes
- **Standard meetings**: 75 minutes (default)
- **Extended meetings**: 120 minutes

**Exception**: Ignored when less than 24 hours remain until deadline

**Script Default**:
```bash
["meetingDelay"]="numeric|75"
```

**Configuration Profile**:
```xml
<key>MeetingDelay</key>
<integer>75</integer>
```

**Related Logic**: See [Runtime Decision Tree - Meeting Detection](02-runtime-decision-tree.md#8-meeting-detection)

---

#### minimumDiskFreePercentage
**Plist Key**: `MinimumDiskFreePercentage`  
**Type**: Integer  
**Default**: 99 (disabled)  
**Valid Range**: 0-99

**Description**: Minimum percentage of free disk space required to avoid showing a low disk space warning in the dialog.

**Impact**:
- Warns users who may not have enough space for update
- 99 = effectively disabled (warning only if <1% free)
- Adds warning message, doesn't block dialog

**Recommendations**:
- **Disabled**: 99 (default)
- **Typical macOS update**: 15-20%
- **Major macOS upgrade**: 25-30%

**Script Default**:
```bash
["minimumDiskFreePercentage"]="numeric|99"
```

**Configuration Profile**:
```xml
<key>MinimumDiskFreePercentage</key>
<integer>20</integer>
```

**Warning Message Variable**: `diskSpaceWarningMessage`

---

### 3. Branding & Appearance

#### organizationOverlayiconURL
**Plist Key**: `OrganizationOverlayIconURL`  
**Type**: String  
**Default**: `https://usw2.ics.services.jamfcloud.com/icon/hash_4804203ac36cbd7c83607487f4719bd4707f2e283500f54428153af17da082e2`

**Description**: URL to organization's icon/logo displayed in the dialog. Accepts HTTP/HTTPS URLs or local file paths.

**Supported Formats**:
- PNG (recommended)
- JPEG
- ICNS
- Local paths: `file:///path/to/icon.png`

**Recommendations**:
- Size: 256x256px or larger
- Transparent background (PNG)
- High contrast for visibility

**Script Default**:
```bash
["organizationOverlayiconURL"]="string|https://your-cdn.com/icon.png"
```

**Configuration Profile**:
```xml
<key>OrganizationOverlayIconURL</key>
<string>https://cdn.company.com/it-icon.png</string>
```

**Local File Example**:
```bash
sudo defaults write /Library/Preferences/org.churchofjesuschrist.dorm \
    OrganizationOverlayIconURL -string "file:///Library/Management/icons/company-logo.png"
```

---

#### organizationOverlayiconURLdark
**Plist Key**: `OrganizationOverlayIconURLdark`  
**Type**: String  
**Default**: (empty)

**Description**: Optional URL to organization's dark mode icon/logo displayed when macOS is in Dark Mode (System Settings > Appearance > Dark). When empty or unset, the standard `organizationOverlayiconURL` is used regardless of appearance mode. The script automatically detects the user's appearance mode from `~/Library/Preferences/.GlobalPreferences.plist` and selects the appropriate icon.

**Supported Formats**:
- PNG (recommended)
- JPEG
- ICNS
- Local paths: `file:///path/to/icon.png`

**Behavior**:
- **Dark Mode Active + Dark URL Set**: Uses `organizationOverlayiconURLdark`
- **Dark Mode Active + Dark URL Empty**: Falls back to `organizationOverlayiconURL`
- **Light Mode**: Always uses `organizationOverlayiconURL`
- **Auto Appearance**: Detects system appearance dynamically at runtime

**Recommendations**:
- Size: 256x256px or larger (match your light mode icon)
- Design: Optimize contrast for dark backgrounds
- Testing: Verify visibility in both System Settings > Appearance modes

**Script Default**:
```bash
["organizationOverlayiconURLdark"]="string|"
```

**Configuration Profile**:
```xml
<key>OrganizationOverlayIconURLdark</key>
<string>https://cdn.company.com/it-icon-dark.png</string>
```

**Local Preference**:
```bash
sudo defaults write /Library/Preferences/org.churchofjesuschrist.dorm \
    OrganizationOverlayIconURLdark -string "https://cdn.company.com/dark-icon.png"
```

**Local File Example**:
```bash
sudo defaults write /Library/Preferences/org.churchofjesuschrist.dorm \
    OrganizationOverlayIconURLdark -string "file:///Library/Management/icons/company-logo-dark.png"
```

**Demo Mode**: Automatically detects and respects the current System Settings > Appearance selection (Auto, Light, or Dark).

---

#### swapOverlayAndLogo
**Plist Key**: `SwapOverlayAndLogo`  
**Type**: Boolean  
**Default**: NO

**Description**: Swaps the position of the overlay icon and the default swiftDialog logo in the dialog window.

**Values**:
- `NO` / `false` / `0` = Default position
- `YES` / `true` / `1` = Swapped position

**Script Default**:
```bash
["swapOverlayAndLogo"]="boolean|NO"
```

**Configuration Profile**:
```xml
<key>SwapOverlayAndLogo</key>
<true/>
```

**Local Preference**:
```bash
sudo defaults write /Library/Preferences/org.churchofjesuschrist.dorm \
    SwapOverlayAndLogo -bool YES
```

---

#### dateFormatDeadlineHumanReadable
**Plist Key**: `DateFormatDeadlineHumanReadable`  
**Type**: String  
**Default**: `+%a, %d-%b-%Y, %-l:%M %p`

**Description**: `date` command format string for displaying the DDM enforcement deadline in human-readable format.

**Default Output Example**: `Wed, 01-Apr-2026, 8:00 AM`

**Format Codes**:
- `%a` = Abbreviated weekday (Mon, Tue, etc.)
- `%d` = Day of month (01-31)
- `%b` = Abbreviated month (Jan, Feb, etc.)
- `%Y` = 4-digit year
- `%-l` = Hour (1-12, no leading zero)
- `%M` = Minute (00-59)
- `%p` = AM/PM

**Alternative Formats**:
```bash
# US Format: 04/01/2026 8:00 AM
"+%m/%d/%Y %-l:%M %p"

# ISO Format: 2026-04-01 08:00
"+%Y-%m-%d %H:%M"

# Verbose: Wednesday, April 1, 2026 at 8:00 AM
"+%A, %B %d, %Y at %-l:%M %p"
```

**Script Default**:
```bash
["dateFormatDeadlineHumanReadable"]="string|+%a, %d-%b-%Y, %-l:%M %p"
```

**Configuration Profile**:
```xml
<key>DateFormatDeadlineHumanReadable</key>
<string>+%m/%d/%Y %-l:%M %p</string>
```

**Note**: Leading `+` is required and automatically added if missing

---

### 4. Support Team Information

#### supportTeamName
**Plist Key**: `SupportTeamName`  
**Type**: String  
**Default**: `IT Support`

**Description**: Name of your organization's support team displayed throughout the dialog and help screen.

**Placeholder**: `{supportTeamName}`  
**Used In**: message, helpmessage

**Script Default**:
```bash
["supportTeamName"]="string|IT Support"
```

**Configuration Profile**:
```xml
<key>SupportTeamName</key>
<string>Enterprise IT Services</string>
```

---

#### supportTeamPhone
**Plist Key**: `SupportTeamPhone`  
**Type**: String  
**Default**: `+1 (801) 555-1212`

**Description**: Support team phone number displayed in help dialog.

**Placeholder**: `{supportTeamPhone}`  
**Used In**: helpmessage

**Recommendations**:
- Include country code
- Use standard formatting
- Consider toll-free numbers

**Script Default**:
```bash
["supportTeamPhone"]="string|+1 (801) 555-1212"
```

**Configuration Profile**:
```xml
<key>SupportTeamPhone</key>
<string>+1 (555) 123-4567</string>
```

---

#### supportTeamEmail
**Plist Key**: `SupportTeamEmail`  
**Type**: String  
**Default**: `rescue@domain.org`

**Description**: Support team email address displayed in help dialog.

**Placeholder**: `{supportTeamEmail}`  
**Used In**: helpmessage

**Script Default**:
```bash
["supportTeamEmail"]="string|rescue@domain.org"
```

**Configuration Profile**:
```xml
<key>SupportTeamEmail</key>
<string>helpdesk@company.com</string>
```

---

#### supportTeamWebsite
**Plist Key**: `SupportTeamWebsite`  
**Type**: String  
**Default**: `https://support.domain.org`

**Description**: Support team website URL displayed in help dialog.

**Placeholder**: `{supportTeamWebsite}`  
**Used In**: helpmessage

**Script Default**:
```bash
["supportTeamWebsite"]="string|https://support.domain.org"
```

**Configuration Profile**:
```xml
<key>SupportTeamWebsite</key>
<string>https://helpdesk.company.com</string>
```

---

#### supportKB
**Plist Key**: `SupportKB`  
**Type**: String  
**Default**: `Update macOS on Mac`

**Description**: Display text for knowledge base article link (without URL).

**Related**: Used with `supportKBURL` to create markdown link

**Script Default**:
```bash
["supportKB"]="string|Update macOS on Mac"
```

**Configuration Profile**:
```xml
<key>SupportKB</key>
<string>How to Update macOS</string>
```

---

#### infobuttonaction
**Plist Key**: `InfoButtonAction`  
**Type**: String  
**Default**: `https://support.apple.com/108382`

**Description**: URL opened when user clicks the info button (?) in dialog. Also used as QR code content in help dialog.

**Placeholder**: `{infobuttonaction}`  
**Used In**: helpimage (QR code generation)

**Recommendations**:
- Link to internal KB article
- Link to video tutorial
- Link to support portal

**Script Default**:
```bash
["infobuttonaction"]="string|https://support.apple.com/108382"
```

**Configuration Profile**:
```xml
<key>InfoButtonAction</key>
<string>https://kb.company.com/macos-updates</string>
```

**Special Value**: Set to empty string to hide info button entirely

---

#### supportKBURL
**Plist Key**: `SupportKBURL`  
**Type**: String  
**Default**: `[Update macOS on Mac](https://support.apple.com/108382)`

**Description**: Full markdown-formatted link combining `supportKB` text with URL for display in help message.

**Format**: `[Link Text](URL)`

**Placeholder**: `{supportKBURL}`  
**Used In**: helpmessage

**Script Default**:
```bash
["supportKBURL"]="string|[Update macOS on Mac](https://support.apple.com/108382)"
```

**Configuration Profile**:
```xml
<key>SupportKBURL</key>
<string>[How to Update macOS](https://kb.company.com/updates)</string>
```

---

### 5. Dialog UI Text

#### title
**Plist Key**: `Title`  
**Type**: String  
**Default**: `macOS {titleMessageUpdateOrUpgrade} Required`

**Description**: Main title displayed at the top of the dialog window.

**Supports Placeholders**: Yes

**Common Placeholders**:
- `{titleMessageUpdateOrUpgrade}` = "Update" or "Upgrade" (auto-detected)
- `{ddmVersionString}` = Required macOS version

**Script Default**:
```bash
["title"]="string|macOS {titleMessageUpdateOrUpgrade} Required"
```

**Configuration Profile**:
```xml
<key>Title</key>
<string>Action Required: macOS {ddmVersionString} Update</string>
```

**Rendered Example**: `macOS Update Required` or `macOS Upgrade Required`

---

#### button1text
**Plist Key**: `Button1Text`  
**Type**: String  
**Default**: `Open Software Update`

**Description**: Label for the primary action button (Button 1) that opens System Settings → Software Update.

**Placeholder**: `{button1text}`  
**Used In**: message

**Recommendations**:
- Keep concise (2-4 words)
- Action-oriented
- Clear outcome

**Script Default**:
```bash
["button1text"]="string|Open Software Update"
```

**Configuration Profile**:
```xml
<key>Button1Text</key>
<string>Update Now</string>
```

---

#### button2text
**Plist Key**: `Button2Text`  
**Type**: String  
**Default**: `Remind Me Later`

**Description**: Label for the secondary button (Button 2) that dismisses the dialog for later reminder.

**Placeholder**: `{button2text}`  
**Used In**: message

**Note**: This button is automatically disabled/hidden when deadline is imminent (controlled by `daysBeforeDeadlineHidingButton2`)

**Script Default**:
```bash
["button2text"]="string|Remind Me Later"
```

**Configuration Profile**:
```xml
<key>Button2Text</key>
<string>Not Now</string>
```

---

#### infobuttontext
**Plist Key**: `InfoButtonText`  
**Type**: String  
**Default**: `Update macOS on Mac`

**Description**: Tooltip text displayed when hovering over the info button (?).

**Special Value**: `hide` to completely hide the info button

**Script Default**:
```bash
["infobuttontext"]="string|Update macOS on Mac"
```

**Configuration Profile**:
```xml
<key>InfoButtonText</key>
<string>Learn More About Updates</string>
```

**To Hide Info Button**:
```xml
<key>InfoButtonText</key>
<string>hide</string>
```

---

#### message
**Plist Key**: `Message`  
**Type**: String  
**Default**: [Full message text with placeholders]

**Description**: Main body text of the dialog. Supports HTML formatting and extensive placeholder substitution.

**Supports Placeholders**: Yes (20+ placeholders)

**HTML Formatting**:
- `**bold**` = Bold text
- `<br>` or `<br><br>` = Line breaks
- Standard markdown formatting

**Key Placeholders Used**:
- `{loggedInUserFirstname}` = User's first name
- `{ddmVersionString}` = Required macOS version
- `{titleMessageUpdateOrUpgrade:l}` = "update" or "upgrade" (lowercase)
- `{updateReadyMessage}` = Staged update status message
- `{button1text}` = Button 1 label
- `{button2text}` = Button 2 label
- `{softwareUpdateButtonText}` = Expected button in System Settings
- `{ddmEnforcedInstallDateHumanReadable}` = Formatted deadline
- `{excessiveUptimeWarningMessage}` = Uptime warning (if applicable)
- `{diskSpaceWarningMessage}` = Disk space warning (if applicable)
- `{supportTeamName}` = Support team name
- `{weekday}` = Current day of week

**Script Default** (condensed):
```bash
["message"]="string|**A required macOS {titleMessageUpdateOrUpgrade:l} is now available**<br><br>Happy {weekday}, {loggedInUserFirstname}!<br><br>Please {titleMessageUpdateOrUpgrade:l} to macOS **{ddmVersionString}**..."
```

**Configuration Profile** (escaped HTML):
```xml
<key>Message</key>
<string>**Important Update Required**&lt;br&gt;&lt;br&gt;Hello {loggedInUserFirstname},&lt;br&gt;&lt;br&gt;Your Mac must be updated to macOS {ddmVersionString} by {ddmEnforcedInstallDateHumanReadable}.</string>
```

**Customization Tips**:
- Keep paragraphs short
- Use bold for emphasis
- Include clear call-to-action
- Explain consequences of deadline

---

#### infobox
**Plist Key**: `InfoBox`  
**Type**: String  
**Default**: [System information display]

**Description**: Right sidebar content showing current system status and deadline information.

**Supports Placeholders**: Yes

**Key Placeholders Used**:
- `{installedmacOSVersion}` = Current macOS version
- `{ddmVersionString}` = Required macOS version
- `{ddmVersionStringDeadlineHumanReadable}` = Formatted deadline
- `{ddmVersionStringDaysRemaining}` = Days until deadline
- `{uptimeHumanReadable}` = Time since last restart
- `{diskSpaceHumanReadable}` = Free disk space

**Script Default**:
```bash
["infobox"]="string|**Current:** macOS {installedmacOSVersion}<br><br>**Required:** macOS {ddmVersionString}<br><br>**Deadline:** {ddmVersionStringDeadlineHumanReadable}..."
```

**Configuration Profile**:
```xml
<key>InfoBox</key>
<string>**System Info**&lt;br&gt;&lt;br&gt;Current: {installedmacOSVersion}&lt;br&gt;Target: {ddmVersionString}&lt;br&gt;Due: {ddmVersionStringDeadlineHumanReadable}</string>
```

---

#### helpmessage
**Plist Key**: `HelpMessage`  
**Type**: String  
**Default**: [Support contact information]

**Description**: Content displayed when user clicks the info (?) button, providing support contact details and system information.

**Supports Placeholders**: Yes (all support placeholders + system info)

**Key Placeholders Used**:
- All support team variables
- `{userfullname}` = User's full name
- `{username}` = User's account name
- `{computername}` = Mac's computer name
- `{serialnumber}` = Mac's serial number
- `{osversion}` = Current macOS version
- `{dialogVersion}` = swiftDialog version
- `{scriptVersion}` = DDM OS Reminder version

**Script Default** (condensed):
```bash
["helpmessage"]="string|For assistance, please contact: **{supportTeamName}**<br>- **Telephone:** {supportTeamPhone}<br>- **Email:** {supportTeamEmail}..."
```

**Configuration Profile**:
```xml
<key>HelpMessage</key>
<string>**Need Help?**&lt;br&gt;&lt;br&gt;Contact {supportTeamName}:&lt;br&gt;Phone: {supportTeamPhone}&lt;br&gt;Email: {supportTeamEmail}</string>
```

---

#### helpimage
**Plist Key**: `HelpImage`  
**Type**: String  
**Default**: `qr={infobuttonaction}`

**Description**: Image displayed in the help dialog. Uses special swiftDialog syntax to generate QR code.

**QR Code Syntax**: `qr=URL`  
**Direct Image**: Full URL or file path to image

**Special Value**: `hide` to show no image

**Script Default**:
```bash
["helpimage"]="string|qr={infobuttonaction}"
```

**Configuration Profile (QR Code)**:
```xml
<key>HelpImage</key>
<string>qr=https://support.company.com</string>
```

**Configuration Profile (Direct Image)**:
```xml
<key>HelpImage</key>
<string>https://cdn.company.com/support-image.png</string>
```

**To Hide Help Image**:
```xml
<key>HelpImage</key>
<string>hide</string>
```

---

### 6. Update Staging Messages

#### stagedUpdateMessage
**Plist Key**: `StagedUpdateMessage`  
**Type**: String  
**Default**: [Message about fully staged update]

**Description**: Message inserted into main dialog when script detects that the macOS update has been fully downloaded and staged in the Preboot volume (ready for quick installation).

**Supports Placeholders**: Yes  
**Inserted Into**: `{updateReadyMessage}` placeholder in `message`

**Detection Criteria**:
- Preboot volume snapshot exists
- Update cryptex1 ≥ 8GB (indicates full download)

**Script Default**:
```bash
["stagedUpdateMessage"]="string|<br><br>**Good news!** The macOS {ddmVersionString} update has already been downloaded to your Mac and is ready to install. Installation will proceed quickly when you click **{button1text}**."
```

**Configuration Profile**:
```xml
<key>StagedUpdateMessage</key>
<string>&lt;br&gt;&lt;br&gt;**Ready to Install** The update is already downloaded and ready.</string>
```

---

#### partiallyStagedUpdateMessage
**Plist Key**: `PartiallyStagedUpdateMessage`  
**Type**: String  
**Default**: [Message about partial staging]

**Description**: Message inserted when update is partially downloaded but not yet complete.

**Supports Placeholders**: Yes  
**Inserted Into**: `{updateReadyMessage}` placeholder in `message`

**Detection Criteria**:
- Preboot volume snapshot exists
- Update cryptex1 between 1GB and 8GB (partial download)

**Script Default**:
```bash
["partiallyStagedUpdateMessage"]="string|<br><br>Your Mac has begun downloading and preparing required macOS update components. Installation will be quicker once all assets have finished staging."
```

**Configuration Profile**:
```xml
<key>PartiallyStagedUpdateMessage</key>
<string>&lt;br&gt;&lt;br&gt;Update download in progress...</string>
```

---

#### pendingDownloadMessage
**Plist Key**: `PendingDownloadMessage`  
**Type**: String  
**Default**: [Message about pending download]

**Description**: Message inserted when no staged update is detected (update will need to download when user clicks Update).

**Supports Placeholders**: Yes  
**Inserted Into**: `{updateReadyMessage}` placeholder in `message`

**Detection Criteria**:
- No Preboot snapshot or cryptex1 < 1GB

**Script Default**:
```bash
["pendingDownloadMessage"]="string|<br><br>Your Mac will begin downloading the update shortly."
```

**Configuration Profile**:
```xml
<key>PendingDownloadMessage</key>
<string>&lt;br&gt;&lt;br&gt;The update will download when you proceed.</string>
```

---

#### hideStagedInfo
**Plist Key**: `HideStagedUpdateInfo`  
**Type**: Boolean  
**Default**: NO

**Description**: When set to YES, suppresses all staged update status messages (staged, partially staged, pending). The `{updateReadyMessage}` placeholder will be empty.

**Values**:
- `NO` / `false` / `0` = Show staging status (default)
- `YES` / `true` / `1` = Hide staging status

**Use Case**: Organizations that don't want to expose technical details about update staging

**Script Default**:
```bash
["hideStagedInfo"]="boolean|NO"
```

**Configuration Profile**:
```xml
<key>HideStagedUpdateInfo</key>
<true/>
```

**Local Preference**:
```bash
sudo defaults write /Library/Preferences/org.churchofjesuschrist.dorm \
    HideStagedUpdateInfo -bool YES
```

---

### 7. Warning Messages

#### excessiveUptimeWarningMessage
**Plist Key**: `ExcessiveUptimeWarningMessage`  
**Type**: String  
**Default**: [Warning about excessive uptime]

**Description**: Warning message inserted into dialog when Mac has been running for excessive days without restart (threshold set by `daysOfExcessiveUptimeWarning`).

**Supports Placeholders**: Yes  
**Key Placeholder**: `{uptimeHumanReadable}`  
**Inserted Into**: `{excessiveUptimeWarningMessage}` in `message`

**Triggered When**: `daysOfExcessiveUptimeWarning` > 0 and uptime exceeds threshold

**Script Default**:
```bash
["excessiveUptimeWarningMessage"]="string|<br><br>**Note:** Your Mac has been powered-on for **{uptimeHumanReadable}**. For more reliable results, please manually restart your Mac before proceeding."
```

**Configuration Profile**:
```xml
<key>ExcessiveUptimeWarningMessage</key>
<string>&lt;br&gt;&lt;br&gt;**Warning:** System uptime is {uptimeHumanReadable}. Please restart before updating.</string>
```

---

#### diskSpaceWarningMessage
**Plist Key**: `DiskSpaceWarningMessage`  
**Type**: String  
**Default**: [Warning about low disk space]

**Description**: Warning message inserted when free disk space falls below `minimumDiskFreePercentage` threshold.

**Supports Placeholders**: Yes  
**Key Placeholders**: 
- `{diskSpaceHumanReadable}` = Free space with percentage
- `{titleMessageUpdateOrUpgrade:l}` = "update" or "upgrade"

**Inserted Into**: `{diskSpaceWarningMessage}` in `message`

**Triggered When**: Free disk space percentage < `minimumDiskFreePercentage`

**Script Default**:
```bash
["diskSpaceWarningMessage"]="string|<br><br>**Note:** Your Mac has only **{diskSpaceHumanReadable}**, which may prevent this macOS {titleMessageUpdateOrUpgrade:l}."
```

**Configuration Profile**:
```xml
<key>DiskSpaceWarningMessage</key>
<string>&lt;br&gt;&lt;br&gt;**Low Disk Space:** {diskSpaceHumanReadable} available. Free up space before updating.</string>
```

---

## Placeholder Reference

### Complete Placeholder List

| Placeholder | Source | Description | Example Output |
|-------------|--------|-------------|----------------|
| `{weekday}` | System | Current day of week | Monday |
| `{loggedInUserFirstname}` | System | User's first name | Dan |
| `{loggedInUser}` | System | Username | dsnelson |
| `{userfullname}` | System | Full name | Dan Snelson |
| `{username}` | System | Account name | dsnelson |
| `{computername}` | System | Mac name | Dans-MacBook-Pro |
| `{serialnumber}` | System | Serial number | C02ABC123DEF |
| `{osversion}` | System | Current macOS | 15.1.1 |
| `{installedmacOSVersion}` | System | Full macOS version | macOS 15.1.1 (Sequoia) |
| `{ddmVersionString}` | DDM | Required version | 15.2 |
| `{ddmEnforcedInstallDateHumanReadable}` | DDM | Formatted deadline | Wed, 01-Apr-2026, 8:00 AM |
| `{ddmVersionStringDeadlineHumanReadable}` | DDM | Formatted deadline (alt) | Wed, 01-Apr-2026, 8:00 AM |
| `{ddmVersionStringDaysRemaining}` | DDM | Days to deadline | 14 |
| `{titleMessageUpdateOrUpgrade}` | Logic | Update or Upgrade | Update |
| `{titleMessageUpdateOrUpgrade:l}` | Logic | Lowercase variant | update |
| `{softwareUpdateButtonText}` | Logic | Expected button label | Update Now |
| `{uptimeHumanReadable}` | System | Time since restart | 5 days |
| `{diskSpaceHumanReadable}` | System | Free space | 128.5 GB (45.2% available) |
| `{updateReadyMessage}` | Logic | Staging status | [Staged update message] |
| `{excessiveUptimeWarningMessage}` | Logic | Uptime warning | [Warning if triggered] |
| `{diskSpaceWarningMessage}` | Logic | Disk space warning | [Warning if triggered] |
| `{supportTeamName}` | Config | Support team | IT Support |
| `{supportTeamPhone}` | Config | Phone number | +1 (555) 123-4567 |
| `{supportTeamEmail}` | Config | Email | helpdesk@company.com |
| `{supportTeamWebsite}` | Config | Website URL | https://support.company.com |
| `{supportKBURL}` | Config | KB article link | [Link text](URL) |
| `{button1text}` | Config | Primary button | Open Software Update |
| `{button2text}` | Config | Secondary button | Remind Me Later |
| `{infobuttonaction}` | Config | Info button URL | https://support.apple.com/... |
| `{dialogVersion}` | System | swiftDialog version | 2.5.6 |
| `{scriptVersion}` | System | Script version | 2.3.0 |

### Placeholder Modifiers

#### Lowercase Modifier: `:l`
Converts placeholder value to lowercase.

**Example**:
```
{titleMessageUpdateOrUpgrade} → "Update"
{titleMessageUpdateOrUpgrade:l} → "update"
```

**Usage**: For grammatically correct sentences

### Multi-Pass Resolution

Placeholders can reference other placeholders. The script resolves them in multiple passes (up to 5) until all are replaced.

**Example**:
```
supportTeamInfo = "{supportTeamName} - {supportTeamPhone}"
message = "Contact {supportTeamInfo}"
```

**Resolves to**: `Contact IT Support - +1 (555) 123-4567`

---

## Common Configuration Scenarios

### Scenario 1: Conservative Deployment (Minimal Disruption)

**Goal**: Later reminders, shorter urgent period, less intrusive

```xml
<key>DaysBeforeDeadlineDisplayReminder</key>
<integer>30</integer>
<key>DaysBeforeDeadlineBlurscreen</key>
<integer>14</integer>
<key>DaysBeforeDeadlineHidingButton2</key>
<integer>7</integer>
```

**Timeline**:
- Day -30: First reminder
- Day -14: Blurscreen activates
- Day -7: Button 2 disabled

---

### Scenario 2: Aggressive Deployment (Maximum Warning)

**Goal**: Earlier reminders, longer urgent period, maximum visibility

```xml
<key>DaysBeforeDeadlineDisplayReminder</key>
<integer>90</integer>
<key>DaysBeforeDeadlineBlurscreen</key>
<integer>60</integer>
<key>DaysBeforeDeadlineHidingButton2</key>
<integer>30</integer>
```

**Timeline**:
- Day -90: First reminder (3 months early)
- Day -60: Blurscreen activates (2 months)
- Day -30: Button 2 disabled (1 month)

---

### Scenario 3: Balanced Deployment (Default)

**Goal**: Reasonable warning with progressive urgency

```xml
<key>DaysBeforeDeadlineDisplayReminder</key>
<integer>60</integer>
<key>DaysBeforeDeadlineBlurscreen</key>
<integer>45</integer>
<key>DaysBeforeDeadlineHidingButton2</key>
<integer>21</integer>
```

**Timeline**:
- Day -60: First reminder (2 months)
- Day -45: Blurscreen activates (1.5 months)
- Day -21: Button 2 disabled (3 weeks)

---

### Scenario 4: Minimal Branding (Text Only)

**Goal**: Simple deployment without custom icons/branding

```xml
<!-- Hide overlay icon -->
<key>OrganizationOverlayIconURL</key>
<string></string>

<!-- Simple support info -->
<key>SupportTeamName</key>
<string>IT</string>
<key>SupportTeamPhone</key>
<string>x1234</string>

<!-- Hide info button -->
<key>InfoButtonText</key>
<string>hide</string>

<!-- Hide help image -->
<key>HelpImage</key>
<string>hide</string>
```

---

### Scenario 5: Full Branding (Complete Customization)

**Goal**: Fully branded with organization identity

```xml
<!-- Custom icon -->
<key>OrganizationOverlayIconURL</key>
<string>https://cdn.company.com/it-icon.png</string>

<!-- Complete support details -->
<key>SupportTeamName</key>
<string>Enterprise IT Services</string>
<key>SupportTeamPhone</key>
<string>+1 (800) 555-HELP</string>
<key>SupportTeamEmail</key>
<string>itsupport@company.com</string>
<key>SupportTeamWebsite</key>
<string>https://helpdesk.company.com</string>

<!-- Custom KB article -->
<key>InfoButtonAction</key>
<string>https://kb.company.com/macos-updates</string>
<key>SupportKBURL</key>
<string>[macOS Update Guide](https://kb.company.com/updates)</string>

<!-- Custom messaging -->
<key>Title</key>
<string>Company Policy: macOS {ddmVersionString} Required</string>
```

---

### Scenario 6: Dark Mode Support (Appearance-Aware Branding)

**Goal**: Optimal icon visibility in both Light and Dark appearance modes

```xml
<!-- Standard light mode icon -->
<key>OrganizationOverlayIconURL</key>
<string>https://cdn.company.com/it-icon-light.png</string>

<!-- Dark mode optimized icon -->
<key>OrganizationOverlayIconURLdark</key>
<string>https://cdn.company.com/it-icon-dark.png</string>

<!-- Optional: swap icon position for better visibility -->
<key>SwapOverlayAndLogo</key>
<false/>
```

**Behavior**:
- Automatically detects user's System Settings > Appearance mode
- Light Mode or Auto (when light): Uses light icon
- Dark Mode or Auto (when dark): Uses dark icon
- Respects empty dark URL by falling back to light icon

**Testing**:
1. Test in Light Mode: System Settings > Appearance > Light
2. Test in Dark Mode: System Settings > Appearance > Dark
3. Test in Auto Mode: Toggle between light/dark times

---

### Scenario 7: User-Friendly (Helpful Context)

**Goal**: Maximum user assistance and transparency

```xml
<!-- Show staging information -->
<key>HideStagedUpdateInfo</key>
<false/>

<!-- Enable uptime warnings -->
<key>DaysOfExcessiveUptimeWarning</key>
<integer>7</integer>

<!-- Enable disk space warnings -->
<key>MinimumDiskFreePercentage</key>
<integer>20</integer>

<!-- Generous meeting delay -->
<key>MeetingDelay</key>
<integer>120</integer>
```

---

## Configuration Methods

### Method 1: Configuration Profile (Managed Preferences)

**Priority**: Highest (overrides all others)  
**Deployment**: Via MDM  
**Modifiable**: No (enforced by MDM)

**When to Use**:
- Organization-wide enforcement
- Compliance requirements
- Large deployments (100+ devices)
- Preventing local modifications

**Example**: See [sample.plist](../Resources/sample.plist) and use `assemble.zsh` to generate .mobileconfig

**Deploying in Jamf Pro**:
1. Upload .mobileconfig to Configuration Profiles
2. Scope to target computers
3. Deploy

**Deploying in Intune**:
1. Devices → macOS → Configuration profiles
2. Import .mobileconfig
3. Assign to devices

---

### Method 2: Local Preferences

**Priority**: Medium (overridden by managed preferences)  
**Deployment**: Manual or via script  
**Modifiable**: Yes (with admin privileges)

**When to Use**:
- Testing before MDM deployment
- Small deployments (<10 devices)
- Site-specific overrides
- Development/testing

**Bulk Configuration Script**:
```bash
#!/bin/bash

PLIST="/Library/Preferences/org.churchofjesuschrist.dorm"

# Timing
sudo defaults write "$PLIST" DaysBeforeDeadlineDisplayReminder -int 60
sudo defaults write "$PLIST" DaysBeforeDeadlineBlurscreen -int 45
sudo defaults write "$PLIST" DaysBeforeDeadlineHidingButton2 -int 21

# Support
sudo defaults write "$PLIST" SupportTeamName -string "IT Support"
sudo defaults write "$PLIST" SupportTeamPhone -string "+1 (555) 123-4567"
sudo defaults write "$PLIST" SupportTeamEmail -string "help@company.com"

# Branding
sudo defaults write "$PLIST" OrganizationOverlayIconURL -string "https://cdn.company.com/icon.png"
sudo defaults write "$PLIST" SwapOverlayAndLogo -bool NO
```

---

### Method 3: Script Defaults

**Priority**: Lowest (fallback only)  
**Deployment**: Embedded in script  
**Modifiable**: Only by re-customizing and re-assembling script

**When to Use**:
- Establishing baseline values
- Ensuring script always has valid configuration
- One-time deployment without ongoing management

**Customization Location**: [reminderDialog.zsh](../reminderDialog.zsh) lines ~150-210

**Format**:
```bash
declare -A preferenceConfiguration=(
    ["variableName"]="type|defaultValue"
)
```

---

### Method 4: Hybrid Approach (Recommended)

**Strategy**: Combine all three methods

1. **Script Defaults**: Sensible baseline values
2. **Configuration Profile**: Enforce critical settings (timing, branding)
3. **Local Preferences**: Testing and site-specific overrides

**Example**:
```
Script Default: DaysBeforeDeadlineDisplayReminder = 60
Config Profile: DaysBeforeDeadlineDisplayReminder = 45 (enforced org-wide)
Test Mac Local: DaysBeforeDeadlineDisplayReminder = 7 (testing only)

Production Macs: Use 45 (from profile)
Test Mac: Use 7 (local override for testing)
```

---

## Troubleshooting

### Variables Not Taking Effect

**Problem**: Changed preference but dialog still shows old value

**Diagnosis**:
```bash
# Check managed preferences
sudo /usr/libexec/PlistBuddy -c "Print :DaysBeforeDeadlineDisplayReminder" \
    /Library/Managed\ Preferences/org.churchofjesuschrist.dorm.plist

# Check local preferences
sudo /usr/libexec/PlistBuddy -c "Print :DaysBeforeDeadlineDisplayReminder" \
    /Library/Preferences/org.churchofjesuschrist.dorm.plist

# Check which was loaded
grep "Reading preference overrides" /var/log/org.churchofjesuschrist.log
```

**Solution**: Remember precedence order: Managed → Local → Default

---

### Type Mismatch Errors

**Problem**: Preference not loading due to wrong data type

**Common Mistakes**:
```xml
<!-- WRONG: Integer as string -->
<key>DaysBeforeDeadlineDisplayReminder</key>
<string>60</string>

<!-- CORRECT: Integer as integer -->
<key>DaysBeforeDeadlineDisplayReminder</key>
<integer>60</integer>

<!-- WRONG: Boolean as string -->
<key>SwapOverlayAndLogo</key>
<string>YES</string>

<!-- CORRECT: Boolean as boolean -->
<key>SwapOverlayAndLogo</key>
<true/>
```

**Validation**:
```bash
# Validate plist syntax
plutil -lint /path/to/config.plist

# Check data types
plutil -p /path/to/config.plist
```

---

### Placeholder Not Resolving

**Problem**: Placeholder appears as literal text in dialog

**Causes**:
1. Typo in placeholder name (case-sensitive)
2. Placeholder not available in that context
3. Multi-pass resolution limit reached (>5 levels deep)

**Diagnosis**:
```bash
# Check script logs for placeholder resolution
grep "replacePlaceholders" /var/log/org.churchofjesuschrist.log
```

**Solution**: Verify placeholder spelling and context

---

### Configuration Profile Not Applying

**Problem**: Profile installed but preferences not in managed location

**Diagnosis**:
```bash
# Check profile installation
sudo profiles show

# Check managed preferences directory
ls -la /Library/Managed\ Preferences/

# Verify plist domain matches
cat /Library/Managed\ Preferences/org.churchofjesuschrist.dorm.plist
```

**Solution**: Ensure profile domain matches script's `preferenceDomain` variable

---

### HTML Entities in Dialog

**Problem**: Dialog shows `&lt;br&gt;` instead of line breaks

**Cause**: Configuration Profile requires HTML entity encoding

**Solution**:
```xml
<!-- Encode HTML in Configuration Profile -->
<string>&lt;br&gt;&lt;br&gt;**Bold text**</string>

<!-- Direct plist (if manually creating) can use literal -->
<string><br><br>**Bold text**</string>
```

**Encoding Guide**:
- `<` → `&lt;`
- `>` → `&gt;`
- `&` → `&amp;`
- `"` → `&quot;`

---

### Boolean Values Not Recognized

**Problem**: Boolean preference not working

**Accepted Values**:
- XML: `<true/>` or `<false/>`
- defaults write: `-bool YES` or `-bool NO`
- Script: `"boolean|YES"` or `"boolean|NO"`

**Also Accepted** (normalized by script):
- `1` / `0`
- `true` / `false`
- `YES` / `NO` (case-insensitive)

**Not Accepted**:
- Strings: `"true"`, `"false"`, `"YES"`, `"NO"`

---

## Related Documentation

- [System Architecture](01-system-architecture.md) - Complete ecosystem overview
- [Runtime Decision Tree](02-runtime-decision-tree.md) - How variables affect script logic
- [Deadline Timeline](03-deadline-timeline.md) - Visual representation of timing variables
- [Deployment Workflow](04-deployment-workflow.md) - How to deploy configurations
- [Configuration Hierarchy](05-configuration-hierarchy.md) - Preference precedence system

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.3.0 | 2026-01-19 | Initial configuration reference documentation |

---

**Last Updated**: January 19, 2026  
**DDM OS Reminder Version**: 2.3.0  
**Variables Documented**: 31 configurable preferences
