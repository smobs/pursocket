# Slice: Integration Tests

**Status:** Complete

## What This Slice Delivers
7 multi-client integration test scenarios proving correct delivery AND non-delivery for all new functions. This is the primary safety net for FFI correctness.

## Scope

### emitTo tests (2 scenarios)
1. **Positive delivery:** Server calls `emitTo` on client A's handle. Client A receives the message.
2. **Exclusivity (negative):** Connect A and B. Server calls `emitTo` on A's handle. B does NOT receive.

### broadcastExceptSender tests (2 scenarios)
3. **Others receive:** Connect A and B. A triggers c2s event; server calls `broadcastExceptSender` using A's handle. B receives.
4. **Sender excluded:** Same setup. A does NOT receive.

### Room tests (3 scenarios)
5. **joinRoom + broadcastToRoom delivery:** A joins "r1", B does not. Server calls `broadcastToRoom "r1"` from some handle. A receives, B does not.
6. **leaveRoom stops delivery:** A joins "r1", then leaves. `broadcastToRoom "r1"`. A does NOT receive.
7. **Multiple rooms isolation:** A in "r1", B in "r2". `broadcastToRoom "r1"` reaches A only. `broadcastToRoom "r2"` reaches B only.

### Test infrastructure
- Multi-client pattern: connect 2-3 clients per test, sequential connection with small delay
- Per-client `Ref` values for delivery tracking
- 200-300ms delay for delivery assertions
- Unique port per test (starting at `testPort + 4`)
- Negative assertions: check `Ref` still holds sentinel value after delay

## NOT in This Slice
- Negative compile tests (separate slice)
- Chat example update (separate slice)

## Dependencies
- emitTo + broadcastExceptSender slice (functions must exist)
- Room support slice (functions must exist)

## Acceptance Criteria
- [x] All 7 test scenarios pass
- [x] Each scenario has both positive and negative delivery assertions
- [x] Tests use sequential client connection to avoid flakes
- [x] All existing tests continue to pass
- [x] `spago test` succeeds

## Verification (Required)
- [x] Tests run and pass: `npm test` -> 27/27 tests pass, no failures
- [x] Existing tests still pass (no regressions) -- original 22 tests unaffected
- [x] Negative compile tests still pass -- 9/9

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | All 7 scenarios implemented in 5 test blocks (emitTo combines scenarios 1+2, broadcastExceptSender combines 3+4, room tests are 5, 6, 7 individually). Hit `Ref.modify` returning new-value (not old) -- fixed case patterns from 0/1/2 to 1/2/3. All 27 tests pass on first run after fix. |
