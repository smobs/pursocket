Here is the updated specification, including the core philosophy and architectural principles driving this design.

# Type-Safe Socket.io Protocol Specification (PureScript 2026)

## 1. Motivation & Principles

The primary motivation for this architecture is to eliminate the **"String-Oriented Programming"** trap common in distributed systems. In standard JavaScript Socket.io development, event names are arbitrary strings, and payloads are untyped JSON. This leads to runtime crashes when the server and client drift out of sync.

### Guiding Principles

* **Single Source of Truth:** The `AppProtocol` row is the only place where events are defined. If it isn't there, it doesn't exist.
* **The "Protocol as a Gatekeeper":** We use the type system to enforce that the Client can only send `c2s` (Client-to-Server) messages and the Server can only emit `s2c` (Server-to-Client) messages.
* **Contextual Safety (The Handle Pattern):** Accessing a room must yield a `RoomHandle`. This handle acts as a capability; you cannot "speak" into a room unless you have the corresponding handle for that specific context.
* **Zero Runtime Overhead:** All the complexity lives at the type level. Once compiled, the generated JavaScript is as lean as standard Socket.io code, with no extra lookups or validation libraries needed.

---

## 2. The Shared Protocol (`Shared.Protocol`)

```purescript
module Shared.Protocol where

-- | Tags to differentiate interaction patterns
data Msg payload            -- Fire and forget
data Call payload response   -- Request/Response (Acknowledgements)

-- | The master schema defining rooms and their directions
type AppProtocol =
  ( lobby :: 
      { c2s :: ( chat :: Msg { text :: String }
               , join :: Call { name :: String } { success :: Boolean }
               )
      , s2c :: ( userCount :: Msg { count :: Int } )
      }
  , game :: 
      { c2s :: ( move :: Msg { x :: Int, y :: Int } )
      , s2c :: ( gameOver :: Msg { winner :: String } )
      }
  )

```

---

## 3. The Type-Level Engine (`Socket.Framework`)

```purescript
module Socket.Framework where

import Prelude
import Prim.Row as Row
import Type.Proxy (Proxy(..))
import Data.Symbol (reflectSymbol)
import Effect (Effect)
import Effect.Aff (Aff)
import Shared.Protocol (AppProtocol, Msg, Call)

-- | A handle tied to a specific room in the protocol
data RoomHandle (room :: Symbol) = RoomHandle Socket

-- | Internal Socket reference
foreign import data Socket :: Type

-- | Constraint to validate Message events
class IsValidMsg (room :: Symbol) (event :: Symbol) (dir :: Symbol) payload 
  | room event dir -> payload

instance msgImpl :: 
  ( Row.Cons room roomDef _ AppProtocol
  , Row.Cons dir events _ roomDef
  , Row.Cons event (Msg payload) _ events
  ) => IsValidMsg room event dir payload

-- | Constraint to validate Call (Req/Res) events
class IsValidCall (room :: Symbol) (event :: Symbol) (dir :: Symbol) payload res 
  | room event dir -> payload res

instance callImpl :: 
  ( Row.Cons room roomDef _ AppProtocol
  , Row.Cons dir events _ roomDef
  , Row.Cons event (Call payload res) _ events
  ) => IsValidCall room event dir res

```

---

## 4. The API Implementation

### Client-Side API

```purescript
-- | Emit a fire-and-forget message
emit :: forall @room @event payload
      . IsValidMsg room event "c2s" payload
     => RoomHandle room 
     -> payload 
     -> Effect Unit
emit (RoomHandle s) payload = primEmit s (reflectSymbol (Proxy @event)) payload

-- | Execute a Request/Response call
call :: forall @room @event payload res
      . IsValidCall room event "c2s" payload res
     => RoomHandle room 
     -> payload 
     -> Aff res
call (RoomHandle s) payload = primCall s (reflectSymbol (Proxy @event)) payload

foreign import primEmit :: forall a. Socket -> String -> a -> Effect Unit
foreign import primCall :: forall a r. Socket -> String -> a -> Aff r

```

### Server-Side Broadcasting

```purescript
-- | Ensure we only broadcast events defined in the room's s2c row
broadcast :: forall @room @event payload
           . IsValidMsg room event "s2c" payload
          => Socket 
          -> payload 
          -> Effect Unit
broadcast s payload = primBroadcast s (reflectSymbol (Proxy @room)) (reflectSymbol (Proxy @event)) payload

foreign import primBroadcast :: forall a. Socket -> String -> String -> a -> Effect Unit

```

---

## 5. Usage Example

### Client Code

```purescript
main = do
  socket <- connect "http://api.myapp.com"
  
  -- Type-safe join gives us a Handle tied to @"lobby"
  lobby <- join @"lobby" socket 

  -- This compiles: "chat" is in "lobby" with correct payload
  emit @"chat" lobby { text: "Hello!" }

  -- This compiles: returns an Aff Boolean as defined in "join"
  res <- call @"join" lobby { name: "Alice" }
  
  -- COMPILER ERROR: "move" does not exist in "lobby"
  -- emit @"move" lobby { x: 1, y: 1 } 

```

### Server Code

```purescript
onConnect socket = do
  -- Broadcast to everyone in "game" that a game is over
  -- Validated against AppProtocol.game.s2c
  broadcast @"game" socket { winner: "Alice" }

```

---
