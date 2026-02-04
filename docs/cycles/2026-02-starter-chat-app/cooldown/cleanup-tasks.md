# Cleanup Tasks

**Project:** Clone-and-Run Starter Chat App
**Cycle:** starter-chat-app
**Started:** 2026-02-04

## Overview

| Total | Pending | In Progress | Complete | Deferred |
|-------|---------|-------------|----------|----------|
| 9 | 2 | 0 | 6 | 1 |

## Tasks

| # | Task | Type | Effort | Assignee | Status | Completed |
|---|------|------|--------|----------|--------|-----------|
| 1 | Fix Effect thunking in index.html callbacks | bug | 1h | web-tech-expert | complete | 2026-02-04 |
| 2 | Commit all uncommitted cycle work and update cycle-end tag | tech-debt | 1h | purescript-specialist | complete | 2026-02-04 |
| 3 | Add HTTP server attachment API to PurSocket.Server | polish | 2h | purescript-specialist | deferred | -- Deferred to next cycle -- requires shaping. |

## Improvement Actions (From Team Retro)

| # | Action | Proposed By | Effort | Owner | Status |
|---|--------|-------------|--------|-------|--------|
| I1 | Create pre-build API checklist template for future cycles | purescript-specialist | small | self | complete | 2026-02-04 |
| I2 | Add `attachToHttpServer` function to PurSocket.Server (same as Task 3) | web-tech-expert | small | team | pending |
| I3 | Add config file convention for negative test subdirectories | qa | small | self | complete | 2026-02-04 |
| I4 | Create docs/GETTING_STARTED.md guide | product-manager | small | team | complete | 2026-02-04 |
| I5 | Audit Socket.io API surface — keep/defer/never decisions | architect | small | self | pending |
| I6 | Add "New Project Setup" section to README | external-user | small | self | complete | 2026-02-04 |

**Note:** I2 and Task 3 overlap — completing Task 3 satisfies I2. I4 and I6 overlap — both address onboarding documentation. They complement each other (GETTING_STARTED.md for full guide, README section for quick reference).

## Tasks by Assignee

### purescript-specialist

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| 2 | Commit all uncommitted cycle work and update cycle-end tag | tech-debt | 1h | complete |
| 3 | Add HTTP server attachment API to PurSocket.Server | polish | 2h | deferred |
| I1 | Create pre-build API checklist template | improvement | small | complete |

### qa

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| I3 | Add config file convention for negative test subdirectories | improvement | small | complete |

### architect

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| I5 | Audit Socket.io API surface — keep/defer/never decisions | improvement | small | pending |

### product-manager

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| I4 | Create docs/GETTING_STARTED.md guide | improvement | small | complete |

### external-user

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| I6 | Add "New Project Setup" section to README | improvement | small | complete |

### web-tech-expert

| # | Task | Type | Effort | Status |
|---|------|------|--------|--------|
| 1 | Fix Effect thunking in index.html callbacks | bug | 1h | complete |
