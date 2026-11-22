# Terminal Font Size Inheritance Design

## Goal

Add Termius-style terminal font size settings for personal hosts and groups, using the same host-over-group-over-default inheritance model as terminal themes.

## Product Context

Termius mobile terminal appearance settings include theme, font, and font size. MobileShell now supports inherited terminal themes, but terminal text still uses a fixed size. Adding font size presets makes terminal appearance customization more complete without introducing custom font management or team-shared settings.

## Scope

- Add built-in `TerminalFontSize` presets.
- Add optional `terminalFontSize` to `ShellHost`.
- Add optional `terminalFontSize` to `HostGroupProfile`.
- Add `terminalFontSize(for:)` to resolve host font size, then group font size, then `.standard`.
- Persist host and group font size choices through existing JSON snapshots.
- Add terminal font size pickers to Add Host, Edit Host, and Edit Group sheets.
- Apply the resolved font size to terminal output for the selected terminal session.

This slice does not add custom numeric font sizes, custom font families, or global app-wide appearance settings.

## Architecture

`TerminalFontSize` lives beside `TerminalTheme` in `MobileShell/Features/Terminal/TerminalTheme.swift` because both are small terminal appearance presets. `ShellHost` and `HostGroupProfile` store optional enum values; legacy JSON decodes missing values as `nil`. `MobileShellStore.terminalFontSize(for:)` is the single resolver used by tests and UI.

`TerminalView` computes the selected font size from the selected session's host and applies its point size to terminal output. Host and group editors expose optional pickers. A host set to "Group / Default" inherits the group font size when available.

## Presets

- `.small`: 12 pt
- `.standard`: 13 pt
- `.large`: 15 pt
- `.extraLarge`: 17 pt

## Testing

- Default font size resolves to `.standard` when host and group have no font size.
- Group font size is inherited by hosts in that group.
- Host font size overrides group font size.
- Host and group font size choices persist through the repository.
- Updating a group profile stores a terminal font size reference.
