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
connectChat :: (NamespaceHandle "chat" -> Effect Unit) -> Effect Unit
connectChat cb = do
  socket <- connect "http://localhost:3000"
  handle <- joinNs @"chat" socket
  cb handle

-- | Send a chat message. Wraps `emit @ChatProtocol @"chat" @"sendMessage"`.
sendMessage :: NamespaceHandle "chat" -> String -> Effect Unit
sendMessage handle text =
  emit @ChatProtocol @"chat" @"sendMessage" handle { text }

-- | Set nickname via Call (request/response). Takes a callback for the result
-- | since `call` returns Aff.
setNicknameCb
  :: NamespaceHandle "chat"
  -> String
  -> ({ ok :: Boolean, reason :: String } -> Effect Unit)
  -> Effect Unit
setNicknameCb handle nickname cb = launchAff_ do
  res <- call @ChatProtocol @"chat" @"setNickname" handle { nickname }
  liftEffect $ cb res

-- | Listen for new messages from the server.
onNewMessage
  :: NamespaceHandle "chat"
  -> ({ sender :: String, text :: String } -> Effect Unit)
  -> Effect Unit
onNewMessage handle cb =
  onMsg @ChatProtocol @"chat" @"newMessage" handle cb

-- | Listen for user joined events.
onUserJoined
  :: NamespaceHandle "chat"
  -> ({ nickname :: String } -> Effect Unit)
  -> Effect Unit
onUserJoined handle cb =
  onMsg @ChatProtocol @"chat" @"userJoined" handle cb

-- | Listen for user left events.
onUserLeft
  :: NamespaceHandle "chat"
  -> ({ nickname :: String } -> Effect Unit)
  -> Effect Unit
onUserLeft handle cb =
  onMsg @ChatProtocol @"chat" @"userLeft" handle cb

-- | Listen for active users list updates.
onActiveUsers
  :: NamespaceHandle "chat"
  -> ({ users :: Array String } -> Effect Unit)
  -> Effect Unit
onActiveUsers handle cb =
  onMsg @ChatProtocol @"chat" @"activeUsers" handle cb
