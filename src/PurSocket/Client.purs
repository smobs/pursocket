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
  , join
  , emit
  , call
  , callWithTimeout
  , onMsg
  , onConnect
  , disconnect
  , defaultTimeout
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

-- | Connect to a Socket.io server at the given URL.
-- |
-- | Returns an opaque `SocketRef` representing the base connection
-- | (default namespace).  Use `join` to connect to specific namespaces
-- | and obtain `NamespaceHandle` capability tokens.
-- |
-- | Internally calls `io(url)` from `socket.io-client`.
connect :: String -> Effect SocketRef
connect = primConnect

-- | Join a namespace, obtaining a `NamespaceHandle` capability token.
-- |
-- | The type-level `ns` parameter (a `Symbol`) identifies which
-- | namespace to connect to.  At runtime, `reflectSymbol` converts
-- | this to a string and the FFI creates a new Socket.io connection
-- | to `baseUrl + "/" + ns`.
-- |
-- | The base URL is extracted from the socket returned by `connect`
-- | via `socket.io.uri` on the JS side.
-- |
-- | Example:
-- | ```purescript
-- | lobby <- join @"lobby" socket
-- | ```
join
  :: forall @ns
   . IsSymbol ns
  => SocketRef
  -> Effect (NamespaceHandle ns)
join baseSocket = do
  nsSocket <- primJoin baseSocket nsStr
  pure (mkNamespaceHandle nsSocket)
  where
  nsStr = reflectSymbol (Proxy :: Proxy ns)

-- | Emit a fire-and-forget message on the given namespace.
-- |
-- | The event must exist as a `Msg` in the protocol's `c2s` direction
-- | for the namespace identified by the handle.  This is enforced at
-- | compile time by the `IsValidMsg` constraint -- attempting to emit
-- | an event that does not exist, or emitting in the wrong direction,
-- | produces a compile error with a descriptive message.
-- |
-- | Internally calls `socket.emit(eventName, payload)`.
-- |
-- | Example:
-- | ```purescript
-- | emit @AppProtocol @"lobby" @"chat" lobby { text: "Hello!" }
-- | ```
emit
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "c2s" payload
  => IsSymbol event
  => NamespaceHandle ns
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
-- | res <- call @AppProtocol @"lobby" @"join" lobby { name: "Alice" }
-- | -- res :: { success :: Boolean }
-- | ```
call
  :: forall @protocol @ns @event payload res
   . IsValidCall protocol ns event "c2s" payload res
  => IsSymbol event
  => NamespaceHandle ns
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
-- | res <- callWithTimeout @AppProtocol @"lobby" @"join" lobby 10000 { name: "Alice" }
-- | ```
callWithTimeout
  :: forall @protocol @ns @event payload res
   . IsValidCall protocol ns event "c2s" payload res
  => IsSymbol event
  => NamespaceHandle ns
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
-- | for the namespace identified by the handle.  This is the client-side
-- | counterpart to `Server.broadcast`.
-- |
-- | Internally calls `socket.on(event, (data) => callback(data)())`.
-- |
-- | Example:
-- | ```purescript
-- | onMsg @AppProtocol @"lobby" @"userCount" handle \payload ->
-- |   log (show payload.count)
-- | ```
onMsg
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
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

-- | Connect to a namespace.  Extracts the base URL from the socket
-- | and calls `io(baseUrl + "/" + ns)`.
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

-- | Disconnect a socket.  Wraps `socket.disconnect()`.
foreign import primDisconnect :: SocketRef -> Effect Unit
