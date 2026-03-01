# PurSocket

Type-safe Socket.io for PureScript. Define your protocol once as a row type; the compiler enforces it everywhere.

## Protocol

A protocol is a nested row type mapping namespaces to directional events:

```purescript
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

`Msg` is fire-and-forget. `Call` is request/response (maps to Socket.io acknowledgements). `c2s` and `s2c` encode direction -- the compiler prevents clients from emitting server events and vice versa.

## Client

```purescript
import PurSocket.Client (connect, joinNs, emit, call)

exampleClient :: Effect Unit
exampleClient = launchAff_ do
  socket <- liftEffect $ connect "http://localhost:3000"
  lobby  <- liftEffect $ joinNs @AppProtocol @"lobby" socket

  liftEffect $ emit @"chat" lobby { text: "Hello from PurSocket!" }

  res <- call @"join" lobby { name: "Alice" }
  liftEffect $ log ("Join successful: " <> show res.success)
```

`joinNs` returns a `NamespaceHandle protocol ns` -- a capability token that carries the protocol and namespace in its type. Subsequent `emit` and `call` infer the protocol from the handle; you only supply the event name.

## Server

```purescript
import PurSocket.Server (createServerWithPort, onConnection, onEvent, broadcast)

exampleServer :: Effect Unit
exampleServer = do
  server <- createServerWithPort 3000

  onConnection @AppProtocol @"lobby" server \handle -> do
    onEvent @"chat" handle \payload ->
      log ("Chat message received: " <> payload.text)

    broadcast @AppProtocol @"lobby" @"userCount" server { count: 1 }
```

The server API also provides `emitTo` (send to a specific client), `broadcastExceptSender`, rooms (`joinRoom`, `leaveRoom`, `broadcastToRoom`), `onDisconnect`, and `onCallEvent` for handling `Call` acknowledgements.

Server creation supports multiple targets via `ServerConfig` and `ServerTarget`: standalone with port, attached to an existing HTTP server, or bound to a Bun engine.

## What the compiler catches

```purescript
-- Typo in event name
emit @"caht" lobby { text: "Hello!" }
```

```
PurSocket: invalid Msg event.
  Namespace: "lobby"
  Event:     "caht"
  Direction: "c2s"
  Check that the event name exists in this namespace/direction and is tagged as Msg.
```

Wrong direction, wrong namespace, wrong payload type, and non-existent events all fail at compile time with similar contextual errors.

## Installation

Add PurSocket as a git dependency in `spago.yaml`:

```yaml
workspace:
  extraPackages:
    pursocket:
      git: https://github.com/toby/pursocket.git
      ref: main

package:
  dependencies:
    - pursocket
```

Install the Socket.io npm packages:

```bash
npm install socket.io socket.io-client
```

## Further reading

- [`docs/GETTING_STARTED.md`](docs/GETTING_STARTED.md) -- project setup walkthrough
- [`examples/chat/`](examples/chat/) -- working chat application with browser client and Node server

## License

MIT
