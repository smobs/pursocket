# Delivery Notes: PurSocket v1 Implementation

**Shipped:** 2026-02-03
**Appetite:** 6 weeks
**Actual:** 1 day (all 6 slices completed same day)

## What Shipped

A type-safe Socket.io protocol library for PureScript. A single `AppProtocol` row type defines all namespaces, directions, and events. The compiler enforces the protocol at compile time with zero runtime overhead. Client can only send `c2s` events; server can only emit `s2c` events.

### Features/Capabilities
- Define a protocol as a nested row type with `Msg` (fire-and-forget) and `Call` (request/response) patterns
- `connect` to a Socket.io server, `join` a namespace (getting a phantom-typed `NamespaceHandle`)
- `emit` and `call` from client, `broadcast` and `onEvent` from server -- all compile-time validated
- Custom type errors via `Prim.TypeError.Fail` when events, namespaces, or directions are wrong
- Browser bundling via esbuild (117kb ESM bundle)
- 22 tests (18 unit + 4 integration with real Socket.io server)
- 4 negative compile tests proving type safety

### Scope Delivered
- **Slice 1 (Project Skeleton & CI):** spago.yaml, package.json, module stubs, GitHub Actions
- **Slice 2 (Protocol & Type Engine):** RowToList-based IsValidMsg/IsValidCall, custom type errors, NamespaceHandle
- **Slice 3 (Client API & FFI):** connect, join, emit, call/callWithTimeout, onMsg, disconnect
- **Slice 4 (Server API & FFI):** createServer, broadcast, onConnection, onEvent, onCallEvent, closeServer
- **Slice 5 (Integration Tests & Browser):** 4 end-to-end tests, esbuild bundle, CI pipeline
- **Slice 6 (Example, Demo & Docs):** Example protocol/client/server modules, README.md

## What Didn't Ship (Scope Cuts)

- **PureScript Registry publishing:** Installable as git dependency only. Registry submission deferred.
- **Standalone runnable demo:** No `examples/hello-world/` with separate server+browser mains. Integration tests prove end-to-end communication. Example modules show the code patterns.
- **Spago workspace split:** Ships as single package per plan. Client/server isolation by convention.

## Success Criteria

| Criterion | Met | Evidence |
|-----------|-----|----------|
| Published and installable | Partial | Git dependency works; registry deferred |
| Core API end-to-end | Yes | 22/22 tests pass including 4 integration tests |
| Compile-time safety proven | Yes | 4/4 negative compile tests fail with custom type errors |
| CI green | Yes | ci.yml with build, test, negative tests, browser bundle |
| README with docs | Yes | 260-line README.md with installation, quick-start, API reference |
| Server-side API works | Yes | broadcast and onEvent proven in integration tests |
| Working demo | Partial | Integration tests prove e2e; no standalone browser demo |

## Definition of Done

**Target:** Working library with compile-time protocol enforcement, both client and server, browser-compatible, with tests and documentation.
**Achieved:** All core functionality works. Integration tests prove end-to-end message delivery. Browser bundle verified. Two items deferred: registry publishing and standalone browser demo.

## Known Limitations

- **Single protocol per app:** v1 hardcodes one AppProtocol type per usage site (by design)
- **No escape hatch:** No PurSocket.Unsafe module (by design)
- **No Call custom type errors:** IsValidCall uses raw compiler errors on failure (IsValidMsg has custom errors)
- **No binary payloads:** JSON-serializable records only
- **No middleware/plugin system:** Application-level concerns not in scope

## Team

| Role | Contribution |
|------|-------------|
| @purescript-specialist | All 6 slices: skeleton, type engine, client/server API, tests, docs |
| @architect | Type engine design, RowToList migration, negative test fixes |
| @web-tech-expert | Socket.io namespace mapping, FFI design |
| @qa | Integration test infrastructure, test strategy |

## Retro Notes Summary

Difficulties captured during building:
- **architect:** Row-vs-record kind mismatch, Row.Cons vs RowToList for custom errors, negative test resolution pattern, fundep visible type app limitation, Prelude `join` name collision, concurrent slice file conflicts
- **web-tech-expert:** NamespaceHandle structural change, constructor visibility tradeoff
- **qa:** Integration test timing, server lifecycle management, CORS configuration

---

## Next Steps

Run `/project-orchestrator:project-cooldown` to begin the cool-down period for cleanup, retrospective, and exploration.
