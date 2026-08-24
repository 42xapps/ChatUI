# Components considered and NOT adopted

Per the coordinator's instruction to only pull docs for components with a
concrete justification either way — these were checked and explicitly
rejected for this app's v1 LLM integration.

## `@convex-dev/persistent-text-streaming`

https://www.convex.dev/components/persistent-text-streaming —
"Stream AI-generated text to users in real-time while automatically
persisting it to your Convex database."

**Not adopted: redundant with `@convex-dev/agent`'s own streaming.** The Agent
component's `saveStreamDeltas` (see `convex-agent/streaming.md`) already does
exactly this — chunks a `streamText` response into deltas, persists them, and
lets clients subscribe reactively — as a built-in feature of the component
we're already installing. Adding this second component would mean two
separate streaming/persistence mechanisms with no distinct benefit. Only
reconsider if a future feature needs to stream some *non-agent* generated
text (e.g. a plain templated response with no LLM call) through the same
reactive-delta mechanism.

## `@convex-dev/workflow`

Referenced from `convex-agent/agent-usage.md`'s "async generation" pattern
and `convex-agent/workflows.md` (not deep-fetched — see
`convex-agent/overview.md`'s sub-page index) as the recommended way to
orchestrate long-lived, multi-step, durably-retried agent workflows (e.g. an
agent that calls several tools across multiple actions with a workflow
manager coordinating retries/step state).

**Not adopted for v1.** This app's initial LLM integration is a single
request → single response turn (see architecture doc's "core integration
decision") with no multi-step tool-calling loop planned yet. The Agent
component's own `ctx.scheduler.runAfter` + `internalAction` pattern (see
`convex-agent/agent-usage.md`'s "RECOMMENDED" section) is sufficient durability
for that. Reconsider if/when the companion needs a genuine multi-step
background job (e.g. a scheduled proactive check-in, or a tool-calling loop
spanning several actions) — at that point `agents/workflows.md` should be
deep-fetched and this decision revisited.

## `@convex-dev/rag`

https://www.convex.dev/components/rag — general external-knowledge-base RAG
(chunking + embeddings + namespaces).

**Not adopted for v1.** This app has no external knowledge base to search
(no documents/FAQ/help-center content) — see `convex-agent/rag.md`. The
Agent's own built-in hybrid text/vector search over thread history is the
only "search" this app needs today. mem0 (planned future work, kept as a
distinct future integration — see architecture doc) plays a different role
than this component (personal-fact memory, not a document knowledge base).
