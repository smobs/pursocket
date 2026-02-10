---
state: empty
created_date: "2026-02-04"
cycle: "emitTo and Room Support"
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

- **Type:** docs
- **Description:** Add module-level doc comment to PurSocket.Server noting that FFI functions use `forall a` for payload parameters and type safety is enforced by `IsValidMsg`/`IsValidCall` constraints. This was identified during shaping (Q&A thread on FFI boundary soundness) but not implemented during build.
- **Effort:** 1h
- **Assignee:** purescript-specialist
- **Acceptance:** Server.purs module doc comment mentions FFI trust boundary and warns against calling `prim*` functions directly.

### Task 2

- **Type:** polish
- **Description:** The integration tests connect clients sequentially with 200ms delays. Verify this is reliable on CI and consider if any delays can be tightened or if a more robust connection-confirmation pattern exists (e.g., waiting for a server-side `onConnection` signal via Ref before proceeding).
- **Effort:** 2h
- **Assignee:** qa
- **Acceptance:** Tests pass reliably on 3 consecutive `npm test` runs. Delays are documented if they cannot be reduced.

### Task 3

- **Type:** docs
- **Description:** Review doc comments on all 5 new functions for completeness and accuracy. Ensure the handle lifecycle pattern (store in Ref Map, clean up in onDisconnect) is mentioned on `emitTo` as specified in the pitch Q&A.
- **Effort:** 1h
- **Assignee:** purescript-specialist
- **Acceptance:** Doc comments match the guidance from the 18 resolved Q&A threads in the pitch.

---

## Retrospective

### What Worked Well

**What went better than expected?**

[Commit data: Single-commit cycle — all work landed atomically with zero fix commits. 6-week appetite completed in <1 day. — Add your thoughts below]

**What would you do the same way again?**

[Optional: Your thoughts]

**What tools/approaches were particularly effective?**

[Commit data: 18 resolved Q&A threads during shaping eliminated all design ambiguity. Every FFI function and PureScript signature was specified before build started — builders could copy-paste from the pitch. — Add your thoughts below]

### What Didn't Work

**What was harder than expected?**

[Commit data: No fix commits and no retro note entries suggest nothing was harder than expected. The QA agent hit a minor `Ref.modify` return-value semantics issue, fixed in one pass. — Add your thoughts below]

**What would you do differently?**

[Optional: Your thoughts]

**Where did you lose time?**

[Commit data: No evidence of lost time. Zero fix commits, all slices completed on first pass. — Add your thoughts below]

### On the Process

**How did shaping help (or not)?**

[Commit data: Shaping was exceptionally thorough — 18 Q&A threads across 6 contributors resolved every design decision including FFI implementations, type signatures, test scenarios, and API naming. The build phase was pure execution with zero design decisions remaining. — Add your thoughts below]

**How useful were the reviews?**

[Optional: Your thoughts]

**Was the appetite right?**

[Commit data: 6-week appetite, <1 day actual. The appetite was dramatically oversized for this scope. The shaping phase did the heavy lifting — the build was mechanical. — Add your thoughts below]

**How did scope hammering go?**

[No scope cuts needed — all scope delivered within appetite. — Add your thoughts below]

### On the Team

**Was the team composition right?**

[Build team: @purescript-specialist (primary), @web-tech-expert (FFI design in shaping), @qa (tests). All 3 contributed meaningfully. — Add your thoughts below]

**Who was missing that should have been there?**

[Optional: Your thoughts]

**Who was there but not needed?**

[Optional: Your thoughts]

### Surprises

**What surprised you?**

[Commit data: 71% of implementation lines are tests (409 of 572). The library code itself is remarkably small — 131 lines of PureScript wrappers + 30 lines of JS FFI. — Add your thoughts below]

**What did you learn that you didn't expect?**

[Optional: Your thoughts]

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

**What:** `callTo` — targeted request/response (acknowledgement) to a specific client
**Why it matters:** `emitTo` is fire-and-forget; for transactional use cases (game moves, payment confirmations), developers need delivery confirmation via acks
**Rough size:** Small
**Urgency:** next-cycle
**Why this urgency:** Identified in the pitch Q&A (external-user asked about delivery confirmation) but not blocking current use cases

### Idea 2

**What:** `joinRoomAff` / `leaveRoomAff` — Aff variants for async adapter support (Redis)
**Why it matters:** `joinRoom`/`leaveRoom` discard the Promise, which is correct for the default adapter but incorrect for Redis adapter deployments
**Rough size:** Small
**Urgency:** someday
**Why this urgency:** No users on Redis adapter currently. Doc comments already note the limitation.

### Idea 3

**What:** Room-scoped namespace-level broadcast (`io.of(ns).to(room).emit()` — includes sender)
**Why it matters:** `broadcastToRoom` excludes sender (socket-level semantics). Some use cases need to include the sender (e.g., room state sync).
**Rough size:** Small
**Urgency:** someday
**Why this urgency:** Workaround exists (broadcastToRoom + emitTo on self). Not blocking.

---

## Team Continuity

**Which team members should continue to the next cycle?**

[Optional: Your thoughts]

**Any roles to add for likely future work?**

[Optional: Your thoughts]

**Any roles no longer needed?**

[Optional: Your thoughts]
