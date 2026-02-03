// FFI for PurSocket.BrowserTest
// Utility to prevent dead code elimination of Client API references.

// isFunction :: forall a. a -> Boolean
export const isFunction = (x) => typeof x === "function";
