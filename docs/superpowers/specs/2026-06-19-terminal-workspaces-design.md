# Terminal Workspaces Design

## Goal

Add personal Termius-style terminal workspaces so active terminal sessions can be grouped into named contexts and switched without losing the global session list.

## Scope

This slice implements workspace creation, selection, terminal-session membership, local persistence, and a compact terminal workspace switcher. It intentionally does not yet implement command broadcasting, saved workspace templates, or monitoring widgets; the model leaves room for those follow-up slices.

## Architecture

- `TerminalWorkspace` lives under `MobileShell/Features/Workspaces/` and stores a name, ordered terminal session IDs, and a broadcast flag for later command-broadcast support.
- `MobileShellStore` owns `terminalWorkspaces`, `selectedWorkspaceID`, workspace CRUD helpers, and `visibleTerminalSessions()`.
- `connect(to:)` assigns the opened or selected terminal session to the active workspace when one is selected.
- `closeTerminalSession(_:)` removes the session from all workspaces and chooses the next selected session from the currently visible workspace.
- `HostPersistenceSnapshot` persists workspace metadata with backward-compatible decoding.
- `TerminalWorkspaceSwitcher` renders `All` plus named workspace pills above terminal tabs and lets users create a workspace from the terminal screen.

## Data Flow

`TerminalWorkspaceSwitcher -> MobileShellStore.create/select -> TerminalView.visibleTerminalSessions -> TerminalSessionPill`

Terminal execution remains unchanged. Workspaces only decide which terminal tabs are visible and which workspace receives newly opened sessions.

## Testing

Focused tests live in `MobileShellTests/Features/Workspaces/TerminalWorkspaceTests.swift`. They cover workspace creation, connecting into a selected workspace, filtering visible sessions, cleanup after closing sessions, and persistence round-trip.
