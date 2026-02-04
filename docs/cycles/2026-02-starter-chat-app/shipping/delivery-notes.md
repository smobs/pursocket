# Delivery Notes: Clone-and-Run Starter Chat App

**Shipped:** 2026-02-04
**Appetite:** 2 weeks
**Actual:** 1 day (well within appetite)

## What Shipped

A complete, self-contained chat application inside the PurSocket repository that demonstrates every PurSocket API pattern with zero custom FFI. Developers can clone the repo, run three commands, and see type-safe Socket.io in action. A guided tour walks through three deliberate type errors to show PurSocket's compile-time protection.

### Features/Capabilities
- Developers can evaluate PurSocket with `git clone && npm install && npm run chat`
- Real-time chat between multiple browser tabs on localhost:3000
- Guided tour with 3 deliberate type error experiments and verbatim compiler output
- Negative test regression suite prevents tour examples from silently breaking
- CI drift prevention ensures the chat example always compiles against current PurSocket

### Scope Delivered
- **Slice 01 - Workspace & Build Plumbing**: Spago workspace member, npm scripts, purs-backend-es propagation
- **Slice 02 - Chat Protocol & Server**: ChatProtocol type, 75-line server with all 6 events
- **Slice 03 - Browser Client & HTML**: Protocol wrapper exports, inline JS DOM, esbuild bundle
- **Slice 04 - Guided Tour & CI**: GUIDED_TOUR.md, 3 tour negative tests, CI integration

## What Didn't Ship (Scope Cuts)

- **Timestamp in protocol**: Dropped `timestamp :: String` from `newMessage` event. Was FFI-dependent (`new Date().toISOString()`). Client-side JS adds timestamps for display instead. Library improvement noted in backlog.
- **PureScript-owned server lifecycle**: Server uses a JavaScript wrapper script (`start-server.mjs`) for HTTP static file serving. Library improvement (HTTP server attachment API) noted in backlog.

## Success Criteria

| Criterion | Met | Notes |
|-----------|-----|-------|
| `npm run chat` produces running chat | Yes | User confirmed "works great" |
| All 6 events demonstrated | Yes | sendMessage, setNickname, newMessage, userJoined, userLeft, activeUsers |
| GUIDED_TOUR.md with 3 experiments | Yes | Verbatim compiler output for all 3 |
| Experiment 3 compiler errors sidebar | Yes | "How to read PureScript compiler errors" section |
| tour/ regression tests pass in CI | Yes | 7/7 negative tests pass |
| chat:build in CI | Yes | Added to ci.yml |
| npm scripts in root package.json | Yes | chat:build, chat:start, chat |
| Modules namespaced as Chat.* | Yes | Chat.Client.Main, Chat.Server.Main, Chat.Protocol |
| HTML under 50 lines | Adjusted | 75 lines (was 30 before FFI elimination moved DOM JS inline). Markup is 27 lines. |
| Server under 80 lines | Yes | 75 lines |

## Definition of Done

**Target:** Committed to main branch, all tests pass, CI green
**Achieved:** All code committed, 22/22 tests + 7/7 negative compile tests pass, CI updated with chat:build step

## Known Limitations

- Server requires a JavaScript wrapper script for static file serving (PurSocket library lacks HTTP server attachment API)
- `setNicknameCb` uses callback pattern because `call` returns `Aff` (not directly consumable from JS)
- No timestamp in protocol — client adds display timestamps in JavaScript
- HTML is 75 lines (over 50-line target) due to inline DOM JavaScript from FFI elimination

## Team

| Role | Contribution |
|------|-------------|
| @purescript-specialist | Primary builder: workspace config, protocol, server, FFI elimination rework |
| @web-tech-expert | Browser client, HTML, esbuild bundling, static file serving |
| @qa | Guided tour, negative tests, CI integration, test infrastructure refactoring |
| @architect | FFI elimination architecture design, workspace member strategy, module namespacing |
| @product-manager | Pitch drafting, guided tour sidebar requirement, 6 Q&A questions in shaping |
| @external-user | Onboarding flow validation, protocol design feedback, command threshold (3 steps) |

## Lessons Learned

- Spago workspace members are auto-discovered — `extraPackages` is for external packages only
- `purs-backend-es` needs `npx` wrapper when installed as devDependency (not on PATH)
- ESM output from purs-backend-es requires explicit `import {main} from '...'; main()` invocation
- PurSocket.Server needed `onDisconnect` and `socketId` for any real application (library gap)
- Eliminating FFI from examples improves clarity but pushes DOM code into HTML (increases HTML line count)
- Subagent permissions must include Write/Edit tools for file creation (caused one blocked agent)

---

## Next Steps

Run `/project-orchestrator:project-cooldown` to begin the cool-down period.
