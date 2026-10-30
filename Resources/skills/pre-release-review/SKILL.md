---
name: pre-release-review
description: >
  Review DDM OS Reminder for release readiness before a release or a pull request
  from development to main. Audit the whole repository, release versions,
  runtime and deployment contracts, documentation, and generated artifacts.
  Use for pre-release reviews or /pre-release-review; ordinary focused code
  reviews do not require this workflow.
---

# Pre-release review

Perform an independent, read-only release audit. Read [AGENTS.md](../../../AGENTS.md)
first and follow its source-of-truth order and authorization boundaries. A review
request does not authorize fixes, tracked artifact regeneration, dependency
installation, commits, pushes, or publication. Treat prior reviews and passing
checks as evidence to verify.

## Establish the release

- Use the requested release version, source branch, and target branch. Default
  branches are `development` and `main`; honor explicit overrides.
- If no version is supplied, infer it only when release entrypoints and current
  release documentation agree. Ask for the intended version when they disagree.
- Record audited commit IDs, working-tree status, and local/remote differences.
  State whether remote refs were verified or only cached refs were available.
  Review named refs without switching branches or disturbing local changes.
- Inventory all tracked files, including hidden configuration, helpers, fixtures,
  diagrams, workflows, and generated artifacts. Use `$workspace` when available;
  otherwise use `git ls-files` and targeted searches. Inventory broadly, then read
  owning code and relevant contracts rather than loading duplicate generated code.
- Compare the source branch against the target branch. Inspect unchanged code
  where it interacts with release changes, and label pre-existing defects.

## Audit release versions

- Search tracked content, including dotfiles and ignored-looking tracked logs,
  with `git grep` or equivalent. Escape the target version before constructing
  search expressions. Inspect embedded scripts and decoded self-extracting
  payloads when present; do not execute deployment payloads.
- Find every beta reference for the target version, including documentation
  history, fixture input, fixture assertions, and generated metadata. Report exact
  locations and counts. The default stable-release requirement is zero remaining
  target-version beta references in the tracked working tree. Record any explicit
  maintainer exception instead of silently excluding history or tests.
- Check release entrypoint versions, README, CHANGELOG, security support
  statements, and packaged metadata for agreement. Preserve independently
  versioned helpers, unrelated historical versions, and Git history.
- Identify linked fixture input and expected-output changes together. Report
  corrections needed; do not make replacements during the audit.

## Review repository contracts

Use the current owning code and nearby documentation to check:

| Area | Contracts to inspect |
| --- | --- |
| DDM resolution | Declaration corroboration, compliance checks, fallback eligibility, fail-safe suppression, and agreement with Pending-OS Extension Attributes |
| Scheduling and dialog lifecycle | Baseline slots, threshold delivery, quiet periods, aggressive cadence, post-boot re-evaluation, DarkWake, and interactions across timing boundaries |
| Deployment and packaging | RDNN consistency, reset/uninstall preservation, parameter forwarding, atomic replacement, download verification, installer status, installed version checks, permissions, and temporary files |
| Preferences and localization | Canonical sample surface, runtime defaults, managed/local precedence, validation, English fallback, existing language families, and generated configuration |
| Observability and security | Structured logs, diagnostic accuracy, redaction, compatibility, blocking scan/finalizer behavior, and full-SHA action pins |
| Release deliverables | Source/embedded-runtime parity after documented assembly transformations, plist/mobileconfig agreement, diagram exports, links, and operator guidance |

Trace failure paths and transitions, not only successful entrypoints. In particular,
exercise unsuccessful dialog launches, dialogs acknowledged after a scheduling
boundary, support suppression, failed installations, and installed versions below
the required minimum. Do not assume a scheduled time remains valid after a dialog
or other long-running operation returns.

## Validate safely

- Run `zsh -n` on every tracked Zsh script. Check extracted embedded runtime and
  starter scripts separately; parsing an outer heredoc does not validate its code.
- Run existing safe fixture suites and `plutil -lint` on tracked plist and
  mobileconfig files. Check the branch diff with `git diff --check`.
- Compare generated content with its source using documented assembly
  transformations. Do not regenerate tracked `Artifacts/` during this review.
- Use isolated temporary fixtures and mocked commands to reproduce material
  failures. Exercise actual owning functions when practical, and identify mocked
  assumptions. Keep test behavior outside default production paths.
- Inspect side effects before demo or build validation. Run only within existing
  authorization; avoid live deployment, installation, restart, or production-state
  changes. Report any required validation that could not be run.
- Distinguish local checks from hosted CI results. A timeout, killed process, or
  unavailable tool is an incomplete check, not a syntax finding or a pass.

## Report release readiness

Lead with actionable findings ordered by severity. Each finding needs a file and
line, a concrete trigger, actual versus expected behavior, impact, the smallest
responsible fix, and supporting evidence. Label reproduced defects, static
findings, unresolved hypotheses, and pre-existing issues accurately.

Include a concise workspace summary and relevant-file links, beta-reference counts,
checks passed/failed/not run, and material limitations. State whether the audited
branch is ready for the requested pull request and identify blockers. If fixes are
needed, provide a concrete correction and validation plan; the audit does not
authorize implementing it. If no actionable findings remain, say so without
implying unrun checks passed.

Prioritize correctness and release risk. Omit cosmetic findings, speculative
defects, and unrelated refactoring. Syntax success alone does not establish
release readiness.

## Example invocation

```text
Use $pre-release-review to review development against main for version <VERSION>.
```
