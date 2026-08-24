<!-- Source: https://docs.convex.dev/agents/streaming.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1 -->

# Streaming

With the Agent component you can stream messages asynchronously — generation
doesn't have to happen in an HTTP handler, and the response streams back to
one or more clients even if their network connection is interrupted. It works
by saving streaming parts to the database in groups (deltas); clients
subscribe to new deltas for the thread via normal Convex reactive queries.

Example: server https://github.com/get-convex/agent/blob/main/example/convex/chat/streaming.ts,
client https://github.com/get-convex/agent/blob/main/example/ui/chat/ChatStreaming.tsx

## Streaming message deltas

```ts
agent.streamText(ctx, { threadId }, { prompt }, { saveStreamDeltas: true });
```

Chunking/debounce config:

```ts
{ saveStreamDeltas: { chunking: "line", throttleMs: 1000 } }
```

- `chunking`: `"word"`, `"line"`, a regex, or a custom function.
- `throttleMs`: how frequently deltas are saved (single-flighted — will not
  write faster than this even if multiple chunks are ready).

## Retrieving streamed deltas

```ts
import { paginationOptsValidator } from "convex/server";
import { vStreamArgs, listUIMessages, syncStreams } from "@convex-dev/agent";
import { components } from "./_generated/api";

export const listThreadMessages = query({
  args: {
    threadId: v.string(),
    paginationOpts: paginationOptsValidator, // for non-streaming messages
    streamArgs: vStreamArgs,
  },
  handler: async (ctx, args) => {
    await authorizeThreadAccess(ctx, threadId);
    const paginated = await listUIMessages(ctx, components.agent, args); // regular messages
    const streams = await syncStreams(ctx, components.agent, args);
    return { ...paginated, streams };
  },
});
```

Client: `useUIMessages(api...listMessages, { threadId }, { initialNumItems: 10, stream: true })`.

### Text smoothing: `SmoothText` / `useSmoothText`

```tsx
import { useSmoothText } from "@convex-dev/agent/react";
const [visibleText] = useSmoothText(message.text);
```

Adapts characters-per-second over time. Doesn't stream the first text received
unless `startStreaming: true` is passed — needed when mixing streaming and
non-streaming messages:

```tsx
const [visibleText] = useSmoothText(message.text, {
  startStreaming: message.status === "streaming",
});
```

Non-hook version: `<SmoothText text={message.text} />`.

## Consuming the stream yourself with the Agent

All the ways you can with the underlying AI SDK (iterate content,
`result.toDataStreamResponse()`, etc). Without saving deltas:

```ts
const result = await agent.streamText(ctx, { threadId }, { prompt });
for await (const textPart of result.textStream) {
  console.log(textPart);
}
```

To both iterate live AND save deltas: pass
`{ saveStreamDeltas: { returnImmediately: true } }` — returns immediately, can
iterate live or return the stream in an HTTP Response:

```ts
const result = await agent.streamText(
  ctx, { threadId }, { prompt },
  { saveStreamDeltas: { returnImmediately: true } },
);
return result.toUIMessageStreamResponse();
```

## Advanced: streaming deltas without an Agent

Use the AI SDK's own `streamText` directly with the `DeltaStreamer` class to
save deltas to the database. Requirements: a `threadId` from the Agent
component, and each stream saved with a distinct `order` for client-side
ordering.

```ts
import { components } from "./_generated/api";
import { type ActionCtx } from "./_generated/server";
import { DeltaStreamer, compressUIMessageChunks } from "@convex-dev/agent";
import { streamText } from "ai";
import { openai } from "@ai-sdk/openai";

async function stream(ctx: ActionCtx, threadId: string, order: number) {
  const streamer = new DeltaStreamer(
    components.agent, ctx,
    {
      throttleMs: 100,
      onAsyncAbort: async () => console.error("Aborted asynchronously"),
      compress: compressUIMessageChunks,
      abortSignal: undefined,
    },
    { threadId, format: "UIMessageChunk", order, stepOrder: 0, userId: undefined },
  );
  const response = streamText({
    model: openai.chat("gpt-4o-mini"),
    prompt: "Tell me a joke",
    abortSignal: streamer.abortController.signal,
    onError: (error) => { console.error(error); streamer.fail(errorToString(error.error)); },
  });
  void streamer.consumeStream(response.toUIMessageStream());
  return { response, streamId: await streamer.getStreamId() };
}
```

Fetch on client via `syncStreams` (optionally skip non-streaming messages) and
the `useStreamingUIMessages` hook.
