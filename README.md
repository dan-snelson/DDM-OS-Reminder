![GitHub release (latest by date)](https://img.shields.io/github/v/release/dan-snelson/DDM-OS-Reminder?display_name=tag) ![GitHub pre-release (latest by date)](https://img.shields.io/github/v/release/dan-snelson/DDM-OS-Reminder?display_name=tag&include_prereleases) ![GitHub issues](https://img.shields.io/github/issues-raw/dan-snelson/DDM-OS-Reminder) ![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/dan-snelson/DDM-OS-Reminder) ![GitHub pull requests](https://img.shields.io/github/issues-pr-raw/dan-snelson/DDM-OS-Reminder) ![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed-raw/dan-snelson/DDM-OS-Reminder)


# DDM-OS-Reminder
> A swiftDialog and LaunchDaemon pair for "set-it-and-forget-it" end-user notifications for DDM-required macOS updates


<img src="images/ddmOSReminder_Hero.png" alt="Mac Health Check Hero" width="800"/>

## Overview

While Apple's Declarative Device Management (DDM) provides a powerful way to enforce macOS updates, its built-in notification _tends_ to be too subtle for most Mac Admins:

<img src="images/ddmOSReminder_Notification.png" alt="Built-in macOS Notication" width="300"/>

DDM OS Reminder provides a swiftDialog and LaunchDaemon pair that delivers a more prominent notification to end-users when their Mac needs to be updated to comply with DDM-enforced OS version requirements:

<img src="images/ddmOSReminder_swiftDialog_1.png" alt="DDM OS Reminder" width="800"/>
<img src="images/ddmOSReminder_swiftDialog_2.png" alt="DDM OS Reminder" width="800"/>

## Features
- **Set-it-and-forget-it**: Once installed, the LaunchDaemon will automatically check the Mac's OS version against the DDM-enforced minimum OS version twice daily and display the swiftDialog notification if an update is required.
- **Customizable**: Easily customize the swiftDialog notification's title, message, icon, and button text to fit your organization's needs.
- **Deadline Awareness**: If a DDM-enforced OS version deadline is set, the notification will include a countdown to the deadline, creating a sense of urgency for end-users to update their Macs.
- **Tastefully Intrusive**: The notification is designed to be informative without being overly disruptive, allowing users to continue their work while being reminded of the need to update.
- **Easy Installation**: The script can be easily deployed via MDM solutions, making it simple to roll out across an organization.
- **Logging**: The script logs its actions to a specified log file, allowing administrators to monitor its activity and troubleshoot if necessary.

## Deployment
[Continue reading …](https://snelson.us/ddm-os-reminder/)