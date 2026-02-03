-- | PurSocket.Server
-- |
-- | Server-side API for creating a Socket.io server, broadcasting
-- | type-safe messages to connected clients, and registering typed
-- | event handlers.
-- |
-- | All functions validate events against the application protocol at
-- | compile time via `IsValidMsg` constraints.
-- |
-- | - `broadcast` is constrained to `s2c` direction — the server can
-- |   only send server-to-client events.
-- | - `onEvent` is constrained to `c2s` direction — the server can
-- |   only listen for client-to-server events.
-- |
-- | Attempting to violate these constraints produces a compile error.
module PurSocket.Server
  ( broadcast
  , onEvent
  , onCallEvent
  , onConnection
  , createServer
  , createServerWithPort
  , closeServer
  , module ReExports
  ) where

import Prelude

import Data.Symbol (class IsSymbol, reflectSymbol)
import Effect (Effect)
import PurSocket.Framework (NamespaceHandle, SocketRef, class IsValidMsg, class IsValidCall)
import PurSocket.Internal (ServerSocket) as ReExports
import PurSocket.Internal (ServerSocket, mkNamespaceHandle, socketRefFromHandle)
import Type.Proxy (Proxy(..))

-- | Create a standalone Socket.io server with no HTTP server attached.
-- | The server will not listen on any port until `listen` is called
-- | or `createServerWithPort` is used instead.
createServer :: Effect ServerSocket
createServer = primCreateServer

-- | Create a Socket.io server listening on the given port.
createServerWithPort :: Int -> Effect ServerSocket
createServerWithPort = primCreateServerWithPort

-- | Broadcast a fire-and-forget message to all clients connected to
-- | namespace `ns`.  The event must exist as a `Msg` in the protocol's
-- | `s2c` direction for the specified namespace.
-- |
-- | Internally performs: `io.of("/" + ns).emit(event, payload)`
-- |
-- | Example:
-- | ```purescript
-- | broadcast @AppProtocol @"game" @"gameOver" server { winner: "Alice" }
-- | ```
broadcast
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol ns
  => IsSymbol event
  => ServerSocket
  -> payload
  -> Effect Unit
broadcast server payload =
  primBroadcast server nsStr eventStr payload
  where
  nsStr = reflectSymbol (Proxy :: Proxy ns)
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Register a connection handler for namespace `ns`.  When a client
-- | connects to this namespace, the callback receives a `NamespaceHandle`
-- | wrapping the client's individual socket.
-- |
-- | The handle can then be used with `onEvent` to register typed event
-- | handlers for that specific client.
-- |
-- | Internally performs:
-- | `io.of("/" + ns).on("connection", (socket) => callback(handle)())`
-- |
-- | Example:
-- | ```purescript
-- | onConnection @"lobby" server \handle -> do
-- |   onEvent @AppProtocol @"lobby" @"chat" handle \payload ->
-- |     log payload.text
-- | ```
onConnection
  :: forall @ns
   . IsSymbol ns
  => ServerSocket
  -> (NamespaceHandle ns -> Effect Unit)
  -> Effect Unit
onConnection server callback =
  primOnConnection server nsStr wrappedCallback
  where
  nsStr = reflectSymbol (Proxy :: Proxy ns)
  wrappedCallback :: SocketRef -> Effect Unit
  wrappedCallback socketRef = callback (mkNamespaceHandle socketRef)

-- | Register a typed event handler on a specific client socket
-- | (obtained from `onConnection`).  The event must exist as a `Msg`
-- | in the protocol's `c2s` direction for the namespace identified
-- | by the handle.
-- |
-- | Internally performs: `socket.on(event, (data) => callback(data)())`
-- |
-- | Example:
-- | ```purescript
-- | onEvent @AppProtocol @"lobby" @"chat" handle \payload ->
-- |   log payload.text
-- | ```
onEvent
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "c2s" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> (payload -> Effect Unit)
  -> Effect Unit
onEvent handle callback =
  primOnEvent (socketRefFromHandle handle) eventStr callback
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Register a typed handler for a `Call` event (request/response with
-- | acknowledgement) on a specific client socket.  The handler receives
-- | the request payload and must return a response synchronously.
-- |
-- | Internally performs:
-- | `socket.on(event, (data, ack) => ack(handler(data)))`
-- |
-- | Example:
-- | ```purescript
-- | onCallEvent @AppProtocol @"lobby" @"join" handle \payload ->
-- |   pure { success: true }
-- | ```
onCallEvent
  :: forall @protocol @ns @event payload res
   . IsValidCall protocol ns event "c2s" payload res
  => IsSymbol event
  => NamespaceHandle ns
  -> (payload -> Effect res)
  -> Effect Unit
onCallEvent handle handler =
  primOnCallEvent (socketRefFromHandle handle) eventStr handler
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Close a Socket.io server, terminating all connections.
-- |
-- | Internally calls `server.close()`.
closeServer :: ServerSocket -> Effect Unit
closeServer = primCloseServer

-- ---------------------------------------------------------------------------
-- FFI imports — thin wrappers around the socket.io server API
-- ---------------------------------------------------------------------------

foreign import primCreateServer :: Effect ServerSocket

foreign import primCreateServerWithPort :: Int -> Effect ServerSocket

foreign import primBroadcast :: forall a. ServerSocket -> String -> String -> a -> Effect Unit

foreign import primOnConnection :: ServerSocket -> String -> (SocketRef -> Effect Unit) -> Effect Unit

foreign import primOnEvent :: forall a. SocketRef -> String -> (a -> Effect Unit) -> Effect Unit

foreign import primOnCallEvent :: forall a r. SocketRef -> String -> (a -> Effect r) -> Effect Unit

foreign import primCloseServer :: ServerSocket -> Effect Unit
