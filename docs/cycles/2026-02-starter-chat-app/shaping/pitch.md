---
title: "Clone-and-Run Starter Chat App"
status: ready
drafter: "@product-manager"
appetite: "2 weeks"
created: "2026-02-04"
open_questions: 0
contributors:
  - "@product-manager"
  - "@external-user"
  - "@web-tech-expert"
  - "@architect"
  - "@purescript-specialist"
---

# Clone-and-Run Starter Chat App

## Problem

PurSocket has working client and server APIs, passing integration tests, and custom compile-time error messages -- but no developer can experience any of this without reverse-engineering the test suite. The `PurSocket.Example.Client` and `PurSocket.Example.Server` modules exist inside the library's own `src/` tree, are not self-contained, and cannot be run independently. There is no standalone project a developer can clone, run, and see messages flowing between a real server and a real client in a browser.

This is a critical gap because PurSocket's most compelling selling point -- "break something and the compiler tells you exactly what's wrong" -- is invisible to anyone who has not already committed to a full PureScript tooling setup. The typical library evaluation flow is: `git clone`, `npm install`, `npm start`, see it work, then break something to see what happens. PurSocket currently fails at step three.

The brainstorm identified this gap from two independent perspectives: the external user wants a copy-paste-and-run template ("the difference between 'the library works' and 'I can use the library'"), and the product manager wants a guided type error tour ("the most convincing onboarding moment is when the developer intentionally breaks something"). These are two halves of the same experience. A chat app that works gives the developer confidence; a guided tour that shows deliberate failures gives them understanding.

> **Q (@product-manager -> @external-user):** When you evaluate a new PureScript library, what is the maximum number of terminal commands you are willing to run before you see something working? Is "clone, npm install, npm start" (3 commands) the right threshold, or do you tolerate a separate `spago build` step?
>
> **A (@external-user):** Three commands is the right target, but I would frame it differently: three *conceptual* steps, not literally three invocations. PureScript developers already expect that a PureScript project involves both npm and spago -- that is the ecosystem we signed up for. What kills my motivation is not a fourth command; it is a fourth command that *fails*. So the real threshold is: zero unexpected errors between clone and "something running in my browser."
>
> Concretely, `git clone`, then a single `make setup` that runs both `npm install` and `spago install` behind the scenes, then `make run` that builds and starts the server -- that is fine. Two make targets, three total commands counting the clone. I would *not* tolerate having to manually run `spago build`, then separately run an esbuild step, then `node server.js`, then open a browser. That is four conceptual steps, each of which can fail with an error message that does not obviously point to the next thing to try.
>
> The existing example code (`PurSocket.Example.Client`) actually illustrates the problem well: it exports `exampleClient` but there is no entry point I can just run. I have to figure out how to wire it into a `Main` module, bundle it, serve it. Each of those is a small step, but together they add up to "I will come back to this later" -- which means never.
>
> One more thing: the `make setup` target needs to be *idempotent*. When I come back to the project a week later and something has changed, I want to run the same command and have it fix whatever drifted. If `make setup` fails on the second run because something is already installed, I lose trust in the project's automation.
>
> RESOLVED

> **Q (@external-user -> @product-manager):** The pitch says the README will list "exact version ranges" for prerequisites. Will the Makefile validate those prerequisites (e.g., check Node.js version, check that `spago` is on PATH) and give a clear error before attempting a build that will fail cryptically?
>
> **A (@user):** No Makefile. We will use `npm run` scripts (`package.json` scripts section) instead. NPM handles packaging and versions via `engines` field and dependency resolution. The quick start becomes `npm install && npm run build && npm start`.
>
> ✓ RESOLVED

## Appetite

2 weeks -- Small batch. This is packaging existing functionality, not building new features. The protocol types, client API, server API, FFI, and custom error messages all exist and are tested. The work is: (1) create a self-contained example project with its own build config, (2) write a minimal chat server and browser client using the existing APIs, (3) write the guided tour document, and (4) wire it into CI.

## Solution

### What gets built

A single `examples/chat/` directory inside the PurSocket repository containing a complete, self-contained chat application with a guided type safety tour. The directory has its own `spago.yaml` (as a workspace member or standalone project referencing PurSocket as a local dependency), its own `package.json` for JS dependencies, and its own README with exact copy-paste commands.

### Directory structure

```
examples/chat/
  spago.yaml              -- references PurSocket as local dependency
  package.json            -- socket.io, socket.io-client, esbuild
  src/
    ChatProtocol.purs     -- the chat app's own AppProtocol
    Server/
      Main.purs           -- Node.js server entry point
    Client/
      Main.purs           -- browser client entry point
  static/
    index.html            -- minimal chat UI (plain HTML + JS, no framework)
  GUIDED_TOUR.md          -- 3 deliberate type error experiments
```

> **Q (@product-manager -> @architect):** Should `examples/chat/` be a spago workspace member of the root `spago.yaml`, or a fully standalone project with a relative `file:` path to PurSocket? The workspace approach is cleaner for CI but may confuse developers who clone the example directory into their own project. The standalone approach means duplicating some config but makes the example more portable.
>
> **A (@architect):** Use a spago workspace member, not a standalone project. The root `spago.yaml` already declares a `workspace:` block with a `packageSet` registry pin (`72.0.1`) and a `purs-backend-es` backend. Adding `examples/chat/` as a workspace member means listing it under `workspace.extraPackages` with a `path:` key and giving the example its own `spago.yaml` containing only a `package:` block (name, dependencies, src globs). It inherits the root workspace's package set and backend, keeping the registry pin in exactly one place.
>
> CI is the primary consumer. A workspace member compiles against the same dependency versions and backend as the library itself -- the correct behavior for drift prevention. A standalone project with its own `workspace.packageSet` can silently diverge if someone bumps the root pin but forgets the example.
>
> The portability concern does not apply. The pitch explicitly says "No separate npm package" and "the example lives inside the PurSocket repo." A developer starting their own project should follow a "Getting Started" section in the main README that shows spago config to depend on PurSocket from the registry -- not copy-pasting a directory out of a monorepo.
>
> Concrete recommendation: add the chat example under `workspace.extraPackages` in the root `spago.yaml` as `chat-example: { path: "examples/chat" }`, give `examples/chat/spago.yaml` a `package:` block with `name: chat-example` and dependencies `[pursocket, prelude, effect, aff, console]`, and verify that `spago build -p chat-example` compiles from the repo root.
>
> ✓ RESOLVED

> **Q (@architect -> @product-manager):** The workspace member approach means `spago build` at the repo root will compile all workspace members by default, including the chat example. This adds compile time to every library development cycle. Should the CI config use `spago build -p chat-example` as a separate step, or is building the example on every `spago build` acceptable as an implicit drift check?
>
> **A (@user):** Building every time is desired to prevent drift. Full workspace build on every `spago build` is fine.
>
> ✓ RESOLVED

> **Q (@user -> @purescript-specialist, @external-user):** How will a user get started if the chat example is a workspace member? They clone the whole PurSocket repo just to try the example?
>
> **A (@purescript-specialist):** Yes, they clone the whole repo, and this is the correct approach. It is standard practice for PureScript libraries and most open-source projects with embedded examples. The key is making the experience seamless *within* the clone, not avoiding the clone.
>
> **Why cloning the repo is not a problem.** The target audience is a PureScript developer evaluating PurSocket. They expect to browse the library source, not just the example in isolation. Cloning gives them the protocol types, the type engine, the test suite, and the example all in one checkout. The alternative -- extracting the example into a separate repository or npm package -- is explicitly a no-go in this pitch and would create the exact drift problem the workspace member approach is designed to prevent.
>
> **The quick-start flow works from the repo root.** Since the chat example is a spago workspace member, all spago commands must run from the repo root (where the `workspace:` block in `spago.yaml` lives). The root `package.json` already contains every JS dependency the chat example needs (`socket.io`, `socket.io-client`, `esbuild`). The chat example does not need its own `package.json` for JS dependencies. Add npm scripts to the root `package.json` for the chat example:
>
> ```json
> "scripts": {
>   "chat:build": "spago build -p chat-example && npx esbuild output-es/Client.Main/index.js --bundle --format=esm --platform=browser --outfile=examples/chat/static/client.bundle.js",
>   "chat:start": "node output-es/Server.Main/index.js",
>   "chat": "npm run chat:build && npm run chat:start"
> }
> ```
>
> The README quick-start becomes:
>
> ```
> git clone https://github.com/toby/pursocket.git
> cd pursocket
> npm install
> npm run chat
> ```
>
> That is three conceptual steps (clone, install, run), matching the threshold established in Q1. The `npm run chat` script handles the spago build, esbuild bundle, and server start in sequence. For the guided tour iteration loop, the developer runs `npm run chat:build` to rebuild after editing source, then `npm run chat:start` to restart the server.
>
> **Why not a separate `package.json` in `examples/chat/`.** The pitch's directory structure shows a `package.json` inside `examples/chat/`, but this creates a real problem for a workspace member. If `examples/chat/package.json` has its own npm scripts, those scripts need to invoke `spago build -p chat-example` from the repo root (because the `workspace:` block lives in the root `spago.yaml`). The scripts would require `cd ../..` or `--prefix` hacks, which are fragile and confusing. Worse, running `npm install` in `examples/chat/` would create a second `node_modules/` with duplicate copies of `socket.io-client` and `esbuild`. Keeping all orchestration in the root `package.json` is simpler, avoids duplication, and is consistent with the user's decision to use npm scripts instead of a Makefile. The chat example needs only a minimal `examples/chat/spago.yaml` for the spago workspace member declaration (a `package:` block with name and dependencies), not its own `package.json`.
>
> **Concrete impacts on the pitch.** Three sections need updating if this answer is accepted:
>
> 1. **Directory structure** (line ~57): Remove `package.json` from the `examples/chat/` listing. Add a note that npm scripts live in the root `package.json`.
> 2. **The README section** (line ~228): Change the quick-start from `cd examples/chat && npm install && npm run build && npm start` to the root-level commands shown above.
> 3. **CI integration** (line ~242): Change `cd examples/chat && npm install && npm run build` to `npm run chat:build`, since all orchestration runs from the root. No separate `npm install` step is needed -- the root install covers everything.
>
> **For developers starting their own project.** The main PurSocket README already has an "Installation" section showing how to add PurSocket as a git dependency in a fresh project's `spago.yaml`. The chat example is for *evaluating* PurSocket; the Installation section is for *adopting* it. These are separate flows and should stay separate.
>
> ✓ RESOLVED

> **Q (@purescript-specialist -> @architect):** The chat example's module names `Client.Main` and `Server.Main` are very generic. In a spago workspace, all packages share a single `output-es/` directory. If a future workspace member (e.g., a second example or a benchmark) also defines `Client.Main` or `Server.Main`, the modules will collide. Should the chat example use namespaced module names like `Chat.Client.Main` and `Chat.Server.Main`?
>
> **A (@architect):** Yes, use namespaced module names: `Chat.Client.Main`, `Chat.Server.Main`, and `Chat.Protocol`. This is the correct approach for three reasons.
>
> **The collision risk is real, not theoretical.** The project already demonstrates the namespacing pattern. The existing library examples use fully qualified module names under the `PurSocket.Example` namespace: `PurSocket.Example.Client`, `PurSocket.Example.Server`, `PurSocket.Example.Protocol`. These modules live in `src/PurSocket/Example/` inside the library package and compile to `output-es/PurSocket.Example.Client/`, `output-es/PurSocket.Example.Server/`, etc. If the chat example uses bare `Client.Main` and `Server.Main`, it breaks this established convention. Worse, using generic top-level module names in a workspace that already has a `PurSocket.*` namespace hierarchy is inviting a collision that is trivial to prevent.
>
> **Workspace growth is plausible within this project's lifetime.** The brainstorm identified rooms as a future medium-sized idea, which could produce a `rooms-example` workspace member. A benchmark suite is another likely addition. If both a chat example and a rooms example define `Server.Main`, the modules silently shadow each other in `output-es/` -- spago does not error on cross-package module name collisions in a workspace; it just overwrites the output directory. The fix at that point requires renaming modules, updating npm scripts, updating CI, and updating documentation. Getting the namespace right on day one costs nothing: the directory structure under `examples/chat/src/` becomes `Chat/Client/Main.purs`, `Chat/Server/Main.purs`, and `Chat/Protocol.purs`.
>
> **The npm script changes are trivial.** The Q12 answer's npm scripts become:
>
> ```json
> "scripts": {
>   "chat:build": "spago build -p chat-example && npx esbuild output-es/Chat.Client.Main/index.js --bundle --format=esm --platform=browser --outfile=examples/chat/static/client.bundle.js",
>   "chat:start": "node output-es/Chat.Server.Main/index.js",
>   "chat": "npm run chat:build && npm run chat:start"
> }
> ```
>
> The paths are longer but equally readable. The esbuild entry point and the `node` invocation each change by one path segment. No other configuration is affected -- the `spago.yaml` workspace member still uses `name: chat-example` with a `src` glob pointing at `examples/chat/src/**/*.purs`, and spago does not care about the module name hierarchy as long as the source files are within the declared glob.
>
> **The protocol module should also be namespaced.** The pitch currently shows `module ChatProtocol where` as a bare top-level module. This should become `module Chat.Protocol where` for consistency. A bare `ChatProtocol` is less likely to collide than `Client.Main`, but following the same `Chat.*` prefix keeps all chat example modules in a single namespace subtree, making the `output-es/` directory self-documenting.
>
> **Concrete directory structure update:**
>
> ```
> examples/chat/
>   spago.yaml
>   src/
>     Chat/
>       Protocol.purs       -- module Chat.Protocol
>       Client/
>         Main.purs          -- module Chat.Client.Main
>       Server/
>         Main.purs          -- module Chat.Server.Main
>   static/
>     index.html
>   GUIDED_TOUR.md
> ```
>
> **Impacts on other pitch sections.** The guided tour experiments reference `emit @ChatProtocol`; this type alias name does not change (only the module it lives in changes from `ChatProtocol` to `Chat.Protocol`). The negative test files under `test-negative/tour/` will `import Chat.Protocol (ChatProtocol)` instead of `import ChatProtocol (ChatProtocol)`. The CI build script and README quick-start commands use npm scripts that already abstract away the paths, so only the npm script definitions themselves (shown above) need updating.
>
> ✓ RESOLVED

### The chat protocol

The protocol should be richer than the existing lobby/game example to demonstrate a realistic chat application, while staying small enough to read in full in under a minute. It uses a single `chat` namespace with multiple events covering both `Msg` and `Call` patterns:

```purescript
module ChatProtocol where

import PurSocket.Protocol (Msg, Call)

type ChatProtocol =
  ( chat ::
      ( c2s ::
          ( sendMessage :: Msg { text :: String }
          , setNickname :: Call { nickname :: String } { ok :: Boolean, reason :: String }
          )
      , s2c ::
          ( newMessage  :: Msg { sender :: String, text :: String, timestamp :: String }
          , userJoined  :: Msg { nickname :: String }
          , userLeft    :: Msg { nickname :: String }
          , activeUsers :: Msg { users :: Array String }
          )
      )
  )
```

This protocol demonstrates:
- **Multiple c2s events** -- `sendMessage` (fire-and-forget) and `setNickname` (request/response with validation)
- **Multiple s2c events** -- `newMessage`, `userJoined`, `userLeft`, `activeUsers` show realistic server-push patterns
- **The `Call` pattern with meaningful response** -- `setNickname` can fail (nickname taken), so the response includes both `ok` and `reason`, not just a boolean
- **`Array` in a payload** -- `activeUsers` shows that payloads are not limited to flat records

> **Q (@product-manager -> @external-user):** Does the `ChatProtocol` design above cover enough patterns to be convincing, or should it include a second namespace?
>
> **A (@external-user):** A single namespace is the right call for a starter example. Adding a second namespace would dilute the focus. The existing `AppProtocol` in `PurSocket.Example.Protocol` already demonstrates multi-namespace usage (`lobby` + `game`), and the integration tests in `test/Test/Integration.purs` exercise both namespaces with `joinNs @"lobby"` and `joinNs @"game"`. Anyone who wants to see how namespaces work can look at those existing files -- the starter chat app does not need to repeat that lesson.
>
> What the `ChatProtocol` *does* need to demonstrate is the stuff that matters for a real application, and it covers the important patterns well: fire-and-forget messages (`sendMessage`), request/response with validation logic (`setNickname` returning `{ ok, reason }`), multiple distinct server-push events for different concerns (`newMessage` vs. `userJoined` vs. `activeUsers`), and non-trivial payload types (`Array String`). That is a more useful set of patterns than a second namespace would be.
>
> One thing I would consider adding, though not necessarily in this cycle: an event with an `Optional` or `Maybe` field in the payload. In my experience with Socket.io, the most common source of runtime bugs is optional fields that are sometimes present and sometimes `undefined`. Showing how PurSocket handles that (or does not handle it yet) would be more valuable than a second namespace. But that might be scope creep for a one-week cycle.
>
> RESOLVED

> **Q (@external-user -> @product-manager):** The `ChatProtocol` has `setNickname` as a `Call` that returns `{ ok :: Boolean, reason :: String }`. In practice, `reason` is meaningless when `ok` is `true`. Has there been any consideration of using a sum type (e.g., `Either String String`) instead of this "boolean + reason" pattern? If PurSocket payloads must be flat JSON-serializable records, that constraint should be documented explicitly so users do not try to use ADTs and get confused.
>
> **A (@user):** Out of scope for this pitch. Added to backlog for @purescript-specialist to investigate ADT payload support and document serialization constraints.
>
> ✓ RESOLVED

### The server

`Server/Main.purs` creates a Socket.io server on port 3000 and handles:
- `onConnection` for the `chat` namespace
- `onCallEvent` for `setNickname` -- validates nickname uniqueness, responds with success/failure
- `onEvent` for `sendMessage` -- broadcasts `newMessage` to all clients with sender and timestamp
- Broadcasts `userJoined` and `activeUsers` on connection, `userLeft` on disconnect

The server should be minimal -- under 80 lines of PureScript -- and heavily commented to explain each PurSocket API call.

### The client

`Client/Main.purs` connects to the server, calls `setNickname`, then listens for incoming messages and renders them. The browser UI in `index.html` is plain HTML with a message list, text input, and send button. No framework, no build tool for the HTML -- just a `<script>` tag loading the bundled PureScript output.

> **Q (@product-manager -> @web-tech-expert):** The client needs to be bundled for the browser. Should the example use esbuild (already a devDependency in the root project) with a one-liner in the Makefile, or should it use a simpler approach like a pre-built bundle checked into the repo? The esbuild approach requires the developer to have Node.js; the pre-built approach means the bundle could drift from the source.
>
> **A (@web-tech-expert):** Use esbuild via the Makefile. Do not check in a pre-built bundle. The developer already needs Node.js to run the Socket.io server (`Server/Main.purs` runs on Node), so requiring Node for the bundling step adds zero additional prerequisites. The existing root project already has the pattern to copy: `scripts/bundle-browser.mjs` calls `esbuild.buildSync()` with `platform: "browser"` and `format: "esm"`. The chat example's Makefile `build` target should run the equivalent one-liner:
>
> `npx esbuild output-es/Client.Main/index.js --bundle --format=esm --platform=browser --outfile=static/client.bundle.js`
>
> This keeps the entire build visible in the Makefile without indirection. A pre-built bundle is the wrong tradeoff because the guided tour explicitly asks developers to edit PureScript source and rebuild. If the bundle is pre-built, either the tour must include a manual rebuild step the developer might skip, or the bundle drifts silently. The whole point is that the developer modifies code and sees the result -- a stale artifact undermines that. The esbuild step should include `--minify` for a realistic production-like bundle size.
>
> ✓ RESOLVED

> **Q (@product-manager -> @web-tech-expert):** This answer references "Makefile" and "Makefile `build` target" in several places, but Q7 resolved to "No Makefile, use npm scripts." The esbuild command and rationale are still correct -- the only thing that needs updating is the delivery mechanism: this should be an `npm run build` script in `examples/chat/package.json` rather than a Makefile target. Can you confirm the esbuild invocation works the same way when wired as a `package.json` script (`"build": "spago build -p chat-example && npx esbuild ..."`)? This is a wording update, not a design change.
>
> **A (@web-tech-expert):** Yes, the esbuild invocation works identically whether it appears in a Makefile target or a `package.json` script. The command `npx esbuild output-es/Client.Main/index.js --bundle --format=esm --platform=browser --outfile=examples/chat/static/client.bundle.js` is a plain shell invocation either way -- npm scripts execute via `sh -c` on POSIX and `cmd /c` on Windows, so any command that works in a Makefile recipe works in a `"scripts"` entry verbatim. No escaping changes, no path resolution differences.
>
> Per Q12's resolution, the scripts should live in the **root** `package.json`, not in a separate `examples/chat/package.json`. The purescript-specialist's answer explains why: the chat example is a spago workspace member, so `spago build -p chat-example` must run from the repo root where the `workspace:` block lives. A nested `package.json` would require fragile `cd ../..` hacks. The root `package.json` already has `socket.io`, `socket.io-client`, and `esbuild` as dependencies, so no duplication is needed. The recommended scripts are:
>
> ```json
> "chat:build": "spago build -p chat-example && npx esbuild output-es/Client.Main/index.js --bundle --format=esm --platform=browser --outfile=examples/chat/static/client.bundle.js",
> "chat:start": "node output-es/Server.Main/index.js",
> "chat": "npm run chat:build && npm run chat:start"
> ```
>
> From a transport-level perspective, the `--format=esm` and `--platform=browser` flags are correct for a Socket.io client bundle. The `socket.io-client` package exports ESM, and esbuild will tree-shake the polling transport code if only WebSocket is used (though Socket.io defaults to polling-first upgrade, so the full client is appropriate here). Adding `--minify` as mentioned in the Q3 answer is still recommended for realistic bundle size, though optional for a development-focused example.
>
> ✓ RESOLVED

> **Q (@web-tech-expert -> @architect):** The `npm run build` target will need to run `spago build` then `esbuild` in sequence. If the example is a spago workspace member, `spago build` may trigger a rebuild of the root PurSocket library as well. Should the npm script explicitly build only the example's package (e.g., `spago build -p chat-example`) to keep build times fast for the guided tour iteration loop, or is a full workspace build acceptable?
>
> **A (@user):** Use `spago build -p chat-example` in the npm build script for fast iteration. Full workspace build happens at the root level for drift prevention (see Q9).
>
> ✓ RESOLVED

### The guided tour

`GUIDED_TOUR.md` walks the developer through three deliberate type errors, each demonstrating a different layer of PurSocket's type safety. For each experiment, the document provides:

1. **The change to make** -- exact line to modify in `Client/Main.purs` or `Server/Main.purs`
2. **The expected compiler output** -- the full custom error message, verbatim
3. **What the error means** -- a one-paragraph explanation of which type-level check caught it and why

The three experiments are:

**Experiment 1: Wrong event name (typo).** Change `emit @ChatProtocol @"chat" @"sendMessage"` to `emit @ChatProtocol @"chat" @"sendMsg"`. Expected error:

```
PurSocket: invalid Msg event.
  Namespace: "chat"
  Event:     "sendMsg"
  Direction: "c2s"
  Check that the event name exists in this namespace/direction and is tagged as Msg.
```

**Experiment 2: Wrong direction (client sending a server event).** Change client code to `emit @ChatProtocol @"chat" @"newMessage"`. Expected error: same structure but event `"newMessage"` is only in `s2c`, not `c2s`.

**Experiment 3: Wrong payload type.** Change `{ text: "Hello" }` to `{ message: "Hello" }` (wrong field name). This one produces a standard PureScript `TypesDoNotUnify` error rather than a custom PurSocket error, because the payload type is inferred from the protocol via the functional dependency. The tour should explain this honestly -- PurSocket catches the wrong event/namespace/direction with custom errors, but payload mismatches fall through to the compiler's standard unification error.

> **Q (@product-manager -> @purescript-specialist):** Experiment 3 (wrong payload) will produce a raw `TypesDoNotUnify` error rather than a custom PurSocket message. The brainstorm noted this gap. Is it acceptable to include this in the guided tour with an honest explanation, or does it undermine the "great error messages" narrative? Should we timebox an attempt at a custom payload error within this cycle?
>
> **A (@purescript-specialist):** Including the raw `TypesDoNotUnify` error is not only acceptable -- it is the right pedagogical move. Do not timebox custom payload errors in this cycle.
>
> **Why custom payload errors are structurally hard.** The `IsValidMsg` class has the functional dependency `protocol ns event dir -> payload`, which means once `LookupMsgEvent` successfully finds the event, the compiler *determines* the payload type. The lookup succeeds -- our custom error machinery is only invoked when the lookup *fails*. The `TypesDoNotUnify` error occurs *after* our type class resolution completes, when the compiler tries to unify the determined payload type `{ text :: String }` with the actual argument `{ message :: String }`. This is outside instance chains entirely. To intercept it would require a separate `PayloadMatches` type class that walks `RowList` representations and produces custom `Fail` messages -- minimum 2-3 days of type-level engineering with real risk of compiler edge cases. It does not belong in a 1-week packaging cycle.
>
> **Why it does not undermine the narrative.** The tour already demonstrates two experiments with custom errors. Experiment 3 shows a *different kind* of safety -- the compiler still catches the bug at compile time, just using its own error format. The story becomes: "PurSocket gives custom errors for protocol-level mistakes. For payload-level mistakes, the compiler's own type checker catches them -- because the payload type is fully determined by the protocol." This is honest, technically precise, and actually demonstrates the functional dependency mechanism.
>
> **Framing recommendation:** Present Experiment 3 not as "here is where our errors fall short" but as "here is where PureScript's own type checker takes over." Show the expected output, point out that it mentions `{ text :: String }` (expected) and `{ message :: String }` (actual), and note that future versions may wrap this in a more descriptive message.
>
> ✓ RESOLVED

> **Q (@purescript-specialist -> @product-manager):** The `TypesDoNotUnify` error from Experiment 3 will include internal type class names like `LookupMsgEvent` and `IsValidMsg` in the constraint trace, which may confuse developers new to PureScript. Should the guided tour include a brief "how to read PureScript compiler errors" sidebar (3-4 sentences explaining the constraint stack), or would that be scope creep?
>
> **A (@product-manager):** Yes, include the sidebar. This is not scope creep -- it is essential to the guided tour's job.
>
> The guided tour is the single most important onboarding artifact PurSocket has. Its purpose is to take a developer from "this looks interesting" to "I understand how this protects me." If Experiment 3 produces an error full of `LookupMsgEvent`, `IsValidMsg`, and `RowToList` constraint traces, and the tour does not explain what those names mean, the developer's takeaway is "I do not understand this compiler output" -- which is the opposite of confidence. The whole point of the tour is that nothing in it should feel unexplained.
>
> The sidebar should be 3-4 sentences placed immediately before Experiment 3's expected output, something like: "PureScript compiler errors show a constraint stack -- the chain of type classes the compiler walked through before it found the mismatch. You will see names like `IsValidMsg` and `LookupMsgEvent` in this trace. These are PurSocket's internal validation steps: `IsValidMsg` is the top-level check, `LookupMsgEvent` is the step that resolved your event's payload type. The important part is at the bottom: the `TypesDoNotUnify` line showing the expected type vs. the type you provided."
>
> This costs perhaps 15 minutes to write during implementation. Within a 2-week appetite, that is negligible. The risk of *not* including it is real: a developer who cannot parse the error output of Experiment 3 will not trust PurSocket's type safety story, because they cannot tell whether the compiler is helping them or yelling at them. The sidebar turns an opaque wall of type class names into a readable diagnostic, which is exactly the "aha moment" the tour exists to create.
>
> One implementation note: the sidebar should use the actual compiler output from `ChatProtocol`, not a generic example. Run the wrong-payload case during development, capture the real output, and annotate it inline. Real output builds more trust than a paraphrase.
>
> ✓ RESOLVED

### The README

`examples/chat/README.md` contains:

1. **Prerequisites** -- PureScript compiler, Spago, Node.js (with exact version ranges)
2. **Quick start** -- `cd examples/chat && npm install && npm run build && npm start`
3. **What you should see** -- screenshot or ASCII description of the running chat
4. **Next steps** -- pointer to `GUIDED_TOUR.md` and the main PurSocket README
5. **Troubleshooting** -- common failures (wrong Node version, port 3000 in use)

### CI integration

The example must be testable in CI to prevent drift. Two CI checks:

1. **Build check** -- `cd examples/chat && npm install && npm run build` succeeds. This verifies the example compiles against the current PurSocket source.
2. **Guided tour regression** -- A script (similar to `test-negative/run-negative-tests.sh`) that applies each of the three guided tour mutations, attempts to compile, and verifies the compilation fails. This ensures the custom error messages remain correct as the type engine evolves.

> **Q (@product-manager -> @architect):** The guided tour regression test needs to apply source mutations, compile, check for failure, then restore the original source. Should this be a shell script that uses `sed` to apply/revert patches, or should we use separate `.purs` files (like the existing `test-negative/` approach) that import from the chat example's protocol? The separate-file approach is cleaner but may not perfectly mirror the guided tour's "edit this line" instructions.
>
> **A (@architect):** Use separate `.purs` files, following the existing `test-negative/` pattern. The project already has `test-negative/WrongEvent.purs`, `test-negative/WrongNamespace.purs`, etc., each a standalone module that imports from the protocol and contains exactly one type error. `run-negative-tests.sh` compiles each one and asserts failure. This is proven infrastructure.
>
> Create `test-negative/tour/Tour1WrongEvent.purs`, `Tour2WrongDirection.purs`, `Tour3WrongPayload.purs` that import from `ChatProtocol` and reproduce each guided tour experiment. The shell script compiles each and verifies failure. This avoids sed fragility (line numbers shift), avoids source file mutation/restoration risk, and is idempotent. The guided tour document says "edit this line" for the human experience; the regression test verifies the same type error fires without needing to actually mutate source. The slight abstraction gap (separate file vs. inline edit) is acceptable because what matters is that the *compiler error* remains correct, not that the *exact edit* is reproduced.
>
> ✓ RESOLVED

## Rabbit Holes

**Do not build a chat UI framework.** The `index.html` should be bare-minimum DOM manipulation -- `document.getElementById`, `innerHTML`, `addEventListener`. No React, no Halogen, no CSS framework. The point is PurSocket, not frontend architecture. If the HTML takes more than 50 lines, it is too complex.

**Do not implement rooms.** The chat app uses a single namespace for all users. PurSocket v1 does not have room support (the brainstorm identified this as a separate medium-sized idea). Do not let the chat app's requirements pull in room implementation.

**Do not solve the payload error message gap.** The guided tour should document the raw `TypesDoNotUnify` error honestly. Improving payload error messages is a separate cycle's work. Spending time on custom payload errors risks consuming the entire week.

**Do not create a separate npm package.** The example lives inside the PurSocket repo. It is not published to npm or the PureScript registry. It is a development/onboarding artifact, not a distributable.

**Timebox the spago workspace question.** If making the example a workspace member takes more than 2 hours of configuration debugging, fall back to a standalone project with a relative path dependency. The developer experience of "it builds" matters more than the elegance of the build configuration.

## No-Gos

- **No TypeScript version.** PurSocket is a PureScript library. A TypeScript companion example is out of scope.
- **No deployment guide.** The example runs on localhost only. No Docker, no cloud deployment, no production configuration.
- **No persistent storage.** Messages exist only in memory. No database, no message history beyond the current session.
- **No authentication.** The chat app does not implement login, JWT, or session management. `setNickname` is the only identity mechanism.
- **No WebSocket transport configuration.** The example uses Socket.io's default transport settings (long-polling upgrade to WebSocket). No configuration of polling intervals, reconnection, or compression.
- **No mobile or desktop client.** Browser only.

## Open Questions

### Resolved
| # | Section | Question | Asker | Assignee | Status |
|---|---------|----------|-------|----------|--------|
| 1 | Problem | Max terminal commands before seeing something working? | @product-manager | @external-user | ✓ |
| 2 | Solution | Spago workspace member vs. standalone project? | @product-manager | @architect | ✓ |
| 3 | Solution | Esbuild bundling vs. pre-built bundle? | @product-manager | @web-tech-expert | ✓ |
| 4 | Solution | TypesDoNotUnify error in the guided tour acceptable? | @product-manager | @purescript-specialist | ✓ |
| 5 | Solution | Sed mutations vs. separate .purs files for tour regression? | @product-manager | @architect | ✓ |
| 6 | Solution | ChatProtocol cover enough patterns? | @product-manager | @external-user | ✓ |
| 7 | Problem | Makefile prerequisites? → **No Makefile, use npm scripts** | @external-user | @user | ✓ |
| 8 | Solution | Payload serialization constraints? → **Out of scope, backlog** | @external-user | @user | ✓ |
| 9 | Solution | Workspace build: separate CI step? → **Build every time** | @architect | @user | ✓ |
| 10 | Solution | `spago build -p` vs. full workspace? → **Use `-p` for iteration** | @web-tech-expert | @user | ✓ |
| 11 | Solution | Should guided tour include "how to read PS compiler errors" sidebar? → **Yes, 3-4 sentence sidebar before Experiment 3** | @purescript-specialist | @product-manager | ✓ |
| 12 | Solution | How will a user get started if the chat example is a workspace member? → **Clone repo, run from root via `npm run chat`; no separate `package.json` in `examples/chat/`** | @user | @purescript-specialist | ✓ |
| 13 | Solution | Q3 answer references "Makefile" but Q7 resolved to npm scripts -- confirm esbuild works same way as npm script? → **Yes, identical invocation; scripts live in root `package.json` per Q12** | @product-manager | @web-tech-expert | ✓ |
| 14 | Solution | Chat example module names collide in shared `output-es/`? → **Yes, use `Chat.Client.Main`, `Chat.Server.Main`, `Chat.Protocol` namespace prefix** | @purescript-specialist | @architect | ✓ |

### Open
| # | Section | Question | Asker | Assignee | Status |
|---|---------|----------|-------|----------|--------|
| | | No open questions. | | | |
