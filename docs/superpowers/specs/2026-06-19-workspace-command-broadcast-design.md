# Workspace Command Broadcast Design

## Goal

Add personal Termius-style command broadcasting for terminal workspaces. When broadcast is enabled for a workspace, the same command can be sent to every terminal session currently visible in that workspace.

## Scope

This slice implements broadcast execution for the selected workspace or the current visible terminal set. It does not yet implement split-view rendering or saved workspace templates.

## Architecture

- `TerminalWorkspace.isBroadcastEnabled` becomes an active setting, toggled through `MobileShellStore.setBroadcastEnabled(_:for:)`.
- `MobileShellStore.broadcastCommand(_:)` trims input, finds `visibleTerminalSessions()`, and sends the command to each visible session.
- `runRemoteCommand(_:)` and `broadcastCommand(_:)` share a private `runRemoteCommand(_:in:recordHistory:)` helper so single-session and broadcast execution stay behaviorally aligned.
- The helper appends the prompt to each target session, writes to session logs, uses active shells when present, falls back to remote executor when available, and uses preview output otherwise.
- `TerminalWorkspaceSwitcher` shows a broadcast toggle when a workspace is selected.
- `CommandBar` shows a broadcast button when the selected workspace has broadcasting enabled; tapping it sends the current draft to the visible workspace sessions.

## Testing

Focused tests extend `MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift`:

- Broadcast sends a command to every visible workspace session and not to sessions outside the selected workspace.
- Blank broadcast input is ignored.
- Broadcast enabled state can be toggled and persisted through `HostPersistenceSnapshot`.
