-- | Negative compile test: wrong direction (guided tour experiment 2).
-- | This file MUST NOT compile.
-- | "newMessage" exists in chat/s2c, not chat/c2s — a client cannot emit it.
module Test.Negative.Tour.Tour2WrongDirection where

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

-- This MUST fail: "newMessage" is s2c only, not c2s
test :: Unit
test = validate
  (Proxy :: _ ChatProtocol)
  (Proxy :: _ "chat")
  (Proxy :: _ "newMessage")
  (Proxy :: _ "c2s")
