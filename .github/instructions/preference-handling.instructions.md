---
name: Preference Handling Rules
description: Rules for preference reads, precedence, and localization
applyTo: "**/*Preference*.zsh,Resources/**/*.plist,Resources/sample.plist"
---

# Preference Handling Rules

## 1. Precedence (Highest Priority)
- Always preserve strict precedence: **Managed Preferences → Local Preferences → Defaults**.
- When starting from `Resources/sample.plist`, ensure all changes respect the precedence order above.

## 2. Tool Usage
- Always use `PlistBuddy` for preference reads — never `defaults read`.
- If `PlistBuddy` is unavailable or fails: Log an error and halt the operation.
- If `PlistBuddy` produces partial or inconsistent output: Log a warning and retry the operation up to 3 times before halting.

## 3. Starting Point & Missing Files
- Start from `Resources/sample.plist` when making localization or preference changes.
- If `Resources/sample.plist` is missing or inaccessible: Log an error and halt the operation.

## 4. Localization
- Validate fallback behavior for English and all languages listed in `Resources/README.md`.
- If a language family is unsupported or missing: Default to English and log a warning.
- Update relevant docs (`README.md`, `Resources/README.md`, `CHANGELOG.md`) when operator-facing behavior changes.
