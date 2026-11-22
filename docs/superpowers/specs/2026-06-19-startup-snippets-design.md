# Startup Snippets Design

## Goal

Add personal Termius-style startup snippets so a saved command can run automatically when a new terminal session is opened for a host.

## Product Context

Termius documents startup snippets as commands that run automatically every time a host is connected. This app should implement the personal/local version and skip team sharing, cloud sync, and shared vault behavior.

## Scope

- Hosts can reference one saved snippet as their startup snippet.
- Adding or editing a host can attach, change, or remove the startup snippet reference.
- Opening a new terminal session for a host with a startup snippet automatically runs that snippet once for that new session.
- Selecting an already-open session for the same host does not run the startup snippet again.
- Deleting a snippet removes that startup reference from any hosts that used it.
- Host JSON persistence keeps the startup snippet reference and defaults legacy hosts to no startup snippet.

This slice does not implement snippet variables, team sharing, snippet folders, or snippet multi-execution. Workspace broadcast already covers manual multi-session command execution.

## Architecture

- Add `startupSnippetID: ShellSnippet.ID?` to `ShellHost` with backward-compatible `Codable` decoding.
- Extend `MobileShellStore.addHost` and `MobileShellStore.updateHost` to accept an optional startup snippet ID.
- Add helper methods to resolve a host's startup snippet and expose its title to views.
- Refactor connection creation so `connect(to:)` can run startup snippets for preview/test sessions, while `openInteractiveTerminal(for:)` starts the live shell first and then sends the startup command to the active shell.
- Update add/edit host sheets with an "Automation" picker for startup snippets and show a small startup-snippet badge on host rows.

## Testing

- Host startup snippet references persist through `HostPersistenceSnapshot`.
- Adding and editing hosts can attach and remove startup snippets.
- Connecting a new session runs the startup snippet once and records terminal/session-log output.
- Re-selecting an existing session does not run the startup snippet again.
- Deleting a snippet detaches it from hosts and persists the cleanup.
