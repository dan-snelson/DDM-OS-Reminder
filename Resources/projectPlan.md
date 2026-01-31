# Project Plan

## [DDM-OS-Reminder](https://snelson.us/ddm)

**Author**: Dan K. Snelson
**Date**: 2026-01-31
**Version**: 2.3.1b1
**Status**: In Progress

---

## Executive Summary

**Problem Statement**: While Apple’s Declarative Device Management (DDM) provides Mac Admins a powerful way to **enforce** macOS updates, its [built-in notification](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/1/web/1.0#dep285036967) is often _too subtle_ for most administrators.

<img src="../images/before.jpg" alt="Apple’s built-in notification" width="500"/>

**One-sentence Description**: DDM-OS-Reminder prominently reminds macOS users when their computer will install a DDM-enforced OS update / upgrade.

<img src="../images/after.jpg" alt="DDM-OS-Reminder dialog" width="500"/>

**Target Audience**: IT administrators managing macOS fleets, end-users of managed Macs, and compliance / security teams.

**Primary Value Proposition**: Automated, user-friendly reminders — with actionable prompts — guide end-users to keep their Mac up-to-date.

---


## Project Overview

### Purpose

DDM-OS-Reminder exists to automate the process of prominently reminding users when a macOS computer has a pending OS update / upgrade. It fills the gap of Apple’s much more subtle built-in notification by providing clear, actionable, end-user reminders to help ensure compliance with organizational update policies.

### Goals

1. Detect when a Mac has a pending DDM-enforced macOS update / upgrade.
2. Remind users with a clear, actionable prompt.
3. Provide IT with [reporting](README.md#4-extension-attributes) capabilities.

### Non-Goals

1. Does not **perform** the OS upgrade itself.
2. Does not remind users about non-OS updates / upgrades.
3. Does not support non-macOS platforms.

### Success Criteria

How will we know this project is successful?

- [ ] 95% of eligible devices receive upgrade reminders within 24 hours of eligibility.
- [ ] 80% of users act on reminders within 7 days.
- [ ] IT can generate compliance reports with <5% false positives / negatives.

---


## Use Cases

### Primary Use Cases

#### Use Case 1: Organization’s internal macOS Product Manager approves enterprise-wide upgrade to the latest macOS version with a specific deadline.

**Actor**: Mac Admin (i.e., the individual who manages a fleet of macOS computers)
**Context**: Mac Admin initiates an enterprise-wide DDM-enforced upgrade policy.
**Goal**: All managed Macs receive the declaration to upgrade by the specified deadline.
**Steps**:
1. Mac Admin logs in to MDM portal.
2. Mac Admin configures upgrade policy with deadline.
3. Managed Macs receive the upgrade declaration.

**Expected Outcome**: Managed Macs receive the upgrade declaration; Mac Admin [monitors compliance](./Jamf-getDDMstatusFromCSV.zsh).

#### Use Case 2: End-user’s macOS computer requires an upgrade to the latest macOS version by a specific deadline.

**Actor**: End-user (i.e., the individual to whom an organization’s macOS computer has been assigned)
**Context**: End-user logs in or unlocks computer after it receives an upgrade declaration.
**Goal**: End-user is informed about the available upgrade and prompted to take action.
**Steps**:
1. End-user logs in or unlocks computer.
2. DDM-OS-Reminder confirms applicability for macOS upgrade.
3. If eligible, end-user sees a reminder dialog with upgrade information and options.

**Expected Outcome**: End-user is aware of the upgrade and can choose to upgrade now, defer, or get more info.

### Secondary Use Cases

- End-user requests to defer reminder for a limited time.
### Anti-Use Cases

- Attempting to upgrade OS automatically without user consent.
- Supporting Windows or Linux computers.

---

## Technical Constraints

### Must Have

- MDM-enrolled macOS computers with Declarative Device Management properly configured.
- Endpoint network connectivity to reach MDM server for declaration updates.
- MDM’s [ability to run `zsh` scripts](README.md#2-create-self-extracting-script) with sufficient privileges to check OS update status.
- Mac’s ability to display GUI dialogs to end-users via [swiftDialog](https://swiftdialog.app).

### Assumptions

- MDM server supports DDM and is configured to enforce OS updates.
- Mac Admin has the ability to deploy custom scripts via MDM.
- End-users have basic proficiency with macOS and can interact with dialog prompts.

### Limitations

- Advanced configuration options (e.g., custom alert schedules) are the sole responsibility of the Mac Admin. (See Deployment Flow > 3. Advanced Deployment.)
- Does **not** integrate with macOS Focus Mode / DND state
- Community-supplied, best-effort support is available on the [Mac Admins Slack](https://www.macadmins.org/) (free, registration required) [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel, or you can open an [issue](https://github.com/dan-snelson/DDM-OS-Reminder/issues).

### Dependencies

#### External Dependencies

- [swiftDialog](https://swiftdialog.app) - Display GUI dialogs to end-users (minimum version 2.5.6.4805)

#### Internal Dependencies

- macOS - Required to run the zsh scripts and access system logs
- `/var/log/install.log` - System log containing DDM enforcement information

---

## Architecture & Design

### High-Level Architecture

See: [Diagrams folder](../Diagrams/README.md) for visual representations.

### Core Components

#### Component 1: [reminderDialog.zsh](../reminderDialog.zsh)

**Purpose**: Evaluates the most recent `EnforcedInstallDate` and `setPastDuePaddedEnforcementDate` entries in `/var/log/install.log`, then confirms the end-user is "available" (i.e., not currently in a meeting) before displaying the reminder dialog.

**Responsibilities**:
- Evaluate pending OS upgrade status by parsing `/var/log/install.log`.
- Confirm end-user availability before reminding (checks for meetings via display sleep assertions).
- Track reminder state to avoid redundant prompts via quiet period logic.
- Display customized swiftDialog-based reminder to end-users.

**Key Functions**:
- `installedOSvsDDMenforcedOS()` - Installed OS vs. DDM-enforced OS Comparison
- `checkUserDisplaySleepAssertions()` - Check End-user’s Display Sleep Assertions
- `detectStagedUpdate()` - Detect Staged macOS Updates
- `loadPreferenceOverrides()` - Load preferences from managed or local plist files

**Inputs**:
- Most recent `EnforcedInstallDate` and `setPastDuePaddedEnforcementDate` entries in `/var/log/install.log`
- End-user’s current session status (e.g., active, idle, in a meeting)
- Configuration from managed preferences plist (`/Library/Managed Preferences/${preferenceDomain}.plist`)
- Configuration from local preferences plist (`/Library/Preferences/${preferenceDomain}.plist`)

**Outputs**:
- GUI reminder dialog via `swiftDialog` with customized content
- Log entries to `scriptLog` (default: `/var/log/org.churchofjesuschrist.log`)

#### Component 2: [launchDaemonManagement.zsh](../launchDaemonManagement.zsh)

**Purpose**: Deploys both the `reminderDialog.zsh` script and a LaunchDaemon to the client-side to enable scheduled, automated reminder checks.

**Responsibilities**:
- Create the organization directory structure on the client.
- Write the `reminderDialog.zsh` script to disk at the configured location.
- Create and load the LaunchDaemon which executes the `reminderDialog.zsh` script on a schedule.
- Manage configuration reset and uninstallation when requested.

**Key Functions**:
- `createDDMOSReminderScript()` - Writes `reminderDialog.zsh` to disk at `"${organizationDirectory}/${organizationScriptName}m.zsh"` (note: script name uses "dorm" suffix for "DDM OS Reminder Message")
- `createLaunchDaemon()` - Creates the LaunchDaemon plist which executes the client-side `reminderDialog.zsh` script according to the defined schedule
- `resetConfiguration()` - Configuration Files to Reset (i.e., None (blank) | All | LaunchDaemon | Script | Uninstall)

**Inputs**:
- The `reminderDialog.zsh` script is embedded into `launchDaemonManagement.zsh` by `assemble.zsh` during the build process.
- MDM Script Parameter 4: `resetConfiguration` (default: "All")

**Outputs**:
- The `reminderDialog.zsh` script is saved as `"${organizationDirectory}/${organizationScriptName}m.zsh"` (e.g., `/Library/Management/org.churchofjesuschrist/dorm.zsh`)
- The LaunchDaemon plist is saved as `"/Library/LaunchDaemons/${launchDaemonLabel}.plist"` (e.g., `/Library/LaunchDaemons/org.churchofjesuschrist.dor.plist`)
- LaunchDaemon is loaded via `launchctl bootstrap`

#### Component 3: [assemble.zsh](../assemble.zsh)

**Purpose**: Build automation script that combines `reminderDialog.zsh` and `launchDaemonManagement.zsh` into a single deployable script, with RDNN (Reverse Domain Name Notation) customization.

**Responsibilities**:
- Validate input files exist (base script, message script, sample plist).
- Check and harmonize RDNN between both scripts.
- Prompt for organization-specific RDNN if needed.
- Embed the entire `reminderDialog.zsh` script into `launchDaemonManagement.zsh`.
- Perform syntax validation on assembled script.
- Generate Configuration Profile (.mobileconfig) from sample plist.
- Output all artifacts to the `Artifacts/` directory.

**Key Functions**:
- RDNN validation and harmonization
- Script embedding (heredoc pattern)
- Syntax checking via `zsh -n`
- Plist / Configuration Profile generation

**Inputs**:
- `reminderDialog.zsh` - The end-user message script
- `launchDaemonManagement.zsh` - The deployment/management script
- `Resources/sample.plist` - Template for preferences

**Outputs** (all saved to `Artifacts/` directory):
- Assembled script: `ddm-os-reminder-assembled-<timestamp>.zsh`
- LaunchDaemon plist: `<RDNN>-<timestamp>.plist`
- Configuration Profile: `<RDNN>-<timestamp>-unsigned.mobileconfig`

### Data Model

#### Configuration Preferences

The system uses a hierarchical preference system with the following priority:
1. Managed Preferences (MDM-deployed): `/Library/Managed Preferences/${preferenceDomain}.plist`
2. Local Preferences: `/Library/Preferences/${preferenceDomain}.plist`
3. Hard-coded defaults in script

**Key Configuration Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `ScriptLog` | String | `/var/log/org.churchofjesuschrist.log` | Path to client-side log file |
| `DaysBeforeDeadlineDisplayReminder` | Integer | 14 | Days before deadline to start showing reminders |
| `DaysBeforeDeadlineBlurscreen` | Integer | 3 | Days before deadline to enable blurred background |
| `DaysBeforeDeadlineHidingButton2` | Integer | 1 | Days before deadline to hide/disable "Remind Me Later" button |
| `DaysOfExcessiveUptimeWarning` | Integer | 7 | Days of uptime before showing warning message |
| `MinimumDiskFreePercentage` | Integer | 10 | Minimum free disk space percentage before warning |
| `MeetingDelay` | Integer | 75 | Minutes to delay reminder if user is in a meeting |
| `OrganizationOverlayIconURL` | String | URL | Organization logo overlay on dialog |
| `SwapOverlayAndLogo` | Boolean | false | Swap positions of overlay icon and main logo |
| `Title` | String | Customizable | Dialog title with variable substitution |
| `Message` | String | Customizable | Main dialog message with variable substitution |
| `Button1Text` | String | "Open Software Update" | Primary action button text |
| `Button2Text` | String | "Remind Me Later" | Secondary action button text |
| `InfoButtonText` | String | Customizable | Info button text |
| `InfoBox` | String | Customizable | Right-side information box content |
| `HelpMessage` | String | Customizable | Help dialog content |
| `SupportTeamName` | String | Customizable | IT support team name |
| `SupportTeamPhone` | String | Customizable | IT support phone number |
| `SupportTeamEmail` | String | Customizable | IT support email address |
| `SupportTeamWebsite` | String | Customizable | IT support website URL |
| `HideStagedUpdateInfo` | Boolean | false | Hide staged update messaging |

#### Variable Substitution System

The dialog content supports dynamic variable substitution using the following patterns:
- `{loggedInUserFirstname}` - Current user’s first name
- `{ddmVersionString}` - Required macOS version
- `{ddmEnforcedInstallDateHumanReadable}` - Deadline in human-readable format
- `{ddmVersionStringDaysRemaining}` - Days until deadline
- `{installedmacOSVersion}` - Currently installed macOS version
- `{uptimeHumanReadable}` - Uptime since last restart
- `{diskSpaceHumanReadable}` - Free disk space
- `{titleMessageUpdateOrUpgrade}` - "Update" or "Upgrade" based on context
- `{titleMessageUpdateOrUpgrade:l}` - Lowercase version
- `{button1text}` - Button 1 text value
- `{button2text}` - Button 2 text value
- `{updateReadyMessage}` - Staged/partially staged/pending download message
- `{excessiveUptimeWarningMessage}` - Conditional uptime warning
- `{diskSpaceWarningMessage}` - Conditional disk space warning
- And additional system information variables

#### Log Data Structure

The system logs to a unified log file with structured entries:
```
<scriptName> (<version>): <timestamp> - [<level>] <message>
```

Example:
```
dorm (2.3.1b1): 2025-01-30 14:34:25 - [NOTICE] Installed OS Version: 15.7.3
dorm (2.3.1b1): 2025-01-30 14:34:26 - [INFO] DDM-enforced OS Version: 26.2
```

Log Levels:
- `[PRE-FLIGHT]` - Initialization and setup
- `[NOTICE]` - Important information
- `[INFO]` - Informational messages
- `[ERROR]` - Error conditions
- `[FATAL]` - Fatal errors requiring attention

### Deployment Flow

#### 1. Test Deployment

Initial testing on a non-production Mac with swiftDialog installed:

1. **Download** the `main` branch from the [DDM OS Reminder repository](https://github.com/dan-snelson/DDM-OS-Reminder) (Code > Download ZIP)
2. **Execute** the `reminderDialog.zsh` script in demo mode:
   ```bash
   cd ~/Downloads/DDM-OS-Reminder-main
   zsh reminderDialog.zsh demo
   ```
3. **Review** the reminder dialog and interact with each button
4. **Simulate** plist installation by copying `sample.plist`:
   ```bash
   cp -v Resources/sample.plist /Library/Preferences/org.churchofjesuschrist.dorm.plist
   ```
5. **Re-execute** demo mode to confirm customizations from `sample.plist` appear

#### 2. Basic Deployment

Standard deployment using your organization’s Reverse Domain Name Notation (RDNN):

1. **Generate** deployment artifacts using `assemble.zsh`:
   ```bash
   zsh assemble.zsh
   ```
   - Prompts for organization’s RDNN (e.g., `com.company`)
   - Creates assembled script, organizational plist, and configuration profile
2. **Review** each deployment artifact:
   - Assembled script: `Artifacts/ddm-os-reminder-[RDNN]-[timestamp].zsh`
   - Organizational plist: `Artifacts/[RDNN].dorm-[timestamp].plist`
   - Configuration profile: `Artifacts/[RDNN].dorm-[timestamp]-unsigned.mobileconfig`
3. **Distribute** to a single test Mac via MDM
4. **Monitor** client-side logs:
   ```bash
   tail -f /var/log/[RDNN].log
   ```
5. **Kickstart** the LaunchDaemon:
   ```bash
   launchctl kickstart -kp system/[RDNN].dor
   ```
6. **Customize** the `.plist` or `.mobileconfig` with organization-specific values:
   - **Logging**: `ScriptLog`
   - **Reminder Timing**: `DaysBeforeDeadlineDisplayReminder`, `DaysBeforeDeadlineBlurscreen`, etc.
   - **Branding**: `OrganizationOverlayIconURL`, `SwapOverlayAndLogo`
   - **Support**: `SupportTeamName`, `SupportTeamPhone`, `SupportTeamEmail`, etc.
   - **Dialog Content**: `Title`, `Button1Text`, `Button2Text`, `Message`, etc.
7. **Deploy** updated configuration to test Mac and kickstart LaunchDaemon again

#### 3. Advanced Deployment

Fine-grained control of reminder display timing via customized LaunchDaemon:

1. **Modify** `StartCalendarInterval` in `launchDaemonManagement.zsh` to match organizational requirements (reference: [launchd.info](https://www.launchd.info/))
2. **Adjust** random delay logic in `reminderDialog.zsh` to align with LaunchDaemon schedule
3. **Execute** `assemble.zsh` to create updated deployment artifacts
4. **Review** and **distribute** to test Mac via MDM
5. **Kickstart** and **monitor** as in Basic Deployment

#### 4. Installation Phase (executed by assembled script)

When the assembled script runs on a target Mac:

1. Creates organization directory (e.g., `/Library/Management/[RDNN]/`)
2. Writes `reminderDialog.zsh` to organization directory
3. Creates LaunchDaemon plist at `/Library/LaunchDaemons/`
4. Loads LaunchDaemon via `launchctl bootstrap`
5. Validates installation

#### 5. Operational Phase (executed by LaunchDaemon)

Once installed, the LaunchDaemon operates autonomously:

1. **Triggers** `reminderDialog.zsh` according to `StartCalendarInterval` schedule
2. **Checks** for DDM enforcement entries in `/var/log/install.log`
3. **Evaluates** update requirements and deadline proximity
4. **If update required and within reminder window**:
   - Implements random delay (0-20 minutes for daily triggers, 30-90 seconds for login triggers)
   - Checks user availability (meetings, display assertions)
   - Displays customized reminder dialog via swiftDialog
   - Logs user interaction
   - Implements quiet period after user interaction
5. **If no update required or outside reminder window**: exits silently

### Integration Points

#### MDM Integration
- Script configuration achieved via Configuration Profile
- Script deployment via MDM script / policy execution
- Inventory collection via MDM Extension Attributes

#### System Integration
- Reads DDM enforcement data from `/var/log/install.log`
- Uses system commands: `pmset`, `diskutil`, `sysctl`, `uptime`
- Detects staged updates via Software Update framework

#### swiftDialog Integration
- Launches swiftDialog with JSON configuration
- Monitors dialog return codes for user actions
- Supports blurred background, overlays, custom icons
- Implements help dialog with QR codes

---

## Testing & Quality Assurance

### Test Environments

DDM-OS-Reminder should be tested across:

- **macOS Versions**: Current and previous major releases (e.g., macOS 26 Tahoe, macOS 15 Sequoia)
- **Hardware**: Intel and Apple Silicon Macs
- **MDM Solutions**: Jamf Pro, Iru / Kandji, Mosyle, Intune, and other DDM-capable MDMs
- **Configuration Variations**: Different RDNN, custom branding, various preference overrides

### Testing Strategy

#### Unit Testing

Individual function testing in demo mode:
```bash
zsh reminderDialog.zsh demo
```

Demo mode allows testing of:
- Dialog appearance and layout
- Button interactions
- Variable substitution
- Conditional messaging (uptime warnings, disk space, staged updates)
- Help dialog and QR code generation

#### Integration Testing

End-to-end testing scenarios:
1. **Fresh Installation**
   - Deploy assembled script to test Mac
   - Verify LaunchDaemon creation and loading
   - Verify script placement in organization directory
   - Confirm scheduled execution

2. **Configuration Changes**
   - Deploy new configuration profile
   - Verify preference override system works correctly
   - Test managed vs. local preference hierarchy

3. **DDM Enforcement Scenarios**
   - Mac with pending update (within reminder window)
   - Mac with pending update (outside reminder window)
   - Mac up-to-date with no pending updates
   - Mac with approaching deadline (< 3 days)
   - Mac with imminent deadline (< 1 day)

4. **End-user Availability Detection**
   - End-user in online meeting (should delay)
   - End-user with display sleep assertions (should suppress)
   - End-user in quiet period after recent interaction (should suppress)

5. **Update States**
   - No update staged
   - Partially staged update
   - Fully staged update ready for installation

#### End-user Acceptance Testing

- End-user experience validation
- Message clarity and comprehension
- Button action verification
- Help dialog usability
- Support contact information accuracy

### Known Test Scenarios

| Scenario | Expected Behavior | Validation |
|----------|------------------|------------|
| Mac up-to-date | Script exits silently | Check log for "Up-to-date" message |
| Update pending, >14 days | No dialog displayed | Check log shows suppression reason |
| Update pending, 7 days | Dialog displayed, normal background | End-user sees reminder |
| Update pending, 2 days | Dialog displayed, blurred background | End-user sees urgent reminder |
| Update pending, <1 day | Dialog displayed, button2 disabled/hidden | End-user cannot defer |
| End-user in meeting | Dialog delayed | Check log for meeting delay message |
| End-user in quiet period after recent interaction | Dialog suppressed (quiet period) | Check log for quiet period message |

### Quality Gates

Before deployment to production:
- [ ] All test scenarios pass
- [ ] Demo mode validation completed
- [ ] Syntax validation passes (`zsh -n` clean)
- [ ] Log output reviewed for errors
- [ ] End-user interface reviewed for branding compliance
- [ ] Configuration profile validates without errors
- [ ] LaunchDaemon loads successfully
- [ ] Script executes on schedule
- [ ] No excessive uptime or disk space false positives
- [ ] Quiet period logic prevents spam

---

## Deployment & Operations

### Deployment Prerequisites

1. **swiftDialog Installation**
   - Minimum version 2.5.6.4805 required
   - Deploy via MDM package or script
   - Validate installation before DDM-OS-Reminder deployment

2. **DDM Configuration**
   - Declarative Device Management enabled in MDM
   - OS update enforcement declarations configured
   - Deadlines set appropriately

3. **Script Preparation**
   - Organization RDNN configured in scripts
   - `assemble.zsh` executed to create deployable artifact
   - Configuration plist or profile customized for organization
   - Assembled script syntax validated

### Deployment Methods

#### Method 1: Full Deployment (Recommended)

1. Upload assembled script to MDM
2. Upload configuration profile to MDM
3. Create policy/configuration to:
   - Deploy configuration profile first
   - Run assembled script with Parameter 4 = "All" (or blank)
4. Scope to pilot group initially
5. Monitor logs and end-user feedback
6. Expand scope to production

#### Method 2: Update Existing Deployment

1. Upload new assembled script version to MDM
2. Update configuration profile if needed
3. Run script with Parameter 4 = "All" to refresh installation
4. Verify LaunchDaemon reloads with new version

#### Method 3: Uninstallation

1. Run script with Parameter 4 = "Uninstall"
2. Script removes:
   - LaunchDaemon plist and unloads daemon
   - Client-side script
   - Organization directory (if empty)
3. Optionally remove configuration profile via MDM

### Configuration Management

#### Preference Hierarchy

The system supports three configuration sources in priority order:

1. **Managed Preferences** (Highest Priority)
   - Path: `/Library/Managed Preferences/${preferenceDomain}.plist`
   - Deployed via Configuration Profile
   - Cannot be overridden by end-user or local admin
   - Best for enterprise-wide settings

2. **Local Preferences**
   - Path: `/Library/Preferences/${preferenceDomain}.plist`
   - Can be set via `defaults` command or manual plist editing
   - Useful for device-specific overrides
   - Overridden by managed preferences

3. **Hard-coded Defaults** (Lowest Priority)
   - Defined in `preferenceConfiguration` array in script
   - Used when no preference file exists
   - Fallback for all settings

#### Creating Configuration Profiles

Use the provided sample plist:
1. Edit `Resources/sample.plist` with organization values
2. Run `assemble.zsh` which generates unsigned .mobileconfig
3. Sign the profile if required by organization
4. Upload to MDM

Alternatively, use the standalone profile generator:
```bash
zsh Resources/createPlist.zsh
```

### Operational Monitoring

#### Log Monitoring

The client-side log (`scriptLog` preference, default `/var/log/org.churchofjesuschrist.log`) contains all operational events.

**Key Log Patterns to Monitor:**

Success patterns:
```
[NOTICE] Up-to-date
[NOTICE] End-user clicked Open Software Update
```

Warning patterns:
```
[WARNING] Meeting in-progress; delaying reminder
[WARNING] Do Not Disturb enabled; suppressing reminder
[WARNING] Quiet period active; suppressing reminder
```

Error patterns:
```
[ERROR] Failed to parse EnforcedInstallDate
[ERROR] swiftDialog not found
[FATAL] Unable to determine logged-in end-user
```

#### MDM Extension Attributes

For Jamf Pro (adaptable to other MDMs):

1. **User Clicks** (`JamfEA-DDM-OS-Reminder-User-Clicks.zsh`)
   - Reports button click history
   - Tracks end-user engagement
   - Example: `2025-10-23 02:53:37 dan clicked Remind Me Later`

2. **Pending OS Update Date** (`JamfEA-Pending_OS_Update_Date.zsh`)
   - Reports DDM deadline
   - Enables Smart Group creation for approaching deadlines

3. **Pending OS Update Version** (`JamfEA-Pending_OS_Update_Version.zsh`)
   - Reports required OS version
   - Enables inventory of enforcement status

#### LaunchDaemon Health Monitoring

Verify LaunchDaemon is loaded and running:
```bash
# Check if loaded
sudo launchctl print system/${launchDaemonLabel}

# View recent execution
sudo launchctl print system/${launchDaemonLabel} | grep "last exit code"

# Check schedule
sudo launchctl print system/${launchDaemonLabel} | grep "next scheduled"
```

### Troubleshooting

#### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Dialog doesn't appear | swiftDialog missing or wrong version | Install/update swiftDialog to 2.5.6.4805+ |
| Dialog appears too frequently | Quiet period not working | Check log for quiet period entries, verify preference |
| Dialog never appears | Outside reminder window or LaunchDaemon not loaded | Check `DaysBeforeDeadlineDisplayReminder`, verify daemon loaded |
| Wrong deadline shown | Log parsing issue | Check `/var/log/install.log` format, verify DDM declaration present |
| Button2 always hidden | Deadline too close | Review `DaysBeforeDeadlineHidingButton2` setting |
| Excessive uptime warning always shown | Threshold too low | Adjust `DaysOfExcessiveUptimeWarning` preference |
| Script fails to load preferences | Plist syntax error | Validate plist with `plutil -lint` |
| LaunchDaemon doesn't run | Plist syntax or permissions | Validate plist, check ownership (root:wheel) |

#### Debug Mode

For detailed troubleshooting, examine the client-side log:
```bash
tail -f /var/log/org.churchofjesuschrist.log
```

Or filter for specific script:
```bash
grep "dorm" /var/log/org.churchofjesuschrist.log
```

### Rollback Procedure

If issues arise in production:

1. **Immediate**: Unload LaunchDaemon
   ```bash
   sudo launchctl bootout system/${launchDaemonLabel}
   ```

2. **Deploy fix** or **revert to previous version**:
   - Run previous assembled script with Parameter 4 = "All"
   - Or run current script with Parameter 4 = "Uninstall"

3. **Communicate** with affected end-users if needed

### Performance Considerations

- Script execution time: Typically <5 seconds
- Resource usage: Minimal (bash script, brief swiftDialog process)
- Network requirements: None (all operations local except icon URLs)
- Storage requirements: <500KB for script and LaunchDaemon

### Scaling Recommendations

- **Small fleets** (<500 devices): Deploy to all devices simultaneously
- **Medium fleets** (500-5000 devices): Phase deployment over 1-2 weeks
- **Large fleets** (>5000 devices): Use tiered approach (pilot → phase 1 → phase 2 → production)
- Consider time zone distribution to avoid help desk spikes

---

## Security & Compliance

### Security Considerations

#### Execution Privileges
- Script runs as root (required for LaunchDaemon management)
- Follows principle of least privilege for end-user dialog display
- All file operations restricted to appropriate system directories

#### Data Privacy
- No PII collected or transmitted
- Log files contain only username and system information
- All data stored locally on device

#### Code Integrity
- Scripts can be signed if organization requires
- Configuration profiles can be signed
- SHA-256 checksums available for validation

### Compliance Alignment

DDM-OS-Reminder supports compliance requirements by:
- Enforcing OS update deadlines (security patches)
- Providing audit trail via logs
- Generating compliance reports via Extension Attributes
- Supporting customizable messaging for policy communication

---

## Monitoring & Metrics

### Key Performance Indicators

- **Deployment success rate**: Target ≥ 98% of devices successfully install and run DDM-OS-Reminder
- **Reminder delivery rate**: Target ≥ 95% of eligible devices display reminders within 1 hour of schedule
- **End-user response rate**: Target ≥ 80% of end-users act (click button1 or button2) within 24 hours of first reminder
- **Update completion rate**: Target ≥ 90% of end-users complete updates before deadline
- **Deferral behavior**: Average deferrals per device ≤ 3 before installation (useful for tuning reminder frequency and messaging)
- **End-user disruption rate**: ≤ 5% of reminders occur during detected meetings/presentations (excluding the <24h "deadline imminent" window)
- **Dialog reliability**: ≥ 99% of executions complete without fatal errors (launch + parse + display + exit) on in-scope devices
- **LaunchDaemon health**: ≥ 99% of endpoints have the LaunchDaemon loaded and running at the expected schedule
- **Mean time to detect (MTTD)**: < 1 business day from first appearance of a new systemic failure signature to detection
- **Mean time to remediate (MTTR)**: < 3 business days from detection to a validated fix (script/config/deployment)

### Monitoring Plan

Operational monitoring is log-driven (script log + system logs) with periodic inventory validation from your management platform.

- **What will be monitored**
  - Script log events:
    - Fatal errors (root/logging failures, parsing failures, missing critical dependencies)
    - Warning/error spikes (download failures, invalid config fallbacks, repeated meeting suppression)
    - Decision outcomes (up-to-date, fully staged, reminder displayed, end-user action taken)
  - LaunchDaemon state:
    - Daemon loaded, last run time, exit codes
    - Script presence/permissions at the expected path
  - Update posture:
    - OS version compliance relative to required version
    - DDM deadline proximity and past-due counts
  - End-user context suppression:
    - Meeting / presentation suppressions (and whether near-deadline bypass is working)

- **How alerts will be triggered**
  - Centralize the script log (e.g., via your EDR, log forwarder, or management platform log collection)
  - Trigger alerts on:
    - Any `[FATAL]` entry
    - A threshold of `[ERROR]` entries per hour/day (e.g., > 20 org-wide in 1 hour)
    - A sustained increase in "no deadline parsed" or "no in-scope entry found" outcomes on devices known to be in-scope
    - A threshold of "LaunchDaemon not loaded" detections in inventory (e.g., > 1% of fleet)
    - Past-due rate exceeding target (e.g., > 2% of in-scope Macs)
  - Route alerts to your existing incident channel (PagerDuty/Teams/Slack/email) with:
    - error signature
    - top affected OS versions / models
    - first-seen timestamp
    - count of affected endpoints
    - recommended first triage steps

- **Who responds to alerts**
  - **Primary**: macOS platform/endpoint engineering (triage, config changes, script updates, redeployments)
  - **Secondary**: Service Desk / End-user Support (end-user communications, "how to update" guidance, handling edge cases)
  - **Escalation**: Security/Compliance (if deadlines are regulatory-driven) and MDM engineering (if profile/script delivery is failing)
  - Define an "owner-of-the-week" rotation for initial triage and an on-call escalation path for deadline-critical periods

---

## Timeline & Milestones

### Phase 1: Foundation & Core UX (Target: 2025-11-18)

- [x] Initial public release with baseline reminder flow (v1.0.0, 14-Oct-2025)
- [x] End-user-focus protection and UX hardening (v1.1.0, 16-Oct-2025: display assertions, foregrounding System Settings, logged-in user detection)
- [x] Expand configuration capabilities and packaging approach (v1.2.0, 20-Oct-2025: dynamic icon/title/message; v1.3.0, 09-Nov-2025: improved deadline detection; v1.4.0, 18-Nov-2025: meeting delay, self-extracting option, swiftDialog installation detection, display reminder threshold)

### Phase 2: Major Refactor & Config Maturity (Target: 2025-12-13)

- [x] Script reorganization for clarity and maintainability (v2.0.0, 06-Dec-2025)
- [x] Formalize dependency requirements and improve testing ergonomics (swiftDialog minimum version, demo mode)
- [x] Strengthen configuration and deadline-driven behaviors (v2.1.0, 13-Dec-2025: read vars from plist, hide/disable secondary button, disk space + uptime warnings, improved reset/deployment & documentation, streamlined deployment)

### Phase 3: Reliability, Monitoring, and Production Hardening (Target: 2026-01-28)

- [x] Reduce end-user friction and improve correctness (v2.2.0, 06-Jan-2026: quiet period, staged update detection; v2.3.0, 19-Jan-2026: refined "update required" logic, disable button2 instead of hide)
- [x] Improve operational supportability (log-file monitoring instructions, assemble/build outputs standardized under `Artifacts/`)
- [x] Resilience and bug fixes driven by community feedback (overlay icon logic fix, prefs read via PlistBuddy; v2.3.1b1, 28-Jan-2026: enforcement-date edge-case handling with wait logic)

---

## Known Issues & Future Enhancements

### Known Limitations

1. **Launch scheduling is not profile-driven** - The LaunchDaemon schedule (`StartCalendarInterval`) is not configurable via a `.mobileconfig` preference key in a simple "MDM-only" way
   - **Impact**: changing the frequency of when the reminder dialog is displayed requires updating the LaunchDaemon plist (and redeploying it), rather than just pushing a profile update
   - **Workaround**: Redeploy assembled script with updated LaunchDaemon schedule when timing changes are needed

2. **Log parsing dependency** - Core behavior depends on parsing `/var/log/install.log` for DDM-related entries
   - **Impact**: Any upstream format changes from Apple can break deadline detection
   - **Mitigation**: Active community monitoring; rapid updates when Apple changes log format

3. **RDNN must match across components** - The Reverse Domain Name Notation must be consistent between `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and configuration files
   - **Impact**: Mismatched RDNN causes preference loading failures
   - **Mitigation**: `assemble.zsh` validates and harmonizes RDNN across all components

### Future Enhancement Ideas

1. **Internationalization / multi-language dialog content** - Support localized strings for title/message/buttons/help text driven by system locale (or by a configured language override)
   - **Rationale**: reduce friction in multilingual environments and improve end-user comprehension

2. **Exclude apps using sleep assertions** - Extend meeting/usage detection to include (or optionally exclude) processes holding sleep assertions
   - **Rationale**: reduce false positives/negatives for "don't interrupt" conditions and avoid suppressing dialogs for unrelated assertions

3. **Light Mode vs Dark Mode overlay icons** - Support automatic selection of overlay icon assets based on appearance mode
   - **Rationale**: improve UI polish and readability across environments without requiring manual swaps

### Technical Debt

- **Log-parsing fragility**: Core behavior depends on parsing `/var/log/install.log` for DDM-related entries. Any upstream format changes can break deadline detection and require rapid updates.
- **Limited automated test surface**: Most validation is currently manual (demo mode, pilot ring). A repeatable test harness (mocked log inputs + deterministic outputs) would reduce regressions and speed releases.

---

## Questions & Decisions

### Open Questions

1. Should the LaunchDaemon schedule be made configurable via preference file instead of requiring plist redeployment?
2. Should there be an option to suppress reminders entirely for specific user groups (e.g., executives, field workers)?
3. Should the system support multiple language localizations out of the box?

### Key Decisions Made

| Decision | Rationale | Date | Decided By |
|----------|-----------|------|------------|
| Mac Admin has sole responsibility for scheduling of reminders | Unnecessary complexity; plist preferences sufficient for current needs | 2026-01 | Dan K. Snelson |
| Use embedded script approach (assemble.zsh) | Simplifies deployment via single script execution in MDM | 2025-11 | Dan K. Snelson |
| Preference hierarchy: Managed > Local > Defaults | Allows flexibility while maintaining enterprise control | 2025-12 | Dan K. Snelson |
| Default to disable button2 instead of hiding when deadline imminent | Provides visual feedback that deferral is no longer available | 2026-01 | Dan K. Snelson |
| Use PlistBuddy instead of `defaults read` for preferences | More reliable parsing, especially for complex nested values | 2026-01 | Community contribution |
| Implement quiet period based on user interaction | Prevents dialog spam after user explicitly defers | 2025-12 | Dan K. Snelson |
| Wait up to 5 minutes if enforcement date is in the past | Handles edge case of recently-passed deadlines before MDM updates | 2026-01 | Dan K. Snelson |

### Rejected Alternatives

| Alternative | Why It Was Rejected |
|-------------|---------------------|
| Separate script deployment (not assembled) | More complex deployment; harder to maintain version consistency across components |
| SQLite database for state management | Unnecessary complexity; plist preferences and log files sufficient for current needs |
| Custom LaunchAgent per user | LaunchDaemon approach ensures consistent execution regardless of user login state |
| Hard-coded configuration in script | Eliminates ability to customize without script editing; prevents MDM-based management |

---

## References & Resources

### Inspiration

- [Mac Health Check](https://github.com/dan-snelson/Mac-Health-Check/blob/main/Mac-Health-Check.zsh#L1430-L1444)

### Documentation

- [Documentation](https://snelson.us/ddm)
- [GitHub repository](https://github.com/dan-snelson/DDM-OS-Reminder)
- [Development branch](https://github.com/dan-snelson/DDM-OS-Reminder/tree/development)

### Related Projects

- [Nudge](https://github.com/macadmins/nudge/wiki) - User-driven update encouragement for macOS
- [Super](https://github.com/Macjutsu/super/wiki) - Comprehensive macOS software update solution

### Community Resources

- [Mac Admins Slack](https://www.macadmins.org/) - #ddm-os-reminders channel
- [GitHub Issues](https://github.com/dan-snelson/DDM-OS-Reminder/issues) - Bug reports and feature requests
- [CHANGELOG](https://github.com/dan-snelson/DDM-OS-Reminder/blob/development/CHANGELOG.md) - Detailed version history

---

## Approval & Sign-off

### Review Process

- [ ] Technical review by: [Name/Role]
- [ ] Security review by: [Name/Role]
- [ ] Stakeholder approval by: [Name/Role]

### Sign-off

**Plan Approved By**: ___________________  
**Date**: ___________________  
**Ready for Implementation**: Yes / No

---

## Implementation Notes

> Once this plan is approved, use this section to track implementation progress and capture any deviations from the plan.

### Implementation Log

- 2025-10-14: Phase 1 initiated - v1.0.0 released with core functionality
- 2025-11-18: Phase 1 completed - v1.4.0 released with expanded configuration capabilities
- 2025-12-06: Phase 2 initiated - v2.0.0 released with major refactor
- 2025-12-13: Phase 2 completed - v2.1.0 released with configuration maturity
- 2026-01-06: Phase 3 initiated - v2.2.0 released with quiet period and staged update detection
- 2026-01-19: Phase 3 continuing - v2.3.0 released with reliability improvements
- 2026-01-28: Phase 3 nearing completion - v2.3.1b1 released with enforcement-date edge-case handling

### Lessons Learned

**From Phase 1:**
- End-user focus protection (meeting detection) critical for adoption
- Clear, actionable messaging more important than comprehensive information
- Demo mode essential for pre-deployment validation

**From Phase 2:**
- Configuration profile support dramatically simplified large-scale customization
- Preference hierarchy needed careful documentation to avoid admin confusion
- Disk space and uptime warnings reduced support tickets related to failed updates

**From Phase 3:**
- Quiet period implementation significantly reduced user complaints about "nagging"
- Staged update detection improved user experience by setting expectations
- PlistBuddy preference reading more reliable than defaults command
- Community feedback invaluable for identifying edge cases

---

**End of Project Plan**

---
