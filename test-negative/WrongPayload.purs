-- | Negative compile test: wrong payload type.
-- | This file MUST NOT compile.
-- | "chat" expects Msg { text :: String }, not { wrong :: Boolean }.
module Test.Negative.WrongPayload where

import Prelude (Unit, unit)
import Type.Proxy (Proxy(..))
import PurSocket.Framework (class IsValidMsg)
import PurSocket.Example.Protocol (AppProtocol)

-- Validator that pins the payload type, forcing the compiler to unify
-- it with what the protocol actually declares for this event.
validateWithPayload
  :: forall protocol ns event dir payload
   . IsValidMsg protocol ns event dir payload
  => Proxy protocol -> Proxy ns -> Proxy event -> Proxy dir -> Proxy payload -> Unit
validateWithPayload _ _ _ _ _ = unit

-- This MUST fail: "chat" payload is { text :: String }, not { wrong :: Boolean }
test :: Unit
test = validateWithPayload
  (Proxy :: _ AppProtocol)
  (Proxy :: _ "lobby")
  (Proxy :: _ "chat")
  (Proxy :: _ "c2s")
  (Proxy :: _ { wrong :: Boolean })
