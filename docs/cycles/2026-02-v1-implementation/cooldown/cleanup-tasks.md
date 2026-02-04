# Cleanup Tasks

**Project:** PurSocket v1 Implementation
**Cycle:** v1-implementation
**Started:** 2026-02-03

## Overview

| Total | Pending | In Progress | Complete |
|-------|---------|-------------|----------|
| 3 | 0 | 0 | 3 |

## Tasks

| # | Task | Type | Effort | Assignee | Status | Completed |
|---|------|------|--------|----------|--------|-----------|
| 1 | Commit all work to git | tech-debt | 1h | architect | complete | 2026-02-03 |
| 2 | Consider renaming `join` to avoid Prelude collision | polish | 2h | purescript-specialist | complete | 2026-02-03 |
| 3 | Add module-level doc comments for Pursuit | docs | 2h | purescript-specialist | complete | 2026-02-03 |

## Improvement Actions (From Team Retro)

| # | Action | Proposed By | Effort | Owner | Status |
|---|--------|-------------|--------|-------|--------|
| I1 | Create throwaway prototype during shaping to compiler-verify type-level specs | architect | small | self | noted |
| I2 | Include FFI runtime requirement doc with phantom type designs | web-tech-expert | small | self | noted |
| I3 | Scope both send-side and receive-side in bidirectional API slices | qa | small | process | noted |

Note: Improvement actions I1-I3 are process changes to apply in future cycles, not code tasks.

## Task Notes

### Task 2: Renaming `join` to `joinNs`

**Decision:** Renamed the function from `join` to `joinNs`.

**Rationale:**
- The original name `join` collided with `Prelude.join` (from Control.Bind), requiring users to write `import Prelude hiding (join)` in every module that used PurSocket.Client.
- Evaluated alternatives: `joinNs`, `connectNs`, `namespace`, `enterNs`.
- `joinNs` was chosen because:
  1. It clearly indicates joining a namespace
  2. It avoids the Prelude collision completely
  3. It's concise and follows PureScript naming conventions (abbreviated suffixes are common)
  4. It doesn't create confusion with the existing `connect` function
  5. It's still familiar to Socket.io users (the "join" concept remains clear)

**Files updated:**
- `/home/toby/pursocket/src/PurSocket/Client.purs` - Module export and function definition
- `/home/toby/pursocket/src/PurSocket/Example/Client.purs` - Example code and imports
- `/home/toby/pursocket/test/Test/Main.purs` - Test cases
- `/home/toby/pursocket/test/Test/Integration.purs` - Integration tests and imports
- `/home/toby/pursocket/src/PurSocket/BrowserTest.purs` - Removed `hiding (join)`
- `/home/toby/pursocket/README.md` - All documentation and examples

**Impact:** Users can now write `import Prelude` without qualification. This is a breaking change but improves ergonomics significantly.

### Task 3: Module-level documentation

**Status:** All public PurSocket modules already had comprehensive module-level doc comments.

**Verified modules:**
- `PurSocket.Protocol` - Defines Msg and Call data kinds
- `PurSocket.Framework` - Type-level validation engine
- `PurSocket.Client` - Client-side API
- `PurSocket.Server` - Server-side API
- `PurSocket.Internal` - Internal utilities (marked as non-public)
- `PurSocket.Example.Protocol` - Example protocol
- `PurSocket.Example.Client` - Example client usage
- `PurSocket.Example.Server` - Example server usage
- `PurSocket.BrowserTest` - Browser bundle smoke test

**Verification:** Ran `spago docs` successfully - documentation generated at `generated-docs/html/index.html`.
