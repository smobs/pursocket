# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PurSocket is a type-safe Socket.io protocol specification and library for PureScript. It uses PureScript's type system to enforce protocol contracts at compile time, eliminating runtime errors from mismatched event names or payloads between client and server.

**Current state:** Bet placed, entering build phase. Design is in `BRIEF.md`, shaped pitch and bet decision in `docs/current/shaping/`.

## Architecture

The design has four layers, using `PurSocket.*` module namespace:

1. **Shared Protocol (`PurSocket.Protocol`)** — A single `AppProtocol` row type that defines all namespaces (Socket.io namespaces, not rooms), message directions (`c2s`/`s2c`), and event types. This is the single source of truth for the entire system.

2. **Type-Level Engine (`PurSocket.Framework`)** — Type classes `IsValidMsg` and `IsValidCall` that use `Row.Cons` constraints to validate at compile time that an event exists in the correct namespace and direction. `NamespaceHandle (ns :: Symbol)` is a phantom-typed capability token — you can only send messages to a namespace if you hold its handle.

3. **API Layer (`PurSocket.Client`, `PurSocket.Server`)** — `emit` (fire-and-forget via `Msg`), `call` (request/response via `Call` with acknowledgements), and `broadcast` (server-to-client). These resolve type-level `Symbol` names to runtime strings via `reflectSymbol`, producing JS output identical to hand-written Socket.io code.

4. **FFI** — Foreign imports (`primEmit`, `primCall`, `primBroadcast`) bridging to the actual Socket.io JavaScript library. Protocol "namespaces" map to Socket.io namespaces (not rooms).

### Key Design Constraints

- Client code can only send `c2s` events; server code can only emit `s2c` events (enforced by type constraints, not runtime checks).
- All type-level machinery compiles away — zero runtime overhead.
- The `Call` pattern maps to Socket.io acknowledgements (request/response over a single event).
- No escape hatch — no `PurSocket.Unsafe` module. PurSocket is a correctness tool, not a gradual migration tool.
- Targets latest (2026) PureScript compiler. No backward compatibility with older versions.

## Build & Development

- **Build tool:** Spago (configured via `spago.yaml`)
- **JS dependencies:** `package.json` with `socket.io` / `socket.io-client`
- **FFI files:** `.js` files alongside `.purs` modules for `primEmit`, `primCall`, `primBroadcast`
- **Browser:** Client must work in browser, esbuild bundling tested in CI
- **Start monolithic**, attempt spago workspace split at week 2/3 boundary (2-hour timebox)

## Shape Up Workflow

This project uses Shape Up with iterative collaborative shaping:
- `/project-orchestrator:project-shape "name"` — create/iterate on a pitch (run repeatedly)
- `/project-orchestrator:project-review "name"` — check Q&A status, add reviewers
- `/project-orchestrator:project-bet "name"` — decide whether to bet on a pitch
- `/project-orchestrator:project-build` — execute the bet-on work
- `/project-orchestrator:project-ship` — validate and deliver
- `/project-orchestrator:project-cooldown` — cleanup and retrospective

Pitches live in `docs/shaping-backlog/`. Active work in `docs/current/`.
