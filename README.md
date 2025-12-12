![GitHub release (latest by date)](https://img.shields.io/github/v/release/dan-snelson/DDM-OS-Reminder?display_name=tag) ![GitHub pre-release (latest by date)](https://img.shields.io/github/v/release/dan-snelson/DDM-OS-Reminder?display_name=tag&include_prereleases) ![GitHub issues](https://img.shields.io/github/issues-raw/dan-snelson/DDM-OS-Reminder) ![GitHub closed issues](https://img.shields.io/github/issues-closed-raw/dan-snelson/DDM-OS-Reminder) ![GitHub pull requests](https://img.shields.io/github/issues-pr-raw/dan-snelson/DDM-OS-Reminder) ![GitHub closed pull requests](https://img.shields.io/github/issues-pr-closed-raw/dan-snelson/DDM-OS-Reminder)

# DDM OS Reminder
> A maintenance release to Mac Admins’ new favorite, MDM-agnostic, **“set-it-and-forget-it”** end-user reminder for Apple’s Declarative Device Management-enforced macOS update deadlines **that further simplifies enterprise-wide deployment**

<img src="images/ddmOSReminder_Hero.png" alt="Mac Admins’ new favorite for “set-it-and-forget-it” end-user messaging of Apple’s Declarative Device Management-enforced macOS update deadlines" width="800"/>

## Overview

While Apple’s Declarative Device Management (DDM) provides Mac Admins a powerful way to _enforce_ macOS updates, its built-in notification is often _too subtle_ for most administrators:

<div class="image-compare-container" style="max-width: 800px; margin: 20px auto;">
  <div class="image-compare">
    <img src="images/before.jpg" alt="Before" class="img-before">
    <img src="images/after.jpg" alt="After" class="img-after">
    <div class="divider"></div>
    <div class="slider"></div>
  </div>
</div>

<style>
.image-compare {
  position: relative;
  display: inline-block;
  width: 100%;
  height: 500px; /* Adjust to your image height */
  overflow: hidden;
  border-radius: 8px;
  box-shadow: 0 4px 8px rgba(0,0,0,0.1);
}
.img-before, .img-after {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.divider {
  position: absolute;
  top: 0;
  left: 50%;
  width: 2px;
  height: 100%;
  background: #fff;
  box-shadow: 0 0 10px rgba(0,0,0,0.5);
  z-index: 2;
  transform: translateX(-50%);
}
.slider {
  position: absolute;
  top: 0;
  left: 50%;
  width: 40px;
  height: 40px;
  margin-left: -20px;
  background: #fff;
  border-radius: 50%;
  cursor: ew-resize;
  z-index: 3;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 2px 5px rgba(0,0,0,0.3);
  user-select: none;
}
.slider::after {
  content: '↔';
  font-size: 16px;
  color: #333;
}
</style>

<script>
document.addEventListener('DOMContentLoaded', function() {
  const container = document.querySelector('.image-compare');
  const slider = container.querySelector('.slider');
  const divider = container.querySelector('.divider');
  let isDragging = false;

  // Initial position
  let position = 50;

  function updatePosition(e) {
    if (!isDragging) return;
    const rect = container.getBoundingClientRect();
    const x = ((e.clientX || e.touches[0].clientX) - rect.left) / rect.width * 100;
    position = Math.max(0, Math.min(100, x));
    divider.style.left = position + '%';
    container.querySelector('.img-after').style.width = position + '%';
    slider.style.left = position + '%';
  }

  // Mouse events
  slider.addEventListener('mousedown', () => { isDragging = true; });
  document.addEventListener('mousemove', updatePosition);
  document.addEventListener('mouseup', () => { isDragging = false; });

  // Touch events for mobile
  slider.addEventListener('touchstart', () => { isDragging = true; });
  document.addEventListener('touchmove', updatePosition);
  document.addEventListener('touchend', () => { isDragging = false; });

  // Initial update
  updatePosition({ clientX: 0 });
});
</script>

**DDM OS Reminder** evaluates the most recent `EnforcedInstallDate` and `setPastDuePaddedEnforcementDate` entries in `/var/log/install.log`, then leverages a [swiftDialog](https://github.com/swiftDialog/swiftDialog/wiki)-enabled script plus a LaunchDaemon to deliver a more prominent end-user dialog that reminds users to update their Mac to comply with DDM-enforced macOS update deadlines.

<img src="images/ddmOSReminder_swiftDialog_1.png" alt="DDM OS Reminder evaluates the most recent `EnforcedInstallDate` entry in `/var/log/install.log`" width="800"/>
<img src="images/ddmOSReminder_swiftDialog_2.png" alt="IT Support information is just a click away …" width="800"/>

## Features

<img src="images/ddmOSReminder_Hero_2.png" alt="Mac Admins can configure `daysBeforeDeadlineBlurscreen` to control how many days before the DDM-specified deadline the screen blurs when displaying your customized message" width="800"/>

> Mac Admins can configure `daysBeforeDeadlineBlurscreen` to control how many days before the DDM-specified deadline the screen blurs when displaying your customized reminder dialog

- **Customizable**: Easily customize the reminder dialog's title, message, icons and button text to fit your organization’s requirements by distributing a Configuration Profile via any MDM solution.
- **Easy Installation**: The [assemble.zsh](assemble.zsh) script makes it easy to deploy your reminder dialog and display frequency customizations via any MDM solution, enabling quick rollout of DDM OS Reminder organization-wide.
- **Set-it-and-forget-it**: Once configured and installed, a LaunchDaemon displays your customized reminder dialog — automatically checking the installed macOS version against the DDM-required version — to remind users if an update is required.
- **Deadline Awareness**: Whenever a DDM-enforced macOS version or its deadline is updated via your MDM solution, the reminder dialog dynamically updates the countdown to both the deadline and required macOS version to drive timely compliance.
- **Intelligently Intrusive**: The reminder dialog is designed to be informative without being disruptive — it checks whether a user is in an online meeting before displaying — so users can remain productive while still being reminded to update.
- **Logging**: The script logs its actions to your specified log file, allowing Mac Admins to monitor its activity and troubleshoot as necessary.
- **Demonstration Mode**: A built-in `demo` mode allows Mac Admins to test the appearance and functionality of the reminder dialog with ease: `zsh reminderDialog.zsh demo`

<img src="images/ddmOSReminder_Demo.png" alt="A built-in 'demo' mode allows Mac Admins to test the appearance and functionality of the reminder dialog with ease." width="500"/>

## Support

Community-supplied, best-effort support is available on the [Mac Admins Slack](https://www.macadmins.org/) (free, registration required) [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel, or you can open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).

## What’s New
See the [CHANGELOG](CHANGELOG.md) for a detailed list of changes / improvements.

## Deployment
[Continue reading on snelson.us …](https://snelson.us/ddm)