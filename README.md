![GitHub release (latest by date)](https://img.shields.io/github/v/release/dan-snelson/DDM-OS-Reminder?display_name=tag) ![GitHub pre-release (latest by date)](https://img.shields.io/github/v/release/dan-snelson/DDM-OS-Reminder?display_name=tag&include_prereleases) ![GitHub issues](https://img.shields.io/github/issues-raw/dan-snelson/DDM-OS-Reminder) ![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/dan-snelson/DDM-OS-Reminder) ![GitHub pull requests](https://img.shields.io/github/issues-pr-raw/dan-snelson/DDM-OS-Reminder) ![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed-raw/dan-snelson/DDM-OS-Reminder)

# DDM OS Reminder
> Yet another maintenance release of Mac Admins’ new favorite, MDM-agnostic, **“set-it-and-forget-it”** end-user reminder for Apple’s Declarative Device Management-enforced macOS update deadlines, with a new **allowlist for more robust meeting detection**, **dark‑mode overlay icon support**, and **enhanced error checking**.

<img src="images/ddmOSReminder_Hero.png" alt="Mac Admins’ new favorite for “set-it-and-forget-it” end-user messaging of Apple’s Declarative Device Management-enforced macOS update deadlines" width="800"/>

## Overview

While Apple’s Declarative Device Management (DDM) provides Mac Admins with a powerful way to _enforce_ macOS updates, its built-in notification is often _too subtle_ for most administrators:
<br/>
<img src="images/before.jpg" alt="macOS built-in Notification" width="400" /> <img src="images/after.jpg" alt="DDM OS Reminder" width="400" />

**DDM OS Reminder** evaluates the most recent `EnforcedInstallDate` and `setPastDuePaddedEnforcementDate` entries in `/var/log/install.log`, then leverages a [swiftDialog](https://github.com/swiftDialog/swiftDialog/wiki)-enabled script plus a LaunchDaemon to deliver a more prominent end-user dialog that reminds users to update their Mac to comply with DDM-enforced macOS update deadlines.

<img src="images/ddmOSReminder_swiftDialog_1.png" alt="DDM OS Reminder evaluates the most recent `EnforcedInstallDate` entry in `/var/log/install.log`" width="800"/>
<img src="images/ddmOSReminder_swiftDialog_2.png" alt="IT Support information is just a click away …" width="800"/>

## Features

<img src="images/ddmOSReminder_Hero_2.png" alt="Mac Admins can configure `daysBeforeDeadlineBlurscreen` to control how many days before the DDM-specified deadline the screen blurs when displaying your customized message" width="800"/>

> Mac Admins can configure `daysBeforeDeadlineBlurscreen` to control how many days before the DDM-specified deadline the screen blurs when displaying your customized reminder dialog

- **Customizable**: Easily customize the reminder dialog’s title, message, icons (including light/dark overlay icons) and button text to fit your organization’s requirements by distributing a Configuration Profile via any MDM solution.
- **Multi-language Ready**: Optionally configure localized profile keys (`*_Localized_en`, `*_Localized_de`, `*_Localized_fr`) and let the script auto-select by logged-in user language, with optional `LanguageOverride`; unsupported locales normalize to English, and missing localized fields fall back to the scalar key.
- **Easy Installation**: The [assemble.zsh](assemble.zsh) script makes it easy to deploy your reminder dialog and display frequency customizations via any MDM solution, enabling quick rollout of DDM OS Reminder organization-wide.
- **Set-it-and-forget-it**: Once configured and installed, a LaunchDaemon displays your customized reminder dialog — automatically checking the installed macOS version against the DDM-required version — to remind users if an update is required.
- **Deadline Awareness**: Whenever a DDM-enforced macOS version or its deadline is updated via your MDM solution, the reminder dialog dynamically updates the countdown to both the deadline and required macOS version to drive timely compliance.
- **Intelligently Intrusive**: The reminder dialog is designed to be informative without being disruptive, first checking whether a user is in an online meeting — via an allowlist of approved apps — before displaying the dialog, so users can remain productive while still being reminded to update.
- **Logging**: The script logs its actions to your specified log file, allowing Mac Admins to monitor its activity and troubleshoot as necessary.
- **Demonstration Mode**: A built-in `demo` mode allows Mac Admins to test the appearance and functionality of the reminder dialog with ease: `zsh reminderDialog.zsh demo`.

> Version `3.0.0`, currently in its first _alpha_ release, will support multiple languages:

<img width="333" alt="Screenshot 2026-02-07 at 7 12 10 PM" src="https://github.com/user-attachments/assets/174b20e8-834c-4345-a978-1ce93f6ee362" />
<img width="333" alt="Screenshot 2026-02-07 at 7 11 36 PM" src="https://github.com/user-attachments/assets/8929227c-5b6d-4198-90f3-02e99cd147c6" />
<img width="333" alt="Screenshot 2026-02-07 at 7 11 11 PM" src="https://github.com/user-attachments/assets/860667bb-8fd1-41a9-b834-afd59d04faf4" />

## Support

Community-supplied, best-effort support is available on the [Mac Admins Slack](https://www.macadmins.org/) (free, registration required) [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel, or you can open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).

See also: [Diagrams/README.md](Diagrams/README.md) for architecture and sequence diagrams.

## What’s New
See [CHANGELOG](CHANGELOG.md) for a detailed list of changes and improvements.

## Deployment
[Continue reading on snelson.us …](https://snelson.us/ddm)
