# Engineering Standards

**Read this at the start of every phase, before reading the phase doc.**

This document is the contract between executor LLMs and the principal engineer.
If you (the executor) follow these standards, your work will pass review. If you
skip them, your work will bounce back with a bug report and you'll do it twice.

The goal is not bureaucracy — it's so the principal engineer can review your
output by checking a finite list, not by re-reading the whole architecture doc.

> **Command resolution.** This project's commands:
>
> | Placeholder | Command |
> |---|---|
> | Format-check (verify only, no write) | `make lint` |
> | Build | `make build` |
> | Lint / static-analysis | `make lint` |
> | Test | `make test` |
>
> Note: swift-format is the only linter in this project (no SwiftLint), so the
> format-check and lint commands are the same. The auto-fix is `make format`.

---

## 1. Definition of Done

A phase is **not** done until every box below is checked. If you cannot tick a
box, the phase is **in-progress** or **blocked**, not done. Report blockers in
the phase's Update Log — never silently mark a phase done.

- [ ] All tasks in the phase doc's Spec section are implemented.
- [ ] Every acceptance criterion in the phase doc is verifiably met.
- [ ] Every acceptance criterion that references a real artifact the phase ships
      (a checked-in file, a CLI behavior, a config the running binary loads) has
      been **verified end-to-end against that real artifact** — not just against
      a unit-test fake — and the actual output is quoted in the completion
      Update Log entry under "End-to-end verification." A green `make test`
      run that exercises a temp-directory-scoped fake is **not** by itself sufficient.
- [ ] `make build` succeeds with **zero new warnings**.
- [ ] `make lint` passes.
- [ ] `make lint` passes.
- [ ] `make test` passes (existing + new tests).
- [ ] New code is covered by tests per the rules in §3.
- [ ] No `TODO` / `FIXME` / `XXX` left in code, unless the phase doc explicitly
      authorizes one (with a follow-up phase referenced).
- [ ] No debug calls or commented-out code.
- [ ] No error-suppressing idioms (force-unwrap `!`, `try!`, `fatalError()`, or
      language equivalents) in production paths. Test code is exempt. See §2.
- [ ] No `unsafe`/unchecked pointer blocks. (If you think you need one, stop and
      report a blocker — it requires principal-engineer review.)
- [ ] Architecture doc updated **only if** the phase explicitly requires it.
      Otherwise leave it alone.
- [ ] Phase doc's Update Log filled in (see WORKFLOW.md).
- [ ] One conventional commit per logical change (see §6).

---

## 2. Code Quality

### 2.1 Error handling

Errors are split by audience:

- **Programmer / infrastructure failures** → a typed error enum
  (`Result<_, _>` / a thrown typed `Error`). Add a new variant only if no existing one fits.
- **Things the user is supposed to see and adapt to** (a denied permission, a
  disconnected device, a missing file) → a structured result value or state,
  **not** a crash. This is a normal outcome, not a programmer mistake.
- **A generic error-wrapping type** is acceptable at app entry points where
  errors propagate to user-visible output. Library code uses specific error types.
- **The language's propagation operator** (`try` / `throws`) is the default.
  Never suppress errors in production paths. A contextual message is acceptable
  when the value is set at compile-time or the invariant was already proven upstream.
- **Never** silently swallow an error you don't want to ignore — that's how
  bugs hide.

### 2.2 What to write (and not write)

- **No new files unless the phase requires them.** Prefer editing.
- **No premature abstraction.** Three similar lines are better than a generic
  helper. Abstract when the *fourth* caller appears.
- **No error handling for cases that can't happen.** Trust framework guarantees
  and internal invariants. Validate at system boundaries (user input, external
  APIs, hardware callbacks), not internally.
- **No feature flags or back-compat shims** unless the phase calls for them.
- **No backwards-compatibility renames.** If a symbol is unused, delete it.
- **No fallbacks for "if X is missing."** Either X is required (fail loud) or it
  has a default (use it). No silent degradation.

### 2.3 Comments

Default: **write no comments.** Add one only when *why* is non-obvious — a hidden
constraint, a subtle invariant, a workaround for a known bug. If removing the
comment wouldn't confuse a future reader, don't write it.

Specifically forbidden: restating what the code does; "used by X" / "added for
Y" references (they rot); TODO/NOTE with no actionable instruction; block
comments above every function. Doc comments on public APIs are fine.

### 2.4 Naming

- Use Swift's conventional naming style consistently (camelCase members,
  UpperCamelCase types).
- Test functions describe behavior
  (`sustainedDropBecomesBad`, `loadsDefaultWhenNoConfigPresent`), not `test1` /
  `itWorks`.

### 2.5 Module layout

- Public API at a single declared entry point per type.
- Internal helpers below public items.
- Unit tests in the `Tests/` target, mirroring the source module they cover.
- Grouped imports following Swift conventions.

### 2.6 Dependencies

- **Do not add new dependencies** unless the phase doc authorizes it. This is a
  dependency-free project (no SwiftPM package deps). Adding a dependency is a
  design decision, not an implementation choice. If you need one, **stop, report
  a blocker**, and wait for principal-engineer authorization.
- **Runtime toolchain binaries are distinct from package dependencies.** A package
  dep is compiled/installed by the build; a *runtime* shell-out to a binary (a
  compiler, a linter) must exist on the executor host. If a phase makes the code
  shell out to a **new** binary, declare it in the phase doc's
  Authorizations/Pre-flight. When a required binary is **absent at runtime**,
  degrade to a user-visible advisory that names the missing binary and the remedy —
  never a crash, never an opaque failure.

---

## 3. Test Coverage

### 3.1 What requires a test

- **Every new pure function** (no side effects, no async): unit test.
- **Every new public function with non-trivial behavior**: at least one
  unit test covering the happy path, plus tests for the boundary cases the
  function's contract names.
- **Every new integration with an external system** (hardware, audio, file
  system, UserDefaults): a hermetic test using a mock, fake, or isolated suite.
- **Every new parsing / data-transformation step**: a positive example of
  the input it handles, plus at least one edge case (malformed input,
  boundary value, the case the spec explicitly pins as `must-NOT-match`).

### 3.2 What does not require a test

- Pure plumbing: a function that only constructs a struct from its fields or
  forwards args.
- SwiftUI view bodies (covered by behavior tests on the ViewModel, not by
  snapshotting the view).
- Code paths the phase doc explicitly marks "stub, no behavior yet."

### 3.3 How tests are written

- One assertion per test where possible; multi-assertion tests need
  per-assertion messages.
- Tests are **hermetic**: no real hardware, no real network, no writes to the
  host home or shared locations. Use injected fakes (`FakeHeadMotionProvider`,
  `FakeAudioOutputMonitor`, `FakePostureNotifier`) and isolated UUID-named
  `UserDefaults` suites.
- Tests are **deterministic**: no `sleep`, no real wall-clock time (inject a
  clock / pass timestamps), no unseeded RNG. Use `drainMainQueue()` after
  emitting motion readings to let main-thread dispatch settle before asserting.
- **Inject hardware / external-IO dependencies behind a protocol seam.** Anything
  that touches a real device, audio route, or system service goes behind a
  protocol with a production impl and a test fake, so tests stay hermetic and fast.

### 3.4 Live-hardware tests

Don't write them unless the phase doc explicitly asks. Real AirPods motion and
CoreAudio interaction need physical hardware the CI environment can't provide.
When the phase doc calls for one, gate it as disabled and document how to run it.

---

## 4. Required Commands

Run these locally before reporting a phase done. Output of the full sequence
goes into the phase's Update Log.

```bash
make lint
make build 2>&1 | tail -20
make lint 2>&1 | tail -20
make test 2>&1 | tail -30
```

If any command fails, the phase is **not** done. Fix the issue or file a blocker;
do not paper over.

---

## 5. Files You Must Not Touch

Without explicit authorization in the phase doc:

- Build and configuration files (`Package.swift`, `Makefile`, `.swift-format`,
  CI workflows, `NoSlouch.entitlements`, `Resources/Info.plist`).
- The architecture doc (architecture changes go through the principal engineer).
- `STANDARDS.md`, `WORKFLOW.md` (these documents).
- Any milestone or phase doc other than the one you're executing.

If you think one of these needs to change to complete the phase, **stop and
report a blocker**.

---

## 6. Commits

- One conventional commit per logical change: `feat:`, `fix:`, `refactor:`,
  `test:`, `docs:`, `chore:`.
- The commit body explains *why*, not *what* (the diff shows what).
- One phase usually = one commit. Multi-commit phases are fine when the changes
  are genuinely independent.

---

## 7. When You Are Stuck

Stop. Do not improvise around an unclear spec or a missing dependency. File a
blocker in the phase doc's Update Log (template in WORKFLOW.md), then stop. The
principal engineer resolves it on the next review pass.

Always-blockers, never improvise:

- Need to add a dependency.
- Need to write an `unsafe`/unchecked pointer block.
- Spec is ambiguous between two valid implementations.
- An acceptance criterion is impossible as written.
- A required file referenced by the spec doesn't exist.
- A test reveals the design itself is wrong, not just your implementation.

---

## 8. Reporting Completion

1. Re-read this document, top to bottom.
2. Run all required commands in §4 and capture their output.
3. Fill in the phase's Update Log with the "complete" template (WORKFLOW.md).
4. Commit and stop. **Do not start the next phase.** The principal engineer
   reviews, then marks the phase **done** or files a bug report.

---

## 9. Source of Truth

When this document and the architecture doc disagree, the **architecture doc
wins**. When the phase doc and the architecture doc disagree, **stop and report a
blocker** — the phase doc has drifted from the design.
