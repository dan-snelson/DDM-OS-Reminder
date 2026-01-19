# Runtime Decision Tree

This flowchart shows the complete decision logic executed each time the LaunchDaemon triggers the DDM OS Reminder script.

```mermaid
flowchart TD
    Start([LaunchDaemon Triggers<br/>8am or 4pm]) --> LoadPrefs[Load Preferences<br/>Managed → Local → Defaults]
    
    LoadPrefs --> CheckUser{Logged-in<br/>User Found?}
    CheckUser -->|No| Exit1[Exit Silently<br/>Log: No user]
    CheckUser -->|Yes| CheckRoot{Running<br/>as Root?}
    
    CheckRoot -->|No| Fatal1[FATAL ERROR<br/>Must run as root]
    CheckRoot -->|Yes| ParseLog[Parse install.log<br/>for DDM enforcement dates]
    
    ParseLog --> CheckDDM{DDM Enforcement<br/>Date Found?}
    CheckDDM -->|No| Exit2[Exit Silently<br/>Log: No DDM enforcement]
    CheckDDM -->|Yes| GetVersions[Get Installed & Required<br/>macOS Versions]
    
    GetVersions --> CompareVersions{Update<br/>Required?}
    CompareVersions -->|No - Up to Date| Exit3[Exit Silently<br/>Log: macOS up to date]
    CompareVersions -->|Yes| CalcDays[Calculate Days<br/>Until Deadline]
    
    CalcDays --> CheckWindow{Within Reminder<br/>Window?<br/>≤ configurable days}
    CheckWindow -->|No - Too Early| Exit4[Exit Silently<br/>Log: Outside reminder window]
    CheckWindow -->|Yes| CheckQuiet{Within Quiet<br/>Period?<br/>Last shown < interval}
    
    CheckQuiet -->|Yes| Exit5[Exit Silently<br/>Log: Quiet period active]
    CheckQuiet -->|No| CheckFocus{Focus Mode<br/>Active?}
    
    CheckFocus -->|Yes, ≥24hrs to deadline| Exit6[Exit Silently<br/>Log: Respecting Focus mode]
    CheckFocus -->|No or <24hrs| CheckMeeting{Display Sleep<br/>Assertions?<br/>User in meeting}
    
    CheckMeeting -->|Yes, ≥24hrs to deadline| Delay[Delay Execution<br/>Sleep 75 min, then retry]
    CheckMeeting -->|No or <24hrs| CheckDisk[Check Free<br/>Disk Space]
    
    Delay --> CheckMeeting
    
    CheckDisk --> DiskOK{Sufficient<br/>Space?<br/>≥ min threshold}
    DiskOK -->|Warning| SetDiskWarn[Set Disk Warning<br/>Message Flag]
    DiskOK -->|OK| CheckUptime
    SetDiskWarn --> CheckUptime[Check System<br/>Uptime]
    
    CheckUptime --> UptimeOK{Excessive<br/>Uptime?<br/>≥ warning threshold}
    UptimeOK -->|Yes| SetUptimeWarn[Set Uptime Warning<br/>Message Flag]
    UptimeOK -->|No| DetectStaged
    SetUptimeWarn --> DetectStaged[Detect Staged<br/>Updates in Preboot]
    
    DetectStaged --> StagedFound{Update<br/>Staged?}
    StagedFound -->|Fully Staged| SetFullStaged[Set Full Staged<br/>Message]
    StagedFound -->|Partially Staged| SetPartialStaged[Set Partial Staged<br/>Message]
    StagedFound -->|Not Staged| SetPending[Set Pending Download<br/>Message]
    
    SetFullStaged --> BuildDialog
    SetPartialStaged --> BuildDialog
    SetPending --> BuildDialog[Build Dialog<br/>with Placeholders]
    
    BuildDialog --> CheckDeadline{Days Until<br/>Deadline?}
    
    CheckDeadline -->|≥ Blurscreen Threshold<br/>default: 45 days| Standard[Standard Dialog<br/>✓ Button 2 enabled<br/>✗ No blurscreen]
    CheckDeadline -->|< Blurscreen Threshold<br/>≥ Hide Button Threshold<br/>default: 3-44 days| Blur[Blurscreen Dialog<br/>✓ Button 2 enabled<br/>✓ Blurscreen active]
    CheckDeadline -->|< Hide Button Threshold<br/>default: <3 days| Urgent[Urgent Dialog<br/>✗ Button 2 disabled/hidden<br/>✓ Blurscreen active]
    
    Standard --> Display[Display swiftDialog]
    Blur --> Display
    Urgent --> Display
    
    Display --> UserAction{User<br/>Action?}
    
    UserAction -->|Button 1:<br/>Open Software Update| OpenSU[Open System Settings<br/>Software Update pane]
    UserAction -->|Button 2:<br/>Remind Me Later| LogRemind[Log Entry:<br/>User postponed]
    UserAction -->|Info Button:<br/>Support Info| ShowHelp[Display Help Dialog<br/>with support details]
    UserAction -->|Dialog Closed/Timeout| LogClose[Log Entry:<br/>Dialog closed]
    
    OpenSU --> LogOpen[Log Entry:<br/>Opened Software Update]
    LogOpen --> Exit7[Exit<br/>User taking action]
    
    LogRemind --> Exit8[Exit<br/>Will retry at next schedule]
    
    ShowHelp --> RedisplayAfterHelp[Re-display<br/>Main Dialog]
    RedisplayAfterHelp --> UserAction
    
    LogClose --> Exit9[Exit<br/>Will retry at next schedule]
    
    Exit1 --> End([End])
    Fatal1 --> End
    Exit2 --> End
    Exit3 --> End
    Exit4 --> End
    Exit5 --> End
    Exit6 --> End
    Exit7 --> End
    Exit8 --> End
    Exit9 --> End
    
    style Start fill:#e3f2fd
    style LoadPrefs fill:#fff9c4
    style CheckUser fill:#ffecb3
    style CheckRoot fill:#ffecb3
    style CheckDDM fill:#ffecb3
    style CompareVersions fill:#ffecb3
    style CheckWindow fill:#ffecb3
    style CheckQuiet fill:#ffecb3
    style CheckFocus fill:#ffecb3
    style CheckMeeting fill:#ffecb3
    style DiskOK fill:#ffecb3
    style UptimeOK fill:#ffecb3
    style StagedFound fill:#ffecb3
    style CheckDeadline fill:#ff9800
    style UserAction fill:#4caf50
    
    style Exit1 fill:#cfd8dc
    style Exit2 fill:#cfd8dc
    style Exit3 fill:#cfd8dc
    style Exit4 fill:#cfd8dc
    style Exit5 fill:#cfd8dc
    style Exit6 fill:#cfd8dc
    style Fatal1 fill:#ef5350
    
    style Standard fill:#c8e6c9
    style Blur fill:#fff59d
    style Urgent fill:#ffab91
    
    style Display fill:#81c784
    style OpenSU fill:#66bb6a
    style ShowHelp fill:#64b5f6
    
    style End fill:#e0e0e0
```

## Decision Points Explained

### 1. User Validation
- **Check**: Is a user logged in (not loginwindow)?
- **Why**: Dialog requires an active user session
- **Exit if**: No user found

### 2. Root Privileges
- **Check**: Is script running as root?
- **Why**: Required for LaunchDaemon management and system-level operations
- **Exit if**: Not root (fatal error)

### 3. DDM Enforcement
- **Check**: Are DDM enforcement dates present in `/var/log/install.log`?
- **Why**: Script relies on Apple DDM data to determine deadlines
- **Exit if**: No enforcement dates found

### 4. Version Comparison
- **Check**: Is installed macOS version older than DDM-required version?
- **Why**: Only display reminder if update is actually needed
- **Exit if**: Mac is up to date

### 5. Reminder Window
- **Check**: Are we within configured days before deadline (default: 60 days)?
- **Why**: Don't annoy users too early
- **Exit if**: Deadline too far in future

### 6. Quiet Period
- **Check**: Has dialog been shown recently (based on last display timestamp)?
- **Why**: Prevent excessive nagging within same day
- **Exit if**: Recently displayed

### 7. Focus Mode
- **Check**: Is user in Focus/Do Not Disturb mode?
- **Why**: Respect user's concentration time
- **Exception**: Ignored if <24 hours to deadline
- **Exit if**: Focus active and deadline not imminent

### 8. Meeting Detection
- **Check**: Are display sleep assertions active (pmset)?
- **Why**: User likely in video call or presentation
- **Exception**: Ignored if <24 hours to deadline
- **Action if**: Delay 75 minutes and retry (not exit)

### 9. Disk Space Check
- **Check**: Is free disk space below minimum threshold?
- **Why**: Update may fail with insufficient space
- **Action**: Adds warning message to dialog (doesn't block display)

### 10. Uptime Check
- **Check**: Has Mac been on for excessive days without restart?
- **Why**: Restarts improve update reliability
- **Action**: Adds warning message to dialog (doesn't block display)

### 11. Staged Update Detection
- **Check**: Is update already downloaded to Preboot volume?
- **Why**: Installation is faster if already staged
- **Action**: Adds appropriate message (fully staged, partially staged, or pending)

### 12. Deadline-Based Behavior
Based on days remaining until deadline:

#### Standard Dialog (≥45 days, configurable)
- Button 2: **Enabled** ("Remind Me Later")
- Blurscreen: **Disabled**
- Urgency: Low

#### Blurscreen Dialog (3-44 days, configurable)
- Button 2: **Enabled** ("Remind Me Later")
- Blurscreen: **Enabled** (background dimmed)
- Urgency: Medium

#### Urgent Dialog (<3 days, configurable)
- Button 2: **Disabled or Hidden** (can't postpone)
- Blurscreen: **Enabled**
- Urgency: High
- Display assertions: **Ignored** (shows even in meetings)

### 13. User Actions
After dialog displays, user can:

1. **Open Software Update**: 
   - Opens System Settings → Software Update
   - Logs action
   - Exits (user taking responsibility)

2. **Remind Me Later**:
   - Logs postponement
   - Exits (will remind again at next schedule)
   - Note: Disabled/hidden when deadline imminent

3. **View Support Info** (? button):
   - Displays help dialog with support contact info
   - Returns to main dialog after closing help
   - Re-displays main dialog (user can then choose action)

4. **Close/Timeout**:
   - Logs dismissal
   - Exits (will remind again at next schedule)

## Configuration Parameters

Key preferences that affect decision tree:

| Parameter | Default | Affects Decision Point |
|-----------|---------|----------------------|
| `daysBeforeDeadlineDisplayReminder` | 60 | Reminder Window check |
| `daysBeforeDeadlineBlurscreen` | 45 | Blurscreen activation |
| `daysBeforeDeadlineHidingButton2` | 21 | Button 2 disable/hide |
| `daysOfExcessiveUptimeWarning` | 0 (disabled) | Uptime warning threshold |
| `meetingDelay` | 75 minutes | Meeting detection delay |
| `minimumDiskFreePercentage` | 99 (disabled) | Disk space warning |
| `disableButton2InsteadOfHide` | YES | Button 2 behavior (disabled vs hidden) |

## Exit Points

The script has **9 exit points** (plus 1 fatal error):

1. **No logged-in user** - Wait for next scheduled run
2. **No DDM enforcement** - Nothing to remind about
3. **macOS up to date** - Update already completed
4. **Outside reminder window** - Too early to remind
5. **Within quiet period** - Recently reminded
6. **Focus mode active** - Respecting user's concentration
7. **After opening Software Update** - User taking action
8. **After "Remind Me Later"** - User postponed
9. **After dialog close** - User dismissed

Each exit logs appropriate message to `/var/log/{RDNN}.log` for troubleshooting.

## Timing

**Default Schedule**: 8:00 AM and 4:00 PM daily

This ensures:
- Morning reminder catches users starting their day
- Afternoon reminder catches users before end of day
- Not intrusive during lunch (typically 12-1 PM)
- Configurable via LaunchDaemon CalendarInterval

**Re-execution**: Script exits after each run; LaunchDaemon handles re-scheduling automatically.
