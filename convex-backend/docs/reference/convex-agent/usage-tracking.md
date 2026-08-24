<!-- Source: https://docs.convex.dev/agents/usage-tracking.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1 -->

# Usage Tracking

A `usageHandler` (settable on the agent, per-thread, or per-message) reports
token usage after each generation:

```ts
const supportAgent = new Agent(components.agent, {
  usageHandler: async (ctx, args) => {
    const { userId, threadId, agentName, model, provider, usage, providerMetadata } = args;
    // log / save to your own table
  },
});
```

## Storing usage for billing

```ts
export const usageHandler: UsageHandler = async (ctx, args) => {
  if (!args.userId) return;
  await ctx.runMutation(internal.example.insertRawUsage, {
    userId: args.userId, agentName: args.agentName, model: args.model,
    provider: args.provider, usage: args.usage, providerMetadata: args.providerMetadata,
  });
};

export const insertRawUsage = internalMutation({
  args: { userId: v.string(), agentName: v.optional(v.string()), model: v.string(),
    provider: v.string(), usage: vUsage, providerMetadata: v.optional(vProviderMetadata) },
  handler: async (ctx, args) => {
    const billingPeriod = getBillingPeriod(Date.now());
    return await ctx.db.insert("rawUsage", { ...args, billingPeriod });
  },
});
```

Schema:

```ts
rawUsage: defineTable({
  userId: v.string(), agentName: v.optional(v.string()), model: v.string(), provider: v.string(),
  usage: vUsage, providerMetadata: v.optional(vProviderMetadata),
  billingPeriod: v.string(),
}).index("billingPeriod_userId", ["billingPeriod", "userId"]),

invoices: defineTable({
  userId: v.string(), billingPeriod: v.string(), amount: v.number(),
  status: v.union(v.literal("pending"), v.literal("paid"), v.literal("failed")),
}).index("billingPeriod_userId", ["billingPeriod", "userId"]),
```

## Generating invoices via cron

```ts
crons.monthly("generateInvoices", { day: 2, hourUTC: 0, minuteUTC: 0 }, internal.usage.generateInvoices, {});
```
