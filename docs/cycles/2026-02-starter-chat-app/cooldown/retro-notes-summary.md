# Retro Notes Summary

Difficulties captured by team members during building.

## By Team Member

### PureScript Specialist
- 2026-02-04: purs-backend-es not in PATH - `spago build` silently failed because `purs-backend-es` was only in `node_modules/.bin/`, not on system PATH. Fixed with `npx` wrapper. (~15 min)
- 2026-02-04: ESM output requires explicit main() invocation - Generated ESM modules export but don't auto-invoke. Required `--input-type=module -e` pattern. (~5 min)
- 2026-02-04: PurSocket.Server missing onDisconnect and socketId - Library lacked two fundamental server capabilities needed by any real app. Added to library. (~20 min)

### Web Tech Expert
- 2026-02-04: Socket.io standalone server does not serve static files - `createServerWithPort` creates headless server with no HTTP handler. Required custom FFI for HTTP+Socket.io attachment. (~15 min)
- 2026-02-04: Browser DOM manipulation requires FFI - No built-in DOM bindings in PureScript. Created 6 thin FFI wrappers. (Minimal impact, expected)

### QA
- 2026-02-04: run-negative-tests.sh needed refactoring for subdirectory support - Script only globbed top-level `*.purs`. Tour tests needed subdirectory support and extra source paths. (~15 min)
- 2026-02-04: Compiler output module name mismatch - Negative tests use standalone modules, so error output references different module names than what developers see. Documented as known tradeoff.

### External User
- No difficulties captured during building.

## Common Themes
- **Library API gaps**: Affected 2 team members (PureScript Specialist needed onDisconnect/socketId, Web Tech Expert needed HTTP server attachment)
- **Tooling/PATH assumptions**: Affected 2 team members (purs-backend-es PATH, ESM invocation pattern)
- **Test infrastructure adaptation**: Affected 1 team member (negative test script restructuring)
