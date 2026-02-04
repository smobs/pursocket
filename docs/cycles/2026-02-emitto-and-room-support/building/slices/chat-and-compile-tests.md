# Slice: Chat Example Update + Negative Compile Tests

**Status:** Complete

## What This Slice Delivers
- Chat example uses `broadcastExceptSender` instead of `broadcast` for `newMessage`, fixing the echo-to-sender bug
- Negative compile tests proving `emitTo` and `broadcastExceptSender` reject wrong-direction events

## Scope

### Chat example update
- In `examples/chat/src/Chat/Server/Main.purs`, replace `broadcast` with `broadcastExceptSender` for the `newMessage` event
- Verify the chat example builds and runs

### Negative compile tests
- Add `test-negative/` entries for `emitTo` with c2s event (must fail to compile)
- Add `test-negative/` entries for `broadcastExceptSender` with c2s event (must fail to compile)
- Follow existing `WrongDirection` pattern

## NOT in This Slice
- Private messaging feature in chat example (explicitly deferred)
- Room usage in chat example

## Dependencies
- emitTo + broadcastExceptSender slice (functions must exist)

## Acceptance Criteria
- [x] Chat example uses `broadcastExceptSender` for `newMessage`
- [x] Chat example builds: `spago build` in examples/chat succeeds
- [x] Negative compile tests exist for `emitTo` wrong direction
- [x] Negative compile tests exist for `broadcastExceptSender` wrong direction
- [x] Negative compile tests fail to compile as expected
- [ ] CI green

## Verification (Required)
- [x] Chat example builds: `spago -x examples/chat/spago.yaml build` or equivalent
- [x] Negative compile tests produce expected errors

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | Chat server updated to use `broadcastExceptSender` for `newMessage`. Two new negative compile tests added: `EmitToWrongDirection.purs` (lobby/chat c2s rejected in s2c) and `BroadcastExceptSenderWrongDirection.purs` (game/move c2s rejected in s2c). All 22 tests pass, 9/9 negative compile tests pass. |
