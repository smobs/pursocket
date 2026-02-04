-- | Negative compile test: wrong payload type (guided tour experiment 3).
-- | This file MUST NOT compile.
-- | "sendMessage" expects { text :: String }, not { message :: String }.
module Test.Negative.Tour.Tour3WrongPayload where

import Prelude (Unit, unit)
import Type.Proxy (Proxy(..))
import PurSocket.Framework (class IsValidMsg)
import Chat.Protocol (ChatProtocol)

-- Validator that pins the payload type, forcing the compiler to unify
-- it with what the protocol actually declares for this event.
validateWithPayload
  :: forall protocol ns event dir payload
   . IsValidMsg protocol ns event dir payload
  => Proxy protocol -> Proxy ns -> Proxy event -> Proxy dir -> Proxy payload -> Unit
validateWithPayload _ _ _ _ _ = unit

-- This MUST fail: "sendMessage" payload is { text :: String }, not { message :: String }
test :: Unit
test = validateWithPayload
  (Proxy :: _ ChatProtocol)
  (Proxy :: _ "chat")
  (Proxy :: _ "sendMessage")
  (Proxy :: _ "c2s")
  (Proxy :: _ { message :: String })
