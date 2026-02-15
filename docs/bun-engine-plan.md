# Plan: Add `@socket.io/bun-engine` Support to PurSocket

## Context

The relay server currently uses Node.js `http.createServer()` with Socket.IO attached via `createServerWithHttpServer`. Socket.IO now provides `@socket.io/bun-engine`, a dedicated engine that hooks into `Bun.serve()` natively — bypassing Bun's Node.js HTTP polyfill for better performance.

The key architectural difference: in the Node.js pattern, Socket.IO owns or attaches to the HTTP server. In the Bun pattern, **Bun owns the server** and Socket.IO provides a handler object that plugs into `Bun.serve()`. This means the creation path must return both the `ServerSocket` (for PureScript event handlers) and the engine handler (for JavaScript's `Bun.serve()`).

All existing handler functions (`onConnection`, `onEvent`, `broadcast`, etc.) work unchanged — they operate on the standard Socket.IO `Server` instance regardless of which engine powers it.

## Changes

### 1. New module: `PurSocket.Server.Bun` (PurSocket library)

**File: `src/PurSocket/Server/Bun.purs`**

```purescript
module PurSocket.Server.Bun
  ( BunEngineHandler
  , BunServerResult
  , BunServerConfig
  , createBunServer
  , createBunServerWith
  , defaultBunServerConfig
  ) where

foreign import data BunEngineHandler :: Type

type BunServerResult =
  { server  :: ServerSocket
  , handler :: BunEngineHandler
  }

type BunServerConfig =
  { path         :: String
  , cors         :: { origin :: String }
  , pingTimeout  :: Int
  , pingInterval :: Int
  }
-- No `port` field — port belongs to Bun.serve(), not Socket.IO

createBunServer :: Effect BunServerResult
createBunServerWith :: BunServerConfig -> Effect BunServerResult
```

**File: `src/PurSocket/Server/Bun.js`**

```javascript
import { Server as Engine } from "@socket.io/bun-engine";
import { Server } from "socket.io";

export const primCreateBunServer = (config) => () => {
  const io = new Server({
    cors: config.cors,
    pingTimeout: config.pingTimeout,
    pingInterval: config.pingInterval,
  });
  const engine = new Engine({ path: config.path });
  io.bind(engine);
  return { server: io, handler: engine.handler() };
};
```

- `server` is a standard Socket.IO `Server` — identical to what `primCreateServer` returns
- `handler` is the result of `engine.handler()` — an object with `fetch` and `websocket` fields for `Bun.serve()`
- Single FFI function handles both `createBunServer` and `createBunServerWith` (the config-less variant just passes defaults)

### 2. Add `@socket.io/bun-engine` as optional peer dependency (PurSocket library)

**File: `package.json`** — add as `optionalDependencies`:
```json
"optionalDependencies": {
  "@socket.io/bun-engine": "^0.1.0"
}
```

This ensures Node.js users don't need to install it. The `PurSocket.Server.Bun` FFI file imports from `@socket.io/bun-engine` at the top level, but ES modules are **loaded lazily** — the import only executes if PureScript code actually imports `PurSocket.Server.Bun`. Node.js consumers who only use `PurSocket.Server` never trigger the Bun FFI file, so the missing package causes no errors.

### 3. New entry point: `mainBun` (consumer relay server)

**File: `whispers-in-the-mist/packages/relay-server/src/Main.purs`** — add:

```purescript
import PurSocket.Server.Bun (BunServerResult, createBunServer)

mainBun :: Effect BunServerResult
mainBun = do
  state <- newRelayState
  analytics <- initAnalytics
  result@{ server } <- createBunServer
  setupHandlers server state analytics
  pure result
```

Key difference: returns `BunServerResult` instead of `Unit`, so the JavaScript entry point can access the handler.

### 4. New Bun entry point (consumer relay server)

**File: `whispers-in-the-mist/packages/relay-server/start-server-bun.mjs`**

```javascript
import { mainBun } from '../../output/Main/index.js';
import { networkInterfaces } from 'os';
import { join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const PUBLIC_DIR = process.env.PUBLIC_DIR || join(__dirname, '../../dist/public');
const PORT = process.env.PORT || 3020;
const ROOM_CODE_RE = /^\/[A-Z]{4}$/;

const { handler } = mainBun();

export default {
  port: PORT,
  hostname: '0.0.0.0',
  idleTimeout: 30, // must exceed Socket.IO pingInterval (25s)
  fetch(req, server) {
    const url = new URL(req.url);
    // Socket.IO requests go to the engine
    if (url.pathname.startsWith('/socket.io/')) {
      return handler.fetch(req, server);
    }
    // Static file serving via Bun.file()
    let pathname = url.pathname === '/' ? '/index.html' : url.pathname;
    if (ROOM_CODE_RE.test(pathname)) pathname = '/index.html';
    const file = Bun.file(join(PUBLIC_DIR, pathname));
    return file.exists().then(exists =>
      exists ? new Response(file) : new Response(Bun.file(join(PUBLIC_DIR, '/index.html')))
    );
  },
  websocket: handler.websocket,
};
```

### 5. Add `dev:bun` script (consumer project)

**File: `whispers-in-the-mist/package.json`** — add script:
```json
"dev:bun": "bun run generate-maps && spago build && bun run bundle && bun packages/relay-server/start-server-bun.mjs"
```

Also add `@socket.io/bun-engine` to dependencies (needed at runtime by PurSocket's Bun FFI).

## How Both Paths Coexist

```
PurSocket Library
├── PurSocket.Server          <- Node.js path (unchanged)
│   ├── Server.purs           createServer, createServerWithHttpServer, etc.
│   └── Server.js             imports "socket.io" only
│
└── PurSocket.Server.Bun      <- Bun path (new, additive)
    ├── Server/Bun.purs       createBunServer, createBunServerWith
    └── Server/Bun.js         imports "socket.io" + "@socket.io/bun-engine"

Both return ServerSocket -> all handler functions work identically
```

**Consumer chooses at the entry point level:**

| Mode | PureScript entry | JS entry | Runtime |
|------|-----------------|----------|---------|
| Node.js | `mainWithHttpServer` -> `Effect Unit` | `start-server.mjs` (Node HTTP + Socket.IO attached) | `bun run dev` or `node` |
| Bun native | `mainBun` -> `Effect BunServerResult` | `start-server-bun.mjs` (Bun.serve + engine handler) | `bun run dev:bun` |

**Dependency isolation:** `@socket.io/bun-engine` is an optional peer dependency. Node.js users never import `PurSocket.Server.Bun`, so its FFI is never loaded and the missing package causes no errors. Bun users install it and import the Bun module.

## What Does NOT Change

| File | Why |
|------|-----|
| `PurSocket/Server.purs` + `.js` | Existing Node.js path fully preserved |
| `PurSocket/Framework.purs` | Protocol validation is transport-agnostic |
| `PurSocket/Client.purs` + `.js` | Client connects via URL, unaware of server engine |
| `PurSocket/Internal.purs` | `ServerSocket` type unchanged — same Socket.IO `Server` |
| `start-server.mjs` | Preserved as the Node.js entry point |
| `Whispers/Relay/Handlers.purs` | `setupHandlers` takes `ServerSocket` regardless of engine |
| `Whispers/Protocol.purs` | Protocol definition is engine-agnostic |

## Verification

1. `cd pursocket && spago build` — PurSocket compiles with new module
2. `cd whispers-in-the-mist && spago build` — relay server compiles with `mainBun`
3. `bun run bundle` — client bundles unchanged
4. `bun run dev:bun` — start via Bun engine, verify:
   - Static files served at `http://localhost:3020/`
   - Socket.IO connects from browser (lobby create/join flow)
   - Game loop works (controller + runner communication)
5. `bun run dev` — existing Node.js path still works
6. `bun run test` — all existing tests pass
