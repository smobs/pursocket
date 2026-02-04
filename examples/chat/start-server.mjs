// Plain JavaScript entry point for the chat server.
// Creates an HTTP server with static file serving, attaches Socket.io,
// then delegates protocol handling to PureScript's startChat function.

import { createServer } from "http";
import { readFileSync, existsSync } from "fs";
import { join, extname } from "path";
import { Server } from "socket.io";
import { startChat } from "../../output-es/Chat.Server.Main/index.js";

const PORT = 3000;
const STATIC_DIR = new URL("static/", import.meta.url).pathname;

const MIME = {
  ".html": "text/html",
  ".js": "application/javascript",
  ".css": "text/css",
  ".json": "application/json",
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

startChat(io)();

httpServer.listen(PORT, () => {
  console.log(`Chat server listening on http://localhost:${PORT}`);
});
