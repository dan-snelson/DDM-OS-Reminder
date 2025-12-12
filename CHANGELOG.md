# DDM OS Reminder

## Changelog

### Version 2.1.0b9 (11-Dec-2025)
- Added ability to use `titleMessageUpdateOrUpgrade:l` (Pull Request #26; thanks, @maxsundellacne!)
- Added logic to hide `button2` based on `DaysBeforeDeadlineHidingButton2` (Pull Request #27; thanks, @maxsundellacne!)
- Refactored `resetConfiguration` function to avoid errors when attempting to `chmod` non-existent files
- Added warning for excessive uptime (configurable via `DaysOfExcessiveUptimeWarning` variable; #28)
- Added logic for when the reminder dialog is re-displayed after clicking the `infobutton` (based on if we're already hiding the secondary button; #31)
- Moved and renamed [`sample.plist`](Resources/sample.plist)
- Streamline Deployment & Documentation (Feature Request #35)
- Addressed Bugs #34 (thanks, @TechTrekkie!) and #36 (I. Blame. AI.)
- Refactored `assemble.zsh` (thanks for the feedback, @Andrew!)

### Version 2.0.0 (06-Dec-2025)
- Reorganized script structure for (hopefully) improved clarity
- Defined `swiftDialogMinimumRequiredVersion` (Addresses #16; thanks for the heads-up, @deski-arnaud!)
- Refactored `displayReminderDialog` function's Exit Code `3` to re-display dialog after 61 seconds when infobutton (i.e., KB) is clicked (Inspired by Pull Request: #20; thanks, @TazNZ!)
- Refactored `daysBeforeDeadlineBlurscreen` logic to use seconds (instead of days) for more precise control (thanks for the suggestion, @Ancaeus!)
- Added a "demo" mode to the `reminderDialog.zsh` script for testing purposes (thanks for the suggestion, Max S!)
- Added ability to read variables from `.plist` (Pull Request #22; thanks, Obi-@maxsundellacne!)

### Version 1.4.0 (18-Nov-2025)
- (Reluctantly) added swiftDialog installation detection
- Added `meetingDelay` variable to pause reminder display until meeting has completed (Issue #14; thanks for the suggestion, @sabanessts!)
- Added `Resources/createSelfExtracting.zsh` script to create self-extracting version of assembled script
- Updated `Resources/README.md` to include "Assemble DDM OS Reminder" and "Create Self-extracting Script" instructions
- Re-re-refactored `installedOSvsDDMenforcedOS` to include @rgbpixel's recent discovery of `setPastDuePaddedEnforcementDate` (thanks again, @rgbpixel!)
- Added `daysBeforeDeadlineDisplayReminder` variable to better align with — or supersede — Apple's behavior of when reminders begin displaying before DDM-enforced deadline (thanks for the suggestion, @kristian!)
- Added `Resources/JamfEA-DDM_Executed_OS_Update_Date.zsh` script to report the date when the DDM-enforced macOS update was executed
- Removed placeholder `DDM-OS-Reminder End-user Message.zsh` from `ddmOSReminder.zsh`; use `Resources/assembleDDMOSReminder.zsh` to assemble your organization's customized script instead

### Version 1.3.0 (09-Nov-2025)
- Refactored `installedOSvsDDMenforcedOS` to better reflect the actual DDM-enforced restart date and time for past-due deadlines (thanks for the suggestion, @rgbpixel!)
- Refactored logged-in user detection
- Added fail-safe to make sure System Settings is brought to the forefront (Pull Request #12; thanks, @techtrekkie!)
- Corrected an errant `mkdir` command that created an unnecessary nested directory (thanks for the heads-up, @jonathanchan!)
- Improved "Uninstall" behavior in `resetConfiguration` function to remove empty `organizationDirectory` (thanks for the suggestion, @Lab5!)

### Version 1.2.0 (20-Oct-2025)
- Addressed Issue #3: Use Dynamic icon based on OS Update version (thanks for the suggestion, @ScottEKendall!)
- Addressed Issue #5: Added logic to ignore Display Assertions 24 hours prior to enforcement (per [Apple's documentation](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/1/web/1.0))
- Added `softwareUpdateButtonText` variable, based on a minor-version "update" vs. a major-version "upgrade"
- Added `titleMessageUpdateOrUpgrade` variable for dynamic dialog title and message content

### Version 1.1.0 (16-Oct-2025)
> :warning: **Breaking Change** :warning:
>
> For users of version `1.0.0` _only_, please first uninstall version `1.0.0` **before** installing any later version via:
> 
> `resetConfiguration="${4:-"Uninstall"}"`
>
> Please feel free to reach out to the Mac Admins Slack [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel for assistance.
> 
> _Sorry for any Dan-induced headaches._

- Added `checkUserFocusDisplayAssertions` function to avoid interrupting users with Display Sleep Assertions enabled (thanks, @TechTrekkie!)
- Refactored `infobuttonaction` to disable blurscreen (Pull Request #2; thanks, @TechTrekkie!)
- Updated `message` variable to clarify update instructions
- Tweaked `updateScriptLog` function to satisfy my CDO (i.e., the alphabetical version of "OCD")

### Version 1.0.0 (14-Oct-2025)
- First "official" release (thanks for the testing and feedback, @TechTrekkie!)