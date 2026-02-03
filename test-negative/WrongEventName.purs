-- | Negative compile test: wrong event name.
-- | This file MUST NOT compile.
-- | "typo" does not exist in lobby/c2s of AppProtocol.
module Test.Negative.WrongEventName where

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

-- This MUST fail: "typo" doesn't exist in lobby/c2s
test :: Unit
test = validate
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "lobby")
  (Proxy :: _ "typo")
  (Proxy :: _ "c2s")
