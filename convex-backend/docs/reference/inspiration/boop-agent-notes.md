# Inspiration notes: raroque/boop-agent

Source: https://github.com/raroque/boop-agent.git
Commit read: `31979130b1371acd9defbea115279a06c63c1fb4` (2026-07-13)
Cloned read-only to a scratch dir for this review; not vendored into this repo.

## Stack reality check (read this first)

**This is not a `@convex-dev/agent` / Vercel AI SDK project**, and it is not really an
"emotional companion" app either — manage expectations accordingly:

- LLM orchestration is the **official Anthropic `@anthropic-ai/claude-agent-sdk`** (the
  Claude Agent SDK, i.e. the same family this very agent runs on) plus an optional Codex
  runtime, not the Vercel AI SDK. There is no `@convex-dev/agent` component anywhere in the
  repo.
- Convex is used purely as **the durable state/reactive-UI layer** (messages, memory,
  agent run logs, usage, drafts, automations) — a debug dashboard subscribes to it. All
  model calls happen in a separate long-running Node/Express server (`server/`), not in
  Convex actions.
- Transport is **iMessage via Sendblue webhooks**, not a chat UI talking directly to the
  backend (there is a debug web UI too, but it's secondary).
- It is explicitly **single-user / single-tenant** — "No user auth. This is a single-user
  tool. Add Clerk or similar if you want multi-tenant" (their own ARCHITECTURE.md). So the
  "authorization/ownership patterns for scoping data per user" ask has **no direct
  answer here** — there's nothing to steal on that front, it's out of scope for them.
- Persona work is thin: the whole "character" is a ~15 word tone instruction ("Warm,
  witty, concise... write like you're texting a friend") inside a much longer
  *operational* system prompt. If you're looking for deep persona/backstory scaffolding
  for a companion, this repo won't teach you that — its system prompt is a dispatcher
  policy manual, not a character sheet.

Despite that mismatch, the project is unusually well-documented (`ARCHITECTURE.md`) and
has several sharp, concrete patterns worth stealing for the memory, cost-tracking, and
safety-rail layers of the Convex Agent integration. Those are below.

---

## 1. Dispatcher / executor split (cheap router + heavy sub-agent)

**What it does:** Every user turn first goes through a small, cheap "interaction agent"
with a tiny toolset (`recall`, `write_memory`, `spawn_agent`, plus small utility tools) and
a short system prompt. It does not have WebSearch/WebFetch/Bash/file tools at all — those
are explicitly listed in `disallowedTools`. If the turn needs real work (web lookup, email,
calendar, etc.), the dispatcher calls `spawn_agent(task, integrations[])` with a
**rewritten, crisp task description** (not the raw user message), which spawns a
short-lived "execution agent" that has the heavy tools scoped to just the integrations
named. The execution agent's result comes back as a tool result, and the dispatcher
relays it *in its own voice* — never verbatim.

**Why it's good:** Most turns (chit-chat, memory lookups) never spawn a sub-agent, so
they're fast and cheap. The heavy, more failure-prone tool-calling path only runs when
needed, and it runs in an isolated context that can't leak its raw tool-chatter into the
user-facing voice — the interaction agent is the only thing that "speaks" to the user, so
tone/persona stays consistent even when the actual work is delegated. It's also a natural
place to enforce policy (no fabricated facts, no phone numbers) once, at the boundary,
instead of in every tool-using call.

**How it'd apply to us:** Our schema is 1:1 companion chat, not multi-tool automation, so a
full "spawn a sub-agent" split is overkill today. But the *shape* is worth keeping in mind
if/when we add tool use (e.g. web search, calendar) to the companion: keep the
conversational/persona-voice model separate from a tool-executing model, and always have
the persona model rewrite the tool result in-voice rather than passing it through. Even
without sub-agents, the "acknowledge immediately, then do slow work" UX rule is directly
applicable: their system prompt hard-requires a one-line ack (`send_ack`) *before* any
slow tool call, because the user sees nothing for 10-30s otherwise. If we ever add
slow tool calls (memory search over mem0, web lookups) to a `messages` turn, send an
optimistic "thinking" message (or a client-side typing indicator keyed off a Convex
`conversations` field) before the slow work starts, exactly for this reason.

---

## 2. Memory as an explicit, scored, decaying store — not "stuff it all in context"

This is the single most transferable piece of the repo for our mem0 plans, and it's a
fully-specified reference implementation you can crib the *shape* of even if mem0 handles
the embeddings/retrieval internally.

**Schema (`convex/schema.ts` → `memoryRecords`):**
```ts
memoryRecords: defineTable({
  memoryId: v.string(),
  content: v.string(),
  tier: v.union(v.literal("short"), v.literal("long"), v.literal("permanent")),
  segment: v.union(v.literal("identity"), v.literal("preference"), v.literal("correction"),
    v.literal("relationship"), v.literal("project"), v.literal("knowledge"), v.literal("context")),
  importance: v.number(),       // 0-1
  decayRate: v.number(),        // per-segment default, see below
  accessCount: v.number(),
  lastAccessedAt: v.number(),
  sourceTurn: v.optional(v.string()),
  lifecycle: v.union(v.literal("active"), v.literal("archived"), v.literal("pruned")),
  supersedes: v.optional(v.array(v.string())),   // memoryIds this replaces
  embedding: v.optional(v.array(v.float64())),
  metadata: v.optional(v.string()),              // loose JSON sidecar, e.g. {corrects: "..."}
})
  .vectorIndex("by_embedding", { vectorField: "embedding", dimensions: 1024, filterFields: ["lifecycle"] })
```

**Key ideas, each independently useful:**

- **Segments with per-segment defaults for tier/importance/decay**, not one global memory
  bucket. `identity` (0.85 importance, decays almost never) vs `context` (0.40, decays
  fast) vs a dedicated `correction` segment (0.80, decays slowly) that exists specifically
  to model "the user told me I was wrong about X." The correction segment is genuinely
  clever: extraction prompts are told to prefer `correction` over `preference`/`identity`
  whenever the user is fixing something, and it carries a `metadata.corrects` field
  recording *what was wrong*. This gives you an explicit, queryable trail of self-repair
  instead of just silently overwriting a fact.
- **Adaptive exponential decay + access reinforcement, computed on read, not stored:**
  `effectiveScore = importance * exp(-λ * daysSinceAccess) * (1 + log1p(accessCount)*0.1)`,
  where λ's implied half-life scales up with importance (`server/memory/clean.ts`). A
  6-hour cron computes this for every active memory and demotes low scorers: below 0.15 →
  `archived`, below 0.05 → `pruned`; `permanent` tier is exempt. This means memories don't
  need a background rewrite on every access — score is a pure function of stored fields
  evaluated lazily.
- **`recall()` is a tool call, not automatic context injection**, and the system prompt is
  aggressively explicit about this: *"Your context does NOT auto-load saved memories...
  Saying 'I don't have a phone number for Alex' without first calling recall() is a
  CRITICAL FAILURE."* This is a strong, concrete answer to "does it rebuild context from
  scratch each turn or maintain a growing transcript" — **neither**: it keeps only the last
  10 raw turns (`messages.recent`, limit 10) for short-term coherence, and everything
  durable must be explicitly recalled via a semantic/substring search tool. The two are
  cleanly separated: recency window vs. durable fact store.
- **`supersedes` as an explicit archival edge**, not a delete: `memoryRecords.upsert`
  takes an optional `supersedes: string[]`, and archives every target memoryId
  (`lifecycle: "archived"`) in the same mutation, before doing the insert/patch. This gives
  you a lightweight "this replaced that" graph without a real graph table.
- **Vector search with an oversample-then-filter pattern for demo/test data isolation**
  (`convex/memoryRecords.ts:vectorSearch`): Convex vector search can't filter on a boolean
  cheaply post-hoc, so they oversample (`limit + 100`, capped at 256) before joining back
  to full records and filtering, so seeded demo rows never leak into real recall results.
  Useful if you ever seed preview/demo conversations in the same deployment as real user
  data — see pattern #7 below for the general form of this trick.

**How it'd apply to us:** mem0 will likely own embeddings/retrieval, but the
*segmentation + tier + decay scoring* is a policy layer you'd still want on top of
whatever mem0 gives you, and it maps cleanly onto a `memoryRecords`-shaped table
alongside `users`/`conversations`/`messages` — one row per durable fact about a user,
scoped by `userId` (their single-tenant `memoryId` isn't user-scoped; ours must be, e.g.
`.index("by_user", ["userId"])` plus `.index("by_user_lifecycle", ["userId", "lifecycle"])`
mirroring their `by_lifecycle` index). The `correction` segment plus `metadata.corrects` is
worth lifting close to verbatim — it's the difference between "the companion just quietly
forgets it was wrong" and "the companion has an audible self-correction it can reference
later." The 6-hour decay-and-archive cron is a cheap Convex `crons.ts` job you could add
almost unmodified once you have an `importance`/`decayRate`/`lastAccessedAt` on whatever
memory table mem0-integration produces (or a Convex-side mirror of mem0's metadata).

---

## 3. Background fact extraction, fire-and-forget, after every turn

**What it does (`server/memory/extract.ts`):** After the dispatcher replies, it kicks off
`extractAndStore({ userMessage, assistantReply, ... })` **without awaiting it**
(`.catch(...)` only) — the user never waits on this. It sends the turn's
`(userMsg, assistantReply)` pair (plus any inbound images) to a cheap model with a tight
extraction prompt that returns strict JSON:
```json
{"facts":[{"content":"...", "segment":"...", "importance":0.0-1.0, "corrects": "...", "describesImage": true}]}
```
The prompt explicitly says "prefer fewer, higher-quality facts over many trivial ones" and
gives per-segment importance defaults so the extractor doesn't have to invent scores from
scratch. Malformed/garbage importance values are clamped and defaulted server-side
(`Math.max(0, Math.min(1, importance))`) rather than trusted from the LLM output, and an
unknown segment string is skipped rather than crashing the loop.

**Why it's good:** Decouples "have a good conversation" from "maintain a good memory
store" — the extraction call can be slow, cheap-model, and even fail silently without
affecting the user-facing latency or reliability of the chat itself. It's also careful
about noise: extraction is explicitly told to skip proactive/synthetic system messages
(their code comment: extracting facts from a synthetic "proactive notice" would create a
feedback loop where surfaced content reshapes future memory).

**How it'd apply to us:** This is directly portable regardless of whether mem0 or a
custom store owns long-term memory: after the agent's `@convex-dev/agent` thread produces
a reply, schedule a fire-and-forget Convex action (or `ctx.scheduler.runAfter(0, ...)`)
that runs a small extraction prompt over the latest user/assistant pair and writes to your
memory table. Keep the same discipline: cheap model, strict JSON, clamp/validate every
numeric field before writing, skip rather than throw on unrecognized shapes, and exclude
any synthetic/system-generated turns (e.g. a "here's your daily check-in" proactive ping)
from ever being fed back into extraction.

---

## 4. Three-role LLM pipeline for memory consolidation (proposer → adversary → judge)

**What it does (`server/consolidation.ts`):** A daily (or on-demand) job loads up to 150
active memories and runs them through three sequential LLM calls with three different
system prompts:

1. **Proposer** — given the memory list, proposes `merge` (multiple memories → one
   rewritten memory), `supersede` (a newer fact overrides an older conflicting one), or
   `prune` (redundant/wrong) operations, as strict JSON.
2. **Adversary** (a cheaper model, e.g. Haiku, configurable via env) — reviews every
   proposal and raises objections with a `severity: low|medium|high`, specifically primed
   to be skeptical of "correction superseded by non-correction" and "identity
   merged/pruned" cases.
3. **Judge** — sees both the proposals and the adversary's objections and approves/rejects
   each with a rationale, told to reject high-severity objections "unless the proposal's
   benefit clearly outweighs the loss."

Only approved proposals are applied (via the same `upsert`/`supersedes` mutation as normal
writes, or `setLifecycle` for prunes). The **entire run — proposals, challenges, decisions,
applied changes, and a snapshot of every memory referenced** — is persisted progressively
to a `consolidationRuns` table (`details` as a JSON blob updated after each phase, not
just at the end), so a UI can show a live pipeline and a full audit trail exists for every
historical run, not just the outcome.

**Why it's good:** This is a genuinely clever, non-obvious pattern for keeping a growing
memory store from degrading into a pile of redundant/contradictory facts, using
adversarial self-critique as a cheap guardrail against a single model's over-eager
merging. Persisting intermediate pipeline state (not just the final result) is also a
nice UX/debuggability trick — you can watch or replay *why* a merge happened, not just
that it did.

**How it'd apply to us:** Directly reusable as a scheduled Convex action once we have a
memory table of any shape (ours or mem0-backed): a `consolidationRuns` table + a
`runConsolidation` action that does proposer→adversary→judge exactly this way. If mem0
already does its own consolidation internally, this pattern is still worth keeping as a
reference for *any* place we want an LLM to make destructive/merging decisions over user
data — the two-model self-critique step before applying anything is a cheap way to reduce
"agent silently deleted something the user cared about" incidents. Even a single-model
version (skip the adversary, just proposer→judge) captures most of the value for less
cost, if you want to start cheap.

---

## 5. Usage/cost tracking as its own append-only ledger, joined by "source"

**What it does:** A dedicated `usageRecords` table logs *every* model call — dispatcher,
execution agent, background extraction, and each of the three consolidation roles — as one
row, tagged by a `source` enum (`dispatcher | execution | extract | consolidation-proposer
| consolidation-adversary | consolidation-judge | proactive`), with `conversationId`,
`turnId`/`agentId`/`runId`, `model`, token counts split into
input/output/cacheRead/cacheCreation, `costUsd`, and `durationMs`. `convex/usageRecords.ts`
exposes `byConversation`, `recent`, and a `summary` query that buckets total cost by
`source` — capped at a defensible scan limit (`5000`, with a comment noting Convex's hard
`.collect()` ceiling of 16,384) so the aggregate query can't silently blow up as the log
grows.

A companion file (`server/usage.ts`) is worth studying for the *cost computation* nuance:
it prefers the SDK's `modelUsage` (aggregate per-model across the whole multi-step query)
over the top-level `usage` field, with an explicit comment that the top-level field
"massively undercounts on tool-heavy runs" — because a single agent turn can silently use
multiple models internally (e.g., a cheap router model for a sub-step). It also handles
model-name aliasing (`claude-sonnet-4-6` vs. the date-stamped `claude-sonnet-4-6-20251101`)
via prefix-matching so cost attribution doesn't silently fall back to "unknown" just
because the SDK expanded an alias.

**Why it's good:** Every cost-control conversation ("which feature is expensive," "is this
user's mem0 extraction costing more than the chat itself," "did the last redeploy spike
cost") is a one-line Convex query against this table instead of parsing provider
dashboards. Tagging by `source` rather than just `conversationId` means you can see, e.g.,
that background extraction is 30% of spend, which is a fundamentally different decision
than "conversation X is expensive."

**How it'd apply to us:** This maps almost 1:1 onto a `@convex-dev/agent`-based
integration. Add a `usageRecords` table with a `source` enum tailored to our call sites
(e.g. `chat`, `memory-extract`, `memory-consolidate`, `title-generation` — whatever
distinct model-call paths we end up with), and record a row after every agent
`generateText`/`streamText` call using the AI SDK's own usage object (input/output/cached
tokens are already surfaced by the Vercel AI SDK's `result.usage`). This gives free
per-user or per-conversation cost visibility without needing a separate analytics
pipeline, and is a natural gate if we ever want a per-user rate/budget limit (e.g. "block
new sends once `sum(costUsd) for user this month > $X`" via a query over this table keyed
by a `userId` field we'd add that they don't need, being single-tenant).

---

## 6. Stage-then-commit ("draft") pattern for any external/irreversible action

**What it does (`server/draft-tools.ts` + `drafts` table):** Any tool-using agent that
could take an external action (send email, create a calendar event, post to Slack) is
given only a `save_draft(kind, summary, payload)` tool — never the real send/create tool
directly, enforced by the system prompt ("ALWAYS call this instead of sending or creating
something directly"). The draft is written to Convex with `status: "pending"`. Only a
*separate* tool available to the higher-trust dispatcher agent, `send_draft(draftId,
integrations)`, actually re-spawns an execution agent with the stored payload as its task
and the real tools available — that's the only code path that can commit. `reject_draft`
cancels it. Every draft (pending/sent/rejected) with its raw JSON payload is visible in
the debug dashboard for audit.

**Why it's good:** This is a clean, general safety rail for "LLM triggers an irreversible
side effect": separate the *decision to act* from the *authority to act*, with a durable,
inspectable intermediate state. It doesn't require a human-in-the-loop UI beyond a normal
chat confirmation ("send it" → `list_drafts` → `send_draft`), so it's cheap to implement
and doesn't add real friction for the user, but it means a single hallucinated/over-eager
tool call from the execution agent never actually reaches the outside world unmediated.

**How it'd apply to us:** Even if our companion app doesn't yet have external-action tools
(email, calendar), this is the pattern to reach for the moment it does — e.g. if we ever
let the agent "remember to remind you," "add this to your calendar," or trigger a push
notification/automation on the user's behalf. A `drafts` table scoped by `conversationId`
(and, for us, `userId`/ownership) plus a two-tool split (`save_draft` for anything with
side effects, `send_draft`/`reject_draft` gated behind explicit user confirmation) is a
low-cost insurance policy against an agent tool call doing something the user didn't
actually approve.

---

## 7. ID-prefix namespacing instead of a boolean flag for demo/seed data isolation

**What it does (`convex/demoMode.ts`):** Rather than adding an `isDemo: boolean` column to
every table, demo/seed rows simply get IDs prefixed with `"demo:"`
(`demoId = "demo:" + realId`), and a single `isDemoId(value)` helper
(`value.startsWith("demo:")`) is called everywhere a query needs to decide whether to
include or exclude demo rows — e.g. `memoryRecords.list` filters
`isDemoId(record.memoryId) === demoOnly`, and the same convention is repeated for
`isDemoMessage`, `isDemoAutomationRort`, `isDemoUsageRecord`, keyed off whichever ID field
each table has (conversationId, memoryId, agentId, runId — any one prefixed with `demo:`
marks the whole row).

**Why it's good:** No schema migration needed to add a demo mode later, no extra index,
and the filtering logic lives in one small shared file (`demoMode.ts`) that every query
imports, so the isolation policy can't silently drift between tables. A single
`settings` row (`debug_demo_mode`) toggles whether dashboard queries surface demo rows or
real rows, letting one deployment serve both a live user and a walkthrough/demo dataset
without duplicate Convex projects.

**How it'd apply to us:** Useful if we ever want seeded/preview conversations (App
Store review screenshots, onboarding sample chat, an internal demo build) living in the
same Convex deployment as real user data. Instead of adding `isSeed`/`isDemo` booleans to
`conversations`/`messages`/`memoryRecords`, prefix seeded IDs (e.g.
`conversationId = "seed:" + realId`) and filter with one shared `isSeedId()` helper reused
across every query that lists conversations/messages for a user — cheaper to retrofit
later than a schema change, and harder to forget in one query than a boolean column would
be.

---

## 8. Small but sharp details worth a passing mention

- **Webhook idempotency via a dedicated dedup table**, not a status flag on the message
  itself: `sendblueDedup` has one row per inbound webhook `message_handle`, and `claim()`
  is a single mutation that inserts-or-reports-already-claimed
  (`convex/sendblueDedup.ts`) — a clean primitive for "has this external event already
  been processed," reusable for e.g. R2 upload-completion webhooks or Clerk webhooks if we
  ever need idempotent webhook handling.
- **HMAC webhook secret derived per-app from the raw provider secret**, not the raw
  provider secret used directly, with `timingSafeEqual` for comparison
  (`server/sendblue-webhook-auth.ts`): `derivedSecret = HMAC-SHA256(providerSecret,
  "boop-sendblue-webhook-v1")`. Binding a fixed context string means the derived secret is
  specific to this integration even if the same provider secret is reused elsewhere.
  Straightforward, but worth copying verbatim if we ever verify inbound webhooks
  ourselves (Clerk, R2 event notifications, etc.) rather than trusting a shared-secret
  header check with no timing-safe comparison.
- **Regex-based PII redaction at the output boundary**, applied uniformly right before
  anything is shown to the user or logged (`server/privacy.ts`: `redactPhoneNumbers`,
  `redactContactHandle`), plus a **tool-input redaction hook**
  (`redactToolInputForLog` in `execution-agent.ts`) that scrubs a specific field
  (`browser_fill`'s typed text) before writing tool-call arguments to the audit log table.
  The general shape — redact both what the model *says* and what gets logged about what
  tools *did* — is a good checklist item if we log tool calls/agent traces for debugging,
  since agent logs are an easy place for PII to leak that a chat-bubble-only review misses.
- **Stale/orphaned agent-run sweeper** (`server/heartbeat.ts`): a 60s poll that marks
  `running` agent rows as `failed` if either (a) the in-process controller is still alive
  but the run has exceeded 15 minutes, or (b) there's no live in-process controller at all
  (e.g. the row survived a server restart) and it's older than 90 seconds. This is a cheap,
  concrete answer to "what happens to an agent run that crashes mid-flight" — useful if we
  ever track long-running agent/tool-call state in a Convex table and want it to
  self-heal instead of showing "in progress" forever after a deploy.

---

## Bottom line

Skip this repo for persona/character design and for multi-tenant auth patterns — it
doesn't do either. Its value is almost entirely in the **memory subsystem** (segmented,
scored, decaying facts with an explicit correction mechanism and a proposer/adversary/judge
consolidation pipeline), the **usage/cost ledger** keyed by call-site "source", and a
couple of general safety-rail patterns (stage-then-commit drafts, ID-prefix namespacing
for demo data, idempotent webhook claims). All of it is written for a single-tenant,
non-Convex-Agent stack, so nothing here is drop-in — everything above needs a `userId`
added and needs re-plumbing onto `@convex-dev/agent` threads/messages instead of their
hand-rolled Claude Agent SDK calls, but the *shapes* (tables, scoring formulas, prompt
structures) translate directly.
