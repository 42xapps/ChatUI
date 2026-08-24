# Current companion-chat implementation

Status: current implementation brief as of 2026-08-23.

Audience: an architect or coding agent evaluating future companion, persona,
Mem0, or multi-bubble work. Read this before proposing schema or runtime
changes. If this document conflicts with the current source, the source wins.

This document describes what is actually built. It is not a request to replace
the architecture, and it does not independently validate claims about Tolan,
Mem0 Platform, or the OpenAI Agents SDK.

## Executive correction to the proposed architecture

The proposed architecture starts from one incorrect premise: it assumes the
repository has only a generic Convex chat backend and that adding the OpenAI
Agents SDK would avoid introducing a second owner of chat state.

The repository already has a deliberate bridge architecture:

- The application-owned `messages` table is the only chat source of truth the
  iOS client reads.
- `generationTurns` is the durable orchestration state machine for model work.
- The `@convex-dev/agent` component is internal-only short-term LLM context and
  history. No client reads its messages or streaming APIs.
- Vercel AI SDK provider adapters perform model calls. The server currently
  selects Google Gemini 3.7 Flash and can allowlist OpenAI, Google, DeepSeek,
  Moonshot/Kimi, or Qwen models.
- Long-term semantic memory is not implemented. The Agent `contextHandler`
  already contains an explicit `TODO(mem0)` insertion point.

Consequently, "remove Convex Agent and add OpenAI Agents SDK" is not a small
simplification of this codebase. It is a runtime and context-storage migration.
It should happen only after a specific, measured benefit justifies replacing a
working provider-neutral integration—not because the current Agent component
is presumed to own client chat state. It does not.

## Repository map and terminology

The backend is:

```text
/Users/bousttamohamed/Developer/tmp/ChatUI/convex-backend
```

The iOS application consuming it is:

```text
/Users/bousttamohamed/Downloads/IAM-Self-Affirmations
```

The app calls a chat thread a `conversation`, not a `thread`. `threadId` in
this repository normally means an internal Agent component thread.

Important source files:

| Concern | Current source |
| --- | --- |
| Schema | `convex/schema.ts` |
| Public message API | `convex/messages.ts` |
| Generation action | `convex/ai.ts` |
| Provider registry, persona, context budget | `convex/agents/companion.ts` |
| Turn state machine, leases, retry | `convex/model/generationTurns.ts` |
| Conversation lifecycle and deletion | `convex/model/conversations.ts` |
| Authentication-derived users | `convex/model/users.ts` |
| Upload ownership and R2 lifecycle | `convex/attachments.ts`, `convex/model/attachments.ts`, `convex/http.ts` |
| Rate limits | `convex/rateLimiting.ts` |
| Usage query | `convex/llmUsage.ts` |
| Backend tests | `convex/companion.test.ts` |
| iOS service contract | `ChatFeature/Sources/ChatFeature/Convex/ConvexService.swift` |
| iOS generation UI | `ChatFeature/Sources/ChatFeature/Conversation/ConversationView.swift` |
| iOS optimistic send/retry | `ChatFeature/Sources/ChatFeature/Conversation/ConversationViewModel.swift` |
| iOS server-model mapping | `ChatFeature/Sources/ChatFeature/Convex/ConvexMessageMapping.swift` |
| Streaming list diffing | `ChatUI/Sources/ExyteChat/Views/UIList+OperationsSplit.swift` and `UIList.swift` |
| Onboarding persistence | `PepGPT/Onboarding/Services/OnboardingPersistenceService.swift` |

Before changing Convex code, read `CLAUDE.md` and
`convex/_generated/ai/guidelines.md` in full. This project uses current Convex
table-name-first database signatures and component conventions that override
generic assumptions.

## Actual system ownership

```text
Native iOS / ExyteChat
  |
  | Clerk-authenticated Convex Swift calls and reactive subscriptions
  v
Application-owned Convex data
  - users
  - conversations + conversationMembers
  - messages                 <-- only client-facing chat truth
  - generationTurns          <-- orchestration truth
  - llmUsageEvents
  - mediaAssets
  |
  | scheduled internal action + lease-checked internal mutations
  v
Companion generation runtime
  - @convex-dev/agent         <-- internal recent context/history only
  - Vercel AI SDK             <-- streaming/provider abstraction
  - allowlisted provider adapter
  |
  v
Selected model provider

Future Mem0 seam:
  Agent contextHandler recall + a durable post-turn memory job
```

There are intentionally two copies of conversational text with different
responsibilities:

1. The application `messages` table is the durable product record: rich media,
   replies, ordering, client identity, generation state, and everything iOS
   renders.
2. The Agent component thread is an internal, replaceable short-term context
   projection used to construct model input.

That is not two client-visible sources of truth. The Agent component's
`listUIMessages`, `syncStreams`, `vStreamArgs`, and client streaming contract
are not used.

## Current data model

### `users`

One row per authenticated Clerk identity, keyed canonically by
`identity.tokenIdentifier` (`issuer|subject`). The raw Clerk subject is retained
as `clerkId` for Clerk API interoperability. A singleton synthetic user with
`tokenIdentifier = "system|companion"` and name `Embie` authors assistant
messages, preserving the existing sender shape in iOS.

There is no `companions` table. The current product has one global authored
character. Add a companion/configuration record only when a real per-user
persona/configuration requirement exists; do not add it merely to mirror a
greenfield diagram.

### `conversations` and `conversationMembers`

`conversations` contains the title, creator, recency, and internal
`agentThreadId`. Membership is explicit and indexed. The sidebar query is
bounded to 100 recent conversations and uses denormalized membership recency.

Creating a conversation also creates its Agent thread and a deterministic
assistant greeting:

```text
Hi, I’m Embie. What’s on your mind today?
```

### `messages`

This is an existing product-specific model, not a generic LLM transcript. It
contains:

- conversation-scoped client IDs and clock-skew-proof Convex ordering;
- sender identity and text;
- R2 image/video attachments and thumbnail keys;
- Giphy media IDs;
- voice recordings with duration and waveform samples;
- flattened reply relationships;
- assistant generation state, structured error, retry timing, and turn link.

Idempotency is intentionally `(conversationId, clientId)`. The same client ID
may be used in a different conversation without poisoning lookup. Do not change
this to a global client-ID lookup.

### `generationTurns`

The proposed `turns` table already exists in a more operationally complete
form. One row currently represents:

```text
one user message -> one provider execution -> one assistant message
```

It stores queued/generating/completed/failed/cancelled status, user and message
IDs, Agent prompt ID, provider/model snapshot, attempt count, not-before time,
attempt/lease identity, lifecycle timestamps, structured errors, and bounded
stream-patch/output counters.

The singular `assistantMessageId` is important: 1–5 assistant bubbles are not
implemented and are not a prompt-only change.

### `llmUsageEvents`

Completed turns append provider/model and input, output, total, cache, and
reasoning token counts. The authenticated `llmUsage.listMine` query exposes a
bounded account-scoped view without leaking internal user or turn IDs.

There is no hard-coded dollar cost because historical cost must be reconciled
against provider pricing/invoices effective at the time.

### `mediaAssets`

Every direct-to-R2 upload is server-keyed and bound to its user and
conversation. The send transaction claims the upload for exactly one message.
Unclaimed uploads expire and are deleted. Conversation deletion removes
tracked R2 objects. Downloads require a revocable, message-bound capability
before the HTTP route issues a short-lived R2 redirect; knowing an object key
alone is insufficient.

## Actual public API and authorization boundary

Client-callable functions are deliberately small:

```text
users.syncCurrentUser
conversations.listMine
conversations.create
conversations.remove
messages.listForConversation
messages.send
messages.retryGeneration
attachments.requestUploadUrl
llmUsage.listMine
```

Clerk authentication is bridged to Convex with `ClerkConvexAuthProvider` and
an `aud: convex` token accepted by `convex/auth.config.ts`.

Every public function touching account, conversation, message, upload, or
usage data derives the caller from `ctx.auth`, loads the indexed user row, and
checks conversation membership where applicable. No public API accepts a
client-supplied user ID as authority.

Internal generation functions are not client-callable. Their writes are still
not based only on stale authorization from the original send: every stream
patch/finalization checks the active attempt lease and verifies that the
conversation and assistant row continue to exist. This closes the scheduled
generation-versus-deletion race.

For future Mem0 scoping, do not blindly use a client argument or assume a raw
Clerk `sub` is globally canonical. Derive an opaque scope server-side from the
authenticated Convex user (for example, a namespaced `users._id`) or from the
issuer-aware `tokenIdentifier`. Use environment-specific application scope so
development and production memories cannot mix.

## Actual send and generation path

`messages.send` is one transaction that:

1. Authenticates the Clerk-backed user and verifies membership.
2. Validates text/media bounds.
3. Returns the existing result for a duplicate `(conversationId, clientId)`
   before consuming rate-limit admission again.
4. Checks and consumes per-user/global message and token admission.
5. Inserts the user message.
6. Atomically proves and claims all uploaded media ownership.
7. Creates/loads the internal Agent thread and pre-saves the prompt.
8. Inserts an empty assistant placeholder with `queued` state.
9. Inserts the `generationTurns` row and links the placeholder to it.
10. Updates title/recency and schedules the internal queue processor.

`ai.processConversationQueue` then:

1. Builds the selected, allowlisted provider runtime from server environment.
2. Claims the oldest runnable turn for that conversation.
3. Enforces one active generation per conversation and at most eight globally.
4. Assigns a 90-second attempt lease and schedules a recovery watchdog.
5. Builds provider-neutral multimodal input for supported images/GIFs.
6. Streams through `@convex-dev/agent` and the Vercel AI SDK.
7. Patches the same assistant message approximately every 250 ms.
8. Verifies the lease on every patch and final write.
9. Completes the turn and writes usage, or classifies and persists failure.
10. Schedules the next conversation turn.

This queue serializes rapid user sends in one conversation. A second message
does not run concurrently against the same Agent thread.

## Retry, failure, timeout, and cancellation behavior

- Model SDK retries are disabled at the call boundary (`maxRetries: 0`).
- Provider billing/auth/configuration failures are terminal after one attempt.
- Only classified transient failures before any streamed output are
  automatically requeued, with bounded backoff and at most three attempts.
- A partial-stream interruption preserves the visible partial text and becomes
  a structured failed row instead of silently replaying/overwriting it.
- A 60-second generation timeout aborts the provider stream.
- Expired leases can be reclaimed; stale attempts cannot patch current rows.
- The iOS retry action reuses the original user prompt and assistant message
  identity.
- Conversation deletion cancels queued/running turns and invalidates leases.

There is not yet a public `cancelTurn` mutation or iOS Stop button. Current
cancellation protects deletion and stale work; user-initiated cancellation is
a separate product addition.

## Provider/runtime reality

The repository does not contain the OpenAI Agents SDK. It currently declares:

- `@convex-dev/agent` for internal context/thread handling;
- Vercel `ai` for streaming and usage;
- AI SDK adapters for OpenAI, Google, DeepSeek, Moonshot, and
  OpenAI-compatible Qwen;
- `@convex-dev/rate-limiter` and `@convex-dev/r2` Convex components.

Provider/model selection is never supplied by iOS. `COMPANION_PROVIDER` and
`COMPANION_MODEL` are server-only, allowlisted deployment settings. The
development deployment currently selects:

```text
COMPANION_PROVIDER=google
COMPANION_MODEL=gemini-3.7-flash
```

The real Google key reached that exact model, but the linked Google project's
prepayment balance is depleted. A successful reply and visible growing stream
therefore remain unverified. Do not interpret the valid key or a typechecked
adapter as a successful provider integration test.

Replacing this runtime with the OpenAI Agents SDK would need answers to these
questions first:

1. What concrete missing capability requires the migration?
2. How will Gemini and the other allowlisted non-OpenAI providers remain first
   class?
3. What replaces Agent component prompt/output persistence and deletion?
4. How are existing attempt leases, classified retry, timeout, usage, and
   multimodal behavior preserved?
5. What measured quality, latency, reliability, or maintenance improvement
   justifies the migration risk?

"One Agent SDK instead of two" is not itself an answer because only one agent
runtime owns execution today; Convex Agent does not own the product chat API.

## Context, persona, and memory reality

The current Agent:

- has one authored Embie prompt in source code;
- bounds output to 600 tokens and a request to 60 seconds;
- considers at most 40 recent internal Agent messages;
- applies a provider-neutral 24,000-character context budget;
- disables vector search, text retrieval, embeddings, tools, and
  cross-thread search;
- has a `contextHandler` that reconstructs bounded recent input each turn;
- contains an explicit `TODO(mem0)` recall seam.

It does not yet have:

- Mem0 or any other long-term learned memory;
- memory write jobs, receipts, confirmation polling, or deletion tombstones;
- onboarding memory ingestion;
- recall-query planning or tone interpretation;
- persona modules/versions or a `personaVersion` turn snapshot;
- programmable safety guardrails or behavioral evaluation datasets.

The proposal's separation of authored persona, recent conversation, retrieved
memory, and current tone is compatible with this system. It should be added
inside the existing context boundary, not used as a reason to discard the
turn/message bridge.

If Mem0 Platform is adopted, Convex should still own operational memory state:
consent/version, durable jobs, provider event IDs, attempts, confirmation,
failures, deletion tombstones, and audit timestamps. Mem0 may own learned
semantic memory content without becoming an untracked external side effect.

## Onboarding and privacy reality

The proposal assumes onboarding data is already available to the backend. It
is not.

The complete onboarding snapshot—including free-form answers and
demographics—is persisted locally in `UserDefaults`. The current code states
that local storage is the source of truth until a provider-neutral profile
repository gains a remote implementation. `cloudAnswers(from:)` deliberately
returns only stable option IDs; free-form answers remain local-only.

Therefore, onboarding-to-Mem0 requires a product/privacy decision and a real
contract:

- explicit user disclosure/consent for sending personalization data;
- an allowlist of fields and stable answer IDs;
- an explicit decision about whether any free text may leave the device;
- Swift DTOs and an authenticated Convex sync mutation;
- versioning, idempotency, revocation, and deletion behavior;
- analytics and logs that never capture private text.

Do not silently upload the current local snapshot or infer memories from fields
the user did not provide.

## iOS and streaming reality

The iOS client has already been changed for companion generation:

- It subscribes reactively to `messages.listForConversation`.
- It renders queued and generating empty placeholders as an Embie thinking row.
- It renders typed failures separately from assistant prose.
- Retry preserves assistant identity and shows retry-after countdowns.
- Outgoing retries preserve the stable client ID and already-uploaded media.
- Rate-limit results become user-facing notices, not raw server errors.
- ExyteChat classifies text/status growth as `editStreaming`, reconfigures the
  existing row, and animates its self-sizing height.
- A deterministic test verifies the streamed-text/status diff classification.
- The live window grows in one reactive subscription from 100 up to 1,000
  messages, avoiding stale cursor stitching.

What is still missing is empirical provider-funded verification of growing
text, bottom pinning, scrolling, and row-height animation during a real stream.
The implementation path exists; the visual result is not yet proven.

## Rich-media reality

Images and Giphy media are passed to vision-capable providers. Unsupported
providers receive only honest textual context and never pretend to have seen
the media. Videos are persisted/rendered but not understood by the model.
Voice recordings are persisted/rendered but not transcribed; the prompt tells
the companion not to pretend it heard them.

Any replacement `Message` type or generic chat abstraction must preserve R2
ownership, thumbnails, Giphy, recordings/waveforms, replies, stable client
identity, and Convex commit-time ordering. A simplified text-only message
schema would be a regression.

## Deletion reality

Conversation deletion is implemented and bounded. It cancels active turns,
deletes the internal Agent thread, and removes usage events, generation turns,
messages, memberships, tracked R2 objects, and finally the conversation in
continuation batches.

End-to-end account deletion is not implemented. There is no app-owned durable
workflow that coordinates Convex account data, future Mem0 data, and Clerk.
The current profile has sign-out and Clerk's account UI, but that is not proof
of a cross-system deletion guarantee.

When added, account deletion must be idempotent and resumable. A naive
`delete Mem0 -> delete Convex -> delete Clerk` action can stop halfway because
external work is not transactional. Persist deletion state/tombstones before
external calls and make every step retry-safe.

## Rate limiting and scale reality

Already implemented:

- per-user message admission: one per five seconds, burst capacity two;
- global message token bucket: 60/minute refill, capacity 15;
- per-user estimated-token bucket: 30,000/minute refill, capacity 60,000;
- global estimated-token bucket: 300,000/minute refill, capacity 600,000;
- at most one active generation per conversation;
- at most eight active generations globally.

These are safety bounds, not evidence of 10,000-DAU readiness. There has been
no funded provider load test, capacity model, queue-latency SLO validation, or
provider-quota rehearsal at that scale. The global concurrency value is a
launch control that must be tuned from real latency, quota, and cost data.

## Proposal-to-reality matrix

| Proposed item | Current verdict |
| --- | --- |
| Existing Convex auth/chat/multiple threads | Already built; real name is conversations. |
| Add a turn model | Already built as `generationTurns`, with leases/retry/usage links. Extend it; do not replace it. |
| Add stream state/deltas | State is already on messages/turns; full text is patched every 250 ms. No delta table is currently needed. |
| Add usage | Already built as append-only `llmUsageEvents`; TTFT and memory latency remain additions. |
| Add a companions table | Not currently justified for one global Embie persona. Reconsider when per-user companion config/version is real. |
| Do not use Convex Agent | Conflicts with the implemented bridge and is based on a false ownership assumption. This would be a migration. |
| Use one companion agent | Already true conceptually. There is one companion Agent configuration, created at action runtime for the selected provider. |
| Do not use OpenAI Sessions | Already true; the OpenAI Agents SDK is not installed. |
| Reconstruct context every turn | Partly built: bounded recent Agent context plus current input. Mem0/persona/tone reconstruction remains. |
| Recent conversation from Convex | Product messages are canonical, while the internal Agent thread is the current context projection. Switching the source requires a reconciliation/migration plan. |
| Mem0 Platform long-term memory | Compatible future work; not installed or configured. Requires durable jobs, privacy, deletion, and evals. |
| Onboarding to Mem0 | Blocked on an intentional local-only privacy boundary and missing sync contract. |
| 1–5 assistant bubbles | Not built. Current schema and retry UI model one assistant row per turn. Requires an explicit cross-backend/iOS migration. |
| Thinking indicator | Already built. |
| Typed retry/failure UX | Already built, including retry-after and stable identity. |
| User Stop/cancellation | Not built. Internal cancellation exists for deletion/leases only. |
| Basic/global rate limits | Already built, including global token and concurrency ceilings. |
| Image/GIF understanding | Already built for vision-capable providers. Voice transcription/video understanding remain deferred. |
| Idempotent messages | Already built as `(conversationId, clientId)` before rate-limit consumption. |
| Initial greeting | Already built deterministically. |
| Generated titles | Not built; title is deterministically derived from the first message/media kind. |
| Account deletion | Not built end to end. Conversation deletion is built. |
| OpenAI tracing/Runner reuse | Not applicable to the current Vercel AI SDK runtime. Any adoption belongs to an explicit SDK migration. |
| 10k DAU target | A target only; not verified. |

## How to approach the compatible future work

If the intended next milestone is persona + Mem0 + conversational pacing,
preserve the current bridge and evolve it in this order:

1. Define memory privacy, consent, retention, deletion, and stable server-side
   scope before sending any data to Mem0.
2. Add a durable `memoryJobs` state machine and Mem0 repository at the existing
   context/post-turn seams. Do not make the visible reply wait for memory
   ingestion.
3. Version the authored persona in code and snapshot `personaVersion` on each
   generation turn for reproducibility.
4. Add a small, evaluated turn-signal/recall planner only if it improves a
   fixed memory-recall dataset enough to justify its latency and token cost.
5. Add TTFT, memory-search latency/count, and final latency to the existing
   usage/turn records.
6. Decide whether 1–5 bubbles are a launch requirement. If yes, first evolve
   `generationTurns` from a singular assistant ID to an ordered set, then add a
   chunk-boundary-safe parser and iOS tests. Do not ship a delimiter-only prompt
   against the current singular schema.
7. Add user-initiated Stop with an authorized public mutation, durable
   cancelled state, lease invalidation, and best-effort provider abort.
8. Build resumable account deletion across Convex, Mem0, and Clerk.
9. Run persona, memory, safety, privacy, deletion, load, and funded-provider
   integration evaluations before describing the system as production-ready.

The proposed large folder tree should be applied only as code is added. The
current implementation is already separated by responsibility:

```text
messages.ts                    public transactional chat mechanics
ai.ts                          external generation orchestration
agents/companion.ts            model/provider/context/persona configuration
model/generationTurns.ts       durable state machine
model/conversations.ts         conversation lifecycle
model/attachments.ts           media ownership/lifecycle
rateLimiting.ts                admission policy
llmUsage.ts                    account-scoped usage reporting
```

Do not perform a broad file reorganization just to match a proposed tree. Add
`persona/`, `memory/`, or `context/` modules when those implementations become
large enough to earn the boundary.

## Current verification and blocker

The current development target is:

```text
dev:exciting-vulture-777
team: mo-san
project: embie-backend
```

The latest recorded verification in this repository:

- backend TypeScript typecheck passed;
- eleven deterministic Convex companion tests passed;
- ExyteChat streaming-operation tests passed;
- an arm64 iOS Simulator build passed;
- a real iOS failure flow reached the selected Google Gemini 3.7 Flash model;
- provider billing failure was classified into a structured, non-prose row;
- permanent billing failure made one provider request after retry hardening;
- deployment changes were applied only to the existing development deployment.

Still unverified and blocking a successful-chat verdict:

- any completed reply from a funded model provider;
- text growth across successive live reads;
- real streamed row height, bottom pinning, and scrolling in the Simulator;
- real provider usage ledger data from a completed Gemini turn;
- provider-scale behavior or 10k-DAU capacity.

The Google API secret must never be copied into documentation, source control,
logs, prompts, or client code.

## Constraints for the next architect or coding agent

1. Treat current code as source of truth and preserve unrelated dirty-worktree
   changes.
2. Preserve the application `messages` table as the sole iOS chat source unless
   the user explicitly authorizes a client/backend migration.
3. Do not remove Convex Agent merely to make the diagram look simpler.
4. Do not add the OpenAI Agents SDK without a provider-neutral migration and
   evidence that it improves this implementation.
5. Never trust a client-supplied user ID, provider, model, R2 key, or Mem0
   scope.
6. Do not export local onboarding free text without explicit privacy/product
   approval and a reviewed contract.
7. Extend the existing generation state machine rather than bypassing it with
   an action that streams directly into messages.
8. Do not treat successful typecheck, a valid key, or a failure response as
   proof of successful generation or streaming.
9. Work against the existing development deployment with `npx convex dev`;
   do not run `npx convex deploy` as part of development work.
10. State exactly what was tested and keep all provider-funded/live gaps
    explicit.

