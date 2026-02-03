# Betting Decision: PurSocket v1 Implementation

**Date:** 2026-02-03
**Decision:** BET
**Decided by:** @user

---

## Risk Profile Presented

*The user reviewed this risk profile before making their decision.*

### Confidence Indicators

**Positive signals:**
- Row.Cons constraint pattern is well-established in PureScript ecosystem
- FFI is intentionally thin (1-3 line JS wrappers) -- low impedance mismatch risk
- Socket.io namespace API maps 1:1 to NamespaceHandle phantom type
- Clear prioritized cut list: Call pattern, registry publishing, custom type errors
- NamespaceHandle is cheap (~5 lines) despite being the key differentiator
- No naming collisions on Pursuit; greenfield opportunity

**Caution signals:**
- No prior art for PureScript + Socket.io + browser bundling -- discovery risk in CI setup
- Integration tests need real Socket.io server lifecycle management
- Spec requires two amendments before building (terminology rename + IsValidCall fundep fix)
- Thin scope margins: client, server, browser, demo all non-negotiable
- Spago workspace split may be deferred to v1.1

**Red flags:**
- None identified

---

## Q&A Summary

| Metric | Count |
|--------|-------|
| Total questions asked | 15 |
| Resolved | 15 |
| Contributors | 3 |
| User overrides | 1 |

### Contributors
- @architect (drafter, 10 questions asked, 6 self-answered)
- @product-manager (3 questions answered, 3 follow-ups asked)
- @user (6 questions answered, 1 override)

---

## High-Signal Concerns

### 1. Namespace/Room Terminology + FFI Mapping
**Asked by:** @architect (3 threads)
**Resolution:** Protocol "rooms" renamed to "namespaces" to match Socket.io language. FFI targets namespace API exclusively. BRIEF.md spec must be amended before building.
**Residual risk:** Spec amendment is a prerequisite -- if incomplete, implementers work from stale reference.

### 2. Scope Pressure
**Asked by:** @architect
**Resolution:** @user declared client, server, browser, and demo all non-negotiable. Cut list: Call pattern first, then registry publishing, then custom type errors.
**Residual risk:** If type-level engine or FFI takes longer than expected, margins are thin.

### 3. Spago Workspace Tooling
**Asked by:** @architect
**Resolution:** Start monolithic, attempt workspace split at week 2/3 boundary with 2-hour timebox. Defer if problematic.
**Residual risk:** v1 may ship as single package with convention-based client/server isolation only.

---

## Escalation Decisions

| Decision | Commitment | Watch For |
|----------|------------|-----------|
| Both client and server in v1 | Non-negotiable | Server-side namespace broadcasting complexity |
| Browser usage mandatory | Esbuild CI testing required | Unknown bundling issues with PureScript + Socket.io |
| No escape hatch | No PurSocket.Unsafe module | Adoption friction for existing Socket.io codebases |
| Socket.io terminology | Rename rooms->namespaces in spec and code | Spec amendment must complete before build starts |
| Fix spec first | IsValidCall fundep bug in BRIEF.md | Blocking prerequisite for build phase |
| Latest PureScript | No backward compat | None -- simplifies implementation |

---

## What to Watch

### From Q&A Threads
- **Spec amendments blocking build start:** Two changes to BRIEF.md (namespace terminology, IsValidCall fix) must be completed before Layer 1 work begins
- **Browser bundling unknowns:** No precedent for PureScript + socket.io-client in esbuild. May surface issues with CommonJS/ESM interop or Socket.io's transport detection
- **Call/acknowledgement FFI:** If in scope, the makeAff wrapper for Socket.io callbacks needs careful timeout/disconnect handling
- **Integration test infrastructure:** Spinning up Socket.io servers in CI and running browser tests has no prior art in this repo

### Mitigation Notes
- Spec amendments can be done in week 1 alongside project skeleton setup
- Browser bundling should be validated early (week 2) with a minimal esbuild smoke test
- If Call pattern proves complex, it's first on the cut list
- Integration test setup is part of Layer 0 (weeks 1-2) -- early discovery

---

## Decision: BET

### User's Rationale
Risk profile is acceptable. Architecture is validated, cut list is clear, and the pitch is thorough.

### Success Criteria
- [ ] Published and installable (registry or git dependency)
- [ ] Core API end-to-end: define AppProtocol, connect, join namespace, emit, call -- all compile-time validated
- [ ] Compile-time safety proven with negative tests
- [ ] CI green: build, unit tests, integration tests, browser bundle test
- [ ] README with installation, quick-start, API reference, client+server example
- [ ] Server-side API works: broadcast and onEvent with shared protocol type
- [ ] Working demo: browser client + Node server communicating via PurSocket

---

## Recommended Execution Team

| Role | Why Needed |
|------|-----------|
| @architect | Primary implementer. Designed the type-level engine, FFI strategy, and module structure. |
| @web-tech-expert | Socket.io internals, browser bundling, transport layer expertise. Critical for FFI correctness and esbuild CI setup. |
| @qa | Test strategy: negative compile tests, FFI integration tests, browser test infrastructure. |

---

## Reviewers for Build Team

| Reviewer | Recommendation | Rationale |
|----------|----------------|-----------|
| @architect | Builder | Drafter and primary technical decision-maker throughout shaping |
| @web-tech-expert | Builder | Socket.io transport expertise essential for FFI and browser bundling |
| @qa | Builder | Test infrastructure is a major part of weeks 1-2 |
| @product-manager | Consulting | Valuable DX perspective for API design and documentation review |
| @external-user | Consulting | End-user perspective for API ergonomics and getting-started story |

---

## Next Steps

Run `/project-orchestrator:project-build` to start execution.
