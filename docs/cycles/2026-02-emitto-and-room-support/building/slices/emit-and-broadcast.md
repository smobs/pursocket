# Slice: emitTo + broadcastExceptSender

**Status:** Complete

## What This Slice Delivers
Two new server-side delivery modes: send to a single client (`emitTo`) and broadcast to all except the sender (`broadcastExceptSender`). After this slice, the server can target individual clients and echo-prevent broadcasts.

## Scope
- Add `primEmitTo` FFI to `Server.js` — `(socket) => (event) => (payload) => () => { socket.emit(event, payload); }`
- Add `primBroadcastExceptSender` FFI to `Server.js` — `(socket) => (event) => (payload) => () => { socket.broadcast.emit(event, payload); }`
- Add `emitTo` PureScript wrapper to `Server.purs` with `IsValidMsg protocol ns event "s2c" payload` + `IsSymbol event` constraints, taking `NamespaceHandle ns -> payload -> Effect Unit`
- Add `broadcastExceptSender` PureScript wrapper to `Server.purs` with same constraints
- Export both from `PurSocket.Server` module
- Add doc comments for both functions
- Foreign imports for both `prim*` functions

## NOT in This Slice
- Integration tests (separate slice)
- Negative compile tests (separate slice)
- Room functions (separate slice)

## Dependencies
- None — this is the first slice

## Acceptance Criteria
- [x] `emitTo` compiles and is exported from `PurSocket.Server`
- [x] `broadcastExceptSender` compiles and is exported from `PurSocket.Server`
- [x] Both have doc comments explaining delivery semantics and handle lifecycle
- [x] `spago build` succeeds with no warnings

## Verification (Required)
- [x] Build succeeds: `spago build` → clean output
- [x] Functions visible in module exports

## Build Notes

**Analysis (2026-02-04):** Both `emitTo` and `broadcastExceptSender` follow the same pattern as existing `onEvent` -- extract `SocketRef` from `NamespaceHandle` via `socketRefFromHandle`, reflect the event symbol, call the FFI. The FFI functions are one-liners. No new imports needed beyond what `Server.purs` already has. The constraint set is `IsValidMsg protocol ns event "s2c" payload` + `IsSymbol event` (no `IsSymbol ns` needed since we never construct a namespace path string). Building both slices (emit-and-broadcast + room-support) together since they modify the same two files.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | Added `primEmitTo` and `primBroadcastExceptSender` FFI to Server.js, foreign imports and PureScript wrappers with doc comments to Server.purs, updated module exports. `spago build` succeeds with 0 warnings, `npm test` passes all 22 tests + 7 negative compile tests. |
