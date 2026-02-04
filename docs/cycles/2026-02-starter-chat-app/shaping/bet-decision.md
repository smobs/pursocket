# Betting Decision: Clone-and-Run Starter Chat App

**Date:** 2026-02-04
**Decision:** BET
**Decided by:** User

---

## Risk Profile Presented

*The user reviewed this risk profile before making their decision.*

### Confidence Indicators

✓ **Positive signals:**
- All 5 team members contributed substantively across 14 questions in 3 rounds
- Problem well-validated from two independent perspectives (external-user + product-manager)
- All existing PurSocket APIs already work -- this is packaging, not new feature development
- Clear rabbit holes and no-gos reduce scope ambiguity
- Proven infrastructure exists (negative test pattern, esbuild bundling, CI pipeline)

⚠ **Caution signals:**
- Pitch body has stale references (directory structure, README, CI commands don't match Q&A resolutions)
- "Under 80 lines of PureScript" server target is aspirational but untested
- `spago build -p chat-example` not yet verified with current workspace config
- `purs-backend-es` propagation to workspace members is assumed but untested

✗ **Red flags:**
- None identified

---

## Q&A Summary

| Metric | Count |
|--------|-------|
| Total questions asked | 14 |
| Resolved | 14 |
| Contributors | 5 + user |
| Rounds | 3 |

### Contributors
- @product-manager (drafter, 6 questions asked)
- @external-user (4 questions answered, 2 follow-ups raised)
- @architect (4 questions answered, 1 follow-up raised)
- @web-tech-expert (2 questions answered, 2 follow-ups raised)
- @purescript-specialist (2 questions answered, 2 follow-ups raised)
- @user (4 direct decisions)

---

## High-Signal Concerns

### 1. Build Tooling Complexity
**Asked by:** @external-user, @architect, @web-tech-expert, @purescript-specialist, @user
**Resolution:** npm scripts in root `package.json`, spago workspace member, `spago build -p chat-example` for iteration, no Makefile, no separate `package.json` in `examples/chat/`
**Residual risk:** 6 questions to stabilize this area. Implementation will hit friction here first.

### 2. Workspace Onboarding Flow
**Asked by:** @user, @purescript-specialist
**Resolution:** Users clone the whole repo, run `npm install && npm run chat` from root. This is standard for embedded examples.
**Residual risk:** Quick-start flow depends on npm scripts that reference `output-es/` paths which assume `purs-backend-es` propagates correctly.

---

## Escalation Decisions

### No Makefile
**Question:** How to handle prerequisites and build orchestration?
**Decision:** Use npm scripts in root `package.json` instead of Makefile
**Rationale:** NPM handles packaging/versions natively; `engines` field validates Node version
**Watch for:** If spago commands need to run from a different directory than npm expects

### 2-Week Appetite (bumped from 1 week)
**Question:** Is 1 week enough?
**Decision:** 2 weeks
**Rationale:** User judgment
**Watch for:** Scope should still flex to fit -- the extra week is buffer, not license to expand

### Payload Serialization Constraints Out of Scope
**Question:** Should the example document that payloads must be flat JSON records (no ADTs)?
**Decision:** Out of scope, added to backlog for @purescript-specialist
**Watch for:** Users of the chat example may try `Either` or `Maybe` in payloads and get confused

### Full Workspace Build for Drift Prevention
**Question:** Build chat example on every `spago build`?
**Decision:** Yes, build every time
**Watch for:** If chat example grows complex, it may slow down library development builds

---

## What to Watch

### From Q&A Threads
- **Workspace config friction:** The 2-hour timebox in Rabbit Holes is the escape hatch. If workspace member setup stalls, fall back to standalone project immediately.
- **`purs-backend-es` propagation:** First thing to verify. If `output-es/` doesn't appear for workspace members, all npm script paths break.
- **Real compiler output for Experiment 3:** The sidebar content depends on capturing actual `TypesDoNotUnify` output. Do this early -- it determines how much explanation is needed.

### From Thread Patterns
- **Pitch body drift:** The pitch prose doesn't match Q&A resolutions in several places (directory structure, README, CI). Builders should follow the resolved Q&A, not the pitch prose.
- **Module naming:** Q14 resolved to `Chat.Client.Main` / `Chat.Server.Main` / `Chat.Protocol` but the pitch code block still shows `module ChatProtocol where`. Follow Q14.

### Mitigation Notes
- Verify `spago build -p chat-example` from repo root within the first hour
- Capture all three guided tour compiler outputs before writing the tour document
- If any workspace issue takes >2 hours, switch to standalone fallback

---

## Decision: BET

### Success Criteria
- [ ] `git clone && npm install && npm run chat` produces a running chat server with browser client
- [ ] Chat demonstrates: sendMessage (Msg), setNickname (Call), newMessage/userJoined/userLeft/activeUsers (s2c)
- [ ] GUIDED_TOUR.md walks through 3 type errors with verbatim compiler output
- [ ] Experiment 3 includes "how to read compiler errors" sidebar with real output
- [ ] `test-negative/tour/` regression tests pass in CI
- [ ] `npm run chat:build` succeeds in CI (drift prevention)
- [ ] All npm scripts live in root `package.json`
- [ ] Modules namespaced as `Chat.Client.Main`, `Chat.Server.Main`, `Chat.Protocol`
- [ ] HTML client under 50 lines, server under 80 lines PureScript

---

## Recommended Execution Team

| Role | Why Needed |
|------|-----------|
| @purescript-specialist | Primary builder. Workspace config, spago setup, PureScript modules, negative test infrastructure |
| @web-tech-expert | Browser bundling, Socket.io client setup, `index.html`, esbuild npm scripts |
| @external-user | Validate onboarding flow end-to-end. Test quick-start from fresh clone. Review guided tour clarity |

## Reviewers for Build Team

| Reviewer | Recommendation | Rationale |
|----------|----------------|-----------|
| @architect | Consulting | Key decisions on workspace and module naming already made. Available for build config questions |
| @product-manager | Consulting | Guided tour framing and README quality review. Not primary implementer |
| @qa | Builder | Not involved in shaping but needed for CI integration, negative test scripts, and regression testing |
| @external-user | Builder | Must validate the entire onboarding flow works as designed |

---

## Next Steps

Run `/project-orchestrator:project-build` to start execution.
