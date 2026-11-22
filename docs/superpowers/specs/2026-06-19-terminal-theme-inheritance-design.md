# Terminal Theme Inheritance Design

## Goal

Add Termius-style terminal theme settings for personal hosts and groups, with host-level theme overriding group-level theme and a built-in default when neither is set.

## Product Context

Termius documents mobile terminal appearance settings such as theme, font, and font size. Termius Groups can also set a terminal theme so hosts in the group share the same appearance. MobileShell already has host and group inheritance for identities, jump hosts, and startup snippets, so terminal theme inheritance fits the existing personal settings model without adding team sync or shared vault behavior.

## Scope

- Add built-in `TerminalTheme` presets.
- Add optional `terminalTheme` to `ShellHost`.
- Add optional `terminalTheme` to `HostGroupProfile`.
- Add `terminalTheme(for:)` to resolve host theme, then group theme, then `.obsidianNeon`.
- Persist host and group terminal theme choices through existing JSON snapshots.
- Add terminal theme pickers to Add Host, Edit Host, and Edit Group sheets.
- Apply the resolved theme to terminal text/background for the selected terminal session.

This slice does not add custom theme editing, font family selection, font size selection, or cloud/team shared themes.

## Architecture

`TerminalTheme` lives under `MobileShell/Features/Terminal/TerminalTheme.swift` and owns display names plus terminal colors. `ShellHost` and `HostGroupProfile` store optional enum values; legacy JSON decodes missing values as `nil`. `MobileShellStore.terminalTheme(for:)` is the single resolver used by tests and UI.

`TerminalView` computes a selected terminal theme from the selected session's host and uses it for the terminal scroll area, prompt/accent line, and empty-state text. Host and group editors provide optional pickers. A host set to "Group / Default" inherits the group theme when available.

## Testing

- Default theme resolves to `.obsidianNeon` when host and group have no theme.
- Group theme is inherited by hosts in that group.
- Host theme overrides group theme.
- Host and group theme choices persist through the repository.
- Updating a group profile stores a terminal theme reference.
