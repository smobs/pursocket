# Retro Notes: Web Tech Expert

Capture difficulties as you work. One entry per obstacle is enough.

---

### [Date] - [Brief title]

**What happened:** [1-2 sentences describing the obstacle]

**Impact:** [Time lost, rework required, scope cut, etc.]

**Root cause:** [Missing info, wrong assumption, tooling issue, unclear requirements, etc.]

---

### 2026-02-03 - NamespaceHandle needed structural change for FFI

**What happened:** The original `NamespaceHandle` had no fields (`data NamespaceHandle (ns :: Symbol) = NamespaceHandle`), making it impossible to carry the underlying JS socket reference needed for real FFI. Both client and server FFI need the handle to wrap an actual socket object. Had to add `foreign import data SocketRef :: Type` to Framework and modify `NamespaceHandle` to hold it, which was a cross-cutting change affecting both Client and Server modules.

**Impact:** Minor -- required coordinating the change across Framework, Internal (new module), Client, and Server. No time lost because the change was straightforward, but it is an architectural detail that the original skeleton did not anticipate.

**Root cause:** The initial skeleton treated `NamespaceHandle` as a pure phantom type (no runtime payload). Real FFI requires it to carry a socket reference. This is a natural consequence of moving from stubs to real implementations.

---

### 2026-02-03 - Constructor visibility tradeoff in PureScript module system

**What happened:** PureScript does not support "friend" modules or package-private exports. To allow `PurSocket.Internal` to construct `NamespaceHandle` values, `Framework` must export the constructor (`NamespaceHandle(..)`). This weakens the abstraction boundary -- any consumer could import the constructor directly.

**Impact:** No time lost. Accepted as a known PureScript limitation. The privacy guarantee is maintained by convention and documentation (Internal module is documented as non-public API). This is the standard pattern used by libraries like `purescript-aff` and `purescript-halogen`.

**Root cause:** PureScript module system lacks visibility modifiers beyond public/private at the module level.

---

<!-- Add more entries below as needed -->
