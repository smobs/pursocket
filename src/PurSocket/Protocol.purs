-- | PurSocket.Protocol
-- |
-- | Defines the data kinds `Msg` and `Call` used to tag events in an
-- | application protocol.  Users import these constructors when writing
-- | their own `AppProtocol` row type.
module PurSocket.Protocol
  ( Msg
  , Call
  ) where

-- | Fire-and-forget message tagged with its payload type.
data Msg (payload :: Type)

-- | Request/response (acknowledgement) tagged with request and response types.
data Call (payload :: Type) (response :: Type)
