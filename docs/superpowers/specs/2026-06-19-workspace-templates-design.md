# Workspace Templates Design

## Goal

Add personal Termius-style workspace templates so a user can save the current terminal workspace setup and reopen the same host set later with one tap.

## Product Context

Termius documents Workspaces as a way to group multiple terminal sessions, broadcast commands, save templates, and reopen a setup later. This app should keep the personal workflow and skip team, cloud, or sharing behavior.

## Scope

- Save the selected workspace as a local template.
- Preserve the template name, ordered host IDs from visible workspace sessions, and the workspace broadcast setting.
- Reopen a template by creating a fresh workspace, selecting it, restoring the broadcast setting, and connecting each saved host that still exists locally.
- Persist templates through the existing JSON host snapshot.
- Expose template save/open controls in the existing terminal workspace switcher.

This slice does not restore remote working directories, running commands, pane geometry, cloud sync, template sharing, or team permissions.

## Architecture

- Add `TerminalWorkspaceTemplate` under `MobileShell/Features/Workspaces/` as a small `Codable`, `Equatable`, `Identifiable` model.
- Extend `HostPersistenceSnapshot` with `terminalWorkspaceTemplates`, decoded with a default empty array for existing installs.
- Add `MobileShellStore.terminalWorkspaceTemplates` plus focused methods:
  - `saveSelectedWorkspaceAsTemplate(name:)`
  - `openWorkspaceTemplate(_:)`
  - `deleteWorkspaceTemplate(_:)`
  - `templateHostNames(for:)`
- Reuse existing workspace and terminal-session behavior instead of adding a new session-opening path. Opening a template calls `createTerminalWorkspace(name:)`, applies broadcast mode, then calls `connect(to:)` for each saved host.
- Update `TerminalWorkspaceSwitcher` to show a save-template action for non-empty selected workspaces and horizontal template chips for quick reopen.

## Testing

- Saving a selected workspace trims the name, stores only visible workspace hosts in order, deduplicates repeated host IDs, preserves broadcast mode, records history, and persists.
- Saving without a selected workspace or without visible sessions returns `nil`.
- Opening a template creates/selects a workspace, connects template hosts, restores broadcast mode, and records history.
- Templates round-trip through `HostPersistenceSnapshot`.
