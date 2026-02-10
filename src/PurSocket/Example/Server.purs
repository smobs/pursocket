-- | PurSocket.Example.Server
-- |
-- | Example server application demonstrating PurSocket's type-safe
-- | server API.  This module shows how to create a Socket.io server,
-- | register connection handlers, listen for typed client events, and
-- | broadcast typed server events.
-- |
-- | Both this module and `PurSocket.Example.Client` import the same
-- | `AppProtocol` from `PurSocket.Example.Protocol`, proving the
-- | "shared contract" story: the protocol type is the single source
-- | of truth for both client and server.
-- |
-- | This module is for demonstration purposes only.  Real applications
-- | should define their own server entry point.
-- |
-- | Usage (conceptual -- requires a running Node.js environment):
-- | ```purescript
-- | main :: Effect Unit
-- | main = do
-- |   server <- createServerWithPort 3000
-- |   onConnection @"lobby" server \handle -> do
-- |     onEvent @AppProtocol @"lobby" @"chat" handle \payload ->
-- |       log ("Chat message: " <> payload.text)
-- |     broadcast @AppProtocol @"lobby" @"userCount" server { count: 1 }
-- | ```
module PurSocket.Example.Server
  ( exampleServer
  ) where

import Prelude

import Effect (Effect)
import Effect.Console (log)
import PurSocket.Example.Protocol (AppProtocol)
import PurSocket.Server (createServerWithPort, onConnection, onEvent, broadcast)

-- | Example server setup demonstrating PurSocket's server API.
-- |
-- | Creates a Socket.io server on port 3000, then:
-- |
-- | 1. Registers a connection handler on the "lobby" namespace.
-- |    When a client connects, the handler:
-- |    - Listens for "chat" messages (c2s) and logs them
-- |    - Broadcasts the current "userCount" (s2c) to all clients
-- |
-- | 2. Registers a connection handler on the "game" namespace.
-- |    When a client connects, the handler:
-- |    - Listens for "move" events (c2s) and logs the coordinates
-- |
-- | All event names and payload types are validated at compile time
-- | against `AppProtocol`.  Attempting to broadcast a c2s event or
-- | listen for an s2c event will produce a compile error.
-- |
-- | Type safety examples:
-- |   - `broadcast @AppProtocol @"lobby" @"userCount"` compiles
-- |     because "userCount" is an s2c Msg in the "lobby" namespace.
-- |   - `onEvent @"chat" handle` compiles because
-- |     "chat" is a c2s Msg and the handle carries the "lobby" protocol.
-- |   - `broadcast @AppProtocol @"lobby" @"chat"` would NOT compile
-- |     because "chat" is c2s, not s2c.
exampleServer :: Effect Unit
exampleServer = do
  server <- createServerWithPort 3000

  -- Handle connections on the "lobby" namespace.
  -- The type parameter @"lobby" is validated against AppProtocol.
  onConnection @AppProtocol @"lobby" server \handle -> do

    -- Listen for "chat" messages from clients.
    -- The constraint IsValidMsg AppProtocol "lobby" "chat" "c2s" payload
    -- resolves payload to { text :: String }.
    onEvent @"chat" handle \payload ->
      log ("Chat message received: " <> payload.text)

    -- Broadcast the user count to all connected clients.
    -- The constraint IsValidMsg AppProtocol "lobby" "userCount" "s2c" payload
    -- resolves payload to { count :: Int }.
    broadcast @AppProtocol @"lobby" @"userCount" server { count: 1 }

  -- Handle connections on the "game" namespace.
  onConnection @AppProtocol @"game" server \handle -> do

    -- Listen for "move" events from clients.
    -- payload resolves to { x :: Int, y :: Int }.
    onEvent @"move" handle \payload ->
      log ("Move received: (" <> show payload.x <> ", " <> show payload.y <> ")")
