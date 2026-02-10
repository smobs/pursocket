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
import Data.Maybe (Maybe(..))
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
waitForNsConnect :: forall protocol ns. NamespaceHandle protocol ns -> Aff Unit
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
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
          Server.onEvent @"chat" handle \payload -> do
            Ref.write payload.text receivedRef

        -- Connect client
        sock <- liftEffect $ Client.connect testUrl
        liftAff $ waitForConnect sock

        -- Join namespace
        lobby <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sock
        liftAff $ waitForNsConnect lobby

        -- Emit a message
        liftEffect $ Client.emit @"chat" lobby { text: "hello integration" }

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
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \_ -> do
          Server.broadcast @AppProtocol @"lobby" @"userCount" server { count: 42 }

        -- Connect client
        sock <- liftEffect $ Client.connect ("http://localhost:" <> show (testPort + 1))
        liftAff $ waitForConnect sock

        -- Join namespace
        lobby <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sock

        -- Set up client-side listener for s2c messages BEFORE the
        -- namespace connection completes.  The socket from join
        -- auto-connects; we register the listener immediately so
        -- we don't miss the broadcast.
        liftEffect $ Client.onMsg @"userCount" lobby \payload -> do
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
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
          Server.onCallEvent @"join" handle \payload -> do
            log ("Call received from: " <> payload.name)
            pure { success: true }

        -- Connect client
        sock <- liftEffect $ Client.connect ("http://localhost:" <> show (testPort + 2))
        liftAff $ waitForConnect sock

        -- Join namespace
        lobby <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sock
        liftAff $ waitForNsConnect lobby

        -- Make the call
        res <- Client.call @"join" lobby { name: "Alice" }

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
        liftEffect $ Server.onConnection @AppProtocol @"game" server \handle -> do
          Server.onEvent @"move" handle \payload -> do
            Ref.write payload.x xRef
            Ref.write payload.y yRef

        -- Connect client
        sock <- liftEffect $ Client.connect ("http://localhost:" <> show (testPort + 3))
        liftAff $ waitForConnect sock

        -- Join game namespace
        game <- liftEffect $ Client.joinNs @AppProtocol @"game" sock
        liftAff $ waitForNsConnect game

        -- Emit a move
        liftEffect $ Client.emit @"move" game { x: 7, y: 13 }

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

    -- -----------------------------------------------------------------------
    -- Slice 3: Multi-client integration tests for emitTo, broadcastExceptSender,
    -- and room operations (joinRoom, leaveRoom, broadcastToRoom).
    -- -----------------------------------------------------------------------

    describe "emitTo (targeted delivery)" do
      it "delivers to target client and not to others" do
        -- Tests 1 & 2: emitTo positive + exclusivity negative
        server <- liftEffect $ Server.createServerWithPort (testPort + 4)

        -- Server-side handle storage
        handleARef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        handleBRef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        connectionCount <- liftEffect $ Ref.new 0

        -- Client-side received data (sentinel = 0)
        receivedA <- liftEffect $ Ref.new 0
        receivedB <- liftEffect $ Ref.new 0

        -- Server: store handles as clients connect sequentially
        -- Ref.modify returns the NEW value: 1 for first connection, 2 for second
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
          n <- Ref.modify (_ + 1) connectionCount
          case n of
            1 -> Ref.write (Just handle) handleARef
            _ -> Ref.write (Just handle) handleBRef

        let url4 = "http://localhost:" <> show (testPort + 4)

        -- Connect client A
        sockA <- liftEffect $ Client.connect url4
        liftAff $ waitForConnect sockA
        lobbyA <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockA
        liftEffect $ Client.onMsg @"userCount" lobbyA \p ->
          Ref.write p.count receivedA
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client B (sequential to guarantee handle ordering)
        sockB <- liftEffect $ Client.connect url4
        liftAff $ waitForConnect sockB
        lobbyB <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockB
        liftEffect $ Client.onMsg @"userCount" lobbyB \p ->
          Ref.write p.count receivedB
        liftAff $ delay (Milliseconds 200.0)

        -- Server emits to A only
        mHandleA <- liftEffect $ Ref.read handleARef
        case mHandleA of
          Nothing -> "handle A was stored" `shouldEqual` "handle A missing"
          Just hA -> liftEffect $ Server.emitTo @"userCount" hA { count: 99 }

        liftAff $ delay (Milliseconds 300.0)

        -- Assert: A received, B did NOT
        rA <- liftEffect $ Ref.read receivedA
        rA `shouldEqual` 99
        rB <- liftEffect $ Ref.read receivedB
        rB `shouldEqual` 0

        -- Cleanup
        liftEffect $ Client.disconnect sockA
        liftEffect $ Client.disconnect sockB
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)

    describe "broadcastExceptSender (echo prevention)" do
      it "delivers to others but not to the sender" do
        -- Tests 3 & 4: broadcastExceptSender positive + sender excluded
        server <- liftEffect $ Server.createServerWithPort (testPort + 5)

        -- Server-side handle storage
        handleARef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        connectionCount <- liftEffect $ Ref.new 0

        -- Client-side received data (sentinel = 0)
        receivedA <- liftEffect $ Ref.new 0
        receivedB <- liftEffect $ Ref.new 0

        -- Server: store first handle, set up broadcastExceptSender on chat event
        -- Ref.modify returns the NEW value: 1 for first connection, 2 for second
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
          n <- Ref.modify (_ + 1) connectionCount
          case n of
            1 -> do
              Ref.write (Just handle) handleARef
              -- When client A sends a chat message, broadcastExceptSender
              Server.onEvent @"chat" handle \_ ->
                Server.broadcastExceptSender @"userCount" handle { count: 77 }
            _ -> pure unit

        let url5 = "http://localhost:" <> show (testPort + 5)

        -- Connect client A
        sockA <- liftEffect $ Client.connect url5
        liftAff $ waitForConnect sockA
        lobbyA <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockA
        liftEffect $ Client.onMsg @"userCount" lobbyA \p ->
          Ref.write p.count receivedA
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client B
        sockB <- liftEffect $ Client.connect url5
        liftAff $ waitForConnect sockB
        lobbyB <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockB
        liftEffect $ Client.onMsg @"userCount" lobbyB \p ->
          Ref.write p.count receivedB
        liftAff $ delay (Milliseconds 200.0)

        -- Client A sends a chat message, which triggers broadcastExceptSender on server
        liftEffect $ Client.emit @"chat" lobbyA { text: "trigger" }

        liftAff $ delay (Milliseconds 300.0)

        -- Assert: B received (others), A did NOT (sender excluded)
        rB <- liftEffect $ Ref.read receivedB
        rB `shouldEqual` 77
        rA <- liftEffect $ Ref.read receivedA
        rA `shouldEqual` 0

        -- Cleanup
        liftEffect $ Client.disconnect sockA
        liftEffect $ Client.disconnect sockB
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)

    describe "rooms (joinRoom, leaveRoom, broadcastToRoom)" do
      it "broadcastToRoom delivers to room members, excludes sender and non-members" do
        -- Test 5: joinRoom + broadcastToRoom
        -- Connect A, B, C. Join A and B to "r1". C not in any room.
        -- broadcastToRoom using A's handle to "r1":
        --   B receives (in room, not sender)
        --   A does NOT receive (sender excluded)
        --   C does NOT receive (not in room)
        server <- liftEffect $ Server.createServerWithPort (testPort + 6)

        -- Server-side handle storage
        handleARef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        handleBRef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        handleCRef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        connectionCount <- liftEffect $ Ref.new 0

        -- Client-side received data (sentinel = 0)
        receivedA <- liftEffect $ Ref.new 0
        receivedB <- liftEffect $ Ref.new 0
        receivedC <- liftEffect $ Ref.new 0

        -- Server: store handles, join A and B to "r1"
        -- Ref.modify returns the NEW value: 1, 2, 3, ...
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
          n <- Ref.modify (_ + 1) connectionCount
          case n of
            1 -> do
              Ref.write (Just handle) handleARef
              Server.joinRoom handle "r1"
            2 -> do
              Ref.write (Just handle) handleBRef
              Server.joinRoom handle "r1"
            _ -> Ref.write (Just handle) handleCRef

        let url6 = "http://localhost:" <> show (testPort + 6)

        -- Connect client A
        sockA <- liftEffect $ Client.connect url6
        liftAff $ waitForConnect sockA
        lobbyA <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockA
        liftEffect $ Client.onMsg @"userCount" lobbyA \p ->
          Ref.write p.count receivedA
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client B
        sockB <- liftEffect $ Client.connect url6
        liftAff $ waitForConnect sockB
        lobbyB <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockB
        liftEffect $ Client.onMsg @"userCount" lobbyB \p ->
          Ref.write p.count receivedB
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client C (not in any room)
        sockC <- liftEffect $ Client.connect url6
        liftAff $ waitForConnect sockC
        lobbyC <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockC
        liftEffect $ Client.onMsg @"userCount" lobbyC \p ->
          Ref.write p.count receivedC
        liftAff $ delay (Milliseconds 200.0)

        -- Server broadcastToRoom "r1" using A's handle (A is sender)
        mHandleA <- liftEffect $ Ref.read handleARef
        case mHandleA of
          Nothing -> "handle A was stored" `shouldEqual` "handle A missing"
          Just hA -> liftEffect $
            Server.broadcastToRoom @"userCount" hA "r1" { count: 55 }

        liftAff $ delay (Milliseconds 300.0)

        -- Assert: B received (in room, not sender)
        rB <- liftEffect $ Ref.read receivedB
        rB `shouldEqual` 55
        -- Assert: A did NOT receive (sender excluded by broadcastToRoom)
        rA <- liftEffect $ Ref.read receivedA
        rA `shouldEqual` 0
        -- Assert: C did NOT receive (not in room)
        rC <- liftEffect $ Ref.read receivedC
        rC `shouldEqual` 0

        -- Cleanup
        liftEffect $ Client.disconnect sockA
        liftEffect $ Client.disconnect sockB
        liftEffect $ Client.disconnect sockC
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)

      it "leaveRoom stops delivery to the client that left" do
        -- Test 6: leaveRoom stops delivery
        -- Connect A, B, C. Join all three to "r1".
        -- LeaveRoom A from "r1".
        -- broadcastToRoom using B's handle to "r1":
        --   C receives (in room, not sender)
        --   A does NOT receive (left room)
        --   B does NOT receive (sender excluded)
        server <- liftEffect $ Server.createServerWithPort (testPort + 7)

        -- Server-side handle storage
        handleARef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        handleBRef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        handleCRef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        connectionCount <- liftEffect $ Ref.new 0

        -- Client-side received data (sentinel = 0)
        receivedA <- liftEffect $ Ref.new 0
        receivedB <- liftEffect $ Ref.new 0
        receivedC <- liftEffect $ Ref.new 0

        -- Server: store handles, join all to "r1"
        -- Ref.modify returns the NEW value: 1, 2, 3, ...
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
          n <- Ref.modify (_ + 1) connectionCount
          case n of
            1 -> do
              Ref.write (Just handle) handleARef
              Server.joinRoom handle "r1"
            2 -> do
              Ref.write (Just handle) handleBRef
              Server.joinRoom handle "r1"
            _ -> do
              Ref.write (Just handle) handleCRef
              Server.joinRoom handle "r1"

        let url7 = "http://localhost:" <> show (testPort + 7)

        -- Connect client A
        sockA <- liftEffect $ Client.connect url7
        liftAff $ waitForConnect sockA
        lobbyA <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockA
        liftEffect $ Client.onMsg @"userCount" lobbyA \p ->
          Ref.write p.count receivedA
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client B
        sockB <- liftEffect $ Client.connect url7
        liftAff $ waitForConnect sockB
        lobbyB <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockB
        liftEffect $ Client.onMsg @"userCount" lobbyB \p ->
          Ref.write p.count receivedB
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client C
        sockC <- liftEffect $ Client.connect url7
        liftAff $ waitForConnect sockC
        lobbyC <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockC
        liftEffect $ Client.onMsg @"userCount" lobbyC \p ->
          Ref.write p.count receivedC
        liftAff $ delay (Milliseconds 200.0)

        -- Server removes A from "r1"
        mHandleA <- liftEffect $ Ref.read handleARef
        case mHandleA of
          Nothing -> "handle A was stored" `shouldEqual` "handle A missing"
          Just hA -> liftEffect $ Server.leaveRoom hA "r1"

        liftAff $ delay (Milliseconds 100.0)

        -- Server broadcastToRoom "r1" using B's handle
        mHandleB <- liftEffect $ Ref.read handleBRef
        case mHandleB of
          Nothing -> "handle B was stored" `shouldEqual` "handle B missing"
          Just hB -> liftEffect $
            Server.broadcastToRoom @"userCount" hB "r1" { count: 66 }

        liftAff $ delay (Milliseconds 300.0)

        -- Assert: C received (in room, not sender)
        rC <- liftEffect $ Ref.read receivedC
        rC `shouldEqual` 66
        -- Assert: A did NOT receive (left room)
        rA <- liftEffect $ Ref.read receivedA
        rA `shouldEqual` 0
        -- Assert: B did NOT receive (sender excluded)
        rB <- liftEffect $ Ref.read receivedB
        rB `shouldEqual` 0

        -- Cleanup
        liftEffect $ Client.disconnect sockA
        liftEffect $ Client.disconnect sockB
        liftEffect $ Client.disconnect sockC
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)

      it "multiple rooms are isolated from each other" do
        -- Test 7: Multiple rooms isolation
        -- Connect A, B, C. Join A and C to "r1". Join B and C to "r2".
        -- broadcastToRoom using C's handle to "r1" -> A gets it
        -- Then reset and broadcastToRoom using C's handle to "r2" -> B gets it
        -- Check A didn't get r2's message and B didn't get r1's message.
        server <- liftEffect $ Server.createServerWithPort (testPort + 8)

        -- Server-side handle storage
        handleARef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        handleBRef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        handleCRef <- liftEffect $ Ref.new (Nothing :: Maybe (NamespaceHandle AppProtocol "lobby"))
        connectionCount <- liftEffect $ Ref.new 0

        -- Client-side received data: track which count value each client got
        -- Sentinel = 0 means "nothing received"
        receivedA <- liftEffect $ Ref.new 0
        receivedB <- liftEffect $ Ref.new 0

        -- Server: store handles, set up rooms
        -- A and C in "r1", B and C in "r2"
        -- Ref.modify returns the NEW value: 1, 2, 3, ...
        liftEffect $ Server.onConnection @AppProtocol @"lobby" server \handle -> do
          n <- Ref.modify (_ + 1) connectionCount
          case n of
            1 -> do
              Ref.write (Just handle) handleARef
              Server.joinRoom handle "r1"
            2 -> do
              Ref.write (Just handle) handleBRef
              Server.joinRoom handle "r2"
            _ -> do
              Ref.write (Just handle) handleCRef
              Server.joinRoom handle "r1"
              Server.joinRoom handle "r2"

        let url8 = "http://localhost:" <> show (testPort + 8)

        -- Connect client A (in r1 only)
        sockA <- liftEffect $ Client.connect url8
        liftAff $ waitForConnect sockA
        lobbyA <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockA
        liftEffect $ Client.onMsg @"userCount" lobbyA \p ->
          Ref.write p.count receivedA
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client B (in r2 only)
        sockB <- liftEffect $ Client.connect url8
        liftAff $ waitForConnect sockB
        lobbyB <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockB
        liftEffect $ Client.onMsg @"userCount" lobbyB \p ->
          Ref.write p.count receivedB
        liftAff $ delay (Milliseconds 200.0)

        -- Connect client C (in both r1 and r2, will be sender)
        sockC <- liftEffect $ Client.connect url8
        liftAff $ waitForConnect sockC
        _lobbyC <- liftEffect $ Client.joinNs @AppProtocol @"lobby" sockC
        liftAff $ delay (Milliseconds 200.0)

        -- Server broadcastToRoom "r1" using C's handle
        mHandleC <- liftEffect $ Ref.read handleCRef
        case mHandleC of
          Nothing -> "handle C was stored" `shouldEqual` "handle C missing"
          Just hC -> do
            -- Broadcast to r1: A should receive (in r1, not sender), B should NOT (not in r1)
            liftEffect $
              Server.broadcastToRoom @"userCount" hC "r1" { count: 11 }

            liftAff $ delay (Milliseconds 300.0)

            -- Assert: A received from r1
            rA1 <- liftEffect $ Ref.read receivedA
            rA1 `shouldEqual` 11
            -- Assert: B did NOT receive from r1
            rB1 <- liftEffect $ Ref.read receivedB
            rB1 `shouldEqual` 0

            -- Reset A's ref for the next broadcast
            liftEffect $ Ref.write 0 receivedA

            -- Broadcast to r2: B should receive (in r2, not sender), A should NOT (not in r2)
            liftEffect $
              Server.broadcastToRoom @"userCount" hC "r2" { count: 22 }

            liftAff $ delay (Milliseconds 300.0)

            -- Assert: B received from r2
            rB2 <- liftEffect $ Ref.read receivedB
            rB2 `shouldEqual` 22
            -- Assert: A did NOT receive from r2
            rA2 <- liftEffect $ Ref.read receivedA
            rA2 `shouldEqual` 0

        -- Cleanup
        liftEffect $ Client.disconnect sockA
        liftEffect $ Client.disconnect sockB
        liftEffect $ Client.disconnect sockC
        liftEffect $ Server.closeServer server
        liftAff $ delay (Milliseconds 100.0)
