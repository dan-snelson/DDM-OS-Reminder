---
name: Reminder Dialog Rules
description: Specific rules for reminderDialog.zsh behavior and validation
applyTo: "reminderDialog.zsh"
---

# Reminder Dialog Specific Rules

## Core Behavior Rules

### Post-Deadline Restart Workflow (Priority Order)
1. Derive the **effective post-deadline epoch** from the resolved DDM declaration state.
2. Validate the derived epoch.
3. Gate the restart workflow on the validated effective post-deadline epoch — **never** use the raw `EnforcedInstallDate`.
4. If the effective post-deadline epoch cannot be derived (missing or invalid DDM declaration state): Log an error and halt the workflow.

### Quiet Period
- Quiet period starts after the user clicks the **'OK' or 'Cancel'** button in the dialog, not when the dialog first appears.
- If the user does not click any button within the specified timeout: Log a warning and proceed with default behavior.

## Validation & Error Handling
- After any behavior change: Run `zsh -n reminderDialog.zsh` immediately.
- If `zsh -n reminderDialog.zsh` fails: Output the error message and stop further execution.
- If deployment behavior is affected: Re-assemble before considering the task complete.
