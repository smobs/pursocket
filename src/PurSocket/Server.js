// FFI for PurSocket.Server
// Thin wrappers around the socket.io server API.

import { Server } from "socket.io";

export const primCreateServer = () => new Server();

export const primCreateServerWithPort = (port) => () =>
  new Server(port, { cors: { origin: "*" } });

export const primBroadcast = (io) => (ns) => (event) => (payload) => () => {
  io.of("/" + ns).emit(event, payload);
};

export const primOnConnection = (io) => (ns) => (callback) => () => {
  io.of("/" + ns).on("connection", (socket) => callback(socket)());
};

export const primOnEvent = (socket) => (event) => (callback) => () => {
  socket.on(event, (data) => callback(data)());
};

// primOnCallEvent :: SocketRef -> String -> (a -> Effect r) -> Effect Unit
// Handles Socket.io acknowledgements: the handler receives data and
// its return value is sent back to the caller via the ack callback.
export const primOnCallEvent = (socket) => (event) => (handler) => () => {
  socket.on(event, (data, ack) => {
    const result = handler(data)();
    if (typeof ack === "function") {
      ack(result);
    }
  });
};

// primOnDisconnect :: SocketRef -> Effect Unit -> Effect Unit
export const primOnDisconnect = (socket) => (callback) => () => {
  socket.on("disconnect", () => callback());
};

// primSocketId :: SocketRef -> String
export const primSocketId = (socket) => socket.id;

// primCloseServer :: ServerSocket -> Effect Unit
export const primCloseServer = (io) => () => {
  io.close();
};
