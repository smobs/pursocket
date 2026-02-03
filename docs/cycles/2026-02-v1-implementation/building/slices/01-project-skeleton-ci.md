# Slice: Project Skeleton & CI

**Status:** Done

## What This Slice Delivers
A compiling PureScript project with all module stubs, npm dependencies, spago configuration, and a green CI pipeline. The foundation everything else builds on.

## Scope
- Initialize `spago.yaml` (monolithic, single package) with all PureScript dependencies
- Initialize `package.json` with `socket.io`, `socket.io-client`, `purescript`, `spago`, `esbuild`, `purs-tidy`, `purs-backend-es`
- Create module stubs for all `PurSocket.*` modules (Protocol, Framework, Client, Server, Example.Protocol)
- Create `.gitignore` for output/, node_modules/, .spago/
- `spago build` succeeds
- `spago test` runs (even with stub tests)
- GitHub Actions CI pipeline: build + test

## NOT in This Slice
- Actual implementation of any module (just stubs/skeletons)
- Browser bundling (that's Slice 5)
- Working FFI (just the file structure)

## Dependencies
- None (this is the first slice)

## Acceptance Criteria
- [x] `spago.yaml` configured with all needed PureScript dependencies
- [x] `package.json` has socket.io, socket.io-client, purescript, spago, esbuild
- [x] All `PurSocket.*` module stubs exist and compile
- [x] `spago build` succeeds
- [x] `spago test` runs purescript-spec suite (stub tests OK)
- [x] `.gitignore` covers output/, node_modules/, .spago/, .psci_modules/
- [x] GitHub Actions workflow file exists and would run build + test

## Verification (Required)
- [x] Tests run and pass: `spago test` -> exits 0
- [x] Build succeeds: `spago build` -> exits 0
- [x] All module files exist in src/PurSocket/

## Build Notes

**Done means:** `spago build` exits 0, `spago test` exits 0, all five PurSocket.* stub modules compile, package.json has socket.io deps, .gitignore is correct, CI workflow exists.
**Critical path:** spago.yaml config (package set + deps) -> module stubs compile -> test stub runs. Everything depends on spago config being right.
**Unknowns:** Exact package set URL for latest spago@next (2026). Whether purescript-spec needs extra transitive deps.
**Applicable risks:** Spago workspace tooling is not a risk yet (starting monolithic). Browser bundling is not in this slice.
**Approach:** (1) .gitignore, (2) package.json + npm install, (3) spago.yaml, (4) module stubs + test stub, (5) verify build/test, (6) GitHub Actions CI, (7) update this doc.

**Difficulty encountered:** The BRIEF.md spec defines `AppProtocol` with records `{ c2s :: (...), s2c :: (...) }` at the namespace level, but this causes a kind mismatch because a record field must have kind `Type` while bare row types have kind `Row Type`. The fix was to use row types at every level (namespace, direction, and event levels are all rows, not records). This means the `Row.Cons` constraint chain will decompose rows directly at each level. This is a design decision that will carry through to the type engine implementation in Slice 2.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-03 | Done | All acceptance criteria met. spago build/test green. 5/5 stub tests pass. CI workflow created. |
