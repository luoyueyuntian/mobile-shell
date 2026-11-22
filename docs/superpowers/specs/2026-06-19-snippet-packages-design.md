# Snippet Packages Design

## Context

Termius documents snippets as saved commands that can be pasted or run from the terminal and organized with snippet packages. MobileShell already supports saved snippets, startup snippets, running snippets in visible terminals, and autocomplete suggestions, but snippets are stored as a flat list.

## Scope

- Add a personal package label to each `ShellSnippet`.
- Decode legacy snippets without a package into the default package `Personal`.
- Allow add/update flows to set and trim package names.
- Expose grouped snippet packages in the store for stable UI rendering.
- Show snippet packages in the Snippets view and autocomplete detail.

## Non-Goals

- No team sharing, permissions, or vault behavior.
- No separate package CRUD screen.
- No package icons, colors, or nested packages.

## Model

`ShellSnippet` gains:

```swift
static let defaultPackageName = "Personal"
var packageName: String
```

The member initializer keeps `packageName` defaulted to `ShellSnippet.defaultPackageName` so existing tests and call sites remain source-compatible.

Legacy decoding:

- Missing `packageName` decodes to `Personal`.
- Blank persisted `packageName` also normalizes to `Personal`.

Store APIs:

```swift
func addSnippet(title: String, command: String, packageName: String = ShellSnippet.defaultPackageName) -> ShellSnippet?
func updateSnippet(_ snippet: ShellSnippet, title: String, command: String, packageName: String = ShellSnippet.defaultPackageName) -> ShellSnippet?
func snippetPackages() -> [SnippetPackageSection]
```

`SnippetPackageSection` is a lightweight derived grouping:

```swift
struct SnippetPackageSection: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var snippets: [ShellSnippet]
}
```

Sorting:

- Package sections sort case-insensitively by name.
- Snippets inside each package sort by title case-insensitively.

## UI

- Snippets list renders package headers with counts.
- Snippet rows show the package in a small badge.
- Snippet editor adds a `Package` text field.
- Empty package input saves as `Personal`.

## Autocomplete

Snippet suggestions keep source `.snippet` and set `detail` to `"<package> package"` so the UI can distinguish similarly named snippets.
