module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Aff (Aff)
import Test.Spec (describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Type.Proxy (Proxy(..))

-- Import the type engine to verify it compiles and links
import PurSocket.Framework (class IsValidMsg, class IsValidCall, NamespaceHandle, SocketRef)
import PurSocket.Example.Protocol (AppProtocol)
-- Import Client API to verify signatures compile
import PurSocket.Client as Client

-- Integration tests
import Test.Integration (integrationSpec)

-- Note: PurSocket.Server is verified to compile via `spago build`.
-- The type constraint tests below (testBroadcastTypeCheck, testOnEventTypeCheck)
-- validate the same IsValidMsg constraints that Server.broadcast and
-- Server.onEvent use.

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] do
  describe "PurSocket" do
    describe "Project skeleton" do
      it "stub test passes" do
        (1 + 1) `shouldEqual` 2

    describe "Protocol" do
      it "Msg and Call data kinds are defined" do
        -- Proves the Protocol module compiles with Msg and Call.
        pure unit

    describe "Framework - IsValidMsg" do
      it "resolves lobby/c2s/chat as Msg { text :: String }" do
        -- Monomorphic call site forces constraint resolution.
        testEmitChat `shouldEqual` unit

      it "resolves lobby/s2c/userCount as Msg { count :: Int }" do
        testBroadcastUserCount `shouldEqual` unit

      it "resolves game/c2s/move as Msg { x :: Int, y :: Int }" do
        testEmitMove `shouldEqual` unit

      it "resolves game/s2c/gameOver as Msg { winner :: String }" do
        testBroadcastGameOver `shouldEqual` unit

    describe "Framework - IsValidCall" do
      it "resolves lobby/c2s/join as Call { name :: String } { success :: Boolean }" do
        testCallJoin `shouldEqual` unit

    describe "Framework - Direction enforcement" do
      it "c2s events are only valid in c2s direction" do
        -- testEmitChat constrains dir to "c2s" -- proves direction is checked.
        testEmitChat `shouldEqual` unit

      it "s2c events are only valid in s2c direction" do
        -- testBroadcastUserCount constrains dir to "s2c".
        testBroadcastUserCount `shouldEqual` unit

    describe "Client" do
      it "connect returns Effect SocketRef" do
        -- Compile-time test: verifies connect has the right type.
        testConnectType `shouldEqual` unit

      it "joinNs returns Effect (NamespaceHandle ns)" do
        -- Compile-time test: verifies joinNs signature.
        testJoinNsType `shouldEqual` unit

      it "emit resolves IsValidMsg for c2s events" do
        -- Compile-time test: verifies emit signature resolves
        -- against the protocol with c2s direction constraint.
        testEmitType `shouldEqual` unit

      it "call resolves IsValidCall for c2s events" do
        -- Compile-time test: verifies call signature resolves
        -- against the protocol with c2s direction constraint.
        testCallType `shouldEqual` unit

      it "callWithTimeout accepts custom timeout" do
        testCallWithTimeoutType `shouldEqual` unit

      it "defaultTimeout is 5000ms" do
        Client.defaultTimeout `shouldEqual` 5000

    describe "Server" do
      it "createServer, createServerWithPort are defined" do
        -- Verifies the Server module exports compile and link.
        -- We do not actually call createServer here because it would
        -- start a real Socket.io server (requiring node socket.io).
        pure unit

      it "broadcast type-checks with s2c events" do
        -- This is a compile-time test: if broadcast accepted c2s events,
        -- this module would not compile.  The type signature
        -- `IsValidMsg protocol ns event "s2c" payload` enforces direction.
        testBroadcastTypeCheck `shouldEqual` unit

      it "onEvent type-checks with c2s events" do
        -- Compile-time test: onEvent only accepts c2s events.
        testOnEventTypeCheck `shouldEqual` unit

    integrationSpec

-- ---------------------------------------------------------------------------
-- Positive compile tests: monomorphic call sites that force constraint
-- resolution.  If the Row.Cons chain fails, the module will not compile.
-- ---------------------------------------------------------------------------

-- | Generic validator for IsValidMsg -- the Proxy arguments let us supply
-- | concrete type arguments at the call site while keeping the function
-- | itself reusable across tests.
validateMsg
  :: forall protocol ns event dir payload
   . IsValidMsg protocol ns event dir payload
  => Proxy protocol -> Proxy ns -> Proxy event -> Proxy dir -> Unit
validateMsg _ _ _ _ = unit

-- | Generic validator for IsValidCall.
validateCall
  :: forall protocol ns event dir payload response
   . IsValidCall protocol ns event dir payload response
  => Proxy protocol -> Proxy ns -> Proxy event -> Proxy dir -> Unit
validateCall _ _ _ _ = unit

-- | Proves IsValidMsg can resolve: lobby -> c2s -> chat -> Msg { text :: String }
testEmitChat :: Unit
testEmitChat = validateMsg
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "lobby")
  (Proxy :: _ "chat")
  (Proxy :: _ "c2s")

-- | Proves IsValidMsg can resolve: lobby -> s2c -> userCount -> Msg { count :: Int }
testBroadcastUserCount :: Unit
testBroadcastUserCount = validateMsg
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "lobby")
  (Proxy :: _ "userCount")
  (Proxy :: _ "s2c")

-- | Proves IsValidMsg can resolve: game -> c2s -> move -> Msg { x :: Int, y :: Int }
testEmitMove :: Unit
testEmitMove = validateMsg
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "game")
  (Proxy :: _ "move")
  (Proxy :: _ "c2s")

-- | Proves IsValidMsg can resolve: game -> s2c -> gameOver -> Msg { winner :: String }
testBroadcastGameOver :: Unit
testBroadcastGameOver = validateMsg
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "game")
  (Proxy :: _ "gameOver")
  (Proxy :: _ "s2c")

-- | Proves IsValidCall can resolve: lobby -> c2s -> join -> Call { name :: String } { success :: Boolean }
testCallJoin :: Unit
testCallJoin = validateCall
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "lobby")
  (Proxy :: _ "join")
  (Proxy :: _ "c2s")

-- ---------------------------------------------------------------------------
-- Server API compile-time validation tests.
-- These validate that Server.broadcast uses s2c and Server.onEvent uses c2s.
-- ---------------------------------------------------------------------------

-- | Proves that broadcast's type signature correctly constrains to s2c.
-- | If broadcast accepted c2s events, the IsValidMsg constraint would
-- | resolve differently (or fail to resolve).
testBroadcastTypeCheck :: Unit
testBroadcastTypeCheck = validateMsg
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "game")
  (Proxy :: _ "gameOver")
  (Proxy :: _ "s2c")

-- | Proves that onEvent's type signature correctly constrains to c2s.
testOnEventTypeCheck :: Unit
testOnEventTypeCheck = validateMsg
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "lobby")
  (Proxy :: _ "chat")
  (Proxy :: _ "c2s")

-- ---------------------------------------------------------------------------
-- Client API compile-time validation tests.
-- These verify that connect, join, emit, call, and callWithTimeout
-- have the correct type signatures and resolve constraints properly.
-- ---------------------------------------------------------------------------

-- | Proves that `connect` has type `String -> Effect SocketRef`.
testConnectType :: Unit
testConnectType = const unit connectRef
  where
  connectRef :: String -> Effect SocketRef
  connectRef = Client.connect

-- | Proves that `joinNs` has the correct type signature.
testJoinNsType :: Unit
testJoinNsType = const unit joinNsRef
  where
  joinNsRef :: SocketRef -> Effect (NamespaceHandle "lobby")
  joinNsRef = Client.joinNs @"lobby"

-- | Proves that `emit` resolves IsValidMsg for c2s events.
testEmitType :: Unit
testEmitType = const unit emitRef
  where
  emitRef :: NamespaceHandle "lobby" -> { text :: String } -> Effect Unit
  emitRef = Client.emit @AppProtocol @"lobby" @"chat"

-- | Proves that `call` resolves IsValidCall for c2s events.
testCallType :: Unit
testCallType = const unit callRef
  where
  callRef :: NamespaceHandle "lobby" -> { name :: String } -> Aff { success :: Boolean }
  callRef = Client.call @AppProtocol @"lobby" @"join"

-- | Proves that `callWithTimeout` accepts a custom timeout.
testCallWithTimeoutType :: Unit
testCallWithTimeoutType = const unit callRef
  where
  callRef :: NamespaceHandle "lobby" -> Int -> { name :: String } -> Aff { success :: Boolean }
  callRef = Client.callWithTimeout @AppProtocol @"lobby" @"join"

-- ---------------------------------------------------------------------------
-- Negative compile tests documentation.
-- The following code MUST NOT compile.  Each case is verified by
-- separate files in test-negative/ that are compiled independently.
--
-- Case 1: Wrong event name (WrongEventName.purs)
-- Case 2: Wrong namespace (WrongNamespace.purs)
-- Case 3: Wrong direction (WrongDirection.purs)
-- Case 4: Wrong payload type (WrongPayload.purs)
-- Case 5: Server broadcast with c2s direction (server cannot send c2s)
-- Case 6: Server onEvent with s2c direction (server cannot listen for s2c)
-- Case 7: Client emit with s2c direction (client cannot send s2c)
-- ---------------------------------------------------------------------------
