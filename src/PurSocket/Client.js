// FFI for PurSocket.Client
// Thin wrappers around the socket.io-client API.

import { io } from "socket.io-client";

// primConnect :: String -> Effect SocketRef
export const primConnect = (url) => () => io(url);

// primJoin :: SocketRef -> String -> Effect SocketRef
// Extracts the base URL from the existing socket and creates a new
// connection to the named namespace.
export const primJoin = (baseSocket) => (ns) => () => {
  const baseUrl = baseSocket.io.uri;
  return io(baseUrl + "/" + ns);
};

// primEmit :: SocketRef -> String -> a -> Effect Unit
export const primEmit = (socket) => (event) => (payload) => () => {
  socket.emit(event, payload);
};

// primCallImpl :: SocketRef -> String -> a -> Int -> (r -> Effect Unit) -> (Error -> Effect Unit) -> Effect Unit
// Uses Socket.io v4.4+ timeout() for acknowledgement with timeout.
export const primCallImpl = (socket) => (event) => (payload) => (timeout) => (onSuccess) => (onError) => () => {
  socket.timeout(timeout).emit(event, payload, (err, response) => {
    if (err) {
      onError(err)();
    } else {
      onSuccess(response)();
    }
  });
};

// primOnMsg :: SocketRef -> String -> (a -> Effect Unit) -> Effect Unit
export const primOnMsg = (socket) => (event) => (callback) => () => {
  socket.on(event, (data) => callback(data)());
};

// primOnConnect :: SocketRef -> Effect Unit -> Effect Unit
export const primOnConnect = (socket) => (callback) => () => {
  socket.on("connect", () => callback());
};

// primDisconnect :: SocketRef -> Effect Unit
export const primDisconnect = (socket) => () => {
  socket.disconnect();
};
