---
name: "emitTo and Room Support"
phase: completed
appetite: "6 weeks"
started: "2026-02-04"
bet_date: "2026-02-04"
---

# Cycle: emitTo and Room Support

## Summary

Add three missing server-side delivery modes to PurSocket: emit to a single client (`emitTo`), broadcast to all except the sender (`broadcastExceptSender`), and room support (`joinRoom`, `leaveRoom`, `broadcastToRoom`). This closes the #1 API gap identified in the surface audit.

## Pitch

See [shaping/pitch.md](shaping/pitch.md) for the full shaped pitch with 18 resolved Q&A threads.

## Bet Decision

See [shaping/bet-decision.md](shaping/bet-decision.md) for risk profile and betting rationale.

## Key Constraints

- All changes land in `Server.purs`, `Server.js`, and tests. No new modules.
- All new functions use `NamespaceHandle ns` (not `ServerSocket`). Clean API split.
- Server module stays 100% `Effect`-based. No `Aff` introduction.
- Room names are runtime `String`. No type-level room names.
- DoD requires both positive and negative delivery assertions for all features.

## Git Tags

| Tag | Date | Notes |
|-----|------|-------|
| `cycle-emitto-and-room-support-start` | 2026-02-04 | Build phase started |
| `cycle-emitto-and-room-support-end` | 2026-02-04 | Shipped |

## Timeline

| Date | Event |
|------|-------|
| 2026-02-04 | Bet placed, build started |
| 2026-02-04 | Shipped (5 functions, 27 tests, 9 negative compile tests) |
| 2026-02-04 | Cooldown started |
| 2026-02-04 | Cooldown complete (6/6 cleanup tasks done) |
