# Retro Notes: QA

Capture difficulties as you work. One entry per obstacle is enough.

---

### [Date] - [Brief title]

**What happened:** [1-2 sentences describing the obstacle]

**Impact:** [Time lost, rework required, scope cut, etc.]

**Root cause:** [Missing info, wrong assumption, tooling issue, unclear requirements, etc.]

---

### 2026-02-04 - run-negative-tests.sh needed refactoring for subdirectory support

**What happened:** The existing `run-negative-tests.sh` only globbed `*.purs` in the top-level `test-negative/` directory. Tour tests live in `test-negative/tour/` and also need `examples/chat/src/**/*.purs` on the compile path (since they import `Chat.Protocol`). The script needed to be restructured into a reusable function with optional extra source globs.

**Impact:** Minor -- about 15 minutes to refactor the script. The function-based approach is cleaner and extensible for future test subdirectories.

**Root cause:** The original script was designed for a flat directory of tests against a single protocol. The tour tests introduced two new requirements simultaneously: subdirectory structure and additional source paths. Both were foreseeable from the slice spec but required modifying the existing infrastructure.

---

### 2026-02-04 - Compiler output in GUIDED_TOUR.md is module-name-sensitive

**What happened:** The verbatim compiler output in the guided tour references module names from the standalone negative test files (e.g., `Test.Negative.Tour.Tour1WrongEvent`). When a developer makes the actual edit in `Chat.Client.Main`, the error will reference `Chat.Client.Main` instead. The GUIDED_TOUR.md notes the module name as `Chat.Client.Main` in the expected output to match what the developer will actually see.

**Impact:** None -- accounted for during writing. The key diagnostic information (custom error text, constraint stack) is identical regardless of which module triggers it.

**Root cause:** Negative tests use standalone modules by design (to avoid source mutation), so there is an inherent mismatch in the module name shown in errors. This is a known tradeoff documented in the pitch (Q&A #14).

---

<!-- Add more entries below as needed -->
