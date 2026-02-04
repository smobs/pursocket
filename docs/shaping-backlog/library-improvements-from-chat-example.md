# Library Improvements Identified from Chat Example

Ideas surfaced during the starter chat app build that could improve PurSocket.

## Server: Attach to Existing HTTP Server
**Problem:** The chat example needs to serve static files and run Socket.io on the same port. PurSocket's `createServer` and `createServerWithPort` create standalone Socket.io servers with no HTTP handler. There is no way to attach Socket.io to an existing `http.Server`.
**Workaround used:** A plain JavaScript wrapper script (`start-server.mjs`) creates the HTTP server externally and passes the Socket.io `Server` instance into PureScript as a `ServerSocket`.
**Proposed improvement:** Add `createServerFromHttpServer :: HttpServer -> Effect ServerSocket` or `attachToHttpServer :: HttpServer -> ServerOptions -> Effect ServerSocket` to `PurSocket.Server`. This would allow PureScript code to own the full server lifecycle without external JS wrappers.

## Server: Timestamp Utility
**Problem:** The chat server originally included a `timestamp` field in broadcast messages, which required a `nowISO :: Effect String` FFI call (`new Date().toISOString()`).
**Workaround used:** Dropped the `timestamp` field from the protocol entirely. The client-side JavaScript adds `new Date().toLocaleTimeString()` for display purposes.
**Proposed improvement:** Either (a) add a `nowISO :: Effect String` utility to a `PurSocket.Util` module, or (b) document the recommended approach of using `purescript-now` + `purescript-js-date` from the registry. This is a common need for any real-time messaging protocol.
