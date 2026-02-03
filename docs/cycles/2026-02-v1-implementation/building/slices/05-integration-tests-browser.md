# Slice: Integration Tests & Browser Bundling

**Status:** Complete

## What This Slice Delivers
Proof that PurSocket works end-to-end: integration tests that spin up a real Socket.io server, connect a PureScript client, and verify message round-trips. Plus browser bundling via esbuild proving the client works in a browser environment.

## Scope
- Integration test infrastructure: start/stop Socket.io server in test setup/teardown
- Integration tests for `emit` (client->server message delivery)
- Integration tests for `broadcast` (server->client message delivery)
- Integration tests for `call` (request/response round-trip with acknowledgement)
- Integration tests for `onEvent` (server receives typed events)
- Negative compile tests for protocol violations
- esbuild configuration to bundle PurSocket client for browser
- CI step for browser bundle smoke test (esbuild exits 0, bundle is valid JS)

## NOT in This Slice
- Performance testing
- Multi-process / scaling tests
- Browser DOM interaction tests (just bundle validity)

## Dependencies
- Slice 3 (Client API) must be complete
- Slice 4 (Server API) must be complete

## Acceptance Criteria
- [x] Integration tests start a real Socket.io server and connect a PureScript client
- [x] `emit` test: client sends message, server receives it with correct payload
- [x] `broadcast` test: server broadcasts, client receives with correct payload
- [x] `call` test: client sends request, server responds, client gets response
- [x] `onEvent` test: server handler receives typed events
- [x] esbuild bundles PurSocket client without errors
- [x] Browser bundle is valid JavaScript (not just "no errors" -- actually parseable)
- [x] CI pipeline includes integration tests and browser bundle step

## Verification (Required)
- [x] Tests run and pass: `spago test` -> 22/22 tests pass (18 existing + 4 integration)
- [x] Browser bundle: `node scripts/bundle-browser.mjs` -> exits 0, produces 117kb valid bundle
- [x] CI updated with integration tests and browser bundle step
- [x] Negative compile tests: 4/4 still pass

## Build Notes

**Analysis (2026-02-03):**

1. **Current state:** Build and all 18 tests pass. Negative compile tests (4/4) pass. No integration tests exist yet. No browser bundle step in CI.

2. **Architecture for integration tests:**
   - Both client and server run in the same Node.js process. Socket.io client connects to `http://localhost:PORT`.
   - Server: `createServerWithPort 3456` starts the server. Need FFI for `closeServer` (cleanup).
   - Client: `connect "http://localhost:3456"` then `join @"lobby"`. Need FFI for `disconnect`.
   - Client needs an `onMsg` function (receive s2c messages) -- not in current API. Required for broadcast test.
   - Tests use `Aff` for async flow. Delays needed for connection establishment.
   - Server `onEvent` handler callback needs to relay results back to the test assertions.

3. **New FFI added:**
   - Client: `primOnMsg`, `primOnConnect`, `primDisconnect` -- thin wrappers around socket.on/disconnect
   - Server: `primOnCallEvent`, `primCloseServer` -- for ack handling and cleanup
   - CORS enabled in `createServerWithPort` to allow Node.js client connections

4. **New PureScript API functions added:**
   - `Client.onMsg` -- listen for s2c messages (counterpart to Server.broadcast)
   - `Client.onConnect` -- wait for connection establishment
   - `Client.disconnect` -- clean disconnect
   - `Server.onCallEvent` -- handle Call/acknowledgement events
   - `Server.closeServer` -- server cleanup

5. **Browser bundling:**
   - `PurSocket.BrowserTest` module as entry point, references Client.connect at runtime
   - `scripts/bundle-browser.mjs` uses esbuild Node API to bundle
   - Bundle includes socket.io-client (114.8kb total)
   - CI step: `node scripts/bundle-browser.mjs`

6. **Difficulties encountered:**
   - Broadcast test initially failed due to timing -- client namespace connection
     was not established before server broadcast. Fixed by broadcasting from
     the `onConnection` handler so the server broadcasts when it knows the
     client is connected.
   - PureScript compiler dead-code-eliminates unused `let _ = ...` bindings,
     so the BrowserTest module needed a FFI helper to force the Client import
     to be retained in the compiled output.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-03 | Complete | All 4 integration tests pass, browser bundle (117kb) created, CI updated |
