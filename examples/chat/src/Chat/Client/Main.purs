-- | Chat.Client.Main
-- |
-- | Protocol wrapper functions for the browser chat client.
-- | Exports thin wrappers around PurSocket's type-safe API.
-- | All DOM manipulation lives in index.html's inline JavaScript.
module Chat.Client.Main
  ( connectChat
  , sendMessage
  , setNicknameCb
  , onNewMessage
  , onUserJoined
  , onUserLeft
  , onActiveUsers
  ) where

import Prelude

import Effect (Effect)
import Effect.Aff (launchAff_)
import Effect.Class (liftEffect)
import Chat.Protocol (ChatProtocol)
import PurSocket.Client (connect, joinNs, emit, call, onMsg)
import PurSocket.Framework (NamespaceHandle)

-- | Connect to the server and join the "chat" namespace.
-- | Takes a callback that receives the NamespaceHandle on success.
connectChat :: (NamespaceHandle ChatProtocol "chat" -> Effect Unit) -> Effect Unit
connectChat cb = do
  socket <- connect "http://localhost:3000"
  handle <- joinNs @ChatProtocol @"chat" socket
  cb handle

-- | Send a chat message. Wraps `emit @"sendMessage"`.
sendMessage :: NamespaceHandle ChatProtocol "chat" -> String -> Effect Unit
sendMessage handle text =
  emit @"sendMessage" handle { text }

-- | Set nickname via Call (request/response). Takes a callback for the result
-- | since `call` returns Aff.
setNicknameCb
  :: NamespaceHandle ChatProtocol "chat"
  -> String
  -> ({ ok :: Boolean, reason :: String } -> Effect Unit)
  -> Effect Unit
setNicknameCb handle nickname cb = launchAff_ do
  res <- call @"setNickname" handle { nickname }
  liftEffect $ cb res

-- | Listen for new messages from the server.
onNewMessage
  :: NamespaceHandle ChatProtocol "chat"
  -> ({ sender :: String, text :: String } -> Effect Unit)
  -> Effect Unit
onNewMessage handle cb =
  onMsg @"newMessage" handle cb

-- | Listen for user joined events.
onUserJoined
  :: NamespaceHandle ChatProtocol "chat"
  -> ({ nickname :: String } -> Effect Unit)
  -> Effect Unit
onUserJoined handle cb =
  onMsg @"userJoined" handle cb

-- | Listen for user left events.
onUserLeft
  :: NamespaceHandle ChatProtocol "chat"
  -> ({ nickname :: String } -> Effect Unit)
  -> Effect Unit
onUserLeft handle cb =
  onMsg @"userLeft" handle cb

-- | Listen for active users list updates.
onActiveUsers
  :: NamespaceHandle ChatProtocol "chat"
  -> ({ users :: Array String } -> Effect Unit)
  -> Effect Unit
onActiveUsers handle cb =
  onMsg @"activeUsers" handle cb
