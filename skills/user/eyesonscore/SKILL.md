---
name: eyesonscore
description: Expert engineering skill for the EyesonScore live archery tournament scoring platform. Use this skill whenever the user mentions EyesonScore, EOS, the monorepo, tournament scoring, bracket engine, match play, Fastify, Prisma schema, Railway deployment, WebSocket scoring, React Native Expo mobile app, or any work on the EyesonScore codebase. Also triggers for: pnpm workspace questions, Cloudflare + Railway architecture, scorer tablet workflow, TOTS import, USA Archery field round integration, subscription/Stripe billing for EOS, or any mention of Scott Booth or Shawn Harrigan in a technical context.
---

# EyesonScore Monorepo Skill

## Project Overview

**EyesonScore** is a live archery tournament scoring SaaS platform, co-founded by Michael Hojnacki, Scott Booth, and Shawn Harrigan. It is live in 12+ states. Michael owns the technical rebuild.

**Critical constraint:** No breaking changes to scoring data or live tournament flows without explicit approval. Platform is production with real tournaments running.

---

## Stack

| Layer | Technology | Notes |
|---|---|---|
| API | Fastify + Prisma | TypeScript, schema-first |
| Database | PostgreSQL | Railway-hosted |
| Frontend | Next.js | Web portal |
| Mobile | React Native Expo | Scorer tablets + archer app |
| Infra | Railway (origin) + Cloudflare (CDN/proxy) | Linode as backup consideration |
| Monorepo | pnpm workspaces | Single repo, multiple packages |
| Auth | JWT + refresh tokens | Replaces old Passport OAuth2 |
| Payments | Stripe | Subscription billing |
| Real-time | WebSockets | Live score updates |
| Queue | BullMQ + Redis | Webhooks, email, async jobs |
| Testing | Vitest + Supertest | Unit + integration |

---

## Monorepo Structure

```
eyesonscore/
├── apps/
│   ├── api/                    # Fastify API
│   │   ├── src/
│   │   │   ├── modules/        # domain modules (tournament, scorer, auth...)
│   │   │   ├── plugins/        # fastify plugins
│   │   │   ├── services/       # external services (stripe, email, fcm)
│   │   │   └── server.ts
│   │   └── package.json
│   ├── web/                    # Next.js portal
│   └── mobile/                 # React Native Expo
├── packages/
│   ├── database/               # Prisma schema + migrations + client
│   ├── shared/                 # shared types, utils, constants
│   └── config/                 # eslint, tsconfig, etc.
├── pnpm-workspace.yaml
├── package.json
└── CLAUDE.md
```

---

## Core Domain Models (Prisma)

These are the canonical models. Never rename or remove fields without migration plan:

```
User
Tournament
TournamentLocation
TournamentLocationTarget
TournamentLocationTargetSlots
TournamentSlot
TournamentSetting
TournamentTemplate
TournamentTargetTablet
Shooter
ShooterScore
ShooterBracketGroup
RegisterArcher
RegisterArcherTransaction
Plan
Subscription
SubscriptionTransaction
Device
DeviceArcher
CardDetail
WalletTransaction
Setting
ContactUs
ContactUsScoreboard
```

**Key flags to preserve:**
- `is_bracket` — enables bracket/match play mode
- `is_match_play` — match play scoring variant
- `is_tablet_score` — tablet-based scoring enabled
- All soft-deletes (`deleted_at`) must be preserved
- All `created_at` / `updated_at` timestamps auto-managed by Prisma

---

## Fastify Module Pattern

Each domain gets its own module folder:

```typescript
// modules/tournament/tournament.routes.ts
import { FastifyInstance } from 'fastify'
import { TournamentController } from './tournament.controller'
import { createTournamentSchema, listTournamentsSchema } from './tournament.schema'

export async function tournamentRoutes(fastify: FastifyInstance) {
    fastify.post('/', { schema: createTournamentSchema }, TournamentController.create)
    fastify.get('/', { schema: listTournamentsSchema }, TournamentController.list)
    fastify.get('/:id', TournamentController.getById)
}

// modules/tournament/tournament.controller.ts
import { FastifyRequest, FastifyReply } from 'fastify'
import { TournamentService } from './tournament.service'

export const TournamentController = {
    async create(request: FastifyRequest, reply: FastifyReply) {
        const tournament = await TournamentService.create(request.body)
        return reply.status(201).send(tournament)
    }
}

// modules/tournament/tournament.service.ts
import { prisma } from '../../database/client'

export const TournamentService = {
    async create(data: CreateTournamentInput) {
        return prisma.tournament.create({ data })
    }
}
```

---

## Prisma Client Pattern

```typescript
// packages/database/src/client.ts
import { PrismaClient } from '@prisma/client'

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient }

export const prisma = globalForPrisma.prisma || new PrismaClient({
    log: process.env.NODE_ENV === 'development' ? ['query', 'error'] : ['error'],
})

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma
```

---

## WebSocket Live Scoring Pattern

```typescript
// Real-time score updates — scorers push, displays receive
import { WebSocket } from 'ws'

// Score update message envelope
interface ScoreUpdate {
    type: 'score_update' | 'timer_sync' | 'match_result'
    tournamentId: string
    locationId: string
    shooterId: string
    scores: number[]
    timestamp: number
}

// Room-based broadcasting (tournament + location = room)
const rooms = new Map<string, Set<WebSocket>>()

function getRoomKey(tournamentId: string, locationId: string) {
    return `${tournamentId}:${locationId}`
}

function broadcast(tournamentId: string, locationId: string, msg: ScoreUpdate) {
    const key = getRoomKey(tournamentId, locationId)
    const room = rooms.get(key)
    if (!room) return
    const payload = JSON.stringify(msg)
    room.forEach(ws => {
        if (ws.readyState === WebSocket.OPEN) ws.send(payload)
    })
}
```

---

## Railway Deployment Rules

- **Never push directly to `main`** — Railway auto-deploys from main
- Always test migrations locally with `prisma migrate dev` before pushing
- Migration deploy command: `prisma migrate deploy` (not `dev`)
- Environment variables managed in Railway dashboard — never commit `.env`
- Health check endpoint required: `GET /health` → `{ status: 'ok', timestamp }`
- **Zero-downtime deploys:** Railway handles graceful shutdown — always handle `SIGTERM`

```typescript
// Graceful shutdown
process.on('SIGTERM', async () => {
    await fastify.close()
    await prisma.$disconnect()
    process.exit(0)
})
```

---

## pnpm Workspace Commands

```bash
# Install all deps
pnpm install

# Run specific app
pnpm --filter @eyesonscore/api dev
pnpm --filter @eyesonscore/web dev

# Add dep to specific package
pnpm --filter @eyesonscore/api add fastify

# Add shared dep to workspace root
pnpm add -w typescript

# Run migrations
pnpm --filter @eyesonscore/database migrate:dev

# Generate Prisma client
pnpm --filter @eyesonscore/database generate

# Build all
pnpm build

# Test all
pnpm test
```

---

## Cloudflare + Railway Architecture

```
User → Cloudflare (CDN, WAF, DDoS) → Railway (Fastify API + PostgreSQL)
                                    → Railway (Next.js SSR)
Mobile App → Cloudflare → Railway API (WebSocket upgraded connection)
```

**WebSocket note:** Cloudflare proxies WebSocket connections. Ensure Railway app handles upgrade headers correctly. Use `wss://` in production.

---

## Scoring Business Logic

### Standard archery scoring
- Recurve/barebow: 10-zone (X, 10, 9...1, M)
- Compound: 5-zone (X, 10, 9, 8, M) or 10-zone
- Field: variable face sizes per distance
- 3D: 12, 10, 8, 5 zones

### Bracket / match play
- Head-to-head, single elimination
- `ShooterBracketGroup` manages seeding and pairings
- Match winner advances — never auto-advance without score confirmation
- `is_bracket` and `is_match_play` flags both required for match play mode

### TOTS integration
- Tournament Officials Tracking System (USA Archery)
- Import flow: TOTS export CSV → parse → map to Shooter/RegisterArcher models
- Field round scorecards: USA Archery standard, printed per archer per round

---

## Stripe Subscription Patterns

```typescript
// Plan tiers — check Plan model for current values, don't hardcode
const PLAN_FEATURES = {
    free: { maxTournaments: 1, maxShooters: 50 },
    pro: { maxTournaments: 12, maxShooters: 500 },
    unlimited: { maxTournaments: Infinity, maxShooters: Infinity },
}

// Webhook handler — always verify signature
import Stripe from 'stripe'
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)

fastify.post('/webhooks/stripe', {
    config: { rawBody: true }  // need raw body for signature verification
}, async (request, reply) => {
    const sig = request.headers['stripe-signature']!
    const event = stripe.webhooks.constructEvent(
        request.rawBody, sig, process.env.STRIPE_WEBHOOK_SECRET!
    )
    // handle event.type
})
```

---

## React Native Expo (Scorer Tablet)

- Target: iPad (landscape), Android tablet
- Expo SDK — keep updated, check EAS build compatibility before upgrading
- Real-time via WebSocket (same endpoint as web)
- Offline scoring buffer — queue scores locally, sync on reconnect
- Screen always-on during active tournament: `activateKeepAwake()` from `expo-keep-awake`

---

## CLAUDE.md Boot Sequence for Claude Code

When starting a new Claude Code session on EyesonScore:

1. Read `CLAUDE.md` at repo root
2. Load `ai/memory-bank/` — activeContext, progress, decisions
3. Report: active session, last completed task, next queued task
4. Confirm Railway environment status
5. **Await task assignment — do NOT begin work until directed**

---

## Common Gotchas

| Issue | Resolution |
|---|---|
| Prisma generates stale types | Run `pnpm --filter database generate` after schema changes |
| WebSocket drops on Cloudflare | Check CF WebSocket setting enabled on zone |
| pnpm workspace dep not found | Check `@eyesonscore/` package name matches in package.json |
| Railway deploy fails on migration | Migration has breaking change — use expand/contract pattern |
| Expo build fails after SDK upgrade | Check all native module compatibility before upgrading |
| Score not syncing to display | Check room key matches between scorer and display clients |
