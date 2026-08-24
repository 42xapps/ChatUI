<!-- Source: https://docs.convex.dev/agents/tools.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1 -->

# Tools

Lets an LLM call out to external services/functions: DB reads/writes, web
search, external APIs, human-in-the-loop confirmation.

## Defining tools

Provide at: Agent constructor (`new Agent(components.agent, { tools: {...} })`),
`createThread`/`continueThread`, thread functions (`thread.generateText({ tools })`),
or a bare call (`agent.generateText(ctx, {}, { tools })`). Later layers override
earlier ones: `args.tools ?? thread.tools ?? agent.options.tools`.

Automatic multi-step tool-call handling requires `stopWhen: stepCountIs(num)`
with `num > 1` (default agent config has this off — see agent-usage.md).
Tool call + result are stored as messages in the thread.

## Creating a tool with Convex context

```ts
export const ideaSearch = createTool({
  description: "Search for ideas in the database",
  args: z.object({ query: z.string().describe("The query to search for") }),
  handler: async (ctx, args, options): Promise<Array<Idea>> => {
    // ctx has agent, userId, threadId, messageId + ActionCtx (auth, storage, runMutation, runAction)
    return await ctx.runQuery(api.ideas.searchIdeas, { query: args.query });
  },
});
```

Or plain AI SDK `tool()` defined at runtime with closure-captured context:

```ts
async function createTool(ctx: ActionCtx, teamId: Id<"teams">) {
  return tool({
    description: "My tool",
    inputSchema: z.object({...}),
    execute: async (args, options) => await ctx.runQuery(internal.foo.bar, args),
  });
}
```

Recommended: use zod with `.describe(...)` on every field — becomes the tool's
description to the LLM.

### Adding custom context to tools

Default tool `ctx` (`ToolCtx`): `agent`, `userId`, `threadId`, `messageId`,
plus everything in `ActionCtx`. Note: in scheduled functions/workflows, the
auth user will be `null`. Extend with custom fields via
`agent.generateText({ ...ctx, orgId: "123" })`, typed via
`new Agent<{ orgId: string }>(...)`.

## Using an LLM/Agent as a tool

Simplest: each tool call works in an independent thread (or no thread at all);
output returned as the tool-call result — no need to manually save it to the
parent thread.

```ts
const agentTool = createTool({
  description: `Ask a question to agent ${agent.name}`,
  args: z.object({ message: z.string() }),
  handler: async (ctx, args, options): Promise<string> => {
    const { userId } = ctx;
    const { thread } = await agent.createThread(ctx, { userId });
    const result = await thread.generateText(
      { prompt: [...options.messages, { role: "user", content: args.message }] },
      { storageOptions: { saveMessages: "all" } },
    );
    return result.text;
  },
});
```
