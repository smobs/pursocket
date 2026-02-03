-- | PurSocket.Internal
-- |
-- | Internal module exposing types and constructors that are hidden
-- | from library consumers but needed by both Client and Server modules.
-- |
-- | **This module is not part of the public API.**  Do not depend on it
-- | directly — its exports may change without notice.
module PurSocket.Internal
  ( module PurSocket.Framework
  , ServerSocket
  , mkNamespaceHandle
  , socketRefFromHandle
  ) where

import PurSocket.Framework (NamespaceHandle(..), SocketRef)

-- | An opaque reference to a Socket.io Server instance.
-- | Created by `createServer` / `createServerWithPort` in Server.
foreign import data ServerSocket :: Type

-- | Construct a `NamespaceHandle` from an opaque socket reference.
-- | This is the only way to create a handle outside of Framework.
mkNamespaceHandle :: forall ns. SocketRef -> NamespaceHandle ns
mkNamespaceHandle = NamespaceHandle

-- | Extract the underlying socket reference from a handle.
socketRefFromHandle :: forall ns. NamespaceHandle ns -> SocketRef
socketRefFromHandle (NamespaceHandle ref) = ref
