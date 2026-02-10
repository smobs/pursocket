# Socket.io v4 API Surface Audit for PurSocket

**Date:** 2026-02-04
**Author:** Architect agent
**Purpose:** Comprehensive mapping of every Socket.io v4 API item to PurSocket status and keep/defer/never decisions, preventing "discovered gaps" in future build cycles.

---

## Legend

- **Wrapped** -- PurSocket has a typed wrapper for this API item today.
- **Partially wrapped** -- PurSocket covers some aspect but not the full API.
- **Not wrapped** -- No PurSocket equivalent exists.
- **Keep** -- Already present, retain as-is.
- **Defer** -- Worth wrapping in a future cycle.
- **Never** -- Intentionally excluded from PurSocket's scope.

---

## 1. Server-Side API

### 1.1 Server Class (`new Server(...)`)

| # | API Item | Kind | PurSocket Status | Decision | Rationale |
|---|----------|------|-----------------|----------|-----------|
| S1 | `new Server(httpServer, opts)` | Constructor | Not wrapped | **Defer** | Currently `createServer` and `createServerWithPort` exist but do not accept an existing HTTP server. Task 3/I2 in cleanup addresses this (`attachToHttpServer`). Essential for real-world deployments with Express/Koa. |
| S2 | `new Server(port, opts)` | Constructor | Wrapped (`createServerWithPort`) | **Keep** | Works. Options record is hardcoded to `{ cors: { origin: "*" } }` in FFI -- consider making options configurable in a future cycle. |
| S3 | `new Server(opts)` | Constructor | Wrapped (`createServer`) | **Keep** | Creates standalone server without port. |
| S4 | `server.listen(httpServer)` / `server.attach(httpServer)` | Method | Not wrapped | **Defer** | Same concern as S1. Needed for attaching to existing HTTP servers after creation. Bundle with S1 when `attachToHttpServer` is built. |
| S5 | `server.listen(port)` / `server.attach(port)` | Method | Not wrapped | **Defer** | Useful for deferred listen. Lower priority since `createServerWithPort` covers the common case. |
| S6 | `server.close()` | Method | Wrapped (`closeServer`) | **Keep** | Works correctly. |
| S7 | `server.of(namespace)` | Method | Partially wrapped | **Keep** | Used internally by `broadcast` and `onConnection` FFI. Not exposed as a standalone function, which is correct -- PurSocket uses phantom-typed handles instead. |
| S8 | `server.use(middleware)` | Method | Not wrapped | **Defer** | Server-level middleware for all namespaces. Important for auth. See middleware section below (S30). |
| S9 | `server.engine` | Property | Not wrapped | **Never** | Low-level Engine.IO access. Not needed for typed protocol work. |
| S10 | `server.sockets` | Property | Not wrapped | **Never** | Alias for `server.of("/")`. PurSocket handles namespaces explicitly via phantom types. |
| S11 | `server.fetchSockets()` | Method | Not wrapped | **Defer** | Returns all connected sockets. Useful for admin/monitoring. Could be typed to return `Array (NamespaceHandle ns)`. |
| S12 | `server.serverSideEmit(event, ...args)` | Method | Not wrapped | **Defer** | Multi-server (cluster) communication via adapters. Only relevant for scaled deployments. |
| S13 | `server.serverSideEmitWithAck(event, ...args)` | Method | Not wrapped | **Defer** | Ack variant of S12. Same rationale. |
| S14 | `server.socketsJoin(rooms)` | Method | Not wrapped | **Defer** | Force sockets into rooms. See rooms section below. |
| S15 | `server.socketsLeave(rooms)` | Method | Not wrapped | **Defer** | Force sockets out of rooms. See rooms section below. |
| S16 | `server.disconnectSockets(close?)` | Method | Not wrapped | **Defer** | Force-disconnect all sockets. Admin utility. |
| S17 | `server.path()` / `server.path(value)` | Method | Not wrapped | **Never** | Path prefix configuration. Set once at construction time via options. |
| S18 | `server.adapter()` / `server.adapter(value)` | Method | Not wrapped | **Never** | Adapter configuration (Redis, etc.). Infrastructure concern, not protocol concern. If needed, users configure in JS before passing to PurSocket. |
| S19 | `server.httpAllowRequest(fn)` | Method | Not wrapped | **Never** | Low-level HTTP handshake override. Security/infrastructure, not protocol. |
| S20 | `server.opts` (various constructor options) | Options | Partially wrapped | **Defer** | `cors`, `path`, `serveClient`, `connectTimeout`, `pingTimeout`, `pingInterval`, `maxHttpBufferSize`, `transports`, etc. Should eventually accept an options record in `createServer`. |

### 1.2 Namespace Class (`server.of(...)`)

| # | API Item | Kind | PurSocket Status | Decision | Rationale |
|---|----------|------|-----------------|----------|-----------|
| N1 | `namespace.name` | Property | Not wrapped | **Never** | Available from the phantom type parameter via `reflectSymbol`. No runtime wrapper needed. |
| N2 | `namespace.sockets` | Property | Not wrapped | **Defer** | Map of connected sockets in this namespace. Useful for admin. Could return typed handles. |
| N3 | `namespace.adapter` | Property | Not wrapped | **Never** | Adapter access per-namespace. Infrastructure concern. |
| N4 | `namespace.use(middleware)` | Method | Not wrapped | **Defer** | Namespace-level middleware. Critical for per-namespace auth. See middleware section (S30). |
| N5 | `namespace.emit(event, ...args)` | Method | Wrapped (`broadcast`) | **Keep** | PurSocket's `broadcast` function covers this with full type safety. |
| N6 | `namespace.to(room)` / `namespace.in(room)` | Method | Not wrapped | **Defer** | Room-scoped broadcast. See rooms section. |
| N7 | `namespace.except(room)` | Method | Not wrapped | **Defer** | Broadcast excluding rooms. See rooms section. |
| N8 | `namespace.fetchSockets()` | Method | Not wrapped | **Defer** | Like S11 but namespace-scoped. |
| N9 | `namespace.socketsJoin(rooms)` | Method | Not wrapped | **Defer** | Force namespace sockets into rooms. |
| N10 | `namespace.socketsLeave(rooms)` | Method | Not wrapped | **Defer** | Force namespace sockets out of rooms. |
| N11 | `namespace.disconnectSockets(close?)` | Method | Not wrapped | **Defer** | Force-disconnect namespace sockets. |
| N12 | `namespace.serverSideEmit(event, ...args)` | Method | Not wrapped | **Defer** | Cluster communication at namespace level. |
| N13 | `namespace.on("connection", callback)` | Event | Wrapped (`onConnection`) | **Keep** | Core connection event. Works correctly. |

### 1.3 Server-Side Socket Class (per-connection)

| # | API Item | Kind | PurSocket Status | Decision | Rationale |
|---|----------|------|-----------------|----------|-----------|
| SK1 | `socket.id` | Property | Wrapped (`socketId`) | **Keep** | Works correctly. |
| SK2 | `socket.handshake` | Property | Not wrapped | **Defer** | Contains auth headers, query params, address, etc. Important for auth-aware handlers. Could be exposed as a typed record. |
| SK3 | `socket.rooms` | Property | Not wrapped | **Defer** | Set of rooms the socket is in. See rooms section. |
| SK4 | `socket.data` | Property | Not wrapped | **Defer** | Arbitrary data attached to socket. Useful for session state. Could use a type parameter. |
| SK5 | `socket.conn` | Property | Not wrapped | **Never** | Low-level Engine.IO connection. Not protocol-relevant. |
| SK6 | `socket.request` | Property | Not wrapped | **Never** | Raw HTTP request that initiated the connection. Infrastructure concern. |
| SK7 | `socket.recovered` | Property | Not wrapped | **Defer** | Boolean indicating connection recovery (v4.6+). Relevant for connection state recovery feature. |
| SK8 | `socket.emit(event, ...args)` | Method | Not wrapped (server->specific-client) | **Defer** | PurSocket has `broadcast` (to all clients) but NOT emit-to-single-client from server. This is a significant gap. A `sendTo` or `emitTo` function taking a `NamespaceHandle` and sending only to that socket's client is needed. |
| SK9 | `socket.on(event, callback)` | Method | Wrapped (`onEvent`) | **Keep** | Core event listener. Works correctly. |
| SK10 | `socket.once(event, callback)` | Method | Not wrapped | **Defer** | One-time listener. Useful but not critical. |
| SK11 | `socket.off(event, callback)` / `socket.removeListener(...)` | Method | Not wrapped | **Defer** | Remove event listener. Important for cleanup in long-lived connections. |
| SK12 | `socket.removeAllListeners(event?)` | Method | Not wrapped | **Defer** | Remove all listeners. Same cleanup concern as SK11. |
| SK13 | `socket.join(room)` | Method | Not wrapped | **Defer** | Join a room. See rooms section. |
| SK14 | `socket.leave(room)` | Method | Not wrapped | **Defer** | Leave a room. See rooms section. |
| SK15 | `socket.to(room)` / `socket.in(room)` | Method | Not wrapped | **Defer** | Broadcast to a room from this socket's perspective (excludes sender). See rooms section. |
| SK16 | `socket.except(room)` | Method | Not wrapped | **Defer** | Broadcast excluding specific rooms. |
| SK17 | `socket.disconnect(close?)` | Method | Not wrapped | **Defer** | Server forcefully disconnects a client. Useful for kick/ban. |
| SK18 | `socket.timeout(ms).emit(...)` | Method | Not wrapped | **Defer** | Server-side emit with ack timeout. Mirror of client-side `callWithTimeout`. |
| SK19 | `socket.use(middleware)` | Method | Not wrapped | **Defer** | Per-socket incoming packet middleware. Rarely used but exists. |
| SK20 | `socket.volatile.emit(...)` | Modifier | Not wrapped | **Never** | Volatile emit (drop if client not ready). Niche optimization, bypasses reliability. |
| SK21 | `socket.compress(flag)` | Method | Not wrapped | **Never** | Per-message compression toggle. Infrastructure tuning, not protocol. |
| SK22 | `socket.broadcast.emit(...)` | Modifier | Not wrapped | **Defer** | Emit to all clients EXCEPT the sender. Extremely common pattern (chat). Could be `broadcastExceptSender` taking a `NamespaceHandle`. |

### 1.4 Server-Side System Events

| # | Event | PurSocket Status | Decision | Rationale |
|---|-------|-----------------|----------|-----------|
| SE1 | `"connection"` | Wrapped (`onConnection`) | **Keep** | Core lifecycle event. |
| SE2 | `"disconnect"` | Wrapped (`onDisconnect`) | **Keep** | Core lifecycle event. |
| SE3 | `"disconnecting"` | Not wrapped | **Defer** | Fires before disconnect, while socket is still in rooms. Useful for cleanup (e.g., notifying rooms before leaving). |
| SE4 | `"error"` | Not wrapped | **Defer** | Emitted on middleware error or namespace connection rejection. Important for error handling. |
| SE5 | `"connect_error"` (namespace) | Not wrapped | **Defer** | Namespace-level connection error. |
| SE6 | `"new_namespace"` (server) | Not wrapped | **Never** | Server-level event when a new namespace is created dynamically. Not relevant to static protocol definitions. |

---

## 2. Client-Side API

### 2.1 `io()` Factory / Manager

| # | API Item | Kind | PurSocket Status | Decision | Rationale |
|---|----------|------|-----------------|----------|-----------|
| C1 | `io(url)` | Factory | Wrapped (`connect`) | **Keep** | Core connection function. |
| C2 | `io(url, options)` | Factory | Not wrapped | **Defer** | Connection options: `auth`, `query`, `transports`, `reconnection`, `reconnectionAttempts`, `reconnectionDelay`, `timeout`, `autoConnect`, `extraHeaders`, etc. Essential for auth and tuning. Should accept an options record. |
| C3 | `manager.open()` / `manager.connect()` | Method | Not wrapped | **Never** | Manual reconnection trigger. Niche use case. |
| C4 | `manager.socket(namespace, opts)` | Method | Partially wrapped (`joinNs`) | **Keep** | PurSocket's `joinNs` uses `io(baseUrl + "/" + ns)` which creates a new Manager per namespace. Consider whether sharing a Manager matters (performance). |
| C5 | `manager.reconnection(flag)` | Method | Not wrapped | **Defer** | Toggle reconnection. Bundle with C2 options. |
| C6 | `manager.reconnectionAttempts(n)` | Method | Not wrapped | **Defer** | Bundle with C2 options. |
| C7 | `manager.reconnectionDelay(ms)` | Method | Not wrapped | **Defer** | Bundle with C2 options. |
| C8 | `manager.reconnectionDelayMax(ms)` | Method | Not wrapped | **Defer** | Bundle with C2 options. |
| C9 | `manager.timeout(ms)` | Method | Not wrapped | **Defer** | Connection timeout. Bundle with C2 options. |

### 2.2 Manager Events

| # | Event | PurSocket Status | Decision | Rationale |
|---|-------|-----------------|----------|-----------|
| ME1 | `"open"` / `"connect"` | Not wrapped (on Manager) | **Defer** | Low-level transport connection. Less useful than socket "connect". |
| ME2 | `"error"` | Not wrapped | **Defer** | Connection error. Important for error handling. |
| ME3 | `"close"` / `"disconnect"` | Not wrapped | **Defer** | Transport disconnection. |
| ME4 | `"ping"` | Not wrapped | **Never** | Heartbeat ping. Infrastructure monitoring, not protocol. |
| ME5 | `"reconnect"` | Not wrapped | **Defer** | Successful reconnection. Useful for UI feedback. |
| ME6 | `"reconnect_attempt"` | Not wrapped | **Defer** | Each reconnection attempt. Useful for UI feedback. |
| ME7 | `"reconnect_error"` | Not wrapped | **Defer** | Failed reconnection attempt. |
| ME8 | `"reconnect_failed"` | Not wrapped | **Defer** | All reconnection attempts exhausted. Critical for error handling. |

### 2.3 Client-Side Socket Class

| # | API Item | Kind | PurSocket Status | Decision | Rationale |
|---|----------|------|-----------------|----------|-----------|
| CS1 | `socket.id` | Property | Not wrapped (client-side) | **Defer** | Client can read its own ID. Useful for identifying self in broadcasts. Server-side `socketId` exists but no client equivalent. |
| CS2 | `socket.connected` | Property | Not wrapped | **Defer** | Boolean connection state. Useful for guards before emitting. |
| CS3 | `socket.disconnected` | Property | Not wrapped | **Never** | Inverse of CS2. Redundant. |
| CS4 | `socket.io` (manager) | Property | Partially wrapped | **Never** | Used internally by `joinNs` to extract `socket.io.uri`. Not needed in public API. |
| CS5 | `socket.auth` | Property | Not wrapped | **Defer** | Auth credentials. Bundle with C2 connection options. |
| CS6 | `socket.recovered` | Property | Not wrapped | **Defer** | Connection recovery status (v4.6+). |
| CS7 | `socket.emit(event, ...args)` | Method | Wrapped (`emit`) | **Keep** | Core emit function with type safety. |
| CS8 | `socket.emit(event, ...args, ack)` | Method | Wrapped (`call` / `callWithTimeout`) | **Keep** | Acknowledgement pattern. Works correctly. |
| CS9 | `socket.on(event, callback)` | Method | Wrapped (`onMsg`) | **Keep** | Core listener for s2c events. |
| CS10 | `socket.once(event, callback)` | Method | Not wrapped | **Defer** | One-time listener. Useful but not critical. |
| CS11 | `socket.off(event, callback)` | Method | Not wrapped | **Defer** | Remove listener. Important for cleanup in SPAs. |
| CS12 | `socket.removeAllListeners(event?)` | Method | Not wrapped | **Defer** | Remove all listeners for an event. |
| CS13 | `socket.connect()` | Method | Not wrapped | **Defer** | Manual connect (when `autoConnect: false`). Bundle with C2 options. |
| CS14 | `socket.disconnect()` | Method | Wrapped (`disconnect`) | **Keep** | Works correctly. |
| CS15 | `socket.compress(flag)` | Method | Not wrapped | **Never** | Per-message compression. Infrastructure tuning. |
| CS16 | `socket.volatile.emit(...)` | Modifier | Not wrapped | **Never** | Volatile emit. Same rationale as server-side. |
| CS17 | `socket.timeout(ms).emit(...)` | Method | Wrapped (`callWithTimeout`) | **Keep** | Timeout on ack. Works correctly. |

### 2.4 Client-Side System Events

| # | Event | PurSocket Status | Decision | Rationale |
|---|-------|-----------------|----------|-----------|
| CE1 | `"connect"` | Wrapped (`onConnect`) | **Keep** | Core lifecycle event. |
| CE2 | `"disconnect"` | Not wrapped (client-side) | **Defer** | Client-side disconnect notification. Important for UI feedback and reconnection logic. Callback receives a `reason` string. |
| CE3 | `"connect_error"` | Not wrapped | **Defer** | Connection error with error object. Critical for auth rejection handling and retry logic. |
| CE4 | `"reconnect"` (via Manager) | Not wrapped | **Defer** | See ME5. |
| CE5 | `"reconnect_attempt"` (via Manager) | Not wrapped | **Defer** | See ME6. |
| CE6 | `"reconnect_error"` (via Manager) | Not wrapped | **Defer** | See ME7. |
| CE7 | `"reconnect_failed"` (via Manager) | Not wrapped | **Defer** | See ME8. |

---

## 3. Cross-Cutting Concerns

### 3.1 Rooms

| # | Feature | PurSocket Status | Decision | Rationale |
|---|---------|-----------------|----------|-----------|
| R1 | `socket.join(room)` | Not wrapped | **Defer** | Rooms are the primary sub-namespace grouping mechanism. Very common in chat, games, collaborative editing. Should be a first-class PurSocket feature with type-level room names if possible. |
| R2 | `socket.leave(room)` | Not wrapped | **Defer** | Counterpart to R1. |
| R3 | `socket.rooms` | Not wrapped | **Defer** | Query which rooms a socket is in. |
| R4 | `io.to(room).emit(...)` / `socket.to(room).emit(...)` | Not wrapped | **Defer** | Room-scoped broadcast. The most important rooms API. |
| R5 | `io.except(room).emit(...)` | Not wrapped | **Defer** | Broadcast excluding rooms. |
| R6 | `io.in(room).fetchSockets()` | Not wrapped | **Defer** | Query sockets in a room. |
| R7 | `io.in(room).socketsJoin(otherRoom)` | Not wrapped | **Defer** | Bulk room operations. |
| R8 | `io.in(room).socketsLeave(otherRoom)` | Not wrapped | **Defer** | Bulk room operations. |
| R9 | `io.in(room).disconnectSockets(close?)` | Not wrapped | **Defer** | Bulk disconnect by room. |

**Rooms design note:** Rooms could be modeled as a type-level `Set` of `Symbol`s in the protocol, or they could be purely runtime strings. The type-level approach would catch room name typos at compile time but adds complexity. A reasonable first step would be a `Room` newtype with `IsSymbol` constraint for compile-time room name literals, without full type-level room membership tracking.

### 3.2 Middleware

| # | Feature | PurSocket Status | Decision | Rationale |
|---|---------|-----------------|----------|-----------|
| M1 | `server.use(fn)` | Not wrapped | **Defer** | Server-level middleware runs on every incoming connection. The `fn` receives `(socket, next)`. Critical for authentication (e.g., JWT validation). |
| M2 | `namespace.use(fn)` | Not wrapped | **Defer** | Same as M1 but per-namespace. More granular auth. |
| M3 | `socket.use(fn)` | Not wrapped | **Defer** | Per-socket incoming packet middleware. Runs on every incoming event. Could be used for rate limiting or payload validation (though PurSocket's types handle validation). |

**Middleware design note:** Middleware operates outside the typed protocol -- it intercepts raw packets before they reach typed handlers. The PurSocket wrapper should accept `SocketRef -> (Effect Unit) -> Effect Unit` (pass/reject pattern) without trying to type the intercepted data. Authentication middleware is the highest-priority use case.

### 3.3 Broadcasting Modifiers

| # | Feature | PurSocket Status | Decision | Rationale |
|---|---------|-----------------|----------|-----------|
| B1 | `.to(room)` | Not wrapped | **Defer** | See rooms section. |
| B2 | `.except(room)` | Not wrapped | **Defer** | See rooms section. |
| B3 | `.volatile` | Not wrapped | **Never** | Unreliable delivery. Counter to PurSocket's correctness goals. |
| B4 | `.local` | Not wrapped | **Defer** | Emit only to sockets on this server (no adapter broadcast). Cluster-only concern. |
| B5 | `.compress(flag)` | Not wrapped | **Never** | Infrastructure tuning. |
| B6 | `socket.broadcast.emit(...)` | Not wrapped | **Defer** | Emit to all except sender. Very common pattern. See SK22. |

### 3.4 Connection State Recovery (v4.6+)

| # | Feature | PurSocket Status | Decision | Rationale |
|---|---------|-----------------|----------|-----------|
| CR1 | `connectionStateRecovery` server option | Not wrapped | **Defer** | Enables automatic reconnection with buffered events. Bundle with server options (S20). |
| CR2 | `socket.recovered` (server) | Not wrapped | **Defer** | See SK7. |
| CR3 | `socket.recovered` (client) | Not wrapped | **Defer** | See CS6. |

### 3.5 Emit-to-Single-Client (Server-Side)

| # | Feature | PurSocket Status | Decision | Rationale |
|---|---------|-----------------|----------|-----------|
| E1 | `socket.emit(event, data)` (server to specific client) | **Not wrapped** | **Defer (HIGH PRIORITY)** | This is the most significant gap in PurSocket today. `broadcast` sends to ALL clients in a namespace. There is no way to send a typed message to a single specific client from the server. A function like `emitTo :: NamespaceHandle ns -> payload -> Effect Unit` that emits on the individual socket (not the namespace) is essential for direct messaging, game state updates to specific players, error responses, etc. |

---

## 4. Summary Statistics

| Category | Keep | Defer | Never | Total |
|----------|------|-------|-------|-------|
| Server Class | 3 | 5 | 4 | 12 |
| Namespace Class | 2 | 9 | 2 | 13 |
| Server Socket | 2 | 11 | 3 | 16 |
| Server Events | 2 | 3 | 1 | 6 |
| Client Factory/Manager | 1 | 7 | 1 | 9 |
| Manager Events | 0 | 6 | 1 | 7 (excluding ping) |
| Client Socket | 5 | 5 | 3 | 13 |
| Client Events | 1 | 6 | 0 | 7 |
| Rooms | 0 | 9 | 0 | 9 |
| Middleware | 0 | 3 | 0 | 3 |
| Broadcasting Modifiers | 0 | 3 | 2 | 5 (excl. dupes) |
| Connection Recovery | 0 | 3 | 0 | 3 |
| Emit-to-Single-Client | 0 | 1 | 0 | 1 |
| **Total** | **16** | **71** | **17** | **104** |

**Currently wrapped: 16 items (15% of total Socket.io API surface)**

---

## 5. Prioritized Defer List (Recommended Build Order)

### Priority 1 -- Next cycle (core gaps)

1. **E1: Server emit to single client** -- Most significant functional gap. Without this, servers cannot send targeted messages.
2. **SK22/B6: Broadcast-except-sender** -- Extremely common pattern (every chat app needs "send to everyone else").
3. **S1/S4: HTTP server attachment** -- Already identified as Task 3/I2. Required for Express/Koa integration.
4. **C2: Client connection options** -- Auth tokens, reconnection config. Needed for any production app.
5. **S20: Server constructor options** -- CORS, timeouts, transports. Needed for any production deployment.

### Priority 2 -- Near-term (rooms and middleware)

6. **R1-R5: Basic rooms support** -- `join`, `leave`, `to(room).emit()`. Very common pattern.
7. **M1-M2: Server/namespace middleware** -- Authentication is the primary use case.
8. **CE2-CE3: Client disconnect and connect_error events** -- Error handling and reconnection UI.
9. **SE3: "disconnecting" event** -- Cleanup before room departure.
10. **SK2: socket.handshake** -- Auth data access on server side.

### Priority 3 -- Later (completeness)

11. **CS1: Client-side socket.id** -- Self-identification.
12. **SK10-SK12, CS10-CS12: once/off/removeAllListeners** -- Listener management.
13. **SK4: socket.data** -- Session state.
14. **S11/N8: fetchSockets** -- Admin/monitoring.
15. **SK17: Server-side socket.disconnect()** -- Kick/ban.

### Priority 4 -- Cluster/advanced (only when needed)

16. **S12-S13/N12: serverSideEmit** -- Multi-server cluster communication.
17. **CR1-CR3: Connection state recovery** -- Automatic reconnection with event buffering.
18. **ME5-ME8: Manager reconnection events** -- Reconnection lifecycle visibility.
19. **B4: .local modifier** -- Cluster-only broadcasting.

---

## 6. Never List (With Rationale)

| Item | Rationale |
|------|-----------|
| `server.engine` | Low-level Engine.IO internals. Not relevant to typed protocol layer. |
| `server.sockets` | Alias for `server.of("/")`. PurSocket uses explicit namespace handles. |
| `server.path()` | One-time configuration, set via constructor options. |
| `server.adapter()` | Infrastructure (Redis adapter etc.), not protocol. Configure in JS. |
| `server.httpAllowRequest()` | Raw HTTP handshake. Security layer, not protocol. |
| `namespace.name` | Redundant: available via `reflectSymbol` on the phantom type. |
| `namespace.adapter` | Same as server.adapter. |
| `socket.conn` | Low-level Engine.IO connection. Not protocol-relevant. |
| `socket.request` | Raw HTTP request. Infrastructure concern. |
| `socket.volatile.emit()` | Intentionally unreliable delivery. Contradicts correctness goals. |
| `socket.compress()` | Per-message compression tuning. Infrastructure, not protocol. |
| `manager.open()` / `manager.connect()` | Niche manual reconnection. Covered by reconnection options. |
| `socket.disconnected` (client) | Inverse of `socket.connected`. Redundant. |
| `socket.io` (manager property) | Used internally. Not needed in public API. |
| Manager `"ping"` event | Heartbeat monitoring. Infrastructure, not protocol. |
| `.volatile` broadcast modifier | Unreliable delivery. See above. |
| `.compress()` broadcast modifier | Infrastructure tuning. See above. |
| `new_namespace` server event | Dynamic namespace creation. PurSocket uses static protocol definitions. |

---

## 7. Design Notes for Future Implementers

### Emit-to-single-client pattern (E1)

The server-side `NamespaceHandle ns` already holds the individual client's `SocketRef`. The `broadcast` function bypasses it by calling `io.of(ns).emit()`. A new `emitTo` function should call `socket.emit()` on the handle's `SocketRef` directly:

```
emitTo
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> payload
  -> Effect Unit
```

This requires no new FFI -- the existing `primEmit` from Client.js (which calls `socket.emit`) could be shared, or a dedicated server-side `primEmitTo` could be added for clarity.

### Broadcast-except-sender pattern (SK22)

Socket.io's `socket.broadcast.emit()` sends to everyone in the namespace except the sending socket. This is a natural extension:

```
broadcastExceptSender
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> payload
  -> Effect Unit
```

FFI: `socket.broadcast.emit(event, payload)`

### Rooms design

Rooms could use a simple `RoomName` newtype over `String` for the first iteration, with `IsSymbol`-based constructors for compile-time room name literals. Full type-level room tracking (knowing which rooms a socket is in at compile time) is likely not worth the complexity.

### Options records

Both `createServer` and `connect` should eventually accept optional configuration via PureScript records. A good pattern is a `defaultServerOptions` value that users can override with record update syntax, avoiding the need for complex optionality in the type.
