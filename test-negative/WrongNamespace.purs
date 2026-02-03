-- | Negative compile test: wrong namespace.
-- | This file MUST NOT compile.
-- | "nonexistent" is not a namespace in AppProtocol.
module Test.Negative.WrongNamespace where

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

-- This MUST fail: "nonexistent" is not a namespace in AppProtocol
test :: Unit
test = validate
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "nonexistent")
  (Proxy :: _ "chat")
  (Proxy :: _ "c2s")
