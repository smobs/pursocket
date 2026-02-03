# Retrospective: PurSocket v1 Implementation

**Shipped:** 2026-02-03
**Cool-down started:** 2026-02-03

## Summary

PurSocket v1 shipped all 6 slices in a single session with no scope cuts — well within the 6-week appetite. The biggest technical surprise was that PureScript's `Row.Cons` is a compiler intrinsic that bypasses instance chains, requiring a full rewrite of the type engine to RowToList-based lookup classes. The spec (BRIEF.md) contained 4 assumptions that didn't survive implementation contact. Parallel slice execution worked well with no merge conflicts. The team's retro notes (17 entries across 3 members) reveal a consistent theme: spec verification before building would have prevented the largest rework items.

## What Worked

- Parallel slice execution (3+4, then 5+6) maximized throughput with no conflicts
- RowToList-based type engine produced excellent custom type errors
- Thin ESM FFI pattern (1-3 lines per function) kept the JS layer trivially auditable
- Prioritized cut list was never needed — good sign that the architecture was sound
- Integration tests caught real issues (async timing, missing receive-side API)
- Negative compile test verification by the coordinator caught a critical testing bug

## What to Improve

- **Compiler-verify spec before building:** BRIEF.md had 4 broken assumptions (records vs rows, Row.Cons instance chains, phantom-only NamespaceHandle, IsValidCall fundep)
- **Scope bidirectional APIs completely:** Client/Server slices only had send-side; receive-side was discovered in integration testing
- **Document FFI runtime requirements alongside type designs:** Phantom types that need runtime payloads should be identified during shaping

## Team Improvement Actions

| Action | Proposed By | Effort | Owner | Status |
|--------|-------------|--------|-------|--------|
| Create throwaway compiler-verified prototype during shaping | architect | small | self | pending |
| Include FFI runtime requirement doc with phantom type designs | web-tech-expert | small | self | pending |
| Scope both send-side and receive-side in bidirectional API slices | qa | small | process | pending |

## Process Notes

- **Shaping:** Thorough Q&A (15 resolved questions) caught naming, architecture, and scope issues. But the spec's PureScript code was never compiled, leading to 4 implementation surprises.
- **Reviews:** Not formally conducted during build (single-session execution). Coordinator verification caught the negative test bug.
- **Appetite:** 6 weeks for work completed in 1 session. Appetite was generous — appropriate for a first cycle with unknowns, but future cycles could be tighter.
- **Scope hammering:** Never needed. All features shipped.

## Team Notes

- **Continue:** architect, web-tech-expert, qa — all contributed meaningfully
- **Consider adding:** None for library work; if browser demo becomes priority, consider frontend specialist
- **No longer needed:** product-manager and external-user were consulting roles, not used during build

## Ideas Captured

| Idea | Size | Urgency | Priority |
|------|------|---------|----------|
| Standalone runnable demo (browser + Node) | Small | next-cycle | Medium |
| PureScript Registry publishing | Medium | next-cycle | High |
| Spago workspace split | Medium | someday | Low |

## Key Lessons

1. **Compiler-verify type-level specs before building.** A 30-minute throwaway prototype during shaping would have caught the Row.Cons limitation and saved the RowToList rewrite.
2. **Bidirectional APIs need bidirectional scoping.** Slicing by send-side only creates predictable gaps that surface during integration testing.
3. **Phantom types that cross FFI boundaries need runtime payload planning.** The distinction between type-level-only and FFI-carrying phantom types should be made explicit during design.
