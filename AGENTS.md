# MobileShell Agent Guide

## Purpose

This file gives coding agents the default rules for working in this repository. Follow it before making structural or behavioral changes.

## Project Snapshot

- `MobileShell` is a Swift 6 iOS app built with SwiftUI and Observation.
- The app models a personal SSH workspace with hosts, terminal sessions, SFTP, snippets, and related local persistence.
- External SSH and SFTP integration lives around Citadel and NIO abstractions.
- XCTest coverage lives in `MobileShellTests`.

## Repository Map

- `MobileShell/MobileShellApp.swift`: app entry point.
- `MobileShell/ShellRootView.swift`: top-level SwiftUI composition and many screen views. This file is already oversized.
- `MobileShell/Models.swift`: domain models plus `MobileShellStore`. This file is already carrying too many responsibilities.
- `MobileShell/ShellConnection.swift`: SSH, SFTP, and command execution integration points.
- `MobileShell/Persistence.swift`: JSON persistence and credential vault code.
- `MobileShellTests`: unit tests.
- `docs/project-constraints.md`: formal project-level code and architecture constraints.
- `build/DerivedData`: generated build artifacts and third-party package checkouts. Do not edit files under `build/`.
- `docs/superpowers/specs`: design notes created during previous planning work.

## Preferred Module Locations

- Put new feature-specific views, components, stores, and feature-local models under `MobileShell/Features/<FeatureName>/`.
- Put cross-feature reusable UI under `MobileShell/Shared/Views/` or `MobileShell/Shared/Components/`.
- Put shared models under `MobileShell/Shared/Models/`.
- Put focused extensions under `MobileShell/Shared/Extensions/`.
- Put SSH, SFTP, port forwarding, and other external integrations under `MobileShell/Services/<Capability>/`.
- Put repositories, local storage, and credential handling under `MobileShell/Persistence/`.
- Mirror the source layout in `MobileShellTests/` for new tests.
- Do not place new feature modules at the root of `MobileShell/` unless they are true app-entry files.

## Architecture Rules

- Keep dependency flow as `View -> Store -> Service/Persistence -> External library`.
- `View` code should focus on presentation and forwarding user actions. Do not add persistence, SSH, SFTP, or complex orchestration logic directly in SwiftUI views.
- `Store` code should coordinate state transitions and use cases. Do not let it absorb large UI trees or low-level library details.
- `Service` code should wrap SSH, SFTP, command execution, and port forwarding behavior behind focused interfaces.
- `Persistence` code should only load, save, and protect local data. Do not mix UI decisions into it.
- `Model` types should stay small and predictable. Do not use model files as a catch-all for unrelated business logic.

## Current Hotspots

- `MobileShell/ShellRootView.swift` should not keep accumulating new screens or large interaction flows. Extract new views or feature-specific components into focused files.
- `MobileShell/Models.swift` should not keep accumulating unrelated state, store methods, and domain behavior. Prefer new focused files when adding new concepts or features.
- `MobileShellTests/MobileShellStoreTests.swift` is already broad. If you add a new cluster of behavior tests, consider splitting them into a more focused test file instead of extending the catch-all.

## Coding Rules

- Prefer small, single-purpose types and files over large multi-purpose containers.
- Default to the narrowest access level that works.
- Prefer immutable data unless mutation is required for state management.
- Avoid `try!`, `as!`, and casual force unwrapping.
- Propagate errors explicitly instead of silently swallowing them.
- Keep side effects near application boundaries.
- Prefer protocol-backed seams when external integrations need test doubles.
- Do not add new responsibilities to an already overloaded file just because the file already exists.

## Change Strategy

- Match the existing product behavior unless the task explicitly changes it.
- Prefer incremental refactors that improve boundaries while making the requested change.
- If a feature requires touching many unrelated concerns, tighten the boundary before adding more logic.
- It is acceptable to introduce new files or folders when that makes responsibilities clearer.
- Prefer the target `Features/`, `Shared/`, `Services/`, and `Persistence/` layout for new modules instead of extending the current flat root layout.
- Do not edit generated files under `build/`.

## Testing And Verification

- Add or update XCTest coverage for behavior changes.
- Test observable behavior, not just implementation details.
- Keep test doubles inside the test target unless shared test support becomes clearly necessary.
- Prefer targeted test runs while iterating, then run the broader relevant test command before finishing.
- Use `xcodebuild` against the shared scheme:

```bash
xcodebuild test -project MobileShell.xcodeproj -scheme MobileShell -destination 'platform=iOS Simulator,name=<installed iPhone>,OS=<installed OS>'
```

- If a specific simulator name is unavailable, choose an installed iPhone simulator rather than changing the scheme or test target.

## Workflow Notes

- Check whether the current workspace actually exposes the git repository root before relying on git commands.
- Treat `docs/project-constraints.md` as the source of truth for repository-wide code and architecture rules.
- When introducing new project-wide rules, update `docs/project-constraints.md` instead of hiding them in code comments.
- Keep comments short and high-signal. Add them only when the code structure is not self-explanatory.
