# Slice: Room Support

**Status:** Complete

## What This Slice Delivers
Three new room functions: `joinRoom`, `leaveRoom`, and `broadcastToRoom`. After this slice, server code can group clients into rooms and broadcast to room members (excluding the sender).

## Scope
- Add `primJoinRoom` FFI to `Server.js` — `(socket) => (room) => () => { socket.join(room); }`
- Add `primLeaveRoom` FFI to `Server.js` — `(socket) => (room) => () => { socket.leave(room); }`
- Add `primBroadcastToRoom` FFI to `Server.js` — `(socket) => (room) => (event) => (payload) => () => { socket.to(room).emit(event, payload); }`
- Add `joinRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit` to `Server.purs`
- Add `leaveRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit` to `Server.purs`
- Add `broadcastToRoom` to `Server.purs` with `IsValidMsg protocol ns event "s2c" payload` + `IsSymbol event` constraints, taking `NamespaceHandle ns -> String -> payload -> Effect Unit`
- Export all three from `PurSocket.Server`
- Doc comments for all three, including note about synchronous join semantics (default adapter)

## NOT in This Slice
- Integration tests (separate slice)
- Type-level room names
- Room membership queries
- `disconnecting` event

## Dependencies
- emitTo + broadcastExceptSender slice (shared module structure)

## Acceptance Criteria
- [x] `joinRoom`, `leaveRoom`, `broadcastToRoom` compile and are exported
- [x] All have doc comments including async adapter caveat for joinRoom/leaveRoom
- [x] `spago build` succeeds with no warnings

## Verification (Required)
- [x] Build succeeds: `spago build` → clean output
- [x] Functions visible in module exports

## Build Notes

**Analysis (2026-02-04):** `joinRoom` and `leaveRoom` are pure FFI wrappers with no protocol constraints -- they take `NamespaceHandle ns -> String -> Effect Unit`. `broadcastToRoom` follows the same pattern as `emitTo`/`broadcastExceptSender` but with an extra `String` room name parameter. All three use socket-level semantics (operating on the `SocketRef` from the handle). `joinRoom`/`leaveRoom` discard the Promise returned by Socket.io (correct for default adapter). Doc comments must note synchronous semantics caveat for async adapters.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | Added `primJoinRoom`, `primLeaveRoom`, `primBroadcastToRoom` FFI to Server.js, foreign imports and PureScript wrappers with doc comments to Server.purs, updated module exports. Built together with Slice 1 (emit-and-broadcast). `spago build` succeeds with 0 warnings, `npm test` passes all 22 tests + 7 negative compile tests. |
