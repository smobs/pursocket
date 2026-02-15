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
-- |
-- | **FFI trust boundary.** The foreign `prim*` functions at the bottom
-- | of this module use `forall a` for payload parameters because the
-- | PureScript FFI cannot express protocol-validated types at the JS
-- | boundary.  Type safety for payloads is enforced entirely by the
-- | `IsValidMsg` and `IsValidCall` constraints in the public API
-- | wrappers above.  Do not call `prim*` functions directly — they
-- | bypass all protocol validation and will accept any value,
-- | including ones that violate the protocol contract.
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
  , createServerWithHttpServer
  , createServerWithBunEngine
  , createServerWith
  , defaultServerConfig
  , ServerConfig
  , ServerTarget(..)
  , HttpServer
  , BunEngine
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

-- | An opaque type representing a Node.js `http.Server` instance.
foreign import data HttpServer :: Type

-- | An opaque type representing a `@socket.io/bun-engine` `Server` instance.
foreign import data BunEngine :: Type

-- | Specifies how the Socket.io server binds to the network.
-- | Using a sum type prevents invalid combinations (e.g. setting both
-- | a port and an HTTP server simultaneously).
data ServerTarget
  = Standalone
  | OnPort Int
  | AttachedTo HttpServer
  | BoundTo BunEngine

-- | Create a standalone Socket.io server with no HTTP server attached.
-- | The server will not listen on any port until `listen` is called
-- | or `createServerWithPort` is used instead.
createServer :: Effect ServerSocket
createServer = primCreateServer

-- | Create a Socket.io server listening on the given port.
createServerWithPort :: Int -> Effect ServerSocket
createServerWithPort = primCreateServerWithPort

-- | Create a Socket.io server attached to an existing Node.js HTTP server.
-- | The HTTP server must already be listening (or will be started separately).
createServerWithHttpServer :: HttpServer -> Effect ServerSocket
createServerWithHttpServer hs =
  createServerWith (defaultServerConfig { target = AttachedTo hs })

-- | Create a Socket.io server powered by a `@socket.io/bun-engine` instance.
-- | The engine is created in JavaScript via `new Engine(...)` and passed in.
createServerWithBunEngine :: BunEngine -> Effect ServerSocket
createServerWithBunEngine eng =
  createServerWith (defaultServerConfig { target = BoundTo eng })

-- | Server configuration record for `createServerWith`.
-- | The `target` field uses a sum type to prevent invalid combinations
-- | (e.g. setting both a port and an HTTP server).
type ServerConfig =
  { target       :: ServerTarget
  , cors         :: { origin :: String }
  , path         :: String
  , pingTimeout  :: Int
  , pingInterval :: Int
  }

-- | Default server configuration.  Override fields using record update syntax:
-- | ```purescript
-- | createServerWith (defaultServerConfig { target = OnPort 3000 })
-- | ```
defaultServerConfig :: ServerConfig
defaultServerConfig =
  { target: Standalone
  , cors: { origin: "*" }
  , path: "/socket.io"
  , pingTimeout: 20000
  , pingInterval: 25000
  }

-- | Create a Socket.io server with full configuration.
-- |
-- | Dispatches to the appropriate FFI constructor based on `target`.
-- |
-- | Example:
-- | ```purescript
-- | server <- createServerWith (defaultServerConfig { target = OnPort 3000 })
-- | server <- createServerWith (defaultServerConfig { target = AttachedTo myHttp, cors = { origin: "http://localhost:5173" } })
-- | ```
createServerWith :: ServerConfig -> Effect ServerSocket
createServerWith config = case config.target of
  Standalone    -> primCreateServerWithOpts opts
  OnPort p      -> primCreateServerWithPortAndOpts p opts
  AttachedTo hs -> primCreateServerWithHttpServerAndOpts hs opts
  BoundTo eng   -> primCreateServerWithBunEngine eng opts
  where
  opts = { cors: config.cors, path: config.path
         , pingTimeout: config.pingTimeout, pingInterval: config.pingInterval }

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
-- | emitTo @"privateMsg" recipientHandle { text: "hello" }
-- | ```
emitTo
  :: forall @event protocol ns payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle protocol ns
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
-- | onEvent @"sendMessage" handle \msg ->
-- |   broadcastExceptSender @"newMessage" handle msg
-- | ```
broadcastExceptSender
  :: forall @event protocol ns payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle protocol ns
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
joinRoom :: forall protocol ns. NamespaceHandle protocol ns -> String -> Effect Unit
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
leaveRoom :: forall protocol ns. NamespaceHandle protocol ns -> String -> Effect Unit
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
-- | broadcastToRoom @"playerJoined" handle "game-42" { name: "Alice" }
-- | ```
broadcastToRoom
  :: forall @event protocol ns payload
   . IsValidMsg protocol ns event "s2c" payload
  => IsSymbol event
  => NamespaceHandle protocol ns
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
-- | onConnection @AppProtocol @"lobby" server \handle -> do
-- |   onEvent @"chat" handle \payload ->
-- |     log payload.text
-- | ```
onConnection
  :: forall @protocol @ns
   . IsSymbol ns
  => ServerSocket
  -> (NamespaceHandle protocol ns -> Effect Unit)
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
-- | onEvent @"chat" handle \payload ->
-- |   log payload.text
-- | ```
onEvent
  :: forall @event protocol ns payload
   . IsValidMsg protocol ns event "c2s" payload
  => IsSymbol event
  => NamespaceHandle protocol ns
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
-- | onCallEvent @"join" handle \payload ->
-- |   pure { success: true }
-- | ```
onCallEvent
  :: forall @event protocol ns payload res
   . IsValidCall protocol ns event "c2s" payload res
  => IsSymbol event
  => NamespaceHandle protocol ns
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
  :: forall protocol ns
   . NamespaceHandle protocol ns
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
  :: forall protocol ns
   . NamespaceHandle protocol ns
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

foreign import primCreateServerWithHttpServer :: HttpServer -> Effect ServerSocket

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

foreign import primCreateServerWithOpts :: forall opts. { | opts } -> Effect ServerSocket

foreign import primCreateServerWithPortAndOpts :: forall opts. Int -> { | opts } -> Effect ServerSocket

foreign import primCreateServerWithHttpServerAndOpts :: forall opts. HttpServer -> { | opts } -> Effect ServerSocket

foreign import primCreateServerWithBunEngine :: forall opts. BunEngine -> { | opts } -> Effect ServerSocket
