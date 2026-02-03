# Slice: Protocol & Type Engine

**Status:** Complete (revised)

## What This Slice Delivers
The core type-level machinery that makes PurSocket work: the `Msg`/`Call` data kinds, the `IsValidMsg`/`IsValidCall` type classes with `RowToList`-based lookup chains, `NamespaceHandle` phantom type, and custom type error messages. A developer can define an `AppProtocol` and get compile-time validation that events exist in the correct namespace and direction, with clear error messages on failure.

## Scope
- `PurSocket.Protocol`: `Msg`, `Call` data kinds
- `PurSocket.Framework`: `IsValidMsg`, `IsValidCall` type classes with three-level `RowToList` + custom lookup chains
- `PurSocket.Framework`: `NamespaceHandle (ns :: Symbol)` phantom-typed capability token
- `PurSocket.Framework`: Level-specific lookup classes (`LookupNamespace`, `LookupDirection`, `LookupMsgEvent`, `LookupCallEvent`) with custom `Fail` errors
- Fix the `IsValidCall` fundep bug from BRIEF.md during implementation
- Custom type errors via `Prim.TypeError.Fail` for both `IsValidMsg` and `IsValidCall` (at all three levels)
- Negative compile tests: wrong event name, wrong namespace, wrong direction, wrong payload type all fail to compile with custom errors
- Rename BRIEF.md terminology: rooms -> namespaces throughout

## NOT in This Slice
- FFI bindings (no JavaScript)
- Runtime functions (emit, call, broadcast)

## Dependencies
- Slice 1 (Project Skeleton & CI) must be complete

## Acceptance Criteria
- [x] `PurSocket.Protocol` exports `Msg` and `Call` data kinds
- [x] `PurSocket.Framework` exports `IsValidMsg`, `IsValidCall`, `NamespaceHandle`
- [x] `IsValidMsg` validates namespace, direction, and event at compile time via `RowToList` + custom lookup
- [x] `IsValidCall` validates namespace, direction, event, payload, and response types
- [x] `IsValidCall` fundep bug from BRIEF.md is fixed
- [x] `NamespaceHandle` is a phantom-typed data type with hidden constructor
- [x] Custom type errors fire for `IsValidMsg` failures (wrong namespace, wrong direction, wrong event)
- [x] Custom type errors fire for `IsValidCall` failures (wrong namespace, wrong direction, wrong event)
- [x] Negative compile tests prove type safety (wrong event names, wrong namespaces, wrong directions, wrong payloads are rejected)
- [x] Positive compile tests use monomorphic call sites that genuinely force constraint resolution
- [x] All code compiles: `spago build` succeeds

## Verification (Required)
- [x] Tests run and pass: `spago test` -> 11/11 tests pass
- [x] Negative compile tests: 4 files in `test-negative/` verified to fail compilation with custom error messages
- [x] `spago build` -> exits 0 with zero warnings
- [x] Negative test error messages verified:
  - WrongEventName: "PurSocket: invalid Msg event. Namespace: lobby, Event: typo, Direction: c2s"
  - WrongNamespace: "PurSocket: unknown namespace. Namespace: nonexistent"
  - WrongDirection: "PurSocket: invalid Msg event. Namespace: lobby, Event: userCount, Direction: c2s"
  - WrongPayload: "Could not match type { text :: String } with type { wrong :: Boolean }" (structural mismatch -- correct behavior)

## Build Notes

**What does "done" look like?** The `IsValidMsg` and `IsValidCall` type classes compile and correctly constrain events via three-level `RowToList` + custom lookup chains. Custom type errors fire for failures at every level (wrong namespace, wrong direction, wrong event). `NamespaceHandle` hides its constructor. Positive tests use monomorphic call sites. Negative compile tests prove wrong event/namespace/direction/payload are rejected. `spago build` and `spago test` pass.

**Critical path:** The three-level `RowToList` + lookup chain is the core. `RowToList` converts each row to a type-level list, then level-specific lookup classes walk the list. Each lookup class has an instance chain: match -> recurse -> `Fail` at `Nil`.

**Architecture (revised):**

The original approach used `Row.Cons` constraints in the `IsValidMsg` instance, with an `else instance ... Fail ...` fallback. This did not work because `Row.Cons` is a compiler intrinsic that reports `TypesDoNotUnify` before instance chain fallthrough occurs.

The working approach uses `RowToList` at each level, converting rows to type-level lists, then custom lookup classes walk the lists:

1. `LookupNamespace` -- `RowList (Row (Row Type))` -> finds namespace, returns `Row (Row Type)`
2. `LookupDirection` -- `RowList (Row Type)` -> finds direction, returns `Row Type`
3. `LookupMsgEvent` / `LookupCallEvent` -- `RowList Type` -> finds event, returns payload (and response for Call)

Each lookup class has three instances: match at head, recurse into tail, and `Fail` at `Nil` with a level-specific error message.

### Key Technical Findings

1. **Row.Cons cannot be used with instance chain fallthrough.** `Row.Cons` is a compiler intrinsic; when it fails, it reports a `TypesDoNotUnify` error immediately rather than allowing fallthrough to `else` instances. This is a fundamental limitation of PureScript's instance chains when interacting with compiler built-ins.

2. **RowToList is kind-polymorphic and always succeeds.** `RowToList` converts any row to a `RowList` regardless of content. For `Row (Row (Row Type))`, it produces `RowList (Row (Row Type))`. This makes it safe to use as a "pre-processing" step before custom lookup.

3. **Lookup classes must use correct kinds at each level.** The protocol nesting means different kinds at each level: `RowList (Row (Row Type))` at level 1, `RowList (Row Type)` at level 2, `RowList Type` at level 3.

4. **Internal classes must be exported.** Even though `LookupNamespace`, `LookupDirection`, `LookupMsgEvent`, and `LookupCallEvent` are internal implementation details, PureScript requires all classes referenced in instance constraints to be importable at call sites.

5. **Monomorphic call sites are required for compile-time testing.** Polymorphic functions like `forall f . IsValidMsg ... => f -> Unit` defer constraint resolution to call sites. To test that constraints are actually checked, use a concrete type like `test :: Unit` that calls a generic validator with `Proxy` arguments.

6. **IsValidCall fundep bug fix.** The BRIEF.md spec had `IsValidCall room event dir res` (missing `payload` from the instance head). Fixed by including both `payload` and `response` as class parameters, both bound through the lookup constraint chain.

7. **Wrong payload produces a structural type error, not a custom error.** When the event IS found but the payload type doesn't match (e.g., `{ wrong :: Boolean }` vs `{ text :: String }`), the error comes from type unification rather than instance resolution. This is correct behavior -- the custom error system handles "not found" cases, while type unification handles "found but wrong type" cases.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-03 | Complete | Initial implementation with Row.Cons chains, custom type errors for IsValidMsg via instance chains, NamespaceHandle with hidden constructor, 11 positive compile tests, 4 negative compile test files. |
| 2026-02-03 | Revised | Fixed two critical bugs: (1) Negative and positive tests were not forcing constraint resolution due to polymorphic function definitions without monomorphic call sites. Rewrote all tests to use Proxy-based validators with concrete call sites. (2) Custom type errors were not firing because Row.Cons bypasses instance chain fallthrough. Restructured type engine from Row.Cons to RowToList + custom lookup classes (LookupNamespace, LookupDirection, LookupMsgEvent, LookupCallEvent). All 4 negative tests now correctly fail with custom error messages. Also added custom errors for IsValidCall (was previously deferred). |
