# Retro Notes: PureScript Specialist

Capture difficulties as you work. One entry per obstacle is enough.

---

### [Date] - [Brief title]

**What happened:** [1-2 sentences describing the obstacle]

**Impact:** [Time lost, rework required, scope cut, etc.]

**Root cause:** [Missing info, wrong assumption, tooling issue, unclear requirements, etc.]

---

### 2026-02-04 - purs-backend-es not in PATH

**What happened:** `spago build` silently failed at the backend step because `purs-backend-es` was not on the system PATH (only in `node_modules/.bin/`). The error was hidden -- spago just printed "Failed to build with backend purs-backend-es" with no details. Had to run with `-v` to discover exit code 127 (ENOENT).

**Impact:** ~15 minutes debugging. Fixed by changing spago.yaml backend cmd from `"purs-backend-es"` to `"npx"` with args `["purs-backend-es", "build"]`.

**Root cause:** The original spago.yaml backend config assumed `purs-backend-es` was globally installed. It was only installed as a devDependency in `package.json`. Spago does not automatically add `node_modules/.bin` to PATH when invoking the backend command.

---

### 2026-02-04 - ESM output requires explicit main() invocation

**What happened:** `node output-es/Chat.Server.Main/index.js` produced no output. The generated ESM module exports `main` as a binding but does not auto-invoke it. The existing test script already used `--input-type=module -e "import {main} from '...'; main();"` but the `chat:start` npm script was written to invoke the file directly.

**Impact:** ~5 minutes. Updated `chat:start` npm script to use the `--input-type=module -e` pattern.

**Root cause:** purs-backend-es generates modules that export functions, not scripts that execute on load. This is the correct behavior for a module system but means entry points need a wrapper.

---

### 2026-02-04 - PurSocket.Server missing onDisconnect and socketId

**What happened:** The chat server needs to handle client disconnections and identify sockets by ID. PurSocket.Server had no `onDisconnect` (Socket.io's "disconnect" is a system event, not a protocol event) and no `socketId` accessor.

**Impact:** ~20 minutes to add two functions + FFI to the library. This was anticipated in the build notes analysis.

**Root cause:** The initial library API was built to match the integration test needs, which did not include disconnect handling or socket identification. These are general-purpose server capabilities that any real application needs.

---

<!-- Add more entries below as needed -->
