# Betting Decision: Shared Manager for Namespace Connections

**Date:** 2026-03-01
**Decision:** BET
**Decided by:** User

---

## Risk Profile Presented

*The user reviewed this risk profile before making their decision.*

### Confidence Indicators

+ **Positive signals:**
- FFI change independently verified by @architect and @purescript-specialist
- All 4 reviewers confirmed: PureScript side truly needs no changes
- Socket.io's `manager.socket()` is the documented, intended API
- DisconnectReason semantics fully preserved
- Concurrent joinNs is safe by Socket.io design
- Server side / Bun engine completely unaffected
- Real bug motivating this (Whispers in the Mist reconnection)

! **Caution signals:**
- Appetite grew from 1-2 hours to 3-4 hours during review
- Core motivation (atomic reconnection) won't be directly tested — deferred
- Double-joinNs aliasing is a silent behavioral change with no compile-time guard

x **Red flags:**
- None identified

---

## Shaping Summary

| Metric | Count |
|--------|-------|
| Team members | 5 |
| Questions raised | 16 |
| Questions resolved | 16 |
| Escalations decided | 0 |

### Contributors
- @web-tech-expert (drafter)
- @architect (reviewer)
- @qa (reviewer)
- @purescript-specialist (reviewer)
- @external-user (reviewer)

---

## High-Signal Concerns

These areas were flagged by multiple teammates:

### 1. Double `joinNs` aliasing
**Raised by:** @qa, @purescript-specialist, @external-user
**Resolution:** `manager.socket()` is idempotent — documented as known constraint. Guard deferred.
**Residual risk:** Low — unlikely in practice but a silent behavioral change.

### 2. Test coverage gap
**Raised by:** @qa, @architect, @external-user
**Resolution:** Multi-namespace test now mandatory and sketched. Reconnection test deferred.
**Residual risk:** None — test is in scope.

### 3. Internal API leak (`socketRefFromHandle`)
**Raised by:** @architect, @external-user, @purescript-specialist
**Resolution:** `onConnectNs`/`onDisconnectNs` wrappers added to scope.
**Residual risk:** None — wrappers are in scope.

---

## Escalation Decisions

No escalations were required. All questions were resolved within the shaping team.

---

## What to Watch

Residual risks to monitor during building:

### From Team Reviews
- **No `disconnectAll` API:** Consumers must disconnect each socket individually. Track as follow-up.
- **Reconnection test deferred:** Atomic reconnection (primary motivation) won't be directly tested. Multi-namespace test validates multiplexing but not reconnection atomicity.
- **Base socket disconnect behavior:** Disconnecting base socket leaves namespace sockets alive. Correct but different. Depends on documentation being read.

### Mitigation Notes
- Multi-namespace test is the primary validation — if it passes, multiplexing works.
- `Server.closeServer` provides test cleanup safety net even without `disconnectAll`.
- Documentation updates are in scope and cover all behavioral changes.

---

## Decision: BET

### Success Criteria
- [ ] `primJoin` FFI updated to use `baseSocket.io.socket("/" + ns)`
- [ ] `onConnectNs` and `onDisconnectNs` wrappers added to `PurSocket.Client`
- [ ] Multi-namespace multiplexing test passes (join lobby + game on same socket)
- [ ] Namespace-disconnect-isolation test passes (disconnect one, other survives)
- [ ] Existing test suite still passes
- [ ] Behavioral changes documented

---

## Recommended Execution Team

| Role | Why Needed |
|------|-----------|
| @web-tech-expert | Socket.io expertise for FFI change and behavioral verification |
| @purescript-specialist | PureScript wrappers (`onConnectNs`/`onDisconnectNs`) and integration test code |

---

## Reviewers for Build Team

| Reviewer | Recommendation | Rationale |
|----------|----------------|-----------|
| @architect | Consulting | Deep FFI verification in review; available for questions but not primary implementer |
| @qa | Consulting | Identified critical test gaps; can validate test coverage during build |
| @external-user | Not needed | Validated problem and migration concerns; expertise not needed for execution |

---

## Next Steps

Run `/project-orchestrator:project-build` to create the building team and start execution.
