# DDM OS Reminder

## Changelog

### Version 1.3.0 (23-Oct-2025)
- Refactored `installedOSvsDDMenforcedOS` to better reflect the actual DDM-enforced restart date and time for past-due deadlines (thanks for the suggestion, @rgbpixel!)

### Version 1.2.0 (20-Oct-2025)

> :warning: **Breaking Change** :warning:
>
> For users of version `1.0.0` _only_, please first uninstall version `1.0.0` **before** installing any later version via:
> 
> `resetConfiguration="${4:-"Uninstall"}"`
>
> Please feel free to reach out to the Mac Admins Slack [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel for assistance.
> 
> _Sorry for any Dan-induced headaches._

- Addressed Issue #3: Use Dynamic icon based on OS Update version (thanks for the suggestion, @ScottEKendall!)
- Addressed Issue #5: Added logic to ignore Display Assertions 24 hours prior to enforcement (per [Apple's documentation](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/1/web/1.0))
- Added `softwareUpdateButtonText` variable, based on a minor-version "update" vs. a major-version "upgrade"
- Added `titleMessageUpdateOrUpgrade` variable for dynamic dialog title and message content

### Version 1.1.0 (16-Oct-2025)
- Added `checkUserFocusDisplayAssertions` function to avoid interrupting users with Display Sleep Assertions enabled (thanks, @TechTrekkie!)
- Refactored `infobuttonaction` to disable blurscreen (Pull Request #2; thanks, @TechTrekkie!)
- Updated `message` variable to clarify update instructions
- Tweaked `updateScriptLog` function to satisfy my CDO (i.e., the alphabetical version of "OCD")

### Version 1.0.0 (14-Oct-2025)
- First "official" release (thanks for the testing and feedback, @TechTrekkie!)