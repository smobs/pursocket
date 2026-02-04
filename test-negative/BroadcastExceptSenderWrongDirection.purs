-- | Negative compile test: broadcastExceptSender wrong direction.
-- | This file MUST NOT compile.
-- | "move" exists in game/c2s, not game/s2c.
-- | broadcastExceptSender constrains events to s2c, so using a c2s
-- | event must fail.
module Test.Negative.BroadcastExceptSenderWrongDirection where

import Prelude (Unit, unit)
import Type.Proxy (Proxy(..))
import PurSocket.Framework (class IsValidMsg)
import PurSocket.Example.Protocol (AppProtocol)

-- Generic validator that forces constraint resolution when called
-- at a concrete (monomorphic) site.
validate
  :: forall protocol ns event dir payload
   . IsValidMsg protocol ns event dir payload
  => Proxy protocol -> Proxy ns -> Proxy event -> Proxy dir -> Unit
validate _ _ _ _ = unit

-- This MUST fail: "move" is c2s, not s2c.
-- broadcastExceptSender requires IsValidMsg protocol ns event "s2c" payload,
-- so a c2s event used in s2c direction must be rejected.
test :: Unit
test = validate
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "game")
  (Proxy :: _ "move")
  (Proxy :: _ "s2c")
