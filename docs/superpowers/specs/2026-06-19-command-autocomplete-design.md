# Command Autocomplete Design

## Goal

Add a personal Termius-style command autocomplete layer for terminal input. The first slice uses local data sources already present in MobileShell: snippets, command history, and a small built-in command catalog.

## Scope

This implements local autocomplete only. It does not yet inspect remote shell paths, shell aliases, or command arguments from a live server. Those require a later shell-integration layer.

## Architecture

- `CommandSuggestion` models one suggestion with a command, display title, source, and optional detail.
- `CommandAutocompleteEngine` is a pure feature-local type that ranks and deduplicates suggestions from snippets, history, and built-ins.
- `MobileShellStore` exposes a small `commandSuggestions(for:)` API and an `applyCommandSuggestion(_:)` action that writes the selected command into the active terminal draft.
- `CommandBar` renders a compact horizontal suggestion strip above the input when the current draft has matches.

## Ranking

Suggestions are ranked by source priority, then match quality:

1. Snippets
2. History
3. Built-ins

Prefix matches rank ahead of substring matches inside the same source. Duplicate commands are collapsed so a command appears once.

## Testing

Focused tests live in `MobileShellTests/Features/Autocomplete/CommandAutocompleteTests.swift`. They cover ranking, deduplication, blank input, applying a suggestion to a selected terminal draft, and the snippet-to-active-terminal behavior that users expect from the existing snippets UI.
