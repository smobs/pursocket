# Hill Chart

**Project:** Clone-and-Run Starter Chat App
**Appetite:** 2 weeks
**Started:** 2026-02-04

## Understanding the Hill

```
        ▲
       /|\        FIGURING OUT (uphill)
      / | \       - Uncertainty
     /  |  \      - Discovery
    /   |   \     - Problem-solving
   /    |    \
  /     |     \
 /      |      \  EXECUTION (downhill)
/       |       \ - Known work
        |         - Just doing it
────────┴─────────
```

## Current Status

| Slice | Position | Notes |
|-------|----------|-------|
| Workspace & Build Plumbing | ✅ Complete | Auto-discovery, npx wrapper for purs-backend-es |
| Chat Protocol & Server | ✅ Complete | 75 lines, zero FFI, exports startChat |
| Browser Client & HTML | ✅ Complete | Zero FFI, protocol wrappers + inline JS in HTML |
| Guided Tour & CI | ✅ Complete | 3 experiments, 7/7 negative tests, CI updated |

## History

| Date | Slice | Movement | Notes |
|------|-------|----------|-------|
| 2026-02-04 | All | Created | Build phase started |
| 2026-02-04 | Workspace & Build Plumbing | Complete | Key discovery: workspace members auto-discovered, not registered in extraPackages |
| 2026-02-04 | Chat Protocol & Server | Complete | Library extended with onDisconnect/socketId. FFI eliminated in rework. |
| 2026-02-04 | Browser Client & HTML | Complete | FFI eliminated: client exports protocol wrappers, DOM in HTML inline JS |
| 2026-02-04 | Guided Tour & CI | Complete | 3 tour experiments, verbatim compiler output, 7/7 negative tests |
