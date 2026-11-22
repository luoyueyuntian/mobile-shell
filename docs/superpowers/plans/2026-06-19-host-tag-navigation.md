# Host Tag Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Termius-style tag navigation for saved hosts.

**Architecture:** `MobileShellStore` owns tag discovery and filtering state. A small `HostTagFilterStrip` SwiftUI component renders tag chips and calls store actions, while `HostsView` simply composes the strip above the grouped host list.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest.

---

### Task 1: Store-Level Tag Navigation Tests

**Files:**
- Create: `MobileShellTests/Features/Hosts/HostTagNavigationTests.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Write failing tests**

Create tests for tag discovery, tag filtering, search combination, and clearing:

```swift
import XCTest
@testable import MobileShell

final class HostTagNavigationTests: XCTestCase {
    func testHostTagsReturnsUniqueCaseInsensitiveSortedTags() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api", tags: ["ssh", "Prod", "api"]),
            makeHost(name: "worker", tags: ["SSH", "prod", "worker"]),
            makeHost(name: "empty", tags: ["", "  "])
        ])

        XCTAssertEqual(store.hostTags(), ["api", "Prod", "ssh", "worker"])
    }

    func testSelectingHostTagFiltersHostsByExactTagMembership() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api", tags: ["ssh", "prod", "api"]),
            makeHost(name: "cache", tags: ["ssh", "dev", "cache"]),
            makeHost(name: "db", tags: ["ssh", "prod", "db"])
        ])

        store.selectHostTag("prod")

        XCTAssertEqual(store.selectedHostTag, "prod")
        XCTAssertEqual(store.filteredHosts().map(\.name), ["api", "db"])
    }

    func testSearchCombinesWithSelectedHostTag() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api-prod", address: "10.0.0.10", tags: ["ssh", "prod", "api"]),
            makeHost(name: "worker-prod", address: "10.0.0.20", tags: ["ssh", "prod", "worker"]),
            makeHost(name: "api-dev", address: "10.0.0.30", tags: ["ssh", "dev", "api"])
        ])

        store.selectHostTag("prod")
        store.searchText = "api"

        XCTAssertEqual(store.filteredHosts().map(\.name), ["api-prod"])
    }

    func testClearingSelectedHostTagRestoresSearchOnlyFiltering() {
        let store = MobileShellStore(hosts: [
            makeHost(name: "api-prod", tags: ["ssh", "prod", "api"]),
            makeHost(name: "api-dev", tags: ["ssh", "dev", "api"])
        ])

        store.selectHostTag("prod")
        store.searchText = "api"
        XCTAssertEqual(store.filteredHosts().map(\.name), ["api-prod"])

        store.clearSelectedHostTag()

        XCTAssertNil(store.selectedHostTag)
        XCTAssertEqual(store.filteredHosts().map(\.name), ["api-prod", "api-dev"])
    }

    private func makeHost(
        name: String,
        address: String = "example.com",
        tags: [String]
    ) -> ShellHost {
        ShellHost(
            id: UUID(),
            name: name,
            address: address,
            username: "deploy",
            group: "Production",
            tags: tags,
            status: .idle
        )
    }
}
```

- [x] **Step 2: Run and verify RED**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostTagNavigationTests
```

Expected: FAIL because `selectedHostTag`, `hostTags()`, `selectHostTag(_:)`, and `clearSelectedHostTag()` do not exist.

### Task 2: Store Tag Filtering

**Files:**
- Modify: `MobileShell/Models.swift`

- [x] **Step 1: Add tag filter state**

Add `var selectedHostTag: String?` near `searchText`.

- [x] **Step 2: Add tag discovery and selection actions**

Implement:

```swift
func hostTags() -> [String] {
    var tagsByLowercase: [String: String] = [:]
    for tag in hosts.flatMap(\.tags) {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { continue }
        let key = trimmedTag.lowercased()
        if tagsByLowercase[key] == nil {
            tagsByLowercase[key] = trimmedTag
        }
    }
    return tagsByLowercase.values.sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
}

func selectHostTag(_ tag: String) {
    let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
    selectedHostTag = trimmedTag.isEmpty ? nil : trimmedTag
}

func clearSelectedHostTag() {
    selectedHostTag = nil
}
```

- [x] **Step 3: Combine tag and search filters**

Update `filteredHosts()` to filter by exact selected tag membership before applying the existing text query.

- [x] **Step 4: Run targeted tests and verify GREEN**

Run the same targeted `xcodebuild test` command. Expected: PASS.

### Task 3: Hosts UI Tag Strip

**Files:**
- Create: `MobileShell/Features/Hosts/HostTagFilterStrip.swift`
- Modify: `MobileShell/ShellRootView.swift`
- Modify: `MobileShell.xcodeproj/project.pbxproj`

- [x] **Step 1: Create `HostTagFilterStrip`**

Create a SwiftUI view that renders no content when `tags` is empty, otherwise renders an "All" chip and one chip per tag. The view accepts:

```swift
struct HostTagFilterStrip: View {
    let tags: [String]
    let selectedTag: String?
    let selectTag: (String) -> Void
    let clearSelection: () -> Void
}
```

- [x] **Step 2: Compose the strip in `HostsView`**

Add it after `QuickImportCard`:

```swift
HostTagFilterStrip(
    tags: store.hostTags(),
    selectedTag: store.selectedHostTag,
    selectTag: { store.selectHostTag($0) },
    clearSelection: { store.clearSelectedHostTag() }
)
```

- [x] **Step 3: Run targeted tests, full tests, and build**

Run:

```bash
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:MobileShellTests/HostTagNavigationTests
xcodebuild test -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild build -quiet -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'
```

Expected: all commands exit 0.

---

## Self-Review

Spec coverage: The plan covers tag discovery, exact tag filtering, tag/search composition, clearing, UI chip composition, and verification.

Placeholder scan: No placeholders or deferred behavior remain.

Type consistency: `selectedHostTag`, `hostTags()`, `selectHostTag(_:)`, `clearSelectedHostTag()`, and `HostTagFilterStrip` are introduced before use.
