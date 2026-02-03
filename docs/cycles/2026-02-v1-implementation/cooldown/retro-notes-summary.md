# Retro Notes Summary

Difficulties captured by team members during building.

## By Team Member

### Architect (12 entries)
- Row-vs-record kind mismatch: BRIEF.md spec used records where rows were needed
- Row.Cons kind polymorphism: Positive finding — nested row decomposition works
- Instance chains with Fail + fundeps: Initially appeared to work but was dead code
- Sandbox restrictions on purs compile: Blocked negative test script execution
- Negative compile tests didn't force resolution: `forall f` pattern deferred constraint checking
- Row.Cons bypasses instance chain fallthrough: Required full RowToList rewrite of type engine
- RowToList kind polymorphism: Each nesting level needs its own kind in lookup classes
- Internal lookup classes must be exported: PureScript requires transitive class visibility
- Kind-polymorphic visible type application fails: Could not delegate `call` to `callWithTimeout`
- NamespaceHandle constructor not exported for Internal: Module export list needed updating
- Server module re-export syntax: PureScript requires `module ReExports` pattern
- Prelude `join` name collision: PurSocket.Client.join conflicts with Control.Bind.join

### Web Tech Expert (2 entries)
- NamespaceHandle structural change: Phantom-only type needed socket reference for real FFI
- Constructor visibility tradeoff: PureScript lacks friend modules, constructor must be public

### QA (3 entries)
- Broadcast test timing failure: Server broadcast before client namespace connected
- PureScript dead code elimination: Browser test references eliminated by compiler
- Client API missing onMsg: No way to receive s2c messages until added in Slice 5

## Common Themes

- **Spec vs reality (4 entries):** BRIEF.md assumptions (records, Row.Cons custom errors, phantom-only handles) didn't survive implementation — affected architect, web-tech-expert
- **PureScript module system constraints (3 entries):** Export visibility, re-export syntax, constructor accessibility — affected architect, web-tech-expert
- **Test infrastructure gaps (3 entries):** Constraint resolution, dead code elimination, missing client receive API — affected architect, qa
- **Async timing (1 entry):** Socket.io connection ordering required architectural fix — affected qa
