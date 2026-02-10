# PureScript API Gotchas

Stdlib behaviors that have caused bugs in this project. Check here before using unfamiliar APIs.

---

### `Ref.modify` returns the NEW value

`Effect.Ref.modify` applies the function and returns the **new** (post-modification) value, not the old value.

```purescript
ref <- Ref.new 0
n <- Ref.modify (_ + 1) ref
-- n is 1, NOT 0
```

If you need the old value, read before modifying:

```purescript
old <- Ref.read ref
Ref.modify_ (_ + 1) ref
```

**Discovered:** 2026-02-04 during emitTo integration tests. Case patterns matching on `Ref.modify` counter results needed to use 1/2/3 instead of 0/1/2.

---
