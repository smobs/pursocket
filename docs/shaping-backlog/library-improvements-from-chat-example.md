# Library Improvements Identified from Chat Example

Ideas surfaced during the starter chat app build that could improve PurSocket.

## Server: Attach to Existing HTTP Server
**Problem:** The chat example needs to serve static files and run Socket.io on the same port. PurSocket's `createServer` and `createServerWithPort` create standalone Socket.io servers with no HTTP handler. There is no way to attach Socket.io to an existing `http.Server`.
**Workaround used:** A plain JavaScript wrapper script (`start-server.mjs`) creates the HTTP server externally and passes the Socket.io `Server` instance into PureScript as a `ServerSocket`.
**Proposed improvement:** Add `createServerFromHttpServer :: HttpServer -> Effect ServerSocket` or `attachToHttpServer :: HttpServer -> ServerOptions -> Effect ServerSocket` to `PurSocket.Server`. This would allow PureScript code to own the full server lifecycle without external JS wrappers.
**Status:** Deferred from cooldown cleanup. Tracked as brainstorm item #18. Design notes in `docs/api-surface-audit.md` (S1/S4).

## Server: Timestamp Utility
**Problem:** The chat server originally included a `timestamp` field in broadcast messages, which required a `nowISO :: Effect String` FFI call (`new Date().toISOString()`).
**Workaround used:** Dropped the `timestamp` field from the protocol entirely. The client-side JavaScript adds `new Date().toLocaleTimeString()` for display purposes.
**Proposed improvement:** Either (a) add a `nowISO :: Effect String` utility to a `PurSocket.Util` module, or (b) document the recommended approach of using `purescript-now` + `purescript-js-date` from the registry. This is a common need for any real-time messaging protocol.
**Status:** Open. Low priority — JS workaround exists.

## Server: Emit to Single Client (NEW — from API audit)
**Problem:** `broadcast` calls `io.of(ns).emit()` which sends to ALL clients. There is no way to send a typed message to a specific client. This is the most significant functional gap in PurSocket.
**Proposed improvement:** Add `emitTo :: NamespaceHandle ns -> payload -> Effect Unit` that calls `socket.emit()` on the handle's individual `SocketRef`.
**Status:** Highest priority. Tracked as brainstorm item #16. Design notes in `docs/api-surface-audit.md` (E1, section 7.1).

## Server: Broadcast Except Sender (NEW — from API audit)
**Problem:** No way to emit to all clients except the sender. This is the standard pattern for chat messages, game state updates, and collaborative editing.
**Proposed improvement:** Add `broadcastExceptSender :: NamespaceHandle ns -> payload -> Effect Unit` wrapping `socket.broadcast.emit()`.
**Status:** High priority. Tracked as brainstorm item #17. Design notes in `docs/api-surface-audit.md` (SK22/B6, section 7.2).
