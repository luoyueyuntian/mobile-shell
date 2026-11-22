# Host Tag Navigation Design

## Goal

Add Termius-style host tag navigation so tags are not only searchable metadata, but also fast filters for moving through a larger personal host list.

## Product Context

Termius describes Hosts as carrying metadata such as labels and tags for search and navigation. MobileShell already stores tags on every host and includes tags in text search, but the user cannot browse available tags or tap a tag to narrow the host list. This slice turns existing tag data into an explicit navigation control without adding team, cloud, or sharing behavior.

## Scope

- Add `selectedHostTag` to `MobileShellStore`.
- Add `hostTags()` to return unique host tags sorted case-insensitively.
- Add `selectHostTag(_:)` and `clearSelectedHostTag()` store actions.
- Update `filteredHosts()` so text search and selected tag filtering combine.
- Add a compact horizontal tag strip above Groups and Hosts in the Hosts screen.
- Show an "All" chip and one chip per known tag.
- Keep tag selection local in memory; it is a transient navigation state, not persisted vault data.

This slice does not introduce nested tags, team-shared tag metadata, tag colors, or label entities. Tags remain strings attached to hosts.

## Architecture

The store remains the source of truth for host filtering. `filteredHosts()` will first apply the selected tag exact match with case-insensitive comparison, then apply the existing free-text query over host name, address, username, group, and tags. A new `HostTagFilterStrip` SwiftUI component renders tag chips and forwards selection changes to the store.

Because `ShellRootView.swift` is already oversized, the tag strip is implemented as a small focused component under `MobileShell/Features/Hosts/HostTagFilterStrip.swift`. The Hosts screen composes that component but does not own tag filtering logic.

## UX

- The strip appears after Quick Import and before Groups.
- "All" clears the tag filter.
- Selected chips use the existing accent color.
- Tag chips show lowercase or original stored text exactly as returned by the store.
- If there are no tags, the strip is hidden.
- Existing search remains available and stacks with the selected tag.

## Testing

- Unique tag list trims empty tags, de-duplicates case-insensitively, and sorts predictably.
- Selecting a tag filters hosts by exact tag membership.
- Search and selected tag filters combine.
- Clearing the selected tag restores normal search-only filtering.
