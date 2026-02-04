# Pre-Build API Checklist

**Cycle:** _[cycle name]_
**Target application:** _[brief description of the app being built]_
**Date:** _[YYYY-MM-DD]_

## Purpose

Before building an application with PurSocket, audit the Socket.io primitives
your app requires against what PurSocket currently exposes. This prevents
mid-build discovery of missing APIs, which forces either scope cuts or
unplanned library work.

## How to use

1. Copy this template to your cycle's `building/` directory.
2. Fill in every row where "Needed" is Yes.
3. For each needed primitive with no PurSocket function, decide the action:
   - **stub** -- add a minimal implementation to unblock the app (timebox: 2h).
   - **defer** -- cut the feature from the app; file a shaping-backlog item.
   - **workaround** -- describe the workaround in the Notes column.
4. Review the completed checklist before writing code.

## Client Primitives

| Socket.io Primitive | PurSocket Function | Needed | Action | Notes |
|---------------------|--------------------|--------|--------|-------|
| `io(url)` | `connect` | | | |
| `io(url, { auth })` | _none_ | | | |
| `socket.emit(event, data)` | `emit` | | | |
| `socket.emit(event, data, ack)` | `call` / `callWithTimeout` | | | |
| `socket.on(event, callback)` | `onMsg` | | | |
| `socket.on("connect", ...)` | `onConnect` | | | |
| `socket.on("disconnect", ...)` | _none (client)_ | | | |
| `socket.on("connect_error", ...)` | _none_ | | | |
| `socket.disconnect()` | `disconnect` | | | |
| `socket.io.on("reconnect", ...)` | _none_ | | | |
| `socket.off(event)` | _none_ | | | Listener cleanup |

## Server Primitives

| Socket.io Primitive | PurSocket Function | Needed | Action | Notes |
|---------------------|--------------------|--------|--------|-------|
| `new Server(port)` | `createServerWithPort` | | | |
| `new Server(httpServer)` | _none_ | | | Attach to existing HTTP server |
| `new Server(port, opts)` | `createServer` | | | CORS options only |
| `io.of(ns).on("connection", ...)` | `onConnection` | | | |
| `socket.on(event, callback)` | `onEvent` | | | |
| `socket.on(event, (data, ack) => ...)` | `onCallEvent` | | | |
| `socket.on("disconnect", ...)` | `onDisconnect` | | | |
| `io.of(ns).emit(event, data)` | `broadcast` | | | |
| `socket.emit(event, data)` | _none_ | | | Emit to single client |
| `socket.join(room)` | _none_ | | | |
| `socket.leave(room)` | _none_ | | | |
| `io.of(ns).to(room).emit(...)` | _none_ | | | Room-targeted broadcast |
| `io.of(ns).use(middleware)` | _none_ | | | Authentication middleware |
| `io.close()` | `closeServer` | | | |
| `socket.id` | `socketId` | | | |

## Summary

| Category | Total Needed | Covered | Stub | Defer | Workaround |
|----------|-------------|---------|------|-------|------------|
| Client | | | | | |
| Server | | | | | |

## Decision log

_Record any decisions made based on this checklist (e.g., "Deferred room
support -- chat app uses namespace-level broadcast only")._

- _[decision]_
