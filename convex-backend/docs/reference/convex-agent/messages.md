<!-- Source: https://docs.convex.dev/agents/messages.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1 -->

# Messages

The Agent component stores message and thread history to enable conversations
between humans and agents.

## Retrieving messages

For clients to show messages, expose a query that returns the messages. For
streaming, see `retrieving streamed deltas` in streaming.md for a modified
version of this query.

Example: https://github.com/get-convex/agent/blob/main/example/convex/chat/basic.ts
Streaming example: https://github.com/get-convex/agent/blob/main/example/convex/chat/streaming.ts

```ts
import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import { listUIMessages } from "@convex-dev/agent";
import { components } from "./_generated/api";

export const listThreadMessages = query({
  args: { threadId: v.string(), paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    await authorizeThreadAccess(ctx, threadId);
    const paginated = await listUIMessages(ctx, components.agent, args);
    // Here you could filter out / modify the documents
    return paginated;
  },
});
```

`listUIMessages` returns UIMessages (Agent extension with extra fields like
order/status). `listMessages` returns raw MessageDocs instead.

## Showing messages in React

`useUIMessages` hook (pass `stream: true` for streaming):

```tsx
import { api } from "../convex/_generated/api";
import { useUIMessages } from "@convex-dev/agent/react";

function MyComponent({ threadId }: { threadId: string }) {
  const { results, status, loadMore } = useUIMessages(
    api.chat.streaming.listMessages,
    { threadId },
    { initialNumItems: 10 /* stream: true */ },
  );
  return (
    <div>
      {results.map((message) => (
        <div key={message.key}>{message.text}</div>
      ))}
    </div>
  );
}
```

(For MessageDocs, use the older `useThreadMessages` hook instead.)

### UIMessage type

Extends AI SDK's `UIMessage` (`parts`, `content`, `role`) with:
`key`, `order`, `stepOrder`, `status` (or `"streaming"`), `agentName`, `text`,
`_creationTime` (for streaming messages this is currently the client's current
time).

`toUIMessages` helper transforms MessageDocs into UIMessages.

### Optimistic updates for sending messages

```ts
const sendMessage = useMutation(
  api.streaming.streamStoryAsynchronously,
).withOptimisticUpdate(
  optimisticallySendMessage(api.streaming.listThreadMessages),
);
```

## Saving messages

By default the Agent saves messages to the database automatically when
provided as a prompt, plus all generated messages. It's useful to save the
prompt message ahead of time and use `promptMessageId` to continue the
conversation (see agent-usage.md's "async" pattern).

```ts
const { messageId } = await saveMessage(ctx, components.agent, {
  threadId,
  userId,
  message: { role: "user", content: "The user message" },
});
```

Note: when calling `agent.generateText` with a raw prompt, embeddings are
generated automatically for vector search (if a text embedding model is
configured). Similarly with `agent.saveMessage` from an action. If saving in a
mutation (no LLM calls possible), pass `skipEmbeddings: true` — embeddings
will be generated lazily when the message is used as a prompt (or generate
explicitly via `agent.generateEmbeddings`).

### Configuring storage of messages

```ts
const result = await thread.generateText({ messages }, {
  storageOptions: {
    saveMessages: "all" | "none" | "promptAndOutput", // default: promptAndOutput
  },
});
```

Use-case for `"none"`/partial saving: passing extra context messages (e.g.
from RAG) that shouldn't be persisted, only the user's actual message.

## Message ordering

Each message has `order` and `stepOrder` fields — incrementing integers
specific to a thread. `saveMessage`/`generateText` adds the message at the
next `order` with `stepOrder: 0`. Response message(s) generated in reply are
added at the SAME `order` with incrementing `stepOrder`. Pass `promptMessageId`
to associate a response with a specific earlier message; if it's not the
latest message in the thread, context will NOT include anything after it
(useful for regenerating an earlier response).

## Deleting messages

By ID: `agent.deleteMessage(ctx, { messageId })` / `agent.deleteMessages(ctx, { messageIds })`.

By order range (start inclusive, end exclusive):
`agent.deleteMessageRange(ctx, { threadId, startOrder, endOrder })`.

## Other utilities (from `@convex-dev/agent`)

- `serializeDataOrUrl` — serializes AI SDK `DataContent`/`URL` to Convex-serializable format.
- `filterOutOrphanedToolMessages` — filters tool-call messages missing a result.
- `extractText` — extracts text from a `ModelMessage`-like object.
- `vMessage` — validator for a `ModelMessage`-like object.
- `MessageDoc` / `vMessageDoc` — message doc type/validator.
- `Thread` — type of thread returned from `continueThread`/`createThread`.
- `ThreadDoc` / `vThreadDoc` — thread metadata type/validator.
- `AgentComponent` — type of `components.agent`.
- `ToolCtx` — the `ctx` type for `createTool` handlers.
