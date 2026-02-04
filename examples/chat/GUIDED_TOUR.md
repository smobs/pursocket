# PurSocket Guided Type Safety Tour

This tour demonstrates PurSocket's compile-time protocol safety using the chat example. You will make three deliberate mistakes in the client code and observe how the PureScript compiler catches each one before a single line of JavaScript runs.

Each experiment shows a different category of protocol mistake:
1. A typo in an event name
2. Sending an event in the wrong direction (client emitting a server-only event)
3. Sending the wrong payload type

All three are bugs that would silently pass in plain Socket.io and only surface at runtime -- if you are lucky enough to notice.

## Prerequisites

Make sure the chat example builds successfully before starting:

```bash
npm run chat:build
```

If this exits with no errors, you are ready.

## Experiment 1: Wrong event name (typo)

### What to change

Open `examples/chat/src/Chat/Client/Main.purs` and find the `sendMessage` function (around line 35-36):

```purescript
sendMessage :: NamespaceHandle "chat" -> String -> Effect Unit
sendMessage handle text =
  emit @ChatProtocol @"chat" @"sendMessage" handle { text }
```

Change `@"sendMessage"` to `@"sendMsg"`:

```purescript
  emit @ChatProtocol @"chat" @"sendMsg" handle { text }
```

### Rebuild

```bash
npm run chat:build
```

### Expected compiler output

```
Error found:
in module Chat.Client.Main

  Custom error:

    PurSocket: invalid Msg event.
      Namespace: chat
      Event:     sendMsg
      Direction: c2s
      Check that the event name exists in this namespace/direction and is tagged as Msg.


while solving type class constraint

  PurSocket.Framework.LookupMsgEvent "sendMsg"
                                     "chat"
                                     "c2s"
                                     (Nil @Type)
                                     t5
```

### What happened

PurSocket walked the `ChatProtocol` type looking for an event named `"sendMsg"` in the `"chat"` namespace's `c2s` (client-to-server) direction. It found no such event -- because the correct name is `"sendMessage"`. The custom error tells you exactly which namespace, event name, and direction failed to match, so you can spot the typo immediately.

In plain Socket.io, this typo would compile and run without error. The client would silently emit to an event name nobody is listening on. You would see no messages arriving on the server and have to debug by comparing string literals across files.

**Revert your change before continuing to Experiment 2.**

## Experiment 2: Wrong direction (client sending a server-only event)

### What to change

In the same `sendMessage` function, change `@"sendMessage"` to `@"newMessage"`:

```purescript
  emit @ChatProtocol @"chat" @"newMessage" handle { text }
```

The `newMessage` event exists in the protocol, but it is defined under `s2c` (server-to-client) -- the server broadcasts new messages to clients, not the other way around.

### Rebuild

```bash
npm run chat:build
```

### Expected compiler output

```
Error found:
in module Chat.Client.Main

  Custom error:

    PurSocket: invalid Msg event.
      Namespace: chat
      Event:     newMessage
      Direction: c2s
      Check that the event name exists in this namespace/direction and is tagged as Msg.


while solving type class constraint

  PurSocket.Framework.LookupMsgEvent "newMessage"
                                     "chat"
                                     "c2s"
                                     (Nil @Type)
                                     t5
```

### What happened

PurSocket's `emit` function hardcodes the direction to `"c2s"` -- clients can only emit client-to-server events. When the type engine looked for `"newMessage"` in the `c2s` event list, it was not there (it is in `s2c`). The error message is the same shape as Experiment 1 because the failure is the same: the event does not exist in the direction being checked.

This is a category of bug that is especially dangerous in plain Socket.io. The event name is valid, the payload might even match -- but the data is flowing in the wrong direction. These bugs pass code review because the event name looks correct. PurSocket catches them because direction is encoded in the type, not just in a comment or convention.

**Revert your change before continuing to Experiment 3.**

## How to read PureScript compiler errors

Before Experiment 3, a note on reading PureScript's error output. The compiler shows a "constraint stack" -- the chain of type classes it walked through before finding the mismatch. You will see names like `IsValidMsg` and `LookupMsgEvent` in this trace. These are PurSocket's internal validation steps: `IsValidMsg` is the top-level check that your `emit` or `onMsg` call is valid, and `LookupMsgEvent` is the step that resolved your event name to its payload type. The important part is at the top: either a custom error message (Experiments 1 and 2) or a `TypesDoNotUnify` line showing the expected type versus the type you provided (Experiment 3).

## Experiment 3: Wrong payload type

### What to change

In the `sendMessage` function, change the payload field name from `text` to `message`:

```purescript
sendMessage :: NamespaceHandle "chat" -> String -> Effect Unit
sendMessage handle text =
  emit @ChatProtocol @"chat" @"sendMessage" handle { message: text }
```

The protocol defines `sendMessage` as `Msg { text :: String }`, but you are passing `{ message :: String }`.

### Rebuild

```bash
npm run chat:build
```

### Expected compiler output

```
Error found:
in module Chat.Client.Main

  Could not match type

    ( text :: String
    ...
    )

  with type

    ( message :: String
    ...
    )


while trying to match type { text :: String
                           }
  with type { message :: String
            }
while solving type class constraint

  PurSocket.Framework.LookupMsgEvent "sendMessage"
                                     "chat"
                                     "c2s"
                                     t0
                                     { message :: String
                                     }
```

### What happened

This time there is no custom PurSocket error message. Instead, the compiler produces its standard `TypesDoNotUnify` error. Here is why: the event name `"sendMessage"` is valid, so PurSocket's lookup succeeds and determines the payload type to be `{ text :: String }` (from the protocol definition). The compiler then tries to unify that expected type with the actual argument `{ message :: String }` -- and they do not match, because the field is named `text`, not `message`.

PurSocket catches protocol-level mistakes (wrong event, wrong namespace, wrong direction) with custom error messages. Payload-level mistakes are caught by PureScript's own type checker, because the payload type is fully determined by the protocol through a functional dependency. The compiler still prevents the bug at compile time -- it just uses its own error format instead of a PurSocket-specific message. Notice that the error shows both the expected type (`text :: String`) and the type you provided (`message :: String`), so it is clear what needs to change.

**Revert your change when done.**

## What to try next

- Read the protocol definition: `examples/chat/src/Chat/Protocol.purs` -- this is the single source of truth for all events.
- Read the full PurSocket README at the repository root for API documentation and architecture details.
- Look at `src/PurSocket/Framework.purs` to see how the type-level validation engine works under the hood.
