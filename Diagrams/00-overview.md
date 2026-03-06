# Executive Overview Diagram

This diagram gives Mac Admins a simple, high-level deployment path for DDM OS Reminder.

```mermaid
flowchart TD
    Clone["<b>1. Clone</b><br/><br/>git&nbsp;clone&nbsp;https://github.com/dan-snelson/DDM-OS-Reminder.git<br/><br/>cd&nbsp;DDM-OS-Reminder"]
    Demo["<b>2. Demo</b><br/><br/>zsh&nbsp;reminderDialog.zsh&nbsp;demo"]
    Assemble["<b>3. Assemble</b><br/><br/>zsh&nbsp;assemble.zsh&nbsp;--interactive"]
    Deploy["<b>4. Deploy Artifacts</b><br/><br/>Configuration Profile<br/>Script"]
    Test["<b>5. Test</b><br/><br/>Verify LaunchDaemon, preferences, logs, and dialog behavior"]

    Clone --> Demo --> Assemble --> Deploy --> Test

    style Clone fill:#c8e6c9
    style Demo fill:#fff9c4
    style Assemble fill:#fff4e6
    style Deploy fill:#ffecb3
    style Test fill:#e1f5ff
```

## What Each Phase Means

**1. Clone**: Get a local working copy of the project.
**2. Demo**: Run demo mode for the fastest feedback loop on reminder dialog.
**3. Assemble**: Assemble deployable artifacts for your RDNN.
**4. Deploy**: Upload the assembled script and profile through MDM.
**5. Test**: Validate behavior on a test device before production rollout.

## How to Use This Overview

- Use this as a quick-start map for new Mac Admins.
- Refer to [01-system-architecture.md](01-system-architecture.md) for full architecture detail.
