# Socket.io FFI Semantics Reference

This document captures the runtime behaviors of Socket.io that require care at
the FFI boundary between PureScript and JavaScript. It serves as a reference
for anyone adding new FFI functions or debugging unexpected behavior at the
JS interop layer.

**Scope:** PurSocket targets Socket.io v4.x on the server (`socket.io` npm
package) and the client (`socket.io-client` npm package). The PureScript FFI
files are `/home/toby/pursocket/src/PurSocket/Server.js` and
`/home/toby/pursocket/src/PurSocket/Client.js`.

---

## 1. Property Access vs Method Calls

Socket.io exposes both stable references and transient operator objects on its
socket and server instances. The distinction matters because transient objects
must not be cached or stored -- they must be consumed immediately.

### Transient Objects (Do Not Cache)

**`socket.broadcast`** returns a `BroadcastOperator`. This is a getter
property, not a method. The returned operator is scoped to the socket's
namespace and pre-configured to exclude the socket's own ID. It must be
followed immediately by `.emit()` in the same expression. Do not store the
result in a variable across ticks or reuse it:

```js
// Correct -- construct and consume in one expression
socket.broadcast.emit(event, payload);

// WRONG -- caching the operator risks stale state
const op = socket.broadcast;
// ... later ...
op.emit(event, payload);  // may not reflect current adapter state
```

PurSocket's FFI (`primBroadcastExceptSender`) constructs the chain fresh on
every call. This is intentional.

**`socket.to(room)`** also returns a transient `BroadcastOperator`. It is
scoped to the socket's namespace, the specified room, and excludes the calling
socket. The same rule applies -- chain `.emit()` immediately:

```js
// Correct
socket.to(room).emit(event, payload);

// WRONG -- do not cache the BroadcastOperator
const op = socket.to(room);
```

PurSocket's FFI (`primBroadcastToRoom`) constructs a fresh chain per call.

**`io.of(ns).to(room)`** at the namespace level also returns a transient
`BroadcastOperator`. PurSocket does not currently use this pattern (all
room operations go through the socket-level variant), but if it is ever
needed in the future, the same "construct fresh, consume immediately" rule
applies.

### Stable References (Safe to Read/Store)

**`socket.id`** is a stable string property. It is assigned when the socket
connects and does not change for the lifetime of the connection. PurSocket's
`primSocketId` reads this as a pure function (no `Effect` wrapper needed):

```js
export const primSocketId = (socket) => socket.id;
```

**`socket.nsp`** is a stable reference to the `Namespace` object that the
socket belongs to. It carries the namespace path, adapter reference, and
connected sockets set. PurSocket does not expose `socket.nsp` directly, but
it is the mechanism by which `socket.broadcast.emit()` and
`socket.to(room).emit()` know which namespace to target -- the
`BroadcastOperator` inherits the namespace from the socket's `.nsp` property.

**`ServerSocket` (the `io` object)** is a stable `Server` instance. It is
created once by `primCreateServer` or `primCreateServerWithPort` and remains
valid until `primCloseServer` is called.

---

## 2. Promise Handling Boundaries

### The Rule

`socket.join(room)` and `socket.leave(room)` return `Promise<void>` in
Socket.io v4.x. This promise exists for adapter compatibility -- async
adapters (e.g., Redis) need time to propagate room membership across
processes.

**PurSocket intentionally discards these promises at the JS boundary.** The
FFI functions return `Effect Unit`, not `Aff Unit`:

```js
export const primJoinRoom = (socket) => (room) => () => {
  socket.join(room);   // Promise<void> return value is discarded
};

export const primLeaveRoom = (socket) => (room) => () => {
  socket.leave(room);  // Promise<void> return value is discarded
};
```

### Why This Is Safe (For the Default Adapter)

The default in-memory adapter's `addAll()` and `del()` methods are
synchronous. The promise resolves in the same microtask. By the time the
next line of `Effect` code runs, the join/leave has already completed. There
is no race condition for users of the default adapter.

### When This Breaks

If a user switches to an async adapter (e.g., `@socket.io/redis-adapter`),
`socket.join()` genuinely needs time to propagate to the Redis pub/sub layer.
Messages sent to a room immediately after `joinRoom` may not reach the newly
joined socket on other servers. PurSocket's doc comments on `joinRoom` and
`leaveRoom` warn about this.

### Future Path

Do not add `await` to the FFI without consulting the architecture. The
correct future approach is to add `joinRoomAff` and `leaveRoomAff` as
separate functions returning `Aff Unit`, keeping the `Effect`-based variants
for the default adapter. This avoids forcing `Aff` boilerplate on the
majority of users who do not need async adapter support.

---

## 3. Namespace Path Construction Rules

Socket.io namespaces are identified by string paths like `"/chat"` or
`"/game"`. PurSocket represents namespace names as type-level `Symbol`s
(e.g., `"chat"`, `"game"`) and must convert them to runtime strings using
`reflectSymbol` when constructing namespace paths. However, not all FFI
functions need this conversion.

### Functions That Need `reflectSymbol` on the Namespace

These functions start from the `Server` instance (`io`) and must construct
the `"/" + ns` path to navigate to the correct namespace:

| PureScript Function | FFI Pattern | Why `reflectSymbol` Is Needed |
|---------------------|-------------|-------------------------------|
| `broadcast` | `io.of("/" + ns).emit(event, payload)` | Navigates from `io` to a namespace by path |
| `onConnection` | `io.of("/" + ns).on("connection", cb)` | Navigates from `io` to a namespace by path |

Both functions take `ServerSocket` as a parameter and have an `IsSymbol ns`
constraint to enable the `reflectSymbol` call.

### Functions That Do NOT Need `reflectSymbol` on the Namespace

These functions operate on a `SocketRef` extracted from a `NamespaceHandle`.
The socket already carries its namespace context (via `socket.nsp`
internally). There is no need to construct a namespace path string:

| PureScript Function | FFI Pattern | Why No `reflectSymbol` |
|---------------------|-------------|------------------------|
| `emitTo` | `socket.emit(event, payload)` | Socket knows its namespace |
| `broadcastExceptSender` | `socket.broadcast.emit(event, payload)` | `BroadcastOperator` inherits namespace from socket |
| `broadcastToRoom` | `socket.to(room).emit(event, payload)` | `BroadcastOperator` inherits namespace from socket |
| `onEvent` | `socket.on(event, cb)` | Listener is scoped to the socket's namespace |
| `onCallEvent` | `socket.on(event, (data, ack) => ...)` | Same as `onEvent` |
| `onDisconnect` | `socket.on("disconnect", cb)` | System event on the socket's namespace |
| `joinRoom` | `socket.join(room)` | Room is within the socket's namespace |
| `leaveRoom` | `socket.leave(room)` | Room is within the socket's namespace |
| `socketId` | `socket.id` | Property read, no namespace needed |

The `ns` phantom type parameter in `NamespaceHandle ns` still participates
in `IsValidMsg`/`IsValidCall` constraints for compile-time validation, but
it is never reflected to a runtime string by these functions.

### Client-Side Note

On the client, `primConnect` takes a URL string and `primJoin` constructs
the namespace URL by concatenating the base URL with `"/" + ns`. The client
FFI does its own path construction and does not use `reflectSymbol` from
PureScript -- the namespace string is passed in directly from the PureScript
wrapper.

---

## 4. Adapter-Aware Operations Matrix

Socket.io's adapter abstraction controls how messages are distributed across
processes in a multi-server deployment (e.g., using `@socket.io/redis-adapter`).
Some operations go through the adapter; others write directly to a socket's
underlying transport connection.

| PureScript Function | JS Pattern | Goes Through Adapter? | Notes |
|---------------------|------------|----------------------|-------|
| `emitTo` | `socket.emit(event, payload)` | No | Direct write to the socket's transport connection. Works in clustered deployments only if the socket is connected to this server process. |
| `broadcastExceptSender` | `socket.broadcast.emit(event, payload)` | Yes | The `BroadcastOperator` uses `adapter.broadcast()` internally. In a Redis adapter setup, this publishes to the Redis channel and all processes deliver to their local matching sockets. |
| `broadcastToRoom` | `socket.to(room).emit(event, payload)` | Yes | Same adapter path as `broadcastExceptSender`, with an additional room filter. |
| `broadcast` | `io.of(ns).emit(event, payload)` | Yes | Namespace-wide broadcast goes through the adapter. All processes deliver to all connected sockets in the namespace. |
| `joinRoom` | `socket.join(room)` | Depends | Default in-memory adapter: synchronous, no adapter round-trip. Redis adapter: async, returns a meaningful `Promise<void>` that PurSocket currently discards (see Section 2). |
| `leaveRoom` | `socket.leave(room)` | Depends | Same behavior as `joinRoom`. |
| `onEvent` | `socket.on(event, cb)` | No | Event listeners are local to the socket. No adapter involvement. |
| `onCallEvent` | `socket.on(event, (data, ack) => ...)` | No | Same as `onEvent`. Acknowledgement callback is a direct reply to the sender. |
| `onConnection` | `io.of(ns).on("connection", cb)` | No | Connection events are local to this server process. Each process sees only its own connections. |
| `onDisconnect` | `socket.on("disconnect", cb)` | No | Disconnect events are local to this server process. |

### Key Implication for Multi-Process Deployments

`emitTo` writes directly to a socket. If the target socket is connected to a
different server process, the message will not be delivered. Applications that
need to send to a specific client across processes should use
`io.to(socketId).emit()` (which goes through the adapter) instead. PurSocket
does not currently expose this pattern -- `emitTo` uses the direct
`socket.emit()` path. This is the correct default for single-process
deployments. Multi-process targeted messaging may be added in a future cycle.

---

## 5. FFI Function Inventory

### Server FFI (`/home/toby/pursocket/src/PurSocket/Server.js`)

All server FFI functions import from the `socket.io` npm package.

| FFI Function | JS Pattern | PureScript Wrapper | PureScript Type |
|---|---|---|---|
| `primCreateServer` | `new Server()` | `createServer` | `Effect ServerSocket` |
| `primCreateServerWithPort` | `new Server(port, { cors: { origin: "*" } })` | `createServerWithPort` | `Int -> Effect ServerSocket` |
| `primBroadcast` | `io.of("/" + ns).emit(event, payload)` | `broadcast` | `forall a. ServerSocket -> String -> String -> a -> Effect Unit` |
| `primOnConnection` | `io.of("/" + ns).on("connection", cb)` | `onConnection` | `ServerSocket -> String -> (SocketRef -> Effect Unit) -> Effect Unit` |
| `primOnEvent` | `socket.on(event, (data) => cb(data)())` | `onEvent` | `forall a. SocketRef -> String -> (a -> Effect Unit) -> Effect Unit` |
| `primOnCallEvent` | `socket.on(event, (data, ack) => { r = handler(data)(); ack(r); })` | `onCallEvent` | `forall a r. SocketRef -> String -> (a -> Effect r) -> Effect Unit` |
| `primOnDisconnect` | `socket.on("disconnect", () => cb())` | `onDisconnect` | `SocketRef -> Effect Unit -> Effect Unit` |
| `primSocketId` | `socket.id` | `socketId` | `SocketRef -> String` |
| `primCloseServer` | `io.close()` | `closeServer` | `ServerSocket -> Effect Unit` |
| `primEmitTo` | `socket.emit(event, payload)` | `emitTo` | `forall a. SocketRef -> String -> a -> Effect Unit` |
| `primBroadcastExceptSender` | `socket.broadcast.emit(event, payload)` | `broadcastExceptSender` | `forall a. SocketRef -> String -> a -> Effect Unit` |
| `primJoinRoom` | `socket.join(room)` | `joinRoom` | `SocketRef -> String -> Effect Unit` |
| `primLeaveRoom` | `socket.leave(room)` | `leaveRoom` | `SocketRef -> String -> Effect Unit` |
| `primBroadcastToRoom` | `socket.to(room).emit(event, payload)` | `broadcastToRoom` | `forall a. SocketRef -> String -> String -> a -> Effect Unit` |

### Client FFI (`/home/toby/pursocket/src/PurSocket/Client.js`)

All client FFI functions import from the `socket.io-client` npm package.

| FFI Function | JS Pattern | PureScript Wrapper | PureScript Type |
|---|---|---|---|
| `primConnect` | `io(url)` | `connect` | `String -> Effect SocketRef` |
| `primJoin` | `io(baseSocket.io.uri + "/" + ns)` | `join` | `SocketRef -> String -> Effect SocketRef` |
| `primEmit` | `socket.emit(event, payload)` | `emit` | `forall a. SocketRef -> String -> a -> Effect Unit` |
| `primCallImpl` | `socket.timeout(ms).emit(event, payload, (err, res) => ...)` | `call` / `callWithTimeout` | `forall a r. SocketRef -> String -> a -> Int -> (r -> Effect Unit) -> (Error -> Effect Unit) -> Effect Unit` |
| `primOnMsg` | `socket.on(event, (data) => cb(data)())` | `onMsg` | `forall a. SocketRef -> String -> (a -> Effect Unit) -> Effect Unit` |
| `primOnConnect` | `socket.on("connect", () => cb())` | `onConnect` | `SocketRef -> Effect Unit -> Effect Unit` |
| `primDisconnect` | `socket.disconnect()` | `disconnect` | `SocketRef -> Effect Unit` |

### The `forall a` Trust Boundary

Every `prim*` function that accepts a payload uses `forall a` in its
PureScript type signature. This means the compiler cannot verify payload
shape at the FFI boundary -- it trusts that the PureScript type engine
(`IsValidMsg` / `IsValidCall` constraints) validated the payload upstream.

This is inherent to how PureScript FFI works with dynamically-typed JS APIs.
Socket.io's `emit` accepts `...args: any[]` at the JS level. The type safety
lives entirely in the PureScript wrapper layer.

**Do not call `prim*` functions directly.** Always use the typed wrappers
(`emitTo`, `broadcast`, `onEvent`, etc.) which enforce protocol constraints
before reaching the FFI boundary.

---

*Created 2026-02-04 during cooldown for the emitTo and Room Support cycle.*
