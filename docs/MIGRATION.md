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

## `ServerConfig` refactor: `ServerTarget` sum type

`ServerConfig` no longer uses `Maybe` fields for `port` and `httpServer`. These have been replaced by a single `target :: ServerTarget` field that makes invalid combinations unrepresentable (you can no longer set both `port` and `httpServer`).

### New type: `ServerTarget`

```purescript
data ServerTarget
  = Standalone            -- no port, no HTTP server
  | OnPort Int            -- listen on a port
  | AttachedTo HttpServer -- attach to existing Node.js HTTP server
  | BoundTo BunEngine     -- bind to a @socket.io/bun-engine instance
```

### New opaque types: `HttpServer`, `BunEngine`

`Foreign` is no longer used. `HttpServer` and `BunEngine` are opaque foreign types — the JS call sites are unchanged, only PureScript type annotations change.

### `ServerConfig` field changes

| Before | After |
|--------|-------|
| `port :: Maybe Int` | removed — use `target: OnPort p` |
| `httpServer :: Maybe Foreign` | removed — use `target: AttachedTo hs` |
| _(n/a)_ | `target :: ServerTarget` (new) |
| `cors`, `path`, `pingTimeout`, `pingInterval` | unchanged |

### `createServerWith` migration

```purescript
-- Before
server <- createServerWith defaultServerConfig
server <- createServerWith (defaultServerConfig { port = Just 3000 })
server <- createServerWith (defaultServerConfig { httpServer = Just myHttp })

-- After
server <- createServerWith defaultServerConfig
server <- createServerWith (defaultServerConfig { target = OnPort 3000 })
server <- createServerWith (defaultServerConfig { target = AttachedTo myHttp })
```

### `createServerWithHttpServer` migration

The function signature changes from `Foreign` to `HttpServer`:

```purescript
-- Before
import Foreign (Foreign)
mainWithHttpServer :: Foreign -> Effect Unit

-- After
import PurSocket.Server (HttpServer)
mainWithHttpServer :: HttpServer -> Effect Unit
```

JS call sites are unchanged — `HttpServer` is an opaque type backed by the same JS object.

### New: `createServerWithBunEngine`

```purescript
import PurSocket.Server (BunEngine, createServerWithBunEngine)

mainBun :: BunEngine -> Effect Unit
mainBun engine = do
  server <- createServerWithBunEngine engine
  -- all handler functions work identically
  setupHandlers server
```

### Current `ServerConfig` fields

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `target` | `ServerTarget` | `Standalone` | How the server binds to the network |
| `cors` | `{ origin :: String }` | `{ origin: "*" }` | CORS origin setting |
| `path` | `String` | `"/socket.io"` | Socket.io path |
| `pingTimeout` | `Int` | `20000` | Ping timeout in ms |
| `pingInterval` | `Int` | `25000` | Ping interval in ms |

---

## Bun engine support

PurSocket now supports `@socket.io/bun-engine` as an alternative to Node.js HTTP. The engine is created in JavaScript and passed to PureScript — all handler functions (`onConnection`, `onEvent`, `broadcast`, etc.) work identically regardless of engine.

### Architecture

```
JS entry point               PureScript
─────────────                ──────────
new Engine(...)  ──engine──>  createServerWithBunEngine engine
                              ↓
engine.handler() ←──────────  ServerSocket (same type as Node path)
  ↓                           ↓
Bun.serve({                   onConnection, onEvent, broadcast, ...
  fetch, websocket             (all unchanged)
})
```

### Whispers-in-the-Mist relay server

Add a `mainBun` export alongside the existing `mainWithHttpServer`:

```purescript
import PurSocket.Server (BunEngine, createServerWithBunEngine)

mainBun :: BunEngine -> Effect Unit
mainBun engine = do
  state <- newRelayState
  analytics <- initAnalytics
  server <- createServerWithBunEngine engine
  setupHandlers server state analytics
```

Create `start-server-bun.mjs`:

```javascript
import { Server as Engine } from "@socket.io/bun-engine";
import { mainBun } from '../../output/Main/index.js';

const engine = new Engine({ path: "/socket.io/", pingInterval: 25000 });
mainBun(engine)();

const { websocket } = engine.handler();

export default {
  port: process.env.PORT || 3020,
  hostname: '0.0.0.0',
  idleTimeout: 30,
  fetch(req, server) {
    const url = new URL(req.url);
    if (url.pathname.startsWith('/socket.io/'))
      return engine.handleRequest(req, server);
    // Static files via Bun.file()...
  },
  websocket,
};
```

Add to `package.json`:

```json
"dependencies": { "@socket.io/bun-engine": "^0.1.0" },
"scripts": { "dev:bun": "bun run generate-maps && spago build && bun run bundle && bun packages/relay-server/start-server-bun.mjs" }
```

### What does NOT change

| Component | Why |
|-----------|-----|
| `PurSocket.Framework` | Protocol validation is transport-agnostic |
| `PurSocket.Client` | Connects via URL, unaware of server engine |
| `PurSocket.Internal` | `ServerSocket` type is unchanged |
| All handler functions | Operate on `ServerSocket` regardless of engine |
| `Whispers/Relay/Handlers.purs` | `setupHandlers` takes `ServerSocket` |
| `start-server.mjs` | Preserved as the Node.js entry point |

---

## Quick-reference: find-and-replace patterns

### Protocol-aware handles (from earlier migration)

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

### ServerTarget refactor

| Find | Replace | Scope |
|------|---------|-------|
| `import Foreign (Foreign)` | `import PurSocket.Server (HttpServer)` | Server config |
| `Foreign -> Effect` | `HttpServer -> Effect` | Type annotations |
| `port = Just 3000` | `target = OnPort 3000` | ServerConfig |
| `httpServer = Just hs` | `target = AttachedTo hs` | ServerConfig |
| `port: Nothing` | `target: Standalone` | ServerConfig |
| `httpServer: Nothing` | _(remove, not needed)_ | ServerConfig |
