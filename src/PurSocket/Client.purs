-- | PurSocket.Client
-- |
-- | Client-side API for connecting to a Socket.io server, joining
-- | namespaces (obtaining `NamespaceHandle` capability tokens), and
-- | sending type-safe messages.
-- |
-- | All functions validate events against the application protocol at
-- | compile time via `IsValidMsg` and `IsValidCall` constraints.
-- |
-- | Usage:
-- | ```purescript
-- | socket <- connect "http://localhost:3000"
-- | lobby <- join @"lobby" socket
-- | emit @AppProtocol @"lobby" @"chat" lobby { text: "Hello!" }
-- | res <- call @AppProtocol @"lobby" @"join" lobby { name: "Alice" }
-- | ```
module PurSocket.Client
  ( connect
  , joinNs
  , emit
  , call
  , callWithTimeout
  , onMsg
  , onConnect
  , onDisconnect
  , onConnectNs
  , onDisconnectNs
  , disconnect
  , defaultTimeout
  , DisconnectReason(..)
  , willAutoReconnect
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Symbol (class IsSymbol, reflectSymbol)
import Effect (Effect)
import Effect.Aff (Aff, makeAff, nonCanceler)
import Effect.Exception (Error)
import PurSocket.Framework (NamespaceHandle, SocketRef, class IsValidMsg, class IsValidCall)
import PurSocket.Internal (mkNamespaceHandle, socketRefFromHandle)
import Type.Proxy (Proxy(..))

-- | Default timeout for `call` in milliseconds.
defaultTimeout :: Int
defaultTimeout = 5000

-- | Reason for a socket disconnection.
-- | Mirrors Socket.io v4 disconnect reasons.
data DisconnectReason
  = ServerDisconnect     -- ^ "io server disconnect" -- server forced disconnect (no auto-reconnect)
  | ClientDisconnect     -- ^ "io client disconnect" -- client called disconnect (no auto-reconnect)
  | TransportClose       -- ^ "transport close" -- connection lost (will auto-reconnect)
  | TransportError       -- ^ "transport error" -- connection error (will auto-reconnect)
  | PingTimeout          -- ^ "ping timeout" -- heartbeat failed (will auto-reconnect)
  | UnknownReason String -- ^ Future-proof catch-all (assumes auto-reconnect)

-- | Parse a Socket.io disconnect reason string into a DisconnectReason.
parseDisconnectReason :: String -> DisconnectReason
parseDisconnectReason = case _ of
  "io server disconnect" -> ServerDisconnect
  "io client disconnect" -> ClientDisconnect
  "transport close" -> TransportClose
  "transport error" -> TransportError
  "ping timeout" -> PingTimeout
  other -> UnknownReason other

-- | Whether Socket.io will automatically attempt to reconnect after this disconnect.
-- | Returns false for ServerDisconnect and ClientDisconnect (intentional disconnects).
willAutoReconnect :: DisconnectReason -> Boolean
willAutoReconnect ServerDisconnect = false
willAutoReconnect ClientDisconnect = false
willAutoReconnect _ = true

-- | Connect to a Socket.io server at the given URL.
-- |
-- | Returns an opaque `SocketRef` representing the base connection
-- | (default namespace).  Use `joinNs` to connect to specific namespaces
-- | and obtain `NamespaceHandle` capability tokens.
-- |
-- | Internally calls `io(url)` from `socket.io-client`.
connect :: String -> Effect SocketRef
connect = primConnect

-- | Join a namespace, obtaining a `NamespaceHandle` capability token.
-- |
-- | The type-level `protocol` parameter pins the protocol type into
-- | the handle, so all subsequent `emit`/`call`/`onMsg` calls infer
-- | it automatically.  The `ns` parameter identifies which namespace
-- | to connect to.
-- |
-- | Example:
-- | ```purescript
-- | lobby <- joinNs @AppProtocol @"lobby" socket
-- | emit @"chat" lobby { text: "Hello!" }   -- protocol inferred from handle
-- | ```
joinNs
  :: forall @protocol @ns
   . IsSymbol ns
  => SocketRef
  -> Effect (NamespaceHandle protocol ns)
joinNs baseSocket = do
  nsSocket <- primJoin baseSocket nsStr
  pure (mkNamespaceHandle nsSocket)
  where
  nsStr = reflectSymbol (Proxy :: Proxy ns)

-- | Emit a fire-and-forget message on the given namespace.
-- |
-- | The event must exist as a `Msg` in the protocol's `c2s` direction
-- | for the namespace identified by the handle.  The protocol and
-- | namespace are inferred from the handle — only `@event` needs to
-- | be specified at the call site.
-- |
-- | Internally calls `socket.emit(eventName, payload)`.
-- |
-- | Example:
-- | ```purescript
-- | emit @"chat" lobby { text: "Hello!" }
-- | ```
emit
  :: forall @event protocol ns payload
   . IsValidMsg protocol ns event "c2s" payload
  => IsSymbol event
  => NamespaceHandle protocol ns
  -> payload
  -> Effect Unit
emit handle payload =
  primEmit (socketRefFromHandle handle) eventStr payload
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Execute a request/response call on the given namespace using
-- | Socket.io acknowledgements.
-- |
-- | The event must exist as a `Call` in the protocol's `c2s` direction.
-- | Uses the default timeout of 5000ms.  For a custom timeout, use
-- | `callWithTimeout`.
-- |
-- | The response type is inferred from the protocol definition.
-- |
-- | Example:
-- | ```purescript
-- | res <- call @"join" lobby { name: "Alice" }
-- | ```
call
  :: forall @event protocol ns payload res
   . IsValidCall protocol ns event "c2s" payload res
  => IsSymbol event
  => NamespaceHandle protocol ns
  -> payload
  -> Aff res
call handle payload = makeAff \callback -> do
  primCallImpl (socketRefFromHandle handle) eventStr payload defaultTimeout
    (\r -> callback (Right r))
    (\e -> callback (Left e))
  pure nonCanceler
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Like `call`, but with a configurable timeout in milliseconds.
-- |
-- | If the server does not acknowledge within the timeout, the `Aff`
-- | will reject with an `Error`.
-- |
-- | Example:
-- | ```purescript
-- | res <- callWithTimeout @"join" lobby 10000 { name: "Alice" }
-- | ```
callWithTimeout
  :: forall @event protocol ns payload res
   . IsValidCall protocol ns event "c2s" payload res
  => IsSymbol event
  => NamespaceHandle protocol ns
  -> Int
  -> payload
  -> Aff res
callWithTimeout handle timeout payload = makeAff \callback -> do
  primCallImpl (socketRefFromHandle handle) eventStr payload timeout
    (\r -> callback (Right r))
    (\e -> callback (Left e))
  pure nonCanceler
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Listen for a server-to-client message on the given namespace.
-- |
-- | The event must exist as a `Msg` in the protocol's `s2c` direction
-- | for the namespace identified by the handle.  The protocol and
-- | namespace are inferred from the handle.
-- |
-- | Internally calls `socket.on(event, (data) => callback(data)())`.
-- |
-- | Example:
-- | ```purescript
-- | onMsg @"userCount" handle \payload ->
-- |   log (show payload.count)
-- | ```
onMsg
  :: forall @event protocol ns payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle protocol ns
  -> (payload -> Effect Unit)
  -> Effect Unit
onMsg handle callback =
  primOnMsg (socketRefFromHandle handle) eventStr callback
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Register a callback that fires when the socket connects.
-- |
-- | Useful in tests and application startup to wait for the connection
-- | to be established before sending messages.
-- |
-- | Internally calls `socket.on("connect", callback)`.
onConnect :: SocketRef -> Effect Unit -> Effect Unit
onConnect = primOnConnect

-- | Register a callback that fires when the socket disconnects.
-- |
-- | The callback receives a `DisconnectReason` indicating why the
-- | disconnection occurred and whether Socket.io will auto-reconnect.
-- |
-- | Internally calls `socket.on("disconnect", (reason) => callback(reason))`.
onDisconnect :: SocketRef -> (DisconnectReason -> Effect Unit) -> Effect Unit
onDisconnect socket callback =
  primOnDisconnect socket (\reasonStr -> callback (parseDisconnectReason reasonStr))

-- | Register a callback that fires when a namespace socket connects.
-- |
-- | Like `onConnect`, but operates on a `NamespaceHandle` instead of
-- | a raw `SocketRef`.
onConnectNs :: forall protocol ns. NamespaceHandle protocol ns -> Effect Unit -> Effect Unit
onConnectNs handle callback = primOnConnect (socketRefFromHandle handle) callback

-- | Register a callback that fires when a namespace socket disconnects.
-- |
-- | Like `onDisconnect`, but operates on a `NamespaceHandle` instead of
-- | a raw `SocketRef`.
onDisconnectNs :: forall protocol ns. NamespaceHandle protocol ns -> (DisconnectReason -> Effect Unit) -> Effect Unit
onDisconnectNs handle callback =
  primOnDisconnect (socketRefFromHandle handle) (\reasonStr -> callback (parseDisconnectReason reasonStr))

-- | Disconnect a socket from the server.
-- |
-- | Internally calls `socket.disconnect()`.
disconnect :: SocketRef -> Effect Unit
disconnect = primDisconnect

-- ---------------------------------------------------------------------------
-- FFI imports -- thin wrappers around the socket.io-client API
-- ---------------------------------------------------------------------------

-- | Connect to a Socket.io server.  Wraps `io(url)`.
foreign import primConnect :: String -> Effect SocketRef

-- | Connect to a namespace via the shared Manager.
-- | Calls `baseSocket.io.socket("/" + ns)`.
foreign import primJoin :: SocketRef -> String -> Effect SocketRef

-- | Emit a fire-and-forget event.  Wraps `socket.emit(event, payload)`.
foreign import primEmit :: forall a. SocketRef -> String -> a -> Effect Unit

-- | Emit an event with acknowledgement callback and timeout.
-- | Wraps `socket.timeout(ms).emit(event, payload, callback)`.
foreign import primCallImpl
  :: forall a r
   . SocketRef -> String -> a -> Int -> (r -> Effect Unit) -> (Error -> Effect Unit) -> Effect Unit

-- | Listen for an event.  Wraps `socket.on(event, callback)`.
foreign import primOnMsg :: forall a. SocketRef -> String -> (a -> Effect Unit) -> Effect Unit

-- | Listen for the "connect" event.  Wraps `socket.on("connect", callback)`.
foreign import primOnConnect :: SocketRef -> Effect Unit -> Effect Unit

-- | Listen for the "disconnect" event.  Wraps `socket.on("disconnect", callback)`.
foreign import primOnDisconnect :: SocketRef -> (String -> Effect Unit) -> Effect Unit

-- | Disconnect a socket.  Wraps `socket.disconnect()`.
foreign import primDisconnect :: SocketRef -> Effect Unit
