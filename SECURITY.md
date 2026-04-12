# Security Policy

Thank you for helping keep **DDM OS Reminder** secure.

DDM OS Reminder is a macOS-only project commonly deployed through MDM, runs with **`root` privileges**, reads **`/var/log/install.log`**, deploys a LaunchDaemon plus reminder script, can auto-download and install **swiftDialog**, writes operational logs, and generates deployable **plist** and **mobileconfig** artifacts. The maintained attack surface includes the main runtime and deployment scripts, helper content under **`Resources/`**, and tracked deployment artifacts committed under **`Artifacts/`**.

## Supported Versions

The latest stable release and the current prerelease line are actively supported for security updates.

- Current stable: **v3.1.0**
- Current prerelease line: **v3.1.0b\***
- Older releases receive no security patches.

If you are running an older release, upgrade before requesting security support.

## Reporting a Vulnerability

If you discover a security vulnerability in this project, report it privately.

**Do not** open a public GitHub Issue or Pull Request that discloses the vulnerability.

Send reports to: **security@snelson.us**

Please include as much of the following as possible:

- A clear description of the issue and its potential impact
- Steps to reproduce it
- Affected version(s) of DDM OS Reminder
- Deployment context, such as MDM platform, LaunchDaemon behavior, or managed preference configuration
- Relevant logs, screenshots, or proof-of-concept details
- Any suggested mitigation or fix
- Your name or handle, if you want attribution

You should receive an acknowledgment within **48 hours**. We will work with you to validate the report, develop a fix, and coordinate disclosure once the issue is resolved.

## Safe Use Guidance

- Test changes and deployments in a lab or VM before broad rollout.
- Use trusted distribution paths, such as official GitHub releases or your own signed packaging flow.
- Review organization-specific customizations before deployment, especially branding, support links, restart policy, and user-facing dialog text.
- Validate managed preferences, local overrides, and **RDNN** consistency before production use.
- Review generated LaunchDaemon, plist, and unsigned mobileconfig artifacts before promotion into production workflows.

## Code Security Practices

- This repository is scanned with **Semgrep** using the `p/r2c-security-audit`, `p/ci`, and `p/secrets` rulesets.
- **Gitleaks** scans repository history for potential credential or secret exposure.
- Tracked `*.zsh` files and zsh-shebang helpers are validated with **`zsh -n`**, including the main entrypoints, zsh helpers under `Resources/`, and tracked assembled zsh artifacts under `Artifacts/`.
- Tracked `*.sh` and `*.bash` files are checked with **ShellCheck** when present.
- Changes are reviewed with attention to shell quoting, install-log parsing, download and install paths, LaunchDaemon deployment, plist/mobileconfig generation, and preference handling.
- The current deployment script validates downloaded swiftDialog installers with **Team ID** verification before installation.

## Disclosure Policy

- We follow coordinated disclosure.
- We will prioritize a fix before sharing public technical details.
- Security fixes will be released as quickly as practical, typically with a tagged release and changelog note.
- We will credit the reporter unless anonymity is requested.

## General Security Questions

For non-vulnerability questions or general usage concerns, use the public project channels.

Community-supplied, best-effort support is available on the [Mac Admins Slack](https://www.macadmins.org) (free, registration required) [#ddm-os-reminders](https://slack.com/app_redirect?channel=C09LVE2NVML) channel, or you can open an issue on [GitHub](https://github.com/dan-snelson/DDM-OS-Reminder/issues).

Last updated: April 2026
