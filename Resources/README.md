# DDM OS Reminder

## Resources

While the following Extension Attributes were created for and tested on Jamf Pro, they most likely can be adapted to other MDMs. (For adaptation assistance, help is available on the [Mac Admins Slack](https://www.macadmins.org/) [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel, or you can open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).)

- [JamfEA-DDM-OS-Reminder-User-Clicks.zsh](JamfEA-DDM-OS-Reminder-User-Clicks.zsh): Reports the user's button clicks for the DDM OS Reminder message.
```
2025-10-23 02:53:37 dan clicked Remind Me Later
2025-10-23 02:55:28 dan clicked Open Software Update
2025-10-23 03:01:11 dan clicked Remind Me Later
2025-10-23 03:11:32 dan clicked Remind Me Later
2025-10-23 03:48:27 dan clicked KB0054571
```

- [JamfEA-Pending_OS_Update_Date.zsh](JamfEA-Pending_OS_Update_Date.zsh): Reports the date of a pending DDM-enforced macOS update.
```
2025-10-28 12:00:00
```

- [JamfEA-Pending_OS_Update_Version.zsh](JamfEA-Pending_OS_Update_Version.zsh): Reports the version of a pending DDM-enforced macOS update.
```
26.1
```