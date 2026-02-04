---
name: "emitTo and Room Support"
status: bet
drafter: "@web-tech-expert"
contributors: ["@web-tech-expert", "@purescript-specialist", "@qa", "@external-user", "@product-manager", "@architect"]
open_questions: 0
created: "2026-02-04"
appetite: "6 weeks"
---

# Pitch: emitTo and Room Support

## Problem

PurSocket's server can only broadcast to every client in a namespace. It has no way to send a typed message to a single specific client, no way to broadcast to everyone except the sender, and no concept of rooms (Socket.io's primary mechanism for grouping sockets into subsets).

This blocks every non-trivial real-time application pattern:

- **Direct messaging:** Server receives a chat message and needs to relay it to one recipient. Currently impossible -- `broadcast` sends to everyone.
- **Echo prevention:** Chat server receives `sendMessage` from Alice and broadcasts `newMessage` to all. Alice sees her own message twice (once from local echo, once from the broadcast). The standard fix is `socket.broadcast.emit()` -- not available.
- **Subgroups:** Game lobby, chat room, document collaboration session. Socket.io models these as rooms. PurSocket has zero room support, so all clients in a namespace see all messages.

The chat example (`examples/chat/src/Chat/Server/Main.purs`) demonstrates the problem concretely: line 59 broadcasts `newMessage` to ALL clients including the sender because `broadcastExceptSender` does not exist. A private messaging feature is impossible with the current API.

**Who has this problem:** Any developer building a real-time app beyond a single-room broadcast demo. This is the #1 gap identified in the API surface audit (E1, SK22, R1-R5).

## Appetite

**Time budget:** 6 weeks

All three features must ship. The priorities are:

1. **emitTo** (server emit to single client) -- The biggest gap.
2. **broadcastExceptSender** -- Every chat and multiplayer app needs it.
3. **Room support** -- `joinRoom`, `leaveRoom`, `broadcastToRoom`. Scoped to the minimal viable surface: no type-level room names, no room membership queries, no bulk room operations.

**Circuit breaker:** If all three features and their tests are complete before week 6, use remaining time for documentation polish and additional integration test scenarios. Do not expand scope into No-Go items.

## Solution Sketch

### Key Elements

- **`emitTo`** -- A new server function that sends a typed s2c message to a single client via their `NamespaceHandle`. Calls `socket.emit(event, payload)` on the handle's `SocketRef` rather than `io.of(ns).emit()`. Same `IsValidMsg` constraint as `broadcast` but operates on the individual socket. This is the simplest change -- the `NamespaceHandle` already holds the right `SocketRef`, and the FFI is a one-liner.

- **`broadcastExceptSender`** -- A new server function that sends to all clients in the namespace except the one identified by the `NamespaceHandle`. Maps to Socket.io's `socket.broadcast.emit(event, payload)`. Same type signature as `emitTo` -- takes a `NamespaceHandle`, uses `IsValidMsg` for s2c validation. The FFI accesses the `.broadcast` property on the socket ref.

- **`joinRoom` / `leaveRoom` / `broadcastToRoom`** -- Minimal room API. Room names are runtime `String` values (not type-level Symbols). `joinRoom` wraps `socket.join(roomName)`. `leaveRoom` wraps `socket.leave(roomName)`. `broadcastToRoom` wraps `io.of(ns).to(roomName).emit(event, payload)` and requires the `ServerSocket` (like `broadcast` does) plus a room name string. Event type safety still applies via `IsValidMsg` -- rooms change the delivery target, not the protocol contract.

### Final API Surface

The shipped API adds five new functions to `PurSocket.Server`:

```
emitTo
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> payload
  -> Effect Unit

broadcastExceptSender
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> payload
  -> Effect Unit

joinRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit

leaveRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit

broadcastToRoom
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> String
  -> payload
  -> Effect Unit
```

Combined with the existing `broadcast`, this gives the server four delivery modes: one client, all-except-sender, everyone in namespace, and everyone in a room (except sender). This covers all standard real-time application patterns.

## Research Findings

### Technical Landscape

**Socket.io's emit model has four tiers:**
1. `socket.emit(event, data)` -- to one client (our `emitTo`)
2. `socket.broadcast.emit(event, data)` -- to all except sender (our `broadcastExceptSender`)
3. `io.of(ns).emit(event, data)` -- to all in namespace (existing `broadcast`)
4. `io.of(ns).to(room).emit(event, data)` -- to all in a room (our `broadcastToRoom`)

PurSocket currently only has tier 3. This pitch adds tiers 1, 2, and (conditionally) 4.

**Socket.io rooms are purely server-side.** Clients never know what room they are in. `socket.join()` is synchronous (no callback, no promise). Room names are strings. Every socket automatically joins a room matching its own `socket.id`. This last point is important -- `io.to(socketId).emit()` is an alternative way to send to a single client, but `socket.emit()` is simpler and avoids the adapter round-trip.

**The `.broadcast` property on a Socket.io socket** is a special BroadcastOperator, not a method. The pattern is `socket.broadcast.emit(event, data)`. In the FFI, we must access the property on the `SocketRef` and then call `.emit()` on the result. This is a subtlety -- we cannot just pass a flag to the same emit path.

**Redis adapter implications.** Socket.io rooms work transparently with the Redis adapter for multi-process/multi-server deployments. `io.of(ns).to(room).emit()` automatically routes through the adapter. `socket.emit()` (single client) does not go through the adapter -- it writes directly to the socket's underlying connection. `socket.broadcast.emit()` does go through the adapter. This means `emitTo` works in clustered deployments with no extra configuration, `broadcastExceptSender` works with the adapter, and `broadcastToRoom` works with the adapter. PurSocket does not need to do anything special for adapter compatibility.

> **Q (@web-tech-expert -> @architect):** The `emitTo` FFI is nearly identical to the client-side `primEmit` -- both call `socket.emit(event, payload)`. Should we share a single FFI function between Client.js and Server.js, or keep them separate for clarity? Sharing reduces code but creates a cross-module FFI dependency.
>
> **A (@architect):** Keep them separate. Write a dedicated `primEmitTo` in `Server.js`. Here is the reasoning:
>
> 1. **PureScript FFI locality rule.** A `foreign import` in `PurSocket.Server` must resolve from `PurSocket/Server.js` (the compiler's FFI resolution pairs `.purs` with `.js` in the same module path). To share the client's `primEmit`, `Server.purs` would need to import the PureScript binding from `PurSocket.Client`, which creates a compile-time dependency of Server on Client. That is architecturally backwards -- server code should never depend on the client module. Alternatively you could put the shared function in `PurSocket.Internal` and add an `Internal.js` FFI file, but `Internal.purs` currently has zero FFI (it is pure PureScript operating on the `NamespaceHandle` constructor), and introducing JS there just to save one trivially identical line is not a net simplification.
>
> 2. **The functions are not actually identical in trajectory.** Today both are `socket.emit(event, payload)`, but this pitch itself introduces `primBroadcastExceptSender` which will live in `Server.js` and call `socket.broadcast.emit(event, payload)`. If rooms ship, `Server.js` will also get `primJoinRoom`, `primLeaveRoom`, and `primBroadcastToRoom`. The server-side FFI file is growing its own family of socket operations that share a common pattern (receive a socket ref, do something server-specific). Keeping `primEmitTo` alongside its siblings in `Server.js` is the natural grouping. The client-side `primEmit` sits alongside `primConnect`, `primJoin`, `primCallImpl` -- a different family entirely.
>
> 3. **The cost of duplication is one line of trivial JS.** The `primEmitTo` implementation is `(socket) => (event) => (payload) => () => { socket.emit(event, payload); }` -- identical to `primEmit` in `Client.js`. That is 1 line of duplicated logic in exchange for zero cross-module coupling, clear ownership, and the ability for each file to evolve independently (e.g., if server-side emit ever needs logging, tracing, or adapter awareness). This is a case where duplication is cheaper than the wrong abstraction.
>
> 4. **Build and bundle implications.** `Client.js` imports from `socket.io-client`; `Server.js` imports from `socket.io`. These are different npm packages with different entry points. A shared FFI file would need to import neither (it would be a pure JS function with no Socket.io dependency), which is fine but means adding a third JS file (`Internal.js`) to the FFI surface for negligible benefit. The esbuild browser bundle for the client should never pull in server code; separate FFI files make that tree-shaking boundary obvious and mechanical.
>
> **Recommendation:** Add `primEmitTo` to `/home/toby/pursocket/src/PurSocket/Server.js` as a one-liner. Add `primBroadcastExceptSender` in the same commit. Keep `/home/toby/pursocket/src/PurSocket/Client.js` untouched. The two FFI files remain independent, each importing only their own Socket.io package.
>
> RESOLVED

> **Q (@web-tech-expert -> @purescript-specialist):** `broadcastToRoom` needs both the `ServerSocket` (for `io.of(ns)`) and a room name string. The current `broadcast` takes `ServerSocket`, and room-scoped functions in Socket.io chain `.to(room)` before `.emit()`. Should `broadcastToRoom` take a `ServerSocket` + `String` room name, or should we introduce a `RoomRef` type that wraps the chained `io.of(ns).to(room)` object? The former is simpler; the latter is more composable for future `.except()` support.
>
> **A (@purescript-specialist):** Take `ServerSocket + String`. Do not introduce `RoomRef`. Here is the reasoning:
>
> **1. `RoomRef` would be a lie at the type level.** A `RoomRef` implies it wraps a stable JS object, but `io.of(ns).to(room)` returns a transient `BroadcastOperator` -- it is not a persistent reference. Caching it in a PureScript value would create a stale-reference hazard if Socket.io's internals ever reconfigure the namespace adapter. The FFI should construct the chain fresh on each call: `io.of(ns).to(room).emit(event, payload)`. That is one JS expression, not a reusable object.
>
> **2. Consistency with the existing `broadcast` signature.** Looking at the current code, `broadcast` takes `ServerSocket -> payload -> Effect Unit` with the namespace resolved from the `IsSymbol ns` constraint via `reflectSymbol`. The natural extension is `broadcastToRoom` taking `ServerSocket -> String -> payload -> Effect Unit`, where the `String` is the room name and the namespace is still resolved from the type parameter. This keeps the Server module's API pattern uniform: `ServerSocket` is always the "server capability," `NamespaceHandle` is always the "per-client capability."
>
> **3. A `RoomRef` newtype adds no safety without type-level room names.** Since the pitch correctly rules out type-level room names (they are dynamic/runtime), a `RoomRef` would just be `newtype RoomRef = RoomRef String` -- a wrapper around a plain string with no phantom parameter and no type-level validation. It does not prevent passing the wrong room name. It adds API surface (a constructor or smart constructor, plus unwrapping) for zero type-safety gain. PureScript idiom says: use newtypes when you get a type distinction that prevents misuse. Here we do not.
>
> **4. Future `.except()` does not need `RoomRef`.** If a future cycle adds modifier chaining, the right PureScript pattern is a `BroadcastTarget` ADT or a record-of-options argument -- not a mutable builder object mirroring the JS API. That future design would supersede any `RoomRef` we introduce now, making it throwaway work.
>
> **Concrete signature:**
> ```
> broadcastToRoom
>   :: forall @protocol @ns @event payload
>    . IsValidMsg protocol ns event "s2c" payload
>   => IsSymbol ns
>   => IsSymbol event
>   => ServerSocket
>   -> String
>   -> payload
>   -> Effect Unit
> ```
>
> **FFI (`primBroadcastToRoom`):**
> ```js
> export const primBroadcastToRoom = (io) => (ns) => (room) => (event) => (payload) => () => {
>   io.of("/" + ns).to(room).emit(event, payload);
> };
> ```
>
> This is one new FFI function, one new PureScript wrapper, and zero new types. It fits the 2-week appetite cleanly.
>
> RESOLVED

> **Q (@purescript-specialist -> @web-tech-expert):** The `emitTo` and `broadcastExceptSender` signatures in the Solution Sketch both take `NamespaceHandle ns` but omit the `IsSymbol ns` constraint (only `IsSymbol event` is listed). Looking at the current `onEvent` implementation, it does not need `IsSymbol ns` because it uses the `SocketRef` extracted from the handle and never calls `reflectSymbol` on `ns`. That is correct for `emitTo` (which calls `socket.emit` directly on the handle's ref). But `broadcastExceptSender` calls `socket.broadcast.emit()` on the same ref -- confirm that this also does not require the `ServerSocket` or `IsSymbol ns`, since we never construct a namespace path string. If it does, the pitch signature needs to change to include `ServerSocket` as a parameter (analogous to `broadcast`). The FFI approach (accessing `.broadcast` property on the individual socket ref) determines which is correct.
>
> **A (@web-tech-expert):** Confirmed: `NamespaceHandle ns` alone is sufficient. Neither `emitTo` nor `broadcastExceptSender` need `IsSymbol ns` or `ServerSocket`. Here is the reasoning grounded in Socket.io's runtime behavior.
>
> **Why `broadcast` needs `ServerSocket` + `IsSymbol ns` but these functions do not.** The existing `broadcast` calls `io.of("/" + ns).emit(event, payload)` -- it starts from the `Server` instance (`io`), navigates to a `Namespace` object via the string path, and emits on that namespace-wide scope. That path construction is why it needs `reflectSymbol` on `ns` (to produce the `"/" + ns` string) and `ServerSocket` (which is the `io` object in JS). The `IsSymbol ns` constraint exists solely to power that `reflectSymbol` call.
>
> **`emitTo` operates on the individual socket.** The FFI is `socket.emit(event, payload)`. The `socket` here is the server-side `Socket` object that Socket.io passes into the `connection` callback. This object already knows which namespace it belongs to -- that information was established when `io.of("/chat").on("connection", ...)` fired. The `SocketRef` extracted from the `NamespaceHandle` IS that socket. We never construct a namespace path string, so `IsSymbol ns` is not needed. We never touch the `Server` instance, so `ServerSocket` is not needed.
>
> **`broadcastExceptSender` also operates on the individual socket.** The FFI is `socket.broadcast.emit(event, payload)`. In Socket.io, accessing `.broadcast` on a server-side `Socket` returns a `BroadcastOperator` that is pre-scoped to the socket's namespace and pre-configured to exclude the socket's own ID. The chain `socket.broadcast.emit(event, data)` internally resolves to something equivalent to `io.of(socket.nsp.name).except(socket.id).emit(event, data)` -- but Socket.io handles that internally. We never need to construct the namespace path ourselves. The `SocketRef` from the `NamespaceHandle` is all we need.
>
> **This is consistent with `onEvent`.** Looking at the existing `onEvent` in `/home/toby/pursocket/src/PurSocket/Server.purs` (lines 113-123), it takes `NamespaceHandle ns` with only `IsSymbol event` (no `IsSymbol ns`) because it calls `socket.on(event, callback)` on the extracted `SocketRef`. The same pattern applies to `onCallEvent` and `onDisconnect`. All per-socket operations use the handle alone. Only namespace-wide operations (`broadcast`, `onConnection`) need `ServerSocket` + `IsSymbol ns`. The new `emitTo` and `broadcastExceptSender` are per-socket operations, so the pitch signatures are correct as written.
>
> **Summary:** The pitch signatures are correct. No changes needed. The `ns` phantom type in `NamespaceHandle ns` still participates in the `IsValidMsg` constraint (ensuring the event is valid for that namespace), but it is never reflected to a string at runtime by these functions.
>
> RESOLVED

> **Q (@purescript-specialist -> @web-tech-expert):** The `primBroadcast` FFI has type `forall a. ServerSocket -> String -> String -> a -> Effect Unit`, where `a` is the payload. This `forall a` means the compiler cannot verify payload shape at the FFI boundary -- it trusts the PureScript type engine to have validated it upstream. The new `emitTo` FFI will have the same pattern: `forall a. SocketRef -> String -> a -> Effect Unit`. This is the same unsoundness window that `primEmit` on the client side has. I am not raising this as a blocker (it is inherent to how PureScript FFI works with untyped JS), but I want to flag it explicitly: every new `prim*` function with `forall a` is a point where a bug in the type engine (e.g., a wrong `IsValidMsg` instance) would produce a runtime type mismatch with no compiler warning. The mitigation is integration tests. Is this already tracked as a known risk, or should we add it to a risk register?
>
> **A (@web-tech-expert):** This is a known, inherent property of the PureScript FFI model, not a PurSocket-specific risk. It does not need a separate risk register entry, but it should be documented in the library's architecture notes. Here is the full assessment.
>
> **Why `forall a` at the FFI boundary is structurally unavoidable.** PureScript's FFI is an escape hatch by design -- foreign imports are trusted. There is no mechanism in PureScript to express "this JS function accepts exactly the type that `IsValidMsg` resolved" at the FFI declaration site. The `forall a` is the only option because the FFI function genuinely does accept any JS value (Socket.io's `emit` takes `...args: any[]`). The type safety lives entirely in the PureScript wrapper layer, where `IsValidMsg` constrains `a` before it reaches the `prim*` call. Every PureScript library that wraps a dynamically-typed JS API has this same pattern -- `purescript-aff`'s foreign imports, `purescript-node-http`'s callbacks, etc.
>
> **The attack surface is narrow and well-bounded.** A runtime type mismatch through this window requires a bug in the `IsValidMsg` or `IsValidCall` instance resolution -- specifically, the `RowToList` + `Lookup*` chain would need to resolve to a wrong payload type. Since the instance chain is purely structural (pattern-matching on row labels in the `RowList`), the only way this fails is if (a) the protocol type definition itself is wrong (user error, not library bug), or (b) the PureScript compiler has a bug in `RowToList` (extremely unlikely for such a mature compiler intrinsic). A bug in PurSocket's type engine would manifest as a compile error or a wrong type inference, both of which would be caught by the existing integration tests that verify actual message delivery with concrete payloads.
>
> **The mitigation strategy is already in place.** The integration tests in `Test.Integration` send typed messages from client to server and back, verifying that the payload arrives intact. These tests exercise the full path: PureScript type resolution -> FFI boundary -> Socket.io wire format -> deserialization. If `IsValidMsg` resolved the wrong type, the payload structure on the receiving end would not match expectations and the test assertions would fail. The @qa answer already calls for both positive and negative delivery tests for the new functions, which extends this coverage.
>
> **What adding more `prim*` functions does NOT change.** Each new `primEmitTo`, `primBroadcastExceptSender`, `primBroadcastToRoom` function has the same `forall a` pattern, but they do not widen the unsoundness window in a meaningful way. The window is per-call-site, not cumulative. Each call site is independently protected by its `IsValidMsg` constraint. Adding more FFI functions does not make existing call sites less safe. The risk is O(1) per function pattern, not O(n) across all functions.
>
> **Recommendation:** Do not create a separate risk register entry. Instead, add a brief note to the `PurSocket.Server` module doc comment (and `PurSocket.Client` for symmetry) stating: "FFI functions use `forall a` for payload parameters. Type safety is enforced by `IsValidMsg`/`IsValidCall` constraints in the public API wrappers. Do not call `prim*` functions directly." The existing `Internal` module documentation already warns against direct use. This is sufficient.
>
> RESOLVED

> **Q (@architect -> @web-tech-expert):** The @product-manager resolved the semantics question in favor of the socket-level variant (`socket.to(room).emit()`), which automatically excludes the sender. This means the @purescript-specialist's resolved `broadcastToRoom` FFI signature (which takes `ServerSocket` and calls `io.of(ns).to(room).emit()`) needs revision: the socket-level variant only needs the `SocketRef` from the `NamespaceHandle`, not the `ServerSocket`. The corrected FFI should be `(socket) => (room) => (event) => (payload) => () => { socket.to(room).emit(event, payload); }` operating on the `SocketRef`, and the PureScript signature should take `NamespaceHandle ns -> String -> payload -> Effect Unit` (no `ServerSocket`, no `IsSymbol ns`). This also means all three new functions (`emitTo`, `broadcastExceptSender`, `broadcastToRoom`) share the same `NamespaceHandle`-based pattern, which is a cleaner API than having rooms break the pattern. Can you confirm the `socket.to(room).emit()` FFI chain works correctly on the server-side socket ref? Note: this overlaps with the @product-manager's question below, so they could be resolved together.
>
> **A (@web-tech-expert):** Confirmed. The `socket.to(room).emit(event, payload)` FFI chain works correctly on the server-side socket ref. The proposed FFI and PureScript signature are both correct. Here are the details.
>
> **How `socket.to(room)` works on a server-side Socket.** In Socket.io v4.x (which PurSocket targets via `package.json`), calling `.to(room)` on a server-side `Socket` object returns a `BroadcastOperator` instance. This is the same class of object returned by `socket.broadcast` -- in fact, `socket.broadcast` is syntactic sugar for `socket.to()` with the socket's own ID pre-added to the exclusion set. When you call `socket.to("room1")`, Socket.io creates a `BroadcastOperator` scoped to: (a) the socket's namespace, (b) the room "room1", (c) excluding the calling socket's ID. Calling `.emit(event, payload)` on that operator dispatches the message to all sockets in "room1" within the namespace, except the calling socket.
>
> **The FFI is a straightforward chain.**
> ```js
> export const primBroadcastToRoom = (socket) => (room) => (event) => (payload) => () => {
>   socket.to(room).emit(event, payload);
> };
> ```
> This is correct. The `socket` parameter is the `SocketRef` extracted from `NamespaceHandle` via `socketRefFromHandle`. The `.to(room)` call does not mutate the socket -- it returns a new `BroadcastOperator` each time, so there is no stale-reference concern. The `.emit()` on the operator is synchronous from the caller's perspective (it enqueues the message for delivery but does not block).
>
> **No `ServerSocket` or `IsSymbol ns` needed.** The `BroadcastOperator` returned by `socket.to(room)` already knows its namespace (inherited from the socket). We never construct a `"/" + ns` path string. This is identical to the reasoning for `broadcastExceptSender` -- the socket carries its namespace context. The PureScript signature is:
> ```
> broadcastToRoom
>   :: forall @protocol @ns @event payload
>    . IsValidMsg protocol ns event "s2c" payload
>   => IsSymbol event
>   => NamespaceHandle ns
>   -> String
>   -> payload
>   -> Effect Unit
> ```
>
> **All three new functions now share the `NamespaceHandle`-based pattern.** This is a clean API: `ServerSocket` = namespace-wide broadcast (existing `broadcast`), `NamespaceHandle` = per-socket targeting (`emitTo`, `broadcastExceptSender`, `broadcastToRoom`). The conceptual split is clear and consistent.
>
> **Redis adapter compatibility note.** `socket.to(room).emit()` works transparently with the Redis adapter in multi-process deployments. The `BroadcastOperator` uses the adapter's `broadcast` method internally, which serializes the message and publishes it to the Redis channel. Other Socket.io processes subscribed to the same adapter will deliver the message to matching sockets in their memory. No special handling is needed in PurSocket's FFI.
>
> **One subtlety for `joinRoom` and `leaveRoom`.** These also operate on the socket ref: `socket.join(room)` and `socket.leave(room)`. In Socket.io v4.x, `socket.join()` returns a `Promise` in theory (for adapter compatibility), but the default in-memory adapter resolves it synchronously. For the Redis adapter, it is genuinely async. The pitch should decide whether `joinRoom` returns `Effect Unit` (ignoring the promise, which works for the default adapter) or `Aff Unit` (awaiting the promise, which is correct for all adapters). For a 2-week appetite targeting the default adapter, `Effect Unit` with a doc note about async adapters is the pragmatic choice.
>
> **Note on reconciliation with @purescript-specialist's earlier answer.** The @purescript-specialist's resolved answer proposed `broadcastToRoom` taking `ServerSocket` with FFI `io.of(ns).to(room).emit()`. That answer was correct for namespace-level semantics (includes sender). The @product-manager subsequently resolved the semantics question in favor of socket-level (excludes sender). The revised FFI and signature above supersede the earlier answer. The @purescript-specialist's answer about not introducing `RoomRef` remains valid -- no new types are needed.
>
> RESOLVED

> **Q (@web-tech-expert -> @architect, broadened by project lead):** The original question asked whether `joinRoom`/`leaveRoom` should return `Effect Unit` or `Aff Unit`, given that `socket.join()` returns a `Promise<void>` in Socket.io v4.x. The project lead broadened this to an architectural concern: **What should PurSocket's stance be on `Effect` vs `Aff` across the entire API, given that mixing them is bad DX?** The current API is almost entirely `Effect`-based (the only exceptions are `call`/`callWithTimeout` on the client, which return `Aff` because they genuinely wrap an async callback with timeout). Having some functions return `Effect` and others return `Aff` forces users to remember which is which and sprinkle `liftEffect` everywhere. If `joinRoom` introduces `Aff` to the server module for the first time, should other server functions also migrate to `Aff` for consistency? Or is there a way to keep everything `Effect` without lying about the semantics? How does this affect `joinRoom`/`leaveRoom` specifically?
>
> **A (@architect):** Keep `joinRoom` and `leaveRoom` as `Effect Unit`. Do not introduce `Aff` to the server module. The entire server-side API should remain `Effect`-based. Here is the full architectural reasoning.
>
> **1. The current API has a clean, defensible split -- preserve it.**
>
> After auditing the codebase, the Effect/Aff boundary in PurSocket is not arbitrary. It follows a clear principle: **`Effect` for fire-and-forget operations, `Aff` only for operations that return a value asynchronously.** On the server side, every function is `Effect Unit` -- `broadcast`, `onEvent`, `onConnection`, `onDisconnect`, `socketId`, `createServer`, `closeServer`. On the client side, everything is `Effect` except `call`/`callWithTimeout`, which are `Aff` because they must await an acknowledgement callback and return the response value (`Aff res`, not `Aff Unit`). The `Aff` there is not a stylistic choice; it is structurally required because the return type carries data that arrives asynchronously.
>
> `joinRoom` and `leaveRoom` do not return data. They return `Unit`. The question is purely whether to await the promise. For an operation that returns `Unit`, the distinction between "the promise resolved" and "the effect was dispatched" is only meaningful if the ordering matters -- that is, if code after `joinRoom` depends on the join having been fully processed by the adapter. This brings us to the adapter question.
>
> **2. The default in-memory adapter resolves `socket.join()` synchronously.**
>
> Socket.io's `socket.join(room)` returns a `Promise<void>`, but the default in-memory `Adapter.addAll()` method is synchronous. The promise resolves in the same microtask. This means that for every PurSocket user running the default adapter (which is everyone in this 2-week cycle, and the vast majority of Socket.io deployments), the join is complete by the time the next line of `Effect` code runs. There is no race condition, no ordering hazard, no lost messages. Wrapping this in `Aff` would add `launchAff_` boilerplate at every call site for zero behavioral difference.
>
> For the Redis adapter (or other async adapters), `socket.join()` genuinely needs time to propagate to the pub/sub layer. But PurSocket does not target the Redis adapter in this cycle. The pitch's appetite is 2 weeks, and the No-Gos section already excludes adapter-specific concerns. When Redis adapter support becomes a priority in a future cycle, the right response is a focused migration that considers the full adapter surface (including `broadcastToRoom` timing, room membership consistency, and cluster coordination), not a preemptive `Aff` wrapper on `joinRoom` today.
>
> **3. Introducing `Aff` to the server module has a cascading DX cost.**
>
> If `joinRoom` returns `Aff Unit`, every `onConnection` handler that calls it must become `Aff`-aware. The current `onConnection` callback type is `NamespaceHandle ns -> Effect Unit`. To call an `Aff`-returning `joinRoom` inside that callback, the user must write `launchAff_ $ joinRoom handle "room1"`. Alternatively, we change `onConnection`'s callback to accept `Aff Unit`, but then every existing user who does not use rooms must change their `onConnection` handlers from `Effect` to `Aff` for no reason, or we provide two variants (`onConnection` and `onConnectionAff`), doubling the API surface.
>
> This is the "mixing Effect and Aff is bad DX" concern the project lead raised, and it cuts in the opposite direction from what one might expect. Introducing `Aff` for `joinRoom` does not make the API more consistent -- it makes it *less* consistent, because the server module goes from "everything is Effect" to "everything is Effect except joinRoom and leaveRoom." The user now has to remember that room operations are special. The cognitive load increases, not decreases.
>
> The only way to make `Aff` consistent would be to migrate the entire server API to `Aff`. But `broadcast`, `onEvent`, `emitTo`, and `broadcastExceptSender` are all synchronous fire-and-forget operations. Wrapping them in `Aff` would be a lie about their semantics -- they do not perform any asynchronous work. Users would pay the `Aff` overhead (fiber allocation, scheduler interaction) at every emit call for zero benefit. This violates PurSocket's design principle that the type-level machinery should compile away to zero runtime overhead.
>
> **4. `Effect Unit` does not lie about the semantics for the default adapter.**
>
> A function's return type is a contract with the caller about what the function does. `Effect Unit` says: "this performs a side effect synchronously." For `socket.join()` on the default adapter, that is exactly what happens. The join is complete synchronously. The promise is an artifact of the adapter interface allowing for async implementations, not evidence that the operation is inherently async. Returning `Effect Unit` is truthful for the default adapter, which is the only adapter PurSocket targets in this cycle.
>
> Compare with `call` on the client: returning `Aff res` is truthful because the acknowledgement genuinely arrives later, over the network, with a timeout. The async nature is inherent to the operation, not adapter-dependent.
>
> **5. The pragmatic path for a 2-week appetite.**
>
> Ship `joinRoom` and `leaveRoom` as `Effect Unit` with the following FFI pattern:
>
> ```js
> export const primJoinRoom = (socket) => (room) => () => {
>   socket.join(room);
> };
>
> export const primLeaveRoom = (socket) => (room) => () => {
>   socket.leave(room);
> };
> ```
>
> The promise returned by `socket.join()` is intentionally discarded. The PureScript signatures are:
>
> ```
> joinRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit
> leaveRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit
> ```
>
> Doc comments should note: "Uses the default in-memory adapter's synchronous join semantics. If you use an async adapter (e.g., Redis), the join may not have propagated to other servers by the time this call returns. A future PurSocket version may provide an Aff variant for async adapter support."
>
> **6. If async adapter support is needed later, do it as a deliberate API expansion, not a retrofit.**
>
> The correct future approach is to add `joinRoomAff :: forall ns. NamespaceHandle ns -> String -> Aff Unit` as a separate function in a future cycle, alongside a broader "async adapter support" feature that also considers `broadcastToRoom` timing and cluster coordination. This keeps the existing `Effect`-based API stable for the majority of users while providing an explicit opt-in for users who need async adapter guarantees. It follows the same pattern as `call` vs `emit` on the client side: the simpler `Effect` version for fire-and-forget, the `Aff` version when you need to await.
>
> **Summary of the architectural stance:** PurSocket's API should use `Effect` for all operations that are synchronous under normal usage, and `Aff` only when the operation inherently returns data asynchronously (like `call`). This is not a blanket "always Effect" rule -- it is a semantic honesty rule. `joinRoom`/`leaveRoom` are synchronous under the default adapter, so they are `Effect Unit`. The server module remains 100% `Effect`-based. No `Aff` import is added to `PurSocket.Server` in this cycle.
>
> RESOLVED

## Rabbit Holes

Watch out for:

- **Type-level room names.** It is tempting to make room names type-level Symbols so typos are caught at compile time. This is a rabbit hole. Rooms are dynamic (created at runtime when a user joins "game-42" or "doc-abc"). Type-level room names would require dependent types or complex type-level string manipulation. The pitch explicitly excludes this -- room names are runtime strings.

- **Chaining modifiers.** Socket.io supports chaining like `socket.to("room1").to("room2").except("room3").emit(...)`. Building a composable modifier chain in PureScript (builder pattern or phantom-typed flags) is appealing but adds significant complexity. For 2 weeks, each operation is a standalone function: `broadcastToRoom`, `broadcastExceptSender`. No chaining.

- **`broadcastToRoom` excluding sender.** The common chat pattern is "broadcast to room except the person who sent the message." Socket.io does this with `socket.to(room).emit()` (which automatically excludes the sender when called on a socket, not on the namespace). This subtlety matters: `io.of(ns).to(room).emit()` includes everyone in the room, while `socket.to(room).emit()` excludes the sender socket. We need to decide which semantics `broadcastToRoom` exposes, or whether we need a separate `broadcastToRoomExceptSender`. This should be resolved in shaping, not discovered during build.

- **Room-scoped `onEvent`.** Once rooms exist, developers will want to scope event handlers to specific rooms. Socket.io does not support this -- `socket.on()` fires regardless of room membership. Room-based filtering is application logic. We must document this clearly to prevent confusion.

> **Q (@web-tech-expert -> @product-manager):** For `broadcastToRoom`, should we expose the namespace-level variant (`io.of(ns).to(room).emit()` -- sends to all in room) or the socket-level variant (`socket.to(room).emit()` -- sends to all in room except sender)? Chat apps almost always want the socket-level variant. Should we provide both, or just the more common socket-level one?
>
> **A (@product-manager):** Ship the socket-level variant only. Name it `broadcastToRoom`. Here is the reasoning:
>
> **1. The "exclude sender" semantic is what developers expect from the name.** When a developer reads `broadcastToRoom`, they think "send this to the room" -- and they almost never mean "including myself." The mental model comes from chat, gaming, and collaboration apps where the sender already has the data locally. The existing `broadcastExceptSender` (namespace-wide) establishes the pattern that "broadcast" in PurSocket's vocabulary means "to others." The namespace-level variant (include sender) would be the surprising default.
>
> **2. The namespace-level variant is already composable from existing primitives.** If a developer genuinely needs to send to all room members including the sender, they can call `broadcastToRoom` (hits everyone else in the room) and then `emitTo` on themselves. That is two calls instead of one, but it is the rare case. Optimizing the API surface for the rare case at the cost of a confusing default is a bad DX tradeoff.
>
> **3. API surface minimalism within a 2-week appetite.** Every additional function is a name to learn, a doc comment to write, a test to maintain, and a decision for the developer to make at the call site. Two room-broadcast variants (`broadcastToRoom` vs. `broadcastToRoomIncludingSender` or similar) force every developer to pause and think about which one they want. Since the vast majority of use cases want the socket-level variant, ship just that one function. If demand emerges for the namespace-level variant, it can be added in a future cycle with a clearly distinct name.
>
> **4. Consistency with `broadcastExceptSender`.** The pitch already establishes a pattern: the `NamespaceHandle`-based functions operate from the perspective of a specific socket. `emitTo` sends from the handle's socket to that client. `broadcastExceptSender` sends to everyone except the handle's socket. `broadcastToRoom` sending to the room except the handle's socket is the natural continuation of that pattern. Switching to the namespace-level variant for rooms would break the conceptual consistency of "handle-based = excludes self."
>
> **Type signature implication:** This answer creates a tension with @purescript-specialist's resolved answer on the `RoomRef` question, which proposed `broadcastToRoom` taking `ServerSocket` (namespace-level FFI: `io.of(ns).to(room).emit()`). If we go socket-level, `broadcastToRoom` should take `NamespaceHandle ns` instead of `ServerSocket`, because the FFI becomes `socket.to(room).emit(event, payload)` on the handle's `SocketRef`. This aligns all three new functions on `NamespaceHandle` -- a clean conceptual split where `ServerSocket` = namespace-wide scope, `NamespaceHandle` = socket-aware targeting. I am raising a follow-up question below to reconcile these two answers.
>
> RESOLVED

> **Q (@product-manager -> @web-tech-expert):** My answer above (socket-level `broadcastToRoom` taking `NamespaceHandle`) conflicts with @purescript-specialist's resolved answer (namespace-level `broadcastToRoom` taking `ServerSocket`). The two answers chose different Socket.io primitives: `socket.to(room).emit()` vs. `io.of(ns).to(room).emit()`. The product question (which semantic?) is now resolved in favor of socket-level. But this means the FFI and type signature from the @purescript-specialist answer need revision. Specifically: (a) Does `socket.to(room)` on a server-side Socket.io socket return a BroadcastOperator that works the same way as `socket.broadcast`? (b) Does the FFI become `socketRef.to(room).emit(event, payload)` -- a straightforward two-step chain on the SocketRef? (c) Does this change affect the `IsSymbol ns` constraint question that @purescript-specialist already raised (since the socket-level variant should not need namespace resolution at all)?
>
> **A (@web-tech-expert):** All three sub-questions answered affirmatively. The revision is clean and straightforward.
>
> **(a) Yes, `socket.to(room)` returns a `BroadcastOperator` that works the same way as `socket.broadcast`.** In Socket.io v4.x, the server-side `Socket` class has a `.to(room)` method (defined in `socket.ts`) that creates and returns a `BroadcastOperator`. The `BroadcastOperator` constructor receives the namespace's adapter, a set of rooms to target, a set of rooms/socket-IDs to exclude, and optional flags. When you call `socket.to("room1")`, the returned operator targets room "room1" and excludes `socket.id`. When you call `socket.broadcast` (a getter property), the returned operator targets no specific room (meaning the whole namespace) and excludes `socket.id`. Both return the same `BroadcastOperator` class; the only difference is whether a room filter is applied. The `.emit()` method on `BroadcastOperator` works identically in both cases -- it calls `adapter.broadcast()` with the rooms/exclusions.
>
> **(b) Yes, the FFI becomes `socketRef.to(room).emit(event, payload)` -- a straightforward two-step chain.** The corrected FFI is:
> ```js
> export const primBroadcastToRoom = (socket) => (room) => (event) => (payload) => () => {
>   socket.to(room).emit(event, payload);
> };
> ```
> The `.to(room)` call is pure (no side effects, no mutation of the socket object) -- it constructs a new `BroadcastOperator` each time. The `.emit()` call on the operator enqueues the message for delivery. This is safe to call multiple times with different rooms on the same socket. The chain is analogous to how `socket.broadcast.emit()` works for `broadcastExceptSender`, just with an additional room filter.
>
> **(c) Yes, this eliminates the `IsSymbol ns` constraint for `broadcastToRoom`.** The socket-level variant never constructs a namespace path string. The `BroadcastOperator` inherits the namespace from the socket object itself (via `socket.nsp`). The PureScript wrapper only needs `IsSymbol event` (to reflect the event name to a string) and `IsValidMsg` (for protocol validation). The `ns` type parameter still participates in `IsValidMsg` for compile-time validation, but it is never reflected to a runtime string. This is consistent with `emitTo` and `broadcastExceptSender`, which also omit `IsSymbol ns`.
>
> **Corrected PureScript signature (superseding @purescript-specialist's earlier answer):**
> ```
> broadcastToRoom
>   :: forall @protocol @ns @event payload
>    . IsValidMsg protocol ns event "s2c" payload
>   => IsSymbol event
>   => NamespaceHandle ns
>   -> String
>   -> payload
>   -> Effect Unit
> ```
>
> **Summary of the reconciliation.** The @purescript-specialist's answer was correct for the namespace-level semantic (`io.of(ns).to(room).emit()`). The @product-manager then resolved the semantic question in favor of socket-level (`socket.to(room).emit()`). The revised signature drops `ServerSocket` in favor of `NamespaceHandle ns`, drops `IsSymbol ns`, and the FFI operates on the `SocketRef` extracted from the handle. All three new functions (`emitTo`, `broadcastExceptSender`, `broadcastToRoom`) now share the same `NamespaceHandle`-based pattern, which is the cleanest possible API surface.
>
> RESOLVED

> **Q (@product-manager -> @web-tech-expert):** The name `emitTo` reads as "emit to [a target]" where the `NamespaceHandle` identifies the target client. That is correct -- in PurSocket's `onConnection` model, the handle represents a specific client's socket, so `emitTo handle payload` means "emit to the client behind this handle." But contrast it with `broadcastExceptSender handle payload` where the same handle identifies who is EXCLUDED. The handle parameter means "deliver to this client" in `emitTo` and "deliver to everyone except this client" in `broadcastExceptSender`. Both functions have identical type signatures (`NamespaceHandle ns -> payload -> Effect Unit`), and @external-user already flagged the identical-signature concern. From a developer experience standpoint, would naming `emitTo` something more explicit -- like `sendToClient` or `emitToHandle` -- make the intent clearer when reading code? Or does the `emitTo` / `broadcastExceptSender` pairing read naturally enough that the opposite-handle-semantics issue is a non-problem in practice?
>
> **A (@web-tech-expert):** Keep `emitTo`. Do not rename it. The pairing reads naturally, and the alternatives introduce worse problems. Here is the detailed reasoning.
>
> **1. `emitTo` maps directly to Socket.io's mental model.** Every Socket.io developer knows `socket.emit()` means "send to this socket." The name `emitTo` clearly communicates "emit to [this handle]." It is the PureScript transliteration of `socket.emit()` -- the same vocabulary the developer already knows from Socket.io's documentation, Stack Overflow answers, and tutorials. Renaming it to `sendToClient` breaks this mapping. Socket.io's API never uses the word "send" for this operation (that is the WebSocket API's vocabulary). Mixing Socket.io and WebSocket terminology in the same library would be confusing.
>
> **2. The verb distinction already carries the semantic difference.** `emitTo` uses "emit" (single-target verb). `broadcastExceptSender` uses "broadcast" (multi-target verb). When a developer reads `emitTo handle payload`, the verb "emit" plus the preposition "to" naturally implies a single destination. When they read `broadcastExceptSender handle payload`, the verb "broadcast" implies fan-out to many, and "ExceptSender" clarifies the exclusion. The handle's role (target vs. excluded party) is implied by the verb, not by the type signature. This is normal API design -- `Array.push` and `Array.indexOf` both take an element argument, but nobody confuses them because the verb carries the meaning.
>
> **3. `sendToClient` is inaccurate.** The `NamespaceHandle` is a capability token for a specific namespace connection, not necessarily a "client" in the user-facing sense. A single browser tab can hold multiple `NamespaceHandle` values (one per namespace it joined). Calling it `sendToClient` implies one handle per human user, which is not the Socket.io model. `emitTo` is neutral about what the handle represents -- it just means "emit to this target."
>
> **4. `emitToHandle` is redundant.** The type signature already tells you the argument is a `NamespaceHandle`. Adding "Handle" to the function name restates the type in the name, which is a PureScript anti-pattern. We do not call `socketId` by the name `socketIdFromHandle`.
>
> **5. The real mitigation for misuse is not naming -- it is the code context.** In practice, `emitTo` and `broadcastExceptSender` appear in different code patterns. `emitTo` appears when the server looks up a specific recipient (e.g., `Map.lookup recipientId handleMap >>= \h -> emitTo h payload`). `broadcastExceptSender` appears in the `onEvent` handler for the sender's message (e.g., inside `onEvent handle \msg -> broadcastExceptSender handle ...`). The surrounding code makes the intent obvious. A developer who swaps them will immediately see wrong behavior in manual testing (either only one person gets the message when everyone should, or everyone gets it when only one should).
>
> **Recommendation:** Ship `emitTo` as named. Add a doc comment that explicitly states "sends to the single client identified by the handle" to make the intent grep-able and IDE-hoverable. The @external-user's concern about identical signatures is addressed separately in the identical-signatures question below.
>
> RESOLVED

> **Q (@web-tech-expert -> @qa):** `emitTo` and `broadcastExceptSender` are thin wrappers over Socket.io primitives. What is the minimum test coverage needed? I would suggest: (1) emitTo reaches only the target client and no others, (2) broadcastExceptSender reaches all clients except the sender, (3) rooms -- joinRoom/broadcastToRoom delivers only to room members. Are the existing integration test patterns (spin up server, connect N clients, verify message receipt) sufficient, or do we need a new test harness for multi-client scenarios?
>
> **A (@qa):** The existing integration test harness (spin up server on a unique port, connect clients, verify via `Ref`, delay for delivery, cleanup) is sufficient. No new test framework is needed. However, every existing test in `Test.Integration` is a single-client scenario. Every test proposed in this pitch requires multiple concurrent clients, which is a structural escalation in test complexity. Here is the minimum coverage and the specific concerns.
>
> **Minimum required tests (7 scenarios across 3 features):**
>
> *emitTo (2 tests):*
> 1. **Positive delivery:** Server calls `emitTo` on client A's handle. Client A receives the message.
> 2. **Exclusivity (negative):** Connect clients A and B to the same namespace. Server calls `emitTo` on A's handle. Verify B does NOT receive the message. This is the critical correctness property -- without it, `emitTo` could be accidentally aliased to `broadcast` and the positive test alone would still pass.
>
> *broadcastExceptSender (2 tests):*
> 3. **Others receive:** Connect clients A and B. Client A triggers a c2s event; server handler calls `broadcastExceptSender` using A's handle. Verify B receives the message.
> 4. **Sender excluded:** Same setup. Verify A does NOT receive the message.
>
> *Rooms (3 tests, only if rooms ship):*
> 5. **joinRoom + broadcastToRoom delivery:** Client A joins room "r1". Client B does not. Server calls `broadcastToRoom "r1"`. Verify A receives, B does not.
> 6. **leaveRoom stops delivery:** Client A joins room "r1", then calls `leaveRoom "r1"`. Server calls `broadcastToRoom "r1"`. Verify A does NOT receive.
> 7. **Multiple rooms isolation:** Client A joins "r1". Client B joins "r2". `broadcastToRoom "r1"` reaches only A. `broadcastToRoom "r2"` reaches only B.
>
> **On the existing harness -- sufficient with one pattern addition:**
>
> The current `Ref.new` + `delay (Milliseconds N)` + `Ref.read` pattern works for positive assertions. For **negative assertions** (verifying a client did NOT receive a message), we use the same delay pattern but assert the `Ref` still holds its initial sentinel value after the delay. A 200-300ms delay after the emit is reasonable for localhost loopback. Each test should use a unique port (continuing the `testPort + N` convention from `Test.Integration`) to avoid cross-test interference. The existing tests use `testPort` through `testPort + 3` (ports 3456-3459), so the new tests should start at `testPort + 4`.
>
> The multi-client pattern is: connect 2-3 clients to the same server on the same port, obtain separate `NamespaceHandle` values from `onConnection`, and use per-client `Ref` values to track who received what. The `onConnection` callback in `PurSocket.Server` already hands us a fresh `NamespaceHandle` per client, so the existing infrastructure supports this directly.
>
> **Reliability concern for multi-client tests:** The order of `onConnection` callbacks for multiple clients connecting simultaneously is not guaranteed by Socket.io. Tests that need to distinguish "client A's handle" from "client B's handle" on the server side should either (a) use `socketId` to correlate handles with clients, or (b) connect clients sequentially with a small delay between them. Sequential connection adds ~100ms per client but eliminates a flake vector. I recommend option (b) for simplicity.
>
> **Compile-time tests (in addition to integration):** `emitTo` and `broadcastExceptSender` should get the same negative-compile-test treatment as `broadcast`: verify that passing a c2s event produces a compile error. Add entries to `test-negative/` following the existing `WrongDirection` pattern.
>
> RESOLVED

> **Q (@qa -> @web-tech-expert):** The `broadcastExceptSender` FFI must access `socket.broadcast.emit()` where `.broadcast` is a property returning a `BroadcastOperator`, not a method. This is a different JS access pattern from every other FFI function in `Server.js`, which all call methods directly on their target object. Should we add a dedicated JS-level smoke test (outside the PureScript test suite) that confirms `socket.broadcast` is a valid object with an `emit` method on the Socket.io version pinned in `package.json`? If a Socket.io major version changes the `.broadcast` property shape, a JS-level test would isolate the failure to the FFI layer rather than surfacing it as a mysterious integration test timeout where `broadcastExceptSender` silently does nothing.
>
> **A (@web-tech-expert):** No, a dedicated JS-level smoke test is not needed. The integration tests provide better coverage with less maintenance burden. Here is the reasoning.
>
> **The `.broadcast` property is stable and well-established.** The `socket.broadcast` getter has existed since Socket.io v1.x and has survived three major version bumps (v2, v3, v4) without changing its API surface. It is one of the most commonly used Socket.io patterns -- featured prominently in the official "Get Started" tutorial, the cheatsheet, and every chat example. If a future Socket.io major version removed or changed `.broadcast`, it would be a massively breaking change that would appear in migration guides, changelog headlines, and npm audit warnings. PurSocket pins its Socket.io version in `package.json`, so a major version bump is already a deliberate, manual action that requires reviewing the changelog.
>
> **A JS-level smoke test adds maintenance cost for marginal benefit.** A test that just checks `typeof socket.broadcast === 'object' && typeof socket.broadcast.emit === 'function'` is a shape check, not a behavior check. It confirms the property exists but does not confirm it works correctly (e.g., that it actually excludes the sender). The integration test for `broadcastExceptSender` (connect two clients, emit, verify sender excluded) tests both the property shape AND the behavior in a single test. If `.broadcast` changes shape, the integration test fails with a clear error (TypeError or delivery failure), not a mysterious timeout.
>
> **The "mysterious timeout" concern is addressed by test design, not extra tests.** The @qa answer already specifies negative delivery assertions with a 200-300ms delay. If `broadcastExceptSender` silently does nothing (because `.broadcast` is undefined or broken), the positive assertion ("verify B receives the message") would fail -- not time out -- because the `Ref` would still hold its sentinel value after the delay. The failure mode is a clear assertion failure ("expected 'hello' but got ''"), not a hung test. Socket.io errors on `undefined.emit()` would throw a TypeError, which PureScript's `Effect` would propagate as an exception, crashing the test immediately with a stack trace pointing at the FFI call.
>
> **The same reasoning applies to `socket.to(room)`.** The `.to()` method has the same stability profile as `.broadcast`. Both return `BroadcastOperator`. Both are covered by the integration tests proposed by @qa. Adding JS-level shape checks for each FFI function would create a parallel test suite that duplicates coverage without adding confidence.
>
> **What would actually catch a Socket.io version incompatibility.** If we want early detection of breaking changes across Socket.io major versions, the right tool is a CI step that runs `npm audit` or a Dependabot/Renovate configuration that flags major version bumps with a "review required" label. That is an infrastructure concern, not a test concern. For PurSocket's 2-week appetite, the integration tests are sufficient.
>
> RESOLVED

> **Q (@qa -> @web-tech-expert):** The Definition of Done says "at least one integration test proving it delivers to exactly one client" for `emitTo` and similar language for `broadcastExceptSender`. This only requires a positive delivery assertion. I recommend the DoD be strengthened to require **both positive and negative delivery assertions** -- proving correct delivery AND proving non-delivery to excluded clients. A test that only checks the happy path would pass even if the implementation secretly called `broadcast`. Should the DoD language for items 1-3 be tightened to "at least one integration test proving correct delivery AND at least one proving non-delivery to excluded clients"?
>
> **A (@web-tech-expert):** Yes, absolutely. The DoD should require both positive and negative delivery assertions. This is not a nice-to-have -- it is essential for the correctness properties these functions exist to provide.
>
> **The core argument is irrefutable.** The entire purpose of `emitTo` (vs. `broadcast`) is that it sends to ONE client and NOT to others. The entire purpose of `broadcastExceptSender` (vs. `broadcast`) is that it sends to others and NOT to the sender. If we only test the positive path (message arrives at expected recipient), we have not tested the defining property of the function. A positive-only test for `emitTo` would pass if the implementation were literally `broadcast` -- every client would get the message, including the intended target. The negative assertion (other clients do NOT receive) is what distinguishes `emitTo` from `broadcast` in the test suite.
>
> **This maps directly to Socket.io's failure modes.** The most likely implementation bug is getting the FFI wrong -- for example, accidentally calling `socket.nsp.emit()` (namespace-wide) instead of `socket.emit()` (single socket) in `primEmitTo`. Both would deliver to the target client. Only the negative assertion catches the difference. Similarly, for `broadcastExceptSender`, accidentally omitting `.broadcast` and calling `socket.emit()` directly would send only to the sender (the opposite of the intended behavior). The positive assertion (others receive) catches this case, but if the bug were calling `io.of(ns).emit()` instead (namespace-wide broadcast), only the negative assertion (sender does NOT receive) would catch it.
>
> **Proposed DoD language revision (items 1-3):**
>
> 1. `emitTo` function exists in `PurSocket.Server`, is exported, has doc comments, and has integration tests proving (a) it delivers to the target client AND (b) it does NOT deliver to other connected clients.
> 2. `broadcastExceptSender` function exists in `PurSocket.Server`, is exported, has doc comments, and has integration tests proving (a) it delivers to other connected clients AND (b) it does NOT deliver to the sender.
> 3. If rooms ship: `joinRoom`, `leaveRoom`, and `broadcastToRoom` exist in `PurSocket.Server`, are exported, have doc comments, and have integration tests proving (a) room-scoped delivery reaches room members AND (b) it does NOT reach non-members.
>
> **Impact on appetite.** The negative assertions use the same test harness pattern as the positive ones (connect multiple clients, emit, delay, check `Ref`). Each negative assertion is 3-5 additional lines of test code per scenario. The @qa answer already scoped this at 7 test scenarios total. Strengthening the DoD to require negative assertions does not add new scenarios -- it makes explicit what was already implied by the @qa test plan. No appetite risk.
>
> RESOLVED

## No-Gos

Explicitly out of scope:

- **Type-level room names.** Rooms are runtime strings. No `IsSymbol` constraints on room names. No compile-time room name validation.
- **Room membership queries.** No `socket.rooms` wrapper. No `fetchSockets` in a room. No `io.in(room).socketsJoin()`. These are admin/monitoring features, not protocol features.
- **Modifier chaining / builder pattern.** No composable `.to().except().emit()` chain. Each delivery mode is a standalone function.
- **`disconnecting` event.** The event that fires before a socket leaves its rooms. Useful for cleanup, but adds scope. Deferred.
- **Volatile / local / compress modifiers.** Infrastructure tuning, not protocol concern. Never for volatile/compress; deferred for local.
- **Room-scoped `Call` (acknowledgement).** `broadcastToRoom` is fire-and-forget only. Socket.io acknowledgements with `to()` have complex semantics (multiple responses). Out of scope.
- **Bulk room operations.** No `socketsJoin`, `socketsLeave`, `disconnectSockets` by room. Admin utilities, not protocol layer.

> **Q (@web-tech-expert -> @external-user):** The pitch explicitly defers room membership queries (`socket.rooms`) and the `disconnecting` event. For your chat/multiplayer use cases, would you be blocked without these, or can you track room membership in application state (e.g., a `Ref (Map RoomName (Set SocketId))`)?
>
> **A (@external-user):** Not blocked. Application-level state tracking is not just workable -- it is what I would do anyway in a typed PureScript codebase, and the chat example already demonstrates this pattern.
>
> Looking at `examples/chat/src/Chat/Server/Main.purs`, the server already maintains a `Ref (Array User)` for user tracking (lines 28-33) and manually cleans it up in the `onDisconnect` handler (lines 63-73). Extending this to `Ref (Map RoomName (Set SocketId))` is a small, well-understood step. In fact, for any app where I care about room membership -- rendering a sidebar of "who's in this room," enforcing max-room-size limits, or checking authorization before join -- I need application-level state regardless, because `socket.rooms` gives me a raw `Set<string>` with no domain semantics attached.
>
> The `disconnecting` event is more nuanced. The reason it exists in Socket.io is that by the time `disconnect` fires, the socket has already left all its rooms, so you cannot inspect `socket.rooms` to know which rooms to clean up. But if I am already tracking room membership in my own `Ref`, I do not need `socket.rooms` at disconnect time -- I can look up the socket ID in my own map. The chat example already does exactly this: it finds the leaving user by `sid` in the ref, not by querying Socket.io state. So the deferral is fine as long as `onDisconnect` continues to fire reliably (which it does).
>
> One concrete scenario worth stress-testing: if a client disconnects abruptly (network drop, browser crash) while in multiple rooms, the `onDisconnect` handler fires once per namespace, not once per room. My application cleanup code needs to remove the socket from all rooms it was in. With app-level state this is a map lookup + delete, which is straightforward. With `disconnecting` + `socket.rooms` it would be marginally more convenient but not fundamentally different.
>
> **Bottom line:** Deferring both is the right call for a 2-week cycle. Application-level state is more explicit, more testable, and avoids a dependency on Socket.io's internal room bookkeeping. The only scenario where I might feel the pain is a very large-scale deployment where maintaining that `Ref` across thousands of rooms becomes a memory concern -- but at that scale I would be using Redis adapter anyway and would need a different state strategy regardless.
>
> RESOLVED

> **Q (@external-user -> @web-tech-expert):** The `emitTo` signature takes a `NamespaceHandle ns` to identify the target client. But in the common "private message" pattern, the server receives a message from Alice containing Bob's user ID, then needs to emit to Bob. At that point the server is inside Alice's `onEvent` handler and only has Alice's handle. To emit to Bob, I need Bob's `NamespaceHandle` -- which means I must have stashed it in a `Ref (Map UserId (NamespaceHandle "chat"))` during Bob's `onConnection`. Is this the intended usage pattern? If so, should the docs/example make it explicit that handles are meant to be stored and reused, not just consumed inline within their `onConnection` callback?
>
> **A (@web-tech-expert):** Yes, that is exactly the intended usage pattern, and yes, the docs should make it explicit. Here is the full picture.
>
> **Storing handles in a `Ref (Map UserId (NamespaceHandle ns))` is the correct pattern.** The `NamespaceHandle` wraps a `SocketRef`, which is a reference to the server-side Socket.io `Socket` object. That object remains valid for the lifetime of the connection -- from the `connection` event until the `disconnect` event. Storing it in a `Ref` or `Map` is safe and expected. Socket.io itself encourages this pattern in its documentation (maintaining a map of user IDs to socket instances for targeted messaging). The PureScript `NamespaceHandle` is just a phantom-typed wrapper around this same reference.
>
> **The chat example already demonstrates the storage pattern for IDs.** Looking at `/home/toby/pursocket/examples/chat/src/Chat/Server/Main.purs`, the server stores `{ id :: String, nickname :: String }` in a `Ref (Array User)` (line 28) and looks up users by `sid` throughout the handlers. The extension to storing handles is natural: change `User` to `{ id :: String, nickname :: String, handle :: NamespaceHandle "chat" }` and look up the recipient's handle when sending a private message. The `onDisconnect` handler already cleans up by `sid`, so removing the handle from the map on disconnect follows the same pattern.
>
> **Why handles are not just callback-scoped.** A developer new to PurSocket might assume the `NamespaceHandle` received in the `onConnection` callback is only valid within that callback's scope, similar to how some event-driven APIs provide ephemeral context objects. This is not the case. The handle wraps a long-lived JS object (`Socket`) that Socket.io maintains in memory for the duration of the connection. The handle is safe to store, pass between functions, and use in any `Effect` context until the corresponding `disconnect` event fires. After disconnect, the underlying `Socket` is in a "disconnected" state and `emit` calls are silent no-ops (see the disconnected-handle question below).
>
> **Documentation recommendation.** The `emitTo` doc comment should include a brief usage note like:
> ```
> -- | To send private messages, store handles from `onConnection` in a
> -- | `Ref (Map UserId (NamespaceHandle ns))` and look up the recipient's
> -- | handle when needed.  Remove handles in `onDisconnect`.
> ```
> This is 3 lines of doc comment, not a full example. Adding a private messaging example to the chat app was already deferred by the @user answer on the DoD question. The doc comment plus the existing chat example's `Ref (Array User)` pattern should be sufficient for developers to extrapolate.
>
> **Type safety note.** The phantom `ns` parameter on the handle ensures you cannot accidentally store a handle from namespace "game" and use it with `emitTo @Protocol @"chat"`. The `IsValidMsg` constraint will fail if the handle's `ns` does not match the event's namespace. This type safety is preserved regardless of how long the handle is stored or how many times it is reused.
>
> RESOLVED

> **Q (@external-user -> @web-tech-expert):** What happens if I call `emitTo` with a `NamespaceHandle` for a client that has already disconnected? In raw Socket.io, `socket.emit()` on a disconnected socket is a silent no-op. Will PurSocket preserve that behavior, or is there any plan for an `emitTo` variant that returns a success/failure indicator? For fire-and-forget chat this does not matter, but for transactional use cases (e.g., confirming a game move was delivered) silent drops are a real problem.
>
> **A (@web-tech-expert):** PurSocket will preserve Socket.io's silent no-op behavior. This is the correct default, and a success/failure variant is out of scope for this pitch. Here is the detailed analysis.
>
> **What actually happens at the Socket.io level.** When a client disconnects, Socket.io marks the server-side `Socket` object's `connected` property as `false` and removes it from the namespace's active sockets set. However, the JS object itself is not garbage-collected immediately -- it remains in memory as long as any reference exists (in our case, the `NamespaceHandle` in the `Ref Map`). Calling `socket.emit(event, data)` on a disconnected socket is a silent no-op: Socket.io's `emit` method checks `this.connected` internally and short-circuits if false. No error is thrown, no exception, no promise rejection. The data is simply discarded. This behavior has been stable across Socket.io v2, v3, and v4.
>
> **Why silent no-op is the correct default for `emitTo`.** The `emitTo` signature returns `Effect Unit`, consistent with every other emit function in PurSocket (`broadcast`, client-side `emit`). Fire-and-forget semantics are the Socket.io contract: `emit` never guarantees delivery. Messages can be lost to network interruptions, transport buffer overflows, or client-side disconnection between the server's `emit` call and the data reaching the wire. A disconnected handle is just one more case in this same category. Changing `emitTo` to return `Effect Boolean` or `Effect (Maybe Error)` would (a) break consistency with all other emit functions, (b) give a false sense of reliability (returning `true` only means the socket was connected at the moment of the call, not that the message was delivered to the application layer), and (c) add API surface for a property that Socket.io itself does not expose synchronously.
>
> **The mitigation is application-level handle lifecycle management.** The correct pattern is to remove handles from the storage map in the `onDisconnect` handler:
> ```purescript
> onDisconnect handle do
>   Ref.modify_ (Map.delete recipientId) handleMapRef
> ```
> Then, when sending a private message, check whether the handle exists in the map:
> ```purescript
> case Map.lookup recipientId handleMap of
>   Nothing -> -- recipient is offline, queue or drop
>   Just h  -> emitTo @Protocol @"chat" @"privateMsg" h payload
> ```
> This is the same pattern used in every Socket.io application and is already demonstrated (for user tracking) in the chat example. The `Map.lookup` returning `Nothing` is the application-level "not connected" signal -- it is more reliable than checking socket state because it is synchronized with the application's own `onDisconnect` handler.
>
> **For transactional use cases, use `Call` (acknowledgements), not `emitTo`.** If a developer needs delivery confirmation for a game move, the correct tool is `onCallEvent` / `call` -- the request/response pattern with Socket.io acknowledgements. An ack confirms the message reached the client AND was processed by the client's handler. If the client disconnects before acking, the `call` on the sender side times out (via `socket.timeout(ms).emit()`). This is the existing PurSocket `Call` pattern. A future cycle could add `callTo` (targeted ack) if there is demand, but that is a new feature, not a variant of `emitTo`.
>
> **Summary:** `emitTo` on a disconnected handle is a silent no-op, consistent with Socket.io and with PurSocket's existing `broadcast` behavior. No variant returning success/failure is planned for this cycle. The doc comment for `emitTo` should note: "Calling `emitTo` on a handle for a disconnected client is a no-op. Use `onDisconnect` to remove stale handles from application state."
>
> RESOLVED

> **Q (@external-user -> @web-tech-expert):** The proposed `emitTo` and `broadcastExceptSender` have identical type signatures -- both take `NamespaceHandle ns -> payload -> Effect Unit`. In a code review or when scanning unfamiliar PurSocket code, the only difference is the function name. Has there been consideration of whether this could lead to accidental misuse? For example, a developer refactoring quickly could swap one for the other without a compile error. Socket.io's `socket.broadcast.emit` reads differently from `socket.emit` precisely because of the `.broadcast.` in the chain. I am not suggesting a builder pattern (that is correctly identified as a rabbit hole), just flagging that the identical signatures mean the compiler cannot help if the wrong function is called.
>
> **A (@web-tech-expert):** This is a valid observation, but it is not a design flaw -- it is an inherent property of the domain. The two functions differ in delivery semantics, not in type structure, and no practical type-level encoding would help without introducing disproportionate complexity. Here is the analysis.
>
> **The identical signature reflects identical type-level requirements.** Both functions need the same inputs: a handle identifying a socket (for targeting or exclusion), an event name (validated by `IsValidMsg`), and a payload (type-inferred from the protocol). The difference is purely in runtime behavior: one calls `socket.emit()`, the other calls `socket.broadcast.emit()`. In Socket.io's own TypeScript definitions, `socket.emit` and `socket.broadcast.emit` also have identical type signatures -- the `.broadcast` property returns a `TypedBroadcastOperator` with the same `emit` signature as the socket itself. PurSocket is not uniquely exposed here.
>
> **Type-level differentiation would require phantom-tagged handles or a delivery mode parameter, both of which are rabbit holes.** One could imagine `emitTo :: NamespaceHandle ns Direct -> ...` vs `broadcastExceptSender :: NamespaceHandle ns Broadcast -> ...` with phantom delivery mode tags. But the same handle obtained from `onConnection` must work with both functions (and with `onEvent`, `onCallEvent`, `onDisconnect`, `socketId`, and the future `broadcastToRoom`). Introducing phantom modes would either (a) require the user to "tag" the handle before use (ceremony with no safety gain, since the tag is always valid), or (b) require separate handle types per delivery mode (breaking the single-handle-per-connection model). Both are worse than the status quo.
>
> **The practical misuse risk is low.** Consider the two scenarios where a developer might confuse them:
>
> 1. **Using `emitTo` where `broadcastExceptSender` was intended.** The developer sends a message to only one client instead of all-except-sender. In a chat app, only one person sees the message instead of the whole room. This is immediately visible in manual testing -- the most basic smoke test (send a message, check if others see it) catches this.
>
> 2. **Using `broadcastExceptSender` where `emitTo` was intended.** The developer broadcasts to everyone except the sender instead of sending to one target. In a private messaging feature, every other user sees the "private" message. This is also immediately visible -- the first time you test with two recipients, the wrong one gets the message.
>
> In both cases, the bug is caught by the first manual test or the first integration test that involves more than one client. The negative delivery assertions in the DoD (now strengthened per the @qa question above) explicitly catch both failure modes in CI.
>
> **The real-world analogy in standard libraries.** PureScript's own `Data.Array` has `snoc` and `cons` with nearly identical signatures (`a -> Array a -> Array a` vs `Array a -> a -> Array a`). Haskell has `writeIORef` and `modifyIORef` operating on the same `IORef` type. React has `useState` and `useReducer` with overlapping use cases. In every case, the function name carries the semantic distinction, and developers learn the difference through documentation and usage patterns, not through type enforcement. PurSocket is in the same category.
>
> **Mitigations already in place:**
> - The function names are maximally descriptive: `emitTo` (emit TO one target) vs `broadcastExceptSender` (broadcast EXCEPT the sender). The names are not confusable.
> - Doc comments (required by the DoD) will state the delivery semantics explicitly.
> - Integration tests with negative assertions will catch accidental swaps in CI.
> - The import list in application code (e.g., `import PurSocket.Server (emitTo, broadcastExceptSender)`) serves as documentation of which functions are in use.
>
> **Summary:** The identical signatures are acceptable. The function names provide clear semantic distinction. No type-level mitigation is warranted within the 2-week appetite.
>
> RESOLVED

## Definition of Done

**"Shipped" means:**

1. `emitTo` function exists in `PurSocket.Server`, is exported, has doc comments, and has integration tests proving (a) it delivers to the target client AND (b) it does NOT deliver to other connected clients.
2. `broadcastExceptSender` function exists in `PurSocket.Server`, is exported, has doc comments, and has integration tests proving (a) it delivers to other connected clients AND (b) it does NOT deliver to the sender.
3. `joinRoom`, `leaveRoom`, and `broadcastToRoom` exist in `PurSocket.Server`, are exported, have doc comments, and have integration tests proving (a) room-scoped delivery reaches room members AND (b) it does NOT reach non-members.
4. `emitTo` and `broadcastExceptSender` have negative compile tests (wrong direction produces compile error), following the existing `test-negative/` `WrongDirection` pattern.
5. The chat example (`examples/chat/`) is updated to use `broadcastExceptSender` for the `newMessage` broadcast (replacing the current `broadcast` that echoes to the sender).
6. All existing tests continue to pass. No regressions.
7. CI green: build, test, browser bundle.

> **Q (@web-tech-expert -> @user):** The chat example update (item 4) would be a concrete demonstration of the new API. Should we also add a private messaging feature to the chat example using `emitTo`, or is the `broadcastExceptSender` update sufficient for the demo?
>
> **A (@user):** The `broadcastExceptSender` update is sufficient for the chat example. Adding private messaging would expand the example's scope (new UI for recipient selection, new protocol events, handle storage map) and risk consuming appetite that should go to the core library functions. The chat example's purpose is to demonstrate PurSocket's API, not to be a full-featured chat app. `emitTo` can be demonstrated in a standalone integration test or a future example.
>
> RESOLVED

---

## Open Questions

| Section | Question | Asker | Assignee | Status |
|---------|----------|-------|----------|--------|
| Research Findings | Should `emitTo` FFI share `primEmit` with Client.js or use a dedicated server-side FFI function? | @web-tech-expert | @architect | RESOLVED |
| Research Findings | Should `broadcastToRoom` take `ServerSocket + String` or a `RoomRef` wrapper type? | @web-tech-expert | @purescript-specialist | RESOLVED |
| Research Findings | Do `emitTo`/`broadcastExceptSender` need `IsSymbol ns` or `ServerSocket`, or is `NamespaceHandle ns` alone sufficient given the FFI approach? | @purescript-specialist | @web-tech-expert | RESOLVED |
| Research Findings | Is the `forall a` unsoundness in FFI `prim*` functions tracked as a known risk? Every new FFI function widens this window. | @purescript-specialist | @web-tech-expert | RESOLVED |
| Research Findings | Socket-level `broadcastToRoom` (per @product-manager) means the `ServerSocket` FFI needs revision to `NamespaceHandle`-based `socket.to(room).emit()`. Confirm FFI works on server-side socket ref. | @architect | @web-tech-expert | RESOLVED |
| Rabbit Holes | Should `broadcastToRoom` use namespace-level semantics (includes sender) or socket-level (excludes sender)? Or both? | @web-tech-expert | @product-manager | RESOLVED |
| Rabbit Holes | Socket-level `broadcastToRoom` (per @product-manager) conflicts with @purescript-specialist's `ServerSocket` signature. What is the correct FFI for `socket.to(room).emit()` and does it affect `IsSymbol ns` constraints? | @product-manager | @web-tech-expert | RESOLVED |
| Rabbit Holes | Would renaming `emitTo` to something more explicit (e.g., `sendToClient`) improve DX given its identical signature to `broadcastExceptSender` but opposite handle semantics? | @product-manager | @web-tech-expert | RESOLVED |
| Rabbit Holes | What is minimum test coverage for emitTo, broadcastExceptSender, and rooms? Are existing integration patterns sufficient for multi-client scenarios? | @web-tech-expert | @qa | RESOLVED |
| Rabbit Holes | Should we add a JS-level FFI smoke test for `socket.broadcast.emit()` to catch Socket.io version incompatibilities at the FFI layer? | @qa | @web-tech-expert | RESOLVED |
| Rabbit Holes | Should the DoD require both positive and negative delivery assertions (proving correct delivery AND non-delivery to excluded clients)? | @qa | @web-tech-expert | RESOLVED |
| No-Gos | Would deferring room membership queries and `disconnecting` event block real use cases, or can app-level state tracking suffice? | @web-tech-expert | @external-user | RESOLVED |
| No-Gos | Is the intended pattern for `emitTo` private messaging to stash `NamespaceHandle` values in a `Ref (Map UserId (NamespaceHandle ns))`? Should docs make handle storage explicit? | @external-user | @web-tech-expert | RESOLVED |
| No-Gos | What happens when `emitTo` is called with a `NamespaceHandle` for a disconnected client? Silent no-op or should there be a success/failure variant? | @external-user | @web-tech-expert | RESOLVED |
| No-Gos | `emitTo` and `broadcastExceptSender` have identical signatures -- could this lead to accidental misuse since the compiler cannot distinguish the two? | @external-user | @web-tech-expert | RESOLVED |
| Research Findings | What should PurSocket's stance be on `Effect` vs `Aff` across the entire API, given that mixing them is bad DX? How does this affect `joinRoom`/`leaveRoom` specifically? | @web-tech-expert | @architect | RESOLVED |
| Definition of Done | Should the chat example also add a private messaging feature (using `emitTo`) beyond the `broadcastExceptSender` update? | @web-tech-expert | @user | RESOLVED |

---

*Drafted by @web-tech-expert on 2026-02-04*
