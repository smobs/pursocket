# Retro Notes: Web Tech Expert

Capture difficulties as you work. One entry per obstacle is enough.

---

### [Date] - [Brief title]

**What happened:** [1-2 sentences describing the obstacle]

**Impact:** [Time lost, rework required, scope cut, etc.]

**Root cause:** [Missing info, wrong assumption, tooling issue, unclear requirements, etc.]

---

### 2026-02-04 - Socket.io standalone server does not serve static files

**What happened:** `PurSocket.Server.createServerWithPort` uses `new Server(port, { cors: ... })` which creates a standalone Socket.io server with no HTTP request handler. Navigating to `http://localhost:3000` in a browser returns the Socket.io polling handshake response, not HTML. The chat example needs to serve `index.html` and `client.bundle.js` from the same port.

**Impact:** Required adding a `createChatServer` FFI function to `Chat.Server.Main.js` that creates an `http.Server` with a static file handler and attaches Socket.io to it. The server PureScript module needed to import `ServerSocket` from `PurSocket.Internal` (since it no longer uses `createServerWithPort` from `PurSocket.Server`). About 15 minutes of design and implementation.

**Root cause:** The library's `createServerWithPort` was designed for headless server-only use (integration tests, standalone socket servers). Real applications that need to serve a web UI alongside Socket.io must create their own HTTP server and attach Socket.io to it. This is standard Socket.io architecture but was not anticipated in the library API. The fix was correctly scoped to the chat example's FFI rather than expanding the library API.

---

### 2026-02-04 - Browser DOM manipulation requires FFI

**What happened:** PureScript has no built-in browser DOM bindings. The chat client needs `getElementById`, `addEventListener`, `innerHTML`, `value` access, and `window.prompt`. All of these require FFI wrappers.

**Impact:** Created 6 FFI functions in `Chat.Client.Main.js` (30 lines). Minimal impact -- the wrappers are thin and straightforward.

**Root cause:** Expected. PureScript's FFI for browser APIs is standard practice. The codebase already established this pattern with `PurSocket.BrowserTest.js`. Using a DOM library like `purescript-web-html` would have added significant dependencies for very little gain in a 30-line HTML app.

---

<!-- Add more entries below as needed -->
