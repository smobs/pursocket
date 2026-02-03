# Retro Notes: QA

Capture difficulties as you work. One entry per obstacle is enough.

---

### 2026-02-03 - Broadcast integration test timing failure

**What happened:** The broadcast (s2c) integration test initially failed because the server broadcast was sent before the client had fully connected to the namespace. The client's `onMsg` listener was registered but the namespace socket was not yet connected, so the broadcast was missed.

**Impact:** Required restructuring the broadcast test to use `onConnection` on the server side, so the broadcast is sent only after the server confirms the client has connected. Minor rework, no time lost beyond debugging the initial failure.

**Root cause:** Socket.io namespace connections are asynchronous. A simple time-based delay (`waitForNsConnect` with 100ms) was insufficient to guarantee connection was established. The fix was architectural: trigger the broadcast from the server's `onConnection` callback rather than relying on timing.

---

### 2026-02-03 - PureScript dead code elimination of browser test references

**What happened:** The `PurSocket.BrowserTest` module was intended to reference `Client.connect` to ensure esbuild includes the socket.io-client dependency in the browser bundle. However, PureScript's compiler eliminated the `let _ = Client.connect` binding as dead code, producing compiled output that did not import PurSocket.Client at all.

**Impact:** Required adding a small FFI helper (`isFunction`) that forces the compiler to retain the Client import by using it in a runtime expression. Minor workaround, no significant time lost.

**Root cause:** PureScript's compiler aggressively eliminates unused bindings. `let _ = expr` is treated as discardable. The value needed to flow into a side-effectful expression (like `log`) to survive compilation.

---

### 2026-02-03 - Client API missing onMsg for receiving s2c messages

**What happened:** The existing Client API had `emit` and `call` but no way to receive server-to-client messages. This was needed for the broadcast integration test (and is needed for real-world usage). Added `Client.onMsg` as the client-side counterpart to `Server.broadcast`.

**Impact:** Required adding 3 new FFI functions to Client (`primOnMsg`, `primOnConnect`, `primDisconnect`) and 2 to Server (`primOnCallEvent`, `primCloseServer`). This was expected from the slice specification and had no schedule impact.

**Root cause:** The Client and Server API slices (3 and 4) focused on the send-side APIs. The receive-side (`onMsg`) and lifecycle management (`disconnect`, `closeServer`) are naturally needed for integration testing and real usage.

---

<!-- Add more entries below as needed -->
