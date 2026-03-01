# Delivery Notes: Shared Manager for Namespace Connections

**Shipped:** 2026-03-01
**Appetite:** 3-4 hours
**Actual:** ~2 hours

## What Shipped

PurSocket clients now share a single WebSocket transport across all namespaces, matching Socket.io's intended multiplexing design. Previously, each `joinNs` call created an independent connection (N+1 WebSockets per client). Now all namespace sockets share one Manager and one transport.

### Capabilities
- Namespace connections share a single WebSocket (1 instead of N+1)
- Transport reconnection is atomic across all namespaces
- Consumers can register connect/disconnect callbacks on `NamespaceHandle` via `onConnectNs`/`onDisconnectNs`

### Scope Delivered
- **FFI Fix and Wrappers:** One-line FFI change + two new `PurSocket.Client` exports
- **Tests:** Multi-namespace multiplexing test + disconnect-isolation test

## What Didn't Ship (Scope Cuts)

- **Reconnection test:** Deferred — requires new FFI for `socket.io.engine.close()` to simulate transport blip
- **`disconnectAll` API:** Deferred — `socket.io.close()` wrapper for tearing down the Manager
- **Double-join guard:** Deferred — `Ref (Set String)` to prevent aliased handles from duplicate `joinNs`

## Success Criteria

| Criterion | Met | Evidence |
|-----------|-----|---------|
| `primJoin` uses `baseSocket.io.socket` | Yes | `Client.js:13` |
| `onConnectNs`/`onDisconnectNs` exported | Yes | `Client.purs:235-244` |
| Multi-namespace test passes | Yes | 29/29 tests |
| Disconnect-isolation test passes | Yes | 29/29 tests |
| Existing tests pass | Yes | 27 pre-existing all green |

## Known Limitations

- **Double `joinNs` aliasing:** Calling `joinNs` twice with the same namespace returns the same socket instance. Listeners accumulate, disconnect affects both handles.
- **No `disconnectAll`:** Must disconnect each namespace socket individually to fully tear down.
- **Reconnection not directly tested:** Atomic reconnection (primary motivation) validated by design, not by test.

## Files Changed

| File | Change |
|------|--------|
| `src/PurSocket/Client.js` | 1 line: `io()` → `manager.socket()` |
| `src/PurSocket/Client.purs` | +15 lines: `onConnectNs`, `onDisconnectNs`, exports |
| `test/Test/Integration.purs` | +82 lines: 2 new integration tests |

## Team

| Role | Contribution |
|------|-------------|
| @web-tech-expert | Drafted pitch, resolved all 16 reviewer questions |
| @architect | Verified FFI correctness, naming, module structure |
| @qa | Identified critical test gaps, reconnection test infeasibility |
| @purescript-specialist | Verified PS/FFI boundary, built all code and tests |
| @external-user | Validated problem, migration concerns, consumer patterns |

---

## Next Steps

Run `/project-orchestrator:project-cooldown` to begin cool-down.
