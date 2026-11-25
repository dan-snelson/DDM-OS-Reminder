# DDM OS Reminder: pre-release test suite

`Tests/` checks a `development` checkout before a pre-release. Run it as `root` on a test Mac, from a full checkout of the repository: a ZIP download (no `git` needed) or a `git clone`.

The suite tests the scripts in the checkout it lives in (`reminderDialog.zsh`, `launchDaemonManagement.zsh`, `assemble.zsh`, and `Resources/`). It does not test the copy deployed on the Mac. It never edits production scripts and never writes into the checkout or `Artifacts/`.

## Run it

Download the `development` branch as a ZIP. This needs no `git` and no Command Line Tools:

```zsh
curl -L -o DDM-OS-Reminder.zip https://github.com/dan-snelson/DDM-OS-Reminder/archive/refs/heads/development.zip
ditto -x -k DDM-OS-Reminder.zip .
cd DDM-OS-Reminder-development
```

Or clone it with `git`:

```zsh
git clone -b development https://github.com/dan-snelson/DDM-OS-Reminder.git
cd DDM-OS-Reminder
```

> **Over SSH, do not run from `~/Downloads` or `~/Desktop`.** TCC blocks `root` there unless Remote Login has "Allow full disk access for remote users" turned on. Move the folder first, for example to `/Users/Shared/`.

Then, from the top of the checkout:

```zsh
sudo zsh Tests/runTests.zsh                          # unit tier (default)
sudo zsh Tests/runTests.zsh --integration            # unit tier, then the integration tier
sudo zsh Tests/runTests.zsh --integration --prerelease 5.4.0b1
sudo zsh Tests/runTests.zsh --integration --release 5.4.0
```

| Flag | Effect |
|---|---|
| `--unit` | Run the unit tier only (default). |
| `--integration` | Run the unit tier first, then the integration tier. The integration tier does not run when any unit test failed. |
| `--skip-dialogs` | Leave out integration scenarios that show swiftDialog windows. |
| `--filter <text>` | Run only tests whose `[group] description` contains `<text>`, for example `--filter unit/starter`. |
| `--keep` | Keep the work directory and the `com.example.dortest` deployment after the run. |
| `--release <x.y.z>` | Require `scriptVersion` in `assemble.zsh`, `launchDaemonManagement.zsh`, and `reminderDialog.zsh`, and the top `CHANGELOG.md` heading, to equal `<x.y.z>`. |
| `--prerelease <x.y.zbN>` | Same check for a beta such as `5.4.0b1`. The top `CHANGELOG.md` heading may add a parenthetical, such as `### Version 5.4.0b1 (Unreleased)` or a date. Cannot be combined with `--release`. |
| `--help` | Show usage. |

Each test prints one line:

```text
PASS  [unit/starter] fingerprint change launches declarationChange
FAIL  [unit/starter] state write failure (uchg) blocks a declarationChange launch with [ERROR]
        [ERROR] for a declaration-change launch
          expected to contain: [ERROR]
          in file: /var/tmp/dor-tests.Ab12Cd/t/093/starter/starter.log (last 8 lines)
SKIP  [unit/syntax-versions] --release or --prerelease version matches every scriptVersion and the CHANGELOG heading (no --release or --prerelease given; …)
```

The run ends with `N passed, N failed, N skipped`, an "Attention" block that repeats every warning and note, and a final banner. The last line printed is always the results log path:

```text
Results log: /var/tmp/dor-tests-C02XK1ABCD12-2026-11-25-140350.log
```

The file name starts with the Mac's serial number, so you can tell which Mac produced each log. If the serial number cannot be read, the name is `dor-tests-<timestamp>.log`. Keep these logs out of public issues, or rename them first.

The exit status is `0` only when nothing failed. Bring that log back after every run.

## Pre-release workflow

1. Optional: an outdated Mac in scope of a DDM declaration from the MDM, running production 5.3.0.
2. Download the `development` ZIP (or `git clone` / `git pull` the `development` branch).
3. `sudo zsh Tests/runTests.zsh`
4. `sudo zsh Tests/runTests.zsh --integration`
5. Bring the results log back, fix, and repeat from step 2.
   For a beta, bump `scriptVersion` and the `CHANGELOG.md` heading to the beta version (for example `5.4.0b1`), then run `sudo zsh Tests/runTests.zsh --integration --prerelease 5.4.0b1` before you deploy it to test Macs.
6. Bump `scriptVersion` and the `CHANGELOG.md` heading, then run `sudo zsh Tests/runTests.zsh --integration --release 5.4.0`. Until the bump, `--release 5.4.0` stops on purpose, because the scripts are still `5.3.0`.
7. Deploy 5.4.0 through the MDM over 5.3.0, and confirm the first heartbeat seeds `LastDeclarationFingerprint`.

## Missed-step guards

The runner checks the workflow before it tests anything. Each check prints a full-width banner with `What happened:`, `Why it matters:`, and `Next step:` lines.

- `❌ STOP` exits at once: `64` for a usage error (for example, not root), `69` for a missing prerequisite.
- `⚠️  WARNING` and `ℹ️  NOTE` banners let the run continue. They are repeated in the "Attention" block before the summary.

| Check | Level |
|---|---|
| Not root | STOP 64 |
| `reminderDialog.zsh`, `launchDaemonManagement.zsh`, `assemble.zsh`, `Resources/`, or `CHANGELOG.md` missing next to `Tests/` (only `Tests/` was copied) | STOP 69 |
| Not a git checkout (ZIP download or no git: script SHA-256 hashes logged; repo-clean guard uses a file manifest) | NOTE |
| Branch is not `development` | WARNING |
| Behind `origin/<branch>` at the last fetch (no automatic fetch; the age of `.git/FETCH_HEAD` is shown) | WARNING |
| Uncommitted changes to tracked files | WARNING |
| `scriptVersion` differs between `assemble.zsh`, `launchDaemonManagement.zsh`, and `reminderDialog.zsh` | STOP 69 |
| No `--release`, and the `CHANGELOG.md` top heading says "(Unreleased)" | NOTE |
| `--release X`, but a `scriptVersion` or the `CHANGELOG.md` heading is not X | STOP 69 |
| `--prerelease X`, but a `scriptVersion` is not X or the `CHANGELOG.md` heading is not `### Version X`, optionally followed by ` (…)` | STOP 69 |
| `--release` and `--prerelease` both given, or a `--prerelease` value not shaped like `x.y.zbN` | STOP 64 |
| `--integration` and a unit test failed | STOP (integration not run) |
| `--integration` with no console user | STOP 69; with `--skip-dialogs`, a WARNING, and console-dependent scenarios are skipped |
| `--integration` and swiftDialog is not installed | WARNING (the test deploy installs it system-wide) |
| `--integration` finds `com.example.dortest` leftovers from an aborted run | WARNING, then automatic cleanup |
| Live `SoftwareUpdateDDMStatePersistence.plist` unreadable or with zero declarations | WARNING |
| Production `org.churchofjesuschrist.dor` loaded or not loaded | NOTE |
| End of run: any FAIL | STOP-style banner, exit `1` |
| End of run: unit tier passed, or both tiers passed (with or without `--release` or `--prerelease`) | NOTE naming the next workflow step |

The results log header records the date, the macOS version and build, the source (`git checkout` or `ZIP download (no .git)`), `scriptVersion`, the git branch and commit (or "not a git checkout"), the SHA-256 hashes of `reminderDialog.zsh`, `launchDaemonManagement.zsh`, and `assemble.zsh`, the flags, and whether the production daemon is loaded. To tie a ZIP run to code, compare those hashes with `shasum -a 256 reminderDialog.zsh launchDaemonManagement.zsh assemble.zsh` in a known checkout.

The repo-clean guard compares `git status --porcelain --ignored` and the `Artifacts/` listing before and after the run. Without a usable git checkout (for example, a ZIP download), it compares a file manifest instead: the SHA-256 hash of every file (including dotfiles, but not `.DS_Store`), every directory path, and the `Artifacts/` listing. Any difference is a FAIL.

## Unit tier

The unit tier is hermetic. It writes only under the work directory `/var/tmp/dor-tests.XXXXXX`, which is removed after the run unless `--keep` is given. Timestamp tests pin `TZ=America/New_York`; device-local cases also run under `Asia/Kolkata` (+05:30).

The tests do not run whole scripts. `lib/testHelpers.zsh` copies what it needs into the work directory:

- **`extractFunctions`** copies every top-level function definition, including the bare `installedOSvsDDMenforcedOS() {` form and one-line helpers. It skips heredoc bodies and all top-level code. It fails loudly unless the extracted file passes `/bin/zsh -n` and the number of functions equals the number of definition lines outside heredocs.
- **`extractStarter`** copies the `ENDOFSTARTER` heredoc and replaces its five placeholders with work-directory paths. It also points `ddmStatePersistencePlistPath` at a fixture and the `scutil` and `pmset` calls at stubs.
- Only those copies are rewritten. Fixtures (`install.log` lines, persistence plists, `dor-state.plist`, fallback plists) are built at run time by helpers in `lib/testHelpers.zsh`.

| File | Covers |
|---|---|
| `10-syntax-versions.zsh` | `/bin/zsh -n` on every script and test file; `scriptVersion` alignment; `--release` and `--prerelease` versions; `diagnoseReminderState.zsh` version against `CHANGELOG.md`; extraction count checks |
| `20-assemble.zsh` | `assemble.zsh com.example.dortest --lane test` in a work-directory copy: three artifacts, no production RDNN, `reverseDomainNameNotation=` and `scriptLog` rewrites, starter placeholders intact, Demo Mode stripped, `plutil -lint`, `zsh -n`, `--lane bogus`, `--help` |
| `30-timestamps.zsh` | `epochFromISO8601Timestamp` and the deployment fallback date checks agree: `Z`, offsets, zone-less in two zones, impossible dates, spring-forward gap |
| `40-preferences.zsh` | `readPreferencePlistValue` statuses; precedence; the mid-load reload and its two warnings |
| `50-resolver.zsh` | `resolveDDMEnforcementFromInstallLog`: resolved, corroboration, NOTICE/WARNING split, both conflict forms, invalidVersion, noMatch, missing |
| `60-fallback.zsh` | `readFallbackDeclaration`, `selectMDMFallbackRequirement`, eligible statuses, stale/invalid fallback with resolved DDM, `applyFallbackDeclarationParameters` |
| `70-starter.zsh` | The extracted starter: `FALSE`, fingerprint seed/change/zero, change time, post-boot heartbeats, console users, DarkWake, stale `dor.pid`, live PID, missing/invalid state, write failures |
| `75-redeploy-assets.zsh` | `removeDeployedRuntimeAssets`: redeploy versus Uninstall |
| `80-runtime-state.zsh` | PID file, scheduler state reads, re-evaluation schedule, aggressive mode, Update Tonight, battery, DarkWake |
| `85-helpers.zsh` | `check-fixtures.zsh`, `diagnoseReminderState.zsh` exit codes, both Pending-OS EAs |

## Integration tier

`--integration` changes system state under the throwaway RDNN `com.example.dortest` only.

> **Production daemon hazard.** `launchDaemonManagement.zsh` modes `All`, `LaunchDaemon`, and `Uninstall` glob `/Library/LaunchDaemons/*.dor.plist`. They would boot out a production `org.churchofjesuschrist.dor`. The suite therefore deploys with `Script` mode only. Teardown never calls `Uninstall`.

What the tier touches:

- `/Library/Management/com.example.dortest/` (scripts, state, kill switch, fallback plist)
- `/Library/LaunchDaemons/com.example.dortest.dor.plist` and the loaded `com.example.dortest.dor` label
- `/Library/Preferences/com.example.dortest.dorm.plist`, which holds only `MeetingDelay` = `0`, so a display-sleep assertion cannot hold a test run for up to 75 minutes
- `/var/log/com.example.dortest.log`, which is kept and copied next to the results log as `dor-tests-<serial>-<timestamp>-com.example.dortest.log`
- swiftDialog, which `launchDaemonManagement.zsh` installs system-wide if it is missing

Teardown, after the tier and on any exit:

```zsh
launchctl bootout system/com.example.dortest.dor
rm -f /Library/LaunchDaemons/com.example.dortest.dor.plist
rm -rf /Library/Management/com.example.dortest
rm -f /Library/Preferences/com.example.dortest.dorm.plist
```

With `--keep`, the deployment and the work directory stay for inspection; run the commands above by hand when you are done. The next `--integration` run also removes leftovers before it starts. The helpers refuse to run if the test RDNN is `org.churchofjesuschrist`.

| File | Scenarios |
|---|---|
| `10-deploy.zsh` | `Script` deploy with a future zone-less Parameter 6: owners, modes, `launchctl print`, verbatim fallback plist, zone-less INFO. Past, malformed, and blank Parameter 6. Redeploy keeps the fingerprint, change time, and kill switch, and clears `NextScheduledReminder`. |
| `20-heartbeat.zsh` | `launchctl kickstart -k`, polling the log for up to 15 s: fingerprint seeding, a declaration-change launch, the `Declaration-change re-evaluation` line from `dor.zsh`, `FALSE`, and stale `dor.pid` (PID `1`, and a live process that is not `dor.zsh`). |
| `30-runtime-fixtures.zsh` | Manual runs of the deployed `dor.zsh` through `installLogPathOverride` and `ddmStatePersistencePlistPathOverride`: already-met NOTICE, impossible deadline, stale and invalid fallback with resolved DDM, and the outside-window interaction cutoff with valid, invalid, and future `LastDeclarationChangeDetected`. |
| `40-dialogs.zsh` | Real dialogs you confirm at a `y/n` prompt: the initial reminder after an ignored interaction, `demo`, `demo aggressive`, and `reminderDialogPreferenceTest.zsh --rdnn com.example.dortest` with `--pre-deadline-threshold 5`, `--aggressive`, and `--battery-percentage 99`. Left out by `--skip-dialogs`. |

How the tier keeps live heartbeat runs quiet and fast:

- Live heartbeats run the deployed `dor.zsh` against this Mac's real DDM state. Before each kickstart the suite appends a fresh `Return Code: 2` line to the test log (quiet period) and keeps `dor-aggressive-kill` in place. Between scenarios it sets `NextScheduledReminder` to `FALSE`. A reminder can still appear if a pre-deadline threshold of the Mac's real declaration is due during the run.
- A manual run of the assembled `dor.zsh` logs only to stdout, because `assemble.zsh` comments out its `tee`. The suite captures stdout for its checks and writes interaction history directly into `/var/log/com.example.dortest.log`.
- `dor.zsh` pauses 30–90 s at random on non-starter runs (0–20 min at exactly 08:00 or 16:00) just before the dialog. Headless scenarios exit before that point. The dialog scenario sets `DOR_LAUNCH_SOURCE=starter`, the existing launch-source hook, which skips the pause and writes test-RDNN scheduler state only.
- The deployed `dor.zsh` has no demo mode, because `assemble.zsh` strips it. Demo scenarios run a work-directory copy of this checkout's `reminderDialog.zsh` with `reverseDomainNameNotation` and `scriptLog` rewritten to `com.example.dortest`.
- `demo Force` is reported as SKIP. In Force mode, both the button and the timer run `/sbin/shutdown -r now`, so it would restart the test Mac in the middle of the run. To check it, run `sudo zsh reminderDialog.zsh demo Force` by hand on a disposable Mac.

## Running pieces in an agent shell

In some agent shells, `zsh -n reminderDialog.zsh` and full runs of `reminderDialog.zsh` are killed (exit `137`). The suite always uses `/bin/zsh -n < file` and runs extracted functions instead. Root-only checks need a real `sudo` run on a test Mac. These are the ownership checks in `60-fallback.zsh`, which are skipped when not root, and the whole integration tier.
