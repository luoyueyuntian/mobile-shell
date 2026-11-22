# MobileShell Project Constraints

## Purpose And Scope

This document is the default engineering contract for production code, tests, and refactors in this repository.

Its purpose is to keep the codebase readable, bounded, and maintainable as the app grows. These project-level rules take precedence over personal style preferences when working in `MobileShell`.

This document defines how code should be organized, how responsibilities should be split, and what kinds of changes should trigger restructuring instead of more accumulation.

## Engineering Principles

- Prefer readability over cleverness.
- Prefer clear boundaries over short-term convenience.
- Prefer explicit behavior over hidden side effects.
- Prefer testability over hidden coupling.
- Prefer incremental evolution over speculative redesign.

## Architecture Constraints

### Dependency Flow

Code should follow this direction by default:

`View -> Store -> Service/Persistence -> External library`

Dependencies should move inward through clear boundaries. UI code should not reach directly into SSH, SFTP, persistence, or library-specific implementation details.

### View

Views are responsible for presentation and user event forwarding.

Views may:

- render state
- bind to observable values
- trigger store actions
- compose smaller view types

Views must not:

- perform persistence directly
- call SSH, SFTP, or command execution code directly
- contain complex orchestration logic
- become the default place for feature state coordination

### Store

Stores are responsible for state transitions, use-case coordination, and feature orchestration.

Stores may:

- hold feature state
- coordinate services and persistence abstractions
- translate user actions into state changes
- expose focused methods that views can call

Stores must not:

- absorb large SwiftUI view trees
- depend on low-level Citadel or NIO details without an abstraction boundary
- become catch-all containers for unrelated features

### Service

Services are responsible for SSH, SFTP, command execution, and port forwarding integrations.

Services should:

- wrap external libraries behind focused interfaces
- expose behavior the store can coordinate
- keep transport and integration details out of view code

Services must not:

- hold UI state
- know about SwiftUI presentation concerns
- become mixed with persistence responsibilities

### Persistence

Persistence code is responsible for local load, save, and credential protection behavior.

Persistence code must:

- stay focused on data storage and retrieval
- expose clear interfaces for the store to use

Persistence code must not:

- perform view decisions
- contain unrelated orchestration logic
- become the default place for business rules

### Model

Models represent domain data and lightweight derived values.

Models should:

- stay small and predictable
- express domain state clearly
- keep derived values simple and local

Models must not:

- become a catch-all home for unrelated behavior
- absorb UI logic, transport logic, and persistence concerns together

### Directory Structure Rules

Existing files may remain in their current locations until touched, but all new modules should follow the target directory structure below.

Production code belongs under `MobileShell/`. Test code belongs under `MobileShellTests/`.

New feature-specific code should be placed under:

- `MobileShell/Features/<FeatureName>/Views/` for feature views
- `MobileShell/Features/<FeatureName>/Components/` for feature-local reusable UI
- `MobileShell/Features/<FeatureName>/Store/` for feature state and orchestration types
- `MobileShell/Features/<FeatureName>/Models/` for feature-local models that are not shared broadly

Cross-feature reusable code should be placed under:

- `MobileShell/Shared/Views/` or `MobileShell/Shared/Components/` for reusable UI
- `MobileShell/Shared/Models/` for shared domain types that do not belong to one feature
- `MobileShell/Shared/Extensions/` for narrow, high-value extensions only

Boundary-layer code should be placed under:

- `MobileShell/Services/<Capability>/` for SSH, SFTP, port forwarding, and other external integrations
- `MobileShell/Persistence/` for repositories, local storage, and credential handling

Tests should mirror the production structure as closely as practical:

- `MobileShellTests/Features/<FeatureName>/`
- `MobileShellTests/Services/`
- `MobileShellTests/Persistence/`
- `MobileShellTests/Shared/`

Do not place new feature views, stores, or services directly at the root of `MobileShell/` unless they are true app-entry types such as `MobileShellApp.swift`.

## Code Constraints

- Use the narrowest practical access level.
- Prefer immutable data unless mutation is required for state management.
- Prefer small, focused types over multi-purpose containers.
- Avoid `try!`, `as!`, and casual force unwrapping.
- Propagate errors explicitly instead of silently swallowing them.
- Keep side effects near application boundaries.
- Prefer protocol-backed seams when external integrations need test doubles.
- Do not add new responsibilities to an already overloaded file or type just because it already exists.
- Keep comments short and high-signal. Add them only when structure or intent is not obvious from the code.

## Scale And Decomposition Rules

Responsibility boundaries come first. File size and complexity are warning signals, not the only reason to split code.

A file should be split when:

- it contains multiple independently understandable responsibilities
- one area can no longer be changed without navigating unrelated concepts
- a feature addition would add another distinct concern rather than extend the same one

A type should be split when:

- it mixes UI, state orchestration, and IO concerns
- it coordinates multiple unrelated workflows
- its behavior cannot be explained in one clear sentence

Current repository hotspots require extra discipline:

- Do not keep accumulating new screens or large interaction flows inside `MobileShell/ShellRootView.swift`.
- Do not keep accumulating unrelated store behavior or domain coordination inside `MobileShell/Models.swift`.
- Do not keep extending `MobileShellTests/MobileShellStoreTests.swift` as a permanent catch-all when a new focused test file would be clearer.

Large-file or complexity warnings should be treated as prompts to review structure, not as permission to keep growing a crowded file until a hard limit fails.

## Testing Constraints

- New behavior requires automated tests.
- Refactors that preserve behavior must preserve or improve behavior coverage.
- Tests should be grouped by domain or behavior, not grown indefinitely in one broad file.
- Test doubles should remain in the test target unless shared test support becomes clearly necessary.
- Tests should validate observable behavior rather than internal implementation trivia.
- Use targeted test runs while iterating, then run the broader relevant test command before finishing a change.

## Change Rules

- Extend clear boundaries when possible.
- If a change requires touching many unrelated concerns, tighten the boundary before adding more logic.
- Improve local structure when working in an already crowded area instead of normalizing more accumulation.
- When adding a new module, place it in the target feature, shared, service, or persistence directory instead of extending the current flat root layout.
- Do not edit generated files under `build/`.
- Document intentional exceptions in review or change context so they remain explicit rather than accidental.

## Enforcement Model

### Tool-Enforced First Pass

These are good candidates for lightweight future automation such as SwiftLint:

- forbid `try!`
- forbid `as!`
- warn on dangerous force unwrap usage
- warn on large files
- warn on large types
- warn on high function complexity
- optionally warn on unmanaged temporary debt markers

Tooling should focus on objective maintainability rules first, not formatting trivia.

### Review-Enforced

These rules require human judgment and should remain review-driven:

- whether a view is doing too much orchestration
- whether a store knows too much about concrete SSH or SFTP implementation details
- whether a file boundary is still coherent even if it remains under a size threshold
- whether a new abstraction is useful or merely speculative

## Initial Rollout

This repository should adopt the constraints in stages:

1. Use this document as the source of truth for future changes.
2. Add lightweight automation only for the most objective rules.
3. Use normal feature work and focused refactors to gradually reduce pressure in known hotspot files.

This document is intended to guide the next changes, not to force a broad rewrite before progress can continue.
