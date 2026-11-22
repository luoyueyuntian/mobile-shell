# Snippet Multi-Execution Design

## Goal

Add personal Termius-style snippet multi-execution so a saved snippet can be executed across the current visible terminal set with one action.

## Product Context

Termius Snippets support running saved commands on multiple hosts. This app already has snippets, terminal sessions, workspaces, and workspace command broadcast, so the personal version should reuse those primitives and avoid team, cloud, or shared-target behavior.

## Scope

- Add a Store API to execute one snippet across `visibleTerminalSessions()`.
- Use the selected workspace as the target scope when one is selected; otherwise target all active terminal sessions.
- Ignore blank snippets and empty target sets.
- Append prompt/output lines and session logs using the same command path as single-session and broadcast execution.
- Record one high-level history item for the multi-exec action.
- Add a Snippet row menu action to run the snippet in visible terminals.

This slice does not implement saved target groups, choosing arbitrary offline hosts, cloud sync, or team-shared snippets.

## Architecture

- Add `@MainActor runSnippetInVisibleTerminals(_:) async -> Int` to `MobileShellStore`.
- The method trims the snippet command, collects visible session IDs, calls the existing private `sendRemoteCommand(_:in:recordHistory:clearDraft:)` for each target, inserts a summary history entry, persists, and returns the executed session count.
- `SnippetsView` passes a menu action into `SnippetRow`; the action starts an async task and disables itself when there are no visible terminal sessions.
- Tests live under `MobileShellTests/Features/Snippets/` and focus on Store behavior, because SwiftUI menu wiring is covered by compilation.

## Testing

- Running a snippet with no selected workspace targets all active terminal sessions.
- Running a snippet with a selected workspace targets only sessions visible in that workspace.
- Empty visible targets are ignored and return zero.
- Stale snippets not in the store are ignored.
