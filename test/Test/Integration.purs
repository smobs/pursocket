-- | Test.Integration
-- |
-- | Integration tests proving PurSocket works end-to-end with a real
-- | Socket.io server.  Tests run in Node.js with both client and server
-- | in the same process.
module Test.Integration
  ( integrationSpec
  ) where

import Prelude

import Data.Either (Either(..))
import Effect.Aff (Aff, makeAff, nonCanceler, delay)
import Effect.Aff.Class (liftAff)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Effect.Ref as Ref
import Data.Time.Duration (Milliseconds(..))
import PurSocket.Client as Client
import PurSocket.Server as Server
import PurSocket.Framework (NamespaceHandle, SocketRef)
import PurSocket.Example.Protocol (AppProtocol)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- | Port used for integration tests.  Avoids conflicts with any
-- | running application servers.
testPort :: Int
testPort = 3456

testUrl :: String
testUrl = "http://localhost:" <> show testPort

-- | Wait for a client socket to connect.  Returns an Aff that resolves
-- | when the "connect" event fires on the socket.
waitForConnect :: SocketRef -> Aff Unit
waitForConnect sock = makeAff \callback -> do
  Client.onConnect sock (callback (Right unit))
  pure nonCanceler

-- | Wait for a NamespaceHandle's underlying socket to connect.
-- | The namespace socket (from `join`) has its own connect lifecycle.
waitForNsConnect :: forall ns. NamespaceHandle ns -> Aff Unit
waitForNsConnect _ = do
  -- Small delay to let the namespace connection establish.
  -- Socket.io namespace connections are near-instant over localhost,
  -- but the event loop needs a tick.
  delay (Milliseconds 100.0)

integrationSpec :: Spec Unit
integrationSpec = do
  describe "Integration" do
    describe "emit (c2s)" do
      it "client emits chat message, server receives it" do
        -- Start server
        server <- liftEffect $ Server.createServerWithPort testPort

        -- Set up a Ref to capture the payload received by the server
        receivedRef <- liftEffect $ Ref.new ""

        -- Register the server-side handler BEFORE client connects
        liftEffect $ Server.onConnection @"lobby" server \handle -> do
          Server.onEvent @AppProtocol @"lobby" @"chat" handle \payload -> do
            Ref.write payload.text receivedRef

        -- Connect client
        sock <- liftEffect $ Client.connect testUrl
        liftAff $ waitForConnect sock

        -- Join namespace
        lobby <- liftEffect $ Client.joinNs @"lobby" sock
        liftAff $ waitForNsConnect lobby

        -- Emit a message
        liftEffect $ Client.emit @AppProtocol @"lobby" @"chat" lobby { text: "hello integration" }

        -- Give the server time to receive the message
        liftAff $ delay (Milliseconds 200.0)

        -- Verify
        received <- liftEffect $ Ref.read receivedRef
        received `shouldEqual` "hello integration"

        -- Cleanup
        liftEffect $ Client.disconnect sock
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)

    describe "broadcast (s2c)" do
      it "server broadcasts userCount, client receives it" do
        -- Start server
        server <- liftEffect $ Server.createServerWithPort (testPort + 1)

        -- Ref to capture what the client receives
        receivedRef <- liftEffect $ Ref.new 0

        -- Use onConnection to know when the client has connected,
        -- then broadcast from there to guarantee delivery.
        liftEffect $ Server.onConnection @"lobby" server \_ -> do
          Server.broadcast @AppProtocol @"lobby" @"userCount" server { count: 42 }

        -- Connect client
        sock <- liftEffect $ Client.connect ("http://localhost:" <> show (testPort + 1))
        liftAff $ waitForConnect sock

        -- Join namespace
        lobby <- liftEffect $ Client.joinNs @"lobby" sock

        -- Set up client-side listener for s2c messages BEFORE the
        -- namespace connection completes.  The socket from join
        -- auto-connects; we register the listener immediately so
        -- we don't miss the broadcast.
        liftEffect $ Client.onMsg @AppProtocol @"lobby" @"userCount" lobby \payload -> do
          Ref.write payload.count receivedRef

        -- Give time for connection + broadcast + delivery
        liftAff $ delay (Milliseconds 500.0)

        -- Verify
        received <- liftEffect $ Ref.read receivedRef
        received `shouldEqual` 42

        -- Cleanup
        liftEffect $ Client.disconnect sock
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)

    describe "call (request/response)" do
      it "client sends join call, server responds with success" do
        -- Start server
        server <- liftEffect $ Server.createServerWithPort (testPort + 2)

        -- Register the server-side call handler
        liftEffect $ Server.onConnection @"lobby" server \handle -> do
          Server.onCallEvent @AppProtocol @"lobby" @"join" handle \payload -> do
            log ("Call received from: " <> payload.name)
            pure { success: true }

        -- Connect client
        sock <- liftEffect $ Client.connect ("http://localhost:" <> show (testPort + 2))
        liftAff $ waitForConnect sock

        -- Join namespace
        lobby <- liftEffect $ Client.joinNs @"lobby" sock
        liftAff $ waitForNsConnect lobby

        -- Make the call
        res <- Client.call @AppProtocol @"lobby" @"join" lobby { name: "Alice" }

        -- Verify response
        res.success `shouldEqual` true

        -- Cleanup
        liftEffect $ Client.disconnect sock
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)

    describe "onEvent (server handler)" do
      it "server onEvent handler receives typed payload" do
        -- Start server
        server <- liftEffect $ Server.createServerWithPort (testPort + 3)

        -- Capture payload fields individually
        xRef <- liftEffect $ Ref.new 0
        yRef <- liftEffect $ Ref.new 0

        -- Register the server-side event handler on "game" namespace
        liftEffect $ Server.onConnection @"game" server \handle -> do
          Server.onEvent @AppProtocol @"game" @"move" handle \payload -> do
            Ref.write payload.x xRef
            Ref.write payload.y yRef

        -- Connect client
        sock <- liftEffect $ Client.connect ("http://localhost:" <> show (testPort + 3))
        liftAff $ waitForConnect sock

        -- Join game namespace
        game <- liftEffect $ Client.joinNs @"game" sock
        liftAff $ waitForNsConnect game

        -- Emit a move
        liftEffect $ Client.emit @AppProtocol @"game" @"move" game { x: 7, y: 13 }

        -- Give the server time to receive
        liftAff $ delay (Milliseconds 200.0)

        -- Verify
        x <- liftEffect $ Ref.read xRef
        y <- liftEffect $ Ref.read yRef
        x `shouldEqual` 7
        y `shouldEqual` 13

        -- Cleanup
        liftEffect $ Client.disconnect sock
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)
