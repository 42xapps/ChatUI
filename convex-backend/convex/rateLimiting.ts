import { MINUTE, RateLimiter, SECOND } from "@convex-dev/rate-limiter";
import { components } from "./_generated/api";

export const rateLimiter = new RateLimiter(components.rateLimiter, {
  sendMessage: {
    kind: "fixed window",
    period: 5 * SECOND,
    rate: 1,
    capacity: 2,
  },
  globalSendMessage: {
    kind: "token bucket",
    period: MINUTE,
    rate: 60,
    capacity: 15,
  },
  tokenUsagePerUser: {
    kind: "token bucket",
    period: MINUTE,
    rate: 30_000,
    capacity: 60_000,
    maxReserved: 60_000,
  },
  globalTokenUsage: {
    kind: "token bucket",
    period: MINUTE,
    rate: 300_000,
    capacity: 600_000,
    maxReserved: 600_000,
  },
});
