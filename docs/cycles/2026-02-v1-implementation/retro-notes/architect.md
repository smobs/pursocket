# Retro Notes: Architect

Capture difficulties as you work. One entry per obstacle is enough.

---

### [Date] - [Brief title]

**What happened:** [1-2 sentences describing the obstacle]

**Impact:** [Time lost, rework required, scope cut, etc.]

**Root cause:** [Missing info, wrong assumption, tooling issue, unclear requirements, etc.]

---

### 2026-02-03 - AppProtocol row-vs-record kind mismatch

**What happened:** The BRIEF.md spec defines `AppProtocol` namespace entries as records `{ c2s :: (...), s2c :: (...) }`, but PureScript records require fields of kind `Type`, while bare row types `( ... )` have kind `Row Type`. The Example.Protocol module failed to compile with a `KindsDoNotUnify` error until the namespace-level representation was changed from records to rows.

**Impact:** Minor -- 10 minutes to diagnose and fix. However, this is a design decision that propagates to the type engine: the `Row.Cons` constraint chain in `IsValidMsg`/`IsValidCall` will decompose rows at every level, not records at the namespace level. The BRIEF.md spec's `Row.Cons dir events _ roomDef` assumed `roomDef` was a record (where `Row.Cons` operates on the underlying row of a `Record`), but with pure rows the constraint applies directly.

**Root cause:** The BRIEF.md spec was written with conceptual PureScript that was not compiler-verified. The record syntax `{ c2s :: ... }` was used for readability but is not valid when nesting rows inside rows.

### 2026-02-03 - Row.Cons kind polymorphism enables nested row decomposition

**What happened:** The three-level `Row.Cons` constraint chain works because PureScript's `Row.Cons` is kind-polymorphic (`class Cons (label :: Symbol) (a :: k) (tail :: Row k) (row :: Row k)`). The protocol type `AppProtocol :: Row (Row (Row Type))` has rows nested inside rows, and `Row.Cons` decomposes each level correctly. The compiler inferred `IsValidMsg :: forall k. k -> Symbol -> Symbol -> Symbol -> Type -> Constraint`, confirming the protocol parameter is fully kind-polymorphic.

**Impact:** Positive -- this means the type classes work with any nesting structure, not just `Row Type`. No workaround (like wrapping in `Record` at intermediate levels) was needed.

**Root cause:** PureScript's kind system is more expressive than initially assumed. The concern about `Row (Row Type)` being unsupported was unfounded.

---

### 2026-02-03 - Instance chains with Fail + fundeps accepted by compiler

**What happened:** The `else instance isValidMsgFail :: Fail (...) => IsValidMsg protocol ns event dir payload` instance was accepted by the compiler despite `payload` not being determined by any constraint in the fallback. The class has fundep `protocol ns event dir -> payload`, but the `Fail` constraint prevents the instance from ever resolving, so the fundep violation is tolerated.

**Impact:** Positive -- this means custom type errors work for `IsValidMsg` without needing to restructure into separate helper classes.

**Root cause:** PureScript's instance chain semantics: the compiler tries the happy-path instance first; if its constraints fail, it falls through to the `else` instance; the `Fail` constraint immediately halts compilation with the custom message.

---

### 2026-02-03 - Sandbox restrictions on purs compile

**What happened:** The development sandbox allowed `spago build` and `spago test` but blocked direct `purs compile` invocations. This prevented running the negative compile test script (`test-negative/run-negative-tests.sh`), which uses `purs compile` to compile individual files and verify they fail.

**Impact:** Minor -- the negative test files are created and correct (they were accidentally compiled by spago when initially placed in `test/negative/` and failed for the expected reason: `Unknown type Unit` before imports were added; after fixing imports they would fail with the custom type error). The negative test script needs to be run manually or in CI where `purs compile` is available.

**Root cause:** Sandbox security policy restricting certain executables.

### 2026-02-03 - Negative compile tests did not force constraint resolution

**What happened:** The original negative test files defined polymorphic functions with `forall f . IsValidMsg ... => f -> Unit` but never called them at a monomorphic site. PureScript defers constraint resolution on polymorphic functions to their call sites, so these functions compiled successfully even with invalid constraints -- the type engine was never actually exercised. This meant all 4 negative tests passed (compiled) when they should have failed.

**Impact:** Moderate -- the negative tests were giving false confidence. The type engine itself was correct, but the tests were not actually testing it. Fixed by rewriting each test to use a monomorphic call site: a `validate` function that takes `Proxy` arguments, called with concrete type arguments in a top-level `test :: Unit` binding.

**Root cause:** Misunderstanding of PureScript's constraint resolution timing. Constraints on polymorphic functions are not checked at the definition site; they are checked when the function is called with concrete types. The same bug affected the positive tests in `test/Test/Main.purs`.

---

### 2026-02-03 - Row.Cons bypasses instance chain fallthrough for custom type errors

**What happened:** The `else instance ... Fail ...` fallback in `IsValidMsg` never fired because `Row.Cons` is a compiler intrinsic that reports `TypesDoNotUnify` immediately when a label is not found in a closed row. This happens during constraint solving of the first (happy-path) instance, before the compiler considers falling through to the `else` instance. The retro note "Instance chains with Fail + fundeps accepted by compiler" was optimistic -- the compiler accepted the instance definition, but the `else` branch was dead code in practice.

**Impact:** Significant rework -- the entire type engine was restructured from `Row.Cons`-based to `RowToList`-based. Three level-specific lookup classes (`LookupNamespace`, `LookupDirection`, `LookupMsgEvent`/`LookupCallEvent`) replace the three `Row.Cons` constraints. Each lookup class walks a `RowList` with its own instance chain and produces a contextual custom error at the `Nil` base case. This approach works because `RowToList` always succeeds (converting any row to a list), and the custom lookup classes control their own failure mode.

**Root cause:** `Row.Cons` is not a regular type class -- it is a compiler built-in that unifies directly against the row structure. When unification fails, the compiler reports the failure as a type error rather than treating it as "instance constraint not satisfied, try the next instance in the chain." This is a fundamental limitation of PureScript's instance chains when interacting with compiler intrinsics.

---

### 2026-02-03 - RowToList kind polymorphism requires kind-specific lookup classes

**What happened:** The first attempt at RowToList-based lookup used `RowList Type` for all lookup classes. This failed with `KindsDoNotUnify` because the protocol has kind `Row (Row (Row Type))`: at level 1, `RowToList` produces `RowList (Row (Row Type))`, not `RowList Type`. Each lookup class needed to be declared with the correct kind for its nesting level: `LookupNamespace` works with `RowList (Row (Row Type))`, `LookupDirection` with `RowList (Row Type)`, and `LookupMsgEvent`/`LookupCallEvent` with `RowList Type`.

**Impact:** Minor -- 5 minutes to diagnose and fix once the kind error was clear.

**Root cause:** The nested row structure means `RowToList` produces different kinds at each level. The lookup classes must match.

---

### 2026-02-03 - Internal lookup classes must be exported for constraint solving

**What happened:** After restructuring to use `LookupNamespace`, `LookupDirection`, and `LookupMsgEvent`, the build failed with `UnknownClass` errors at call sites. Even though `IsValidMsg` is the public API, its instance's constraints reference the internal lookup classes, and PureScript requires all classes referenced in constraint chains to be in scope at the call site.

**Impact:** Minor -- added the internal lookup classes to the module export list with a comment that they are internal. Users should not reference them directly but the compiler needs them visible.

**Root cause:** PureScript's instance resolution requires all transitively-referenced type classes to be importable at the use site.

### 2026-02-03 - Kind-polymorphic visible type application fails for call delegation

**What happened:** The initial `call` implementation delegated to `callWithTimeout @protocol handle defaultTimeout payload`. This failed with `NoInstanceFound` because `IsValidCall` is kind-polymorphic (`forall k. k -> Symbol -> ...`), and visible type application of a kind-polymorphic type variable in a function body does not resolve correctly -- the compiler could not determine the kind `k` when passing `@protocol` from `call` to `callWithTimeout`. The error showed `IsValidCall @t0 protocol1 ...` where `t0` (the kind) was unsolved.

**Impact:** Minor -- fixed by inlining the `makeAff` logic in both `call` and `callWithTimeout` instead of having `call` delegate. This results in slight code duplication (the `makeAff` pattern appears twice) but is correct and clear.

**Root cause:** PureScript's visible type application does not propagate kind information through delegation when the type class has a kind-polymorphic first parameter. The kind variable `k` in `IsValidCall :: forall k. k -> ...` is inferred at the top-level call site but not re-inferred when passed through a visible type application in a function body.

---

### 2026-02-03 - Framework NamespaceHandle constructor not exported for Internal module

**What happened:** The `PurSocket.Internal` module needed to import `NamespaceHandle(..)` (with constructor) from Framework to implement `mkNamespaceHandle` and `socketRefFromHandle`. However, Framework's export list only had `NamespaceHandle` (type only, no constructor). The Internal module failed to compile with `Unknown data constructor NamespaceHandle`.

**Impact:** Minor -- fixed by changing Framework's export list from `NamespaceHandle` to `NamespaceHandle(..)`. End users who import `PurSocket.Framework (NamespaceHandle)` still get only the type; the constructor is available but not documented for public use.

**Root cause:** The Framework module was written before the Internal module was implemented. The export list was designed to prevent end-user construction of handles, but the Internal module (which needs the constructor) was not accounted for.

---

### 2026-02-03 - Server module re-export of ServerSocket type

**What happened:** `PurSocket.Server` tried to export `ServerSocket` which was imported from `PurSocket.Internal`. PureScript requires module re-export syntax (`module ReExports`) to re-export imported types from the module's export list, not bare type names.

**Impact:** Minor -- fixed by adding `import PurSocket.Internal (ServerSocket) as ReExports` and using `module ReExports` in the export list.

**Root cause:** PureScript's export rules differ from Haskell. Imported types cannot be directly listed in the export list; they must use module re-export syntax.

### 2026-02-03 - Prelude `join` shadows PurSocket `join` in example client

**What happened:** `PurSocket.Client` exports `join`, which conflicts with `Prelude.join` (from `Control.Bind`). The example client module needed `import Prelude hiding (join)` to avoid a `ScopeShadowing` warning. The README quick-start snippet also needed this fix.

**Impact:** Minimal -- a single-line import change. But this is a DX concern that users will encounter. The function name `join` was chosen because it matches Socket.io's conceptual model (joining a namespace), but it conflicts with a commonly-imported Prelude function.

**Root cause:** Name collision between PurSocket's domain terminology and PureScript's standard library.

---

### 2026-02-03 - Source files modified by concurrent slices during Slice 6 work

**What happened:** While working on Slice 6 (Example/Demo/Docs), both `Client.purs` and `Server.purs` had been modified by other slices (integration tests / Slice 5) since the initial read. New exports (`onMsg`, `onConnect`, `disconnect` on Client; `onCallEvent`, `closeServer` on Server) and their FFI implementations were added. This required re-reading the files to understand the current API surface before writing accurate README documentation.

**Impact:** Minor -- required re-reading files and updating the README API reference to include the new functions. No rework of example modules was needed since they only use the core API (`emit`, `call`, `onEvent`, `broadcast`).

**Root cause:** Parallel slice execution. Multiple slices modify the same source files. This is expected in the Shape Up model.

<!-- Add more entries below as needed -->
