-- | PurSocket.Framework
-- |
-- | Type-level validation engine.  `IsValidMsg` and `IsValidCall` use
-- | `RowToList`-based lookup to verify at compile time that an event
-- | exists in the correct namespace and direction of the application
-- | protocol, producing custom type errors on failure.
-- |
-- | `NamespaceHandle` is a phantom-typed capability token: you can only
-- | send messages to a namespace if you hold its handle.
-- |
-- | The type classes are parameterized by the protocol row type so that
-- | any application can define its own protocol.  The `emit`, `call`,
-- | and `broadcast` functions in the Client/Server modules fix the
-- | protocol to the application's specific type.
-- |
-- | The protocol uses row types at every nesting level (not records).
-- |
-- | Architecture:
-- |   - Level-specific lookup classes walk `RowList`s to find labels.
-- |     Each level is kind-polymorphic to match the nesting depth:
-- |     protocol row has kind `Row (Row (Row Type))`, namespace defs
-- |     have kind `Row (Row Type)`, events have kind `Row Type`.
-- |   - `IsValidMsg` converts each row level to a `RowList` via
-- |     `RowToList`, then uses the lookup classes to validate
-- |     namespace -> direction -> event
-- |   - `IsValidCall` does the same but expects `Call payload response`
-- |     instead of `Msg payload`
-- |
-- | Why not `Row.Cons`?
-- |   PureScript's `Row.Cons` is a compiler intrinsic.  When it cannot
-- |   find a label in a closed row, it reports a `TypesDoNotUnify` error
-- |   immediately -- before instance chain fallthrough can occur.  This
-- |   means `else instance ... Fail ...` never fires.  Using `RowToList`
-- |   + custom lookup classes avoids this: `RowToList` always succeeds
-- |   (converting any row to a list), and each lookup class uses its own
-- |   instance chain to produce a contextual custom error.
module PurSocket.Framework
  ( NamespaceHandle(..)
  , SocketRef
  , class IsValidMsg
  , class IsValidCall
  -- Internal lookup classes: exported because they appear in the
  -- superclass constraints of IsValidMsg/IsValidCall instances.
  -- Users should not reference these directly.
  , class LookupNamespace
  , class LookupDirection
  , class LookupMsgEvent
  , class LookupCallEvent
  ) where

import Prim.RowList as RL
import Prim.TypeError (class Fail, Above, Beside, QuoteLabel, Text)
import PurSocket.Protocol (Msg, Call)

-- | An opaque reference to a JavaScript socket object (either a
-- | socket.io-client Socket or a socket.io server-side Socket).
-- | This is an implementation detail — users never interact with
-- | `SocketRef` directly.
foreign import data SocketRef :: Type

-- | A capability token tied to a specific namespace in the protocol.
-- | The `ns` phantom type parameter (a `Symbol`) identifies which
-- | namespace this handle grants access to.
-- |
-- | Internally holds a `SocketRef` — the underlying JS socket for
-- | this namespace connection.
-- |
-- | The data constructor is exported for use by `PurSocket.Internal`
-- | only.  Library consumers should treat `NamespaceHandle` as opaque
-- | and obtain instances only via `join` (Client) or `onConnection`
-- | (Server).
data NamespaceHandle :: forall k. k -> Symbol -> Type
data NamespaceHandle protocol (ns :: Symbol) = NamespaceHandle SocketRef

-- ---------------------------------------------------------------------------
-- Level 1: LookupNamespace
-- ---------------------------------------------------------------------------
-- | Look up a namespace in the protocol RowList.
-- | The protocol has kind `Row (Row (Row Type))`, so RowToList produces
-- | `RowList (Row (Row Type))` -- each value has kind `Row (Row Type)`.
class LookupNamespace
  :: Symbol
  -> RL.RowList (Row (Row Type))
  -> Row (Row Type)
  -> Constraint
class LookupNamespace (ns :: Symbol) (protoList :: RL.RowList (Row (Row Type))) (nsDef :: Row (Row Type))
  | ns protoList -> nsDef

instance lookupNamespaceMatch ::
  LookupNamespace ns (RL.Cons ns nsDef rest) nsDef

else instance lookupNamespaceRecurse ::
  LookupNamespace ns rest nsDef
  => LookupNamespace ns (RL.Cons other otherDef rest) nsDef

else instance lookupNamespaceNil ::
  Fail
    ( Above
        (Text "PurSocket: unknown namespace.")
        ( Above
            ( Beside (Text "  Namespace: ") (QuoteLabel ns) )
            (Text "  This namespace does not exist in your protocol definition.")
        )
    )
  => LookupNamespace ns RL.Nil nsDef

-- ---------------------------------------------------------------------------
-- Level 2: LookupDirection
-- ---------------------------------------------------------------------------
-- | Look up a direction ("c2s" or "s2c") in a namespace definition RowList.
-- | Namespace defs have kind `Row (Row Type)`, so RowToList produces
-- | `RowList (Row Type)` -- each value has kind `Row Type`.
class LookupDirection
  :: Symbol  -- direction
  -> Symbol  -- namespace name (for error context)
  -> RL.RowList (Row Type)
  -> Row Type
  -> Constraint
class LookupDirection (dir :: Symbol) (ns :: Symbol) (nsList :: RL.RowList (Row Type)) (events :: Row Type)
  | dir nsList -> events

instance lookupDirectionMatch ::
  LookupDirection dir ns (RL.Cons dir events rest) events

else instance lookupDirectionRecurse ::
  LookupDirection dir ns rest events
  => LookupDirection dir ns (RL.Cons other otherEvents rest) events

else instance lookupDirectionNil ::
  Fail
    ( Above
        (Text "PurSocket: unknown direction in namespace.")
        ( Above
            ( Beside (Text "  Namespace: ") (QuoteLabel ns) )
            ( Above
                ( Beside (Text "  Direction: ") (QuoteLabel dir) )
                (Text "  Expected \"c2s\" or \"s2c\".")
            )
        )
    )
  => LookupDirection dir ns RL.Nil events

-- ---------------------------------------------------------------------------
-- Level 3: LookupMsgEvent / LookupCallEvent
-- ---------------------------------------------------------------------------
-- | Look up an event tagged as `Msg payload` in an events RowList.
-- | Events have kind `Row Type`, so RowToList produces `RowList Type`.
class LookupMsgEvent
  :: Symbol  -- event name
  -> Symbol  -- namespace (for error context)
  -> Symbol  -- direction (for error context)
  -> RL.RowList Type
  -> Type  -- payload
  -> Constraint
class LookupMsgEvent (event :: Symbol) (ns :: Symbol) (dir :: Symbol) (eventsList :: RL.RowList Type) (payload :: Type)
  | event eventsList -> payload

instance lookupMsgEventMatch ::
  LookupMsgEvent event ns dir (RL.Cons event (Msg payload) rest) payload

else instance lookupMsgEventRecurse ::
  LookupMsgEvent event ns dir rest payload
  => LookupMsgEvent event ns dir (RL.Cons other otherVal rest) payload

else instance lookupMsgEventNil ::
  Fail
    ( Above
        (Text "PurSocket: invalid Msg event.")
        ( Above
            ( Beside (Text "  Namespace: ") (QuoteLabel ns) )
            ( Above
                ( Beside (Text "  Event:     ") (QuoteLabel event) )
                ( Above
                    ( Beside (Text "  Direction: ") (QuoteLabel dir) )
                    (Text "  Check that the event name exists in this namespace/direction and is tagged as Msg.")
                )
            )
        )
    )
  => LookupMsgEvent event ns dir RL.Nil payload

-- | Look up an event tagged as `Call payload response` in an events RowList.
class LookupCallEvent
  :: Symbol  -- event name
  -> Symbol  -- namespace (for error context)
  -> Symbol  -- direction (for error context)
  -> RL.RowList Type
  -> Type  -- payload
  -> Type  -- response
  -> Constraint
class LookupCallEvent (event :: Symbol) (ns :: Symbol) (dir :: Symbol) (eventsList :: RL.RowList Type) (payload :: Type) (response :: Type)
  | event eventsList -> payload response

instance lookupCallEventMatch ::
  LookupCallEvent event ns dir (RL.Cons event (Call payload response) rest) payload response

else instance lookupCallEventRecurse ::
  LookupCallEvent event ns dir rest payload response
  => LookupCallEvent event ns dir (RL.Cons other otherVal rest) payload response

else instance lookupCallEventNil ::
  Fail
    ( Above
        (Text "PurSocket: invalid Call event.")
        ( Above
            ( Beside (Text "  Namespace: ") (QuoteLabel ns) )
            ( Above
                ( Beside (Text "  Event:     ") (QuoteLabel event) )
                ( Above
                    ( Beside (Text "  Direction: ") (QuoteLabel dir) )
                    (Text "  Check that the event name exists in this namespace/direction and is tagged as Call.")
                )
            )
        )
    )
  => LookupCallEvent event ns dir RL.Nil payload response

-- ---------------------------------------------------------------------------
-- IsValidMsg: fire-and-forget message validation
-- ---------------------------------------------------------------------------

-- | Validates that a fire-and-forget `Msg` event exists in the given
-- | namespace and direction of an application protocol.
-- |
-- | Uses `RowToList` at each nesting level, then level-specific lookup
-- | classes (`LookupNamespace`, `LookupDirection`, `LookupMsgEvent`)
-- | to walk the type-level lists.  Each lookup class has its own `Fail`
-- | fallback with a contextual error message.
-- |
-- | The functional dependency `protocol ns event dir -> payload` means
-- | the compiler infers the payload type from the protocol, namespace,
-- | event name, and direction.
class IsValidMsg :: forall k. k -> Symbol -> Symbol -> Symbol -> Type -> Constraint
class IsValidMsg protocol (ns :: Symbol) (event :: Symbol) (dir :: Symbol) (payload :: Type)
  | protocol ns event dir -> payload

instance isValidMsgImpl ::
  ( RL.RowToList protocol protoList
  , LookupNamespace ns protoList nsDef
  , RL.RowToList nsDef nsList
  , LookupDirection dir ns nsList events
  , RL.RowToList events eventsList
  , LookupMsgEvent event ns dir eventsList payload
  ) => IsValidMsg protocol ns event dir payload

-- ---------------------------------------------------------------------------
-- IsValidCall: request/response validation
-- ---------------------------------------------------------------------------

-- | Validates that a request/response `Call` event exists in the given
-- | namespace and direction of an application protocol.
-- |
-- | Uses the same `RowToList` + lookup approach as `IsValidMsg` but
-- | uses `LookupCallEvent` to extract `Call payload response`.
-- |
-- | The functional dependency `protocol ns event dir -> payload response`
-- | means the compiler infers both payload and response types.
-- |
-- | Note: This fixes the fundep bug from BRIEF.md where the original spec
-- | listed `IsValidCall room event dir res` (4 params in instance head)
-- | but the class had 5 params.  Both `payload` and `response` are now
-- | correctly bound through the lookup constraint chain.
class IsValidCall :: forall k. k -> Symbol -> Symbol -> Symbol -> Type -> Type -> Constraint
class IsValidCall protocol (ns :: Symbol) (event :: Symbol) (dir :: Symbol) (payload :: Type) (response :: Type)
  | protocol ns event dir -> payload response

instance isValidCallImpl ::
  ( RL.RowToList protocol protoList
  , LookupNamespace ns protoList nsDef
  , RL.RowToList nsDef nsList
  , LookupDirection dir ns nsList events
  , RL.RowToList events eventsList
  , LookupCallEvent event ns dir eventsList payload response
  ) => IsValidCall protocol ns event dir payload response
