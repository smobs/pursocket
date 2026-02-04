# Slice: Guided Tour & CI

**Status:** Complete
**Assignee:** @qa

## What This Slice Delivers
A GUIDED_TOUR.md document with 3 type error experiments using verbatim compiler output, negative test regression files, and CI integration that prevents drift.

## Scope
- Capture real compiler output for all 3 experiments:
  1. Wrong event name: `emit @ChatProtocol @"chat" @"sendMsg"` (typo)
  2. Wrong direction: client emitting `@"newMessage"` (s2c event)
  3. Wrong payload: `{ message: "Hello" }` instead of `{ text: "Hello" }`
- Create `test-negative/tour/` directory with:
  - `Tour1WrongEvent.purs` — imports Chat.Protocol, uses wrong event name
  - `Tour2WrongDirection.purs` — client sends s2c event
  - `Tour3WrongPayload.purs` — wrong payload field
- Integrate tour negative tests into `test-negative/run-negative-tests.sh`
- Write `examples/chat/GUIDED_TOUR.md`:
  - 3 experiments with exact code changes, verbatim compiler output, explanations
  - "How to read PureScript compiler errors" sidebar before Experiment 3 (3-4 sentences per Q11)
  - Real `TypesDoNotUnify` output annotated inline
- Update `.github/workflows/ci.yml`:
  - Add `npm run chat:build` step (drift prevention)
  - Tour negative tests already covered by existing `run-negative-tests.sh` step
- Add `examples/chat/static/client.bundle.js` to `.gitignore`

## NOT in This Slice
- Any changes to the chat app itself
- README for the chat example (minimal — just point to GUIDED_TOUR.md and root README)

## Dependencies
- Slice 01 (workspace & build plumbing)
- Slice 02 (chat protocol & server) — needed for real compiler output
- Slice 03 (browser client) — needed for client-side experiment examples

## Acceptance Criteria
- [x] `GUIDED_TOUR.md` exists with 3 experiments and verbatim compiler output
- [x] Experiment 3 has "how to read compiler errors" sidebar with real output
- [x] `test-negative/tour/Tour1WrongEvent.purs` correctly fails to compile
- [x] `test-negative/tour/Tour2WrongDirection.purs` correctly fails to compile
- [x] `test-negative/tour/Tour3WrongPayload.purs` correctly fails to compile
- [x] `test-negative/run-negative-tests.sh` includes tour tests and passes
- [x] `npm run chat:build` succeeds in CI
- [x] CI pipeline passes with all new checks

## Verification (Required)
- [x] Negative tests pass: `bash test-negative/run-negative-tests.sh` → 7/7 PASS
- [x] Chat build works: `npm run chat:build` → exits 0
- [x] Full test suite: `npm test` → exits 0 (22/22 tests + 7/7 negative)
- [x] Compiler output in GUIDED_TOUR.md matches actual compiler output

## Build Notes

**Analysis (2026-02-04, @qa):**

1. The existing negative tests use `Proxy`-based `validate` helpers that force constraint resolution
   without needing actual socket connections. Tour tests must follow this same pattern but import
   from `Chat.Protocol` instead of `PurSocket.Example.Protocol`.

2. The `run-negative-tests.sh` script currently only globs `*.purs` files in the `test-negative/`
   directory (not subdirectories). Tour tests live in `test-negative/tour/`, so the script needs
   a second loop or glob pattern for `tour/*.purs` files. The tour tests also need the chat
   example's source path (`examples/chat/src/**/*.purs`) in the `purs compile` command, since
   they import `Chat.Protocol`.

3. Tour negative test 3 (wrong payload) needs to pin the payload type to force unification,
   same approach as `WrongPayload.purs` -- uses `validateWithPayload` with a `Proxy payload`.

4. The `client.bundle.js` is already in `.gitignore`. Good.

5. CI needs one new step: `npm run chat:build`. The negative tests are already covered by the
   existing `run-negative-tests.sh` step, which will pick up the tour tests after the script
   is updated.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | Created 3 tour negative tests, updated run-negative-tests.sh, wrote GUIDED_TOUR.md with verbatim compiler output, added chat:build to CI. All verifications pass: 7/7 negative tests, 22/22 unit+integration tests, chat:build exits 0. |
