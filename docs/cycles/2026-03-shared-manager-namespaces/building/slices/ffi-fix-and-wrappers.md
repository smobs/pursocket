# Slice: FFI Fix and Client Wrappers

**Status:** Not started

## What This Slice Delivers
Namespace connections share a single WebSocket transport. Consumers can register connect/disconnect callbacks on namespace handles via public API.

## Scope
- Update `primJoin` in `src/PurSocket/Client.js` to use `baseSocket.io.socket("/" + ns)`
- Add `onConnectNs` wrapper to `PurSocket.Client` (delegates to existing `primOnConnect`)
- Add `onDisconnectNs` wrapper to `PurSocket.Client` (delegates to existing `primOnDisconnect`)
- Export both new functions from the module
- Verify existing test suite still passes after FFI change

## NOT in This Slice
- New tests (that's slice 2)
- Documentation / changelog
- `disconnectAll` API (deferred)
- Double-join guard (deferred)

## Dependencies
- None — this is the foundation slice

## Acceptance Criteria
- [ ] `primJoin` uses `baseSocket.io.socket("/" + ns)` instead of `io(baseUrl + "/" + ns)`
- [ ] `onConnectNs :: forall protocol ns. NamespaceHandle protocol ns -> Effect Unit -> Effect Unit` exported from `PurSocket.Client`
- [ ] `onDisconnectNs :: forall protocol ns. NamespaceHandle protocol ns -> (DisconnectReason -> Effect Unit) -> Effect Unit` exported from `PurSocket.Client`
- [ ] `spago build` succeeds
- [ ] `spago test` passes (existing tests)

## Verification (Required)
- [ ] Tests run and pass: `spago test` → all existing tests green
- [ ] Build succeeds: `spago build` → no errors

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
