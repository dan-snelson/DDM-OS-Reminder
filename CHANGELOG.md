# DDM OS Reminder

## Changelog

### Version 1.2.0 (16-Oct-2025)
> :warning: **Breaking Change** :warning:
>
> For users of version `1.0.0`, please first uninstall version `1.0.0` **before** installing any later version via:
> 
> `resetConfiguration="${4:-"Uninstall"}"`
>
> Please feel free to reach out to the Mac Admins Slack [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel for assistance.
> 
> _Sorry for any Dan-induced headaches._
- Addressed Issue #3: Use Dynamic icon based on OS Update version (thanks for the suggestion, @ScottEKendall!)

### Version 1.1.0 (16-Oct-2025)
- Added `checkUserFocusDisplayAssertions` function to avoid interrupting users with Focus modes or Display Sleep Assertions enabled (thanks, @TechTrekkie!)
- Refactored `infobuttonaction` to disable blurscreen (Pull Request #2; thanks, @TechTrekkie!)
- Updated `message` variable to clarify update instructions
- Tweaked `updateScriptLog` function to satisfy my CDO (i.e., the alphabetical version of "OCD")

### Version 1.0.0 (14-Oct-2025)
- First "official" release (thanks for the testing and feedback, @TechTrekkie!)