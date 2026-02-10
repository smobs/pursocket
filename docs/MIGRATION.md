# Migration Guide: Protocol-Aware Handles

This guide covers the breaking changes introduced by the protocol-aware `NamespaceHandle` and the new `createServerWith` config API.

## Summary of changes

1. **`NamespaceHandle` gains a `protocol` type parameter** — handles now carry the protocol type, so most call sites drop `@protocol @ns` and only specify `@event`.
2. **`createServerWith` added** — a config-record-based server constructor supporting CORS, path, ping settings, etc.

---

## Client-side migration

### `joinNs`: add `@protocol`

`joinNs` is now the injection point where the protocol enters the handle. Add `@YourProtocol` before `@ns`:

```purescript
-- Before
lobby <- joinNs @"lobby" socket

-- After
lobby <- joinNs @AppProtocol @"lobby" socket
```

### `emit`, `call`, `callWithTimeout`, `onMsg`: drop `@protocol @ns`

These functions infer the protocol and namespace from the handle. Remove the first two type applications:

```purescript
-- Before
emit @AppProtocol @"lobby" @"chat" lobby { text: "Hello!" }
res <- call @AppProtocol @"lobby" @"join" lobby { name: "Alice" }
onMsg @AppProtocol @"lobby" @"userCount" lobby \payload -> ...

-- After
emit @"chat" lobby { text: "Hello!" }
res <- call @"join" lobby { name: "Alice" }
onMsg @"userCount" lobby \payload -> ...
```

### `NamespaceHandle` type annotations

Any explicit type annotation mentioning `NamespaceHandle` needs the protocol parameter added:

```purescript
-- Before
handleRef :: Ref (Maybe (NamespaceHandle "lobby"))

-- After
handleRef :: Ref (Maybe (NamespaceHandle AppProtocol "lobby"))
```

---

## Server-side migration

### `onConnection`: add `@protocol`

Like `joinNs`, `onConnection` is an injection point. Add `@YourProtocol` before `@ns`:

```purescript
-- Before
onConnection @"lobby" server \handle -> ...

-- After
onConnection @AppProtocol @"lobby" server \handle -> ...
```

### Handle-based functions: drop `@protocol @ns`

`onEvent`, `onCallEvent`, `emitTo`, `broadcastExceptSender`, and `broadcastToRoom` now infer protocol and namespace from the handle:

```purescript
-- Before
onEvent @AppProtocol @"lobby" @"chat" handle \payload -> ...
onCallEvent @AppProtocol @"lobby" @"join" handle \payload -> ...
emitTo @AppProtocol @"lobby" @"userCount" handle { count: 1 }
broadcastExceptSender @AppProtocol @"lobby" @"msg" handle payload
broadcastToRoom @AppProtocol @"lobby" @"msg" handle "room1" payload

-- After
onEvent @"chat" handle \payload -> ...
onCallEvent @"join" handle \payload -> ...
emitTo @"userCount" handle { count: 1 }
broadcastExceptSender @"msg" handle payload
broadcastToRoom @"msg" handle "room1" payload
```

### `broadcast`: unchanged

`broadcast` takes a `ServerSocket` (not a handle), so it still requires all three type applications:

```purescript
-- No change
broadcast @AppProtocol @"lobby" @"userCount" server { count: 42 }
```

### `joinRoom`, `leaveRoom`, `onDisconnect`, `socketId`: no call-site changes

These don't use type applications at call sites, so they work as before. Only explicit type annotations need updating (add the `protocol` parameter to `NamespaceHandle`).

---

## New: `createServerWith` config API

Three new exports from `PurSocket.Server`: `ServerConfig`, `defaultServerConfig`, and `createServerWith`. The existing `createServer`, `createServerWithPort`, and `createServerWithHttpServer` remain unchanged.

```purescript
import PurSocket.Server (createServerWith, defaultServerConfig)

-- Standalone (equivalent to createServer)
server <- createServerWith defaultServerConfig

-- With port + CORS
server <- createServerWith
  (defaultServerConfig { port = Just 3000, cors = { origin: "http://localhost:5173" } })

-- Attach to HTTP server with custom ping settings
server <- createServerWith
  (defaultServerConfig { httpServer = Just myHttpServer, pingTimeout = 30000 })
```

`ServerConfig` fields:

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `port` | `Maybe Int` | `Nothing` | Listen on this port |
| `httpServer` | `Maybe Foreign` | `Nothing` | Attach to existing HTTP server (takes priority over `port`) |
| `cors` | `{ origin :: String }` | `{ origin: "*" }` | CORS origin setting |
| `path` | `String` | `"/socket.io"` | Socket.io path |
| `pingTimeout` | `Int` | `20000` | Ping timeout in ms |
| `pingInterval` | `Int` | `25000` | Ping interval in ms |

---

## Quick-reference: find-and-replace patterns

For mechanical migration, apply these replacements in order:

| Find | Replace | Scope |
|------|---------|-------|
| `joinNs @"` | `joinNs @AppProtocol @"` | Client |
| `onConnection @"` | `onConnection @AppProtocol @"` | Server |
| `emit @AppProtocol @"ns" @"event"` | `emit @"event"` | Client |
| `call @AppProtocol @"ns" @"event"` | `call @"event"` | Client |
| `callWithTimeout @AppProtocol @"ns" @"event"` | `callWithTimeout @"event"` | Client |
| `onMsg @AppProtocol @"ns" @"event"` | `onMsg @"event"` | Client |
| `onEvent @AppProtocol @"ns" @"event"` | `onEvent @"event"` | Server |
| `onCallEvent @AppProtocol @"ns" @"event"` | `onCallEvent @"event"` | Server |
| `emitTo @AppProtocol @"ns" @"event"` | `emitTo @"event"` | Server |
| `broadcastExceptSender @AppProtocol @"ns" @"event"` | `broadcastExceptSender @"event"` | Server |
| `broadcastToRoom @AppProtocol @"ns" @"event"` | `broadcastToRoom @"event"` | Server |
| `NamespaceHandle "ns"` | `NamespaceHandle AppProtocol "ns"` | Type annotations |

Replace `AppProtocol` with your own protocol type alias throughout.
