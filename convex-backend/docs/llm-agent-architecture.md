# LLM Agent Integration Architecture

Status: historical implementation plan. The bridge described here has since
been implemented and substantially hardened. Read
`docs/current-companion-implementation.md` for the current system and
`docs/llm-chat-remediation-todo.md` for verified/deferred work. This document
preserves the original design sequence and is not a current implementation
inventory.

It was written against `@convex-dev/agent@0.7.1` and
`@convex-dev/rate-limiter@0.3.2` (latest on npm as of 2026-08-22). Every API
claim below cites a local doc file under `docs/reference/convex-agent/` — read
those before implementing, don't rely on this summary alone for exact syntax.

## 1. Schema / config changes

`convex.config.ts` — add the Agent component alongside the existing R2 one
(per `docs/reference/convex-agent/getting-started.md`):

```ts
import { defineApp } from "convex/server";
import { v } from "convex/values";
import r2 from "@convex-dev/r2/convex.config.js";
import agent from "@convex-dev/agent/convex.config";

const app = defineApp({
  env: { R2_PUBLIC_BASE_URL: v.optional(v.string()) },
});

app.use(r2);
app.use(agent);

export default app;
```

**The Agent component manages its own tables internally** (threads, messages,
embeddings) under the `components.agent.*` namespace — confirmed across every
pulled doc page (e.g. `components.agent.threads.listThreadsByUserId`,
`components.agent.vector.index.*` in `context.md`). Nothing in this app's own
`schema.ts` needs to change shape for the component itself to work.

**One new field is needed** on `conversations`, to link each conversation to
its Agent thread:

```ts
conversations: defineTable({
  title: v.optional(v.string()),
  createdAt: v.number(),
  createdBy: v.id("users"),
  lastMessageAt: v.number(),
  agentThreadId: v.optional(v.string()), // NEW — set lazily on first message
}),
```

No other existing table changes. `rawUsage`/`invoices` tables (for billing,
per `docs/reference/convex-agent/usage-tracking.md`) are deferred — not needed
for v1, add later if usage-based billing becomes a real requirement.

## 2. Core integration decision: bridge pattern, existing `messages` table stays authoritative

**Decision: the Agent component's thread/message storage is used purely as
the LLM's memory/context engine. It is never read by the client. The
existing `messages` table remains the single source of truth the iOS client
subscribes to, exactly as it does today — zero changes to
`messages:listForConversation`, `resolveMessage`, or any Swift code.**

Why, concretely:

- The existing `messages` table has a rich, app-specific shape (R2
  attachments, Giphy media ids, voice recordings with waveforms, flattened
  reply-quoting) that the Agent component's `UIMessage`/`ModelMessage` model
  knows nothing about (see `docs/reference/convex-agent/messages.md`). Making
  the Agent's own storage client-facing would mean re-deriving all of that on
  the client, or duplicating attachment/reply resolution logic against a
  different schema.
- The iOS `ChatFeature` package (`ConversationViewModel`,
  `ConvexService.messagesPublisher`) is already built entirely around
  `messages:listForConversation`'s pagination and `resolvedMessage` shape.
  Keeping that query's contract identical means **this entire backend change
  ships with no iOS work at all.**
- The Agent component doesn't require its thread to be client-visible to be
  useful — its value here (conversation-aware context assembly, hybrid
  text/vector search over history, `contextHandler` hook, tool-calling
  scaffolding for later) is entirely a server-side concern.

Consequence: an Agent thread is created lazily, one per `conversations` row,
purely as a place for the LLM's own context/history bookkeeping to live. The
human's message text is passed to the Agent as a plain `prompt` (not
pre-saved via `promptMessageId` — see `docs/reference/convex-agent/agent-usage.md`'s
"Basic (synchronous)" pattern) so the Agent component saves both sides of the
turn into its own thread automatically; this app's own `messages` table
already has its own, separate, synchronous save of the human's message from
the existing `messages.send` mutation, so there is no need for the
"pre-save + `promptMessageId`" optimization the docs recommend for apps that
don't already have their own transactional message-save path.

## 3. New / changed functions

| File | Change |
|---|---|
| `convex/convex.config.ts` | `app.use(agent)` |
| `convex/schema.ts` | `agentThreadId` field on `conversations` |
| `convex/agents/companion.ts` **(new)** | `Agent` instance: model, instructions, name, `contextHandler`/`usageHandler` hook points |
| `convex/ai.ts` **(new)** | `internalAction generateReply` — the generation pipeline (§4) |
| `convex/model/users.ts` | `getOrCreateCompanionUser(ctx)` — synthetic AI sender (§2b) |
| `convex/model/conversations.ts` | `getOrCreateAgentThreadId(ctx, conversationId)` |
| `convex/model/messages.ts` | `insertAssistantPlaceholder`, `patchAssistantText` (internal helpers called by `ai.ts`) |
| `convex/messages.ts` | `send` mutation: after its existing insert, resolve/create `agentThreadId`, schedule `internal.ai.generateReply` |
| `convex/rateLimiting.ts` **(new)** | `RateLimiter` instance (§7) |

### 2b. The synthetic "companion" sender

`messages.senderId` is `v.id("users")` — every message needs a real `users`
row. Rather than changing that type (which would touch `resolveMessage`,
`resolvedMessage`, and every place that assumes a human sender), create
**one well-known singleton `users` row** representing the companion, looked
up (and created on first use) via a stable sentinel identity:

```ts
// model/users.ts
const COMPANION_TOKEN_IDENTIFIER = "system|companion";

export async function getOrCreateCompanionUser(ctx: MutationCtx) {
  const existing = await ctx.db
    .query("users")
    .withIndex("by_token_identifier", (q) => q.eq("tokenIdentifier", COMPANION_TOKEN_IDENTIFIER))
    .unique();
  if (existing !== null) return existing;
  const id = await ctx.db.insert("users", {
    tokenIdentifier: COMPANION_TOKEN_IDENTIFIER,
    clerkId: "companion",
    name: "Embie", // TODO: pull from config/env once companion naming is settled
  });
  return (await ctx.db.get("users", id))!;
}
```

This is the load-bearing trick that makes the zero-iOS-changes claim in §2
true: `resolveMessage`/`toPublicUser` already render any `users` row
correctly, and the client's existing "is this my message" / bubble-alignment
logic already keys off `sender.isCurrentUser`/comparing to the signed-in
user's own id — a companion-authored message just naturally renders as an
incoming bubble, no new concept needed anywhere in the app model.

Since this is a single 1:1-companion app (no multi-companion/social feature),
one global companion row shared across all users/conversations is correct —
per-user personality customization belongs in the Agent's `instructions`, not
in a proliferation of fake `users` rows.

## 4. Generation pipeline (streaming to the iOS client via the existing table)

```
┌─────────────┐   1. insert human message (existing)      ┌──────────────┐
│ messages.send│──────────────────────────────────────────▶│  messages    │
│ (mutation)  │   2. getOrCreateAgentThreadId               │  table       │
│             │   3. schedule internal.ai.generateReply ──┐ └──────────────┘
└─────────────┘                                            │        ▲
                                                             ▼        │ 5. throttled
                                              ┌──────────────────────┴──┐  .patch(text)
                                              │ ai.generateReply         │
                                              │ (internalAction)         │
                                              │ 4. insert placeholder    │
                                              │    assistant message     │
                                              │ 6. agent.streamText(...) │──▶ Agent's own
                                              │    iterate textStream    │    thread (context/
                                              │ 7. final patch + patch   │    memory only —
                                              │    conversations.        │    never read by
                                              │    lastMessageAt         │    the client)
                                              └──────────────────────────┘
```

`messages.send` (existing mutation, minimal addition):

```ts
// after the existing ctx.db.insert("messages", {...}) and conversation patch:
const threadId = await getOrCreateAgentThreadId(ctx, args.conversationId);
await ctx.scheduler.runAfter(0, internal.ai.generateReply, {
  conversationId: args.conversationId,
  threadId,
  prompt: args.text,
});
```

`getOrCreateAgentThreadId` (`model/conversations.ts`) — per
`docs/reference/convex-agent/threads.md` ("You can create a thread in a
mutation or action"), this runs directly inside the `messages.send` mutation,
no extra round trip:

```ts
export async function getOrCreateAgentThreadId(ctx: MutationCtx, conversationId: Id<"conversations">) {
  const conversation = await ctx.db.get("conversations", conversationId);
  if (conversation?.agentThreadId) return conversation.agentThreadId;
  const threadId = await createThread(ctx, components.agent, { title: conversation?.title });
  await ctx.db.patch("conversations", conversationId, { agentThreadId: threadId });
  return threadId;
}
```

`convex/ai.ts` (new — the streaming bridge is the key novel piece, not shown
verbatim in any pulled doc since it's specific to bridging into a pre-existing
table rather than using the Agent's own `listUIMessages`/`syncStreams`):

```ts
"use node";
import { v } from "convex/values";
import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { companionAgent } from "./agents/companion";

export const generateReply = internalAction({
  args: { conversationId: v.id("conversations"), threadId: v.string(), prompt: v.string() },
  handler: async (ctx, { conversationId, threadId, prompt }) => {
    const messageId = await ctx.runMutation(internal.model.messages.insertAssistantPlaceholder, {
      conversationId,
    });

    const result = await companionAgent.streamText(ctx, { threadId }, { prompt });

    let text = "";
    let lastPatchAt = 0;
    const THROTTLE_MS = 250; // mirrors the Agent's own saveStreamDeltas throttling philosophy
    for await (const chunk of result.textStream) {
      text += chunk;
      const now = Date.now();
      if (now - lastPatchAt >= THROTTLE_MS) {
        await ctx.runMutation(internal.model.messages.patchAssistantText, { messageId, text });
        lastPatchAt = now;
      }
    }
    // Final patch is required — the loop above may exit with unflushed text
    // if the last chunk arrived inside the throttle window.
    await ctx.runMutation(internal.model.messages.patchAssistantText, {
      messageId,
      text,
      conversationId, // also bumps lastMessageAt — see below
    });
  },
});
```

`model/messages.ts` additions:

```ts
export const insertAssistantPlaceholder = internalMutation({
  args: { conversationId: v.id("conversations") },
  returns: v.id("messages"),
  handler: async (ctx, { conversationId }) => {
    const companion = await getOrCreateCompanionUser(ctx);
    return await ctx.db.insert("messages", {
      conversationId,
      clientId: crypto.randomUUID(), // server-authored; clientId is only meaningful for dedup on client-sent messages
      senderId: companion._id,
      text: "",
      attachments: [],
      createdAt: Date.now(),
    });
  },
});

export const patchAssistantText = internalMutation({
  args: { messageId: v.id("messages"), text: v.string(), conversationId: v.optional(v.id("conversations")) },
  returns: v.null(),
  handler: async (ctx, { messageId, text, conversationId }) => {
    await ctx.db.patch("messages", messageId, { text });
    if (conversationId !== undefined) {
      await ctx.db.patch("conversations", conversationId, { lastMessageAt: Date.now() });
    }
    return null;
  },
});
```

**Why this gives real streaming with zero iOS changes**: `messages:listForConversation`
is a reactive Convex query. Every `ctx.db.patch("messages", messageId, { text })`
call above re-triggers that query for every subscribed client, same as any
other write to that table. The iOS client already re-renders on new query
results — it doesn't know or care that the same message's `text` field is
growing across several pushes rather than appearing once, fully formed. This
reuses 100% of the existing reactivity path; nothing about it is
Agent-component-specific plumbing (`saveStreamDeltas`, `vStreamArgs`,
`syncStreams`, `listUIMessages` — all documented in
`docs/reference/convex-agent/streaming.md` — are **not used** here precisely
because they target the Agent's own client-facing query shape, which this app
deliberately isn't exposing).

**Known open question, explicitly flagged, not resolved here (client-side,
out of scope for this backend doc):** whether ExyteChat's message list
diffing handles a message's `text` mutating in place smoothly (vs. only
appending pre-fixed messages) is untested. If it doesn't animate well, the
fallback is simply increasing `THROTTLE_MS` toward "patch once at the end"
(i.e. non-streaming UX, full response appears when ready) — a one-line
change, not an architecture change.

## 5. LLM provider

`@ai-sdk/openai`, per `docs/reference/convex-agent/getting-started.md`'s own
example (`openai.chat("gpt-4o-mini")`). `convex/agents/companion.ts`:

```ts
"use node";
import { Agent } from "@convex-dev/agent";
import { openai } from "@ai-sdk/openai";
import { components } from "../_generated/api";

export const companionAgent = new Agent(components.agent, {
  name: "Companion",
  languageModel: openai.chat(process.env.COMPANION_MODEL ?? "gpt-4o-mini"),
  embeddingModel: openai.embedding("text-embedding-3-small"), // enables hybrid search over thread history
  instructions: "…", // TODO: real companion persona
  // TODO(mem0): contextHandler hook point — see §8
  // TODO: usageHandler — see §7
});
```

Swapping models (including to Anthropic/Google) later is a one-line change to
`languageModel` via a different `@ai-sdk/*` package — this is the concrete
payoff of using the Agent component (built on Vercel AI SDK) instead of
calling the OpenAI SDK directly, per the earlier session research.

## 6. Environment / secrets

```
npx convex env set OPENAI_API_KEY sk-...
npx convex env set COMPANION_MODEL gpt-4o-mini   # optional override, read via process.env above
```

`@ai-sdk/openai` reads `OPENAI_API_KEY` from the environment by its own
convention — no explicit key-passing needed in code. Both actions/agent files
need `"use node"` (Node.js Convex runtime) since the AI SDK and `@convex-dev/agent`
are not built for the restricted default V8 action runtime — confirmed
implicitly by every pulled example importing `ai`/`@ai-sdk/openai` inside
files that are otherwise plain Node-style TypeScript with no V8-runtime
restrictions called out; treat `"use node"` as required unless proven
otherwise when implementing.

## 7. Rate limiting

Per `docs/reference/convex-agent/rate-limiting.md` and
`docs/reference/rate-limiter/overview.md`. `convex/rateLimiting.ts`:

```ts
import { MINUTE, RateLimiter, SECOND } from "@convex-dev/rate-limiter";
import { components } from "./_generated/api";

export const rateLimiter = new RateLimiter(components.rateLimiter, {
  sendMessage: { kind: "fixed window", period: 5 * SECOND, rate: 1, capacity: 2 },
  tokenUsagePerUser: { kind: "token bucket", period: MINUTE, rate: 2000, capacity: 10000 },
});
```

In `messages.send`, before scheduling `internal.ai.generateReply`:

```ts
await rateLimiter.limit(ctx, "sendMessage", { key: viewer._id, throws: true });
```

In `companionAgent`'s `usageHandler` (§5), after generation:

```ts
usageHandler: async (ctx, { usage, userId }) => {
  if (!userId) return;
  await rateLimiter.limit(ctx, "tokenUsagePerUser", { key: userId, count: usage.totalTokens, reserve: true });
},
```

This is a companion app real users will message repeatedly — per-user
message-frequency limiting prevents accidental spam loops (e.g. a retry bug
on the client) and the token-bucket usage limit bounds runaway API cost per
user without a hard wall on any single request. A global limit
(`globalSendMessage`/`globalTokenUsage` in the doc's example) is deferred
until there's a real multi-tenant cost-ceiling concern — not needed to ship
v1.

## 8. mem0 hook point (designed, not implemented)

Per the earlier session's research into Tolan's architecture (rebuilds full
context every message from persona + retrieved memories, not a growing
transcript) and mem0's Node SDK (`mem0ai`, `MemoryClient.add()`/`.search()`),
the exact seam is the Agent's **`contextHandler`**
(`docs/reference/convex-agent/context.md`) — the one place the docs
explicitly describe as the hook for "fetch memories and add them to context":

```ts
// convex/agents/companion.ts — future, not implemented now
import { MemoryClient } from "mem0ai";
const mem0 = new MemoryClient({ apiKey: process.env.MEM0_API_KEY! });

export const companionAgent = new Agent(components.agent, {
  // ...
  contextHandler: async (ctx, args) => {
    // TODO(mem0): const memories = await mem0.search(args.inputPrompt text, { user_id: args.userId });
    // TODO(mem0): return [...memoriesAsMessages, ...args.allMessages];
    return args.allMessages; // current no-op default
  },
});
```

And a second, symmetric hook in `ai.ts`'s `generateReply`, after the final
patch — adding the completed turn to mem0 so future turns can retrieve it:

```ts
// convex/ai.ts — future, not implemented now
// TODO(mem0): await mem0.add([{ role: "user", content: prompt }, { role: "assistant", content: text }], { user_id: ... });
```

Building today's pipeline with this `contextHandler` already present (even as
a no-op) means mem0 integration later is additive — no restructuring of the
generation pipeline, matching the "build so mem0 slots in cleanly" goal.

## 9. Authorization

> Implementation amendment (2026-08-22): the original text below correctly
> describes the public authorization boundary, but its claim that a check made
> "seconds earlier" is sufficient for scheduled streaming work is wrong once
> deletion and concurrent retries are possible. The implementation therefore
> persists a `generationTurns` record. Each internal write verifies the active
> attempt lease and the continued existence of both the conversation and the
> assistant message; conversation deletion cancels active turns first. This is
> a correction prompted by the real code audit, not a change to the bridge
> architecture or to its public authorization pattern.

`messages.send` already calls `requireCurrentUser` + `requireMembership`
before doing anything (`convex/messages.ts`, unchanged) — this gate runs
**before** the new `getOrCreateAgentThreadId`/schedule call, so an
unauthenticated or non-member request never reaches the Agent at all, exactly
matching this codebase's existing pattern (`model/conversations.ts`'s
`requireMembership` is "the server-side replacement for … a client-side
filter").

The three new internal functions (`internal.ai.generateReply`,
`insertAssistantPlaceholder`, `patchAssistantText`) are Convex
`internalAction`/`internalMutation` — **not reachable by any client**, by
Convex's own internal-function convention (same guarantee this codebase
already relies on nowhere else needing an explicit re-check, since
`internal.*` functions are only callable from other server-side code). They
receive `conversationId`/`threadId` only as values the calling mutation
already validated seconds earlier via `requireMembership` — there is no
client-supplied-id trust boundary being crossed here, so no additional
ownership check is needed inside them. This mirrors the existing codebase's
own reasoning for why `deleteConversation`'s internals don't re-check
membership either (`model/conversations.ts`) — the check happens once, at the
one point a client-supplied id enters the system.

## 10. Build order checklist

1. `npm install @convex-dev/agent @ai-sdk/openai ai @convex-dev/rate-limiter` in `convex-backend/`.
2. Edit `convex/convex.config.ts` — add `app.use(agent)`.
3. Edit `convex/schema.ts` — add `agentThreadId` to `conversations`.
4. Run `npx convex dev` once to generate component code (required before referencing `components.agent` anywhere — per `docs/reference/convex-agent/getting-started.md`).
5. `npx convex env set OPENAI_API_KEY ...` (get a key first).
6. Add `model/users.ts`'s `getOrCreateCompanionUser`.
7. Add `convex/agents/companion.ts` (Agent definition, `"use node"`).
8. Add `model/conversations.ts`'s `getOrCreateAgentThreadId`.
9. Add `model/messages.ts`'s `insertAssistantPlaceholder`/`patchAssistantText`.
10. Add `convex/ai.ts`'s `generateReply` internalAction (`"use node"`).
11. Modify `messages.ts`'s `send` mutation to call `getOrCreateAgentThreadId` + `ctx.scheduler.runAfter(0, internal.ai.generateReply, ...)`.
12. Add `convex/rateLimiting.ts`, wire `rateLimiter.limit` into `messages.send` and `usageHandler` into the agent.
13. `npx convex dev` / manually send a test message from the iOS app and confirm an assistant reply appears with no client changes.
14. Run `npx convex run` or the app itself to verify streaming (`text` field visibly growing) — adjust `THROTTLE_MS` per §4's open question if it looks wrong on the client.
15. Typecheck (`npm run typecheck` per `package.json`) and run the existing `convex-authz`/`convex-reviewer` skills against the new functions before considering this done.
