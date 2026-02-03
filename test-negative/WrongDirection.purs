-- | Negative compile test: wrong direction.
-- | This file MUST NOT compile.
-- | "userCount" exists in lobby/s2c, not lobby/c2s.
module Test.Negative.WrongDirection where

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

-- This MUST fail: "userCount" is s2c, not c2s
test :: Unit
test = validate
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "lobby")
  (Proxy :: _ "userCount")
  (Proxy :: _ "c2s")
