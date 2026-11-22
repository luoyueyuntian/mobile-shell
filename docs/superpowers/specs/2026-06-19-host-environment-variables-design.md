# Host Environment Variables Design

## Context

Termius treats hosts as saved connection records and groups as inherited configuration containers. Official documentation lists environment variables among group-level properties that hosts can inherit, and snippets/startup snippets are part of the terminal workflow. MobileShell already supports host groups, group inheritance, startup snippets, terminal sessions, and session logs, so environment variables should fit into that existing inheritance model instead of becoming a separate settings island.

## Goal

Add personal environment variables for hosts and groups. A group can define default variables for hosts in that group, and a host can add or override variables for itself. When a new terminal session opens, MobileShell exports the resolved variables before running the startup snippet.

## Data Model

Add a small shared model:

```swift
struct ShellEnvironmentVariable: Identifiable, Equatable, Codable, Sendable {
    var key: String
    var value: String
    var id: String { key }
}
```

`ShellHost` stores `[ShellEnvironmentVariable]`, defaulting to `[]` for legacy JSON. `HostGroupProfile` stores `[ShellEnvironmentVariable]`, defaulting to `[]`.

## Resolution Rules

`MobileShellStore.environmentVariables(for:)` returns group variables plus host variables. Keys are case-sensitive shell names. If the same key appears in both, the host value wins. Output is sorted by key so tests, logs, and generated commands are deterministic.

Invalid or blank keys are filtered at write time. Valid keys follow shell variable name rules:

```text
[A-Za-z_][A-Za-z0-9_]*
```

Values are trimmed of outer whitespace but otherwise preserved.

## Terminal Injection

When a new terminal session opens:

1. Resolve environment variables for the host.
2. Emit one `export KEY='escaped value'` command per variable.
3. Run the startup snippet after the exports.

The same ordering applies to preview terminals and live shell terminals. Export commands are recorded in terminal lines and session logs, making startup behavior auditable.

Single quotes inside values are escaped with the POSIX-safe sequence:

```text
'\''
```

## UI

Add an Environment section to the group editor, add-host sheet, and edit-host sheet. Each section uses a multiline text editor with one `KEY=value` per line. Group helper text says hosts inherit these variables. Host helper text says host variables override group variables with the same key.

This keeps the first implementation compact while still making the feature usable on iPhone.

## Testing

Add focused XCTest coverage under `MobileShellTests/Features/Environment/` for:

- group environment variables inheriting to hosts
- host environment variables overriding group values
- invalid lines being ignored during add/update
- host and group environment variables round-tripping through JSON persistence
- export commands running before startup snippets
- live shell sessions receiving export commands before startup snippets

## Non-Goals

- Team vault sharing
- Secret storage for environment variable values
- Interactive snippet parameter prompts
- Shell-specific export syntaxes beyond POSIX-style `export`

## Self-Review

Placeholder scan: No placeholders remain.

Consistency check: The model, resolver, terminal injection, UI, and tests all use the `ShellEnvironmentVariable` name and host-over-group precedence.

Scope check: This is a single implementation slice that advances Termius-style personal configuration inheritance without adding team features.
