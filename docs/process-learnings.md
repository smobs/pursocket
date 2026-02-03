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
