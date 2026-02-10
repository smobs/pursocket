---
name: "Room-Scoped Broadcast and Client Room Joining"
status: refining
drafter: "@web-tech-expert"
contributors: ["@web-tech-expert", "@architect", "@purescript-specialist", "@external-user", "@product-manager"]
open_questions: 7
created: "2026-02-04"
appetite: "6 weeks"
---

# Pitch: Room-Scoped Broadcast and Client Room Joining

## Problem

PurSocket shipped basic room support in the "emitTo and Room Support" cycle: `joinRoom`, `leaveRoom`, and `broadcastToRoom` (socket-level, excluding sender). Three gaps remain that block common real-time application patterns:

**1. No namespace-level room broadcast.** The existing `broadcastToRoom` uses `socket.to(room).emit()`, which operates from a `NamespaceHandle` and automatically excludes the sender. There is no way to broadcast to a room from the server level (`io.of(ns).to(room).emit()`), which does NOT exclude any sender because there is no "sender" at the namespace level. This matters for server-initiated events where no client triggered the broadcast -- timers ("game starting in 5 seconds"), scheduled jobs ("market closing"), admin actions ("room is being archived"). Today, the workaround is to call `broadcastToRoom` from an arbitrary handle and then separately `emitTo` the handle's own client, which is fragile and semantically wrong.

**2. No client-side room joining pattern.** Socket.io rooms are a server-only concept -- clients cannot call `socket.join()` directly. The only way for a client to join a room is to emit a c2s event that the server handles by calling `joinRoom`. Every PurSocket application that uses rooms must reinvent this request/response handshake: define a protocol event, write a server handler, call `joinRoom`, optionally confirm back to the client. This is boilerplate that every room-using application repeats. The question is whether PurSocket should provide a built-in pattern for this or document the idiomatic approach and leave it to application code.

**3. No `socket.rooms` query.** The server has no way to ask "which rooms is this socket currently in?" Socket.io exposes `socket.rooms` as a `Set<string>` on the server side. Without this, the server must maintain shadow state in a `Ref (Map SocketId (Set RoomName))` -- which works (as the external-user confirmed in the prior cycle), but is error-prone when room membership changes through multiple code paths. Exposing `socket.rooms` provides a canonical, always-consistent source of truth.

**Who has this problem:** Any developer building a real-time application with room semantics beyond the basic "broadcast to room excluding sender" pattern. Game servers with server-initiated broadcasts, chat applications where clients choose rooms, and collaborative editing where the server needs to inspect room membership are all blocked or forced into workarounds.

**Audit references:** N6 (namespace `.to(room)`), N7 (namespace `.except(room)`), R4 (`io.to(room).emit()`), SK3 (`socket.rooms`).

## Appetite

**Time budget:** 6 weeks

The three features have clear priorities:

1. **Namespace-level room broadcast** (`broadcastToRoomFromServer`) -- The most impactful gap. Pure FFI + PureScript wrapper, no protocol design needed. Should take 1-2 weeks including tests.
2. **`socket.rooms` query** (`getRooms`) -- Small, well-defined. One FFI function reading a JS `Set` and converting to a PureScript `Set String`. Should take less than 1 week.
3. **Client-side room joining pattern** -- The most design-intensive feature. Requires deciding between a built-in protocol pattern vs. documentation-only approach. May consume 2-3 weeks depending on the design direction chosen.

**Circuit breaker:** If the client-side room joining design becomes a rabbit hole (more than 2 weeks of shaping without convergence), cut it to documentation-only: ship a well-documented example of the "emit joinRoom event, server calls joinRoom" pattern without building library-level abstractions. Features 1 and 2 ship regardless.

> **Q (@product-manager -> @user):** The pitch proposes a 6-week appetite. If Feature 3 is resolved as Direction A (documentation-only), the implementation scope is two FFI functions, two PureScript wrappers, tests, and a documentation page. The prior "emitTo and Room Support" cycle shipped 5 functions with exhaustive testing in significantly less wall time. Should the appetite be reduced to 4 weeks to reflect the actual scope, or is 6 weeks intended to absorb potential complexity from Feature 3 Directions B/C?
>
> **A:** *[pending]*
>
> -- OPEN

## Solution Sketch

### Key Elements

#### Feature 1: Namespace-Level Room Broadcast

A new server function that broadcasts to all members of a room from the `ServerSocket` (namespace) level, with no sender exclusion:

```
broadcastToRoomFromServer
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol ns
  => IsSymbol event
  => ServerSocket
  -> String
  -> payload
  -> Effect Unit
```

This maps to `io.of("/" + ns).to(room).emit(event, payload)` in Socket.io. The FFI constructs and consumes the transient `BroadcastOperator` in a single expression, consistent with the pattern documented in `/home/toby/pursocket/docs/ffi-socket-io-patterns.md`:

```js
export const primBroadcastToRoomFromServer = (io) => (ns) => (room) => (event) => (payload) => () => {
  io.of("/" + ns).to(room).emit(event, payload);
};
```

This follows the same pattern as the existing `broadcast` function: takes `ServerSocket`, needs `IsSymbol ns` for namespace path construction via `reflectSymbol`. The `ns` phantom type participates in `IsValidMsg` for protocol validation.

**Why a separate function instead of extending `broadcastToRoom`.** The existing `broadcastToRoom` takes a `NamespaceHandle` and uses socket-level semantics (excludes sender). The new function takes `ServerSocket` and uses namespace-level semantics (includes everyone in the room). These are fundamentally different Socket.io primitives (`socket.to(room).emit()` vs `io.of(ns).to(room).emit()`). Merging them into one function with a flag or sum type would obscure the delivery semantics. The naming convention follows the existing pattern: `broadcast` (namespace-level, all clients) vs `broadcastExceptSender` (socket-level, excludes sender). Similarly: `broadcastToRoomFromServer` (namespace-level, all room members) vs `broadcastToRoom` (socket-level, excludes sender from room).

> **Q (@web-tech-expert -> @architect):** The name `broadcastToRoomFromServer` is descriptive but long. Alternatives include `broadcastToRoomAll` (emphasizing "all members including sender"), `roomBroadcast` (shorter but less explicit), or keeping the existing `broadcastToRoom` for the namespace-level variant and renaming the socket-level one. The naming should be consistent with the existing `broadcast` / `broadcastExceptSender` / `broadcastToRoom` family. What naming convention best serves discoverability and prevents confusion between the two room broadcast variants?
>
> **A (@architect):** The existing module already establishes a clear naming axis: `broadcast` (namespace-level, all clients) vs `broadcastExceptSender` (socket-level, excludes sender). The room-scoped functions should follow the same axis rather than introducing a new naming dimension.
>
> I recommend **`broadcastToRoom`** for the namespace-level variant (all room members, no exclusion) and **renaming the current `broadcastToRoom` to `broadcastToRoomExceptSender`**. Reasoning:
>
> 1. **Parallel structure with the existing pair.** `broadcast` / `broadcastExceptSender` mirrors exactly to `broadcastToRoom` / `broadcastToRoomExceptSender`. The "ExceptSender" suffix is the established marker for socket-level semantics with sender exclusion. This makes the naming convention a learnable rule rather than a set of arbitrary names.
>
> 2. **The namespace-level variant is the more common semantic.** When you say "broadcast to a room," the default mental model is "everyone in the room gets the message." The sender-excluding variant is the special case that deserves the longer, qualified name. This matches Socket.io's own design where `io.to(room).emit()` is the primary room broadcast API and `socket.to(room).emit()` is the contextual variant.
>
> 3. **Rejecting the alternatives.** `broadcastToRoomFromServer` leaks an implementation detail ("from server" describes the JS API path, not the semantic). `broadcastToRoomAll` introduces "All" as a new modifier that does not appear elsewhere in the API. `roomBroadcast` breaks the `broadcastTo*` prefix convention that makes these functions discoverable via autocomplete.
>
> 4. **Addressing the @external-user's follow-up question about capability-token-based naming.** The suggestion of distinguishing by capability token (e.g., `broadcastToRoom` for `NamespaceHandle`, `broadcastToRoomFrom` for `ServerSocket`) has merit in that it encodes the source of authority. However, the capability token already appears in the type signature -- the compiler enforces which token you pass. The function name should describe the *delivery semantic* (who receives the message), not the *authority source* (where it came from). "ExceptSender" describes delivery. "FromServer" describes authority. Delivery is what matters to the developer reasoning about their application's behavior.
>
> The rename of the existing function is a breaking change, but PurSocket is pre-1.0 and the prior cycle shipped only days ago. The number of downstream consumers is effectively zero. The rename cost is one line in the export list, one function signature, and a doc comment update. Failing to rename now means living with an inconsistent naming convention permanently, because post-1.0 renames are far more expensive.
>
> Final naming family:
> - `broadcast` -- all clients in namespace (namespace-level)
> - `broadcastExceptSender` -- all clients in namespace except sender (socket-level)
> - `broadcastToRoom` -- all clients in room (namespace-level)
> - `broadcastToRoomExceptSender` -- all clients in room except sender (socket-level)
>
> Note: this rename should be included in this cycle's scope. The compatibility risk section currently says "no existing functions are modified" but this rename means one existing function is renamed. Update that section accordingly, and add the rename to the appetite estimate (trivial -- under an hour including test updates).
>
> ✓ RESOLVED

> **Q (@web-tech-expert -> @product-manager):** Should we also include `io.of(ns).except(room).emit()` (N7 in audit) for completeness? This broadcasts to everyone in the namespace EXCEPT members of a specified room. It is the namespace-level counterpart to the socket-level `socket.except(room).emit()`. Including it adds one more FFI function and PureScript wrapper with the same pattern. Excluding it keeps scope tighter. Is there a concrete use case that justifies adding it now, or should it be deferred?
>
> **A (@product-manager):** Defer it. The use cases for `except(room)` are real but niche -- scenarios like "broadcast a maintenance warning to everyone except admins" or "send updates to everyone except spectators." These appear later in application maturity, not during initial development. No developer building their first PurSocket app will reach for `except(room)` in their first week; they will reach for `broadcastToRoomFromServer` within their first day.
>
> The workaround is acceptable: maintain a complementary room structure (e.g., put non-admin users in a "general" room) and broadcast to that room instead. This is more explicit and avoids subtle confusion about "except" semantics where developers must reason about room membership to predict who receives a message.
>
> API surface discipline matters at this stage. `PurSocket.Server` is at 13 exports today; this pitch adds 2 more (Features 1 and 2), bringing it to 15. The architect question about module splitting is already on the table. Adding `except(room)` pushes to 16 and strengthens the case that we are growing the API faster than developers can absorb it. PurSocket's competitive advantage is that it is a small, learnable library -- not a comprehensive Socket.io wrapper. Every new export should clear a high bar of "developers will use this in their first real application."
>
> If the chat example or a future cycle surfaces a concrete scenario where `except(room)` would have saved significant complexity, that is the signal to add it. Adding it now on the basis of "completeness" is speculative scope -- exactly the kind of thing Shape Up's fixed appetite is designed to resist.
>
> Recommendation: **Defer N7. Do not include it in this cycle.**
>
> RESOLVED

> **Q (@architect -> @web-tech-expert):** The type signature for the namespace-level `broadcastToRoom` needs the `room` parameter typed as `String` in the PureScript wrapper. Looking at the existing room functions (`joinRoom`, `leaveRoom`, `broadcastToRoom`/`broadcastToRoomExceptSender`), the room parameter is also `String`. There is currently no `RoomName` newtype anywhere in the codebase. The `socketId` function returns `String`, and `joinRoom` takes `String` -- nothing prevents `joinRoom handle (socketId handle)` which would be semantically wrong (joining a room named after your own socket ID, which Socket.io already auto-joins). A newtype would catch this at compile time. This concern was independently raised by @purescript-specialist as well (see Rabbit Holes section). Should this cycle introduce a `RoomName` newtype, and if so, should it be applied retroactively to `joinRoom` and `leaveRoom` (which would be a breaking change to two existing functions)?
>
> **A:** *[pending]*
>
> -- OPEN

#### Feature 2: `socket.rooms` Query

A new server function that returns the set of rooms a socket is currently in:

```
getRooms :: forall ns. NamespaceHandle ns -> Effect (Set String)
```

Socket.io's `socket.rooms` is a JavaScript `Set<string>`. The FFI must convert this to a PureScript-compatible representation. There are two conversion strategies:

**Option A: Convert in FFI to Array, then to Set in PureScript.** The FFI returns `Array String` (using `Array.from(socket.rooms)`), and the PureScript wrapper converts to `Set String` via `Set.fromFoldable`. This is the simplest FFI (no PureScript data structure construction in JS) but performs two allocations.

**Option B: Return Array directly.** The function returns `Effect (Array String)` and the caller converts to `Set` if needed. Simpler type, but loses the semantic that rooms are unique (a Set conveys this, an Array does not).

My recommendation is Option A. The double allocation is negligible (room sets are typically small, under 100 entries), and `Set String` correctly communicates the uniqueness invariant. The FFI is a one-liner:

```js
export const primGetRooms = (socket) => () => Array.from(socket.rooms);
```

The PureScript wrapper:

```purescript
getRooms :: forall ns. NamespaceHandle ns -> Effect (Set String)
getRooms handle = do
  arr <- primGetRooms (socketRefFromHandle handle)
  pure (Set.fromFoldable arr)
```

Note: `socket.rooms` always includes the socket's own ID as a room (Socket.io auto-joins every socket to a room matching its ID). The doc comment should mention this, as it may surprise developers who expect only explicitly-joined rooms.

> **Q (@web-tech-expert -> @purescript-specialist):** The `socket.rooms` property is a JS `Set` which is a live reference -- mutations to it would affect Socket.io's internal state. By converting to `Array.from()` in the FFI, we create a snapshot copy, which is safe. However, `socket.rooms` is documented as read-only in Socket.io. Is there any concern about reading it inside an `Effect` (which implies the value may change between reads) vs. making it a pure function like `socketId`? The value CAN change (rooms are joined/left over time), so `Effect` seems correct, but I want to confirm the PureScript idiom here.
>
> **A (@purescript-specialist):** `Effect (Set String)` is correct and `socketId` is the exception, not the rule. The distinction comes down to referential transparency. `socket.id` is assigned once at connection time and never changes for the lifetime of the handle -- it is genuinely pure, so modeling it as `NamespaceHandle ns -> String` (no `Effect`) is honest. The compiler can safely inline, deduplicate, or reorder calls to `socketId` without changing program behavior.
>
> `socket.rooms` is fundamentally different: calling `getRooms` before `joinRoom handle "r1"` and after will produce different results. That is the textbook definition of a side-effectful read. Wrapping it in `Effect` is not just "correct" -- omitting `Effect` would be a soundness violation. A pure `getRooms` would let the compiler CSE (common subexpression eliminate) multiple calls into one, silently returning stale data. In PureScript, if calling a function twice at different program points can produce different values, it must live in `Effect` (or `Aff`). No exceptions.
>
> The `Array.from()` snapshot in the FFI is the right call. It severs the reference to Socket.io's live `Set`, so the returned PureScript `Set String` is an immutable value that cannot be invalidated by later room changes. This is the "parse, don't validate" principle applied to FFI boundaries: cross the JS/PS boundary by converting mutable foreign data into an immutable PureScript value, then return that value inside `Effect` to signal that the read itself is effectful.
>
> One minor note on the proposed FFI: the `primGetRooms` foreign import should be typed `SocketRef -> Effect (Array String)`, not `SocketRef -> Array String`, since the thunk `() => ...` in the JS makes it effectful. The pitch's JS snippet already does this correctly with the `() =>` wrapper.
>
> Confirmed: `Effect (Set String)` is the idiomatic PureScript type. Do not make this pure.
>
> RESOLVED

> **Q (@web-tech-expert -> @qa):** What test coverage does `getRooms` need? I would propose: (1) After `joinRoom handle "r1"`, `getRooms handle` contains "r1" and the socket's own ID. (2) After `leaveRoom handle "r1"`, `getRooms handle` no longer contains "r1" but still contains the socket's own ID. (3) A freshly connected socket's `getRooms` contains only its own ID. Are there edge cases I am missing?
>
> **A:** *[pending]*
>
> -- OPEN

#### Feature 3: Client-Side Room Joining Pattern

This is the most design-intensive feature because Socket.io rooms are fundamentally a server-side concept. Clients cannot call `socket.join()`. Any "client joins a room" flow requires:

1. Client emits a c2s event (e.g., `"joinRoom"`) with the room name
2. Server handler receives the event, calls `joinRoom` on the handle
3. (Optional) Server confirms back to the client via s2c event or acknowledgement

There are three possible design directions:

**Direction A: Documentation-only.** Ship no library code. Instead, provide a well-documented example showing the idiomatic pattern: define `joinRoom`/`leaveRoom` as c2s `Call` events in the protocol, write server handlers that call `joinRoom`/`leaveRoom`, and use the ack response to confirm. This is the zero-abstraction approach -- every app writes the glue code, but it is explicit and flexible (apps can add authorization, rate limiting, room-exists checks, etc.).

**Direction B: Convention helpers.** Provide helper functions that assume a conventional protocol shape. For example, if the protocol includes events named `"_joinRoom"` and `"_leaveRoom"` with payload `{ room :: String }` and response `{ ok :: Boolean }`, PurSocket could provide `setupRoomHandlers` on the server and `requestJoinRoom` / `requestLeaveRoom` on the client that wire up the full flow. The underscore prefix signals these are PurSocket conventions. This reduces boilerplate but constrains the protocol shape.

**Direction C: Higher-order pattern.** Provide a server-side function like `onRoomJoinRequest` that takes a `NamespaceHandle`, an event name, and an authorization callback, and wires up the join-with-confirmation pattern internally. The client side uses the normal `call` function. This is more flexible than Direction B (any event name, custom auth) but still provides the wiring.

My recommendation from a web technology perspective is **Direction A** (documentation-only) for this cycle, with the following reasoning:

1. **Every real application needs custom authorization for room joins.** A chat app checks if the user is allowed in the room. A game app checks if the game is accepting players. A collaboration app checks document permissions. The authorization logic is the hard part, not the `joinRoom` call. A library-level abstraction that skips authorization is dangerous (developers use the easy path and forget auth), and one that includes it is necessarily complex (callback-based auth with error handling).

2. **The boilerplate is small.** The full server-side pattern is roughly 5 lines: `onCallEvent @Protocol @"chat" @"joinRoom" handle \req -> do { joinRoom handle req.room; pure { ok: true } }`. This is not the kind of boilerplate that justifies a library abstraction.

3. **PurSocket's value proposition is type safety, not code generation.** The protocol type already ensures the client sends the right payload shape for the join request and receives the right response shape. The type system is doing its job. The `joinRoom` call is application logic, not protocol logic.

> **Q (@web-tech-expert -> @user):** Given the three design directions above, which approach best fits the project's goals? Direction A (documentation-only) is lowest risk and ships fastest. Direction B (convention helpers) reduces boilerplate but constrains protocol design. Direction C (higher-order pattern) is flexible but more complex. My web-tech perspective favors Direction A, but this is ultimately a product/scope decision. Would you be comfortable shipping this cycle with documentation-only for client room joining, knowing that a library-level abstraction could be added in a future cycle if the pattern proves painful?
>
> **A:** *[pending]*
>
> -- OPEN

> **Q (@web-tech-expert -> @external-user):** If PurSocket ships documentation-only for client room joining (Direction A), would the documented pattern be sufficient for your use cases? Specifically: would you expect the protocol definition to include explicit `joinRoom`/`leaveRoom` events, or would you prefer a different approach (e.g., query parameters on namespace connection, middleware-based room assignment)?
>
> **A (@external-user):** Yes, Direction A is sufficient, and I would strongly prefer it over the alternatives. Here is my reasoning from the perspective of someone who would actually ship a product on top of PurSocket.
>
> **Explicit `joinRoom`/`leaveRoom` as `Call` events in the protocol is the right pattern.** I looked at the existing chat example's `setNickname` Call event (`Call { nickname :: String } { ok :: Boolean, reason :: String }`) and immediately understood how room joining would work by analogy. The pattern would be:
>
> ```
> type MyProtocol =
>   ( game ::
>       ( c2s ::
>           ( joinRoom  :: Call { room :: String } { ok :: Boolean, reason :: String }
>           , leaveRoom :: Call { room :: String } { ok :: Boolean }
>           , ...
>           )
>       , s2c :: ( ... )
>       )
>   )
> ```
>
> On the server:
>
> ```
> onCallEvent @MyProtocol @"game" @"joinRoom" handle \req -> do
>   -- my authorization logic here
>   joinRoom handle req.room
>   pure { ok: true, reason: "" }
> ```
>
> This is roughly 5 lines of server code, as the pitch notes. That is not boilerplate I need a library to eliminate. It is application logic where the interesting part -- authorization, validation, room-exists checks -- varies completely between my projects.
>
> **Why I prefer this over Direction B (convention helpers):** If PurSocket introduced underscore-prefixed `_joinRoom` / `_leaveRoom` convention events, I would immediately have two problems. First, my protocol definition would contain events I did not write, which breaks the "protocol is the single source of truth" principle that drew me to PurSocket in the first place. Second, if `setupRoomHandlers` does not support my authorization model (and it will not -- every app is different), I have to bypass the helper and write the same 5 lines anyway, but now there is a dead convention cluttering my protocol. Direction B is the kind of "framework magic" that makes me reach for escape hatches within the first week.
>
> **Why I prefer this over Direction C (higher-order pattern):** Direction C is better than B because it does not constrain the protocol shape, but `onRoomJoinRequest` is still a specialized abstraction that I have to learn, understand the edge cases of, and then debug when it interacts with my middleware. I would rather compose `onCallEvent` + `joinRoom` myself. I already know both of those functions. The composition is trivial.
>
> **Query parameters on namespace connection would NOT work for me.** Most of my use cases involve a client that joins multiple rooms dynamically after connecting. A game lobby where the player browses available games and clicks "join" is the common case. Baking room assignment into the connection handshake only works for the narrow case where a client belongs to exactly one room for the lifetime of the connection. That is not the general case.
>
> **Middleware-based room assignment is orthogonal.** Socket.io middleware runs at connection time and is useful for authentication (verifying a JWT, attaching user data to the handshake). It is the wrong layer for room management, which is a dynamic, ongoing concern. I would use middleware for auth and protocol events for room operations.
>
> **What the documentation should include:** A complete, copy-pasteable example showing: (1) the protocol definition with `joinRoom`/`leaveRoom` as `Call` events, (2) the server handler with a placeholder authorization check, (3) the client-side `call` invocation, and (4) handling the response (success vs. rejection). The chat example's `setNickname` is 80% of the way there already. A "rooms" section in the Getting Started guide that mirrors that pattern would be enough.
>
> **One thing I would want that is not in the pitch:** The documentation should explicitly show the combined pattern of `joinRoom` + `broadcastToRoom` together. Joining a room is not useful in isolation -- the developer wants to see "client requests to join room, server authorizes, server joins socket to room, server broadcasts to room that a new member arrived, other room members see the notification." The full lifecycle, not just the join call.
>
> RESOLVED

### No-Go Items

Explicitly out of scope for this cycle:

- **Type-level room names.** Rooms remain runtime `String` values. No `IsSymbol` constraints on room names. No compile-time room validation. Same stance as the prior cycle.
- **Modifier chaining / builder pattern.** No composable `.to().except().emit()` chain. Each delivery mode is a standalone function. Same stance as the prior cycle.
- **`io.in(room).fetchSockets()`** (R6 in audit). Querying which sockets are in a room. This is an admin/monitoring feature. Use application-level state or defer to a future cycle.
- **Bulk room operations.** No `socketsJoin`, `socketsLeave`, `disconnectSockets` by room (R7, R8, R9). Admin utilities.
- **Multi-room targeting.** Socket.io supports `socket.to("room1").to("room2").emit()` for broadcasting to the union of multiple rooms. This requires the chaining builder pattern, which is explicitly excluded. Applications needing multi-room broadcast can call the function once per room.
- **`disconnecting` event** (SE3). The event that fires while the socket is still in its rooms, before `disconnect`. Useful for cleanup but adds scope. Deferred.
- **Room-scoped `Call` (acknowledgement).** Broadcasting an ack-expecting event to a room has complex semantics (multiple responses). Out of scope.
- **Redis adapter `Aff` variants.** `joinRoom`/`leaveRoom` remain `Effect Unit`. No `Aff` variants for async adapters. Same architectural stance as the prior cycle.

## Rabbit Holes

Watch out for:

- **Naming collision between room broadcast variants.** The existing `broadcastToRoom` (socket-level, excludes sender) and the new namespace-level variant must have clearly distinct names. Choosing a bad name that confuses which function includes/excludes the sender will cause subtle delivery bugs in application code. The naming must be resolved in shaping, not discovered during build. This is flagged as an open question above.

- **`socket.rooms` auto-includes socket ID.** Every socket in Socket.io is automatically a member of a room matching its own `socket.id`. Developers querying `getRooms` will see this extra entry and may be confused. The doc comment must explain this. If the function filters out the socket's own ID, it breaks the fidelity with Socket.io's behavior. If it includes it, developers must filter manually. My recommendation is to include it (match Socket.io behavior) and document it clearly.

- **Client room joining authorization patterns.** If Direction B or C is chosen for client room joining, the authorization callback design could become a rabbit hole. What does the callback receive (room name, handle, handshake data)? What does it return (boolean, result type, Effect/Aff)? How does rejection communicate back to the client? Each of these questions spawns sub-questions. Direction A avoids this entirely.

- **JS `Set` to PureScript `Set` conversion performance.** For `getRooms`, converting via `Array.from()` then `Set.fromFoldable` is O(n log n) in PureScript's ordered `Set`. For typical room counts (1-20), this is negligible. But if an application puts sockets in thousands of rooms (unlikely but possible), this could matter. The escape hatch is exposing an `Array`-returning variant alongside the `Set`-returning one.

> **Q (@web-tech-expert -> @architect):** The `broadcastToRoomFromServer` FFI pattern (`io.of(ns).to(room).emit()`) chains two transient operations: `io.of(ns)` returns a `Namespace` object (stable, can be cached), and `.to(room)` returns a transient `BroadcastOperator` (must not be cached). In the FFI, we construct the full chain in one expression, which is correct. But should we consider caching the `Namespace` object for performance in hot paths (e.g., a game server broadcasting to a room 60 times per second)? Socket.io internally caches namespace objects, so `io.of(ns)` on repeated calls returns the same object. The FFI calling `io.of(ns)` every time is a hash lookup, not an allocation. Is this worth documenting, or is it obvious enough to skip?
>
> **A (@architect):** Not worth documenting in the library itself. The question answers itself: `io.of(ns)` is internally a hash lookup returning a cached `Namespace` object (Socket.io stores namespaces in a `Map<string, Namespace>` on the `Server` instance). At 60 calls per second, this is 60 hash lookups per second -- utterly negligible compared to the actual work of broadcasting (serializing the payload and writing to each socket's transport). The cost of `io.of(ns)` is on the order of nanoseconds; the cost of the `.to(room).emit(event, payload)` that follows is on the order of microseconds to milliseconds depending on room size.
>
> Caching the `Namespace` object in PureScript-land (e.g., passing it as a parameter instead of `ServerSocket` + namespace symbol) would add API complexity for zero measurable benefit. It would also create a parallel "namespace handle for server-level operations" concept alongside the existing `NamespaceHandle` (which wraps a socket, not a namespace), which would be confusing.
>
> If this ever becomes a real performance concern (it will not), the correct optimization would be at the FFI level -- caching the namespace reference inside the JS closure -- not at the PureScript API level. But even that is unnecessary because Socket.io already does the caching internally.
>
> Add a single line to the FFI patterns doc (`/home/toby/pursocket/docs/ffi-socket-io-patterns.md`) noting that `io.of(ns)` returns a cached object, for completeness. Do not change the API design or add it to the function's doc comment -- it is an implementation detail that should not surface to users.
>
> ✓ RESOLVED

> **Q (@web-tech-expert -> @purescript-specialist):** If Direction B or C is chosen for client room joining, the protocol type would need to accommodate "built-in" events alongside application-defined events. Would this require changes to the `IsValidMsg` / `IsValidCall` machinery, or can built-in events simply be documented as "add these to your protocol definition"? The latter is simpler but means the user can forget to add them. The former means the library injects events into the protocol, which conflicts with the "protocol is the single source of truth" design principle.
>
> **A (@purescript-specialist):** The existing `IsValidMsg`/`IsValidCall` machinery would NOT need changes for either Direction B or C. Here is the analysis for each.
>
> **Direction B (convention helpers):** Helper functions like `setupRoomHandlers` and `requestJoinRoom` would use `IsValidCall` with hardcoded event name symbols (e.g., `@"_joinRoom"`). The constraint `IsValidCall protocol ns "_joinRoom" "c2s" { room :: String } { ok :: Boolean }` would appear in the type signature of `setupRoomHandlers`. This works without any changes to `IsValidCall` -- the `RowToList`-based lookup classes (`LookupNamespace`, `LookupDirection`, `LookupCallEvent`) will search the user's protocol for an event named `"_joinRoom"` with exactly that payload and response shape. If the user forgets to add it to their protocol, the compiler produces the existing custom error: "PurSocket: invalid Call event. Namespace: ... Event: _joinRoom ...". This is actually a good developer experience -- the error tells them exactly what is missing. However, the fundep (`protocol ns event dir -> payload response`) locks the payload and response types, so the user MUST define `"_joinRoom"` with exactly `Call { room :: String } { ok :: Boolean }`. Any deviation (e.g., adding a `token` field to the request) is a compile error. This rigidity is either a feature (consistency across PurSocket apps) or a problem (real apps often need custom payloads for authorization).
>
> **Direction C (higher-order pattern):** A function like `onRoomJoinRequest` that takes the event name as a type-level parameter would look like `onRoomJoinRequest :: forall @protocol @ns @event payload res. IsValidCall protocol ns event "c2s" payload res => ...`. This uses `IsValidCall` exactly as `onCallEvent` already does. Zero machinery changes. The event name and types are fully user-controlled.
>
> **The "injecting events into the protocol" alternative is a rabbit hole -- explicitly rule it out.** If the library tried to automatically merge built-in events into the user's protocol row, it would require a type-level row merge (`Union userProtocol builtinEvents mergedProtocol`) and then passing `mergedProtocol` through `IsValidMsg`/`IsValidCall`. This is technically possible using `Row.Union`, but it creates three serious problems: (1) it changes the kind signature of every function that takes the protocol type parameter, breaking the entire existing API; (2) `Row.Union` requires that labels do not overlap, so a user who happens to name their own event `"_joinRoom"` gets an obscure unification error instead of a helpful custom message from our instance chains; (3) it violates the "protocol is the single source of truth" principle -- the actual protocol the system validates against becomes an invisible merge of two sources, which is exactly the kind of implicit magic PurSocket exists to prevent.
>
> **Recommendation:** Regardless of which direction is chosen, built-in events should be "add these to your protocol definition" conventions, not injected by the library. The existing `IsValidCall` machinery handles this with no changes. The "user can forget" risk is fully mitigated by the compiler -- it produces a clear custom type error at compile time. If the project wants to make this even more ergonomic, a type alias like `type WithRoomEvents r = ("_joinRoom" :: Call { room :: String } { ok :: Boolean }, "_leaveRoom" :: Call { room :: String } { ok :: Boolean } | r)` could be provided for users to splice into their protocol's `c2s` direction. That is a documentation convenience, not a machinery change.
>
> Direction C is the cleanest from a type-system perspective because it imposes no constraints on event names or payload shapes. Direction B works but creates payload rigidity through the fundep that may frustrate applications with custom authorization requirements.
>
> RESOLVED

> **Q (@purescript-specialist -> @web-tech-expert):** The proposed type signature for `broadcastToRoomFromServer` takes `ServerSocket -> String -> payload -> Effect Unit`, where the `String` is the room name. This means the room name argument is positionally adjacent to `payload`, and both are often string-shaped in practice (e.g., `broadcastToRoomFromServer server "game-42" "Player joined"`). Unlike `broadcastToRoom` where the first argument is a `NamespaceHandle ns` (a distinct newtype that cannot be confused with a string), the new function's first non-server argument is a bare `String`. Should we consider a `RoomName` newtype wrapper to make call sites unambiguous? For example: `broadcastToRoomFromServer @AppProtocol @"game" @"tick" server (RoomName "game-42") { frame: 1 }` vs the bare string variant. The newtype has zero runtime cost after `purs-backend-es` optimization and prevents argument-swap bugs. This would also apply retroactively to `joinRoom`, `leaveRoom`, and `broadcastToRoom`, which all take bare `String` room names today. The trade-off is API churn on three existing shipped functions. Is this worth addressing now (while adding a new room function), or is the bare `String` acceptable given that room names are typically literal strings at call sites?
>
> **A:** *[pending]*
>
> -- OPEN

## Risk Assessment

**Technical risk: LOW for features 1 and 2, MEDIUM for feature 3.**

Features 1 and 2 are straightforward FFI wrappers over well-understood Socket.io primitives. The patterns are directly analogous to functions already shipped (`broadcast` for feature 1, `socketId` for feature 2's property-reading pattern). The prior cycle's process learnings confirm that when shaping is thorough, build is pure execution.

Feature 3's risk depends entirely on the design direction chosen. Direction A (documentation-only) is zero implementation risk. Directions B and C introduce protocol-level design complexity that could consume disproportionate appetite.

**Process risk: LOW.** The prior cycle demonstrated that exhaustive Q&A eliminates design ambiguity and enables clean execution. This pitch follows the same pattern. The circuit breaker on feature 3 ensures scope does not expand uncontrollably.

**Compatibility risk: LOW.** All three features are additive. No existing functions are modified. No existing types change. No breaking changes to the public API. The `ServerSocket` and `NamespaceHandle` types are unchanged. New functions are added to `PurSocket.Server`'s export list.

**Multi-process / Redis adapter risk: LOW for features 1 and 2, NOT APPLICABLE for feature 3.** `io.of(ns).to(room).emit()` goes through the adapter and works transparently in clustered deployments (documented in `/home/toby/pursocket/docs/ffi-socket-io-patterns.md`, Section 4). `socket.rooms` is a local query (no adapter involvement) -- in a Redis adapter deployment, it only returns rooms known to the local process. This is a known Socket.io limitation, not a PurSocket concern, but should be documented.

> **Q (@web-tech-expert -> @qa):** For the namespace-level room broadcast (`broadcastToRoomFromServer`), what minimum test coverage is needed? I propose: (1) Server calls `broadcastToRoomFromServer` for room "r1" -- clients in "r1" receive the message. (2) Clients NOT in "r1" do NOT receive the message. (3) The sender (if any client triggered the broadcast via a c2s event) DOES receive the message if they are in the room -- this distinguishes it from the existing `broadcastToRoom` which would exclude the sender. Test (3) is the critical differentiator. Are there other scenarios?
>
> **A:** *[pending]*
>
> -- OPEN

> **Q (@web-tech-expert -> @architect):** Adding `broadcastToRoomFromServer` and `getRooms` to the `PurSocket.Server` export list brings the module to 14 exported functions. Is this approaching a size where we should consider splitting into sub-modules (e.g., `PurSocket.Server.Room` for room-specific functions)? The prior cycle's `emitTo` and `broadcastExceptSender` additions brought it from 7 to 12 exports. At what point does the module warrant restructuring?
>
> **A (@architect):** Do not split yet. 15 exports (after adding `broadcastToRoom` and `getRooms` under the renamed scheme) is well within the comfort zone for a single cohesive module. Here is the structured analysis:
>
> **The export count is misleading.** Of the 15 exports, 3 are lifecycle/infrastructure (`createServer`, `createServerWithPort`, `closeServer`), 2 are connection lifecycle (`onConnection`, `onDisconnect`), 1 is identity (`socketId`), 2 are event handlers (`onEvent`, `onCallEvent`), and 7 are delivery/room functions (`broadcast`, `broadcastExceptSender`, `emitTo`, `joinRoom`, `leaveRoom`, `broadcastToRoom`, `broadcastToRoomExceptSender`, `getRooms`). The module has a single responsibility: "server-side Socket.io operations." Splitting it would create modules with 3-5 exports each, which is splitting for the sake of splitting.
>
> **The right heuristic is not export count but import confusion.** A module should be split when a developer importing it is surprised by what they find, or when they must import from multiple modules to accomplish a single task. Today, a developer writing a server handler imports `PurSocket.Server` and gets everything they need. If room functions lived in `PurSocket.Server.Room`, every room-using developer would need two imports (`PurSocket.Server` for `onConnection`/`onEvent` and `PurSocket.Server.Room` for `joinRoom`/`broadcastToRoom`). This is strictly worse for the common case.
>
> **When to revisit.** Split when one of these triggers occurs: (a) the module exceeds 25 exports, (b) a clearly independent concern emerges (e.g., middleware support that has its own types and patterns), or (c) the FFI file grows large enough that two developers need to work on different parts simultaneously. None of these apply today.
>
> **One concrete action.** Group the exports in the module header by concern (lifecycle, handlers, delivery, rooms) with comment separators. This gives developers visual structure without the import tax of separate modules. The current export list in `/home/toby/pursocket/src/PurSocket/Server.purs` is already roughly grouped but lacks explicit separators.
>
> Recommendation: **Keep `PurSocket.Server` as a single module. Add comment grouping to the export list. Revisit at 25+ exports or when middleware lands.**
>
> ✓ RESOLVED

> **Q (@architect -> @web-tech-expert):** The compatibility risk section states "No existing functions are modified" and "No breaking changes to the public API." If the naming resolution above is accepted (renaming `broadcastToRoom` to `broadcastToRoomExceptSender`), this is technically a breaking change. The risk section should be updated to acknowledge this rename and explain why it is acceptable (pre-1.0, zero downstream consumers, naming consistency justification). Should the drafter update this section before the pitch moves to bet review?
>
> **A:** *[pending]*
>
> -- OPEN

## Open Questions

### Team Questions
| Section | Question | Asker | Assignee | Status |
|---------|----------|-------|----------|--------|
| Solution (Feature 1) | What naming convention for the namespace-level room broadcast variant best prevents confusion with the existing socket-level `broadcastToRoom`? | @web-tech-expert | @architect | RESOLVED |
| Solution (Feature 1) | Should `io.of(ns).except(room).emit()` (N7) be included for completeness, or deferred? | @web-tech-expert | @product-manager | RESOLVED |
| Solution (Feature 1) | Should this cycle introduce a `RoomName` newtype to prevent `String` confusion between room names and socket IDs? (raised independently by @architect and @purescript-specialist) | @architect, @purescript-specialist | @web-tech-expert | OPEN |
| Solution (Feature 1) | From a user's perspective, naming based on capability token vs delivery semantic -- which is clearer? (Subsumed by naming resolution: delivery semantic wins, see @architect answer above.) | @external-user | @architect | RESOLVED |
| Solution (Feature 2) | Is `Effect (Set String)` the correct return type for `getRooms`, or should it be pure like `socketId`? | @web-tech-expert | @purescript-specialist | RESOLVED |
| Solution (Feature 2) | What test coverage does `getRooms` need beyond join/leave/fresh-socket scenarios? | @web-tech-expert | @qa | OPEN |
| Solution (Feature 3) | Which design direction for client room joining: A (documentation-only), B (convention helpers), or C (higher-order pattern)? | @web-tech-expert | @user | OPEN |
| Solution (Feature 3) | Is the documented "emit joinRoom event, server calls joinRoom" pattern sufficient for real use cases? | @web-tech-expert | @external-user | RESOLVED |
| Solution (Feature 3) | Should the Direction A documentation show the full room lifecycle (join + broadcast + notification)? | @external-user | @web-tech-expert | OPEN |
| Rabbit Holes | Is `io.of(ns)` namespace caching worth documenting for hot-path performance, or is it obvious? | @web-tech-expert | @architect | RESOLVED |
| Rabbit Holes | Would built-in room-join events require changes to `IsValidMsg`/`IsValidCall`, or can they be "add to your protocol" conventions? | @web-tech-expert | @purescript-specialist | RESOLVED |
| Risk Assessment | What test scenarios differentiate `broadcastToRoomFromServer` (includes sender) from `broadcastToRoom` (excludes sender)? | @web-tech-expert | @qa | OPEN |
| Risk Assessment | At 14 exports, should `PurSocket.Server` be split into sub-modules (e.g., `PurSocket.Server.Room`)? | @web-tech-expert | @architect | RESOLVED |
| Risk Assessment | Should the compatibility risk section be updated to reflect the `broadcastToRoom` rename? | @architect | @web-tech-expert | OPEN |
| Appetite | If Feature 3 goes Direction A, should the appetite be reduced to 4 weeks? | @product-manager | @user | OPEN |

### User Decisions
| Section | Question | Asker | Status |
|---------|----------|-------|--------|
| Solution (Feature 3) | Which design direction for client room joining? (A/B/C) | @web-tech-expert | OPEN |

---

*Drafted by @web-tech-expert on 2026-02-04*
