-- | Chat server protocol handlers. Uses PurSocket API against ChatProtocol.
-- | Receives a pre-configured Socket.io server from start-server.mjs
-- | and sets up all protocol handlers.
module Chat.Server.Main (startChat, startChatBun) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Console (log)
import Effect.Ref as Ref
import Chat.Protocol (ChatProtocol)
import PurSocket.Server
  ( onConnection
  , onEvent
  , onCallEvent
  , onDisconnect
  , socketId
  , broadcast
  , broadcastExceptSender
  , BunEngine
  , createServerWithBunEngine
  )
import PurSocket.Internal (ServerSocket)

type User = { id :: String, nickname :: String }

startChat :: ServerSocket -> Effect Unit
startChat server = do
  usersRef <- Ref.new ([] :: Array User)

  onConnection @ChatProtocol @"chat" server \handle -> do
    let sid = socketId handle
    let defaultNick = "anon-" <> sid
    Ref.modify_ (\us -> Array.snoc us { id: sid, nickname: defaultNick }) usersRef

    -- Broadcast join and active user list
    broadcast @ChatProtocol @"chat" @"userJoined" server { nickname: defaultNick }
    users <- Ref.read usersRef
    broadcast @ChatProtocol @"chat" @"activeUsers" server
      { users: map _.nickname users }

    -- Handle nickname changes (Call with acknowledgement)
    onCallEvent @"setNickname" handle \payload -> do
      currentUsers <- Ref.read usersRef
      let taken = Array.any (\u -> u.nickname == payload.nickname) currentUsers
      if taken
        then pure { ok: false, reason: "Nickname already taken" }
        else do
          Ref.modify_
            (map \u -> if u.id == sid then u { nickname = payload.nickname } else u)
            usersRef
          pure { ok: true, reason: "" }

    -- Handle incoming messages
    onEvent @"sendMessage" handle \payload -> do
      currentUsers <- Ref.read usersRef
      let sender = case Array.find (\u -> u.id == sid) currentUsers of
            Nothing -> defaultNick
            Just u  -> u.nickname
      broadcastExceptSender @"newMessage" handle
        { sender, text: payload.text }

    -- Handle disconnect
    onDisconnect handle do
      currentUsers <- Ref.read usersRef
      let leaving = Array.find (\u -> u.id == sid) currentUsers
      Ref.modify_ (Array.filter \u -> u.id /= sid) usersRef
      case leaving of
        Nothing -> pure unit
        Just u -> do
          broadcast @ChatProtocol @"chat" @"userLeft" server { nickname: u.nickname }
          remaining <- Ref.read usersRef
          broadcast @ChatProtocol @"chat" @"activeUsers" server
            { users: map _.nickname remaining }

  log "Chat protocol handlers registered"

-- | Bun entry point: creates a Socket.io server from a Bun engine
-- | and sets up all chat handlers.
startChatBun :: BunEngine -> Effect Unit
startChatBun engine = do
  server <- createServerWithBunEngine engine
  startChat server
