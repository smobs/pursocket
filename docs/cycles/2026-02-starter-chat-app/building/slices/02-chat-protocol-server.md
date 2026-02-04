# Slice: Chat Protocol & Server

**Status:** Complete
**Assignee:** @purescript-specialist

## What This Slice Delivers
A running chat server on port 3000 that handles connections, nickname setting, message broadcasting, and user join/leave events using the PurSocket API against the ChatProtocol.

## Scope
- Implement `Chat.Protocol` with the full ChatProtocol type (from pitch):
  ```purescript
  type ChatProtocol =
    ( chat ::
        ( c2s ::
            ( sendMessage :: Msg { text :: String }
            , setNickname :: Call { nickname :: String } { ok :: Boolean, reason :: String }
            )
        , s2c ::
            ( newMessage  :: Msg { sender :: String, text :: String, timestamp :: String }
            , userJoined  :: Msg { nickname :: String }
            , userLeft    :: Msg { nickname :: String }
            , activeUsers :: Msg { users :: Array String }
            )
        )
    )
  ```
- Implement `Chat.Server.Main` (target: under 80 lines) with:
  - Socket.io server on port 3000
  - `onConnection` for `chat` namespace
  - `onCallEvent` for `setNickname` — validates nickname uniqueness
  - `onEvent` for `sendMessage` — broadcasts `newMessage` to all clients
  - Broadcasts `userJoined` and `activeUsers` on connection
  - Broadcasts `userLeft` and updated `activeUsers` on disconnect
  - In-memory `Map` or `Ref` for connected users
- Server should start with `node output-es/Chat.Server.Main/index.js`

## NOT in This Slice
- Browser client (tested via integration or manual socket.io-client)
- HTML UI
- Guided tour
- CI integration

## Dependencies
- Slice 01 (workspace & build plumbing) must be complete

## Acceptance Criteria
- [x] `Chat.Protocol` module compiles with full ChatProtocol type
- [x] `Chat.Server.Main` compiles and exports `main` effect
- [x] Server starts on port 3000 with `node output-es/Chat.Server.Main/index.js`
- [x] Server handles `setNickname` call with uniqueness validation
- [x] Server broadcasts `newMessage` when `sendMessage` received
- [x] Server broadcasts `userJoined` and `activeUsers` on connection
- [x] Server broadcasts `userLeft` on disconnect
- [x] Server is under 80 lines of PureScript (78 lines)

## Verification (Required)
- [x] Build succeeds: `spago build -p chat-example` → exits 0
- [x] Server starts: `node --input-type=module -e "import {main} from './output-es/Chat.Server.Main/index.js'; main();"` → logs "Chat server listening on port 3000"
- [x] Server handles connection: verified via socket.io-client script (connect, setNickname, sendMessage, disconnect all work)

## Build Notes

**What does 'done' look like?** `node output-es/Chat.Server.Main/index.js` starts a Socket.io server on port 3000, logs its status, and handles connections on the `/chat` namespace. Clients can set nicknames (with uniqueness validation), send messages (broadcast to all), and see join/leave notifications. Under 80 lines of PureScript.

**Critical path:** (1) Verify Chat.Protocol is correct (already done by Slice 01), (2) Add `onDisconnect` and `nowISO` FFI to PurSocket.Server (library gap), (3) Add `refs` dependency to chat-example for `Effect.Ref`, (4) Implement Chat.Server.Main following PurSocket.Example.Server patterns, (5) Build and run.

**Unknowns resolved:**
- State management: Use `Effect.Ref` with a simple `Array { id :: String, nickname :: String }` keyed by socket ID. No need for `Map` -- the user count is small and array operations are fine.
- onDisconnect: PurSocket.Server has no `onDisconnect`. Socket.io's "disconnect" is a system event, not a protocol event, so `onEvent` cannot handle it. Need a thin FFI: `socket.on("disconnect", callback)`. This is a general-purpose server need, so it belongs in PurSocket.Server, not the chat example.
- Timestamp: Need `new Date().toISOString()` for message timestamps. A 1-line FFI in a chat-local module is simplest. Adding `purescript-now` + `purescript-js-date` would work but is heavier than needed for a string timestamp.
- Socket ID: Need a way to identify which socket disconnected to remove from the users list. Socket.io sockets have a `.id` property. Need thin FFI to extract it from SocketRef.

**What could go wrong:** The 80-line target requires keeping comments minimal in the server module. State management across async events needs careful ordering (update ref before broadcasting).

**Approach:**
1. Add `onDisconnect` + `socketId` to PurSocket.Server (library enhancement, 2 functions + FFI)
2. Add `nowISO` as FFI in a chat-local helper module
3. Add `refs` dependency to chat-example spago.yaml
4. Implement Chat.Server.Main
5. Build, run, verify

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | Server implemented at 78 lines. Added `onDisconnect` and `socketId` to PurSocket.Server (library enhancement). Added `nowISO` FFI local to chat example. Fixed spago backend cmd to use `npx` (purs-backend-es not in PATH). Fixed `chat:start` npm script to use `--input-type=module`. All 22 tests + 4 negative compile tests pass. |
