-- | PurSocket.Example.Protocol
-- |
-- | This module exists for demonstration purposes.  Real applications
-- | should define their own protocol in their own codebase.
-- |
-- | The example protocol defines two namespaces ("lobby" and "game")
-- | with client-to-server and server-to-client events, illustrating
-- | the `Msg` (fire-and-forget) and `Call` (request/response) patterns.
-- |
-- | The protocol is a nested row type.  The outermost row maps
-- | namespace names to their definitions.  Each namespace definition
-- | is a row with `c2s` and `s2c` entries, each of which is itself
-- | a row mapping event names to their types (`Msg` or `Call`).
-- |
-- | Row types (not records) are used at every level so that `Row.Cons`
-- | constraints can decompose the protocol at compile time without any
-- | runtime representation.
module PurSocket.Example.Protocol
  ( AppProtocol
  ) where

import PurSocket.Protocol (Msg, Call)

-- | Example application protocol.
-- |
-- | Structure:
-- |   namespace -> ( c2s -> (events...), s2c -> (events...) )
-- |
-- | Each event is tagged with `Msg payload` (fire-and-forget) or
-- | `Call payload response` (request/response).
type AppProtocol =
  ( lobby ::
      ( c2s ::
          ( chat :: Msg { text :: String }
          , join :: Call { name :: String } { success :: Boolean }
          )
      , s2c :: ( userCount :: Msg { count :: Int } )
      )
  , game ::
      ( c2s :: ( move :: Msg { x :: Int, y :: Int } )
      , s2c :: ( gameOver :: Msg { winner :: String } )
      )
  )
