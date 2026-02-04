# Hill Chart

**Project:** emitTo and Room Support
**Appetite:** 6 weeks
**Started:** 2026-02-04

## Understanding the Hill

```
        ▲
       /|\        FIGURING OUT (uphill)
      / | \       - Uncertainty
     /  |  \      - Discovery
    /   |   \     - Problem-solving
   /    |    \
  /     |     \
 /      |      \  EXECUTION (downhill)
/       |       \ - Known work
        |         - Just doing it
────────┴─────────
```

## Current Status

| Slice | Position | Notes |
|-------|----------|-------|
| emitTo + broadcastExceptSender | ✅ Complete | FFI + PureScript wrappers for two per-socket delivery modes |
| Room support | ✅ Complete | joinRoom, leaveRoom, broadcastToRoom |
| Integration tests | ✅ Complete | 27/27 tests pass, 7 new multi-client scenarios |
| Chat example update + negative compile tests | ✅ Complete | 9/9 negative compile tests pass |

## History

| Date | Slice | Movement | Notes |
|------|-------|----------|-------|
| 2026-02-04 | All | Created | Build phase started |
| 2026-02-04 | emitTo + broadcastExceptSender | Complete | 5 FFI + 5 PureScript wrappers, spago build clean |
| 2026-02-04 | Room support | Complete | Built together with Slice 1 |
| 2026-02-04 | Integration tests | Complete | 7 scenarios in 5 test blocks, all pass |
| 2026-02-04 | Chat + compile tests | Complete | broadcastExceptSender in chat, 2 new negative tests |
