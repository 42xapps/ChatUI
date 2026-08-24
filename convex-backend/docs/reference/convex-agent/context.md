<!-- Source: https://docs.convex.dev/agents/context.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1 -->

# LLM Context

By default the Agent provides context from the thread's message history:
recent messages, plus messages found via text/vector search. If a
`promptMessageId` is provided, context includes that message and any other
messages at the same `order` (see messages.md).

## Customizing context (`contextOptions`)

Settable as Agent defaults or per call-site:

```ts
const result = await agent.generateText(ctx, { threadId }, { prompt }, {
  contextOptions: { // values shown are defaults
    excludeToolMessages: true,
    recentMessages: 100,
    searchOptions: {
      limit: 10,
      textSearch: false,
      vectorSearch: false,
      messageRange: { before: 2, after: 1 }, // applied after limit
    },
    searchOtherThreads: false, // search across the user's other threads too
  },
});
```

## Full context control

Two ways:

1. **`contextHandler`** — filter/modify/enrich context messages. Settable on
   the Agent constructor or per call-site (overrides Agent default):

```ts
const myAgent = new Agent(components.agent, {
  contextHandler: async (ctx, args) => {
    // default behavior:
    return [...args.search, ...args.recent, ...args.inputMessages, ...args.inputPrompt, ...args.existingResponses];
    // equivalent to: return args.allMessages;
  },
});
```

Use cases: filter irrelevant messages, inject fetched "memories", add sample
messages to steer style, inject user/thread-specific context, copy messages
from other threads, summarize long context. Example combining several:

```ts
contextHandler: async (ctx, args) => {
  const relevantSearch = args.search.filter((m) => messageIsRelevant(m));
  const userMemories = await getUserMemories(ctx, args.userId);
  const userContext = await getUserContext(ctx, args.userId, args.threadId);
  const related = await getRelatedThreadMessages(ctx, args.threadId);
  return [
    ...(await summarizeOrTruncateIfTooLong(related)),
    ...relevantSearch,
    ...userMemories,
    ...userContext,
    ...args.recent,
    ...args.inputMessages,
    ...args.inputPrompt,
    ...args.existingResponses,
  ];
},
```

  **This `contextHandler` is the concrete hook point for injecting mem0
  results into the prompt later** — see the architecture doc's mem0 section.

2. **Provide all messages manually** via the `messages` argument, with
   `contextOptions` set to use no recent/search messages.

### Fetch context manually (no LLM call)

```ts
import { fetchContextWithPrompt } from "@convex-dev/agent";
const { messages } = await fetchContextWithPrompt(ctx, components.agent, {
  prompt, messages, promptMessageId, userId, threadId, contextOptions,
});
```

### Search for messages manually

```ts
const messages: MessageDoc[] = await agent.fetchContextMessages(ctx, {
  threadId,
  searchText: prompt, // optional, needed for text/vector search
  targetMessageId: promptMessageId, // optional; scopes search to before this message
  userId, // optional unless searchOtherThreads is true
  contextOptions,
});
```

Without an Agent instance (must supply your own embeddings, and it will not
run your usage handler): `fetchRecentAndSearchMessages(ctx, components.agent, { threadId, searchText, targetMessageId, contextOptions, getEmbedding })`.

## Searching other threads

`searchOtherThreads: true` searches across all of the given `userId`'s
threads (hybrid text + vector search) — useful for cross-conversation
reference within the Agent component itself (distinct from mem0's
cross-session distilled-fact memory — see architecture doc).

## Passing in messages as context (RAG)

Final message order sent to the LLM:
1. System prompt (explicit or Agent's `instructions`)
2. Messages found via `contextOptions`
3. The `messages` argument passed to `generateText`/etc.
4. If a `prompt` string was given, a final `{ role: "user", content: prompt }`.

Messages passed this way are NOT saved to thread history automatically unless
requested.

## Managing embeddings manually

`textEmbeddingModel` on the Agent constructor enables auto-embedding for
vector search. Manual helpers: `embedMessages(...)`,
`agent.generateAndSaveEmbeddings(ctx, { messageIds })`, plus low-level
`components.agent.vector.index.{paginate,updateBatch,deleteBatch,insertBatch}`
for migrations between embedding models.
