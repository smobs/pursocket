-- | PurSocket.Example.Client
-- |
-- | Example client application demonstrating PurSocket's type-safe
-- | client API.  This module shows how to connect to a Socket.io
-- | server, join namespaces (obtaining `NamespaceHandle` capability
-- | tokens), emit fire-and-forget messages, and make request/response
-- | calls with acknowledgements.
-- |
-- | Both this module and `PurSocket.Example.Server` import the same
-- | `AppProtocol` from `PurSocket.Example.Protocol`, proving the
-- | "shared contract" story: the protocol type is the single source
-- | of truth for both client and server.
-- |
-- | This module is for demonstration purposes only.  Real applications
-- | should define their own client entry point.
-- |
-- | Usage (conceptual -- requires a running Socket.io server):
-- | ```purescript
-- | main :: Effect Unit
-- | main = launchAff_ do
-- |   socket <- liftEffect $ connect "http://localhost:3000"
-- |   lobby <- liftEffect $ join @"lobby" socket
-- |   liftEffect $ emit @"chat" lobby { text: "Hello!" }
-- |   res <- call @"join" lobby { name: "Alice" }
-- |   liftEffect $ log ("Join result: " <> show res.success)
-- | ```
module PurSocket.Example.Client
  ( exampleClient
  ) where

import Prelude

import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Console (log)
import PurSocket.Client (connect, joinNs, emit, call)
import PurSocket.Example.Protocol (AppProtocol)

-- | Example client demonstrating PurSocket's client API.
-- |
-- | Connects to a Socket.io server at localhost:3000, then:
-- |
-- | 1. Joins the "lobby" namespace, receiving a `NamespaceHandle "lobby"`.
-- |    This handle is a capability token -- you can only emit events
-- |    that exist in the "lobby" namespace of `AppProtocol`.
-- |
-- | 2. Emits a "chat" message (fire-and-forget `Msg`).
-- |    The compiler verifies that "chat" exists in lobby/c2s and that
-- |    the payload `{ text :: String }` matches the protocol definition.
-- |
-- | 3. Calls "join" with an acknowledgement (`Call`).
-- |    The compiler infers the response type `{ success :: Boolean }`
-- |    from the protocol definition.  The `Aff` resolves when the
-- |    server acknowledges, or rejects on timeout (default 5000ms).
-- |
-- | 4. Joins the "game" namespace and emits a "move" event,
-- |    demonstrating multi-namespace usage.
-- |
-- | Type safety examples:
-- |   - `emit @"chat" lobby { text: "Hello!" }`
-- |     compiles because "chat" is a c2s Msg in "lobby".
-- |   - `emit @"move" lobby { x: 1, y: 1 }`
-- |     would NOT compile because "move" is in "game", not "lobby".
-- |   - `emit @"userCount" lobby { count: 1 }`
-- |     would NOT compile because "userCount" is s2c, not c2s.
exampleClient :: Effect Unit
exampleClient = launchAff_ exampleClientAff

exampleClientAff :: Aff Unit
exampleClientAff = do
  -- Connect to the Socket.io server.
  -- `connect` returns an opaque `SocketRef` representing the base
  -- connection (default namespace).
  socket <- liftEffect $ connect "http://localhost:3000"

  -- Join the "lobby" namespace.
  -- The type-level parameter @"lobby" is reflected to the string
  -- "/lobby" at runtime.  The returned `NamespaceHandle "lobby"`
  -- is a capability token scoped to this namespace.
  lobby <- liftEffect $ joinNs @AppProtocol @"lobby" socket

  -- Emit a fire-and-forget chat message.
  -- The IsValidMsg constraint resolves:
  --   AppProtocol -> "lobby" -> "chat" -> "c2s" -> { text :: String }
  -- The payload type is inferred from the protocol.
  liftEffect $ emit @"chat" lobby { text: "Hello from PurSocket!" }

  -- Call "join" with an acknowledgement.
  -- The IsValidCall constraint resolves:
  --   AppProtocol -> "lobby" -> "join" -> "c2s"
  --     -> payload: { name :: String }
  --     -> response: { success :: Boolean }
  -- The response type is inferred automatically.
  res <- call @"join" lobby { name: "Alice" }
  liftEffect $ log ("Join successful: " <> show res.success)

  -- Join the "game" namespace and emit a move.
  -- Demonstrates that multiple namespaces can be used independently,
  -- each with its own handle and its own set of valid events.
  game <- liftEffect $ joinNs @AppProtocol @"game" socket
  liftEffect $ emit @"move" game { x: 10, y: 20 }
  liftEffect $ log "Move emitted to game namespace"
