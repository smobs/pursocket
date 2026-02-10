# Team Retrospective Proposals

Each team member proposes one concrete improvement action based on their experience.

**Cycle:** emitTo and Room Support
**Date:** 2026-02-04

---

## PureScript Specialist

### Key Difficulty
Zero build failures or rework cycles during implementation — all 4 slices (emitTo, broadcastExceptSender, room support, integration tests) compiled and passed on first attempt. This appears successful, but masked a critical gap: **there is no capture mechanism for implementation questions and edge cases that arise during build**. Questions like "what does `Ref.modify` return?", "should joinRoom discard the Promise?", and "how do we avoid test flakes on fast connections?" were discovered and solved ad-hoc without being recorded. The next cycle will have different developers and these decisions will be lost.

### Proposed Action
Add a **Build Questions Log** (`.md` file in `docs/current/building/`) that is updated during implementation whenever a design ambiguity, FFI subtlety, or implementation choice surfaces. Each entry records: (1) the question, (2) the decision made, (3) why that choice prevents bugs or clarifies intent. This log becomes required reading for the next cycle's developers and reduces rework when context shifts.

### Effort
small

### Owner
process

## QA

### Key Difficulty
During integration testing, the `Ref.modify` function in PureScript returns the **new value**, not the old value as expected from similar patterns in other languages. This caused test assertion logic to use incorrect pattern cases (0/1/2 instead of 1/2/3), leading to wrong value matching in sentinel checks for delivery assertions.

### Proposed Action
Create a "PureScript API Gotchas Cheat-Sheet" document in the project (e.g., `/docs/pureScript-gotchas.md`) that captures non-obvious semantics of common stdlib functions like `Ref.modify`, `Array.findIndex`, mutable record field updates, and other FFI-adjacent pitfalls. Reference this cheat-sheet in onboarding and before tackling test infrastructure.

### Effort
small

### Owner
self (QA responsibility to maintain as test patterns emerge)

## Web Tech Expert

### Key Difficulty

The FFI design introduced new patterns during shaping that represent subtle Socket.io runtime semantics outside the type system: **property access chains returning transient operators** (`socket.broadcast`, `socket.to(room)`) and **promise discarding at the FFI boundary** (`socket.join(room)` returns a Promise but only Effect semantics are exposed). The pitch Q&A carefully reasoned through 25 resolved questions to document these decisions, but there is no structural mechanism to prevent future FFI contributors from reintroducing similar semantic mismatches. A developer unfamiliar with Socket.io internals could cache a BroadcastOperator, create stale references, and produce silent message loss. Or they might incorrectly await promises in the FFI rather than at the PureScript boundary, breaking the Effect/Aff semantic split. These bugs would only surface in integration tests, not at compile time.

### Proposed Action

**Create a Socket.io FFI semantics reference in `/home/toby/pursocket/docs/ffi-socket-io-patterns.md`** documenting the runtime behaviors that require extra care at the FFI boundary:

1. **Property access vs method calls** — Note which Socket.io patterns return stable objects vs transient operators (e.g., `socket.broadcast` is a transient BroadcastOperator that must be used immediately, not cached; `socket.to(room)` also returns a transient operator and must be chained immediately with `.emit()`).

2. **Promise handling boundaries** — Establish the rule: "socket.join() and socket.leave() return Promises for async adapter compatibility, but PurSocket v1 targets the default in-memory adapter only. Promises are intentionally discarded at the JS boundary with a comment explaining why. Do not add `await` at the FFI level without consulting the architecture team."

3. **Namespace path construction rules** — Document when `reflectSymbol` is needed (e.g., `broadcast` and `onConnection` need it because they construct `"/" + ns` strings at the FFI boundary) vs when it is not needed (e.g., `emitTo` and `broadcastExceptSender` operate on the socket ref, which already carries namespace context).

4. **Adapter-aware operations matrix** — Document which FFI functions work transparently with Redis adapter vs which have in-memory-only semantics (e.g., `emitTo` to a disconnected handle is a silent no-op everywhere, but `joinRoom` timing guarantees differ between adapters).

Include this reference as a required pre-read for any PR adding new emit or room operations. Integrate into the FFI code review checklist.

### Effort

small

### Owner

process (document during next shaping cycle, integrate into PR template and FFI review process)
