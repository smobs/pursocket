# Delivery Notes: emitTo and Room Support

**Shipped:** 2026-02-04
**Appetite:** 6 weeks
**Actual:** < 1 day

## What Shipped

PurSocket's server module now supports all four standard Socket.io delivery modes: single client, all-except-sender, namespace-wide, and room-scoped. This closes the #1 API gap identified in the surface audit.

### Features/Capabilities
- Server can send typed messages to a single specific client (`emitTo`)
- Server can broadcast to all clients except the sender (`broadcastExceptSender`) -- standard echo prevention
- Server can group clients into rooms (`joinRoom`, `leaveRoom`) and broadcast to room members (`broadcastToRoom`)
- All new functions enforce protocol contracts at compile time via `IsValidMsg` constraints
- All new per-socket functions use `NamespaceHandle ns` (not `ServerSocket`), maintaining a clean API split

### Scope Delivered
- **emitTo + broadcastExceptSender**: 2 FFI functions + 2 PureScript wrappers with doc comments
- **Room support**: 3 FFI functions + 3 PureScript wrappers with doc comments (including async adapter caveats)
- **Integration tests**: 7 multi-client scenarios in 5 test blocks, all with positive AND negative delivery assertions
- **Chat example update**: `newMessage` broadcast replaced with `broadcastExceptSender`, fixing the echo-to-sender bug
- **Negative compile tests**: 2 new tests proving `emitTo` and `broadcastExceptSender` reject c2s events

## What Didn't Ship (Scope Cuts)

None. All scope delivered within appetite.

## Success Criteria

| Criterion | Met | Proof |
|-----------|-----|-------|
| `emitTo` ships with positive + negative delivery tests | Yes | Tests "delivers to target client and not to others" -- `rA shouldEqual 99`, `rB shouldEqual 0` |
| `broadcastExceptSender` ships with positive + negative delivery tests | Yes | Tests "delivers to others but not to the sender" -- `rB shouldEqual 77`, `rA shouldEqual 0` |
| `joinRoom`, `leaveRoom`, `broadcastToRoom` ship with positive + negative delivery tests | Yes | 3 room tests: delivery + sender/non-member exclusion, leaveRoom stops delivery, multiple rooms isolation |
| Negative compile tests for wrong-direction usage | Yes | `EmitToWrongDirection.purs` and `BroadcastExceptSenderWrongDirection.purs` both correctly fail to compile |
| Chat example updated to use `broadcastExceptSender` | Yes | Line 60 of `Chat/Server/Main.purs` uses `broadcastExceptSender` |
| All existing tests pass, CI green | Yes | 27/27 tests pass, 9/9 negative compile tests pass, 0 warnings |

## Definition of Done

**Target:** All functions exist in `PurSocket.Server`, exported with doc comments, backed by integration tests proving correct delivery semantics.
**Achieved:** Committed to main branch with full test coverage.

## Known Limitations

- `joinRoom`/`leaveRoom` use synchronous semantics (default in-memory adapter). Users of async adapters (Redis) should be aware the join may not have propagated when the call returns. Doc comments note this.
- `emitTo` on a disconnected handle is a silent no-op (matches Socket.io behavior). Doc comments advise using `onDisconnect` to clean up stale handles.
- `broadcastToRoom` uses socket-level semantics (excludes sender). To include the sender, call `broadcastToRoom` + `emitTo` on self.

## Team

| Role | Contribution |
|------|-------------|
| @purescript-specialist | Primary implementer: all 5 PureScript wrappers, FFI functions, module exports, doc comments, chat example update, negative compile tests |
| @web-tech-expert | FFI design (resolved during shaping): Socket.io API correctness, adapter behavior analysis |
| @qa | Integration test design and implementation: 7 multi-client test scenarios with positive + negative assertions |

## Lessons Learned

- Thorough shaping (18 resolved Q&A threads) left zero ambiguity during build. Every signature and FFI implementation was copy-paste from the pitch.
- Building Slices 1+2 together (same files) avoided merge conflicts and was the right call.
- The `Ref.modify` return value (returns new value, not old) tripped up the QA agent briefly -- a known PureScript gotcha worth remembering.
- Multi-client test pattern (sequential connection with delays, per-client Refs) worked reliably with no flakes.

---

## Next Steps

Run `/project-orchestrator:project-cooldown` to begin the cool-down period.
