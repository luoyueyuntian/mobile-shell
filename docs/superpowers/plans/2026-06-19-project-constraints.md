# Project Constraints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the repository's formal project constraints document so code and architecture rules are documented in one project-facing source of truth.

**Architecture:** Keep the implementation lightweight and document-first. Reuse the approved design spec, translate it into a concise project policy document at `docs/project-constraints.md`, and align it with the existing `AGENTS.md` guidance so agents and human contributors follow the same boundaries.

**Tech Stack:** Markdown documentation, Swift/iOS repository conventions, existing design spec and AGENTS guidance.

---

### Task 1: Write The Formal Constraints Document

**Files:**
- Create: `docs/project-constraints.md`
- Reference: `docs/superpowers/specs/2026-06-19-project-constraints-design.md`
- Reference: `AGENTS.md`

- [ ] **Step 1: Re-read the approved design inputs**

Review the design spec and current agent guide so the formal document reflects the agreed boundaries and current repository hotspots.

Run:

```bash
sed -n '1,260p' docs/superpowers/specs/2026-06-19-project-constraints-design.md
sed -n '1,240p' AGENTS.md
```

Expected: both documents describe the same core themes: architecture boundaries, maintainability hotspots, and lightweight first-pass enforcement.

- [ ] **Step 2: Write the formal project constraints document**

Create `docs/project-constraints.md` with the following complete structure:

```markdown
# MobileShell Project Constraints

## Purpose And Scope
- State that this is the default engineering contract for production code, tests, and refactors.
- State that repository rules override personal style preferences for this codebase.

## Engineering Principles
- Readability over cleverness.
- Clear boundaries over short-term convenience.
- Explicit behavior over hidden side effects.
- Testability over hidden coupling.
- Incremental evolution over speculative redesign.

## Architecture Constraints
- Define `View`, `Store`, `Service`, `Persistence`, and `Model` responsibilities.
- Define the allowed dependency flow.
- Call out direct prohibitions such as putting SSH or persistence logic in views.

## Code Constraints
- Narrowest practical access level.
- Immutable-by-default data.
- Small focused types and files.
- Avoid `try!`, `as!`, and casual force unwraps.
- Explicit error propagation.
- Side effects near system boundaries.
- Prefer protocol seams for external integrations that need test doubles.

## Scale And Decomposition Rules
- Split files by responsibility first, not only by line count.
- Do not keep extending `ShellRootView.swift`, `Models.swift`, or broad catch-all test files without extracting focused files.
- Treat large-file or complexity warnings as triggers for review.

## Testing Constraints
- New behavior requires tests.
- Refactors must preserve or improve behavior coverage.
- Group tests by domain or behavior.
- Keep test doubles in the test target unless shared support becomes clearly necessary.

## Change Rules
- Extend clear boundaries when possible.
- Restructure boundaries before adding more unrelated logic.
- Document intentional exceptions in review context.

## Enforcement Model
- Separate tool-enforced first-pass rules from review-enforced architecture rules.
- Recommend future lightweight linting for objective constraints only.
```

- [ ] **Step 3: Verify the new document exists and reads cleanly**

Run:

```bash
sed -n '1,260p' docs/project-constraints.md
rg -n "TODO|TBD|FIXME|placeholder" docs/project-constraints.md
```

Expected:
- the file exists with the intended sections
- the grep command returns no matches

- [ ] **Step 4: Commit**

No git repository is currently exposed at this workspace root, so do not attempt to commit. Report the created file path and verification results in the final response instead.

### Task 2: Verify Repository-Level Constraints Coverage

**Files:**
- Verify: `AGENTS.md`
- Verify: `docs/project-constraints.md`
- Verify: `docs/superpowers/specs/2026-06-19-project-constraints-design.md`

- [ ] **Step 1: Confirm the intended artifact set exists**

Run:

```bash
test -f AGENTS.md && echo AGENTS_OK
test -f docs/project-constraints.md && echo CONSTRAINTS_OK
test -f docs/superpowers/specs/2026-06-19-project-constraints-design.md && echo SPEC_OK
```

Expected: all three markers are printed.

- [ ] **Step 2: Confirm the final constraints document covers the design scope**

Run:

```bash
rg -n "Purpose And Scope|Engineering Principles|Architecture Constraints|Code Constraints|Scale And Decomposition Rules|Testing Constraints|Change Rules|Enforcement Model" docs/project-constraints.md
```

Expected: matches for every required major section.

- [ ] **Step 3: Commit**

No git repository is currently exposed at this workspace root, so do not attempt to commit. Report coverage verification in the final response instead.
