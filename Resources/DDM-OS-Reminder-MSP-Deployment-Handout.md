# DDM OS Reminder MSP Deployment Handout

## Purpose and Scope
- DDM OS Reminder is a macOS-only, MDM-agnostic reminder layer for DDM-enforced OS update deadlines
- It reads `/var/log/install.log` and displays a swiftDialog prompt via a LaunchDaemon
- It does not perform OS updates or manage non-OS updates

## Prereqs and Inputs
- Client RDNN value for each environment (keep it consistent across artifacts and preferences)
- MDM access to deploy scripts and profiles
- One test Mac for validation

## Customize (Deployment-Critical Only)
- Confirm RDNN consistency in `reminderDialog.zsh` and `launchDaemonManagement.zsh`
- If you change the LaunchDaemon schedule, also update the random delay in `reminderDialog.zsh`

## Assemble Artifacts
- Run `zsh assemble.zsh`
- Assembled script: `Artifacts/ddm-os-reminder-<rdnn>-YYYY-MM-DD-HHMMSS.zsh` (deployable script)
- Plist: `Artifacts/<rdnn>.dorm-YYYY-MM-DD-HHMMSS.plist` (preferences via plist)
- Profile: `Artifacts/<rdnn>.dorm-YYYY-MM-DD-HHMMSS-unsigned.mobileconfig` (preferences via profile)

## Choose Deployment Method
- Deploy the assembled script directly via MDM, or
- Create a self-extracting script with `zsh Resources/createSelfExtracting.zsh`, or
- Deploy the profile for managed preferences (or the plist for local prefs)

## Deploy
- Upload and distribute artifacts using your MDM of choice
- Prefer the profile for managed preferences; use the plist for local preference testing

## Validate
- Force a run: `launchctl kickstart -kp system/<rdnn>.dor`
- Tail logs: `/var/log/<rdnn>.log`
- Visual sanity check: `zsh reminderDialog.zsh demo`

## Operational Notes
- Artifact filenames are timestamped; keep track of which version is deployed
- Re-run `assemble.zsh` after any reminder script changes
- Support: Mac Admins Slack `#ddm-os-reminders` and GitHub issues

## Common Pitfalls
- RDNN mismatch causes silent preference-loading failures
- Schedule changes without matching random delay lead to unexpected prompts
- Forgetting to re-assemble leaves old embedded logic in deployments

## Resources
- Blog Post: https://snelson.us/ddm
- GitHub Repo: https://github.com/dan-snelson/DDM-OS-Reminder

Revision date: 2026-02-06