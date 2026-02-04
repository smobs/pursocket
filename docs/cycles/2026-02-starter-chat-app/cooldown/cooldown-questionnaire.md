---
state: empty
created_date: "2026-02-04"
cycle: "starter-chat-app"
answers_count: 0
total_questions: 20
user_input_optional: true
---

# Cool-Down Questionnaire

Take time to reflect. Fill this in over the cool-down period.

---

## Cleanup Tasks

List tasks that need attention. Be specific about what needs to be done.

### Task 1

- **Type:** bug
- **Description:** Fix Effect thunking in index.html callbacks — inline JS callbacks need `return function() { ... };` wrappers to match PureScript's `Effect Unit` calling convention (`cb(x)()`)
- **Effort:** 1h
- **Assignee:** web-tech-expert
- **Acceptance:** Browser console shows zero TypeErrors when running chat app; all 6 event handlers fire correctly

### Task 2

- **Type:** tech-debt
- **Description:** Commit all uncommitted cycle work — 27 untracked files and 11 modified files from the chat example are not committed. Cycle tags point to same commit.
- **Effort:** 1h
- **Assignee:** purescript-specialist
- **Acceptance:** All chat example files committed, cycle-end tag updated, `git status` clean

### Task 3

- **Type:** polish
- **Description:** Add HTTP server attachment API to PurSocket.Server so examples don't need custom FFI for static file serving
- **Effort:** 2h
- **Assignee:** purescript-specialist
- **Acceptance:** Chat example can attach Socket.io to an existing HTTP server without custom FFI in start-server.mjs

---

## Retrospective

### What Worked Well

**What went better than expected?**

[Commit data: Entire 2-week appetite completed in a single day. All 4 slices shipped with zero blockers. The v1 library was solid enough that the example app needed only 2 library additions (onDisconnect, socketId). -- Add your thoughts below]

**What would you do the same way again?**

[Optional: Your thoughts]

**What tools/approaches were particularly effective?**

[Commit data: The slice-based approach kept work focused. Zero-FFI constraint for the chat example forced clean API design. Negative test infrastructure from v1 cycle was reusable for tour tests. -- Add your thoughts below]

### What Didn't Work

**What was harder than expected?**

[Commit data: 3 retro entries from PureScript Specialist all relate to tooling assumptions (PATH, ESM, missing APIs). Web Tech Expert hit the static file serving gap. -- Add your thoughts below]

**What would you do differently?**

[Optional: Your thoughts]

**Where did you lose time?**

[Retro data: ~55 minutes total across team on tooling issues (PATH ~15min, ESM ~5min, onDisconnect/socketId ~20min, static files ~15min). Most time lost was on library API gaps that became apparent only when building a real app. -- Add your thoughts below]

### On the Process

**How did shaping help (or not)?**

[Optional: Your thoughts]

**How useful were the reviews?**

[Optional: Your thoughts]

**Was the appetite right?**

[Commit data: 2-week appetite, 1-day actual. Appetite was generous but appropriate — the v1 library being done de-risked everything. If the library had needed changes, 2 weeks would have been needed. -- Add your thoughts below]

**How did scope hammering go?**

[Delivery data: 2 scope cuts made (timestamp field dropped, PureScript-owned server lifecycle deferred). Both were clean cuts that didn't affect the core value proposition. -- Add your thoughts below]

### On the Team

**Was the team composition right?**

[Optional: Your thoughts]

**Who was missing that should have been there?**

[Optional: Your thoughts]

**Who was there but not needed?**

[Optional: Your thoughts]

### Surprises

**What surprised you?**

[Commit data: The entire cycle completed in one day. Also, the external-user agent captured zero difficulties — the onboarding flow worked as designed on first attempt. -- Add your thoughts below]

**What did you learn that you didn't expect?**

[Retro data: PurSocket.Server needed onDisconnect and socketId — these are fundamental for any real application but weren't in the original API. Building an example exposed library gaps that tests didn't. -- Add your thoughts below]

---

## Process Changes

Capture changes that should be made to how we work.

**What should change about how we shape work?**

[Optional: Your thoughts]

**What should change about how we review?**

[Optional: Your thoughts]

**What should change about scoping/building?**

[Optional: Your thoughts]

---

## Ideas for Next Cycle

Capture ideas that came up during building but were out of scope.
These are candidates for future shaping, not commitments.

### Idea 1

**What:** HTTP server attachment API for PurSocket.Server
**Why it matters:** Every real app needs static file serving alongside Socket.io. Current workaround requires custom FFI.
**Rough size:** Small
**Urgency:** next-cycle
**Why this urgency:** Workaround exists (JS wrapper script), but it undermines the "zero FFI" selling point

### Idea 2

**What:** Timestamp/metadata helpers for protocol events
**Why it matters:** `new Date().toISOString()` was dropped from protocol because it required FFI. A `PurSocket.Util` module could provide common helpers.
**Rough size:** Small
**Urgency:** someday
**Why this urgency:** Client-side JS timestamp works fine; this is polish

### Idea 3

**What:** PureScript DOM bindings or helpers for browser examples
**Why it matters:** Current browser examples push DOM code into inline JS. PureScript-native DOM access would make examples fully type-safe.
**Rough size:** Large
**Urgency:** someday
**Why this urgency:** Using purescript-web-html adds heavy dependencies; inline JS is pragmatic for small examples

---

## Team Continuity

**Which team members should continue to the next cycle?**

[Optional: Your thoughts]

**Any roles to add for likely future work?**

[Optional: Your thoughts]

**Any roles no longer needed?**

[Optional: Your thoughts]
