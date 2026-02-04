-- | Chat.Protocol
-- |
-- | The chat application's protocol definition. This is the single source
-- | of truth for all events that can flow between client and server.
-- |
-- | Uses PurSocket's `Msg` (fire-and-forget) and `Call` (request/response)
-- | data kinds to tag each event with its payload type.
module Chat.Protocol
  ( ChatProtocol
  ) where

import PurSocket.Protocol (Msg, Call)

-- | The chat protocol defines a single "chat" namespace with:
-- |
-- | Client-to-server (`c2s`):
-- |   - `sendMessage` (Msg): fire-and-forget text message
-- |   - `setNickname` (Call): request/response nickname registration
-- |
-- | Server-to-client (`s2c`):
-- |   - `newMessage` (Msg): broadcast a new chat message to all clients
-- |   - `userJoined` (Msg): notification when a user joins
-- |   - `userLeft` (Msg): notification when a user leaves
-- |   - `activeUsers` (Msg): list of currently connected users
type ChatProtocol =
  ( chat ::
      ( c2s ::
          ( sendMessage :: Msg { text :: String }
          , setNickname :: Call { nickname :: String } { ok :: Boolean, reason :: String }
          )
      , s2c ::
          ( newMessage  :: Msg { sender :: String, text :: String }
          , userJoined  :: Msg { nickname :: String }
          , userLeft    :: Msg { nickname :: String }
          , activeUsers :: Msg { users :: Array String }
          )
      )
  )
