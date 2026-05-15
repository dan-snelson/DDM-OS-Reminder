---
name: Deployment Flow Rules
description: Rules for launchDaemonManagement.zsh and assemble.zsh
applyTo: "launchDaemonManagement.zsh,assemble.zsh"
---

# Deployment Flow Rules

## 1. RDNN Consistency (Highest Priority)
- Preserve RDNN consistency across `reminderDialog.zsh`, `launchDaemonManagement.zsh`, generated plist, and generated mobileconfig.
- If RDNN consistency cannot be preserved due to conflicting requirements: Document the conflict and escalate to the team lead.

## 2. Validation
- Run `zsh -n` on every touched Zsh script immediately after editing.
- If `zsh -n` detects errors: Resolve them before proceeding to the next step.

## 3. Artifact & Review Rules
- `reminderDialog.zsh` changes are **not live** inside `launchDaemonManagement.zsh` until `zsh assemble.zsh` runs.
- Review `Resources/README.md` and packaging helpers before calling work complete.
- Do not regenerate tracked `Artifacts/` unless explicitly required by a documented process or team lead instruction.