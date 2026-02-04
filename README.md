# PurSocket

Type-safe Socket.io for PureScript. Define your protocol once, enforce it everywhere at compile time, with zero runtime overhead.

## What PurSocket Does

PurSocket wraps Socket.io with PureScript's type system so that event names, payload types, and message directions (client-to-server vs. server-to-client) are validated at compile time. If your protocol says the `"lobby"` namespace has a `"chat"` event with payload `{ text :: String }`, then:

- `emit @AppProtocol @"lobby" @"chat" handle { text: "Hello" }` compiles.
- `emit @AppProtocol @"lobby" @"caht" handle { text: "Hello" }` does not (typo in event name).
- `emit @AppProtocol @"lobby" @"userCount" handle { count: 1 }` does not (wrong direction -- `userCount` is server-to-client).

The compiled JavaScript is identical to hand-written Socket.io code. All type-level machinery erases at compile time.

## Installation

PurSocket is not yet on the PureScript Registry. Install as a git dependency.

### spago.yaml

Add PurSocket to your `extraPackages` in the workspace section, then add it as a dependency:

```yaml
workspace:
  packageSet:
    registry: 72.0.1
  extraPackages:
    pursocket:
      git: https://github.com/toby/pursocket.git
      ref: main

package:
  name: my-app
  dependencies:
    - pursocket
    - prelude
    - effect
    - aff
```

### npm peer dependencies

PurSocket requires Socket.io packages as peer dependencies:

```bash
# Client-side (browser or Node)
npm install socket.io-client

# Server-side (Node only)
npm install socket.io
```

Both `socket.io` and `socket.io-client` version `^4.7.0` are required.

## New Project Setup

This section covers the steps to go from an empty directory to a running PurSocket project. For a full walkthrough, see `docs/GETTING_STARTED.md`.

### Step 1: Initialize and configure Spago

```bash
spago init
```

Then edit `spago.yaml` to add PurSocket as a git dependency (see the [Installation](#installation) section above for the full `spago.yaml` snippet). Make sure your `dependencies` list includes `pursocket`, `prelude`, `effect`, and `aff`.

### Step 2: Install npm peer dependencies and bundler

```bash
npm install socket.io socket.io-client esbuild
```

`socket.io` is the server library, `socket.io-client` is for browser or Node clients, and `esbuild` bundles the compiled PureScript ESM output into a single file the browser can load.

### Step 3: Create a server entry-point

PureScript compiles to ES modules via `purs-backend-es`. You need a small JavaScript file to create the HTTP server, attach Socket.io, and call into your PureScript code. Save this as `start-server.mjs`:

```js
import { createServer } from "http";
import { Server } from "socket.io";
import { main } from "./output-es/MyApp.Server/index.js"; // your compiled PS module

const httpServer = createServer();                // 1. Create an HTTP server
const io = new Server(httpServer);                // 2. Attach Socket.io to it
main(io)();                                       // 3. Pass io into PureScript (see Step 5)
httpServer.listen(3000, () =>                     // 4. Start listening
  console.log("Running on http://localhost:3000")
);
```

If you need to serve static files (HTML, bundled JS), add a request handler to `createServer()`. See `examples/chat/start-server.mjs` for a complete example with static file serving.

### Step 4: Bundle the browser client

After `spago build`, bundle the client module for the browser:

```bash
npx esbuild output-es/MyApp.Client/index.js --bundle --format=esm --platform=browser --outfile=static/client.bundle.js
```

Then load the bundle in your HTML with `<script type="module" src="client.bundle.js"></script>`.

### Step 5: PureScript Effect calling convention

When JavaScript code calls a PureScript `Effect` function, every argument is passed one at a time (curried), and the final `()` triggers the effect:

```js
// PureScript: main :: ServerSocket -> Effect Unit
// JavaScript: main is  function(io) { return function() { ... } }
main(io)();    // pass the argument, then () to run the effect
```

If a function takes two arguments (`f :: A -> B -> Effect Unit`), call it as `f(a)(b)()`. The trailing `()` is always required -- without it, nothing happens.

## Quick Start

### 1. Define Your Protocol

A protocol is a nested row type. The outer row maps namespace names to definitions. Each namespace has `c2s` (client-to-server) and `s2c` (server-to-client) directions, each containing events tagged as `Msg` (fire-and-forget) or `Call` (request/response).

```purescript
module MyApp.Protocol where

import PurSocket.Protocol (Msg, Call)

type AppProtocol =
  ( lobby ::
      ( c2s ::
          ( chat :: Msg { text :: String }
          , join :: Call { name :: String } { success :: Boolean }
          )
      , s2c :: ( userCount :: Msg { count :: Int } )
      )
  , game ::
      ( c2s :: ( move :: Msg { x :: Int, y :: Int } )
      , s2c :: ( gameOver :: Msg { winner :: String } )
      )
  )
```

### 2. Client: Connect and Send Messages

```purescript
module MyApp.Client where

import Prelude
import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)
import PurSocket.Client (connect, joinNs, emit, call)
import MyApp.Protocol (AppProtocol)

main :: Effect Unit
main = launchAff_ do
  socket <- liftEffect $ connect "http://localhost:3000"
  lobby <- liftEffect $ joinNs @"lobby" socket

  -- Fire-and-forget message
  liftEffect $ emit @AppProtocol @"lobby" @"chat" lobby { text: "Hello!" }

  -- Request/response with acknowledgement
  res <- call @AppProtocol @"lobby" @"join" lobby { name: "Alice" }
  liftEffect $ log ("Join success: " <> show res.success)
```

### 3. Server: Handle Events and Broadcast

```purescript
module MyApp.Server where

import Prelude
import Effect (Effect)
import Effect.Console (log)
import PurSocket.Server (createServerWithPort, onConnection, onEvent, broadcast)
import MyApp.Protocol (AppProtocol)

main :: Effect Unit
main = do
  server <- createServerWithPort 3000

  onConnection @"lobby" server \handle -> do
    onEvent @AppProtocol @"lobby" @"chat" handle \payload ->
      log ("Chat: " <> payload.text)

    broadcast @AppProtocol @"lobby" @"userCount" server { count: 1 }
```

### 4. See a Compiler Error

```purescript
-- Typo in event name: "caht" instead of "chat"
emit @AppProtocol @"lobby" @"caht" lobby { text: "Hello!" }
```

The compiler produces:

```
PurSocket: invalid Msg event.
  Namespace: "lobby"
  Event:     "caht"
  Direction: "c2s"
  Check that the event name exists in this namespace/direction and is tagged as Msg.
```

## API Reference

### PurSocket.Protocol

Defines the data kinds used to tag events in a protocol.

| Export | Type | Description |
|--------|------|-------------|
| `Msg` | `data Msg (payload :: Type)` | Fire-and-forget message tag |
| `Call` | `data Call (payload :: Type) (response :: Type)` | Request/response (acknowledgement) tag |

### PurSocket.Framework

Type-level validation engine and capability token.

| Export | Type | Description |
|--------|------|-------------|
| `NamespaceHandle` | `data NamespaceHandle (ns :: Symbol)` | Phantom-typed capability token for a namespace. Obtained via `joinNs` (client) or `onConnection` (server). |
| `IsValidMsg` | `class IsValidMsg protocol ns event dir payload` | Validates that a `Msg` event exists in the given namespace/direction. Fundep: `protocol ns event dir -> payload`. |
| `IsValidCall` | `class IsValidCall protocol ns event dir payload response` | Validates that a `Call` event exists in the given namespace/direction. Fundep: `protocol ns event dir -> payload response`. |

### PurSocket.Client

Client-side API. All `emit` and `call` functions are constrained to the `c2s` direction.

| Function | Signature | Description |
|----------|-----------|-------------|
| `connect` | `String -> Effect SocketRef` | Connect to a Socket.io server at the given URL |
| `joinNs` | `forall @ns. IsSymbol ns => SocketRef -> Effect (NamespaceHandle ns)` | Join a namespace, obtaining a capability token |
| `emit` | `forall @protocol @ns @event payload. IsValidMsg protocol ns event "c2s" payload => IsSymbol event => NamespaceHandle ns -> payload -> Effect Unit` | Emit a fire-and-forget message |
| `call` | `forall @protocol @ns @event payload res. IsValidCall protocol ns event "c2s" payload res => IsSymbol event => NamespaceHandle ns -> payload -> Aff res` | Request/response call with default timeout (5000ms) |
| `callWithTimeout` | `... => NamespaceHandle ns -> Int -> payload -> Aff res` | Like `call` with a custom timeout in milliseconds |
| `onMsg` | `forall @protocol @ns @event payload. IsValidMsg protocol ns event "s2c" payload => IsSymbol event => NamespaceHandle ns -> (payload -> Effect Unit) -> Effect Unit` | Listen for a server-to-client message |
| `onConnect` | `SocketRef -> Effect Unit -> Effect Unit` | Register a callback for when the socket connects |
| `disconnect` | `SocketRef -> Effect Unit` | Disconnect from the server |
| `defaultTimeout` | `Int` | Default timeout for `call` (5000ms) |

### PurSocket.Server

Server-side API. `broadcast` is constrained to `s2c`; `onEvent` is constrained to `c2s`.

| Function | Signature | Description |
|----------|-----------|-------------|
| `createServer` | `Effect ServerSocket` | Create a Socket.io server (no port) |
| `createServerWithPort` | `Int -> Effect ServerSocket` | Create a server listening on the given port |
| `broadcast` | `forall @protocol @ns @event payload. IsValidMsg protocol ns event "s2c" payload => IsSymbol ns => IsSymbol event => ServerSocket -> payload -> Effect Unit` | Broadcast to all clients in a namespace |
| `onConnection` | `forall @ns. IsSymbol ns => ServerSocket -> (NamespaceHandle ns -> Effect Unit) -> Effect Unit` | Register a connection handler for a namespace |
| `onEvent` | `forall @protocol @ns @event payload. IsValidMsg protocol ns event "c2s" payload => IsSymbol event => NamespaceHandle ns -> (payload -> Effect Unit) -> Effect Unit` | Register a typed event handler on a client socket |
| `onCallEvent` | `forall @protocol @ns @event payload res. IsValidCall protocol ns event "c2s" payload res => IsSymbol event => NamespaceHandle ns -> (payload -> Effect res) -> Effect Unit` | Register a handler for a `Call` event with acknowledgement |
| `closeServer` | `ServerSocket -> Effect Unit` | Close the server |

## Example

The library ships with a complete example protocol and demo modules:

- **`PurSocket.Example.Protocol`** -- An importable `AppProtocol` with lobby and game namespaces. Use this to experiment before defining your own.
- **`PurSocket.Example.Client`** -- Shows `connect`, `join`, `emit`, and `call` usage.
- **`PurSocket.Example.Server`** -- Shows `createServerWithPort`, `onConnection`, `onEvent`, and `broadcast` usage.

Both `Example.Client` and `Example.Server` import the same `AppProtocol`, demonstrating the shared contract between client and server.

## How It Works

PurSocket uses PureScript's type system to enforce protocol contracts with zero runtime cost.

### The Protocol Type

An `AppProtocol` is a nested row type with kind `Row (Row (Row Type))`. The three levels represent:

1. **Namespaces** -- Top-level labels (e.g., `"lobby"`, `"game"`) mapping to Socket.io namespaces
2. **Directions** -- `"c2s"` (client-to-server) and `"s2c"` (server-to-client)
3. **Events** -- Event names mapping to `Msg payload` or `Call payload response`

### Type-Level Validation

When you write `emit @AppProtocol @"lobby" @"chat" handle { text: "Hello" }`, the compiler resolves the `IsValidMsg` constraint by walking the protocol:

1. `RowToList` converts the protocol row to a type-level list
2. `LookupNamespace` finds `"lobby"` in the list
3. `LookupDirection` finds `"c2s"` in the namespace definition
4. `LookupMsgEvent` finds `"chat"` and extracts its payload type `{ text :: String }`

If any lookup fails, an instance chain fallback produces a custom error via `Prim.TypeError.Fail`.

### NamespaceHandle

`NamespaceHandle (ns :: Symbol)` is a phantom-typed newtype over the raw Socket.io socket. The phantom parameter ties the handle to a specific namespace so that the compiler can verify events belong to that namespace. You cannot construct a `NamespaceHandle` directly -- it is obtained only via `joinNs` (client) or `onConnection` (server).

### Protocol Namespaces and Socket.io Namespaces

PurSocket protocol namespaces map directly to Socket.io namespaces (not rooms). Each namespace has independent connection semantics, isolated event handlers, and a separate socket object. The `joinNs` function connects to `baseUrl + "/" + ns`, and the returned handle wraps that namespace-specific socket.

## Trust Model

PurSocket's type safety guarantee depends on both peers using the same protocol definition. The library trusts the transport boundary -- it performs no runtime payload validation. This is an intentional design choice to achieve zero runtime overhead, not an oversight.

**When both peers use PurSocket** with the same `AppProtocol`, compile-time checks on the send side (`emit`, `broadcast`, `call` response) guarantee that values produced at the transport boundary match the types expected by the receiver. Socket.io faithfully round-trips record types through JSON serialization. Under these conditions, the FFI functions (which internally use `forall a` types the compiler cannot verify) are unreachable with incorrect types through PurSocket's public API.

**PurSocket does not protect against untrusted peers.** If a non-PurSocket client connects to your server, or if client and server are deployed with different protocol versions, payloads may arrive that do not match the expected types. PurSocket will not detect this -- the values will be passed through as-is, potentially causing runtime failures.

If you need to defend against untrusted peers, validate payloads at your application boundary using a library like `argonaut-codecs` before passing them into your domain logic. This is outside PurSocket's scope.

## Scope

### In v1

- Shared protocol type (`Msg` and `Call` patterns)
- Client API: `connect`, `joinNs`, `emit`, `call`, `callWithTimeout`, `onMsg`
- Server API: `createServer`, `createServerWithPort`, `broadcast`, `onConnection`, `onEvent`, `onCallEvent`, `closeServer`
- Custom type errors for invalid events, namespaces, and directions
- Browser bundling (esbuild)
- Type-safe demo with browser client and Node server

### Not in v1

- PureScript Registry publishing (install via git dependency)
- Multi-protocol support (one `AppProtocol` per application)
- Binary/non-JSON payloads
- Transport-layer configuration (polling vs. websocket, reconnection)
- Middleware or plugin system
- "Did you mean X?" suggestions in type errors

## License

MIT
