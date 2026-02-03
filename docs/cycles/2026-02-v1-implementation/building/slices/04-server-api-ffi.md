# Slice: Server API & FFI

**Status:** Complete

## What This Slice Delivers
A working server-side API where a PureScript developer can create a Socket.io server, handle connections, `broadcast` messages to namespaces, and register typed event handlers -- all compile-time validated against the shared `AppProtocol`.

## Scope
- `PurSocket.Server`: `createServer`, `createServerWithPort`, `broadcast`, `onEvent`, `onConnection` functions
- FFI file for server primitives: `primCreateServer`, `primCreateServerWithPort`, `primBroadcast`, `primOnConnection`, `primOnEvent`
- `broadcast` uses `IsValidMsg` constraint with `"s2c"` direction
- `onEvent` registers typed handlers for incoming `c2s` events
- Server code cannot send `c2s` events (compile error)
- Server code cannot listen for `s2c` events (compile error)
- `PurSocket.Internal` module with `ServerSocket` foreign type, `mkNamespaceHandle`, `socketRefFromHandle`
- `NamespaceHandle` updated to hold a `SocketRef` (opaque foreign socket reference)

## NOT in This Slice
- Client-side API (Slice 3)
- Integration tests (Slice 5)
- Multi-process / Redis adapter support

## Dependencies
- Slice 1 (Project Skeleton) must be complete
- Slice 2 (Protocol & Type Engine) must be complete

## Build Notes

### Analysis

1. **NamespaceHandle needed a payload field.** The original `NamespaceHandle` had no fields (`data NamespaceHandle (ns :: Symbol) = NamespaceHandle`). For real FFI, both client and server need it to hold an opaque socket reference. Added `foreign import data SocketRef :: Type` to Framework and changed the definition to `data NamespaceHandle (ns :: Symbol) = NamespaceHandle SocketRef`.

2. **Internal module coordination.** No `PurSocket.Internal` existed. Created it to provide:
   - `ServerSocket` foreign data type for the Socket.io Server instance
   - `mkNamespaceHandle` -- constructs a `NamespaceHandle` from a `SocketRef`
   - `socketRefFromHandle` -- extracts the `SocketRef` from a handle
   - Re-exports `NamespaceHandle(..)` and `SocketRef` from Framework

3. **Constructor visibility.** Framework now exports `NamespaceHandle(..)` (including the constructor) because Internal needs to import it. The privacy guarantee is maintained by convention: Internal is documented as non-public API. This is the standard PureScript pattern when multiple internal modules need access to a constructor.

4. **Server-side NamespaceHandle semantics.** On the server, `NamespaceHandle` wraps an individual client socket received in `onConnection`, not a namespace connection. The namespace itself is accessed via `ServerSocket` + namespace symbol. `broadcast` operates on `ServerSocket`, while `onEvent` operates on `NamespaceHandle`.

5. **FFI callback pattern.** Socket.io callbacks fire in JS-land. PureScript `Effect` is a thunk, so callbacks need double invocation: `callback(data)()` -- first call applies the curried argument, second runs the Effect.

6. **Client module updated.** The Client module's stubs were updated to work with the new `NamespaceHandle` shape, using `mkNamespaceHandle` from Internal instead of raw `unsafeCoerce`.

### Files Changed/Created

- **Modified:** `src/PurSocket/Framework.purs` -- added `SocketRef` foreign type, updated `NamespaceHandle` to hold `SocketRef`, updated export list
- **Created:** `src/PurSocket/Internal.purs` -- internal module with `ServerSocket`, handle construction/extraction
- **Created:** `src/PurSocket/Server.js` -- thin FFI wrappers (5 functions, each 1-2 lines)
- **Replaced:** `src/PurSocket/Server.purs` -- full implementation with real types and FFI bindings
- **Modified:** `src/PurSocket/Client.purs` -- updated stubs to use new `NamespaceHandle` shape
- **Modified:** `test/Test/Main.purs` -- added Server compile-time validation tests

## Acceptance Criteria
- [x] `createServer` creates a Socket.io server instance
- [x] `createServerWithPort` creates server listening on a port
- [x] `broadcast` sends messages to all clients in a namespace, constrained to `s2c`
- [x] `onEvent` registers typed handlers for `c2s` events from clients
- [x] `onConnection` handles new client connections per namespace
- [x] Server code cannot send `c2s` events (compile error -- enforced by `IsValidMsg` constraint with `"s2c"`)
- [x] FFI files are thin wrappers around socket.io server API (5 functions, each 1-2 lines)
- [x] `spago build` succeeds

## Verification (Required)
- [x] Build succeeds: `spago build` exits 0 with no errors
- [x] Type safety: `broadcast` is constrained to `s2c` events via `IsValidMsg protocol ns event "s2c" payload`; attempting `c2s` would fail at the `LookupMsgEvent` level
- [x] FFI files exist alongside PureScript modules: `Server.js` alongside `Server.purs`
- [x] Tests pass: `spago test` exits 0, 13/13 tests pass

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-03 | Complete | All acceptance criteria met. Build and tests green. |
