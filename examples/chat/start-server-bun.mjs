// Bun entry point for the chat server.
// Creates a @socket.io/bun-engine instance, delegates protocol handling
// to PureScript's startChatBun, and serves static files via Bun.file().

import { Server as Engine } from "@socket.io/bun-engine";
import { startChatBun } from "../../output-es/Chat.Server.Main/index.js";

const PORT = process.env.PORT || 3000;
const STATIC_DIR = new URL("static/", import.meta.url).pathname;

const engine = new Engine({ path: "/socket.io/", pingInterval: 25000 });
startChatBun(engine)();

const { websocket } = engine.handler();

export default {
  port: PORT,
  hostname: '0.0.0.0',
  idleTimeout: 30, // must exceed Socket.IO pingInterval (25s)
  fetch(req, server) {
    const url = new URL(req.url);
    // Socket.IO requests go to the engine
    if (url.pathname.startsWith('/socket.io/')) {
      return engine.handleRequest(req, server);
    }
    // Static file serving via Bun.file()
    const pathname = url.pathname === '/' ? '/index.html' : url.pathname.split('?')[0];
    const file = Bun.file(STATIC_DIR + pathname);
    return file.exists().then(exists =>
      exists ? new Response(file) : new Response("Not found", { status: 404 })
    );
  },
  websocket,
};
