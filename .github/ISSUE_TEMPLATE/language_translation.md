---
name: Language Translation
about: Contribute a new language or improve an existing translation for DDM OS Reminder
title: 'Language Translation: [Language Name]'
labels: localization
assignees: dan-snelson

---

> **No Pull Request needed.** Simply fill out this form and the maintainer will apply your contribution directly. (See:[Language Translation: Italian](https://github.com/dan-snelson/DDM-OS-Reminder/issues/89) for an example of a completed issue.)
> 
> You're also welcome to discuss via the [Mac Admins Slack](https://www.macadmins.org/) (free, registration required) [#ddm-os-reminders Channel](https://slack.com/app_redirect?channel=C09LVE2NVML).

---

**Language**

What language are you contributing? (e.g., `Italian`, `Swedish`, `Polish`)

Examples: `en` `de` `fr` `es` `it` `nl` `pt` `ja`
The script auto-detects any additional language present in the plist. No script edits are required.

Are you adding a **new** language or **improving** an existing one?

---

**Instructions**

1. Download [`Resources/sample.plist`](https://raw.githubusercontent.com/dan-snelson/DDM-OS-Reminder/main/Resources/sample.plist) from the `main` branch.
2. For every key ending in `_Localized_en`, add a matching key with your language code suffix (e.g., `_Localized_it`), with the translated value — following the `_Localized_de` / `_Localized_fr` pattern already in the file.
3. To preview your translation, set `LanguageOverride` to your language code in a local copy of the plist (e.g., `it`) and place it in one of the script's supported preference locations:
   - `/Library/Managed Preferences/org.churchofjesuschrist.dorm.plist`
   - `/Library/Preferences/org.churchofjesuschrist.dorm.plist`
4. Run demo mode to verify your strings render correctly:
```zsh
zsh reminderDialog.zsh demo
```
5. Paste your complete, updated `sample.plist` in the code block at the bottom of this form.

---

**Demo Screenshot (REQUIRED)**

Attach at least one screenshot of `zsh reminderDialog.zsh demo` running with your translated language active.

> ⚠️ Issues submitted without a demo screenshot will be closed.

<!-- Drag and drop your screenshot(s) here -->

---

**Updated `Resources/sample.plist`**

Paste your complete, updated `sample.plist` below (the full file, not just the changed keys):

```xml
<!-- Paste your complete Resources/sample.plist here -->
```

---

**Translation Notes** *(optional)*

Note any translation decisions, formality register choices, character set considerations, or strings that don't translate cleanly:
