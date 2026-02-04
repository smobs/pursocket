# Slice: Workspace & Build Plumbing

**Status:** Complete
**Assignee:** @purescript-specialist

## What This Slice Delivers
A developer can run `npm install && npm run chat:build` from the repo root and it compiles the chat example as a spago workspace member with `purs-backend-es` output to `output-es/`.

## Scope
- Create `examples/chat/` directory structure per Q14:
  ```
  examples/chat/
    spago.yaml
    src/
      Chat/
        Protocol.purs       -- module Chat.Protocol (stub)
        Client/
          Main.purs          -- module Chat.Client.Main (stub)
        Server/
          Main.purs          -- module Chat.Server.Main (stub)
    static/
      index.html            -- placeholder
  ```
- Create `examples/chat/spago.yaml` as workspace member:
  ```yaml
  package:
    name: chat-example
    dependencies:
      - pursocket
      - prelude
      - effect
      - aff
      - console
  ```
- ~~Update root `spago.yaml` to add workspace member under `extraPackages`~~ **Not needed.** Spago 0.93.x auto-discovers workspace members from subdirectories containing a `spago.yaml` with a `package:` block. The `extraPackages` key is for external/third-party packages, not workspace members. Attempting to list a workspace member under `extraPackages` produces an error: "Some packages in your local tree overlap with ones you have declared in your workspace configuration."
- Add npm scripts to root `package.json`:
  ```json
  "chat:build": "spago build -p chat-example && npx esbuild output-es/Chat.Client.Main/index.js --bundle --format=esm --platform=browser --outfile=examples/chat/static/client.bundle.js",
  "chat:start": "node output-es/Chat.Server.Main/index.js",
  "chat": "npm run chat:build && npm run chat:start"
  ```
- Verify `spago build -p chat-example` produces `output-es/Chat.Client.Main/` and `output-es/Chat.Server.Main/`
- Verify `purs-backend-es` propagates to workspace member (output goes to `output-es/`, not `output/`)

## NOT in This Slice
- Real chat logic (stubs only)
- esbuild bundle verification (just needs to compile)
- CI changes
- GUIDED_TOUR.md

## Dependencies
- None (first slice)

## Acceptance Criteria
- [x] `examples/chat/spago.yaml` exists as valid workspace member config
- [x] Root `spago.yaml` includes `chat-example` in workspace (via auto-discovery, not `extraPackages` -- see Scope note above)
- [x] Root `package.json` has `chat:build`, `chat:start`, `chat` scripts
- [x] `spago build -p chat-example` succeeds from repo root
- [x] `output-es/Chat.Client.Main/index.js` exists after build
- [x] `output-es/Chat.Server.Main/index.js` exists after build
- [x] `output-es/Chat.Protocol/index.js` exists after build
- [x] Full workspace `spago build` still succeeds (no regressions)

## Verification (Required)
- [x] Tests run and pass: `spago build -p chat-example` exits 0, output-es directories created
- [x] Full build works: `spago build` exits 0 (all workspace members: `chat-example`, `pursocket`)
- [x] Existing tests pass: `npm test` exits 0 (22/22 tests, 4/4 negative compile tests)

## Build Notes

**What does 'done' look like?** From the repo root, `spago build -p chat-example` exits 0 and produces `output-es/Chat.Client.Main/index.js`, `output-es/Chat.Server.Main/index.js`, `output-es/Chat.Protocol/index.js`. The full workspace `spago build` and `npm test` still pass. Root `package.json` has `chat:build`, `chat:start`, `chat` scripts.

**Critical path:** (1) Create directory structure + stubs, (2) create workspace member `spago.yaml`, (3) update root `spago.yaml` with `extraPackages`, (4) verify `spago build -p chat-example` works with `purs-backend-es` output in `output-es/`, (5) add npm scripts to root `package.json`.

**Unknowns:** Whether `purs-backend-es` propagates from workspace-level `backend:` config to workspace member builds. The root `spago.yaml` declares the backend at the `workspace:` level. If spago does not pass that through to member package builds, output will go to `output/` instead of `output-es/` and all npm script paths break.

**Risks:** The `purs-backend-es` propagation issue is the #1 risk from the bet decision. Mitigation: verify early, and if it fails, try adding a `backend:` key to the member's `spago.yaml`. If that also fails within 30 minutes, document the issue.

**Approach:** Create all files first, then build and verify. Fix issues iteratively.

## Progress Log
| Date | Status | Notes |
|------|--------|-------|
| 2026-02-04 | Complete | Directory structure, spago.yaml, npm scripts, all stubs compile. purs-backend-es propagates correctly. Key discovery: workspace members are auto-discovered, not registered in extraPackages. |
