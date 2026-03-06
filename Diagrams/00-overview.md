# Executive Overview Diagram

This diagram gives Mac Admins a simple, high-level deployment path for DDM OS Reminder.

```mermaid
%%{init: {'themeVariables': {'lineColor': '#555555', 'fontFamily': 'monospace'}}}%%
flowchart TD
    Clone["<b>1. Clone</b><br/><br/><code>git&nbsp;clone&nbsp;https://github.com/dan-snelson/DDM-OS-Reminder.git</code><br/><br/><code>cd&nbsp;DDM-OS-Reminder</code>"]
    Demo["<b>2. Demo</b><br/><br/><code>zsh&nbsp;reminderDialog.zsh&nbsp;demo</code>"]
    Assemble["<b>3. Assemble</b><br/><br/><code>zsh&nbsp;assemble.zsh&nbsp;--interactive</code>"]
    Deploy["<b>4. Deploy Artifacts</b><br/><br/>Configuration Profile<br/>Script"]
    Test["<b>5. Test</b><br/><br/>Verify LaunchDaemon, preferences, logs, and dialog behavior"]

    Clone --> Demo --> Assemble --> Deploy --> Test

    classDef clone    fill:#2e7d32,color:#ffffff,stroke:#1b5e20
    classDef demo     fill:#f9a825,color:#ffffff,stroke:#f57f17
    classDef assemble fill:#e65100,color:#ffffff,stroke:#bf360c
    classDef deploy   fill:#1565c0,color:#ffffff,stroke:#0d47a1
    classDef test     fill:#6a1b9a,color:#ffffff,stroke:#4a148c

    class Clone clone
    class Demo demo
    class Assemble assemble
    class Deploy deploy
    class Test test
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