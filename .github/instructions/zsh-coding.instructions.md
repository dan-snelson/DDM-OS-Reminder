---
name: Zsh Coding Standards
description: Core Zsh conventions for this project
applyTo: "**/*.zsh"
---

# Zsh Coding Standards (DDM OS Reminder)

## Validation
- Run `zsh -n <file>` after every edit.
- If `zsh -n` fails to execute or produces validation errors: Verify Zsh is installed and retry. If validation still fails, escalate to the project lead.
- If a file cannot pass validation after multiple attempts: Escalate to the project lead.
- If using a non-standard Zsh configuration and compatibility cannot be ensured, revert to the standard configuration or consult the project lead.

## Naming & Style

### Variable Naming
- Use lowerCamelCase (exception: existing `PLACEHOLDER_MAP`).

### Function Definitions
- Use `function name() {` style with same-line braces.
- If this style is not followed, refactor the code to comply.

### String Handling
- Prefer `"${var}"` expansions.
- Use single quotes for static strings unless the string contains variables.

## Logging
1. Use existing logging helper functions with this exact format:  
   `<scriptName> (<version>): <timestamp> - [<level>] <message>`
2. Use `[NOTICE]` or `[WARNING]` for events such as script execution failures, suppression of key processes, or reaching restart thresholds.
3. If logging helpers fail: Log directly to stderr using the same format.
4. If both helpers and stderr fail: Write the error to a temporary file and notify the project lead.

## Visual Structure & Comments
- Use hash walls (`#`) for major sections.
- Leave **at least 2 blank lines** between sections.
- Keep comments short and purposeful (explain *why*, not *what*).
