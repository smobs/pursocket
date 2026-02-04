# PureScript Specialist Memory

## Spago Workspace Discovery (2026-02-04)

**Key insight:** In spago 0.93.x, workspace members are auto-discovered from subdirectories containing a `spago.yaml` with a `package:` block. Do NOT list workspace members under `workspace.extraPackages` -- that key is for external/third-party packages. Attempting to list a workspace member there causes error: "Some packages in your local tree overlap with ones you have declared in your workspace configuration."

**purs-backend-es propagation:** Confirmed working. The `workspace.backend` config in the root `spago.yaml` propagates to all auto-discovered workspace members. Output goes to `output-es/` as expected. This was the #1 risk from the bet decision and it resolved cleanly.

## Project State

- `examples/chat/` exists as a workspace member with stubs for `Chat.Protocol`, `Chat.Client.Main`, `Chat.Server.Main`
- Root `package.json` has `chat:build`, `chat:start`, `chat` scripts
- Slice 01 (Workspace & Build Plumbing) is complete
- Slices 1+2 of emitTo/Room cycle complete: `emitTo`, `broadcastExceptSender`, `joinRoom`, `leaveRoom`, `broadcastToRoom` added to `PurSocket.Server`
- All 22 tests and 7 negative compile tests pass
- `spago build` compiles both `pursocket` and `chat-example` packages

## Build Commands

- `spago build -p chat-example` -- builds just the chat example (fast iteration)
- `spago build` -- builds all workspace members (drift prevention)
- `npm test` -- full test suite (unit + integration + negative compile)
- `npm run chat:build` -- builds chat example + esbuild browser bundle
- `npm run chat:start` -- runs the chat server
- `npm run chat` -- build + start in sequence

## Existing Patterns

- Protocol types are row types using `Msg` and `Call` data kinds from `PurSocket.Protocol`
- Module namespace convention: `PurSocket.*` for library, `Chat.*` for chat example
- FFI files are `.js` alongside `.purs` modules
- Negative compile tests live in `test-negative/` as standalone `.purs` files
- Browser bundle script is `scripts/bundle-browser.mjs` using esbuild
- Integration tests in `test/Test/Integration.purs` spin up real Socket.io server

## Server API Patterns (emitTo/Room cycle)

- **Namespace-wide ops** (`broadcast`, `onConnection`) take `ServerSocket` + `IsSymbol ns` -- they use `io.of("/" + ns)`
- **Per-socket ops** (`emitTo`, `broadcastExceptSender`, `broadcastToRoom`, `onEvent`, `onCallEvent`, `onDisconnect`, `socketId`) take `NamespaceHandle ns` -- they use the SocketRef from the handle directly, no `IsSymbol ns` needed
- `joinRoom`/`leaveRoom` are constraint-free (no protocol validation needed, rooms are runtime strings)
- `broadcastToRoom` uses socket-level semantics (`socket.to(room).emit()`) which automatically excludes the sender
- All new FFI functions use `forall a` for payload -- type safety enforced upstream by `IsValidMsg`
- `joinRoom`/`leaveRoom` discard the Promise from `socket.join()`/`socket.leave()` -- correct for default in-memory adapter
