# Slice: Client API & FFI

**Status:** Complete

## What This Slice Delivers
A working client-side API where a PureScript developer can `connect` to a Socket.io server, `join` a namespace (getting a `NamespaceHandle`), `emit` fire-and-forget messages, and `call` with acknowledgement responses -- all compile-time validated against their `AppProtocol`.

## Scope
- `PurSocket.Client`: `connect`, `join`, `emit`, `call`, `callWithTimeout`, `defaultTimeout`
- FFI file for client primitives: `primConnect`, `primJoin`, `primEmit`, `primCallImpl`
- `connect` takes a URL, returns a `SocketRef` in `Effect`
- `join` takes a namespace symbol and base socket, returns `NamespaceHandle ns` in `Effect`
- `emit` uses `IsValidMsg` constraint with `"c2s"` direction
- `call` uses `IsValidCall` constraint with `"c2s"` direction, returns `Aff`
- `call` FFI wraps Socket.io acknowledgement callback via `makeAff`
- Basic timeout handling for `call` (configurable via `callWithTimeout`, default 5000ms, no retry)
- Compile-time tests for API function signatures (18 tests total)

## NOT in This Slice
- Server-side API
- Integration tests with a real server (Slice 5)
- Browser bundling (Slice 5)

## Dependencies
- Slice 1 (Project Skeleton) must be complete
- Slice 2 (Protocol & Type Engine) must be complete

## Build Notes

### Design decisions made during implementation:

1. **NamespaceHandle wraps SocketRef.** The `NamespaceHandle` data constructor was updated (in Framework, Slice 2) to hold a `SocketRef` internally: `data NamespaceHandle (ns :: Symbol) = NamespaceHandle SocketRef`. This is necessary for `emit` and `call` to extract the underlying socket for FFI calls.

2. **Framework exports `NamespaceHandle(..)`.** The constructor is exported from `PurSocket.Framework` so that `PurSocket.Internal` can import and use it. End users should treat `NamespaceHandle` as opaque -- the constructor is available but undocumented for public use.

3. **`connect` returns `SocketRef`, not a custom `Socket` type.** Since `SocketRef` already exists as the opaque JS socket reference in Framework, there is no need for a separate `Socket` type. The `SocketRef` from `connect` is passed to `join` to derive namespace connections.

4. **`join` extracts base URL from the socket.** The FFI uses `socket.io.uri` to get the base URL from the socket returned by `connect`, then calls `io(baseUrl + "/" + ns)` to create a namespace-specific connection. This avoids requiring the user to pass the URL again.

5. **`call` inlines `makeAff` instead of delegating.** The initial attempt to have `call` delegate to `callWithTimeout @protocol` failed because `IsValidCall` is kind-polymorphic (`forall k. k -> ...`), and visible type application of kind-polymorphic type variables in function bodies does not resolve correctly. The fix was to inline the `makeAff` logic in both `call` and `callWithTimeout`.

6. **FFI uses ESM imports.** Consistent with `Server.js`, the client FFI uses `import { io } from "socket.io-client"` (ESM syntax).

7. **Socket.io v4.4+ `timeout()` API.** The `call` FFI uses `socket.timeout(ms).emit(event, payload, callback)` which provides timeout-based acknowledgement handling. The callback receives `(err, response)` where `err` is set on timeout.

## Acceptance Criteria
- [x] `connect` connects to a Socket.io server URL, returns `Effect SocketRef`
- [x] `join` connects to a namespace, returns `Effect (NamespaceHandle ns)`
- [x] `emit` sends fire-and-forget messages, constrained to `c2s` direction
- [x] `call` sends request/response messages via acknowledgements, constrained to `c2s`
- [x] `call` has configurable timeout (`callWithTimeout`, default 5000ms)
- [x] FFI files are thin (1-3 lines per function) wrapping socket.io-client
- [x] Client code cannot send `s2c` events (compile error, enforced by `IsValidMsg`/`IsValidCall` constraints)
- [x] `spago build` succeeds (0 errors, 0 warnings)

## Verification (Required)
- [x] Build succeeds: `spago build` exits 0, 0 errors, 0 warnings
- [x] Type safety: `emit` constrains to `c2s` via `IsValidMsg`; `call` constrains to `c2s` via `IsValidCall`; compile-time tests verify correct type resolution
- [x] FFI files exist alongside PureScript modules: `src/PurSocket/Client.js`

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-03 | Complete | Implemented connect, join, emit, call, callWithTimeout with FFI. 18/18 tests pass. |
