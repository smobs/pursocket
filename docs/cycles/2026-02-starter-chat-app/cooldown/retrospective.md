# Retrospective: Clone-and-Run Starter Chat App

**Shipped:** 2026-02-04
**Cool-down started:** 2026-02-04

## Summary

The starter chat app shipped in a single day against a 2-week appetite, demonstrating that the v1 library is architecturally sound for building real applications. The type-level machinery (IsValidMsg, IsValidCall, NamespaceHandle phantom types, directional constraints) held up without modification. The cycle exposed two categories of gaps: (1) the library API was scoped to protocol events and missed Socket.io system events and lifecycle primitives that real apps need, and (2) the onboarding path from "run the demo" to "start my own project" has undocumented steps that would block evaluators. Both are addressable with small, concrete actions before the next cycle.

## What Worked

- The v1 library was solid enough that only 2 additions were needed (onDisconnect, socketId)
- Slice-based building kept work focused — 4 slices completed sequentially without blockers
- Zero-FFI constraint for the chat example forced clean API design
- Negative test infrastructure from the v1 cycle was reusable for guided tour experiments
- The entire 2-week appetite completed in 1 day — build velocity was high

## What to Improve

- **Library API surface**: Scoped to protocol events only; missed system events (disconnect, connect_error) and lifecycle methods (socket.id, rooms, HTTP attachment). Needs a comprehensive audit.
- **Onboarding documentation**: Demo works in 3 commands, but no guidance for starting a new project (server wrapper, esbuild bundling, Effect calling convention)
- **Test infrastructure**: Negative test runner hardcoded per-category; needs declarative config convention
- **Commit hygiene**: Cycle work was largely uncommitted; tags pointed to same commit

## Team Improvement Actions

| Action | Proposed By | Effort | Owner | Status |
|--------|-------------|--------|-------|--------|
| Pre-build API checklist for future cycles | PureScript Specialist | small | self | pending |
| `attachToHttpServer` for PurSocket.Server | Web Tech Expert | small | team | pending |
| Config file convention for negative tests | QA | small | self | pending |
| `docs/GETTING_STARTED.md` guide | Product Manager | small | team | pending |
| Socket.io API surface audit | Architect | small | self | pending |
| "New Project Setup" section in README | External User | small | self | pending |

## Process Notes

- **Shaping:** Questionnaire not filled in by user. From commit data: the shaped pitch accurately predicted scope — 4 slices mapped to the 4 sections of work. Two scope cuts (timestamp, server lifecycle) were clean.
- **Appetite:** 2-week appetite, 1-day actual. Generous but appropriate — if the library had needed rework, 2 weeks would have been necessary. The v1 cycle de-risked this one.
- **Scope hammering:** 2 clean cuts (timestamp field, PureScript-owned server lifecycle). Neither affected the core value proposition. Both are captured as future ideas.

## Team Notes

- **Continue:** All 6 team members contributed meaningfully. PureScript Specialist and Web Tech Expert carried the implementation. QA's test infrastructure work was reusable. Architect's design held up. Product Manager's guided tour requirement was the key differentiator. External User validated the onboarding flow.
- **Consider adding:** No gaps identified.
- **No longer needed:** No roles to remove.

## Ideas Captured

| Idea | Size | Urgency | Priority |
|------|------|---------|----------|
| HTTP server attachment API | Small | next-cycle | High — undermines "zero FFI" selling point |
| Timestamp/metadata helpers | Small | someday | Low — JS workaround exists |
| PureScript DOM bindings for examples | Large | someday | Low — inline JS is pragmatic |

## Key Lessons

1. **Building a real application is the best API test.** Integration tests validated protocol correctness but missed system events and lifecycle methods. The chat example exposed 2 library gaps in a single day that months of testing wouldn't have found.
2. **Document the glue, not just the API.** The README shows how to write PureScript code but not how to run it. Server bootstrap, client bundling, and the Effect calling convention are all undocumented steps between "code compiles" and "app runs."
3. **Scope protocol events separately from system events.** Socket.io has two distinct API surfaces — protocol events (typed by PurSocket) and system events (disconnect, error, reconnect). The library should explicitly decide which system events to wrap rather than discovering gaps mid-build.
