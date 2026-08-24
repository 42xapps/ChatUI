<!-- Source: https://docs.convex.dev/agents/agent-usage.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1 -->

# Agent Definition and Usage

Agents encapsulate models, prompting, tools, and other configuration. They use
threads to contain a series of messages. A thread can have multiple Agents
responding, or be used by a single Agent.

## Basic Agent definition

```ts
import { components } from "./_generated/api";
import { Agent } from "@convex-dev/agent";
import { openai } from "@ai-sdk/openai";

const agent = new Agent(components.agent, {
  name: "Basic Agent",
  languageModel: openai.chat("gpt-4o-mini"),
});
```

Everything except `name` can be overridden at the call site.

## Dynamic Agent definition

Define an Agent at runtime (e.g. per-request tools/model):

```ts
function createAuthorAgent(ctx: ActionCtx, bookId: Id<"books">, model: LanguageModel) {
  return new Agent(components.agent, {
    name: "Author",
    languageModel: model,
    tools: { getChapter: getChapterTool(ctx, bookId), /* ... */ },
    stopWhen: stepCountIs(10),
  });
}
```

## Generating text

Args mirror the AI SDK's `generateText`/`streamText`/etc (model optional —
defaults to the agent's). Message history is provided automatically as
context from the thread (see context.md).

### Basic (synchronous)

```ts
export const generateReplyToPrompt = action({
  args: { prompt: v.string(), threadId: v.string() },
  handler: async (ctx, { prompt, threadId }) => {
    // await authorizeThreadAccess(ctx, threadId);
    const result = await agent.generateText(ctx, { threadId }, { prompt });
    return result.text;
  },
});
```

Best practice: don't rely on the action's return value — query thread messages
via `useThreadMessages`/`useUIMessages` and receive the new message
automatically.

### RECOMMENDED: save prompt, then generate asynchronously

Benefits: optimistic UI updates on a transactional mutation; the message can
be saved in the same transaction as other writes; mutations are safely
retryable (idempotent) while actions can transiently fail.

```ts
// Step 1: save a user message, kick off async response.
export const sendMessage = mutation({
  args: { threadId: v.id("threads"), prompt: v.string() },
  handler: async (ctx, { threadId, prompt }) => {
    const { messageId } = await saveMessage(ctx, components.agent, { threadId, prompt });
    await ctx.scheduler.runAfter(0, internal.example.generateResponseAsync, {
      threadId, promptMessageId: messageId,
    });
  },
});

// Step 2: generate the response.
export const generateResponseAsync = internalAction({
  args: { threadId: v.string(), promptMessageId: v.string() },
  handler: async (ctx, { threadId, promptMessageId }) => {
    await agent.generateText(ctx, { threadId }, { promptMessageId });
  },
});
```

If `promptMessageId` is reused across multiple generations, prior responses
are automatically included as context (continuation) — relevant for workflows
with retries.

### Generating an object

```ts
const result = await thread.generateObject({
  prompt: "Generate a plan based on the conversation so far",
  schema: z.object({ ... }),
});
```

Object generation doesn't support tools directly — workaround: structure the
object as tool-call arguments, use a custom `stopWhen`, and `toolChoice: "required"`.

## Customizing the agent (full config shape)

```ts
const sharedDefaults = {
  languageModel: openai.chat("gpt-4o-mini"),
  embeddingModel: openai.embedding("text-embedding-3-small"), // needed for RAG/vector search
  contextOptions,   // see context.md
  storageOptions,   // see messages.md
  usageHandler: async (ctx, args) => { /* log/save usage — see usage-tracking.md */ },
  contextHandler: async (ctx, args) => [...customMessages, args.allMessages], // see context.md
  rawResponseHandler: async (ctx, args) => { /* log every request/response */ },
  callSettings: { maxRetries: 3, temperature: 1.0 },
} satisfies Config;

const supportAgent = new Agent(components.agent, {
  instructions: "You are a helpful assistant.",
  tools: {
    myConvexTool: createTool({ description: "...", inputSchema: z.object({...}), execute: async (ctx, input) => "..." }),
    myTool: tool({ description: "...", inputSchema: z.object({...}), execute: async () => {} }), // plain AI SDK tool
  },
  stopWhen: stepCountIs(5), // >1 needed for automatic multi-step tool-call loops
  ...sharedDefaults,
});
```
