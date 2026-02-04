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
  , emitTo
  , broadcastExceptSender
  , joinRoom
  , leaveRoom
  , broadcastToRoom
  , onEvent
  , onCallEvent
  , onConnection
  , onDisconnect
  , socketId
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

-- | Send a typed message to the single client identified by the
-- | `NamespaceHandle`.  The event must exist as a `Msg` in the
-- | protocol's `s2c` direction for the specified namespace.
-- |
-- | Calling `emitTo` on a handle for a disconnected client is a
-- | silent no-op (consistent with Socket.io's behavior).  Use
-- | `onDisconnect` to remove stale handles from application state.
-- |
-- | To send private messages, store handles from `onConnection` in a
-- | `Ref (Map UserId (NamespaceHandle ns))` and look up the recipient's
-- | handle when needed.  Remove handles in `onDisconnect`.
-- |
-- | Internally performs: `socket.emit(event, payload)` on the handle's
-- | underlying socket reference.
-- |
-- | Example:
-- | ```purescript
-- | emitTo @AppProtocol @"chat" @"privateMsg" recipientHandle { text: "hello" }
-- | ```
emitTo
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> payload
  -> Effect Unit
emitTo handle payload =
  primEmitTo (socketRefFromHandle handle) eventStr payload
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Broadcast a typed message to all clients in the namespace EXCEPT
-- | the client identified by the `NamespaceHandle`.  The event must
-- | exist as a `Msg` in the protocol's `s2c` direction.
-- |
-- | This is the standard echo-prevention pattern: when a client sends
-- | a message, the server re-broadcasts it to everyone else using the
-- | sender's handle to exclude them.
-- |
-- | Internally performs: `socket.broadcast.emit(event, payload)` on
-- | the handle's underlying socket reference.
-- |
-- | Example:
-- | ```purescript
-- | onEvent @AppProtocol @"chat" @"sendMessage" handle \msg ->
-- |   broadcastExceptSender @AppProtocol @"chat" @"newMessage" handle msg
-- | ```
broadcastExceptSender
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> payload
  -> Effect Unit
broadcastExceptSender handle payload =
  primBroadcastExceptSender (socketRefFromHandle handle) eventStr payload
  where
  eventStr = reflectSymbol (Proxy :: Proxy event)

-- | Add the client identified by the handle to a Socket.io room.
-- | Room names are runtime strings (not type-level validated).
-- |
-- | Uses the default in-memory adapter's synchronous join semantics.
-- | If you use an async adapter (e.g., Redis), the join may not have
-- | propagated to other servers by the time this call returns.  A
-- | future PurSocket version may provide an `Aff` variant for async
-- | adapter support.
-- |
-- | Internally performs: `socket.join(room)` (promise discarded).
joinRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit
joinRoom handle room =
  primJoinRoom (socketRefFromHandle handle) room

-- | Remove the client identified by the handle from a Socket.io room.
-- |
-- | Uses the default in-memory adapter's synchronous leave semantics.
-- | If you use an async adapter (e.g., Redis), the leave may not have
-- | propagated to other servers by the time this call returns.  A
-- | future PurSocket version may provide an `Aff` variant for async
-- | adapter support.
-- |
-- | Internally performs: `socket.leave(room)` (promise discarded).
leaveRoom :: forall ns. NamespaceHandle ns -> String -> Effect Unit
leaveRoom handle room =
  primLeaveRoom (socketRefFromHandle handle) room

-- | Broadcast a typed message to all members of a room EXCEPT the
-- | client identified by the `NamespaceHandle` (socket-level
-- | semantics).  The event must exist as a `Msg` in the protocol's
-- | `s2c` direction.
-- |
-- | This uses `socket.to(room).emit()`, which automatically excludes
-- | the sender socket from delivery.  If you need to include the
-- | sender, call `broadcastToRoom` and then `emitTo` on the sender's
-- | own handle.
-- |
-- | Internally performs: `socket.to(room).emit(event, payload)`
-- |
-- | Example:
-- | ```purescript
-- | joinRoom handle "game-42"
-- | broadcastToRoom @AppProtocol @"game" @"playerJoined" handle "game-42" { name: "Alice" }
-- | ```
broadcastToRoom
  :: forall @protocol @ns @event payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle ns
  -> String
  -> payload
  -> Effect Unit
broadcastToRoom handle room payload =
  primBroadcastToRoom (socketRefFromHandle handle) room eventStr payload
  where
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

-- | Register a handler for when a client disconnects from a namespace.
-- |
-- | The "disconnect" event is a Socket.io system event (not a protocol
-- | event), so it bypasses protocol validation.  The callback receives
-- | no payload -- use `socketId` before the disconnect to track which
-- | client left.
-- |
-- | Internally performs: `socket.on("disconnect", () => callback())`
onDisconnect
  :: forall ns
   . NamespaceHandle ns
  -> Effect Unit
  -> Effect Unit
onDisconnect handle callback =
  primOnDisconnect (socketRefFromHandle handle) callback

-- | Get the unique Socket.io ID for a client connection.
-- |
-- | Useful for tracking connected clients in a `Ref` or `Map`.
-- | The ID is assigned by Socket.io and is unique per connection.
-- |
-- | Internally reads `socket.id`.
socketId
  :: forall ns
   . NamespaceHandle ns
  -> String
socketId handle = primSocketId (socketRefFromHandle handle)

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

foreign import primOnDisconnect :: SocketRef -> Effect Unit -> Effect Unit

foreign import primSocketId :: SocketRef -> String

foreign import primCloseServer :: ServerSocket -> Effect Unit

foreign import primEmitTo :: forall a. SocketRef -> String -> a -> Effect Unit

foreign import primBroadcastExceptSender :: forall a. SocketRef -> String -> a -> Effect Unit

foreign import primJoinRoom :: SocketRef -> String -> Effect Unit

foreign import primLeaveRoom :: SocketRef -> String -> Effect Unit

foreign import primBroadcastToRoom :: forall a. SocketRef -> String -> String -> a -> Effect Unit
