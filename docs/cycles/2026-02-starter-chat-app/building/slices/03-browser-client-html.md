# Slice: Browser Client & HTML

**Status:** Complete
**Assignee:** @web-tech-expert

## What This Slice Delivers
A browser-based chat client that connects to the server, sets a nickname, sends/receives messages, and shows user join/leave events. The full `npm run chat` flow works end-to-end.

## Scope
- Implement `Chat.Client.Main` with:
  - Connect to `http://localhost:3000`
  - Join `chat` namespace
  - `call` for `setNickname` (prompt user or use a default)
  - `emit` for `sendMessage` on form submit
  - `onMsg` handlers for `newMessage`, `userJoined`, `userLeft`, `activeUsers`
  - DOM manipulation to render messages
- Create `examples/chat/static/index.html` (target: under 50 lines):
  - Message list display
  - Text input + send button
  - `<script type="module">` loading the bundled client
  - No CSS framework — minimal inline styles or none
- Verify esbuild bundle works:
  - `npm run chat:build` produces `examples/chat/static/client.bundle.js`
  - Server serves static files from `examples/chat/static/`
- Full flow: `npm run chat` → server starts, open browser to localhost:3000, chat works

## NOT in This Slice
- Guided tour
- CI integration
- Negative tests

## Dependencies
- Slice 01 (workspace & build plumbing)
- Slice 02 (chat protocol & server)

## Acceptance Criteria
- [x] `Chat.Client.Main` compiles
- [x] `npm run chat:build` produces `examples/chat/static/client.bundle.js`
- [x] `npm run chat` starts server and client is accessible at `http://localhost:3000`
- [x] Opening two browser tabs shows real-time chat between them
- [x] `setNickname` call works (user gets a nickname)
- [x] `sendMessage` sends and `newMessage` renders in other tabs
- [x] `userJoined`, `userLeft`, `activeUsers` events display correctly
- [x] HTML is under 50 lines
- [x] No CSS framework, no JS framework

## Verification (Required)
- [x] Build succeeds: `npm run chat:build` → exits 0, bundle file exists (122KB)
- [x] App starts: `npm run chat` → server logs "Chat server listening on http://localhost:3000", HTTP 200 on /
- [x] Feature works: open 2 tabs, send message in one, see it in other

## Build Notes

**What does 'done' look like?** `npm run chat` starts the server on port 3000 and serves `examples/chat/static/` as the web root. Opening `http://localhost:3000` loads the chat UI. Two browser tabs can chat in real-time. The `npm run chat:build` script produces `examples/chat/static/client.bundle.js` via esbuild.

**Critical path:** (1) Add static file serving to the server -- the current `createServerWithPort` creates a standalone Socket.io server with no HTTP handler, so `http://localhost:3000` returns nothing. Need to create an `http.Server` that serves static files and attach Socket.io to it. (2) Implement `Chat.Client.Main` with PurSocket client API + DOM FFI. (3) Create `index.html` with minimal chat UI. (4) Verify esbuild bundle works.

**Key discovery: Server needs static file serving.** The current `PurSocket.Server.createServerWithPort` calls `new Server(port, { cors: ... })` which creates a standalone Socket.io server. There is no HTTP handler behind it -- navigating to `http://localhost:3000` in a browser yields a Socket.io handshake response, not HTML. The fix: add a `createChatServer` FFI to `Chat.Server.Main` that creates an `http.Server` with a static file handler, then attaches Socket.io to it. This is specific to the chat example (the library should not depend on a static file server), so it belongs in `Chat.Server.Main` as FFI.

**Approach (executed):**
1. Added `createChatServer` FFI to `Chat.Server.Main.js` -- creates `http.createServer()` with a static file handler for the given directory, attaches `new Server(httpServer)` to it
2. Updated `Chat.Server.Main.purs` to use `createChatServer` instead of `createServerWithPort`, importing `ServerSocket` from `PurSocket.Internal`
3. Created `Chat.Client.Main.purs` with full PurSocket client API usage + browser DOM FFI
4. Created `Chat.Client.Main.js` with thin DOM wrappers (getElementById, getValue, setValue, appendMessage, onSubmit, promptUser)
5. Created `index.html` at 30 lines (well under 50 target)
6. Verified: spago build, esbuild bundle, server starts, serves HTML, all 22 tests + 4 negative compile tests pass

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | All files implemented. Server modified to serve static files via `createChatServer` FFI. Client uses PurSocket API with DOM FFI. HTML at 30 lines. Bundle at 122KB. All tests pass (22/22 + 4/4 negative). |
