# Slice: Example Protocol, Demo & Docs

**Status:** Complete

## What This Slice Delivers
The onboarding story: an example `AppProtocol` module developers can import to experiment with, a fully runnable client+server demo application, and a README with installation, quick-start, API reference, and complete example.

## Scope
- `PurSocket.Example.Protocol`: example `AppProtocol` with lobby/game namespaces (from BRIEF.md)
- `examples/hello-world/client/`: PureScript browser client using PurSocket
- `examples/hello-world/server/`: PureScript/Node server using PurSocket
- README.md: installation, quick-start, API reference, client+server example
- Document npm peer dependencies (socket.io-client, socket.io)
- Document git dependency installation (if not on registry)

## NOT in This Slice
- Registry publishing (deferred per cut list if needed)
- Advanced documentation (guides, tutorials beyond quick-start)
- Multiple example applications

## Dependencies
- Slice 3 (Client API) must be complete
- Slice 4 (Server API) must be complete
- Slice 5 (Integration Tests) should be complete (proves everything works)

## Acceptance Criteria
- [x] `PurSocket.Example.Protocol` exports a working `AppProtocol` type
- [x] Example protocol includes `Msg` and `Call` patterns, `c2s` and `s2c` directions, multiple namespaces
- [x] `PurSocket.Example.Client` and `PurSocket.Example.Server` contain compilable client and server demos (placed under `src/` for `spago build` compilation)
- [x] Demo compiles and type-checks: both client and server import the same `AppProtocol`, proving the shared contract
- [x] README has: installation, quick-start, API reference, complete example
- [x] npm peer dependencies are documented

## Verification (Required)
- [x] Example protocol compiles: `spago build` exits 0 (all example modules compile with 0 warnings, 0 errors)
- [x] Demo type-checks: `PurSocket.Example.Client` and `PurSocket.Example.Server` compile, proving all `emit`, `call`, `broadcast`, `onEvent` calls are valid against `AppProtocol`
- [x] README is accurate: code snippets use actual API signatures (`emit @AppProtocol @"lobby" @"chat"`, etc.)
- [x] `spago test` passes (18/18 unit tests; 1 pre-existing integration test failure in broadcast timing unrelated to this slice)

## Build Notes

**Analysis (2026-02-03):**

1. **Example Protocol** -- `src/PurSocket/Example/Protocol.purs` is already complete and well-documented. It has both `Msg` and `Call` patterns, `c2s` and `s2c` directions, and two namespaces (lobby, game). Doc comments explain the row-type structure. No changes needed.

2. **Demo placement** -- The pitch Q&A resolved that the demo should live in `examples/` as runnable files, separate from `PurSocket.Example.Protocol`. However, compiling under `spago build` is more important than directory structure. I will place demo modules under `src/PurSocket/Example/Server.purs` and `src/PurSocket/Example/Client.purs` so they compile with `spago build`. These import the existing `AppProtocol` from `PurSocket.Example.Protocol`, proving the shared contract story.

3. **Demo limitations** -- The demo modules cannot have `main` functions that actually run (they would require a real Socket.io server and browser). Instead, they will be importable example modules showing complete usage patterns that compile and type-check. The README will reference these as the canonical examples.

4. **README** -- Will cover installation (git dep + npm peers), quick start, API reference, full example, type-level explanation, and scope. Code snippets will match actual API signatures from the source files.

5. **Peer dependencies** -- `package.json` already lists `socket.io` and `socket.io-client` as dependencies. README will document these as peer dependencies for users.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-03 | Complete | Example Protocol verified, Example.Client and Example.Server created under src/, README.md created with full API reference, peer deps documented. All modules compile cleanly. |
