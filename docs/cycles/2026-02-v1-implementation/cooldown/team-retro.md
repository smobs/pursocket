# Team Retrospective Proposals

Each team member proposes one concrete improvement action based on their experience.

**Cycle:** v1-implementation
**Date:** 2026-02-03

---

## Architect

### Key Difficulty
BRIEF.md spec contained conceptual PureScript type signatures that were never compiler-verified. Row.Cons was specified as the constraint mechanism for custom type errors, but Row.Cons is a compiler intrinsic that bypasses instance chains entirely. This was only discovered during implementation, causing complete restructuring of the type engine from Row.Cons-based to RowToList-based lookup classes (significant rework mid-cycle).

### Proposed Action
During shaping phase, create a minimal throwaway prototype module that compiles the core type-level mechanism (type classes, constraints, instance chains) with one concrete example. Delete it after validating the approach. This is not a production artifact - it's a 30-minute compiler verification step before finalizing the spec.

### Effort
small

### Owner
self

---

## Web Tech Expert

### Key Difficulty
The initial `NamespaceHandle` skeleton was defined as a pure phantom type with no runtime payload. When implementing real FFI in Slice 3/4, it needed to carry an opaque socket reference, requiring coordinated structural changes across Framework, Internal (new module), Client, and Server modules.

### Proposed Action
When designing types that will bridge PureScript and FFI layers, include a skeleton FFI requirement doc alongside the initial type definition. For each phantom-typed capability token (like `NamespaceHandle`), explicitly document:
- What JS runtime value it must wrap (if any)
- How the FFI will construct instances
- How the FFI will extract values

This prevents "phantom type that turns out to need a payload" surprises during implementation.

### Effort
small

### Owner
self

---

## QA

### Key Difficulty
Client and Server API slices (3 and 4) scoped only send-side APIs (emit, call, broadcast). Integration testing naturally required receive-side APIs (onMsg, onConnect, disconnect). This caused unplanned scope expansion in Slice 5 when adding 5 FFI functions for message reception and lifecycle management.

### Proposed Action
When shaping bidirectional API slices (client/server, publisher/subscriber, sender/receiver), explicitly scope both send-side AND receive-side operations in the initial slice specification. For Client API: include onMsg and connection lifecycle. For Server API: include onConnection and onEvent. Integration tests should not be the first place receive-side APIs are specified.

### Effort
small

### Owner
process

