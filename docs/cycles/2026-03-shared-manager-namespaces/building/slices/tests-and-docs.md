# Slice: Tests and Documentation

**Status:** Not started

## What This Slice Delivers
Proof that namespace multiplexing works: two namespaces on one socket, independent message delivery, disconnect isolation. Behavioral changes documented for consumers.

## Scope
- Multi-namespace multiplexing test: join lobby + game on same base socket, emit on both, verify independent delivery
- Namespace-disconnect-isolation test: disconnect one namespace, verify other survives and can still send/receive
- Update pitch "What consumers need to know" text into a migration/changelog entry

## NOT in This Slice
- Reconnection test (deferred — requires new FFI for `engine.close()`)
- Double-join aliasing test (deferred)

## Dependencies
- Slice 1 (FFI fix and wrappers) must be complete

## Acceptance Criteria
- [ ] Multi-namespace test passes: joins lobby + game on same socket, both emit/receive independently
- [ ] Disconnect-isolation test passes: disconnect one namespace, other stays alive and functional
- [ ] All tests pass together: `spago test`
- [ ] Behavioral changes documented

## Verification (Required)
- [ ] Tests run and pass: `spago test` → all tests green including new ones
- [ ] New tests exercise shared Manager behavior specifically

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
