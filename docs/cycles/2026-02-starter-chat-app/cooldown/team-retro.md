# Team Retrospective Proposals

Each team member proposes one concrete improvement action based on their experience.

**Cycle:** starter-chat-app
**Date:** 2026-02-04

---

[Sections will be added by team members]

## PureScript Specialist

### Key Difficulty
PurSocket.Server was missing `onDisconnect` and `socketId` -- two capabilities that any real application needs. The v1 library API was shaped entirely against the integration test suite, which only exercised emit/broadcast/call round-trips. When the chat example tried to track connected users and handle disconnections, the library had no surface for it. This forced mid-cycle library modifications (new functions + new FFI) that rippled into the server module, the FFI file, and the delivery timeline.

### Proposed Action
Before the next cycle that adds library API surface, create a **pre-build API checklist** file at `docs/current/building/api-checklist.md` that lists the Socket.io primitives we intend to wrap (connection, disconnection, socket identity, room management, middleware hooks, error events) cross-referenced against the cycle's target application. Any primitive used by the target app must have a corresponding PurSocket function stub *before* slicing begins. Run `spago build` against those stubs as a gate before starting application code. This turns "discovered gaps" into "planned work" and prevents mid-cycle library surgery.

### Effort
small

### Owner
self

## Web Tech Expert

### Key Difficulty
The library's `createServerWithPort` creates a standalone Socket.io server with no HTTP request handler, so it cannot serve static files (HTML, bundled JS). Any real application that presents a browser UI alongside Socket.io needs to create its own `http.Server`, wire up static file serving, and then attach Socket.io to that server. This forced the chat example to drop down to a 40-line JavaScript wrapper script (`examples/chat/start-server.mjs`) that manually constructs the HTTP server, implements a MIME-type lookup, and passes the `Server` instance into PureScript. The library API had no affordance for this standard deployment pattern, even though it is how Socket.io is used in the vast majority of production applications.

### Proposed Action
Add a `PurSocket.Server.attachToHttpServer` function (and corresponding FFI) that accepts a Node `http.Server` and returns a `ServerSocket`. This lets users create their HTTP server however they like (Express, Fastify, bare `http.createServer`, etc.) and attach PurSocket to it without leaving PureScript. The function signature would be approximately `attachToHttpServer :: HttpServer -> ServerOptions -> Effect ServerSocket`. This eliminates the JavaScript wrapper pattern that the chat example currently requires and keeps the server lifecycle under PureScript control. File an issue or backlog item for this before the next cycle starts, with the chat example's `start-server.mjs` cited as the motivating case.

### Effort
small

### Owner
team

## QA

### Key Difficulty
The negative test runner (`test-negative/run-negative-tests.sh`) was hardcoded for a flat directory of `.purs` files compiled against `src/`. When the tour tests arrived in `test-negative/tour/` needing `examples/chat/src/**/*.purs` on the compile path, the script required mid-cycle refactoring to support subdirectories and per-category extra source globs. The refactoring itself was small (~15 min), but it exposed a structural problem: every new test category that depends on different source modules will require another hand-coded `if [ -d ... ]` block in the shell script. This does not scale, and it means adding new negative test categories (e.g., for future examples or library extensions) always involves editing the runner rather than just dropping in test files.

### Proposed Action
Add a `test-negative/<category>/config` file convention. Each subdirectory under `test-negative/` that contains a `config` file declares its extra source globs (one per line). The runner script discovers all `config` files, reads the extra sources from them, and runs every `.purs` file in that directory against `src/**/*.purs` plus the declared extras. The top-level `test-negative/*.purs` files (no config needed) continue to work as they do today. This makes adding a new negative test category a two-step process: (1) create the subdirectory with `.purs` files, (2) add a `config` file listing extra source globs -- no shell script edits required. Concretely:

```
# test-negative/tour/config
examples/chat/src/**/*.purs
```

The runner becomes a single loop over discovered directories instead of per-category `if` blocks. This also improves CI reliability because new test categories cannot be silently skipped due to a missing `if` clause in the script.

### Effort
small

### Owner
self

## Product Manager

### Key Difficulty
The chat example achieves its goal of making PurSocket evaluable -- `git clone && npm install && npm run chat` works, and the guided tour demonstrates compile-time safety convincingly. However, the example app cannot stand on its own as an adoption vehicle because evaluators who want to go from "I tried the demo" to "I am using PurSocket in my own project" face a significant gap. The README's installation section tells them to add a git dependency to `spago.yaml`, but it says nothing about the toolchain prerequisites (`purs-backend-es`, esbuild for browser bundling, the `npx` wrapper workaround) that the team itself hit during the build. Three separate retro entries (purs-backend-es PATH, ESM invocation pattern, static file serving) are all things that a first-time evaluator would hit in sequence. The demo works because the repo has `package.json` scripts that paper over these issues, but the moment someone starts their own project they will encounter every one of them with no guidance. The onboarding funnel has a working top (clone and run) but a missing middle (start your own project).

### Proposed Action
Before the next cycle ships, create a `docs/GETTING_STARTED.md` (linked from README under a new "Start Your Own Project" section) that walks an evaluator from zero to a compiling two-file PurSocket project (one protocol, one client or server stub) in their own repository. The guide must cover: (1) required npm packages and their versions, (2) `spago.yaml` configuration with the git dependency, (3) the `purs-backend-es` requirement and the `npx` workaround, (4) a minimal esbuild command for browser bundling, and (5) how to run the server (the `start-server.mjs` pattern or `createServerWithPort` for headless use). Each step should be a copy-pasteable command. Timebox this to 2 hours; if it takes longer, the library itself has too much setup friction and that becomes the next cycle's work.

### Effort
small

### Owner
team

## Architect

### Key Difficulty
The library's public API was designed against the protocol type-level specification alone -- what events can be sent and received, in which direction, with which payloads. That type-level machinery held up perfectly: IsValidMsg, IsValidCall, and the NamespaceHandle phantom types all compiled away cleanly, the directional constraints caught real errors in the guided tour experiments, and the module boundaries (Chat.* workspace member, four-layer architecture) were not violated. The architectural problem was that Socket.io has an entire category of *system events* (`disconnect`, `connect_error`, `reconnect`, `reconnect_attempt`) and *lifecycle primitives* (`socket.id`, rooms, middleware) that exist outside the protocol event model. Because `disconnect` is a system event and not a protocol event, our type-level validation framework correctly had nothing to say about it -- but that also meant there was no `onDisconnect` function at all. The gap was invisible until the chat server needed to broadcast `userLeft` on disconnection (Slice 02, ~20 min unplanned work). The same class of omission applies to every other Socket.io system event and lifecycle method we have not yet wrapped. A second instance of the same pattern surfaced in Slice 03: `createServerWithPort` had no HTTP attachment point, forcing a JavaScript wrapper script for static file serving. Both gaps share a root cause -- the API surface was scoped to protocol events and missed the non-protocol primitives that real applications depend on.

### Proposed Action
Before the next cycle, audit the Socket.io server and client JavaScript APIs and enumerate every system event and lifecycle method (disconnect, connect_error, reconnect, reconnect_attempt, middleware, rooms, fetchSockets, attachToHttpServer, etc.). For each one, record an explicit keep/defer/never decision in a new file at `docs/api-surface-audit.md`. Any method marked "keep" that is not yet exposed in PurSocket.Server or PurSocket.Client gets a stub added to the library before slicing begins on the next application cycle. This converts mid-build discovery of missing primitives into planned pre-cycle work and prevents unplanned modifications to the library's public API surface while application code is being built.

### Effort
small

### Owner
self

## External User

### Key Difficulty
(Reconstructed from shipped artifacts -- no difficulties were captured during building because this role did not record notes in `retro-notes/external-user.md`.)

The README Quick Start shows three PureScript snippets -- protocol, client, and server -- but stops there. A developer who follows those snippets and runs `spago build` will have compiled PureScript modules and no way to actually run anything. The critical glue that makes the chat example work is invisible to someone reading only the README:

1. **Server bootstrap requires a JavaScript wrapper.** PurSocket's `createServerWithPort` creates a headless Socket.io server with no HTTP handler. The chat example works because of a 40-line `start-server.mjs` that manually creates an HTTP server, wires up static file serving, attaches Socket.io, and delegates to PureScript. The README never mentions that this wrapper is necessary. A developer who writes the Quick Start server snippet, compiles it, and runs `node output-es/MyApp.Server/index.js` gets a WebSocket-only process that cannot serve any client page.

2. **Client bundling requires an esbuild step** that is only visible inside `package.json`'s `chat:build` script. The README does not mention that browser clients need a bundler to produce a loadable script from `purs-backend-es` ESM output.

3. **The PureScript Effect calling convention** (curried `function(x) { return function() { ... } }`) appears throughout the HTML file but is never explained. A JavaScript developer consuming the bundled client module would not understand why every function returns a thunk requiring a trailing `()` call.

The net effect: the in-repo `npm run chat` path works in three commands as advertised, but the "use PurSocket in my own project" path has undocumented steps that would block a developer within minutes of starting. The Product Manager's proposal for a `GETTING_STARTED.md` addresses the same gap from a different angle; this proposal focuses on keeping the information in the README itself, where developers actually look first.

### Proposed Action
Add a **"New Project Setup"** section to the README (between the current "Installation" and "Quick Start" sections) that walks through the concrete steps to go from an empty directory to a running hello-world. Specifically:

1. `spago init` and `spago.yaml` configuration with the git dependency (already partially documented).
2. `npm install socket.io socket.io-client esbuild` -- peer dependencies plus bundler, stated explicitly.
3. A minimal 8-10 line server entry-point `.mjs` file showing the `http.createServer` + `new Server(httpServer)` + `startMyApp(io)()` + `httpServer.listen()` pattern, with a one-line comment on each step.
4. The esbuild command to bundle the client: `npx esbuild output-es/MyApp.Client/index.js --bundle --format=esm --platform=browser --outfile=static/client.bundle.js`.
5. A short paragraph explaining the PureScript Effect calling convention (`fn(arg1)(arg2)()`) so that the JavaScript-side HTML integration is not a mystery.

Every step must be copy-pasteable. A developer should be able to follow this section top to bottom in a fresh directory and have a running page in under five minutes without needing to read the chat example source code.

### Effort
small

### Owner
self
