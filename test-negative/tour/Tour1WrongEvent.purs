-- | Negative compile test: wrong event name (guided tour experiment 1).
-- | This file MUST NOT compile.
-- | "sendMsg" does not exist in chat/c2s of ChatProtocol (typo for "sendMessage").
module Test.Negative.Tour.Tour1WrongEvent where

import Prelude (Unit, unit)
import Type.Proxy (Proxy(..))
import PurSocket.Framework (class IsValidMsg)
import Chat.Protocol (ChatProtocol)

-- Generic validator that forces constraint resolution when called
-- at a concrete (monomorphic) site.
validate
  :: forall protocol ns event dir payload
   . IsValidMsg protocol ns event dir payload
  => Proxy protocol -> Proxy ns -> Proxy event -> Proxy dir -> Unit
validate _ _ _ _ = unit

-- This MUST fail: "sendMsg" is a typo, the correct event is "sendMessage"
test :: Unit
test = validate
  (Proxy :: _ ChatProtocol)
  (Proxy :: _ "chat")
  (Proxy :: _ "sendMsg")
  (Proxy :: _ "c2s")
