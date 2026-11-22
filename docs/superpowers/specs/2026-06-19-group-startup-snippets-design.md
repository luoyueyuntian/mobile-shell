# Group Startup Snippets Design

## Goal

Add Termius-style group inheritance for startup snippets so hosts can inherit a startup command from their group unless they define their own host-level startup snippet.

## Product Context

Termius documents Groups as an organization layer that can define protocol settings inherited by Hosts. This app already supports group-level identities and jump hosts, and host-level startup snippets. Extending the same inheritance model to startup snippets makes group defaults more complete without adding team or cloud behavior.

## Scope

- Add `startupSnippetID` to `HostGroupProfile`.
- Let `MobileShellStore.startupSnippetTitle(for:)` and connection startup execution use host-level startup snippets first, then group-level startup snippets.
- Let group editor sheets assign or clear a group startup snippet.
- Show group startup snippet metadata in group cards.
- Deleting a snippet detaches it from both hosts and group profiles.
- Persist group startup snippet references through existing host JSON.

This slice does not add a host-level "explicitly disable inherited startup snippet" state. A host can override a group startup snippet by choosing another snippet.

## Architecture

- Extend `HostGroupProfile` with optional `startupSnippetID`.
- Update `MobileShellStore.upsertHostGroupProfile` to accept and save `startupSnippetID`.
- Update `startupSnippet(for:)` to resolve `host.startupSnippetID ?? hostGroupProfile(for: host)?.startupSnippetID`.
- Update snippet deletion cleanup to clear group profile startup references.
- Add `startupSnippetSummary(forGroup:)` UI helper and an Automation picker in `HostGroupEditorSheet`.

## Testing

- Group profile creation stores startup snippet references.
- Host startup snippet lookup falls back to group startup snippet.
- Host startup snippet overrides group startup snippet.
- Connecting a host runs the inherited group startup snippet.
- Deleting a snippet detaches it from group profiles and persists cleanup.
