# Getting Started with PurSocket

This guide walks you from an empty directory to a running PurSocket project with a type-safe Socket.io server and browser client.

## Prerequisites

Install these tools before starting:

- **Node.js** >= 18
- **PureScript compiler** (`purs`) >= 0.15
- **spago** >= 0.93

Verify they are available:

```bash
node --version
purs --version
spago --version
```

## 1. Create the project

```bash
mkdir my-pursocket-app && cd my-pursocket-app
spago init
```

## 2. Install npm packages

```bash
npm install socket.io socket.io-client
npm install --save-dev esbuild purs-backend-es
```

- `socket.io` -- server-side Socket.io library
- `socket.io-client` -- client-side Socket.io library
- `esbuild` -- bundles PureScript output for the browser
- `purs-backend-es` -- alternative PureScript backend that produces ES modules (required for esbuild bundling)

## 3. Configure spago.yaml

Replace the generated `spago.yaml` with this. The key parts are the `extraPackages` section (which pulls PurSocket from git) and the `backend` section (which tells spago to use `purs-backend-es`).

```yaml
package:
  name: my-pursocket-app
  dependencies:
    - pursocket
    - prelude
    - effect
    - console

workspace:
  packageSet:
    registry: 72.0.1
  extraPackages:
    pursocket:
      git: https://github.com/toby/pursocket.git
      ref: main
  backend:
    cmd: "npx"
    args:
      - "purs-backend-es"
      - "build"
```

The `backend` section uses `npx` to run `purs-backend-es`. This is a workaround: spago's `backend.cmd` needs an executable on PATH, and `purs-backend-es` is installed locally in `node_modules/.bin/`. Using `npx` resolves it automatically.

## 4. Define your protocol

Create `src/MyApp/Protocol.purs`:

```purescript
module MyApp.Protocol where

import PurSocket.Protocol (Msg)

type AppProtocol =
  ( chat ::
      ( c2s :: ( hello :: Msg { name :: String } )
      , s2c :: ( welcome :: Msg { greeting :: String } )
      )
  )
```

This defines a single `chat` namespace with one client-to-server event (`hello`) and one server-to-client event (`welcome`).

## 5. Write the server

Create `src/MyApp/Server.purs`:

```purescript
module MyApp.Server (startApp) where

import Prelude
import Effect (Effect)
import Effect.Console (log)
import PurSocket.Server (onConnection, onEvent, broadcast)
import PurSocket.Internal (ServerSocket)
import MyApp.Protocol (AppProtocol)

startApp :: ServerSocket -> Effect Unit
startApp server = do
  onConnection @"chat" server \handle -> do
    log "Client connected"

    onEvent @AppProtocol @"chat" @"hello" handle \payload -> do
      log ("Hello from: " <> payload.name)
      broadcast @AppProtocol @"chat" @"welcome" server
        { greeting: "Welcome, " <> payload.name <> "!" }

  log "Server ready"
```

The server function accepts a `ServerSocket` rather than creating one itself. This lets you attach Socket.io to your own HTTP server (see the next step).

## 6. Write the server entry point

Create `start-server.mjs` in the project root. This JavaScript file creates an HTTP server, attaches Socket.io, and delegates to your PureScript code:

```javascript
import { createServer } from "http";
import { readFileSync, existsSync } from "fs";
import { join, extname } from "path";
import { Server } from "socket.io";
import { startApp } from "./output-es/MyApp.Server/index.js";

const PORT = 3000;
const STATIC_DIR = "static";

const MIME = {
  ".html": "text/html",
  ".js":   "application/javascript",
  ".css":  "text/css",
};

const httpServer = createServer((req, res) => {
  const urlPath = req.url === "/" ? "/index.html" : req.url.split("?")[0];
  const filePath = join(STATIC_DIR, urlPath);
  if (existsSync(filePath)) {
    const ext = extname(filePath);
    res.writeHead(200, { "Content-Type": MIME[ext] || "application/octet-stream" });
    res.end(readFileSync(filePath));
  } else {
    res.writeHead(404);
    res.end("Not found");
  }
});

const io = new Server(httpServer, { cors: { origin: "*" } });

// PureScript Effect functions are curried and thunked.
// startApp takes a ServerSocket and returns Effect Unit,
// which in JavaScript looks like: startApp(io)()
startApp(io)();

httpServer.listen(PORT, () => {
  console.log(`Listening on http://localhost:${PORT}`);
});
```

**Why a .mjs file?** PurSocket's server needs an HTTP server to serve your HTML page alongside the WebSocket connection. The `.mjs` entry point creates that HTTP server, attaches Socket.io, and passes the Socket.io instance into PureScript. This is the standard Socket.io deployment pattern.

## 7. Write the client

Create `src/MyApp/Client.purs`:

```purescript
module MyApp.Client (connectAndSayHello) where

import Prelude
import Effect (Effect)
import PurSocket.Client (connect, joinNs, emit)
import PurSocket.Framework (NamespaceHandle)
import MyApp.Protocol (AppProtocol)

connectAndSayHello :: (NamespaceHandle "chat" -> Effect Unit) -> Effect Unit
connectAndSayHello onConnected = do
  socket <- connect "http://localhost:3000"
  handle <- joinNs @"chat" socket
  emit @AppProtocol @"chat" @"hello" handle { name: "World" }
  onConnected handle
```

## 8. Build and bundle

Build the PureScript code:

```bash
spago build
```

Bundle the client for the browser:

```bash
npx esbuild output-es/MyApp.Client/index.js \
  --bundle --format=esm --platform=browser \
  --outfile=static/client.bundle.js
```

This takes the ES module output from `purs-backend-es` and produces a single browser-loadable file.

## 9. Create the HTML page

Create `static/index.html`:

```html
<!DOCTYPE html>
<html>
<head><title>PurSocket Hello</title></head>
<body>
  <h1>PurSocket Hello World</h1>
  <div id="output"></div>
  <script type="module">
    import { connectAndSayHello } from "./client.bundle.js";
    import { onMsg } from "./client.bundle.js";

    // PureScript Effect calling convention:
    //   Every PureScript function is curried: f(a)(b)(c)
    //   Effect functions return a thunk: f(a)() executes the effect
    //   Callbacks must also return thunks: function(x) { return function() { ... } }

    connectAndSayHello(function(handle) {
      return function() {
        document.getElementById("output").textContent = "Connected!";
      };
    })();
  </script>
</body>
</html>
```

## 10. Run it

```bash
node start-server.mjs
```

Open `http://localhost:3000` in your browser. You should see "Connected!" and the server terminal should print "Client connected" and "Hello from: World".

## PureScript Effect calling convention (for JS interop)

When you call PureScript functions from JavaScript, the calling convention may look unusual. Here is how it works:

- **Curried arguments**: `f(a)(b)` instead of `f(a, b)`.
- **Effect thunking**: A PureScript `Effect Unit` compiles to a function that takes no arguments. To run it, call it with `()`. So `emit(handle)(payload)` returns a thunk; `emit(handle)(payload)()` actually sends the message.
- **Callbacks**: When PureScript expects `(a -> Effect Unit)`, in JavaScript you write `function(a) { return function() { /* side effects here */ }; }`. The outer function receives the argument; the inner function is the Effect thunk.

These three rules cover every case you will encounter when integrating PureScript with JavaScript.

## Next steps

- See the [chat example](../examples/chat/) for a complete multi-feature application
- Read the [README](../README.md) for the full API reference
- Try introducing a typo in an event name and run `spago build` to see PurSocket's compile-time error messages
