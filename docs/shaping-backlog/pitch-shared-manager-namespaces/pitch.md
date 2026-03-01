---
name: "Shared Manager for Namespace Connections"
status: refining
drafter: "@web-tech-expert"
contributors: ["@web-tech-expert", "@architect", "@qa", "@purescript-specialist", "@external-user"]
open_questions: 0
created: "2026-03-01"
appetite: "3-4 hours"
---

# Pitch: Shared Manager for Namespace Connections

## Problem

`joinNs` creates a **completely independent Socket.io connection** for each namespace. This is wrong.

### What happens today

```javascript
// Client.js — primJoin
export const primJoin = (baseSocket) => (ns) => () => {
  const baseUrl = baseSocket.io.uri;
  return io(baseUrl + "/" + ns);  // <-- new io() call = new Manager + new transport
};
```

Each `io()` call creates a fresh `Manager` (which owns the Engine.IO transport) and a fresh `Socket`. A PurSocket client that joins two namespaces opens **three independent WebSocket connections** to the server:

```
connect "http://localhost:3000"        →  WebSocket #1 (default namespace "/")
joinNs @"lobby" socket                 →  WebSocket #2 ("/lobby")
joinNs @"game_player" socket           →  WebSocket #3 ("/game_player")
```

### How Socket.io is designed to work

Socket.io namespaces are a **multiplexing** mechanism. Multiple namespaces share a single underlying transport (one WebSocket). The `Manager` owns the transport; `Socket` instances for each namespace share the Manager:

```
Manager (one WebSocket)
  ├── Socket "/lobby"
  ├── Socket "/game_player"
  └── Socket "/game_controller"
```

The standard way to join a namespace on an existing connection is:

```javascript
const manager = baseSocket.io;        // get the Manager from any socket
const nsSocket = manager.socket("/lobby");  // new Socket on SAME transport
```

### Why this matters

**1. Transport blip recovery is broken across namespaces.**

When a phone loses WiFi and Socket.io auto-reconnects, the Manager reconnects its transport and all child sockets reconnect together, atomically. With the current PurSocket implementation, each namespace reconnects independently on its own schedule. A client monitoring the base socket for reconnection has no way to know when the namespace sockets have reconnected — they're separate Managers.

This is actively causing bugs in Whispers in the Mist. After a WiFi blip, the base socket reconnects and the app hides the "Connection lost" overlay, but the game namespace sockets haven't reconnected yet. The game appears recovered but is silently broken — moves and state syncs are dropped.

> **Q (@external-user -> @web-tech-expert):** The Whispers in the Mist scenario is exactly the kind of bug I would hit. But after this fix, what is the recommended pattern for connection status UI? Currently `onConnect` and `onDisconnect` take a bare `SocketRef`, not a `NamespaceHandle`. If I am monitoring the base socket for "connection lost" overlay, and reconnection is now atomic across all namespaces, can I rely on the base socket's `onConnect` as the single source of truth? Or should I still register `onConnect` on every namespace socket? The "What consumers need to know" section says to register `onConnect` on each namespace's `SocketRef` for re-identification, but it does not clarify whether the base socket's `onConnect` is sufficient for UI state.
>
> **A (@web-tech-expert):** Yes, the base socket's `onConnect`/`onDisconnect` is sufficient as the single source of truth for UI state (show/hide "Connection lost" overlay). Here is why: with a shared Manager, when the transport drops, all namespace sockets disconnect simultaneously, and when the Manager reconnects the transport, all namespace sockets reconnect in the same event loop tick. The base socket (default namespace "/") is one of those sockets, so its `connect`/`disconnect` events reflect the shared transport state. However, you still need per-namespace `onConnect` for one purpose: **re-identification**. After a transport blip, each namespace socket gets a new `socket.id` on the server. If your server-side logic maps socket IDs to game players or user sessions, you need to re-emit an auth/identity event on each namespace after reconnect. The base socket's `onConnect` tells you the transport is back; per-namespace `onConnectNs` (new wrapper, see Solution section) tells you that specific namespace is ready to re-identify. Recommended pattern: use base socket `onDisconnect` to show overlay, base socket `onConnect` to hide overlay, and per-namespace `onConnectNs` to re-emit identity events.
>
> -- RESOLVED

**2. Three WebSockets instead of one.**

Every PurSocket client opens N+1 WebSocket connections (base + one per namespace). This wastes file descriptors on the server, triples the TLS handshake cost, and makes mobile battery usage worse. For a phone-based party game with 9 players, each joining 2-3 namespaces, the server handles ~30 WebSocket connections instead of ~10.

**3. Connection state recovery can't work.**

Socket.io's `connectionStateRecovery` (v4.6+) preserves session state across reconnections — room memberships, `socket.data`, buffered events. It works by tying recovery to the Manager's session ID. With separate Managers per namespace, each namespace has its own independent recovery window. If PurSocket ever wants to support connection state recovery, the shared Manager is a prerequisite.

**4. Auth/middleware runs per-Manager, not per-namespace.**

Socket.io's `io.use()` middleware runs once per Manager connection, not per namespace socket. With separate Managers, auth middleware runs 3 times — once per connection. With a shared Manager, it runs once.

## Appetite

3-4 hours. Scope breakdown:

- FFI change to `primJoin` in Client.js: 5 minutes (one line)
- `onConnectNs` / `onDisconnectNs` wrappers in Client.purs: 30 minutes
- Multi-namespace integration test: 45 minutes
- Namespace-disconnect-isolation test: 30 minutes
- Documentation updates (this pitch's "What consumers need to know" text becomes the basis for CHANGELOG/migration notes): 30 minutes
- Manual verification and edge-case poking: 30 minutes
- Buffer for unexpected issues: 30 minutes

The original "1-2 hours" estimate assumed no new PureScript code and trivial testing. Reviewer feedback correctly identified that the `onConnectNs`/`onDisconnectNs` wrappers are mandatory for the pitch's own guidance to work, and that the multi-namespace test is the only way to verify the core behavioral claim. Both are small additions, but they bring the realistic total to 3-4 hours.

## Solution

### FFI change (Client.js)

Replace `io(baseUrl + "/" + ns)` with `baseSocket.io.socket("/" + ns)`:

```javascript
// Before:
export const primJoin = (baseSocket) => (ns) => () => {
  const baseUrl = baseSocket.io.uri;
  return io(baseUrl + "/" + ns);
};

// After:
export const primJoin = (baseSocket) => (ns) => () => {
  return baseSocket.io.socket("/" + ns);
};
```

`baseSocket.io` is the `Manager` instance (every Socket.io socket exposes its Manager via `.io`). `manager.socket("/ns")` creates a namespace socket that shares the Manager's transport. This is the documented Socket.io API for namespace multiplexing.

> **Q (@architect -> @web-tech-expert):** I verified the FFI change against the actual code at `/home/toby/pursocket/src/PurSocket/Client.js` (lines 9-15). The one-line change is correct. One note: `manager.socket(nsp, opts)` accepts an optional second `opts` argument for per-socket options (`auth`, etc.). The current `io(baseUrl + "/" + ns)` call implicitly uses default options. After the change, per-namespace socket options would need to be passed via `manager.socket("/ns", { auth: ... })`. The pitch's rabbit hole section correctly defers connection options, but the future path for per-namespace auth changes: it will go through `manager.socket()`'s second argument, not through a separate `io()` call. This is not a blocker but is relevant context for whoever implements per-namespace auth later. To answer @external-user's question above: adding an `opts` parameter to `primJoin` later is a compatible extension -- just add one more curried argument to the FFI function (`(baseSocket) => (ns) => (opts) => () => ...`) and update the PureScript foreign import accordingly. No redesign needed.
>
> Also: the `io` import in `Client.js` (line 4: `import { io } from "socket.io-client"`) is still needed by `primConnect` (line 7) and must not be removed. After this pitch, `io()` is used exactly once (for the initial connection in `primConnect`), which is the correct usage pattern: `io()` for bootstrap, `manager.socket()` for additional namespaces.
>
> -- RESOLVED (informational, no action needed)

> **Q (@external-user -> @web-tech-expert):** With a shared Manager, the connection options passed to the initial `io(url)` call via `connect` now implicitly apply to all namespace sockets. In multi-tenant apps where each namespace represents a different permission scope, per-namespace auth tokens are common. Socket.io supports `manager.socket("/ns", { auth: ... })` for per-namespace auth. The proposed FFI change does not pass any options to `socket()`. Can you confirm that adding an options parameter to `primJoin` later is a compatible extension (just adding a second arg), not a redesign? I want assurance this change does not lock consumers out of per-namespace options in the future.
>
> **A (@web-tech-expert):** Confirmed. Adding per-namespace options is a compatible extension. `manager.socket(nsp, opts)` already accepts an optional second argument. To add it to PurSocket later, the FFI change is: `(baseSocket) => (ns) => (opts) => () => baseSocket.io.socket("/" + ns, opts)` and the PureScript foreign import gains one more parameter. No redesign, no breaking change. The current pitch correctly defers this to the "connection options" work tracked in the API surface audit. This change does not lock anyone out.
>
> -- RESOLVED

### PureScript side

**Core FFI:** No changes. `primJoin` still takes a `SocketRef` and returns a `SocketRef`. The `NamespaceHandle` wrapping is unchanged. The type signatures are identical. All existing `emit`, `call`, `onMsg`, `onConnect`, `onDisconnect` calls work the same way — they operate on the `Socket` object, which has the same API regardless of whether it shares a Manager or has its own.

> **Q (@architect -> @web-tech-expert):** I verified the "No changes" claim against the actual PureScript source. The `joinNs` function at `/home/toby/pursocket/src/PurSocket/Client.purs` lines 96-105 calls `primJoin baseSocket nsStr` and wraps the result with `mkNamespaceHandle`. Since `primJoin` retains the FFI type `SocketRef -> String -> Effect SocketRef`, and `manager.socket("/ns")` returns a Socket object (same JS type as what `io()` returns), the PureScript wrapper is genuinely unchanged. The `NamespaceHandle` phantom types, `IsValidMsg`/`IsValidCall` constraints, and all type-level machinery at `/home/toby/pursocket/src/PurSocket/Framework.purs` are unaffected because they operate on the `NamespaceHandle`/`SocketRef` abstraction, not on any Manager-level concept. Confirmed: no PureScript changes required.
>
> -- RESOLVED (confirmed)

> **Q (@purescript-specialist -> @web-tech-expert):** I have independently verified the "no PS changes" claim. Confirming @architect's findings with additional depth on the FFI boundary and type-level concerns:
>
> **Effect wrapping is correct.** The FFI thunk `() => baseSocket.io.socket("/" + ns)` properly defers the side-effectful `manager.socket()` call. The Manager is mutable JS state, but PureScript never observes it -- it only sees the `SocketRef` output. Each `joinNs` call produces a fresh `SocketRef` wrapped in Effect, consistent with PureScript's Effect semantics.
>
> **No type-level machinery is affected.** The `IsValidMsg`/`IsValidCall` constraint chains in `Framework.purs` walk `RowToList`s to validate namespace/direction/event. They operate entirely through phantom types on `NamespaceHandle` and `reflectSymbol` for runtime event names. The Manager is invisible to the type system. The `SocketRef` abstraction (`foreign import data SocketRef :: Type`) is completely opaque -- no PureScript code inspects `.io` or assumes anything about Manager ownership.
>
> -- RESOLVED (confirmed independently)

**New wrappers: `onConnectNs` and `onDisconnectNs`.** Three reviewers (@external-user, @architect, @purescript-specialist) independently identified that the pitch's own "What consumers need to know" section recommends registering `onConnect` on namespace sockets, but the only way to do so currently requires importing `socketRefFromHandle` from `PurSocket.Internal` -- a module explicitly marked as not public API. This pitch includes adding two trivial wrappers to `PurSocket.Client`:

```purescript
-- | Register a callback that fires when a namespace socket connects.
-- | Use this for re-identification after transport recovery.
onConnectNs :: forall protocol ns. NamespaceHandle protocol ns -> Effect Unit -> Effect Unit
onConnectNs handle callback = primOnConnect (socketRefFromHandle handle) callback

-- | Register a callback that fires when a namespace socket disconnects.
onDisconnectNs :: forall protocol ns. NamespaceHandle protocol ns -> (DisconnectReason -> Effect Unit) -> Effect Unit
onDisconnectNs handle callback =
  primOnDisconnect (socketRefFromHandle handle) (\reasonStr -> callback (parseDisconnectReason reasonStr))
```

These use the existing `primOnConnect`/`primOnDisconnect` FFI functions. No new JS code needed. The `socketRefFromHandle` import is already present in `Client.purs` (line 40). These wrappers are added to the module's export list.

> **Q (@external-user -> @web-tech-expert):** The "What consumers need to know" section recommends registering `onConnect` on namespace sockets via `socketRefFromHandle`. But `socketRefFromHandle` is exported from `PurSocket.Internal`, whose module doc says "is not part of the public API" and "do not depend on it directly -- its exports may change without notice." If re-identification on namespace reconnect is a recommended consumer pattern, then either `socketRefFromHandle` must be promoted to `PurSocket.Client`'s public exports, or `onConnect`/`onDisconnect` need overloaded variants that accept `NamespaceHandle`. Telling consumers to depend on an internal module for a core workflow is a documentation gap that will cause confusion.
>
> **A (@web-tech-expert):** Agreed. This pitch now includes `onConnectNs` and `onDisconnectNs` wrappers in `PurSocket.Client` (see above). Consumers never need to touch `PurSocket.Internal`. The "What consumers need to know" section has been updated to reference these new wrappers.
>
> -- RESOLVED

> **Q (@architect -> @web-tech-expert):** I concur with @external-user's observation above and want to make it more concrete. Looking at `/home/toby/pursocket/src/PurSocket/Client.purs` lines 216-227, `onConnect` takes `SocketRef` and `onDisconnect` also takes `SocketRef` directly. The `NamespaceHandle`-based `onDisconnect` variant exists only in `PurSocket.Server` (line 365-371), not in `PurSocket.Client`. This means client-side code has no public API path to register `onConnect` or `onDisconnect` on a namespace socket. This is a pre-existing gap that becomes acute with the shared Manager change, because namespace reconnection monitoring is now a primary use case. I recommend this pitch include a scope note: either (a) add `onConnect :: forall protocol ns. NamespaceHandle protocol ns -> Effect Unit -> Effect Unit` and a corresponding `onDisconnect` variant to `PurSocket.Client`'s public API, or (b) explicitly state this gap will be addressed in a separate follow-up. Option (a) is two trivial wrappers (under 30 minutes) and fits within the 1-2 hour appetite. The omission would undermine the pitch's own "What consumers need to know" guidance.
>
> **A (@web-tech-expert):** Option (a) adopted. `onConnectNs` and `onDisconnectNs` are now in scope for this pitch. See the solution sketch above.
>
> -- RESOLVED

> **Q (@purescript-specialist -> @web-tech-expert):** On `socketRefFromHandle` being in `PurSocket.Internal`: you are correct that this is a documentation gap. I concur with @architect's recommendation (line 140) to add `onConnect`/`onDisconnect` variants accepting `NamespaceHandle` directly to `PurSocket.Client`. The signatures would be: `onConnectNs :: forall protocol ns. NamespaceHandle protocol ns -> Effect Unit -> Effect Unit` and `onDisconnectNs :: forall protocol ns. NamespaceHandle protocol ns -> (DisconnectReason -> Effect Unit) -> Effect Unit`. These are trivial wrappers (extract `SocketRef` via pattern match, delegate to existing `primOnConnect`/`primOnDisconnect`). This fits within the 1-2 hour appetite and resolves the abstraction barrier concern without exposing `socketRefFromHandle` publicly.
>
> **A (@web-tech-expert):** Adopted as stated. See solution sketch above.
>
> -- RESOLVED

> **Q (@purescript-specialist -> @external-user):** Responding to your connection status UI question: `onConnect`/`onDisconnect` in `Client.purs` take `SocketRef`, not `NamespaceHandle`. After this change, all sockets share one Manager, so transport events are synchronized. But each Socket still fires its own `connect` event per namespace handshake. For UI state (show/hide "Connection lost"), the base socket's events should suffice since they reflect the shared transport state. For re-identification (re-emitting auth per namespace after reconnect), register `onConnect` on each namespace socket's `SocketRef`.
>
> -- RESOLVED (superseded by onConnectNs wrappers)

### Behavioral changes

| Behavior | Before (independent Managers) | After (shared Manager) |
|----------|-------------------------------|------------------------|
| WebSocket count | N+1 (base + per namespace) | 1 (shared transport) |
| Transport reconnection | Independent per namespace | Atomic -- all namespaces reconnect together |
| `onConnect` / `onDisconnect` | Per-namespace, independent timing | Per-namespace, but synchronized via shared transport |
| Connection state recovery | Impossible (separate sessions) | Possible (shared session) |
| Auth middleware | Runs per Manager (N+1 times) | Runs once |
| Namespace connection latency | Full transport setup per namespace (50-200ms) | Near-instant (multiplexed over existing transport) |
| `disconnect` on one namespace | Tears down that namespace's Manager | Disconnects that namespace only; Manager and other sockets stay alive |
| `disconnect` on base socket | Tears down base socket's Manager only; namespace sockets unaffected (own Managers) | Disconnects base socket only; Manager stays alive while other namespace sockets remain connected |
| Double `joinNs` same namespace | Creates two independent sockets (own Managers) | Returns the same Socket instance (aliased handles -- see Compatibility section) |

> **Q (@architect -> @web-tech-expert):** The behavioral changes table is accurate but missing one row: **namespace connection latency**. With independent Managers, `joinNs` creates a new transport, performs a full WebSocket handshake, then the namespace handshake -- 50-200ms even on localhost. With a shared Manager, the transport is already established, so the namespace handshake happens immediately over the existing connection -- near-instant. This is a positive behavioral change worth documenting. Suggested additional row: `Namespace connection latency | Full transport setup per namespace | Near-instant (multiplexed over existing transport)`. The integration test's `waitForNsConnect` at `/home/toby/pursocket/test/Test/Integration.purs` lines 44-49 uses `delay (Milliseconds 100.0)` which will still work (generous timeout), but the behavioral change affects timing-sensitive application code.
>
> **A (@web-tech-expert):** Added to the table above. Good catch -- this is a meaningful positive change for application responsiveness.
>
> -- RESOLVED

### What consumers need to know

**Reconnection becomes atomic.** Previously, consumers monitoring one socket for reconnection couldn't assume other namespace sockets had also reconnected. After this change, when the Manager reconnects, all namespace sockets reconnect in the same event loop tick.

**Use `onConnectNs` for re-identification after transport recovery.** Register `onConnectNs` on each namespace handle to re-emit identity/auth events when the transport recovers. For UI state (show/hide "Connection lost" overlay), the base socket's `onConnect`/`onDisconnect` is the single source of truth.

**`disconnect` on one namespace socket does not tear down other namespaces.** With a shared Manager, `socket.disconnect()` on one namespace only disconnects that namespace's Socket. The Manager and other namespace sockets remain alive and connected. This includes the base socket: disconnecting a namespace socket does not affect the base socket, and disconnecting the base socket does not affect namespace sockets (see next point).

**Disconnecting the base socket does NOT tear down namespace sockets.** Socket.io's `socket.disconnect()` only disconnects the specific Socket instance it is called on. The Manager stays alive as long as any Socket still references it. Calling `Client.disconnect sock` on the base socket disconnects the default "/" namespace socket but leaves namespace sockets (created via `joinNs`) alive. To tear down everything, disconnect each socket individually. A future `disconnectAll` API (calling `socket.io.close()`) may be added as a convenience, but is out of scope for this pitch.

**Double `joinNs` to the same namespace produces aliased handles.** `manager.socket("/lobby")` is idempotent -- calling it twice returns the same underlying Socket instance. This means two `NamespaceHandle`s from `joinNs @"lobby"` on the same base socket point to the same JS Socket. Listeners registered via one handle fire for the other. Disconnecting via one handle disconnects both. This is a behavioral change from the old `io()` approach which created independent sockets. Applications should not call `joinNs` twice with the same namespace on the same base socket.

> **Q (@external-user -> @web-tech-expert):** The pitch says the practical impact of the disconnect change is "the same," but I think there is a real difference for existing apps. Before: calling `disconnect` on the base socket tears down that socket's independent Manager/transport, but namespace sockets keep running on their own Managers. After: if I call `disconnect` on the base socket (the default "/" socket on the shared Manager), does the Manager stay alive because namespace sockets still reference it, or does it tear everything down? In `Test.Integration`, the cleanup pattern is `Client.disconnect sock` on the base socket only. If the shared Manager makes that destructive for all namespaces, existing cleanup code silently changes from "disconnect base only" to "disconnect everything." This needs explicit documentation in "What consumers need to know."
>
> **A (@web-tech-expert):** Definitive answer: **the Manager stays alive.** Socket.io's `socket.disconnect()` calls `this.io._destroy(this)` internally, which removes the Socket from the Manager's internal socket map. The Manager only closes its transport when it has zero active sockets remaining (checked via `this._nsps.size === 0` in the `_destroy` method). So `Client.disconnect sock` on the base socket removes the default "/" socket but leaves namespace sockets alive. The Manager's transport stays open because the namespace sockets still reference it. This is actually better than the old behavior: before, disconnecting the base socket killed that socket's Manager/transport but namespace sockets (on their own Managers) were unaffected. After, it is the same outcome (namespace sockets unaffected) but for a different reason (shared Manager stays alive rather than separate Managers being independent). The integration test cleanup pattern `Client.disconnect sock` is safe but incomplete with shared Managers -- namespace sockets will linger. Tests should disconnect all sockets. The "What consumers need to know" section has been updated.
>
> -- RESOLVED

> **Q (@qa -> @web-tech-expert):** When one namespace socket is intentionally disconnected via `Client.disconnect` while others share the Manager, does the shared Manager remain open? The pitch says "disconnecting one namespace socket leaves the others connected," but consider the cleanup path: every integration test calls `Client.disconnect sock` on the **base socket** at the end. If the base socket disconnects from a shared Manager, does the Manager close and tear down all namespace sockets? Or do the namespace sockets become orphaned and leak? This affects test isolation -- if namespace sockets from test N survive into test N+1, we get cross-test interference. The test suite needs to either disconnect all namespace sockets explicitly, or we need to verify that disconnecting the base socket tears down the Manager and all its children.
>
> **A (@web-tech-expert):** The Manager stays open (see answer to @external-user above). For test cleanup, the existing pattern is safe because each test uses a different port and `Server.closeServer server` closes the server, which triggers server-side disconnection of all sockets. When the server closes, all connected client sockets receive a `TransportClose` disconnect event and the Manager's transport is torn down from the server side. So even though `Client.disconnect sock` only disconnects the base socket, `Server.closeServer server` cleans up everything. Cross-test interference does not occur because each test uses a unique port. The multi-namespace test (see Testing section) should still explicitly disconnect all namespace sockets for clarity, but `Server.closeServer` provides the safety net.
>
> -- RESOLVED

> **Q (@purescript-specialist -> @web-tech-expert):** On `disconnect` cleanup (supporting @qa's and @external-user's questions): The current `disconnect :: SocketRef -> Effect Unit` calls `socket.disconnect()` on a single socket. With shared Manager, this only disconnects that namespace, leaving the Manager and other sockets alive. There is no PureScript API to close the Manager itself. I would suggest adding a `disconnectAll :: SocketRef -> Effect Unit` FFI function that calls `socket.io.close()` to tear down the Manager and all child sockets. The FFI would be trivial: `export const primDisconnectAll = (socket) => () => { socket.io.close(); };` and the PureScript type: `foreign import primDisconnectAll :: SocketRef -> Effect Unit`. This is additive scope -- not required for the FFI fix itself -- but would be useful for both test cleanup and application lifecycle (mobile app backgrounding). Recommend tracking as a follow-up.
>
> **A (@web-tech-expert):** Good suggestion. `disconnectAll` via `socket.io.close()` is useful but out of scope for this pitch. It is a follow-up tracked in the API surface audit. For now, consumers can disconnect each socket individually, and test cleanup relies on `Server.closeServer` to tear down the server side.
>
> -- RESOLVED (deferred to follow-up)

### Double `joinNs` aliasing behavior

> **Q (@qa -> @web-tech-expert):** What happens if `joinNs @"lobby" sock` is called twice with the same namespace on the same base socket? With the old `io()` approach, this creates two independent sockets to the same namespace (wasteful but functional -- each has its own listeners). With `manager.socket("/lobby")`, does Socket.io return the **same** `Socket` instance (idempotent) or create a new one? If it returns the same instance, both `NamespaceHandle`s in PureScript point to the same JS socket -- listeners registered on one affect the other. If it creates a new one, we should know if event listeners from the first handle leak. Either way, this is a behavioral difference from the old code that needs to be documented and ideally tested.
>
> **A (@web-tech-expert):** Definitive answer: **`manager.socket("/lobby")` is idempotent -- it returns the same Socket instance.** The Manager maintains an internal `Map<string, Socket>` called `_nsps` (namespace sockets). When `manager.socket(nsp)` is called, it checks `this._nsps.has(nsp)`. If the namespace already exists, it returns the cached Socket. If not, it creates a new Socket, stores it in the map, and returns it. This means two `joinNs @"lobby"` calls on the same base socket produce two `NamespaceHandle`s wrapping the exact same JS Socket object. Consequences: (1) `socket.on()` listeners accumulate on the same object -- both handles' `onMsg` listeners fire for every message. (2) `socket.disconnect()` via either handle disconnects both. (3) The PureScript type system cannot detect this aliasing. This is a semantic change from the old behavior where `io()` created independent sockets. The "What consumers need to know" section now documents this. A `Ref (Set String)` guard at the PureScript level to prevent double-join is a possible future enhancement but is out of scope for this pitch.
>
> -- RESOLVED

> **Q (@purescript-specialist -> @web-tech-expert):** Responding to @qa's double-join question from the PureScript/FFI boundary: this is a **significant concern**. If `manager.socket("/lobby")` is idempotent (returns the same JS Socket instance on repeated calls), then two PureScript `joinNs @AppProtocol @"lobby"` calls produce two `NamespaceHandle`s wrapping the **same** `SocketRef`. Consequences: (1) `onMsg` listeners registered via one handle also fire for the other, since `socket.on()` accumulates listeners on the same JS object. (2) `disconnect` via one handle disconnects both. The PureScript type system cannot detect this aliasing -- both handles have type `NamespaceHandle AppProtocol "lobby"` and there is no referential identity check available. This would be a **silent semantic change** from the old `io()` behavior where each call created a truly independent socket. Needs empirical verification against Socket.io source. If idempotent, consider guarding at the PureScript level with a `Ref (Set String)` tracking already-joined namespaces, or at minimum documenting it as a known constraint.
>
> **A (@web-tech-expert):** Confirmed idempotent. See definitive answer above. Documented as a known constraint. A `Ref (Set String)` guard is a reasonable follow-up but adds complexity (requires threading state) and is out of scope for this pitch.
>
> -- RESOLVED

### DisconnectReason consistency

> **Q (@qa -> @web-tech-expert):** The `onDisconnect` API with `DisconnectReason` -- do the reasons stay consistent with a shared Manager? Specifically: (1) If the Manager's transport drops (WiFi blip), do all namespace sockets receive `TransportClose`/`TransportError` as the reason, or does the Manager translate it differently per socket? (2) If one namespace socket is intentionally disconnected via `socket.disconnect()`, does that socket get `ClientDisconnect` while the others stay connected with no disconnect event at all? This matters for consumers using `willAutoReconnect` to decide UI behavior -- if the reasons differ from what they were with independent Managers, application logic could break silently.
>
> **A (@web-tech-expert):** Both answers are definitive.
>
> **(1) Transport drop:** When the Manager's transport drops, the Manager iterates all sockets in its `_nsps` map and calls `socket._onclose(reason)` on each. The reason string is the same for all sockets -- typically `"transport close"`. So yes, all namespace sockets receive `TransportClose` as the `DisconnectReason`. This is the same reason they would have received with independent Managers (each Manager's transport dropping independently). `willAutoReconnect` returns `true` for `TransportClose`, which is correct.
>
> **(2) Intentional namespace disconnect:** When `socket.disconnect()` is called on one namespace socket, only that socket fires the `"disconnect"` event with reason `"io client disconnect"`. The other namespace sockets are completely unaffected -- they receive no disconnect event and continue operating normally. The Manager stays alive (see disconnect semantics above). So `willAutoReconnect` returns `false` for the intentionally-disconnected socket (correct -- it was intentional) and the other sockets never fire `onDisconnect` at all (correct -- they are still connected).
>
> Bottom line: `DisconnectReason` semantics are fully preserved. No application logic using `willAutoReconnect` will break.
>
> -- RESOLVED

### Rapid concurrent joins

> **Q (@qa -> @web-tech-expert):** Does `manager.socket()` handle rapid concurrent calls safely? If PureScript code does `joinNs @"lobby" sock` followed immediately by `joinNs @"game" sock` (two joins in the same event loop tick, before either namespace has connected), does the Manager correctly queue both namespace connection handshakes over the single transport? Or could there be a race where the second `manager.socket()` call interferes with the first namespace's connection handshake? The old `io()` approach avoided this by giving each namespace its own independent transport. A smoke test with rapid sequential joins (no delay between them) would catch this.
>
> **A (@web-tech-expert):** Safe. `manager.socket()` is synchronous and returns immediately. It creates the Socket object and stores it in the Manager's `_nsps` map. The actual namespace connection handshake is deferred to the next event loop tick via `setTimeout(() => socket.open(), 0)` inside the Manager. This means multiple `manager.socket()` calls in the same tick all register their sockets in the map, and then all their `open()` calls fire in subsequent ticks. The Manager's transport multiplexes the CONNECT packets for each namespace over the single WebSocket. There is no race condition -- Socket.io was explicitly designed for this pattern. The multi-namespace test in the Testing section below calls both `joinNs` calls with only a single `waitForNsConnect` delay after both, which exercises this exact scenario.
>
> -- RESOLVED

## Rabbit holes

- Don't change the `connect` function or the base socket concept — consumers may rely on the base socket for connection monitoring. The base socket remains the Manager's default namespace socket.
- Don't change `connect`'s return type or attempt to return the Manager. `baseSocket.io` already provides Manager access internally, so there is no need for a Manager type in PureScript.
- Don't expose the `Manager` type in PureScript — keep it an implementation detail. The behavioral change (shared transport) is the value; consumers don't need Manager access.
- Don't add connection options yet (auth, reconnection config) — that's a separate, larger change tracked in the API surface audit.
- Don't add a `disconnectAll` API in this pitch — defer to follow-up.
- Don't add a double-join guard (`Ref (Set String)`) in this pitch — defer to follow-up.

> **Q (@architect -> @web-tech-expert):** The rabbit holes section should add one more item: **Do not change `connect`'s return type or attempt to return the Manager.** With the shared Manager, there is an architectural temptation to return a Manager wrapper from `connect` instead of a `SocketRef`, since all subsequent `joinNs` calls need the Manager. But `baseSocket.io` already gives us the Manager from any socket, so the current design (connect returns a socket, `joinNs` extracts the Manager internally via `baseSocket.io`) is correct and clean. Adding a Manager type to PureScript would create a second "connection" concept alongside `SocketRef` and `NamespaceHandle`, adding confusion for no functional benefit. The pitch's existing rabbit hole about not exposing the Manager covers this, but "do not change `connect`'s return type" makes it more explicit.
>
> **A (@web-tech-expert):** Added to the rabbit holes list above.
>
> -- RESOLVED

> **Q (@architect -> @web-tech-expert):** Does this change affect `ServerTarget` / Bun engine support? I reviewed `/home/toby/pursocket/src/PurSocket/Server.js` and `/home/toby/pursocket/src/PurSocket/Server.purs`. The server-side namespace handling uses `io.of("/ns")` (lines 14-19 of `Server.js`), which is the server's namespace API and is completely independent of the client-side `manager.socket()` change. The `ServerTarget` sum type, `BunEngine` support via `primCreateServerWithBunEngine` (lines 94-98 of `Server.js`), and all server FFI functions are unaffected. The shared Manager is purely a client-side concept -- the server always multiplexed namespaces correctly via its own internal mechanisms. Confirmed: no server-side impact.
>
> -- RESOLVED (confirmed)

## Compatibility risks

This change is not purely additive. While the API surface is unchanged (same function signatures, same types), the runtime behavior changes in ways that could affect existing applications:

1. **Double `joinNs` aliasing.** Previously, calling `joinNs @"lobby"` twice created two independent sockets. Now it returns the same Socket instance, causing listener accumulation and shared disconnect. Applications that rely on multiple independent connections to the same namespace will break silently. Mitigation: document as a known constraint.

2. **Disconnect scope change.** Previously, `Client.disconnect` on the base socket killed that socket's Manager/transport with no effect on namespace sockets (separate Managers). Now, `Client.disconnect` on the base socket only disconnects the "/" namespace; namespace sockets remain alive on the shared Manager. The observable behavior is the same (namespace sockets stay up), but the mechanism is different. Applications that assumed `Client.disconnect` on the base socket would free all resources associated with that connection will now leak namespace sockets. Mitigation: document that all sockets must be individually disconnected, or use `Server.closeServer` for test cleanup.

3. **Reconnection timing.** Previously, each namespace reconnected independently after a transport blip. Now all namespaces reconnect atomically. Applications that relied on staggered reconnection timing (unlikely but possible) will see different behavior. This is overwhelmingly a positive change, but it is a behavioral change.

4. **Auth middleware execution count.** Previously, `io.use()` middleware ran N+1 times (once per Manager). Now it runs once. Applications that relied on middleware running per-namespace (e.g., per-namespace rate limiting in middleware) will see different behavior. This is the correct Socket.io behavior and was likely never intentional, but it is a change.

## Testing

### Mandatory: Multi-namespace multiplexing test

This is the primary validation test. It joins two namespaces on the same base socket and verifies both can independently send and receive messages.

```purescript
describe "shared Manager" do
  it "multiple namespaces on same connection can independently emit and receive" do
    server <- liftEffect $ Server.createServerWithPort (testPort + 9)

    -- Server-side capture refs
    chatRef <- liftEffect $ Ref.new ""
    moveXRef <- liftEffect $ Ref.new 0
    moveYRef <- liftEffect $ Ref.new 0

    -- Register handlers on both namespaces
    liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
      Server.onEvent @"chat" handle \payload ->
        Ref.write payload.text chatRef

    liftEffect $ Server.onConnection @AppProtocol @"game" server \handle -> do
      Server.onEvent @"move" handle \payload -> do
        Ref.write payload.x moveXRef
        Ref.write payload.y moveYRef

    -- Single client connection
    let url9 = "http://localhost:" <> show (testPort + 9)
    sock <- liftEffect $ Client.connect url9
    liftAff $ waitForConnect sock

    -- Join BOTH namespaces on the SAME base socket
    lobby <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sock
    game <- liftEffect $ Client.joinNs @AppProtocol @"game" sock
    liftAff $ delay (Milliseconds 200.0)

    -- Emit on both
    liftEffect $ Client.emit @"chat" lobby { text: "shared manager" }
    liftEffect $ Client.emit @"move" game { x: 42, y: 99 }

    liftAff $ delay (Milliseconds 300.0)

    -- Verify both namespaces received independently
    chat <- liftEffect $ Ref.read chatRef
    chat `shouldEqual` "shared manager"
    mx <- liftEffect $ Ref.read moveXRef
    mx `shouldEqual` 42
    my <- liftEffect $ Ref.read moveYRef
    my `shouldEqual` 99

    -- Cleanup
    liftEffect $ Client.disconnect sock
    liftEffect $ Server.closeServer server
    liftAff $ delay (Milliseconds 100.0)
```

> **Q (@architect -> @web-tech-expert):** The testing section says "The test server already uses multiple namespaces" but looking at the integration tests at `/home/toby/pursocket/test/Test/Integration.purs`, each test joins only one namespace per base socket. There is no test that joins multiple namespaces on the same base socket. This means the existing test suite does not exercise the shared Manager multiplexing behavior. A test that does `lobby <- joinNs @"lobby" sock` followed by `game <- joinNs @"game" sock` on the same `sock`, then emits on both and verifies both messages arrive at the correct server-side namespace handlers, would directly validate that `manager.socket()` correctly multiplexes. This is the most important test to add -- more important than the reconnection test. Without it, the suite could pass even if `manager.socket()` silently routes everything to one namespace.
>
> **A (@web-tech-expert):** Correct. I was wrong to claim the existing suite was sufficient. The multi-namespace test sketched above is now mandatory. It exercises the exact multiplexing behavior this pitch enables.
>
> -- RESOLVED

> **Q (@external-user -> @web-tech-expert):** The integration tests each use a separate port and fresh `connect` call, so each has its own Manager. None of the existing tests join multiple namespaces on the same connection -- the "lobby" and "game" namespace tests are in separate test blocks. The proposed reconnect test is good but does not verify the core claim of this pitch: that namespaces share a transport. I would want at least one test that joins two namespaces on the same connection and verifies shared-transport behavior (e.g., disconnect one namespace and verify the other stays alive; or verify on the server side that only one transport exists for a client with two namespace sockets). Without that, the test suite can pass even if the FFI change is incorrect.
>
> **A (@web-tech-expert):** Addressed by the multi-namespace test above, plus the disconnect-isolation test below.
>
> -- RESOLVED

> **Q (@qa -> @web-tech-expert):** Reinforcing the above: I audited every `joinNs` call in `test/Test/Integration.purs` and confirmed that **no existing test joins multiple namespaces from the same base socket**. Each test joins exactly one namespace per client connection -- either `"lobby"` (lines 72, 108, 145, 231, 239, 294, 302, etc.) or `"game"` (line 179), never both on the same `sock`. The claim "Run the suite -- if it passes, the change is correct" is false: the suite could pass even if `manager.socket()` returned a broken object, as long as single-namespace joins still work. Minimum required: a test that does `joinNs @"lobby" sock` and `joinNs @"game" sock` on the same base socket, then verifies both can independently emit and receive messages.
>
> **A (@web-tech-expert):** Agreed. The original claim was wrong. See multi-namespace test above.
>
> -- RESOLVED

### Recommended: Namespace-disconnect-isolation test

Verifies that disconnecting one namespace socket leaves the other alive on the shared Manager:

```purescript
it "disconnecting one namespace does not affect the other" do
    server <- liftEffect $ Server.createServerWithPort (testPort + 10)

    moveRef <- liftEffect $ Ref.new 0

    liftEffect $ Server.onConnection @AppProtocol @"lobby" server \_ -> pure unit
    liftEffect $ Server.onConnection @AppProtocol @"game" server \handle -> do
      Server.onEvent @"move" handle \payload ->
        Ref.write payload.x moveRef

    let url10 = "http://localhost:" <> show (testPort + 10)
    sock <- liftEffect $ Client.connect url10
    liftAff $ waitForConnect sock

    lobby <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sock
    game <- liftEffect $ Client.joinNs @AppProtocol @"game" sock
    liftAff $ delay (Milliseconds 200.0)

    -- Disconnect lobby namespace
    liftEffect $ Client.disconnect (socketRefFromHandle lobby)
    liftAff $ delay (Milliseconds 100.0)

    -- Game namespace should still work
    liftEffect $ Client.emit @"move" game { x: 7, y: 0 }
    liftAff $ delay (Milliseconds 200.0)

    mx <- liftEffect $ Ref.read moveRef
    mx `shouldEqual` 7

    -- Cleanup
    liftEffect $ Client.disconnect sock
    liftEffect $ Server.closeServer server
    liftAff $ delay (Milliseconds 100.0)
```

Note: this test uses `socketRefFromHandle` from `PurSocket.Internal` in test code, which is acceptable since tests are not library consumers. An alternative is to add a `disconnectNs` wrapper to `PurSocket.Client` that accepts a `NamespaceHandle`, but that can be a follow-up.

### Deferred: Reconnection test

> **Q (@architect -> @web-tech-expert):** The reconnection test proposed in the pitch ("calling `disconnect` then waiting for auto-reconnect") has a subtle issue. Calling `socket.disconnect()` on a client socket produces the `"io client disconnect"` reason. Per PurSocket's own `willAutoReconnect` function (`/home/toby/pursocket/src/PurSocket/Client.purs` lines 69-72), `ClientDisconnect` returns `false` -- Socket.io does NOT auto-reconnect after intentional client disconnects. To simulate a transport blip, you would need to force-close the engine transport (`socket.io.engine.close()`) which triggers `TransportClose` and auto-reconnect, or have the server forcefully disconnect. Neither mechanism is exposed in PurSocket's current FFI. This may push the reconnection test outside the 1-2 hour appetite. Consider deferring the reconnection test and prioritizing the multi-namespace multiplexing test instead.
>
> **A (@web-tech-expert):** Correct on all points. The original reconnection test was broken as described. The proper way to simulate a transport blip is `socket.io.engine.close()`, which closes the Engine.IO transport without calling `socket.disconnect()`. This triggers `TransportClose` (which has `willAutoReconnect = true`) and the Manager auto-reconnects. The FFI would be: `export const primForceTransportClose = (socket) => () => { socket.io.engine.close(); };`. However, this requires a new FFI function and a PureScript wrapper, and the test itself is more complex (need to wait for disconnect, then wait for reconnect, then verify events flow). This pushes beyond the appetite for this pitch. **Deferred.** The multi-namespace test and disconnect-isolation test are sufficient to validate the shared Manager change. The reconnection test is tracked as a follow-up.
>
> -- RESOLVED (deferred)

> **Q (@qa -> @web-tech-expert):** The proposed reconnection test says "calling `disconnect` then waiting for auto-reconnect," but this will not work as described. `Client.disconnect` calls `socket.disconnect()`, which produces the `"io client disconnect"` reason. The pitch's own `DisconnectReason` ADT and `willAutoReconnect` function (in `src/PurSocket/Client.purs` lines 51-72) confirm that `ClientDisconnect` returns `false` for auto-reconnect. Socket.io does **not** auto-reconnect after client-initiated disconnects. The proposed test will hang forever waiting for a reconnect that never comes. To actually test reconnection, you need to simulate a transport-level failure, for example by accessing the underlying engine transport and forcing it closed (`socket.io.engine.close()`), or by using the server-side `socket.disconnect(true)` which severs with transport close. What is the concrete test setup?
>
> **A (@web-tech-expert):** Agreed. The original reconnection test was wrong. See deferral above. For the record, the two viable approaches for a future reconnection test are: (1) client-side `socket.io.engine.close()` via new FFI, or (2) server-side `socket.disconnect(true)` which sends a server-forced disconnect with reason `"io server disconnect"` -- but note this also does not auto-reconnect (`willAutoReconnect` returns `false` for `ServerDisconnect`). The correct approach is (1), because `engine.close()` triggers `TransportClose` which does auto-reconnect.
>
> -- RESOLVED (deferred)

## Open Questions Summary

| # | Question | Raiser | Status |
|---|----------|--------|--------|
| 1 | Connection status UI pattern after shared Manager | @external-user | RESOLVED -- base socket for UI, onConnectNs for re-identification |
| 2 | FFI change verification | @architect | RESOLVED -- confirmed correct |
| 3 | PureScript side "no changes" verification | @architect, @purescript-specialist | RESOLVED -- confirmed independently |
| 4 | Namespace connection latency row in table | @architect | RESOLVED -- added to table |
| 5 | onConnectNs/onDisconnectNs wrappers needed | @external-user, @architect, @purescript-specialist | RESOLVED -- included in scope |
| 6 | Per-namespace auth future compatibility | @external-user | RESOLVED -- compatible extension via manager.socket(nsp, opts) |
| 7 | Base socket disconnect tears down namespaces? | @external-user, @qa | RESOLVED -- Manager stays alive; documented |
| 8 | Double joinNs aliasing | @qa, @purescript-specialist | RESOLVED -- idempotent; documented as constraint |
| 9 | DisconnectReason consistency | @qa | RESOLVED -- reasons fully preserved |
| 10 | Rapid concurrent joins safe? | @qa | RESOLVED -- safe by design |
| 11 | Reconnection test infeasible as described | @architect, @qa | RESOLVED -- deferred; multi-namespace test prioritized |
| 12 | Multi-namespace test mandatory | @architect, @external-user, @qa | RESOLVED -- test sketched above |
| 13 | Do not change connect return type | @architect | RESOLVED -- added to rabbit holes |
| 14 | ServerTarget/Bun unaffected | @architect | RESOLVED -- confirmed |
| 15 | disconnectAll API suggestion | @purescript-specialist | RESOLVED -- deferred to follow-up |
| 16 | Appetite too low | all reviewers | RESOLVED -- updated to 3-4 hours |
