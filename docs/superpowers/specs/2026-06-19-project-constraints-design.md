# Project Constraints Design

## Overview

This document defines the design for introducing project-level code and architecture constraints to the `MobileShell` codebase. The goal is to reduce maintenance risk, slow the growth of oversized files, and give future changes a consistent set of engineering boundaries.

The resulting project constraints should be pragmatic, mainstream for Swift/iOS teams, and tailored to the current repository rather than copied from a generic style guide.

## Current Repository Signals

The current codebase is small enough to improve incrementally, but it already shows early maintainability pressure:

- `MobileShell/ShellRootView.swift` is a very large SwiftUI file that mixes multiple screens and interaction flows.
- `MobileShell/Models.swift` acts as both a model container and a state-orchestration home for `MobileShellStore`.
- `MobileShellTests/MobileShellStoreTests.swift` has become a broad catch-all test file across several behaviors.
- There is no existing project-level constraints document.
- There is no existing lint configuration defining maintainability guardrails.

These are not failures on their own, but they are strong signals that new features should not continue to accumulate in the same shape.

## Goals

- Define a single project constraints document that future contributors can follow by default.
- Capture mainstream Swift/iOS code conventions that materially improve readability and maintainability.
- Define architecture boundaries for `View`, `Store`, `Service`, `Persistence`, and `Model` responsibilities.
- Introduce explicit scale and decomposition rules so large files and multi-purpose types stop growing unchecked.
- Identify which constraints should later be enforced automatically and which should remain review-driven.

## Non-Goals

- This work does not immediately refactor the existing codebase into the target structure.
- This work does not introduce a heavy governance process such as a full ADR system or broad CI policy redesign.
- This work does not attempt to encode every architecture judgment into tooling.
- This work does not replace engineering judgment with rigid line-count-only rules.

## Deliverables

### 1. Project Constraints Document

Create `docs/project-constraints.md` as the source of truth for repository-level engineering constraints.

This document should be written as a project policy document, not as a tutorial. It should use direct language such as:

- what the project optimizes for
- what each layer is allowed to do
- what each layer must not do
- what triggers file or type decomposition
- what test coverage is expected for behavior changes
- what rules are enforced by tools versus code review

### 2. Tooling Mapping

Define a short section in the constraints document that distinguishes:

- automatically enforceable rules
- review-only rules

The first implementation pass should only map objective rules into tooling. Subjective architectural concerns should stay in documented review guidance.

## Proposed Document Structure

The `docs/project-constraints.md` document should use the following structure:

### 1. Purpose and Scope

Define this document as the default engineering contract for production code, tests, and refactors in this repository.

State that repository-level constraints take precedence over individual style preferences.

### 2. Engineering Principles

List the core priorities that guide tradeoffs:

- readability over cleverness
- clear boundaries over short-term convenience
- explicit behavior over implicit side effects
- testability over hidden coupling
- incremental evolution over large speculative design

### 3. Architecture Constraints

Define layer responsibilities and dependency boundaries.

#### View

- Responsible for presentation and user event forwarding.
- May bind to observable state and render UI state.
- Must not directly perform persistence, network calls, SSH operations, or complex orchestration logic.

#### Store

- Responsible for state transitions, feature orchestration, and use-case coordination.
- May call services and persistence abstractions.
- Must not absorb low-level library details or large amounts of presentation code.

#### Service

- Responsible for SSH, SFTP, command execution, and port forwarding integrations.
- Must expose focused interfaces that the store can coordinate.
- Must not hold UI state or SwiftUI concerns.

#### Persistence

- Responsible for local storage and retrieval.
- Must not perform UI decisions or unrelated business orchestration.

#### Model

- Responsible for representing domain data and lightweight derived values.
- Must stay small and predictable.
- Must not become the default home for unrelated coordination logic.

### 4. Code Constraints

Document mainstream Swift/iOS conventions that are both common and high-value:

- default to the narrowest access level possible
- prefer immutable values unless mutation is required
- prefer small focused types over multi-purpose containers
- avoid `try!` and `as!`
- keep force unwraps exceptional and justified
- propagate errors explicitly instead of silently swallowing them
- keep side effects near application boundaries
- avoid adding new responsibilities to already overloaded files or types
- prefer protocol-backed boundaries where external integrations need substitution in tests

### 5. Scale and Decomposition Rules

Define when code must be split, using responsibility-based rules first and size thresholds second.

The document should explicitly state:

- a file must be split when it contains multiple independently understandable responsibilities
- a type must be split when it mixes UI, state orchestration, and IO concerns
- a new feature should extend a focused module instead of adding another responsibility to a crowded file
- line counts and complexity warnings are indicators that trigger review, not the only reason to split

The document should call out the current repository risks directly:

- new views should not continue to accumulate inside `ShellRootView.swift`
- new store or domain behavior should not continue to accumulate in `Models.swift`
- broad behavior tests should not continue to accumulate in `MobileShellStoreTests.swift`

### 6. Testing Constraints

Define behavior-focused test expectations:

- new behavior requires automated tests
- refactors that change structure without changing behavior must preserve or improve behavior coverage
- tests should be grouped by behavior or domain, not as a single growing catch-all file
- test doubles should remain inside the test target unless there is a compelling shared test-support need
- tests should validate observable behavior rather than internal implementation trivia

### 7. Change Rules

Describe how future contributors should make changes:

- prefer extending existing clear boundaries
- if a change requires touching many unrelated concerns, restructure the boundary before adding more behavior
- do not normalize temporary shortcuts into permanent architecture
- document intentional exceptions in the change description or review context

### 8. Enforcement Model

Split rules into two groups.

#### Tool-Enforced First Pass

These are good candidates for a future lint configuration:

- forbid `try!`
- forbid `as!`
- warn on dangerous force unwrap usage
- warn on large files
- warn on large types
- warn on high function complexity
- warn on unmanaged `TODO` or `FIXME` markers if desired

#### Review-Enforced

These should remain human-reviewed:

- whether a view is doing too much orchestration
- whether a store knows too much about concrete SSH/SFTP implementation details
- whether a file boundary is still coherent even if it is under size thresholds
- whether a new abstraction is genuinely useful instead of speculative

## Recommended Initial Enforcement Strategy

Use a staged rollout.

### Stage 1

Add the project constraints document only.

This gives the repository a clear and reviewable engineering contract without forcing an immediate codebase-wide cleanup.

### Stage 2

Introduce lightweight linting for the most objective maintainability rules.

This should focus on obvious risk patterns and scale warnings, not style trivia.

### Stage 3

Use normal feature work and refactors to gradually move oversized files toward the documented boundaries.

This avoids a high-cost rewrite while still preventing the current structure from degrading further.

## Why This Design Fits the Current Project

This repository is small, UI-heavy, and already showing signs of responsibility concentration. A lightweight but explicit constraints document is the right first move because it:

- creates shared expectations immediately
- addresses the actual failure modes already visible in the repository
- avoids premature heavy process
- leaves room for later automation where rules are objective

The design intentionally favors maintainability boundaries over cosmetic formatting rules, because the primary risk in this codebase is structural drift rather than stylistic inconsistency.

## Self-Review

### Placeholder Scan

No placeholder sections, TODO markers, or unresolved decision labels remain in this design.

### Internal Consistency

The proposed document structure aligns with the earlier design decisions:

- one main project constraints document
- architecture and code rules in the same source of truth
- light automation only for objective rules
- review-driven enforcement for architecture judgments

### Scope Check

The scope is focused enough for a single implementation plan:

- create the constraints document
- optionally add a first-pass lint mapping afterward

### Ambiguity Check

Potential ambiguity around decomposition is resolved by defining responsibility-based triggers first and size-based indicators second.
