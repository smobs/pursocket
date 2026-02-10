# Cleanup Tasks

**Project:** emitTo and Room Support
**Cycle:** emitTo and Room Support
**Started:** 2026-02-04

## Overview

| Total | Pending | In Progress | Complete |
|-------|---------|-------------|----------|
| 6 | 0 | 0 | 6 |

## Tasks

| # | Task | Type | Effort | Assignee | Status | Completed |
|---|------|------|--------|----------|--------|-----------|
| 1 | Add FFI trust boundary note to Server.purs module doc | docs | 1h | purescript-specialist | complete | 2026-02-04 |
| 2 | Verify integration test timing reliability | polish | 2h | qa | complete | 2026-02-04 |
| 3 | Review doc comments on all 5 new functions | docs | 1h | purescript-specialist | complete | 2026-02-04 |
| I1 | Create Build Questions Log template | process | 1h | purescript-specialist | complete | 2026-02-04 |
| I2 | Create PureScript API Gotchas cheat-sheet | docs | 1h | qa | complete | 2026-02-04 |
| I3 | Create Socket.io FFI semantics reference | docs | 2h | web-tech-expert | complete | 2026-02-04 |

## Tasks by Assignee

### purescript-specialist

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| 1 | Add FFI trust boundary note to Server.purs module doc comment. Note that `prim*` functions use `forall a` for payloads and type safety is enforced by `IsValidMsg`/`IsValidCall` constraints. Warn against calling `prim*` directly. | docs | 1h | complete |
| 3 | Review doc comments on all 5 new functions for completeness. Ensure handle lifecycle pattern (store in Ref Map, clean up in onDisconnect) is mentioned on `emitTo`. Cross-check against pitch Q&A guidance. | docs | 1h | complete |
| I1 | Create a Build Questions Log template at `docs/current/building/questions-log.md` for future cycles. Each entry: question, decision, rationale. (From PureScript Specialist retro proposal) | process | 1h | complete |

### qa

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| 2 | Run `npm test` 3x consecutively. Verify all pass. If any flakes, investigate timing. Document delay choices. | polish | 2h | complete |
| I2 | Create `docs/purescript-gotchas.md` capturing `Ref.modify` return semantics and other stdlib pitfalls discovered during testing. (From QA retro proposal) | docs | 1h | complete |

### web-tech-expert

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| I3 | Create `docs/ffi-socket-io-patterns.md` documenting: transient operators vs stable objects, promise discarding rules, namespace path construction rules, adapter-aware operations matrix. (From Web Tech Expert retro proposal) | docs | 2h | complete |

## Improvement Actions (From Team Retro)

| # | Action | Proposed By | Effort | Owner | Status |
|---|--------|-------------|--------|-------|--------|
| I1 | Build Questions Log template for future cycles | purescript-specialist | small | process | complete |
| I2 | PureScript API Gotchas cheat-sheet | qa | small | self | complete |
| I3 | Socket.io FFI semantics reference | web-tech-expert | small | process | complete |
