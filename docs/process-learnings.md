# Process Learnings

Accumulated learnings from project cycles. Check these before starting new work.

---

### 2026-02-03 — PurSocket v1 Implementation

**From Team Proposals:**
- Create a throwaway compiler-verified prototype during shaping to validate type-level mechanisms before finalizing the spec (proposed by architect)
- Include FFI runtime requirement documentation alongside phantom type designs (proposed by web-tech-expert)
- Scope both send-side and receive-side operations when shaping bidirectional API slices (proposed by qa)

**Shaping:** Thorough Q&A (15 questions) was valuable. But spec code was conceptual, not compiler-verified — 4 assumptions broke during implementation. Add a "compiler verification" step to shaping for type-level designs.

**Building:** Parallel slice execution worked well. Coordinator verification caught a critical bug (negative tests not forcing constraint resolution) that subagents missed. Always verify compilation independently after subagent work.

**Scoping:** Send-only API slices created a gap filled during integration testing. For bidirectional protocols, scope receive-side alongside send-side.

### 2026-02-04 — Clone-and-Run Starter Chat App

**From Team Proposals:**
- Create pre-build API checklist cross-referencing Socket.io primitives against target application (proposed by purescript-specialist)
- Add `attachToHttpServer` to PurSocket.Server for standard deployment patterns (proposed by web-tech-expert)
- Declarative config file convention for negative test subdirectories (proposed by qa)
- Create `docs/GETTING_STARTED.md` for "start your own project" path (proposed by product-manager)
- Full Socket.io API surface audit with keep/defer/never decisions (proposed by architect)
- "New Project Setup" section in README with copy-pasteable steps (proposed by external-user)

**Shaping:** Shaped pitch accurately predicted scope. Two clean scope cuts (timestamp, server lifecycle) didn't affect core value.

**Building:** Building a real application exposed 2 library API gaps that integration tests missed. Test suite validates protocol correctness but not application completeness. Pre-build API checklists would catch this earlier.

**Documentation:** Demo onboarding (3 commands) works, but "start your own project" path is undocumented. Server bootstrap, client bundling, and Effect calling convention are all invisible steps. Document the glue, not just the API.

### 2026-02-04 — emitTo and Room Support

**From Team Proposals:**
- Build Questions Log template for capturing implementation decisions during build (proposed by purescript-specialist)
- PureScript API Gotchas cheat-sheet for stdlib pitfalls like `Ref.modify` semantics (proposed by qa)
- Socket.io FFI semantics reference documenting transient operators, promise handling, and adapter compatibility (proposed by web-tech-expert)

**Shaping:** Exhaustive Q&A (18 questions, 6 contributors) eliminated all design ambiguity. Build was pure execution — zero fix commits, zero design decisions during build. When shaping is this thorough, appetite can be much shorter than the default.

**Building:** Retro note files were created but not used. Empty templates don't get filled. Structured prompts ("what did you decide and why?") are more likely to capture knowledge. The QA agent's `Ref.modify` issue was noted in a slice progress log but not in the retro file — different capture points have different friction levels.

**Testing:** Negative delivery assertions are essential for delivery-mode functions. A positive-only test for `emitTo` would pass even if the implementation were `broadcast`. The QA team's insistence on both positive AND negative assertions in the DoD was the right call.
