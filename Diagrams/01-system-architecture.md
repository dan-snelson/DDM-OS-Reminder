# System Architecture Diagram

This diagram shows the complete DDM OS Reminder ecosystem from development through deployment to runtime execution.

```mermaid
graph TB
    subgraph Development["🛠️ Development Environment"]
        RD["reminderDialog.zsh<br>End-user messaging logic"]
        LD["launchDaemonManagement.zsh<br>Deployment orchestration"]
        AS["assemble.zsh<br>Build script"]
        SP["sample.plist<br>Configuration template"]
        
        style RD fill:#e1f5ff
        style LD fill:#e1f5ff
        style AS fill:#fff4e6
        style SP fill:#f3e5f5
    end
    
    subgraph Assembly["⚙️ Assembly Process"]
        AS -->|1. Reads & harmonizes RDNN| RD
        AS -->|2. Embeds dialog script| LD
        AS -->|3. Generates config| SP
        AS -->|4. Produces artifacts| ART
        
        ART["Artifacts/<br>- Assembled script<br>- .plist<br>- .mobileconfig"]
        
        style ART fill:#c8e6c9
    end
    
    subgraph Deployment["📦 Deployment via MDM"]
        MDM["MDM Server<br>Jamf Pro / Intune / etc."]
        ART -->|Upload| MDM
        
        MDM -->|Policy: Script| SCRIPT[Assembled Script]
        MDM -->|Profile: Prefs| PROFILE[Configuration Profile]
        
        style MDM fill:#ffecb3
        style SCRIPT fill:#c8e6c9
        style PROFILE fill:#f3e5f5
    end
    
    subgraph Client["💻 Client Mac"]
        SCRIPT -->|Executes on client| INST[Installation Process]
        PROFILE -->|Deploys preferences| MGDPREF
        
        INST -->|Creates| CLISCRIPT["/Library/Management/<br>(RDNN)/dor.zsh"]
        INST -->|Creates| CLILD["/Library/LaunchDaemons/<br>(RDNN).dor.plist"]
        INST -->|Installs if needed| SD["swiftDialog.app"]
        
        MGDPREF["/Library/Managed<br>Preferences/<br>(RDNN).{orgScriptName}.plist"]
        
        style INST fill:#fff4e6
        style CLISCRIPT fill:#e1f5ff
        style CLILD fill:#e1f5ff
        style SD fill:#e1f5ff
        style MGDPREF fill:#f3e5f5
    end
    
    subgraph Runtime["▶️ Runtime Execution"]
        CLILD -->|RunAtLoad + schedule<br/>8am & 4pm daily| CLISCRIPT
        
        CLISCRIPT -->|1. Loads preferences| MGDPREF
        CLISCRIPT -->|2. Checks for user| USER{"Logged-in<br>User?"}
        CLISCRIPT -->|3. Parses install log| INSTLOG["/var/log/install.log<br>DDM enforcement data"]
        CLISCRIPT -->|4. Compares versions| OSVER["macOS Version<br>Check"]
        CLISCRIPT -->|5. Checks context| CONTEXT["User Context<br>Focus/Meetings"]
        CLISCRIPT -->|6. Displays dialog| SD
        
        USER -->|Yes| INSTLOG
        USER -->|No| EXIT1[Exit Silently]
        
        INSTLOG --> OSVER
        OSVER -->|Update Required| CONTEXT
        OSVER -->|Up to Date| EXIT2[Exit Silently]
        
        CONTEXT -->|Available| SD
        CONTEXT -->|In Meeting| DELAY[Delay 75 min]
        
        SD -->|"User clicks<br>Open Software Update"| SU["System Settings<br>Software Update"]
        SD -->|"User clicks<br>Remind Me Later"| LOG["Log Entry<br>& Exit"]
        
        style USER fill:#ffccbc
        style INSTLOG fill:#b2dfdb
        style OSVER fill:#b2dfdb
        style CONTEXT fill:#b2dfdb
        style EXIT1 fill:#cfd8dc
        style EXIT2 fill:#cfd8dc
        style DELAY fill:#fff9c4
        style SU fill:#c5e1a5
        style LOG fill:#cfd8dc
    end
    
    subgraph External["🍎 Apple Systems"]
        DDM["Declarative Device<br>Management"]
        DDM -->|Enforces deadline| INSTLOG
        DDM -->|"Forces update at<br>deadline"| RESTART["Automatic Restart"]
        
        SU -->|Downloads & installs| MACOS[macOS Update]
        
        style DDM fill:#e3f2fd
        style RESTART fill:#ffcdd2
        style MACOS fill:#c5e1a5
    end

    classDef default font-size:11px
```

## Component Descriptions

### Development Environment
- **reminderDialog.zsh**: Core logic for end-user messaging, preference management, and dialog display
- **launchDaemonManagement.zsh**: Handles deployment, LaunchDaemon creation, and swiftDialog installation
- **assemble.zsh**: Combines the above scripts into a single deployable artifact
- **sample.plist**: Template configuration file with all customizable preferences

### Assembly Process
- Harmonizes Reverse Domain Name Notation (RDNN) across files
- Embeds reminderDialog.zsh content into launchDaemonManagement.zsh
- Removes demo mode code
- Generates three deployment artifacts:
  - Assembled .zsh script (ready to deploy)
  - .plist configuration file
  - .mobileconfig Configuration Profile

### Deployment
- Administrator uploads assembled script to MDM server
- Script runs via MDM policy (one-time execution)
- Configuration Profile deployed separately for preference management
- Both components work together on client

### Client Installation
- Script installs to `/Library/Management/{RDNN}/`
- LaunchDaemon created and loaded at `/Library/LaunchDaemons/`
- swiftDialog installed if not present (or updated if outdated)
- Managed Preferences deployed via Configuration Profile

### Runtime Execution
1. **LaunchDaemon triggers** at load and on scheduled times (default: 8am, 4pm)
2. **Preference loading** from 3-tier hierarchy (Managed → Local → Defaults)
3. **User validation** ensures someone is logged in
4. **Log parsing** extracts DDM enforcement dates from install.log
5. **Version comparison** determines if update is required
6. **Context checking** respects user's Focus mode and meetings
7. **Dialog display** with deadline-appropriate behavior (blurscreen, button visibility)
8. **User interaction** leads to Software Update or delayed reminder

### Apple Integration
- **DDM** enforces update deadlines and writes enforcement data to install.log
- **Software Update** handles the actual macOS update process
- **Forced restart** occurs at deadline if user hasn't updated

## Data Flow

```
Development → Assembly → MDM → Client Installation → Runtime Execution → User Interaction → macOS Update
     ↑                                                        ↓
     └────────────── Admin monitors logs & adjusts ──────────┘
```

## Key Benefits of Architecture

1. **Single deployment**: One assembled script contains all logic
2. **Flexible configuration**: Preferences managed separately from code
3. **Automated scheduling**: LaunchDaemon ensures regular reminders
4. **User-friendly**: swiftDialog provides polished UI
5. **DDM-aware**: Reads Apple's enforcement data, no MDM API required
6. **Intelligent**: Respects user context (meetings, Focus mode)
7. **Deadline-driven**: Behavior adapts as deadline approaches
