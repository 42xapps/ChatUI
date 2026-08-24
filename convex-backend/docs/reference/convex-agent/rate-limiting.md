<!-- Source: https://docs.convex.dev/agents/rate-limiting.md | Pulled 2026-08-22 | @convex-dev/agent@0.7.1
     Depends on the separate @convex-dev/rate-limiter component (v0.3.2 latest on npm). -->

# Rate Limiting

Uses the separate Rate Limiter component (https://www.convex.dev/components/rate-limiter,
`npm install @convex-dev/rate-limiter`) to control message frequency and token
usage per user (and globally, to stay under provider API limits).

```ts
import { MINUTE, RateLimiter, SECOND } from "@convex-dev/rate-limiter";
import { components } from "./_generated/api";

export const rateLimiter = new RateLimiter(components.rateLimiter, {
  sendMessage: { kind: "fixed window", period: 5 * SECOND, rate: 1, capacity: 2 },
  globalSendMessage: { kind: "token bucket", period: MINUTE, rate: 1_000 },
  tokenUsagePerUser: { kind: "token bucket", period: MINUTE, rate: 2000, capacity: 10000 },
  globalTokenUsage: { kind: "token bucket", period: MINUTE, rate: 100_000 },
});
```

- `fixed window`: e.g. 1 msg/5s per user, `capacity` allows a small burst.
- `token bucket`: continuously accrues up to a cap; good for "burst then
  cooldown" (per-user token budgets) and global ceilings under the LLM
  provider's own rate limit.

## Step 1: pre-flight checks (in the mutation that starts generation)

```ts
await rateLimiter.limit(ctx, "sendMessage", { key: userId, throws: true });
await rateLimiter.limit(ctx, "globalSendMessage", { throws: true });

const count = await estimateTokens(ctx, args.threadId, args.question);
await rateLimiter.check(ctx, "tokenUsage", { key: userId, count: estimateTokens(args.question), throws: true });
await rateLimiter.check(ctx, "globalTokenUsage", { count, reserve: true, throws: true });
```

`limit` consumes immediately; `check` only checks (tokens are marked used once
actual usage is known, post-generation). Throws a catchable rate-limit error
if exceeded.

## Step 2: post-generation usage tracking (via the Agent's `usageHandler`)

```ts
const sharedConfig = {
  usageHandler: async (ctx, { usage, userId }) => {
    if (!userId) return;
    await rateLimiter.limit(ctx, "tokenUsage", { key: userId, count: usage.totalTokens, reserve: true });
  },
} satisfies Config;

const agent = new Agent(components.agent, { name, languageModel, ...sharedConfig });
```

`reserve: true` allows a temporary negative balance if actual usage exceeded
the pre-flight estimate — future requests are blocked until the "debt" is
repaid, which bounds average usage over time even though a single request can
exceed the nominal per-request limit.

## Client-side handling

```ts
export const { getRateLimit, getServerTime } = rateLimiter.hookAPI<DataModel>(
  "sendMessage", { key: (ctx) => getAuthUserId(ctx) },
);
```

```tsx
const { status } = useRateLimit(api.example.getRateLimit);
// status.ok === false → show "Try again after <Countdown ts={status.retryAt} />"
```

```ts
import { isRateLimitError } from "@convex-dev/rate-limiter";
await submitQuestion({ question, threadId }).catch((e) => {
  if (isRateLimitError(e)) { /* toast e.data.name / e.data.retryAfter */ }
});
```

## Token estimation helper

```ts
export async function estimateTokens(ctx: QueryCtx, threadId: string | undefined, question: string) {
  const promptTokens = question.length / 4; // ~4 chars/token
  const estimatedOutputTokens = promptTokens * 3 + 1;
  const latestMessages = await fetchContextMessages(ctx, components.agent, {
    threadId, searchText: question, contextOptions: { recentMessages: 2 },
  });
  const lastUsageMessage = latestMessages.reverse().find((m) => m.usage);
  const lastPromptTokens = lastUsageMessage?.usage?.totalTokens ?? 1;
  return lastPromptTokens + promptTokens + estimatedOutputTokens;
}
```
