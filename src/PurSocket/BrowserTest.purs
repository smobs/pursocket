-- | PurSocket.BrowserTest
-- |
-- | Minimal browser entry point used to verify that PurSocket can be
-- | bundled for the browser via esbuild.  This module imports the full
-- | Client API and the example protocol, exercising all code paths
-- | that must survive bundling.
-- |
-- | This module is used by CI only (browser bundle smoke test).
-- | It is not part of the public API.
module PurSocket.BrowserTest
  ( main
  ) where

import Prelude hiding (join)

import Effect (Effect)
import Effect.Console (log)
import PurSocket.Client as Client

-- | Entry point for the browser bundle smoke test.
-- |
-- | Does not actually connect to a server -- it just proves that
-- | the Client module can be bundled for the browser.  The reference
-- | to `connect` at value level ensures the module is included.
main :: Effect Unit
main = do
  log "PurSocket browser bundle loaded successfully"
  -- Reference Client.connect at runtime so the bundler must include
  -- the Client module and its socket.io-client FFI dependency.
  log ("Client API available: " <> show (isFunction Client.connect))

-- | Check if a value is a function (always true for our purposes,
-- | but forces the compiler to keep the reference).
foreign import isFunction :: forall a. a -> Boolean
