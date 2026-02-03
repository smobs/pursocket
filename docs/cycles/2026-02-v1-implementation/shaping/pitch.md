---
name: "PurSocket v1 Implementation"
status: ready
drafter: "@architect"
contributors: ["@architect", "@product-manager", "@user"]
open_questions: 0
created: "2026-02-03"
appetite: "6 weeks"
---

# Pitch: PurSocket v1 Implementation

## Problem

PureScript developers working with Socket.io today have no compile-time safety net. Event names are raw strings, payloads are untyped, and the contract between client and server lives only in documentation (if it exists at all). When the server renames an event or changes a payload shape, the client discovers this at runtime -- often in production. This is the "String-Oriented Programming" trap, and it is especially painful in PureScript where developers choose the language *because* they expect the compiler to catch these categories of errors.

There is no existing PureScript library that wraps Socket.io with type-level protocol enforcement. The closest analogs in other ecosystems (e.g., `tRPC` for TypeScript) demonstrate massive developer demand for this pattern, but nothing equivalent exists for PureScript's more powerful type system.

PurSocket v1 fills this gap: a library where a single `AppProtocol` row type is the source of truth for every room, direction, and event, enforced at compile time with zero runtime overhead.

> **Q (@architect -> @product-manager):** Is there an existing PureScript Socket.io wrapper (even an untyped one) on Pursuit or the package sets that we should be aware of -- either to avoid namespace collisions or to study prior art in FFI approach?
>
> **A (@product-manager):** I investigated this thoroughly. There is **no maintained PureScript Socket.io wrapper** on Pursuit or in the current PureScript package sets. The closest prior art falls into two categories:
>
> 1. **Abandoned/experimental Socket.io wrappers.** There is a `purescript-socket.io` repository (nicksenger on GitHub) that attempted a thin, untyped FFI wrapper around Socket.io. It has not been updated for modern PureScript (pre-0.15 era), is not published to the PureScript Registry, and is not in the package sets. Its FFI approach was straightforward -- `foreign import` wrapping `io()`, `socket.emit()`, and `socket.on()` directly -- which validates that our planned thin-FFI strategy (`primEmit`, `primCall`, `primBroadcast`) is the right pattern. There is no namespace collision risk since it was never registered.
>
> 2. **WebSocket libraries (not Socket.io).** `purescript-web-socket` (wrapping the browser WebSocket API) and `purescript-websocket-simple` exist on Pursuit. These are lower-level than Socket.io and do not handle rooms, namespaces, reconnection, or acknowledgements. They are not competitive with PurSocket since Socket.io provides significant application-level semantics on top of raw WebSockets.
>
> **Conclusion:** The name `pursocket` is clear of collisions. We should adopt the same thin-FFI pattern (1-3 line JS functions per foreign import) that prior attempts used, since it keeps the JS layer trivially auditable. The absence of any typed wrapper -- even an untyped one in the package sets -- confirms the gap the pitch identifies.
>
> ✓ RESOLVED

> **Q (@product-manager -> @architect):** Given that `purescript-web-socket` exists on Pursuit, should PurSocket's module namespace use `Socket.IO.*` (e.g., `Socket.IO.Client`, `Socket.IO.Framework`) rather than bare `Socket.*` to clearly differentiate from raw WebSocket libraries and avoid future confusion?
>
> **A (@architect):** Use `PurSocket.*` as the module namespace -- not `Socket.IO.*` and not bare `Socket.*`. Here is the reasoning:
>
> **`Socket.IO.*` is wrong because it claims to be Socket.io.** A module path like `Socket.IO.Client` implies this library *is* Socket.io, just in PureScript. But PurSocket is not a thin wrapper or a port -- it is an opinionated, type-level protocol enforcement layer that *uses* Socket.io as its transport. Naming the modules `Socket.IO.*` would set incorrect expectations: developers would look for 1:1 API parity with the JavaScript `socket.io-client` library and be confused when they find `AppProtocol`, `NamespaceHandle`, and `IsValidMsg` instead of raw `io()` and `socket.on()`. The module namespace should reflect what this library *is*, not what it wraps.
>
> **Bare `Socket.*` is wrong because it is too generic.** `Socket.Client` or `Socket.Framework` could be anything -- TCP sockets, Unix domain sockets, WebSockets, or Socket.io. It provides no signal about what kind of socket or what level of abstraction the library operates at. It would also create conceptual (if not literal) confusion with `purescript-web-socket`, which occupies the "socket" mental namespace on Pursuit.
>
> **`PurSocket.*` is right because it is the library's own identity.** The package is called `pursocket`. The module namespace `PurSocket.*` is self-consistent, immediately recognizable, and creates no ambiguity with any existing or future library. It follows the established PureScript convention where libraries use their own name as the module root (`Halogen.*`, `Aff.*`, `Codec.*`). The concrete module tree becomes:
>
> - `PurSocket.Protocol` -- `Msg`, `Call` data kinds, user-facing protocol definition utilities
> - `PurSocket.Client` -- `connect`, `join`, `emit`, `call`
> - `PurSocket.Server` -- `broadcast`, `onEvent`, server setup
> - `PurSocket.Framework` -- `IsValidMsg`, `IsValidCall`, `NamespaceHandle`
> - `PurSocket.Example.Protocol` -- the example `AppProtocol`
>
> This also means the BRIEF.md spec's use of `Socket.Framework` and `Shared.Protocol` should be treated as *conceptual* module names, not literal ones. During implementation, we map `Shared.Protocol` to `PurSocket.Protocol` and `Socket.Framework` to `PurSocket.Framework`.
>
> **Decision:** Module namespace is `PurSocket.*`. The spec's module names are conceptual; the implementation uses `PurSocket.*` throughout.
>
> ✓ RESOLVED

## Appetite

**Time budget:** 6 weeks (big batch)

Six weeks is enough to deliver a working, published library with the core type-level engine, client and server APIs, FFI bindings, a test suite, and CI -- but only if we are disciplined about scope. The infrastructure-first approach means weeks 1-2 are devoted entirely to project scaffolding (spago config, npm setup, module skeleton, CI pipeline, test harness). Weeks 3-4 build the type-level engine and FFI. Weeks 5-6 handle the API surface, integration tests against a real Socket.io server, documentation, and package registry submission.

**What gets cut if things take longer:** In priority order, we sacrifice: (1) the `Call`/acknowledgement pattern (ship `Msg`-only, add `Call` later), (2) registry publishing (release as a git dependency first), (3) custom `Prim.TypeError` error messages (defer to v1.1). The non-negotiable core is: shared protocol type, `IsValidMsg` constraint, client-side `emit`, server-side `broadcast`, browser bundling, and a working demo with browser client and Node server communicating end-to-end.

> **Q (@architect -> @user):** If we hit week 4 and the server-side `broadcast` API is proving harder than expected (e.g., Socket.io server's room/namespace semantics are more complex than the spec assumes), are you comfortable shipping a client-only v1 and deferring server to a fast-follow?
>
> **A (@user):** No. Both client and server must ship in v1. If server-side proves difficult, cut scope elsewhere (e.g., defer `Call`/acknowledgements, simplify test coverage, defer registry publishing) -- but both sides of the protocol are non-negotiable.
>
> ✓ RESOLVED

## Solution Sketch

The implementation follows a layered architecture matching the BRIEF.md spec, built infrastructure-first:

**Layer 0 -- Project Skeleton (Week 1-2):**
Set up a monorepo-style spago workspace with three packages: `pursocket-shared` (protocol types, `Msg`/`Call` data kinds), `pursocket-client` (client API + FFI to `socket.io-client`), and `pursocket-server` (server API + FFI to `socket.io`). A fourth `pursocket-test` package contains integration tests. npm dependencies are managed at the workspace root. CI runs on GitHub Actions: build, test, and (eventually) publish.

**Layer 1 -- Shared Protocol & Type Engine (Week 3):**
Implement `Shared.Protocol` as a module exporting `Msg`, `Call`, and a sample `AppProtocol`. Then build `Socket.Framework` with the `IsValidMsg` and `IsValidCall` type classes using `Row.Cons` constraint chains. This layer has zero FFI -- it is pure type-level PureScript. We validate it compiles and that deliberately wrong code fails to compile (negative compile-time tests).

**Layer 2 -- FFI Bindings (Week 3-4):**
Write `.js` FFI files for `primEmit`, `primCall`, `primBroadcast`, and connection/room-join primitives. The FFI is intentionally thin: each function is a 1-3 line JavaScript wrapper around the Socket.io API. The PureScript side wraps these in `Effect` or `Aff` and threads `RoomHandle` through them.

**Layer 3 -- Public API & Integration Tests (Week 5-6):**
Wire up `emit`, `call`, `broadcast`, `connect`, and `join` as the user-facing API. Write integration tests that spin up a real Socket.io server in Node, connect a PureScript client, and verify message round-trips. Publish to the PureScript registry or document git-dependency installation.

### Key Elements

- **Single `AppProtocol` row type** as the shared contract between client and server -- the "single source of truth" principle from the spec.
- **`RoomHandle (room :: Symbol)` phantom type** providing capability-based room access -- you cannot emit into a room you have not joined.
- **`IsValidMsg` / `IsValidCall` type classes** using `Row.Cons` constraint chains to validate room, direction, and event at compile time.
- **Thin FFI layer** (`primEmit`, `primCall`, `primBroadcast`) that compiles away to bare Socket.io calls -- the "zero runtime overhead" guarantee.
- **Spago workspace** with separate packages for shared/client/server to enforce that client code cannot import server internals (and vice versa).

### Simplest Version

The absolute minimum that proves the architecture works end-to-end: a single-package library (no workspace split) containing the `AppProtocol` type, `IsValidMsg` constraint, a `connect` function, a `RoomHandle`-returning `join`, and `emit` -- client-side fire-and-forget only, no `Call`, no server API. One FFI file wrapping `socket.io-client`'s `emit`. One integration test proving a message reaches a Node.js Socket.io server. If we are behind schedule, this is what ships as v1.0.0.

> **Q (@architect -> @architect):** Should the simplest version skip `RoomHandle` entirely and just validate events against the flat protocol row (no room scoping)? That removes the `join` step but also removes the capability pattern which is a key selling point.
>
> **A (@architect):** No -- keep `RoomHandle` even in the simplest version. Here is the reasoning:
>
> The `RoomHandle` is not incidental complexity; it is *the* distinguishing feature of PurSocket compared to a naive typed-emit wrapper. Without it, we are shipping "typed event names" which is useful but not compelling enough to justify a new library -- a developer could achieve the same with a handful of helper functions and a record type. The `RoomHandle` as a capability token is what makes the "you cannot emit into a room you haven't joined" guarantee possible, and that is the guarantee that makes PurSocket feel like a real safety net rather than a convenience.
>
> Practically, `RoomHandle` is also cheap to implement. It is a newtype over `Socket` with a phantom `Symbol` parameter -- roughly 5 lines of PureScript. The `join` function that produces it is a single FFI call (either `socket.nsp` for namespaces or `socket.join` for rooms). The cost is not in `RoomHandle` itself but in the three-level `Row.Cons` chain, which we need regardless of whether `RoomHandle` exists.
>
> The simplest version should be: `connect` returns a `Socket`, `join @"lobby" socket` returns `RoomHandle "lobby"`, `emit @"chat" handle { text: "Hello" }` validates against the protocol. This is only marginally more code than a flat version and it preserves the capability pattern that the BRIEF.md spec explicitly calls out as a guiding principle ("Contextual Safety -- The Handle Pattern").
>
> What *can* be cut from the simplest version is the *multi-room* scenario in tests. Ship with one room in the example protocol and one integration test. Multi-room testing is a week 5-6 activity.
>
> **Decision:** Keep `RoomHandle`. Cut multi-room test coverage if time is short, not the handle itself.
>
> ✓ RESOLVED

> **Q (@architect -> @architect):** Single spago package vs. workspace split (shared/client/server) -- should we start monolithic and split later, or set up the workspace from day one?
>
> **A (@architect):** Start with a single package and split into a workspace at the boundary between week 2 and week 3. Here is the reasoning:
>
> **The workspace split is correct architecture but premature on day one.** Spago workspaces (`workspace:` key in root `spago.yaml` with per-package `spago.yaml` files) enforce that `pursocket-client` cannot import `pursocket-server` internals and vice versa. This is a real correctness property we want. However, setting up a workspace before we have any code means debugging tooling issues (IDE resolution, test runner configuration, cross-package dependency declarations) in a vacuum. If `purescript-language-server` misresolves imports or `spago test` does not pick up the right package, we will burn time on infrastructure with no application logic to validate against.
>
> **The risk of starting monolithic is low.** The module structure can mirror the eventual package split from day one: `PurSocket.Shared.Protocol`, `PurSocket.Client.Emit`, `PurSocket.Server.Broadcast`, etc. When we split into a workspace, we move directories and create per-package `spago.yaml` files -- no renaming, no refactoring of imports beyond adjusting the package boundary. PureScript's module system does not care about package boundaries; only spago does.
>
> **The trigger for splitting:** At the end of week 2, when the project skeleton and CI are working, attempt the workspace split. If it works in under 2 hours, keep it. If it causes tooling problems, defer to v1.1 and ship as a single package. A single-package v1 is not a failure -- it just means client and server module isolation is by convention rather than by build system enforcement.
>
> **Registry implications:** A single package registers as `pursocket`. A workspace registers as up to three packages (`pursocket-shared`, `pursocket-client`, `pursocket-server`). The single-package approach is simpler for v1 registry submission and for users (`spago install pursocket` vs. `spago install pursocket-client pursocket-shared`). We can split the registry packages in v2 when there is a real user demand for depending on only the client or only the server.
>
> **Decision:** Start monolithic with workspace-ready module naming. Attempt the workspace split at the week 2/3 boundary. If it costs more than 2 hours, defer. Ship as a single `pursocket` package for v1.
>
> ✓ RESOLVED

## Research Findings

### Technical Landscape

- **spago@next (0.93+):** Uses `spago.yaml` configuration. Supports workspaces with multiple packages via a top-level `workspace` key and per-package `spago.yaml` files. This is the right tool for a multi-package library. The `spago publish` command targets the PureScript Registry (not Bower).

- **PureScript Registry:** The modern registry (`github.com/purescript/registry`) accepts packages via GitHub releases and a `purs.json` manifest. We need to decide whether to register as one package (`pursocket`) or multiple (`pursocket-shared`, `pursocket-client`, `pursocket-server`). Multiple packages impose more registry overhead but enforce cleaner dependency boundaries.

- **Socket.io JavaScript API surface:** `socket.io-client` exposes `io(url)` for connection, `socket.emit(event, data)` for fire-and-forget, and `socket.emit(event, data, callback)` for acknowledgements. The server's `socket.io` exposes `io.to(room).emit(event, data)` for broadcasting. The acknowledgement callback pattern maps naturally to PureScript's `Aff` via `makeAff`.

- **Row.Cons constraint pattern:** This is well-established in PureScript (used by `purescript-record`, `purescript-variant`, etc.). The three-deep nested `Row.Cons` chain in the spec (room -> direction -> event) is more deeply nested than typical usage, which may produce verbose compiler error messages when a constraint fails. Custom type errors via `Prim.TypeError` can improve this.

- **Testing frameworks:** `purescript-spec` is the most common testing library. For integration tests involving a real Socket.io server, we need a way to start/stop a Node process -- likely via `purescript-node-child-process` or a shell script orchestrator. `purescript-aff` provides the async plumbing for waiting on socket events in tests.

- **Prior art in other languages:** TypeScript's `tRPC` and `ts-rest` demonstrate that typed protocol layers drive adoption. Haskell's `servant` shows that type-level API specifications can work at scale. The PurSocket approach is closer to `servant`'s philosophy (the type IS the spec) than `tRPC`'s (code-generation from runtime schemas).

> **Q (@architect -> @architect):** The three-level `Row.Cons` chain (room -> dir -> event) will produce opaque error messages when a developer misspells an event name. Should we invest time in `Prim.TypeError` custom errors in v1, or defer that to v1.1? Custom errors could easily consume 2-3 days.
>
> **A (@architect):** Invest in a *minimal* custom error layer in v1, but scope it strictly to avoid the rabbit hole. Here is the plan:
>
> **The problem is real and user-facing.** When a developer writes `emit @"lobby" @"caht" handle payload` (misspelling "chat"), the PureScript compiler will report something like: `No type class instance was found for IsValidMsg "lobby" "caht" "c2s" { text :: String }`. That is already *decent* -- the developer can see the room, event name, direction, and payload. But the underlying `Row.Cons` failure will also produce a secondary error like `Could not match type ... with ...` referencing the internal row decomposition, which is confusing noise.
>
> **The fix is lightweight.** PureScript's `Prim.TypeError` module provides `Fail` (a constraint that always fails with a custom message) and combinators `Text`, `Quote`, `Beside`, and `Above` for composing error messages. The standard pattern is to add a *fallback instance* using `Prim.TypeError.Fail` that triggers when the normal `Row.Cons` chain does not match. For our three-level chain, we need at most three fallback instances:
>
> 1. Room not found: `Fail (Text "PurSocket: room '" <> Text room <> Text "' does not exist in the protocol.")`
> 2. Direction not found: `Fail (Text "PurSocket: direction '" <> Text dir <> Text "' is not valid for room '" <> Text room <> Text "'. Use \"c2s\" or \"s2c\".")`
> 3. Event not found: `Fail (Text "PurSocket: event '" <> Text event <> Text "' does not exist in room '" <> Text room <> Text "' for direction '" <> Text dir <> Text "'.")`
>
> **However**, PureScript's instance resolution with overlapping fallback instances requires care. The compiler uses instance chains (introduced via `else` syntax) to try the primary instance first and fall through to the `Fail` instance. This is well-supported in modern PureScript (0.15+) but means we need to restructure `IsValidMsg` from a single instance to an instance chain. The actual implementation work is roughly 1 day, not 2-3, because the pattern is well-established in libraries like `purescript-record` and `purescript-variant`.
>
> **Decision:** Implement custom type errors for `IsValidMsg` in v1 using instance chains with `Prim.TypeError.Fail`. Budget 1 day. Defer `IsValidCall` custom errors to v1.1 (they follow the same pattern and can be done mechanically once `IsValidMsg` is proven). Do *not* attempt to report "did you mean X?" suggestions -- that requires `RowToList` iteration and is genuinely a 2-3 day rabbit hole.
>
> ✓ RESOLVED
>
> **Q (@architect -> @user):** The custom type error implementation requires PureScript 0.15+ instance chains (`else` keyword in instance declarations). Can we confirm the minimum PureScript compiler version we are targeting? If anyone needs 0.14 compatibility, the custom error approach changes significantly.
>
> **A (@user):** Target the latest (2026) version of PureScript. No backward compatibility with older versions needed. All modern features including instance chains are available.
>
> ✓ RESOLVED

> **Q (@architect -> @product-manager):** For the "getting started" story, should the library ship a default/example `AppProtocol` in the library itself, or should documentation guide users to define their own from scratch? A bundled example lowers the barrier but might confuse users into thinking it is required.
>
> **A (@product-manager):** **Ship an example protocol, but put it in the right place.** The answer is neither "bundle it in the library core" nor "only document it" -- it is a third option that gives us the benefits of both.
>
> **Recommendation: Place the example `AppProtocol` in a dedicated `PurSocket.Example.Protocol` module that is part of the published package but clearly namespaced as an example.** Here is why:
>
> From a developer experience standpoint, the single hardest moment in adopting a type-level library is the first 5 minutes. The developer needs to answer: "What do I actually write?" If the only guidance is prose documentation saying "define a row type with this shape," many developers will bounce -- especially PureScript newcomers who may not be fluent in row types yet. A concrete, importable, compilable example protocol eliminates that cold-start problem. They can `import PurSocket.Example.Protocol (AppProtocol)`, get a working `emit` in under 2 minutes, and *then* replace it with their own protocol once they understand the shape.
>
> The confusion risk ("is this required?") is real but manageable through naming and documentation:
> - Name the module `PurSocket.Example.Protocol`, not `PurSocket.Protocol` or `PurSocket.Default.Protocol`. The word "Example" in the module path is self-documenting.
> - The quick-start section of the README should use the example protocol for the first snippet, then immediately show "Now define your own" as step 2.
> - The module's doc comment should say: "This module exists for demonstration purposes. Real applications should define their own protocol in their own codebase."
>
> This pattern is well-established in typed library ecosystems. Haskell's `servant` ships example APIs in its tutorial package. Elm's `Browser.sandbox` ships with a counter example. TypeScript's `tRPC` documentation leads with a working example router before explaining customization. The pattern works because developers learn by modifying working code, not by constructing from scratch.
>
> **What the example protocol should contain:** The lobby/game protocol from the BRIEF.md spec is perfect -- it demonstrates `Msg` (fire-and-forget), `Call` (request/response), `c2s`/`s2c` directionality, and multi-room scoping. It is small enough to read in 30 seconds but rich enough to show every feature.
>
> ✓ RESOLVED

> **Q (@product-manager -> @architect):** Should the `PurSocket.Example.Protocol` module also ship a tiny working `main` (example client) that imports the example protocol and does one `connect` / `join` / `emit` -- effectively a copy-pasteable "hello world"? Or does that belong only in the README / a separate examples repo?
>
> **A (@architect):** No -- do not put a `main` in `PurSocket.Example.Protocol`. The example protocol module and the working demo serve different purposes and should stay separate. Here is the reasoning:
>
> **The demo already exists as a requirement.** Definition of Done item 7 mandates a working demo with a browser client and Node server communicating end-to-end. That demo will necessarily contain a `main` function that calls `connect`, `join`, and `emit`. It is the canonical "hello world." Adding a second `main` inside the library's own module tree creates redundancy and a maintenance burden -- two places to keep in sync when the API changes.
>
> **`PurSocket.Example.Protocol` has a specific, narrow job.** Its purpose (established in the prior resolved question) is to provide a concrete, importable `AppProtocol` value so that new developers can get a compiling `emit` in under 2 minutes. It answers the question "what does the *type* look like?" A `main` function answers a different question: "what does the *program* look like?" Mixing both in one module dilutes the module's purpose and makes it harder to scan.
>
> **A `main` in a library module is an anti-pattern in PureScript.** Library modules should export types and functions, not executable entry points. If `PurSocket.Example.Protocol` exports a `main :: Effect Unit`, it will show up in generated documentation as a public API, confusing users who expect library modules to be building blocks, not runnable programs. It also means the module needs runtime dependencies (a Socket.io server URL, DOM access for browser clients) that do not belong in a library package.
>
> **Where the "hello world" lives instead:** The working demo required by DoD item 7 should be structured as a self-contained directory in the repository (e.g., `examples/hello-world/`) with its own `Main.purs` for the client and `Main.purs` for the server. The README quick-start section should inline the key lines from this demo. This gives developers three on-ramps at increasing levels of detail:
>
> 1. **README snippet** -- 10 lines, read in 30 seconds, not runnable on its own.
> 2. **`PurSocket.Example.Protocol`** -- importable, compilable protocol type to experiment with.
> 3. **`examples/hello-world/`** -- fully runnable client+server demo, clone-and-run.
>
> **Decision:** `PurSocket.Example.Protocol` exports only the example `AppProtocol` type and supporting data types. No `main`, no executable code. The working demo lives in `examples/` as a separate, runnable application.
>
> ✓ RESOLVED

## Rabbit Holes

Watch out for:

- **Socket.io namespaces vs. our "rooms" abstraction.** Socket.io has both "namespaces" (`/chat`, `/game`) and "rooms" (arbitrary groupings within a namespace). The BRIEF.md spec calls its top-level grouping "rooms" but the semantics are closer to Socket.io namespaces. We need to decide early which Socket.io primitive maps to our `AppProtocol` top-level keys. Getting this wrong means rewriting the FFI layer. Recommendation: map protocol "rooms" to Socket.io namespaces, not rooms, since namespaces have independent connection semantics and event isolation.

- **`Call` / acknowledgement FFI complexity.** Socket.io acknowledgements use a callback pattern (`socket.emit("event", data, (response) => {...})`). Wrapping this in `Aff` via `makeAff` is straightforward in the happy path, but we need to handle: (a) timeouts (Socket.io v4.4+ has a `timeout()` modifier), (b) disconnection during a pending call, (c) the server never calling the callback. Each edge case is a potential rabbit hole. Recommendation: implement a simple `makeAff` wrapper with a configurable timeout and no retry logic in v1.

- **Spago workspace ergonomics.** Spago workspaces are relatively new. If we hit issues with cross-package dependencies, test runner configuration, or IDE support (purescript-language-server resolving the wrong package), we could burn days debugging tooling. Recommendation: start with a single package and only split into a workspace if the build works cleanly in the first two days.

- **`IsValidCall` instance in the BRIEF.md has a bug.** The spec's `IsValidCall` instance constrains `payload` and `res` in the fundep (`room event dir -> payload res`) but the instance head only mentions `payload res` while the `Row.Cons` for the event extracts `(Call payload res)` -- the instance binds `payload` from the constraint but the functional dependency lists both. This needs careful verification when implementing, as a subtle mismatch here will cause confusing type inference failures.

- **Module re-exports and package boundaries.** If `pursocket-client` re-exports types from `pursocket-shared`, users need to depend on both packages. This is a common friction point in PureScript library design. We may need a `pursocket` umbrella package that re-exports everything.

> **Q (@architect -> @architect):** The BRIEF.md maps protocol "rooms" to what concept in Socket.io -- namespaces or rooms? The FFI implementation is fundamentally different depending on this choice. Need to prototype both and decide before writing the type engine.
>
> **A (@architect):** Map protocol "rooms" to **Socket.io namespaces**, not Socket.io rooms. This is a firm architectural decision based on the following analysis:
>
> **Socket.io namespaces** (`io.of("/lobby")`, `io.of("/game")`) provide:
> - Independent connection semantics: each namespace is essentially a separate socket connection multiplexed over one transport. A client connects to `/lobby` and `/game` independently.
> - Independent event handlers: `lobbyNsp.on("chat", ...)` is completely isolated from `gameNsp.on("chat", ...)`. Event name collisions across namespaces are impossible.
> - Independent middleware: authentication can differ per namespace.
> - The client-side API returns a *separate socket object per namespace* (`io("/lobby")` returns a different socket than `io("/game")`), which maps perfectly to our `RoomHandle` phantom type -- each `RoomHandle "lobby"` wraps a distinct socket object.
>
> **Socket.io rooms** (`socket.join("lobby")`) provide:
> - Server-side grouping for targeted broadcasting (`io.to("lobby").emit(...)`).
> - No client-side API -- rooms are a server-only concept. The client cannot "join" a room directly; the server calls `socket.join(room)` on behalf of the client.
> - No event isolation -- all rooms within a namespace share the same event handler space.
> - No independent connection -- all rooms exist within a single socket connection to a namespace.
>
> **Why namespaces win for PurSocket:**
>
> 1. **Client-side `join` maps to namespace connection.** The BRIEF.md spec shows `lobby <- join @"lobby" socket` on the client side. Socket.io rooms have no client-side join API, so we would need a custom protocol on top (client sends a "please join me" event, server calls `socket.join`). Namespaces give us this for free: `join` is simply `io("/lobby")`.
>
> 2. **`RoomHandle` as a distinct socket object.** Each namespace connection returns a separate `Socket` instance in Socket.io. Our `RoomHandle "lobby"` wraps exactly this -- a socket connected to the `/lobby` namespace. This is a clean 1:1 mapping with no impedance mismatch.
>
> 3. **Event isolation matches protocol isolation.** The `AppProtocol` row defines events per-room. Namespaces naturally isolate events per-namespace. Rooms do not -- they share the event space of their parent namespace. Using rooms would require us to prefix event names (e.g., `"lobby:chat"`) or maintain manual routing tables, adding runtime overhead that violates our "zero runtime overhead" principle.
>
> 4. **Server-side broadcasting works.** `io.of("/game").emit("gameOver", data)` broadcasts to all clients connected to the `/game` namespace. This maps directly to `broadcast @"game" socket { winner: "Alice" }`.
>
> **FFI implications:**
> - `connect url` = `io(url)` -- connects to the default namespace.
> - `join @"lobby" socket` = `io(url + "/lobby")` or `socket.io.of("/lobby")` -- connects to a specific namespace. Returns a new `Socket` instance wrapped in `RoomHandle "lobby"`.
> - `emit @"chat" handle payload` = `socket.emit("chat", payload)` -- emits on the namespace-specific socket.
> - `broadcast @"game" serverSocket payload` = `io.of("/game").emit("gameOver", payload)` -- broadcasts on a namespace.
>
> **Naming concern:** We call them "rooms" in the protocol but they map to Socket.io "namespaces." This terminology mismatch could confuse developers familiar with Socket.io. We should consider either: (a) renaming our concept to "namespace" in the protocol (breaking change to the spec), or (b) documenting clearly that "PurSocket rooms = Socket.io namespaces" and accepting the terminology gap.
>
> **Decision:** Protocol rooms = Socket.io namespaces. No prototyping of the rooms-based approach is needed -- the mismatch with client-side semantics rules it out. The FFI layer targets the namespace API exclusively.
>
> ✓ RESOLVED
>
> **Q (@architect -> @user):** The spec uses the term "rooms" but we are mapping to Socket.io namespaces. Should we rename the protocol concept from "rooms" to "namespaces" in the `AppProtocol` type and throughout the spec to avoid confusion for developers who know Socket.io? Or keep "rooms" as a PurSocket-specific abstraction and document the mapping?
>
> **A (@user):** Use Socket.io's language. Rename to "namespaces" throughout the protocol, spec, API, and type names (e.g., `NamespaceHandle` instead of `RoomHandle`). Update BRIEF.md accordingly. Developers familiar with Socket.io should see familiar terminology.
>
> ✓ RESOLVED

> **Q (@architect -> @user):** The `IsValidCall` instance in the spec appears to have the functional dependency and constraint slightly misaligned. Should I treat the spec as aspirational (fix issues as I find them) or do you want to review and amend the spec before implementation begins?
>
> **A (@user):** Review and amend the spec first. Fix the `IsValidCall` issue in BRIEF.md before implementation begins so the spec remains the authoritative reference.
>
> ✓ RESOLVED

## No-Gos

Explicitly out of scope for v1:

- **Code generation / template haskell style metaprogramming.** The protocol is hand-written PureScript types. No codegen from JSON Schema, OpenAPI, or similar.
- **Transport-layer configuration.** No exposing Socket.io's transport options (polling vs. websocket, reconnection strategies, etc.) through the type system. Users who need this can access the raw socket via an escape hatch.
- **Multi-protocol support.** v1 supports exactly one `AppProtocol` type per application. Supporting multiple independent protocols or protocol composition (merging two protocols) is deferred.
- **Binary/non-JSON payloads.** All payloads are JSON-serializable PureScript records. Binary (ArrayBuffer, Blob) support is out of scope.
- **Middleware or plugin system.** No typed middleware chain for logging, authentication, or rate limiting. These are application concerns, not library concerns for v1.
- **Backward compatibility with raw Socket.io.** We do not provide an "untyped escape hatch" that lets you emit arbitrary strings. The entire point is that you cannot bypass the protocol. (An internal `unsafeEmit` may exist for testing but will not be exported.)
- **Browser bundling optimization.** v1 must work in the browser (esbuild bundling tested in CI), but advanced bundler configuration (tree-shaking, code splitting, multiple bundler support) is out of scope. We test with esbuild only.

> **Q (@architect -> @product-manager):** The no-go on "no untyped escape hatch" is philosophically pure but practically aggressive. Should we provide a clearly-marked `Unsafe.emit` module for developers migrating incrementally from untyped Socket.io? Or does that undermine the value proposition?
>
> **A (@product-manager):** Yes, ship an `Unsafe` module designed to feel uncomfortable. *(See full rationale in revision history.)*
>
> **OVERRIDDEN by @user:** No escape hatch. Do not add a `PurSocket.Unsafe` module. The entire point of PurSocket is that you cannot bypass the protocol. If developers need untyped Socket.io, they can use Socket.io directly -- PurSocket is not a gradual migration tool, it is a correctness tool. The no-go stands as written.
>
> ✓ RESOLVED (overridden)

> **Q (@architect -> @user):** Is browser-side usage a v1 requirement? If real users need PurSocket in the browser (not just Node), we need to add esbuild/bundler testing to CI, which affects the 6-week scope.
>
> **A (@user):** Yes, browser usage is mandatory for v1. The client side must work in the browser. Add esbuild/bundler testing to CI.
>
> ✓ RESOLVED

## Definition of Done

"Shipped" means:

1. **Published and installable.** The library is either on the PureScript Registry (`spago install pursocket`) or installable as a git dependency with documented instructions. npm peer dependencies (`socket.io-client`, optionally `socket.io`) are documented in README.
2. **Core API works end-to-end.** A developer can: define a custom `AppProtocol`, `connect` to a Socket.io server, `join` a room (receiving a `RoomHandle`), `emit` a fire-and-forget message, and `call` with an acknowledgement response -- all with compile-time validation against their protocol.
3. **Compile-time safety is proven.** The test suite includes "negative" tests (code that *must not* compile) demonstrating that wrong event names, wrong rooms, wrong directions, and wrong payload types are caught by the compiler.
4. **CI is green and automated.** GitHub Actions builds the library, runs unit tests, runs integration tests against a real Socket.io server, and (on tag) publishes to the registry.
5. **Documentation exists.** A README with: installation, quick-start (define protocol, connect, emit), API reference for all public functions, and one complete client+server example.
6. **Server-side API works.** `broadcast` and server-side `onEvent` handler registration work with the same protocol type, proving the "shared contract" story. Both client and server are required for v1.
7. **Working demo ships with the library.** A small but complete demo application with a PureScript browser client and a PureScript/Node server communicating via PurSocket over Socket.io, demonstrating the type-safe protocol end-to-end in a real browser+server setup.

---

## Open Questions

| Section | Question | Asker | Assignee | Status |
|---------|----------|-------|----------|--------|
| Problem | Is there an existing PureScript Socket.io wrapper on Pursuit or the package sets that we should study or avoid colliding with? | @architect | @product-manager | ✓ RESOLVED |
| Problem | Should PurSocket's module namespace use `Socket.IO.*` rather than bare `Socket.*` to differentiate from raw WebSocket libraries? | @product-manager | @architect | ✓ RESOLVED |
| Appetite | If server-side `broadcast` proves harder than expected, are you comfortable shipping a client-only v1? | @architect | @user | ✓ RESOLVED |
| Solution Sketch | Should the simplest version skip `RoomHandle` and validate events against a flat protocol row (no room scoping)? | @architect | @architect | ✓ RESOLVED |
| Research | Should we invest in `Prim.TypeError` custom error messages in v1, or defer to v1.1? | @architect | @architect | ✓ RESOLVED |
| Research | Should the library ship a bundled example `AppProtocol` or guide users to define their own from scratch? | @architect | @product-manager | ✓ RESOLVED |
| Research | Should `PurSocket.Example.Protocol` also ship a tiny working `main` as a copy-pasteable hello world? | @product-manager | @architect | ✓ RESOLVED |
| Rabbit Holes | Do protocol "rooms" map to Socket.io namespaces or Socket.io rooms? Need to prototype before building the type engine. | @architect | @architect | ✓ RESOLVED |
| Rabbit Holes | The `IsValidCall` instance in the spec has a potential fundep issue. Should I fix as I go or does the spec need a formal amendment first? | @architect | @user | ✓ RESOLVED |
| No-Gos | Should we provide a clearly-marked `Unsafe.emit` module for incremental migration, or does that undermine the value proposition? | @architect | @product-manager | ✓ RESOLVED |
| No-Gos | Escape hatch question moot -- @user overrode: no `PurSocket.Unsafe` module. | @product-manager | @architect | ✓ RESOLVED |
| No-Gos | Is browser-side usage a v1 requirement? If yes, esbuild/bundler testing needs to enter the CI scope. | @architect | @user | ✓ RESOLVED |
| Solution Sketch | Single spago package vs. workspace split (shared/client/server) -- should we start monolithic and split later, or set up the workspace from day one? | @architect | @architect | ✓ RESOLVED |
| Research | Custom type errors require PureScript 0.15+ instance chains. What is our minimum compiler version? | @architect | @user | ✓ RESOLVED |
| Rabbit Holes | Should we rename "rooms" to "namespaces" in the protocol to match Socket.io terminology, or keep "rooms" as a PurSocket abstraction? | @architect | @user | ✓ RESOLVED |

---

*Drafted by @architect on 2026-02-03*
