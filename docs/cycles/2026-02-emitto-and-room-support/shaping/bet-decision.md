# Betting Decision: emitTo and Room Support

**Date:** 2026-02-04
**Decision:** BET
**Decided by:** @user

---

## Risk Profile Presented

*The user reviewed this risk profile before making their decision.*

### Confidence Indicators

**Positive signals:**
- All 6 team perspectives represented -- deep coverage from architecture, types, DX, testing, and end-user angles
- 18 questions resolved across 2 rounds of collaborative shaping, 0 open
- Every FFI function has a concrete JS implementation specified in the Q&A threads
- Every PureScript signature is finalized with constraints explicitly confirmed
- 7 test scenarios specified with both positive and negative assertions
- No new modules, no new dependencies, no `spago.yaml` changes -- clean scope
- All changes land in two files: `Server.purs` and `Server.js` (plus tests)
- All three new functions share the same `NamespaceHandle`-based pattern -- uniform API

**Caution signals:**
- Multi-client integration tests are new territory -- existing tests are all single-client. Sequential connection with delays should prevent flakes, but it's untested infrastructure
- The `broadcastToRoom` signature was revised mid-shaping (from `ServerSocket` to `NamespaceHandle`) after the product-manager chose socket-level semantics. Builders must use the revised signature.

**Red flags:**
- None identified

---

## Q&A Summary

| Metric | Count |
|--------|-------|
| Total questions asked | 18 |
| Resolved | 18 |
| Contributors | 6 |

### Contributors
- @web-tech-expert (drafter, 10 answers)
- @architect (2 answers, 2 questions)
- @purescript-specialist (2 answers, 2 questions)
- @product-manager (1 answer, 2 questions)
- @qa (1 answer, 2 questions)
- @external-user (1 answer, 3 questions)
- @user (1 answer)

---

## High-Signal Concerns

These areas were questioned by multiple team members:

### 1. broadcastToRoom signature and semantics
**Asked by:** @purescript-specialist, @product-manager, @architect
**Resolution:** Socket-level semantics (`socket.to(room).emit()`), takes `NamespaceHandle ns` not `ServerSocket`, excludes sender. All three new functions share the same handle-based pattern.
**Residual risk:** None -- fully reconciled across all three perspectives.

### 2. Identical signatures for emitTo / broadcastExceptSender
**Asked by:** @external-user, @product-manager
**Resolution:** Accepted as inherent to the domain. Function names carry the semantic distinction. Negative delivery assertions in tests catch accidental swaps.
**Residual risk:** Low -- mitigated by naming, docs, and CI tests.

### 3. Effect vs Aff for room operations
**Asked by:** @web-tech-expert, @architect (broadened by project lead)
**Resolution:** Keep server module 100% Effect. `socket.join()` is synchronous under default adapter. Future `joinRoomAff` can be added as opt-in.
**Residual risk:** Users of Redis adapter will need to be aware that join propagation is not awaited. Documented in doc comment.

---

## Escalation Decisions Made

None required. All questions resolved at team level.

---

## What to Watch

### From Q&A Threads
- **`forall a` FFI boundary:** Each new `prim*` function trusts upstream `IsValidMsg`. Mitigated by integration tests. Add doc note to module comments.
- **Disconnected handle silent no-op:** `emitTo` on a disconnected handle discards data silently. Documentation must make handle lifecycle pattern explicit (store in `Ref Map`, clean up in `onDisconnect`).
- **Promise discarding in joinRoom/leaveRoom:** Correct for default adapter. Doc comment caveat for async adapters.
- **Multi-client test flakes:** Sequential client connection with delays is the agreed pattern. Watch for CI flakiness in the first test runs.

### Mitigation Notes
- Integration tests with negative assertions are the primary safety net for all FFI correctness
- Each new function follows an established pattern (existing `onEvent`, `broadcast` as templates)
- The 6-week appetite provides comfortable margin for the 5 new functions + 7 test scenarios

---

## Decision: BET

### User's Rationale
Room support is a firm requirement, not conditional. The 6-week appetite gives sufficient room for all three features plus thorough testing.

### Success Criteria
- [ ] `emitTo` ships with positive + negative delivery tests
- [ ] `broadcastExceptSender` ships with positive + negative delivery tests
- [ ] `joinRoom`, `leaveRoom`, `broadcastToRoom` ship with positive + negative delivery tests
- [ ] Negative compile tests for wrong-direction usage of `emitTo` and `broadcastExceptSender`
- [ ] Chat example updated to use `broadcastExceptSender`
- [ ] All existing tests pass, CI green

---

## Recommended Execution Team

| Role | Why Needed |
|------|-----------|
| @purescript-specialist | Primary implementer -- PureScript wrappers, type constraints, module exports |
| @web-tech-expert | FFI implementation -- JS functions in Server.js, Socket.io API correctness |
| @qa | Test implementation -- 7 integration test scenarios, negative compile tests |

## Reviewers for Build Team

| Reviewer | Recommendation | Rationale |
|----------|----------------|-----------|
| @architect | Consulting | Provided key FFI separation decision and Effect/Aff stance. Available for architecture questions during build. |
| @product-manager | Not needed | Review complete. API naming and semantics decisions are finalized. |
| @external-user | Consulting | Provided handle lifecycle and DX insights. Available for usability review of doc comments. |

---

## Next Steps

Run `/project-orchestrator:project-build` to start execution.
